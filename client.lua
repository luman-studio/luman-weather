local meanSeaLevel = 40.0

local currentWeather = nil
local currentWindDirection = 0.0
local snowOnGround = false
local syncEnabled = true

-- Raw (untranslated) state received from the server, kept so region/altitude
-- translation can be re-applied locally as the player moves around the map
local serverWeather = nil
local serverPermanentSnow = false
local serverWindDirection = nil
local serverWindSpeed = 0.0
local appliedWindDirection = nil
local appliedWindSpeed = nil

local initialized = false

-- When set, the next syncCheckResult is delivered to this callback (used by
-- the automated test suite) instead of being printed to chat
local pendingSyncCheck = nil

local forecastIsDisplayed = false
local adminUiIsOpen = false

local currentTimescale = Config.timescale

local baseNetworkTime = 0
local baseGameTime = 0
local timeIsFrozen = false

local debugMode = false
local debugStats = {
    lastWeatherSync = 0,
    lastTimeSync = 0,
    weatherSyncCount = 0,
    timeSyncCount = 0,
    lastWindSync = 0,
    windSyncCount = 0
}

RegisterNetEvent("weathersync:changeWeather")
RegisterNetEvent("weathersync:changeTime")
RegisterNetEvent("weathersync:changeTimescale")
RegisterNetEvent("weathersync:changeWind")
RegisterNetEvent("weathersync:toggleForecast")
RegisterNetEvent("weathersync:updateForecast")
RegisterNetEvent("weathersync:openAdminUi")
RegisterNetEvent("weathersync:updateAdminUi")
RegisterNetEvent("weathersync:toggleSync")
RegisterNetEvent("weathersync:setSyncEnabled")
RegisterNetEvent("weathersync:setMyTime")
RegisterNetEvent("weathersync:setMyWeather")
RegisterNetEvent("weathersync:syncBaseTime")
RegisterNetEvent("weathersync:syncCheckResult")

local function setWeather(weatherType, transitionTime)
    Citizen.InvokeNative(0x59174F1AFE095B5A, GetHashKey(weatherType), true, false, true, transitionTime, false) -- SET_WEATHER_TYPE
end

local function setSnowCoverageTypeDirect(coverageType)
    Citizen.InvokeNative(0xF02A9C330BBFC5C7, coverageType) -- _SET_SNOW_COVERAGE_TYPE
end

local function setTime(hour, minute, second, transitionTime, freeze)
    -- The clock is always frozen (last arg true): the tick loop below drives it,
    -- otherwise the game would advance time on its own between our updates
    Citizen.InvokeNative(0x669E223E64B1903C, hour, minute, second, transitionTime, true) -- _NETWORK_CLOCK_TIME_OVERRIDE
end

local function isInSnowyRegion(x, y, z)
    return (x <= -700.0 and y >= 1090.0) or (x <= -500.0 and y >= 2388.0)
end

local function isInDesertRegion(x, y, z)
    return x <= -2050 and y <= -1750
end

local function isInNorthernRegion(x, y, z)
    return y >= 1050
end

local function isInGuarma(x, y, z)
    return x >= 0 and y <= -4096
end

local function translateWeatherForRegion(weather, x, y, z)
    local temp = GetTemperatureAtCoords(x, y, z)

    if weather == "rain" then
        if isInSnowyRegion(x, y, z) then
            return "snow"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "snow"
        elseif isInDesertRegion(x, y, z) then
            return "thunder"
        end
    elseif weather == "thunderstorm" then
        if isInSnowyRegion(x, y, z) then
            return "blizzard"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "blizzard"
        elseif isInDesertRegion(x, y, z) then
            return "rain"
        end
    elseif weather == "hurricane" then
        if isInSnowyRegion(x, y, z) then
            return "whiteout"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "whiteout"
        elseif isInDesertRegion(x, y, z) then
            return "sandstorm"
        end
    elseif weather == "drizzle" then
        if isInSnowyRegion(x, y, z) then
            return "snowlight"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "snowlight"
        elseif isInDesertRegion(x, y, z) then
            return "sunny"
        end
    elseif weather == "shower" then
        if isInSnowyRegion(x, y, z) then
            return "groundblizzard"
        elseif isInNorthernRegion(x, y, z) and temp < 0.0 then
            return "groundblizzard"
        elseif isInDesertRegion(x, y, z) then
            return "sunny"
        end
    elseif weather == "fog" then
        if isInSnowyRegion(x, y, z) then
            return "snowlight"
        end
    elseif weather == "misty" then
        if isInSnowyRegion(x, y, z) then
            return "snowlight"
        end
    elseif weather == "snow" then
        if isInGuarma(x, y, z) then
            return "sunny"
        end
    elseif weather == "snowlight" then
        if isInGuarma(x, y, z) then
            return "sunny"
        end
    elseif weather == "blizzard" then
        if isInGuarma(x, y, z) then
            return "sunny"
        end
    end

    return weather
end

local function isSnowyWeather(weather)
    return weather == "blizzard" or weather == "groundblizzard" or weather == "snow" or weather == "whiteout" or weather == "snowlight"
end

local function translateWindForAltitude(direction, speed)
    local ped = PlayerPedId()
    local altitudeSea = GetEntityCoords(ped).z - meanSeaLevel
    local altitudeTerrain = GetEntityHeightAboveGround(ped)

    local directionMultiplier = math.floor(altitudeSea / Config.windShearInterval)
    local speedMultiplier = math.floor(altitudeTerrain / Config.windShearInterval)

    direction = (direction + directionMultiplier * Config.windShearDirection) % 360
    speed = speed + speedMultiplier * Config.windShearSpeed

    return direction, speed
