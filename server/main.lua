-- ============================================================================
-- WeatherSync - server core
--
-- Owns the authoritative weather/time/wind state and the forecast queue.
-- Clients are only messaged when something actually changes (weather change,
-- admin command, player join) - the in-game clock runs locally on each client
-- from a shared base, so no periodic network sync is needed.
--
-- The public API is exposed on the WeatherSync table (used by commands.lua
-- and tests.lua) and mirrored as resource exports for other resources.
-- ============================================================================

WeatherSync = {}

-- ============================================================================
-- STATE
-- ============================================================================

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

-- Time is anchored: currentTime = baseGameTime + elapsed since baseServerTime
-- (scaled by the timescale). Re-anchored whenever time or timescale changes.
local baseServerTime = GetGameTimer()
local baseGameTime = 0
local currentTime = 0

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

-- ============================================================================
-- LOGGING
-- ============================================================================

local logColors = {
    ["default"] = "\x1B[0m",
    ["error"] = "\x1B[31m",
    ["success"] = "\x1B[32m",
    ["info"] = "\x1B[36m",
    ["warning"] = "\x1B[33m"
}

local function log(label, message)
    local color = logColors[label] or logColors.default
    print(string.format("%s[%s]%s %s", color, label, logColors.default, message))
end

local function debugLog(message)
    if debugMode then
        log("info", message)
    end
end

WeatherSync.log = log
WeatherSync.debugLog = debugLog

function WeatherSync.toggleDebug()
    debugMode = not debugMode
    return debugMode
end

-- Send a chat message to a player, or print to the console for source 0
function WeatherSync.printMessage(target, message)
    if target and target > 0 then
        TriggerClientEvent("chat:addMessage", target, message)
    else
        print(table.concat(message.args, ": "))
    end
end

-- ============================================================================
-- TIME
-- ============================================================================

local function initBaseTime()
    baseServerTime = GetGameTimer()

    if Config.time then
        -- Explicit starting time from the config
        baseGameTime = Config.time
    elseif Config.timescale == 0 then
        -- Real-time mode: anchor to the real server clock
        local now = os.date("*t", os.time() + (Config.timezoneOffset or 0) * 3600)
        baseGameTime = now.sec + now.min * 60 + now.hour * 3600 + (now.wday - 1) * DAY_SECONDS
    else
        baseGameTime = 0
    end

    currentTime = baseGameTime
end

-- Recompute currentTime from the anchor. Cheap and exact - can be called
-- any time fresh state is needed.
local function updateTime()
    if timeIsFrozen then
        return
    end

    -- Timescale 0 means real time (1 in-game second per real second)
    local scale = currentTimescale == 0 and 1 or currentTimescale
    local elapsed = (GetGameTimer() - baseServerTime) / 1000

    currentTime = math.floor(baseGameTime + elapsed * scale) % WEEK_SECONDS
end

local function setTime(d, h, m, s, transition, freeze)
    -- Whole numbers only: fractional values break %d formatting and TimeToDHMS
    d, h, m, s = math.floor(d), math.floor(h), math.floor(m), math.floor(s)

    syncStats.timeChanges = syncStats.timeChanges + 1
    debugLog(string.format("Setting time to %s %.2d:%.2d:%.2d (frozen: %s)", GetDayOfWeek(d), h, m, s, tostring(freeze)))

    currentTime = DHMSToTime(d, h, m, s)
    timeIsFrozen = freeze
    baseServerTime = GetGameTimer()
    baseGameTime = currentTime

    TriggerClientEvent("weathersync:changeTime", -1, d, h, m, s, transition, freeze)
end

local function getTimeSeconds()
    updateTime()
    return currentTime
end

local function getTime()
    local d, h, m, s = TimeToDHMS(getTimeSeconds())
    return {day = d, hour = h, minute = m, second = s}
end

local function resetTime()
    timeIsFrozen = Config.timeIsFrozen
    initBaseTime()

    -- Clients keep their own clocks, so they must be re-anchored explicitly
    TriggerClientEvent("weathersync:syncBaseTime", -1, currentTime, currentTimescale, timeIsFrozen)
end

local function setTimescale(scale)
    syncStats.timescaleChanges = syncStats.timescaleChanges + 1
    debugLog(string.format("Setting timescale to %.2f", scale))

    -- Refresh currentTime under the old timescale before re-anchoring
    updateTime()

    currentTimescale = scale
    baseServerTime = GetGameTimer()
    baseGameTime = currentTime

    TriggerClientEvent("weathersync:changeTimescale", -1, scale)
end

local function resetTimescale()
    setTimescale(Config.timescale)
end

-- ============================================================================
-- WEATHER PATTERN & FORECAST
-- ============================================================================

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

-- Pick the next weather stage using the configured probabilities
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

