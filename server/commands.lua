-- ============================================================================
-- WeatherSync - server commands
--
-- Admin commands are registered as restricted (ace permissions), see
-- permissions.cfg. Player commands (/forecast, /mytime, ...) are granted to
-- everyone there.
-- ============================================================================

local printMessage = WeatherSync.printMessage

RegisterCommand("weather", function(source, args, raw)
    local weather = args[1] and args[1] or WeatherSync.getWeather()
    local transition = tonumber(args[2]) or 10.0
    local freeze = args[3] == "1"
    local permanentSnow = args[4] == "1"

    if transition <= 0.0 then
        transition = 0.1
    end

    if TableContains(Config.weatherTypes, weather) then
        WeatherSync.setWeather(weather, transition + 0.0, freeze, permanentSnow)
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

        WeatherSync.setTime(d, h, m, s, t, f)
    else
        printMessage(source, {color = {255, 255, 128}, args = {"Time", FormatTime(WeatherSync.getTimeSeconds())}})
    end
end, true)

RegisterCommand("timescale", function(source, args, raw)
    local scale = tonumber(args[1])

    if scale then
        WeatherSync.setTimescale(scale + 0.0)
    else
        printMessage(source, {color = {255, 255, 128}, args = {"Timescale", WeatherSync.getState().timescale}})
    end
end, true)

RegisterCommand("syncdelay", function(source, args, raw)
    local delay = tonumber(args[1])

    if delay and delay >= 100 then
        WeatherSync.setSyncDelay(delay)
    else
        printMessage(source, {color = {255, 255, 128}, args = {"Sync delay", string.format("%dms", WeatherSync.getState().syncDelay)}})
    end
end, true)

RegisterCommand("wind", function(source, args, raw)
    if #args > 0 then
        local direction = (tonumber(args[1]) or 0.0) + 0.0
        local speed = (tonumber(args[2]) or 0.0) + 0.0
        local frozen = args[3] == "1"

        WeatherSync.setWind(direction, speed, frozen)
    end
end, true)

RegisterCommand("forecast", function(source, args, raw)
    if source and source > 0 then
        TriggerClientEvent("weathersync:toggleForecast", source)
    else
        local forecast = WeatherSync.getForecast()

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
        local state = WeatherSync.getState()
        TriggerClientEvent("weathersync:openAdminUi", source, state.weather, state.time, state.timescale, state.windDirection, state.windSpeed, state.syncDelay)
    end
end, true)

RegisterCommand("weathersync", function(source, args, raw)
    if source and source > 0 then
        TriggerClientEvent("weathersync:toggleSync", source)
    end
end, true)

RegisterCommand("mytime", function(source, args, raw)
    if source and source > 0 then
        local h = tonumber(args[1]) or 0
        local m = tonumber(args[2]) or 0
        local s = tonumber(args[3]) or 0
        local t = tonumber(args[4]) or 0

        TriggerClientEvent("weathersync:setMyTime", source, h, m, s, t)
    end
end, true)

RegisterCommand("myweather", function(source, args, raw)
    if source and source > 0 then
        local weather = args[1] and args[1] or WeatherSync.getWeather()
        local transition = tonumber(args[2]) or 5.0
        local permanentSnow = args[3] == "1"

        TriggerClientEvent("weathersync:setMyWeather", source, weather, transition, permanentSnow)
    end
end, true)

RegisterCommand("weatherdebug_sv", function(source, args, raw)
    local enabled = WeatherSync.toggleDebug()
    local message = string.format("Server weather debug: %s", enabled and "enabled" or "disabled")

    WeatherSync.log(enabled and "success" or "default", message)
    printMessage(source, {color = {255, 255, 128}, args = {"WeatherSync", message}})
end, true)

RegisterCommand("weatherstats", function(source, args, raw)
    local state = WeatherSync.getState()
    local stats = WeatherSync.getStats()

    printMessage(source, {color = {100, 200, 255}, args = {"=== Server Weather Stats ==="}})
    printMessage(source, {color = {255, 255, 255}, args = {"Current Weather", state.weather}})
    printMessage(source, {color = {255, 255, 255}, args = {"Current Time", FormatTime(state.time)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Timescale", string.format("%.2f", state.timescale)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Time Frozen", tostring(state.timeFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Frozen", tostring(state.weatherFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Frozen", tostring(state.windFrozen)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Direction", string.format("%.1f° %s", state.windDirection, GetCardinalDirection(state.windDirection))}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Speed", string.format("%.1f", state.windSpeed)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Permanent Snow", tostring(state.permanentSnow)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Sync Delay", string.format("%dms", state.syncDelay)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Interval", string.format("%ds", state.weatherInterval)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Connected Players", #GetPlayers()}})

    printMessage(source, {color = {100, 200, 255}, args = {"=== Sync Statistics ==="}})
    printMessage(source, {color = {255, 255, 255}, args = {"Weather Changes", tostring(stats.weatherChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Time Changes", tostring(stats.timeChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Timescale Changes", tostring(stats.timescaleChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Wind Changes", tostring(stats.windChanges)}})
    printMessage(source, {color = {255, 255, 255}, args = {"Player Inits", tostring(stats.playerInits)}})

    if stats.lastWeatherChange > 0 then
        printMessage(source, {color = {255, 255, 255}, args = {"Last Weather Change", string.format("%ds ago", os.time() - stats.lastWeatherChange)}})
    end

    if stats.lastPlayerInit > 0 then
        printMessage(source, {color = {255, 255, 255}, args = {"Last Player Init", string.format("%ds ago", os.time() - stats.lastPlayerInit)}})
    end
end, true)