end

-- Apply the current server weather locally, translating it for the player's
-- region. Safe to call repeatedly: only invokes natives when something changes.
local function applyServerWeather(transitionTime)
    if not serverWeather then
        return
    end

    local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
    local translatedWeather = translateWeatherForRegion(serverWeather, x, y, z)

    if not currentWeather then
        transitionTime = 1.0
        setSnowCoverageTypeDirect(0)
        snowOnGround = false
    end

    local inSnowyRegion = isInSnowyRegion(x, y, z)

    if serverPermanentSnow or (Config.dynamicSnow and (inSnowyRegion or isSnowyWeather(translatedWeather))) then
        if not snowOnGround then
            snowOnGround = true
            setSnowCoverageTypeDirect(3)
        end
    else
        if snowOnGround then
            snowOnGround = false
            setSnowCoverageTypeDirect(0)
        end
    end

    if translatedWeather ~= currentWeather then
        debugLog(string.format("Applying weather: %s -> %s (server: %s, transition: %.1fs)", tostring(currentWeather), translatedWeather, serverWeather, transitionTime))
        setWeather(translatedWeather, transitionTime)
        currentWeather = translatedWeather
    end
end

-- Apply the current server wind locally, translating it for the player's
-- altitude. Safe to call repeatedly: only invokes natives when something changes.
local function applyServerWind()
    if not serverWindDirection then
        return
    end

    local direction, speed = translateWindForAltitude(serverWindDirection, serverWindSpeed)

    if direction ~= appliedWindDirection or speed ~= appliedWindSpeed then
        debugLog(string.format("Applying wind: %.1f° speed %.1f (server: %.1f° speed %.1f)", direction, speed, serverWindDirection, serverWindSpeed))
        SetWindDirection(direction)
        SetWindSpeed(speed)
        appliedWindDirection = direction
        appliedWindSpeed = speed
        currentWindDirection = direction
    end
end

-- Game time as computed by the local clock (what the tick loop applies)
local function computeLocalTime()
    local scale = currentTimescale == 0 and 1 or currentTimescale

    if not timeIsFrozen and baseNetworkTime > 0 and scale > 0 then
        return math.floor(baseGameTime + (GetNetworkTime() - baseNetworkTime) / 1000 * scale) % 604800
    end

    return baseGameTime
end

-- Absolute difference between two values on a circular scale (day/week time)
local function wrapDiff(a, b, period)
    local diff = math.abs(a - b) % period

    if diff > period / 2 then
        diff = period - diff
    end

    return diff
end

local function updateForecast(forecast)
    local h24 = ShouldUse_24HourClock()

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local x, y, z = table.unpack(pos)

    for i = 1, #forecast do
        if h24 then
            forecast[i].time = string.format(
                "%.2d:%.2d",
                forecast[i].hour,
                forecast[i].minute)
        else
            local h = forecast[i].hour % 12
            forecast[i].time = string.format(
                "%d:%.2d %s",
                h == 0 and 12 or h,
                forecast[i].minute,
                forecast[i].hour > 12 and "PM" or "AM")
        end

        forecast[i].weather = translateWeatherForRegion(forecast[i].weather, x, y, z)
        forecast[i].wind = GetCardinalDirection(forecast[i].wind)
    end

    -- Get local temperature
    local metric = ShouldUseMetricTemperature()
    local temperature
    local temperatureUnit
    local windSpeed
    local windSpeedUnit
    local tempStr

    if metric then
        temperature = math.floor(GetTemperatureAtCoords(x, y, z))
        temperatureUnit = "C"
    else
        temperature = math.floor(GetTemperatureAtCoords(x, y, z) * 9/5 + 32)
        temperatureUnit = "F"
    end

    tempStr = string.format("%d °%s", temperature, temperatureUnit)

    if metric then
        windSpeed = math.floor(GetWindSpeed() * 3.6)
        windSpeedUnit = "kph"
    else
        windSpeed = math.floor(GetWindSpeed() * 3.6 * 0.621371)
        windSpeedUnit = "mph"
    end

    local windStr = string.format("🌬️ %d %s %s", windSpeed, windSpeedUnit, GetCardinalDirection(currentWindDirection))

    local altitudeSea = string.format("%d", math.floor(pos.z - meanSeaLevel))
    local altitudeTerrain = string.format("%d", math.floor(GetEntityHeightAboveGround(ped)))

    SendNUIMessage({
        action = "updateForecast",
        forecast = json.encode(forecast),
        temperature = tempStr,
        wind = windStr,
        syncEnabled = syncEnabled,
        altitudeSea = altitudeSea,
        altitudeTerrain = altitudeTerrain
    })
end

local function toggleSync()
    currentWeather = nil

    syncEnabled = not syncEnabled

    if syncEnabled then
        -- Re-request the full state from the server: local overrides may have
        -- desynced us, and no periodic sync exists to catch us up
        TriggerServerEvent("weathersync:init")
    end

    if Config.Notify then
        TriggerEvent("chat:addMessage", {
            color = {255, 255, 128},
            args = {"Weather Sync", syncEnabled and "on" or "off"}
        })
    end
end

local function setSyncEnabled(toggle)
    if syncEnabled ~= toggle then
        toggleSync()
    end
end

local function setMyWeather(weather, transition, permanentSnow)
    if syncEnabled then
        toggleSync()
    end

    if transition <= 0.0 then
        transition = 0.1
    end

    setWeather(weather, transition)

    if permanentSnow then
        setSnowCoverageTypeDirect(3)
        snowOnGround = true
    else
        setSnowCoverageTypeDirect(0)
        snowOnGround = false
    end
