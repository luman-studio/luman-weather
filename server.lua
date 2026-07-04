local currentWeather = Config.weather
local currentTimescale = Config.timescale
local weatherPattern = Config.weatherPattern
local weatherInterval = Config.weatherInterval
local timeIsFrozen = Config.timeIsFrozen
local weatherIsFrozen = Config.weatherIsFrozen
local maxForecast = Config.maxForecast
local syncDelay = Config.syncDelay
local currentWindDirection = Config.windDirection
local currentWindSpeed = Config.windSpeed
local windIsFrozen = Config.windIsFrozen
local permanentSnow = Config.permanentSnow

local weatherTicks = 0
local weatherForecast = {}

local dayLength = 86400
local weekLength = 604800

local baseServerTime = GetGameTimer()
local baseGameTime = 0
local currentTime = 0

-- Initialize time based on config
if Config.time then
    -- Use explicit starting time from config
    baseGameTime = Config.time
    currentTime = baseGameTime
elseif Config.timescale == 0 then
    -- When using real-time sync, initialize baseGameTime from real server time
    local now = os.date("*t", os.time() + (Config.timezoneOffset or 0) * 3600)
    baseGameTime = now.sec + now.min * 60 + now.hour * 3600 + (now.wday - 1) * dayLength
    currentTime = baseGameTime
else
    baseGameTime = 0
    currentTime = 0
end

local debugMode = false
local syncStats = {
    weatherChanges = 0,
    timeChanges = 0,
    timescaleChanges = 0,
    windChanges = 0,
    playerInits = 0,
    lastWeatherChange = 0,
    lastPlayerInit = 0
}

local logColors = {
    ["default"] = "\x1B[0m",
    ["error"] = "\x1B[31m",
    ["success"] = "\x1B[32m",
    ["info"] = "\x1B[36m",
    ["warning"] = "\x1B[33m"
}

RegisterNetEvent("weathersync:init")
RegisterNetEvent("weathersync:requestUpdatedForecast")
RegisterNetEvent("weathersync:requestUpdatedAdminUi")
RegisterNetEvent("weathersync:setTime")
RegisterNetEvent("weathersync:resetTime")
RegisterNetEvent("weathersync:setTimescale")
RegisterNetEvent("weathersync:resetTimescale")
RegisterNetEvent("weathersync:setWeather")
RegisterNetEvent("weathersync:resetWeather")
RegisterNetEvent("weathersync:setWeatherPattern")
RegisterNetEvent("weathersync:resetWeatherPattern")
RegisterNetEvent("weathersync:setWind")
RegisterNetEvent("weathersync:resetWind")
RegisterNetEvent("weathersync:setSyncDelay")
RegisterNetEvent("weathersync:resetSyncDelay")
RegisterNetEvent("weathersync:requestSyncCheck")

local function nextWeather(weather)
    if weatherIsFrozen then
        return weather
    end

    local choices = weatherPattern[weather]

    if not choices then
        return weather
    end

    local c = 0
    local r = math.random(1, 100)

    for weatherType, chance in pairs(choices) do
        c = c + chance
        if r <= c then
            return weatherType
        end
    end

    return weather
end

local function nextWindDirection(direction)
    if windIsFrozen then
        return direction
    end

    return ((direction + math.random(0, 90) - 45) % 360) * 1.0
end

-- ============================================================================
-- FORECAST MANAGEMENT
-- Handles weather forecast queue generation and advancement
-- ============================================================================

local function generateForecast()
    local weather = nextWeather(currentWeather)
    local wind = nextWindDirection(currentWindDirection)

    weatherForecast = {{weather = weather, wind = wind}}

    for i = 2, maxForecast do
        weather = nextWeather(weather)
        wind = nextWindDirection(wind)
        weatherForecast[i] = {weather = weather, wind = wind}
    end
end