-- Pop the next forecast entry and append a fresh one to the end of the queue
local function advanceForecast()
    local next = table.remove(weatherForecast, 1)
    local last = weatherForecast[#weatherForecast]

    table.insert(weatherForecast, {
        weather = nextWeather(last.weather),
        wind = nextWindDirection(last.wind)
    })

    return next
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
            local time = (timeIsFrozen and currentTime or (currentTime + weatherInterval * i) % WEEK_SECONDS)
            d, h, m, s = TimeToDHMS(time - time % weatherInterval)
            weather = weatherForecast[i].weather
            wind = weatherForecast[i].wind
        end

        table.insert(forecast, {day = d, hour = h, minute = m, second = s, weather = weather, wind = wind})
    end

    return forecast
end

-- ============================================================================
-- WEATHER & WIND
-- ============================================================================

-- Advance to a new weather state. Broadcasts to clients only if something
-- actually changed - this is what keeps idle network traffic at zero.
local function applyWeatherChange(newWeather, newWind)
    local weatherChanged = (currentWeather ~= newWeather)
    local windChanged = (currentWindDirection ~= newWind)

    currentWeather = newWeather
    currentWindDirection = newWind

    if not weatherChanged and not windChanged then
        debugLog(string.format("Weather tick - no change (still %s)", currentWeather))
        return false
    end

    syncStats.weatherChanges = syncStats.weatherChanges + 1
    syncStats.lastWeatherChange = os.time()
    debugLog(string.format("Weather change to %s (%.1f°) - broadcasting to all players", currentWeather, currentWindDirection))

    local transition = weatherInterval / (currentTimescale > 0 and currentTimescale or 1) / 4

    if weatherChanged then
        TriggerClientEvent("weathersync:changeWeather", -1, currentWeather, transition, permanentSnow)
    end

    if windChanged then
        TriggerClientEvent("weathersync:changeWind", -1, currentWindDirection, currentWindSpeed)
    end

    return true
end

local function setWeather(weather, transition, freeze, permSnow)
    syncStats.weatherChanges = syncStats.weatherChanges + 1
    syncStats.lastWeatherChange = os.time()
    debugLog(string.format("Setting weather to %s (transition: %.1fs, frozen: %s, snow: %s)", weather, transition, tostring(freeze), tostring(permSnow)))

    TriggerClientEvent("weathersync:changeWeather", -1, weather, transition, permSnow)

    currentWeather = weather
    weatherIsFrozen = freeze
    permanentSnow = permSnow
    generateForecast()
end

local function getWeather()
    return currentWeather
end

local function resetWeather()
    -- Broadcasts so clients don't keep the old weather until the next change
    setWeather(Config.weather, 10.0, Config.weatherIsFrozen, Config.permanentSnow)
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

local function setWind(direction, speed, frozen)
    syncStats.windChanges = syncStats.windChanges + 1
    debugLog(string.format("Setting wind to %.1f° speed %.1f (frozen: %s)", direction, speed, tostring(frozen)))

    TriggerClientEvent("weathersync:changeWind", -1, direction, speed)

    currentWindDirection = direction
    currentWindSpeed = speed
    windIsFrozen = frozen
    generateForecast()
end

local function getWind()
    return {direction = currentWindDirection, speed = currentWindSpeed}
end

local function resetWind()
    -- Broadcasts so clients don't keep the old wind until the next change
    setWind(Config.windDirection, Config.windSpeed, Config.windIsFrozen)
end

-- ============================================================================
-- SYNC
-- ============================================================================

local function setSyncDelay(delay)
    syncDelay = delay
end

local function resetSyncDelay()
    syncDelay = Config.syncDelay
end

-- Anchor a client's local clock: sends the *current* game time, the timescale
-- and the freeze flag. From then on the client advances time on its own.
local function syncBaseTime(player)
    updateTime()
    TriggerClientEvent("weathersync:syncBaseTime", player, currentTime, currentTimescale, timeIsFrozen)
end

local function syncWeather(player)
    local scale = currentTimescale > 0 and currentTimescale or 1
    TriggerClientEvent("weathersync:changeWeather", player, currentWeather, weatherInterval / scale / 4, permanentSnow)
end

local function syncWind(player)
    TriggerClientEvent("weathersync:changeWind", player, currentWindDirection, currentWindSpeed)
end

-- ============================================================================
-- PUBLIC API (WeatherSync namespace + resource exports)
-- ============================================================================

WeatherSync.setTime = setTime
WeatherSync.getTime = getTime
WeatherSync.getTimeSeconds = getTimeSeconds
WeatherSync.resetTime = resetTime
WeatherSync.setTimescale = setTimescale
WeatherSync.resetTimescale = resetTimescale
WeatherSync.setWeather = setWeather
WeatherSync.getWeather = getWeather
WeatherSync.resetWeather = resetWeather
WeatherSync.setWeatherPattern = setWeatherPattern
WeatherSync.resetWeatherPattern = resetWeatherPattern
WeatherSync.setWind = setWind
WeatherSync.getWind = getWind
WeatherSync.resetWind = resetWind
WeatherSync.setSyncDelay = setSyncDelay
WeatherSync.resetSyncDelay = resetSyncDelay
WeatherSync.getForecast = createForecast

function WeatherSync.getWeatherPattern()
    return weatherPattern
end

-- Preview what nextWeather would pick (used by the test suite)
function WeatherSync.peekNextWeather(weather)
    return nextWeather(weather)
end

function WeatherSync.getStats()
    return syncStats
end

-- Full snapshot of the authoritative state (time is recomputed fresh)
function WeatherSync.getState()
    updateTime()

    return {
        weather = currentWeather,
        weatherFrozen = weatherIsFrozen,
        permanentSnow = permanentSnow,
        time = currentTime,
        timescale = currentTimescale,
        timeFrozen = timeIsFrozen,
        windDirection = currentWindDirection,
        windSpeed = currentWindSpeed,
        windFrozen = windIsFrozen,
        syncDelay = syncDelay,
        weatherInterval = weatherInterval
    }
end

exports("getTime", getTime)
exports("setTime", setTime)
exports("resetTime", resetTime)
exports("setTimescale", setTimescale)
exports("resetTimescale", resetTimescale)
exports("getWeather", getWeather)
exports("setWeather", setWeather)
exports("resetWeather", resetWeather)
exports("setWeatherPattern", setWeatherPattern)
exports("resetWeatherPattern", resetWeatherPattern)
exports("getWind", getWind)
exports("setWind", setWind)
exports("resetWind", resetWind)
exports("setSyncDelay", setSyncDelay)
exports("resetSyncDelay", resetSyncDelay)
exports("getForecast", createForecast)

-- ============================================================================
-- NETWORK EVENTS
-- Net events can be triggered by any client, so they are gated by the same
-- ace permissions as the corresponding commands. Events triggered from
-- server-side code (TriggerEvent/exports) have no player source and pass.
-- ============================================================================

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

WeatherSync.isAllowed = isAllowed

RegisterNetEvent("weathersync:init")
RegisterNetEvent("weathersync:requestUpdatedForecast")
RegisterNetEvent("weathersync:requestUpdatedAdminUi")
RegisterNetEvent("weathersync:requestSyncCheck")
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

AddEventHandler("weathersync:setWeather", function(weather, transition, freeze, permSnow)
    if not isAllowed(source, "weather") then return end

    if not TableContains(Config.weatherTypes, weather) then
        return
    end

    setWeather(weather, tonumber(transition) or 10.0, freeze == true, permSnow == true)
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
    setWind((tonumber(direction) or 0.0) + 0.0, (tonumber(speed) or 0.0) + 0.0, frozen == true)
end)

AddEventHandler("weathersync:resetWind", function()
    if not isAllowed(source, "wind") then return end
    resetWind()
end)

AddEventHandler("weathersync:requestUpdatedForecast", function()
    TriggerClientEvent("weathersync:updateForecast", source, createForecast())
end)

AddEventHandler("weathersync:requestUpdatedAdminUi", function()
    if not isAllowed(source, "weatherui") then return end

    updateTime()
    TriggerClientEvent("weathersync:updateAdminUi", source, currentWeather, currentTime, currentTimescale, currentWindDirection, currentWindSpeed, syncDelay)
end)

-- Read-only diagnostics: sends the authoritative state so the client can
-- compare it against its locally computed state (/synccheck, /weathertest)
AddEventHandler("weathersync:requestSyncCheck", function()
    updateTime()
    debugLog(string.format("Sync check requested by player %s: time %s, weather %s", tostring(source), FormatTime(currentTime), currentWeather))
    TriggerClientEvent("weathersync:syncCheckResult", source, currentTime, currentWeather, currentWindDirection, currentWindSpeed, currentTimescale, timeIsFrozen)
end)

-- A client is ready: anchor its clock and send the current weather and wind.
-- syncBaseTime carries the timescale and freeze flag, so nothing else is needed.
AddEventHandler("weathersync:init", function()
    syncStats.playerInits = syncStats.playerInits + 1
    syncStats.lastPlayerInit = os.time()
    debugLog(string.format("Player %d initialized weather sync", source))

    syncBaseTime(source)
    syncWeather(source)
    syncWind(source)
end)

-- ============================================================================
-- MAIN LOOP
-- Advances the internal clock and the weather queue. Runs every syncDelay ms
-- but only touches the network when the weather actually changes.
-- ============================================================================

initBaseTime()

CreateThread(function()
    validateWeatherPattern(weatherPattern)
    generateForecast()

    log("success", "WeatherSync initialized successfully")
    log("info", string.format("Initial weather: %s, time: %s", currentWeather, FormatTime(currentTime)))
    log("info", string.format("Timescale: %.2f, sync delay: %dms", currentTimescale, syncDelay))

    while true do
        -- In-game seconds that pass during one tick
        local tick = currentTimescale == 0
            and syncDelay / 1000
            or currentTimescale * (syncDelay / 1000)

        updateTime()

        if not weatherIsFrozen then
            weatherTicks = weatherTicks + tick

            if weatherTicks >= weatherInterval then
                local nextState = advanceForecast()
                applyWeatherChange(nextState.weather, nextState.wind)
                weatherTicks = 0
            end
        end

        Wait(syncDelay)
    end
end)