end

local function setMyTime(h, m, s, t)
    if syncEnabled then
        toggleSync()
    end

    setTime(h, m, s, t, true)
end

exports("toggleSync", toggleSync)
exports("setSyncEnabled", setSyncEnabled)
exports("setMyWeather", setMyWeather)
exports("setMyTime", setMyTime)

exports("isSnowOnGround", function()
    return snowOnGround or IsNextWeatherType("XMAS")
end)

function debugLog(message)
    if debugMode then
        print(string.format("^3[WeatherSync Debug]^7 %s", message))
    end
end

AddEventHandler("weathersync:changeWeather", function(weather, transitionTime, permanentSnow)
    if not syncEnabled then
        return
    end

    debugStats.weatherSyncCount = debugStats.weatherSyncCount + 1
    debugStats.lastWeatherSync = GetGameTimer()
    debugLog(string.format("Weather change: %s (transition: %.1fs, snow: %s)", weather, transitionTime, tostring(permanentSnow)))

    serverWeather = weather
    serverPermanentSnow = permanentSnow

    applyServerWeather(transitionTime)
end)

AddEventHandler("weathersync:changeTime", function(day, hour, minute, second, transitionTime, freezeTime)
    if not syncEnabled then
        return
    end

    debugStats.timeSyncCount = debugStats.timeSyncCount + 1
    debugStats.lastTimeSync = GetGameTimer()
    debugLog(string.format("Time change: %s %.2d:%.2d:%.2d (transition: %sms, frozen: %s)", GetDayOfWeek(day), hour, minute, second, tostring(transitionTime), tostring(freezeTime)))

    timeIsFrozen = freezeTime

    -- Update base time to prevent the tick loop from overriding this change
    baseGameTime = DHMSToTime(day, hour, minute, second)
    baseNetworkTime = GetNetworkTime()

    setTime(hour, minute, second, transitionTime, freezeTime)
end)

AddEventHandler("weathersync:syncBaseTime", function(gameTime, timescale, frozen)
    if not syncEnabled then
        return
    end

    -- The server sends its *current* game time; anchor our clock to it
    baseNetworkTime = GetNetworkTime()
    baseGameTime = gameTime
    currentTimescale = timescale
    timeIsFrozen = frozen

    local d, hour, minute, second = TimeToDHMS(baseGameTime)
    setTime(hour, minute, second, 0, frozen)
end)

-- Compares the authoritative server state against everything computed and
-- applied locally. All checks should report OK on a healthy server.
AddEventHandler("weathersync:syncCheckResult", function(svTime, svWeather, svWindDirection, svWindSpeed, svTimescale, svFrozen)
    if pendingSyncCheck then
        local deliver = pendingSyncCheck
        pendingSyncCheck = nil
        deliver({
            time = svTime,
            weather = svWeather,
            windDirection = svWindDirection,
            windSpeed = svWindSpeed,
            timescale = svTimescale,
            frozen = svFrozen
        })
        return
    end

    local ok = {50, 255, 50}
    local fail = {255, 80, 80}
    local white = {255, 255, 255}

    local function report(label, passed, detail)
        local status = passed and "OK" or "FAIL"
        TriggerEvent("chat:addMessage", {color = passed and ok or fail, args = {label, status .. " — " .. detail}})
        print(string.format("[synccheck] %s: %s — %s", label, status, detail))
    end

    TriggerEvent("chat:addMessage", {color = {100, 200, 255}, args = {"=== Sync Check ==="}})

    if not syncEnabled then
        TriggerEvent("chat:addMessage", {color = {255, 255, 0}, args = {"WARNING", "sync is disabled (/weathersync) — all checks below are expected to fail"}})
    end

    if not initialized then
        TriggerEvent("chat:addMessage", {color = {255, 80, 80}, args = {"WARNING", "client init() never ran — framework login event did not fire"}})
        print("[synccheck] WARNING: client init() never ran")
    elseif baseNetworkTime == 0 then
        TriggerEvent("chat:addMessage", {color = {255, 80, 80}, args = {"WARNING", "init() ran but no syncBaseTime received from the server yet"}})
        print("[synccheck] WARNING: no syncBaseTime received from the server")
    end

    -- 1. Locally computed game time vs authoritative server time
    local scale = currentTimescale == 0 and 1 or currentTimescale
    local localTime = computeLocalTime()
    local diff = wrapDiff(localTime, svTime, 604800)

    -- Client clock ticks once a second and events have latency, so allow up
    -- to ~2 ticks of drift
    local tolerance = scale * 2 + 5

    report("TIME", diff <= tolerance,
        string.format("server %s, client %s, diff %ds (tolerance %ds)", FormatTime(svTime), FormatTime(localTime), diff, tolerance))

    -- 2. The actual in-game clock vs what we computed (checks the override applied)
    local clockTime = GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()
    local clockDiff = wrapDiff(clockTime, localTime % 86400, 86400)

    report("GAME CLOCK", clockDiff <= tolerance,
        string.format("in-game %.2d:%.2d:%.2d, computed %s, diff %ds", GetClockHours(), GetClockMinutes(), GetClockSeconds(), FormatTime(localTime), clockDiff))

    -- 3. Last weather received from the server vs the server's actual state
    report("WEATHER EVENT", serverWeather == svWeather,
        string.format("server %s, received %s", svWeather, tostring(serverWeather)))

    -- 4. Weather actually applied vs what should be applied in this region
    local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
    local expectedWeather = translateWeatherForRegion(svWeather, x, y, z)

    report("WEATHER APPLIED", currentWeather == expectedWeather,
        string.format("expected %s, applied %s (region monitor updates every 5s)", expectedWeather, tostring(currentWeather)))

    -- 5. Wind, timescale, freeze flag
    report("WIND", serverWindDirection == svWindDirection and serverWindSpeed == svWindSpeed,
        string.format("server %.1f°/%.1f, received %s/%.1f", svWindDirection, svWindSpeed, serverWindDirection and string.format("%.1f°", serverWindDirection) or "none", serverWindSpeed))

    report("TIMESCALE", currentTimescale == svTimescale,
        string.format("server %.2f, client %.2f", svTimescale, currentTimescale))

    report("TIME FROZEN", timeIsFrozen == svFrozen,
        string.format("server %s, client %s", tostring(svFrozen), tostring(timeIsFrozen)))
end)