local function advanceForecast()
    -- Remove current forecast entry and get last entry
    local next = table.remove(weatherForecast, 1)
    local last = weatherForecast[#weatherForecast]

    -- Generate and append new forecast entry
    table.insert(weatherForecast, {
        weather = nextWeather(last.weather),
        wind = nextWindDirection(last.wind)
    })

    return next
end

-- ============================================================================
-- WEATHER SYNCHRONIZATION
-- Handles weather state changes and client broadcasting
-- ============================================================================

local function applyWeatherChange(newWeather, newWind)
    local weatherChanged = (currentWeather ~= newWeather)
    local windChanged = (currentWindDirection ~= newWind)

    -- Update server state
    currentWeather = newWeather
    currentWindDirection = newWind

    -- Only broadcast if something changed
    if weatherChanged or windChanged then
        syncStats.weatherChanges = syncStats.weatherChanges + 1
        syncStats.lastWeatherChange = os.time()
        debugLog(string.format("Weather change to %s (%.1f°) - broadcasting to all players", currentWeather, currentWindDirection))

        local players = GetPlayers()
        local transition = weatherInterval / (currentTimescale > 0 and currentTimescale or 1) / 4

        for _, playerId in pairs(players) do
            if weatherChanged then
                TriggerClientEvent("weathersync:changeWeather", playerId, currentWeather, transition, permanentSnow)
            end
            if windChanged then
                TriggerClientEvent("weathersync:changeWind", playerId, currentWindDirection, currentWindSpeed)
            end
        end

        return true -- Changed
    else
        debugLog(string.format("Weather tick - no change (still %s)", currentWeather))
        return false -- Not changed
    end
end

-- ============================================================================
-- TIME MANAGEMENT
-- Handles time progression (real-time and timescale modes)
-- ============================================================================

local function updateTime()
    if timeIsFrozen then
        return
    end

    currentTime = getCurrentTime(baseServerTime, currentTimescale, dayLength, weekLength, baseGameTime)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function contains(t, x)
    for _, v in pairs(t) do
        if v == x then
            return true
        end
    end
    return false
end

local function printMessage(target, message)
    if target and target > 0 then
        TriggerClientEvent("chat:addMessage", target, message)
    else
        print(table.concat(message.args, ": "))
    end
end

local function setWeather(weather, transition, freeze, permSnow, broadcastToAll)
    if broadcastToAll == nil then
        broadcastToAll = true
    end

    syncStats.weatherChanges = syncStats.weatherChanges + 1
    syncStats.lastWeatherChange = os.time()
    debugLog(string.format("Setting weather to %s (transition: %.1fs, frozen: %s, snow: %s, broadcast: %s)", weather, transition, tostring(freeze), tostring(permSnow), tostring(broadcastToAll)))

    if broadcastToAll then
        local players = GetPlayers()
        for _, playerId in pairs(players) do
            TriggerClientEvent("weathersync:changeWeather", playerId, weather, transition, permSnow)
        end
    end

    currentWeather = weather
    weatherIsFrozen = freeze
    permanentSnow = permSnow
    generateForecast()
end

local function getWeather()
    return currentWeather
end

local function resetWeather()
    -- Broadcast so clients don't keep the old weather until the next change
    setWeather(Config.weather, 10.0, Config.weatherIsFrozen, Config.permanentSnow, true)
end

function log(label, message)
    local color = logColors[label]

    if not color then
        color = logColors.default
    end

    print(string.format("%s[%s]%s %s", color, label, logColors.default, message))
end

function debugLog(message)
    if debugMode then
        log("info", message)
    end
end

local function validateWeatherPattern(pattern)
    for weather, choices in pairs(pattern) do
        local sum = 0

        for nextWeather, chance in pairs(choices) do
            if not pattern[nextWeather] then
                log("error", nextWeather .. " (following " .. weather .. ") is missing from the weather pattern table")
            end

            sum = sum + chance
        end

        if sum ~= 100 then
            log("error", weather .. " next stages do not add up to 100")
        end
    end
end

local function setWeatherPattern(pattern)
    validateWeatherPattern(pattern)
    weatherPattern = pattern
    generateForecast()
end

local function resetWeatherPattern()
    weatherPattern = Config.weatherPattern
    generateForecast()
end

local function setTime(d, h, m, s, t, f)
    -- Whole numbers only: fractional values break %d formatting and TimeToDHMS
    d, h, m, s = math.floor(d), math.floor(h), math.floor(m), math.floor(s)

    syncStats.timeChanges = syncStats.timeChanges + 1
    debugLog(string.format("Setting time to %s %.2d:%.2d:%.2d (frozen: %s)", GetDayOfWeek(d), h, m, s, tostring(f)))

    currentTime = DHMSToTime(d, h, m, s)
    timeIsFrozen = f
    baseServerTime = GetGameTimer()
    baseGameTime = currentTime

    local players = GetPlayers()
    for _, playerId in pairs(players) do
        TriggerClientEvent("weathersync:changeTime", playerId, d, h, m, s, t, f)
    end
end

local function getTime()
    updateTime()
    local d, h, m, s = TimeToDHMS(currentTime)
    return {day = d, hour = h, minute = m, second = s}
end

local function resetTime()
    timeIsFrozen = Config.timeIsFrozen
    baseServerTime = GetGameTimer()

    if Config.time then
        baseGameTime = Config.time
        currentTime = baseGameTime
    elseif Config.timescale == 0 then
        local now = os.date("*t", os.time() + (Config.timezoneOffset or 0) * 3600)
        baseGameTime = now.sec + now.min * 60 + now.hour * 3600 + (now.wday - 1) * dayLength
        currentTime = baseGameTime
    else
        baseGameTime = 0
        currentTime = 0
    end

    -- Clients keep their own clocks, so they must be re-anchored explicitly
    TriggerClientEvent("weathersync:syncBaseTime", -1, currentTime, currentTimescale, timeIsFrozen)
end

local function setTimescale(scale)
    syncStats.timescaleChanges = syncStats.timescaleChanges + 1
    debugLog(string.format("Setting timescale to %.2f", scale))

    -- Refresh currentTime under the old timescale before rebasing
    updateTime()

    currentTimescale = scale
    baseServerTime = GetGameTimer()
    baseGameTime = currentTime

    TriggerClientEvent("weathersync:changeTimescale", -1, scale)
end

local function resetTimescale()
    setTimescale(Config.timescale)
end

local function setSyncDelay(delay)
    syncDelay = delay
end

local function resetSyncDelay()
    syncDelay = Config.syncDelay
end

local function setWind(direction, speed, frozen, broadcastToAll)
    if broadcastToAll == nil then
        broadcastToAll = true
    end

    syncStats.windChanges = syncStats.windChanges + 1
    debugLog(string.format("Setting wind to %.1f° speed %.1f (frozen: %s, broadcast: %s)", direction, speed, tostring(frozen), tostring(broadcastToAll)))

    if broadcastToAll then
        local players = GetPlayers()
        for _, playerId in pairs(players) do
            TriggerClientEvent("weathersync:changeWind", playerId, direction, speed)
        end
    end

    currentWindDirection = direction
    currentWindSpeed = speed
    windIsFrozen = frozen
    generateForecast()
end

local function resetWind()
    -- Broadcast so clients don't keep the old wind until the next change
    setWind(Config.windDirection, Config.windSpeed, Config.windIsFrozen, true)
end

local function getWind()
    return {direction = currentWindDirection, speed = currentWindSpeed}
end

local function createForecast()
    updateTime()

    local forecast = {}

    for i = 0, #weatherForecast do
        local d, h, m, s, weather, wind

        if i == 0 then
            d, h, m, s = TimeToDHMS(currentTime)
            weather = currentWeather
            wind = currentWindDirection
        else
            local time = (timeIsFrozen and currentTime or (currentTime + weatherInterval * i) % weekLength)
            d, h, m, s = TimeToDHMS(time - time % weatherInterval)
            weather = weatherForecast[i].weather
            wind = weatherForecast[i].wind
        end

        table.insert(forecast, {day = d, hour = h, minute = m, second = s, weather = weather, wind = wind})
    end

    return forecast
end

local function syncWeather(player)
    local scale = currentTimescale > 0 and currentTimescale or 1
    TriggerClientEvent("weathersync:changeWeather", player, currentWeather, weatherInterval / scale / 4, permanentSnow)
end

local function syncWind(player)
    TriggerClientEvent("weathersync:changeWind", player, currentWindDirection, currentWindSpeed)
end

local function syncBaseTime(player)
    -- Send the *current* game time as the anchor, not the stale base from
    -- resource start, so late joiners get the right time
    updateTime()
    TriggerClientEvent("weathersync:syncBaseTime", player, currentTime, currentTimescale, timeIsFrozen)
end

exports("getTime", getTime)
exports("setTime", setTime)
exports("resetTime", resetTime)
exports("setTimescale", setTimescale)
exports("resetTimescale", resetTimescale)
exports("getWeather", getWeather)
exports("setWeather", function(weather, transition, freeze, permSnow)
    setWeather(weather, transition, freeze, permSnow, true)
end)
exports("resetWeather", resetWeather)
exports("setWeatherPattern", setWeatherPattern)
exports("resetWeatherPattern", resetWeatherPattern)
exports("getWind", getWind)
exports("setWind", function(direction, speed, frozen)
    setWind(direction, speed, frozen, true)
end)
exports("resetWind", resetWind)
exports("setSyncDelay", setSyncDelay)
exports("resetSyncDelay", resetSyncDelay)
exports("getForecast", createForecast)

-- Net events can be triggered by any client, so they must be gated by the
-- same ace permissions as the corresponding commands. Events triggered from
-- server-side code (TriggerEvent/exports) have no player source and are allowed.
local function isAllowed(src, command)
    if not src or src == "" or src == 0 then
        return true
    end

    if IsPlayerAceAllowed(src, "command." .. command) then
        return true
    end

    log("warning", string.format("Player %s tried to use %s without permission", tostring(src), command))
    return false
end

AddEventHandler("weathersync:setWeather", function(weather, transition, freeze, permSnow)
    if not isAllowed(source, "weather") then return end

    if not contains(Config.weatherTypes, weather) then
        return
    end

    setWeather(weather, tonumber(transition) or 10.0, freeze == true, permSnow == true, true)
end)
AddEventHandler("weathersync:resetWeather", function()
    if not isAllowed(source, "weather") then return end
    resetWeather()
end)
AddEventHandler("weathersync:setWeatherPattern", function(pattern)
    if not isAllowed(source, "weather") then return end
    setWeatherPattern(pattern)
end)
AddEventHandler("weathersync:resetWeatherPattern", function()
    if not isAllowed(source, "weather") then return end
    resetWeatherPattern()
end)
AddEventHandler("weathersync:setTime", function(d, h, m, s, t, f)
    if not isAllowed(source, "time") then return end
    setTime(tonumber(d) or 0, tonumber(h) or 0, tonumber(m) or 0, tonumber(s) or 0, tonumber(t) or 0, f == true)
end)
AddEventHandler("weathersync:resetTime", function()
    if not isAllowed(source, "time") then return end
    resetTime()
end)
AddEventHandler("weathersync:setTimescale", function(scale)
    if not isAllowed(source, "timescale") then return end

    scale = tonumber(scale)
    if scale then
        setTimescale(scale + 0.0)
    end
end)
AddEventHandler("weathersync:resetTimescale", function()
    if not isAllowed(source, "timescale") then return end
    resetTimescale()
end)
AddEventHandler("weathersync:setSyncDelay", function(delay)
    if not isAllowed(source, "syncdelay") then return end

    delay = tonumber(delay)
    if delay and delay >= 100 then
        setSyncDelay(delay)
    end
end)
AddEventHandler("weathersync:resetSyncDelay", function()
    if not isAllowed(source, "syncdelay") then return end
    resetSyncDelay()
end)
AddEventHandler("weathersync:setWind", function(direction, speed, frozen)
    if not isAllowed(source, "wind") then return end
    setWind((tonumber(direction) or 0.0) + 0.0, (tonumber(speed) or 0.0) + 0.0, frozen == true, true)
end)
AddEventHandler("weathersync:resetWind", function()
    if not isAllowed(source, "wind") then return end
    resetWind()
end)

-- Read-only diagnostics: sends the authoritative server state so the client
-- can compare it against its locally computed state (/synccheck)
AddEventHandler("weathersync:requestSyncCheck", function()
    updateTime()
    debugLog(string.format("Sync check requested by player %s: time %s, weather %s", tostring(source), FormatTime(currentTime), currentWeather))
    TriggerClientEvent("weathersync:syncCheckResult", source, currentTime, currentWeather, currentWindDirection, currentWindSpeed, currentTimescale, timeIsFrozen)
end)

AddEventHandler("weathersync:requestUpdatedForecast", function()
    TriggerClientEvent("weathersync:updateForecast", source, createForecast())
end)

AddEventHandler("weathersync:requestUpdatedAdminUi", function()
    if not isAllowed(source, "weatherui") then return end

    updateTime()
    TriggerClientEvent("weathersync:updateAdminUi", source, currentWeather, currentTime, currentTimescale, currentWindDirection, currentWindSpeed, syncDelay)
end)

AddEventHandler("weathersync:init", function()
    syncStats.playerInits = syncStats.playerInits + 1
    syncStats.lastPlayerInit = os.time()
    debugLog(string.format("Player %d initialized weather sync", source))

    -- syncBaseTime carries the timescale and frozen flag, so no separate
    -- timescale sync is needed here
    syncBaseTime(source)
    syncWeather(source)
    syncWind(source)
end)

RegisterCommand("weather", function(source, args, raw)
    local weather = args[1] and args[1] or currentWeather
    local transition = tonumber(args[2]) or 10.0
    local freeze = args[3] == "1"
    local permanentSnow = args[4] == "1"

    if transition <= 0.0 then
        transition = 0.1
    end

    if contains(Config.weatherTypes, weather) then
        setWeather(weather, transition + 0.0, freeze, permanentSnow, true)
    else
        printMessage(source, {color = {255, 0, 0}, args = {"Error", "Unknown weather type: " .. weather}})
    end
end, true)

RegisterCommand("time", function(source, args, raw)
    if #args > 0 then
        local d = tonumber(args[1]) or 0
        local h = tonumber(args[2]) or 0
        local m = tonumber(args[3]) or 0
        local s = tonumber(args[4]) or 0
        local t = tonumber(args[5]) or 0
        local f = args[6] == "1"

        setTime(d, h, m, s, t, f)
    else
        local d, h, m, s = TimeToDHMS(currentTime)
        printMessage(source, {color = {255, 255, 128}, args = {"Time", string.format("%s %.2d:%.2d:%.2d", GetDayOfWeek(d), h, m, s)}})
    end
end, true)

RegisterCommand("timescale", function(source, args, raw)
    if args[1] then
        setTimescale(tonumber(args[1]) + 0.0)
    else
        printMessage(source, {color = {255, 255, 128}, args = {"Timescale", currentTimescale}})
    end
end, true)

RegisterCommand("syncdelay", function(source, args, raw)
    local delay = tonumber(args[1])

    if delay and delay >= 100 then
        setSyncDelay(delay)
    else
        printMessage(source, {color = {255, 255, 128}, args = {"Sync delay", string.format("%dms", syncDelay)}})
    end
end, true)

RegisterCommand("wind", function(source, args, raw)
    if #args > 0 then
        local direction = (tonumber(args[1]) or 0.0) + 0.0
        local speed = (tonumber(args[2]) or 0.0) + 0.0
        local frozen = args[3] == "1"
        setWind(direction, speed, frozen, true)
    end
end, true)

RegisterCommand("forecast", function(source, args, raw)
    if source and source > 0 then
        TriggerClientEvent("weathersync:toggleForecast", source)
    else
        local forecast = createForecast()
        printMessage(source, {args = {"WEATHER FORECAST"}})
        printMessage(source, {args = {"================"}})
        for i = 1, #forecast do
            local time = string.format("%s %.2d:%.2d", GetDayOfWeek(forecast[i].day), forecast[i].hour, forecast[i].minute)
            printMessage(source, {args = {time, forecast[i].weather}})
        end
        printMessage(source, {args = {"================"}})
    end
end, true)

RegisterCommand("weatherui", function(source, args, raw)
    if source and source > 0 then
        updateTime()
        TriggerClientEvent("weathersync:openAdminUi", source, currentWeather, currentTime, currentTimescale, currentWindDirection, currentWindSpeed, syncDelay)
    end
end, true)

RegisterCommand("weathersync", function(source, args, raw)
    TriggerClientEvent("weathersync:toggleSync", source)
end, true)

RegisterCommand("mytime", function(source, args, raw)
    local h = (args[1] and tonumber(args[1]) or 0)
    local m = (args[2] and tonumber(args[2]) or 0)
    local s = (args[3] and tonumber(args[3]) or 0)
    local t = (args[4] and tonumber(args[4]) or 0)
    TriggerClientEvent("weathersync:setMyTime", source, h, m, s, t)
end, true)

RegisterCommand("myweather", function(source, args, raw)
    local weather = (args[1] and args[1] or currentWeather)
    local transition = (args[2] and tonumber(args[2]) or 5.0)
    local permanentSnow = args[3] == "1"
    TriggerClientEvent("weathersync:setMyWeather", source, weather, transition, permanentSnow)
end, true)

RegisterCommand("weatherdebug_sv", function(source, args, raw)
    debugMode = not debugMode
    local message = string.format("Server weather debug: %s", debugMode and "enabled" or "disabled")
    log(debugMode and "success" or "default", message)
    printMessage(source, {color = {255, 255, 128}, args = {"WeatherSync", message}})
end, true)

RegisterCommand("weatherstats", function(source, args, raw)
    local d, h, m, s = TimeToDHMS(currentTime)
    local timeStr = string.format("%s %.2d:%.2d:%.2d", GetDayOfWeek(d), h, m, s)

    printMessage(source, {color = {100, 200, 255}, args = {"=== Server Weather Stats ==="}})
    printMessage(source, {color = {255, 255, 255}, args = {"Current Weather", currentWeather}})
    printMessage(source, {color = {255, 255, 255}, args = {"Current Time", timeStr}})
    printMessage(source, {color = {255, 255, 255}, args = {"Timescale", string.format("%.2f", currentTimescale)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Time Frozen", tostring(timeIsFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Frozen", tostring(weatherIsFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Frozen", tostring(windIsFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Direction", string.format("%.1f° %s", currentWindDirection, GetCardinalDirection(currentWindDirection))}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Speed", string.format("%.1f", currentWindSpeed)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Permanent Snow", tostring(permanentSnow)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Sync Delay", string.format("%dms", syncDelay)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Interval", string.format("%ds", weatherInterval)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Connected Players", #GetPlayers()}})

    printMessage(source, {color = {100, 200, 255}, args = {"=== Sync Statistics ==="}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Changes", tostring(syncStats.weatherChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Time Changes", tostring(syncStats.timeChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Timescale Changes", tostring(syncStats.timescaleChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Changes", tostring(syncStats.windChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Player Inits", tostring(syncStats.playerInits)}})

    if syncStats.lastWeatherChange > 0 then
        local timeSince = os.time() - syncStats.lastWeatherChange
        printMessage(source, {color = {255, 255, 255}, args = {"Last Weather Change", string.format("%ds ago", timeSince)}})
    end

    if syncStats.lastPlayerInit > 0 then
        local timeSince = os.time() - syncStats.lastPlayerInit
        printMessage(source, {color = {255, 255, 255}, args = {"Last Player Init", string.format("%ds ago", timeSince)}})
    end
end, true)

RegisterCommand("testforecast", function(source, args, raw)
    local forecast = createForecast()
    printMessage(source, {color = {100, 200, 255}, args = {"=== WEATHER FORECAST (TEST) ==="}})

    for i = 1, #forecast do
        local time = string.format("%s %.2d:%.2d", GetDayOfWeek(forecast[i].day), forecast[i].hour, forecast[i].minute)
        local wind = string.format("%s %.1f°", GetCardinalDirection(forecast[i].wind), forecast[i].wind)
        printMessage(source, {color = {255, 255, 255}, args = {time, forecast[i].weather, wind}})
    end
end, true)

-- ============================================================================
-- AUTOMATED TEST SUITE (server console)
--   weathertest              - read-only server tests
--   weathertest full         - adds mutating tests (state is restored)
--   weathertest client <id>  - run the client test suite on player <id>,
--                              results are echoed to this console
--                              (add "full" as the last argument for the full suite)
-- ============================================================================

local pendingClientTests = {}

if Config.enableTests then
    RegisterNetEvent("weathersync:clientTestResult")
    AddEventHandler("weathersync:clientTestResult", function(line)
        local src = tonumber(source)

        -- Only echo results from players we actually asked to run tests
        if src and pendingClientTests[src] and os.time() - pendingClientTests[src] < 180 then
            print(string.format("[weathertest][player %d] %s", src, tostring(line)))
        end
    end)
end

local function runServerTestSuite(full)
    CreateThread(function()
        local passed, failed, skipped = 0, 0, 0

        local function report(name, ok, detail)
            if ok then
                passed = passed + 1
            else
                failed = failed + 1
            end

            log(ok and "success" or "error", string.format("%s: %s%s", name, ok and "OK" or "FAIL", detail and (" — " .. detail) or ""))
        end

        local function skip(name, reason)
            skipped = skipped + 1
            log("warning", string.format("%s: SKIP — %s", name, reason))
        end

        log("info", full and "weathertest: starting full server suite (~10s)" or "weathertest: starting read-only server suite (~5s)")

        -- S1: time conversion roundtrip
        do
            local ok, detail = true, nil

            for _, t in ipairs({0, 1, 59, 3600, 86399, 86400, 186300, 604799}) do
                local d, h, m, s = TimeToDHMS(t)
                if DHMSToTime(d, h, m, s) ~= t then
                    ok, detail = false, string.format("roundtrip failed for %d", t)
                    break
                end
            end

            report("S1 time conversion", ok, detail)
        end

        -- S2: cardinal directions
        do
            local cases = {{0, "N"}, {45, "NE"}, {90, "E"}, {180, "S"}, {270, "W"}, {359, "N"}}
            local ok, detail = true, nil

            for _, c in ipairs(cases) do
                if GetCardinalDirection(c[1]) ~= c[2] then
                    ok, detail = false, string.format("%d° -> %s, expected %s", c[1], GetCardinalDirection(c[1]), c[2])
                    break
                end
            end

            report("S2 cardinal directions", ok, detail)
        end

        -- S3: active weather pattern is consistent
        do
            local ok, detail = true, nil

            for weather, choices in pairs(weatherPattern) do
                local sum = 0

                for nextW, chance in pairs(choices) do
                    sum = sum + chance

                    if not weatherPattern[nextW] then
                        ok, detail = false, string.format("%s references %s which has no pattern entry", weather, nextW)
                    end
                end

                if sum ~= 100 then
                    ok, detail = false, string.format("%s chances sum to %d, expected 100", weather, sum)
                end
            end

            report("S3 weather pattern", ok, detail)
        end

        -- S4: forecast structure
        do
            local forecast = createForecast()
            local ok = #forecast == maxForecast + 1
            local detail = string.format("%d entries (expected %d)", #forecast, maxForecast + 1)

            if ok then
                for i = 1, #forecast do
                    if not contains(Config.weatherTypes, forecast[i].weather) then
                        ok, detail = false, string.format("entry %d has invalid weather %s", i, tostring(forecast[i].weather))
                        break
                    end
                end
            end

            if ok and forecast[1].weather ~= currentWeather then
                ok, detail = false, string.format("first entry %s != current weather %s", forecast[1].weather, currentWeather)
            end

            report("S4 forecast", ok, detail)
        end

        -- S5: nextWeather only produces known weather types
        do
            local ok, detail = true, nil

            for weather in pairs(weatherPattern) do
                for i = 1, 50 do
                    local nw = nextWeather(weather)

                    if not weatherPattern[nw] then
                        ok, detail = false, string.format("%s -> %s which has no pattern entry", weather, tostring(nw))
                        break
                    end
                end

                if not ok then
                    break
                end
            end

            report("S5 nextWeather", ok, detail)
        end

        -- S6: time progression at the configured rate
        if timeIsFrozen then
            skip("S6 time progression", "time is frozen")
        else
            updateTime()
            local t1 = currentTime

            Wait(3000)

            updateTime()
            local scale = currentTimescale == 0 and 1 or currentTimescale
            local advance = (currentTime - t1) % weekLength
            local expected = 3 * scale

            report("S6 time progression", math.abs(advance - expected) <= scale + 2,
                string.format("%ds over 3s (expected ~%ds)", advance, expected))
        end

        -- Mutating tests
        if full then
            -- S7: time set/restore
            do
                updateTime()
                local origTime, origFrozen = currentTime, timeIsFrozen
                local t0 = GetGameTimer()
                local target = DHMSToTime(2, 3, 45, 0)

                setTime(2, 3, 45, 0, 0, false)
                updateTime()

                report("S7 time set", math.abs(currentTime - target) <= 2,
                    string.format("set %s, now %s", FormatTime(target), FormatTime(currentTime)))

                -- Restore, compensating for real time spent testing
                local scale = currentTimescale == 0 and 1 or currentTimescale
                local elapsed = math.floor((GetGameTimer() - t0) / 1000 * scale)
                local rd, rh, rm, rs = TimeToDHMS((origTime + elapsed) % weekLength)
                setTime(rd, rh, rm, rs, 0, origFrozen)
            end

            -- S8: timescale set/restore
            if timeIsFrozen then
                skip("S8 timescale", "time is frozen")
            else
                local orig = currentTimescale

                setTimescale(120.0)
                updateTime()
                local t1 = currentTime

                Wait(2000)

                updateTime()
                local advance = (currentTime - t1) % weekLength

                report("S8 timescale", currentTimescale == 120.0 and math.abs(advance - 240) <= 130,
                    string.format("advance %ds over 2s (expected ~240s)", advance))

                setTimescale(orig)
            end

            -- S9: weather set/restore (freeze/snow flags restored exactly)
            do
                local origW, origFrozen, origSnow = currentWeather, weatherIsFrozen, permanentSnow
                local testW = origW ~= "rain" and "rain" or "clouds"

                setWeather(testW, 0.1, origFrozen, origSnow, true)
                report("S9 weather set", currentWeather == testW, string.format("%s -> %s", origW, tostring(currentWeather)))
                setWeather(origW, 2.0, origFrozen, origSnow, true)
            end

            -- S10: wind set/restore
            do
                local origD, origS, origF = currentWindDirection, currentWindSpeed, windIsFrozen

                setWind(123.0, 4.5, origF, true)
                report("S10 wind set", currentWindDirection == 123.0 and currentWindSpeed == 4.5,
                    string.format("direction %.1f°, speed %.1f", currentWindDirection, currentWindSpeed))
                setWind(origD, origS, origF, true)
            end
        end

        log(failed == 0 and "success" or "error",
            string.format("weathertest done: %d passed, %d failed, %d skipped", passed, failed, skipped))
    end)
end

if Config.enableTests then
    RegisterCommand("weathertest", function(source, args, raw)
        if source and source > 0 then
            printMessage(source, {color = {255, 255, 128}, args = {"weathertest", "Use /weathertest in game, or run this command from the server console"}})
            return
        end

        if args[1] == "client" then
            local target = tonumber(args[2])

            if not target or not GetPlayerName(target) then
                log("error", "weathertest client: unknown player id. Usage: weathertest client <id> [full]")
                return
            end

            pendingClientTests[target] = os.time()
            log("info", string.format("weathertest: running client suite on player %d (%s)...", target, GetPlayerName(target)))
            TriggerClientEvent("weathersync:runClientTests", target, args[3] == "full")
            return
        end

        runServerTestSuite(args[1] == "full")
    end, true)
end

CreateThread(function()
    validateWeatherPattern(weatherPattern)

    generateForecast()

    log("success", "WeatherSync initialized successfully")
    log("info", string.format("Initial weather: %s, time: %s", currentWeather, FormatTime(currentTime)))
    log("info", string.format("Timescale: %.2f, sync delay: %dms", currentTimescale, syncDelay))

    while true do
        -- Calculate tick size based on timescale
        local tick = currentTimescale == 0
            and syncDelay / 1000
            or currentTimescale * (syncDelay / 1000)

        -- Update time (handles both real-time and timescale modes)
        updateTime()

        -- Handle weather progression
        if not weatherIsFrozen then
            weatherTicks = weatherTicks + tick

            if weatherTicks >= weatherInterval then
                -- Advance forecast queue and get next weather state
                local nextState = advanceForecast()

                -- Apply weather change (broadcasts only if changed)
                applyWeatherChange(nextState.weather, nextState.wind)

                weatherTicks = 0
            end
        end

        Wait(syncDelay)
    end
end)