RegisterCommand("synccheck", function(source, args, raw)
    TriggerServerEvent("weathersync:requestSyncCheck")
end, false)

AddEventHandler("weathersync:changeTimescale", function(scale)
    if not syncEnabled then
        return
    end

    -- Rebase to the current computed game time under the old timescale,
    -- otherwise the clock would jump back to the previous anchor point
    if not timeIsFrozen and baseNetworkTime > 0 then
        local oldScale = currentTimescale == 0 and 1 or currentTimescale
        local elapsed = (GetNetworkTime() - baseNetworkTime) / 1000
        baseGameTime = math.floor(baseGameTime + elapsed * oldScale) % 604800
    end

    baseNetworkTime = GetNetworkTime()
    currentTimescale = scale
end)

AddEventHandler("weathersync:changeWind", function(direction, speed)
    debugStats.windSyncCount = debugStats.windSyncCount + 1
    debugStats.lastWindSync = GetGameTimer()
    debugLog(string.format("Wind change: %.1f°, speed: %.1f", direction, speed))

    serverWindDirection = direction
    serverWindSpeed = speed

    applyServerWind()
end)

AddEventHandler("weathersync:toggleForecast", function()
    forecastIsDisplayed = not forecastIsDisplayed

    CreateThread(function()
        while forecastIsDisplayed do
            TriggerServerEvent("weathersync:requestUpdatedForecast")
            Wait(1000)
        end
    end)

    SendNUIMessage({
        action = "toggleForecast"
    })
end)

AddEventHandler("weathersync:updateForecast", updateForecast)

AddEventHandler("weathersync:openAdminUi", function(weather, time, timescale, windDirection, windSpeed, syncDelay)
    adminUiIsOpen = true

    local d, h, m, s = TimeToDHMS(time)

    SetNuiFocus(true, true)

    SendNUIMessage({
        action = "openAdminUi",
        weatherTypes = json.encode(Config.weatherTypes),
        weather = weather,
        day = d,
        hour = h,
        min = m,
        sec = s,
        timescale = timescale,
        windSpeed = windSpeed,
        windDirection = windDirection,
        syncDelay = syncDelay
    })

    CreateThread(function()
        while adminUiIsOpen do
            TriggerServerEvent("weathersync:requestUpdatedAdminUi")
            Wait(1000)
        end
    end)
end)

AddEventHandler("weathersync:updateAdminUi", function(weather, time, timescale, windDirection, windSpeed, syncDelay)
    local d, h, m, s = TimeToDHMS(time)

    SendNUIMessage({
        action = "updateAdminUi",
        weatherTypes = json.encode(Config.weatherTypes),
        weather = weather,
        day = d,
        hour = h,
        min = m,
        sec = s,
        timescale = timescale,
        windSpeed = windSpeed,
        windDirection = windDirection,
        syncDelay = syncDelay
    })
end)

RegisterNUICallback("getGameName", function(data, cb)
    cb({gameName = "rdr3"})
end)

RegisterNUICallback("setTime", function(data, cb)
    TriggerServerEvent("weathersync:setTime", data.day, data.hour, data.min, data.sec, data.transition, data.freeze)
    cb({})
end)

RegisterNUICallback("setTimescale", function(data, cb)
    TriggerServerEvent("weathersync:setTimescale", data.timescale * 1.0)
    cb({})
end)

RegisterNUICallback("setWeather", function(data, cb)
    TriggerServerEvent("weathersync:setWeather", data.weather, data.transition * 1.0, data.freeze, data.permanentSnow)
    cb({})
end)

RegisterNUICallback("setWind", function(data, cb)
    TriggerServerEvent("weathersync:setWind", data.windDirection * 1.0, data.windSpeed * 1.0, data.freeze)
    cb({})
end)

RegisterNUICallback("setSyncDelay", function(data, cb)
    TriggerServerEvent("weathersync:setSyncDelay", data.syncDelay)
    cb({})
end)

RegisterNUICallback("closeAdminUi", function(data, cb)
    SetNuiFocus(false, false)
    adminUiIsOpen = false
    cb({})
end)

AddEventHandler("weathersync:setSyncEnabled", setSyncEnabled)
AddEventHandler("weathersync:toggleSync", toggleSync)
AddEventHandler("weathersync:setMyWeather", setMyWeather)
AddEventHandler("weathersync:setMyTime", setMyTime)

function init()
    if initialized then
        return
    end
    initialized = true

    SetNuiFocus(false, false)

    TriggerEvent("chat:addSuggestion", "/forecast", "Toggle display of weather forecast", {})

    TriggerEvent("chat:addSuggestion", "/syncdelay", "Change how often time/weather are synced.", {
        {name = "delay", help = "The time in milliseconds between syncs"}
    })

    TriggerEvent("chat:addSuggestion", "/time", "Change the time", {
        {name = "day", help = "0 = Sun, 1 = Mon, 2 = Tue, 3 = Wed, 4 = Thu, 5 = Fri, 6 = Sat"},
        {name = "hour", help = "0-23"},
        {name = "minute", help = "0-59"},
        {name = "second", help = "0-59"},
        {name = "transition", help = "Transition time in milliseconds"},
        {name = "freeze", help = "0 = don\"t freeze time, 1 = freeze time"}
    })

    TriggerEvent("chat:addSuggestion", "/timescale", "Change the rate at which time passes", {
        {name = "scale", help = "Number of in-game seconds per real-time second"}
    })

    TriggerEvent("chat:addSuggestion", "/weather", "Change the weather", {
        {name = "type", help = "The type of weather to change to"},
        {name = "transition", help = "Transition time in seconds"},
        {name = "freeze", help = "0 = don\"t freeze weather, 1 = freeze weather"},
        {name = "snow", help = "0 = temporary snow coverage, 1 = permanent snow coverage"}
    })

    TriggerEvent("chat:addSuggestion", "/weatherui", "Open weather admin UI", {})

    TriggerEvent("chat:addSuggestion", "/wind", "Change wind direction and speed", {
        {name = "direction", help = "Direction of the wind in degrees"},
        {name = "speed", help = "Minimum wind speed"},
        {name = "freeze", help = "0 don\"t freeze wind, 1 = freeze wind"}
    })

    TriggerEvent("chat:addSuggestion", "/weathersync", "Enable/disable weather and time sync", {})

    TriggerEvent("chat:addSuggestion", "/mytime", "Change local time (if weathersync is off)", {
        {name = "hour", help = "0-23"},
        {name = "minute", help = "0-59"},
        {name = "second", help = "0-59"},
        {name = "transition", help = "Transition time in milliseconds"}
    })

    TriggerEvent("chat:addSuggestion", "/myweather", "Change local weather (if weathersync is off)", {
        {name = "type", help = "The type of weather to change to"},
        {name = "transition", help = "Transition time in seconds"},
        {name = "snow", help = "0 = no snow on ground, 1 = snow on ground"}
    })

    TriggerEvent("chat:addSuggestion", "/weatherdebug", "Toggle weather sync debug mode", {})

    TriggerEvent("chat:addSuggestion", "/synccheck", "Compare local weather/time state with the server", {})

    if Config.enableTests then
        TriggerEvent("chat:addSuggestion", "/weathertest", "Run the weather sync test suite", {
            {name = "full", help = "add 'full' to also test set/restore of time/weather/wind (admin only)"}
        })
    end

    TriggerEvent("chat:addSuggestion", "/weatherstatus", "Display current weather/time sync status", {})

    TriggerEvent("chat:addSuggestion", "/testweather", "Test weather transition", {
        {name = "weather", help = "Weather type to test"}
    })

    TriggerServerEvent("weathersync:init")

    -- Local clock: advances game time from the shared network clock without
    -- any server communication. Timescale 0 means real-time (1:1).
    CreateThread(function()
        while true do
            if syncEnabled and not timeIsFrozen and baseNetworkTime > 0 then
                local scale = currentTimescale == 0 and 1 or currentTimescale

                if scale > 0 then
                    local networkTimeDiff = (GetNetworkTime() - baseNetworkTime) / 1000
                    local calculatedGameTime = baseGameTime + (networkTimeDiff * scale)
                    local d, h, m, s = TimeToDHMS(math.floor(calculatedGameTime) % 604800)

                    setTime(h, m, s, 0, false)
                end
            end
            Wait(1000)
        end
    end)

    -- Region/altitude monitor: re-applies the last known server weather and
    -- wind as the player moves, entirely locally (no network traffic)
    CreateThread(function()
        while true do
            Wait(5000)
            if syncEnabled then
                applyServerWeather(10.0)
                applyServerWind()
            end
        end
    end)
end

-- Framework-independent: initialize as soon as the network session is up
CreateThread(function()
    while not NetworkIsSessionStarted() do
        Wait(500)
    end

    init()
end)

RegisterCommand("weatherdebug", function(source, args, raw)
    debugMode = not debugMode
    TriggerEvent("chat:addMessage", {
        color = {255, 255, 128},
        args = {"WeatherSync Debug", debugMode and "Enabled" or "Disabled"}
    })
end, false)

RegisterCommand("weatherstatus", function(source, args, raw)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local x, y, z = table.unpack(pos)

    local gameTime = baseGameTime
    if not timeIsFrozen and baseNetworkTime > 0 then
        local scale = currentTimescale == 0 and 1 or currentTimescale
        gameTime = math.floor(baseGameTime + (GetNetworkTime() - baseNetworkTime) / 1000 * scale) % 604800
    end

    local d, h, m, s = TimeToDHMS(gameTime)
    local timeStr = string.format("%s %.2d:%.2d:%.2d", GetDayOfWeek(d), h, m, s)

    local metric = ShouldUseMetricTemperature()
    local temp = metric and math.floor(GetTemperatureAtCoords(x, y, z)) or math.floor(GetTemperatureAtCoords(x, y, z) * 9/5 + 32)
    local tempUnit = metric and "C" or "F"

    local windSpeed = metric and math.floor(GetWindSpeed() * 3.6) or math.floor(GetWindSpeed() * 3.6 * 0.621371)
    local windUnit = metric and "kph" or "mph"

    local altitudeSea = math.floor(pos.z - meanSeaLevel)
    local altitudeTerrain = math.floor(GetEntityHeightAboveGround(ped))

    local translatedWeather = translateWeatherForRegion(currentWeather or "unknown", x, y, z)

    TriggerEvent("chat:addMessage", {color = {100, 200, 255}, args = {"=== Weather Sync Status ==="}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Sync Enabled", tostring(syncEnabled)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Weather", translatedWeather or "unknown"}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Time", timeStr}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Timescale", string.format("%.2f", currentTimescale)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Time Frozen", tostring(timeIsFrozen)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Temperature", string.format("%d °%s", temp, tempUnit)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Wind", string.format("%d %s %s", windSpeed, windUnit, GetCardinalDirection(currentWindDirection))}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Altitude (Sea)", string.format("%dm", altitudeSea)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Altitude (Ground)", string.format("%dm", altitudeTerrain)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Snow on Ground", tostring(snowOnGround)}})
    TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Position", string.format("%.1f, %.1f, %.1f", x, y, z)}})

    if isInSnowyRegion(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Snowy"}})
    elseif isInDesertRegion(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Desert"}})
    elseif isInNorthernRegion(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Northern"}})
    elseif isInGuarma(x, y, z) then
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Guarma"}})
    else
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Region", "Normal"}})
    end

    if debugMode then
        TriggerEvent("chat:addMessage", {color = {100, 200, 255}, args = {"=== Debug Stats ==="}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Weather Syncs", tostring(debugStats.weatherSyncCount)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Time Syncs", tostring(debugStats.timeSyncCount)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Wind Syncs", tostring(debugStats.windSyncCount)}})

        local timeSinceWeatherSync = (GetGameTimer() - debugStats.lastWeatherSync) / 1000
        local timeSinceTimeSync = (GetGameTimer() - debugStats.lastTimeSync) / 1000
        local timeSinceWindSync = (GetGameTimer() - debugStats.lastWindSync) / 1000

        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Last Weather Sync", string.format("%.1fs ago", timeSinceWeatherSync)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Last Time Sync", string.format("%.1fs ago", timeSinceTimeSync)}})
        TriggerEvent("chat:addMessage", {color = {255, 255, 255}, args = {"Last Wind Sync", string.format("%.1fs ago", timeSinceWindSync)}})
    end
end, false)

-- ============================================================================
-- AUTOMATED TEST SUITE (/weathertest [full])
-- Read-only tests always run. "full" adds mutating tests that change and then
-- restore server time/weather/timescale/wind (requires the same ace
-- permissions as the corresponding admin commands).
-- Can also be launched remotely from the server console: weathertest client <id>
-- ============================================================================

local testRunning = false

local function fetchServerState(timeout)
    local p = promise.new()
    local done = false

    pendingSyncCheck = function(state)
        if not done then
            done = true
            p:resolve(state)
        end
    end

    TriggerServerEvent("weathersync:requestSyncCheck")

    SetTimeout(timeout or 3000, function()
        if not done then
            done = true
            pendingSyncCheck = nil
            p:resolve(nil)
        end
    end)

    return Citizen.Await(p)
end

local function pollUntil(timeoutMs, check)
    local deadline = GetGameTimer() + timeoutMs

    while GetGameTimer() < deadline do
        if check() then
            return true
        end
        Wait(100)
    end

    return check()
end

local function gameClockTime()
    return GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()
end

local function runTestSuite(full, echoToServer)
    local passed, failed, skipped = 0, 0, 0

    local function say(color, label, text)
        TriggerEvent("chat:addMessage", {color = color, args = {label, text}})
        print(string.format("[weathertest] %s: %s", label, text))

        if echoToServer then
            TriggerServerEvent("weathersync:clientTestResult", string.format("%s: %s", label, text))
        end
    end

    local function report(name, ok, detail)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
        end

        say(ok and {50, 255, 50} or {255, 80, 80}, name, (ok and "OK" or "FAIL") .. (detail and (" — " .. detail) or ""))
    end

    local function skip(name, reason)
        skipped = skipped + 1
        say({255, 255, 0}, name, "SKIP — " .. reason)
    end

    say({100, 200, 255}, "weathertest", full and "starting (full suite, ~40s)" or "starting (read-only suite, ~15s)")

    -- T1: time conversion roundtrip
    do
        local ok, detail = true, nil

        for _, t in ipairs({0, 1, 59, 3600, 86399, 86400, 186300, 604799}) do
            local d, h, m, s = TimeToDHMS(t)
            if DHMSToTime(d, h, m, s) ~= t then
                ok, detail = false, string.format("roundtrip failed for %d", t)
                break
            end
        end

        report("T1 time conversion", ok, detail)
    end

    -- T2: cardinal directions
    do
        local cases = {{0, "N"}, {45, "NE"}, {90, "E"}, {180, "S"}, {270, "W"}, {359, "N"}}
        local ok, detail = true, nil

        for _, c in ipairs(cases) do
            if GetCardinalDirection(c[1]) ~= c[2] then
                ok, detail = false, string.format("%d° -> %s, expected %s", c[1], GetCardinalDirection(c[1]), c[2])
                break
            end
        end

        report("T2 cardinal directions", ok, detail)
    end

    -- T3: region weather translation with fixed coordinates
    do
        local cases = {
            {"rain", -1500.0, 2500.0, "snow", "snowy region"},
            {"thunderstorm", -1500.0, 2500.0, "blizzard", "snowy region"},
            {"rain", -2500.0, -2000.0, "thunder", "desert"},
            {"drizzle", -2500.0, -2000.0, "sunny", "desert"},
            {"snow", 1000.0, -5000.0, "sunny", "Guarma"},
            {"sunny", -1500.0, 2500.0, "sunny", "snowy region, unchanged"}
        }
        local ok, detail = true, nil

        for _, c in ipairs(cases) do
            local got = translateWeatherForRegion(c[1], c[2], c[3], 0.0)
            if got ~= c[4] then
                ok, detail = false, string.format("%s in %s -> %s, expected %s", c[1], c[5], got, c[4])
                break
            end
        end

        report("T3 region translation", ok, detail)
    end

    -- T4: initialization completed and server state received
    report("T4 init", initialized and baseNetworkTime > 0 and serverWeather ~= nil,
        string.format("initialized=%s, timeSynced=%s, weather=%s",
            tostring(initialized), tostring(baseNetworkTime > 0), tostring(serverWeather)))

    -- T5: client state vs authoritative server state
    local state = fetchServerState()

    if not state then
        report("T5 server sync", false, "no response from server within 3s")
    else
        local scale = state.timescale == 0 and 1 or state.timescale
        local tolerance = scale * 2 + 5

        local timeDiff = wrapDiff(computeLocalTime(), state.time, 604800)
        report("T5a time sync", timeDiff <= tolerance, string.format("diff %ds (tolerance %ds)", timeDiff, tolerance))

        local clockDiff = wrapDiff(gameClockTime(), computeLocalTime() % 86400, 86400)
        report("T5b game clock", clockDiff <= tolerance, string.format("diff %ds", clockDiff))

        report("T5c weather received", serverWeather == state.weather,
            string.format("server %s, client %s", state.weather, tostring(serverWeather)))

        local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
        local expected = translateWeatherForRegion(state.weather, x, y, z)
        report("T5d weather applied", currentWeather == expected,
            string.format("expected %s, applied %s", expected, tostring(currentWeather)))

        report("T5e wind", serverWindDirection == state.windDirection and serverWindSpeed == state.windSpeed,
            string.format("server %.1f°/%.1f, client %s/%.1f", state.windDirection, state.windSpeed,
                serverWindDirection and string.format("%.1f°", serverWindDirection) or "none", serverWindSpeed))

        report("T5f timescale", currentTimescale == state.timescale,
            string.format("server %.2f, client %.2f", state.timescale, currentTimescale))

        report("T5g frozen flag", timeIsFrozen == state.frozen,
            string.format("server %s, client %s", tostring(state.frozen), tostring(timeIsFrozen)))
    end

    -- T6: clock advances at the expected rate
    if timeIsFrozen then
        skip("T6 clock advance", "time is frozen")
    else
        local scale = currentTimescale == 0 and 1 or currentTimescale
        local t1 = computeLocalTime()
        local c1 = gameClockTime()

        say({255, 255, 255}, "T6", "measuring clock advance over 4s...")
        Wait(4000)

        local computedAdvance = (computeLocalTime() - t1) % 604800
        local clockAdvance = (gameClockTime() - c1) % 86400
        local expected = 4 * scale
        local tol = 2 * scale + 3

        report("T6a computed time advance", math.abs(computedAdvance - expected) <= tol,
            string.format("%ds over 4s (expected ~%ds)", computedAdvance, expected))
        report("T6b in-game clock advance", math.abs(clockAdvance - expected) <= tol,
            string.format("%ds over 4s (expected ~%ds)", clockAdvance, expected))
    end

    -- T7: no sync traffic while idle
    do
        local w1, t1 = debugStats.weatherSyncCount, debugStats.timeSyncCount

        say({255, 255, 255}, "T7", "monitoring network traffic for 5s...")
        Wait(5000)

        local dw = debugStats.weatherSyncCount - w1
        local dt = debugStats.timeSyncCount - t1

        report("T7 idle traffic", dw == 0 and dt == 0,
            (dw == 0 and dt == 0) and "no sync events received"
            or string.format("%d weather / %d time events (could be a scheduled weather change — rerun to confirm)", dw, dt))
    end

    -- Mutating tests
    if not full then
        say({255, 255, 255}, "weathertest", "read-only tests done; run '/weathertest full' to also test set/restore of time, weather, timescale and wind (requires admin permissions)")
    else
        local st = fetchServerState()

        if not st then
            skip("T8-T11", "no response from server")
        else
            -- T8: weather set/restore
            local origSnow = serverPermanentSnow
            local testWeather = st.weather ~= "rain" and "rain" or "clouds"

            TriggerServerEvent("weathersync:setWeather", testWeather, 0.1, false, false)
            local canMutate = pollUntil(3000, function() return serverWeather == testWeather end)

            if not canMutate then
                skip("T8-T11", "no weather event within 3s — missing admin permissions (command.weather etc.)?")
            else
                local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
                report("T8 weather set", currentWeather == translateWeatherForRegion(testWeather, x, y, z),
                    string.format("set %s, applied %s", testWeather, tostring(currentWeather)))

                TriggerServerEvent("weathersync:setWeather", st.weather, 2.0, false, origSnow)
                pollUntil(3000, function() return serverWeather == st.weather end)

                -- T9: time set/restore
                local before = fetchServerState()

                if before then
                    local target = DHMSToTime(2, 3, 45, 0)
                    local startTimer = GetGameTimer()
                    local scale = before.timescale == 0 and 1 or before.timescale

                    TriggerServerEvent("weathersync:setTime", 2, 3, 45, 0, 0, false)
                    local okSet = pollUntil(3000, function() return wrapDiff(baseGameTime, target, 604800) <= 5 end)

                    local clockOk = false
                    if okSet then
                        pollUntil(2500, function() return wrapDiff(gameClockTime(), target % 86400, 86400) <= scale * 3 + 5 end)
                        clockOk = wrapDiff(gameClockTime(), target % 86400, 86400) <= scale * 3 + 5
                    end

                    report("T9 time set", okSet and clockOk,
                        okSet and string.format("target Tue 03:45, in-game %.2d:%.2d:%.2d", GetClockHours(), GetClockMinutes(), GetClockSeconds())
                        or "changeTime event not received")

                    -- Restore original time, compensating for real time spent testing
                    local elapsed = math.floor((GetGameTimer() - startTimer) / 1000 * scale)
                    local rd, rh, rm, rs = TimeToDHMS((before.time + elapsed) % 604800)
                    TriggerServerEvent("weathersync:setTime", rd, rh, rm, rs, 0, before.frozen)
                    Wait(500)
                else
                    skip("T9 time set", "no server response")
                end

                -- T10: timescale set/restore, checks speed and absence of time jumps
                local st10 = fetchServerState()

                if st10 then
                    local oldScale = st10.timescale == 0 and 1 or st10.timescale
                    local t0 = computeLocalTime()

                    TriggerServerEvent("weathersync:setTimescale", 120.0)
                    local okScale = pollUntil(3000, function() return currentTimescale == 120.0 end)

                    if okScale then
                        local t1 = computeLocalTime()
                        local jump = wrapDiff(t1, t0, 604800)
                        local noJump = jump <= oldScale * 4 + 10

                        Wait(3000)

                        local advance = (computeLocalTime() - t1) % 604800
                        local speedOk = math.abs(advance - 360) <= 60

                        report("T10 timescale", noJump and speedOk,
                            string.format("switch jump %ds, advance %ds over 3s (expected ~360s)", jump, advance))
                    else
                        report("T10 timescale", false, "changeTimescale event not received")
                    end

                    TriggerServerEvent("weathersync:setTimescale", st10.timescale)
                    Wait(500)
                else
                    skip("T10 timescale", "no server response")
                end

                -- T11: wind set/restore
                local st11 = fetchServerState()

                if st11 then
                    TriggerServerEvent("weathersync:setWind", 123.0, 4.5, false)
                    local okWind = pollUntil(3000, function() return serverWindDirection == 123.0 and serverWindSpeed == 4.5 end)

                    report("T11 wind", okWind, okWind and "changeWind received and applied" or "changeWind event not received")

                    TriggerServerEvent("weathersync:setWind", st11.windDirection, st11.windSpeed, false)
                    pollUntil(2000, function() return serverWindDirection == st11.windDirection end)
                else
                    skip("T11 wind", "no server response")
                end

                say({255, 255, 0}, "Note", "weather/wind freeze flags were reset to unfrozen during restore")
            end
        end
    end

    say(failed == 0 and {50, 255, 50} or {255, 80, 80}, "weathertest",
        string.format("done: %d passed, %d failed, %d skipped", passed, failed, skipped))
end

local function startTestSuite(full, echoToServer)
    if testRunning then
        TriggerEvent("chat:addMessage", {color = {255, 255, 0}, args = {"weathertest", "already running"}})
        return
    end

    if not syncEnabled then
        TriggerEvent("chat:addMessage", {color = {255, 80, 80}, args = {"weathertest", "sync is disabled — enable it first with /weathersync"}})
        return
    end

    testRunning = true

    CreateThread(function()
        local ok, err = pcall(runTestSuite, full, echoToServer)

        if not ok then
            TriggerEvent("chat:addMessage", {color = {255, 80, 80}, args = {"weathertest", "error: " .. tostring(err)}})
            print("[weathertest] error: " .. tostring(err))

            if echoToServer then
                TriggerServerEvent("weathersync:clientTestResult", "error: " .. tostring(err))
            end
        end

        testRunning = false
    end)
end

if Config.enableTests then
    RegisterCommand("weathertest", function(source, args, raw)
        startTestSuite(args[1] == "full", false)
    end, false)

    RegisterNetEvent("weathersync:runClientTests")
    AddEventHandler("weathersync:runClientTests", function(full)
        startTestSuite(full, true)
    end)
end

RegisterCommand("testweather", function(source, args, raw)
    if not args[1] then
        TriggerEvent("chat:addMessage", {
            color = {255, 0, 0},
            args = {"Error", "Please specify a weather type"}
        })
        return
    end

    local testWeather = args[1]
    local found = false

    for _, weatherType in pairs(Config.weatherTypes) do
        if weatherType == testWeather then
            found = true
            break
        end
    end

    if not found then
        TriggerEvent("chat:addMessage", {
            color = {255, 0, 0},
            args = {"Error", "Invalid weather type: " .. testWeather}
        })
        TriggerEvent("chat:addMessage", {
            color = {255, 255, 128},
            args = {"Available types", table.concat(Config.weatherTypes, ", ")}
        })
        return
    end

    local ped = PlayerPedId()
    local x, y, z = table.unpack(GetEntityCoords(ped))
    local translatedWeather = translateWeatherForRegion(testWeather, x, y, z)

    TriggerEvent("chat:addMessage", {
        color = {100, 255, 100},
        args = {"Test Weather", string.format("Testing %s -> %s", testWeather, translatedWeather)}
    })

    setWeather(translatedWeather, 5.0)

    if isSnowyWeather(translatedWeather) then
        setSnowCoverageTypeDirect(3)
    end
end, false)


