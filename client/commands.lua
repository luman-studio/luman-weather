-- ============================================================================
-- WeatherSync - client commands
--
-- Diagnostics and local-only commands. Everything here is read-only or
-- affects only this client; server state is changed via server commands.
-- ============================================================================

local function chatMessage(color, ...)
    TriggerEvent("chat:addMessage", {color = color, args = {...}})
end

-- ============================================================================
-- /synccheck
-- Compares the authoritative server state against everything computed and
-- applied locally. All checks should report OK on a healthy server.
-- ============================================================================

RegisterCommand("synccheck", function(source, args, raw)
    CreateThread(function()
        local state = WeatherSync.getState()

        chatMessage({100, 200, 255}, "=== Sync Check ===")

        if not state.syncEnabled then
            chatMessage({255, 255, 0}, "WARNING", "sync is disabled (/weathersync) — all checks below are expected to fail")
        end

        if not state.initialized then
            chatMessage({255, 80, 80}, "WARNING", "client init() never ran")
        elseif state.baseNetworkTime == 0 then
            chatMessage({255, 80, 80}, "WARNING", "init() ran but no syncBaseTime received from the server yet")
        end

        local server = WeatherSync.fetchServerState(3000)

        if not server then
            chatMessage({255, 80, 80}, "FAIL", "no response from the server within 3s")
            return
        end

        local function report(label, passed, detail)
            local status = passed and "OK" or "FAIL"
            chatMessage(passed and {50, 255, 50} or {255, 80, 80}, label, status .. " — " .. detail)
            print(string.format("[synccheck] %s: %s — %s", label, status, detail))
        end

        -- Client clock ticks once a second and events have latency, so allow
        -- up to ~2 ticks of drift
        local scale = server.timescale == 0 and 1 or server.timescale
        local tolerance = scale * 2 + 5

        -- 1. Locally computed game time vs authoritative server time
        local localTime = WeatherSync.computeLocalTime()
        local diff = WrapDiff(localTime, server.time, WEEK_SECONDS)

        report("TIME", diff <= tolerance,
            string.format("server %s, client %s, diff %ds (tolerance %ds)", FormatTime(server.time), FormatTime(localTime), diff, tolerance))

        -- 2. The actual in-game clock vs what we computed (checks the override applied)
        local clockTime = GetClockHours() * 3600 + GetClockMinutes() * 60 + GetClockSeconds()
        local clockDiff = WrapDiff(clockTime, localTime % DAY_SECONDS, DAY_SECONDS)

        report("GAME CLOCK", clockDiff <= tolerance,
            string.format("in-game %.2d:%.2d:%.2d, computed %s, diff %ds", GetClockHours(), GetClockMinutes(), GetClockSeconds(), FormatTime(localTime), clockDiff))

        -- 3. Last weather received from the server vs the server's actual state
        report("WEATHER EVENT", state.serverWeather == server.weather,
            string.format("server %s, received %s", server.weather, tostring(state.serverWeather)))

        -- 4. Weather actually applied vs what should be applied in this region
        local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
        local expectedWeather = WeatherSync.translateWeatherForRegion(server.weather, x, y, z)

        report("WEATHER APPLIED", state.weather == expectedWeather,
            string.format("expected %s, applied %s (region monitor updates every 5s)", expectedWeather, tostring(state.weather)))

        -- 5. Wind, timescale, freeze flag
        report("WIND", state.serverWindDirection == server.windDirection and state.serverWindSpeed == server.windSpeed,
            string.format("server %.1f°/%.1f, received %s/%.1f", server.windDirection, server.windSpeed,
                state.serverWindDirection and string.format("%.1f°", state.serverWindDirection) or "none", state.serverWindSpeed))

        report("TIMESCALE", state.timescale == server.timescale,
            string.format("server %.2f, client %.2f", server.timescale, state.timescale))

        report("TIME FROZEN", state.timeFrozen == server.frozen,
            string.format("server %s, client %s", tostring(server.frozen), tostring(state.timeFrozen)))
    end)
end, false)

-- ============================================================================
-- /weatherstatus
-- ============================================================================

RegisterCommand("weatherstatus", function(source, args, raw)
    local state = WeatherSync.getState()

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local x, y, z = table.unpack(pos)

    local metric = ShouldUseMetricTemperature()
    local temp = metric and math.floor(GetTemperatureAtCoords(x, y, z)) or math.floor(GetTemperatureAtCoords(x, y, z) * 9 / 5 + 32)
    local tempUnit = metric and "C" or "F"

    local windSpeed = metric and math.floor(GetWindSpeed() * 3.6) or math.floor(GetWindSpeed() * 3.6 * 0.621371)
    local windUnit = metric and "kph" or "mph"

    chatMessage({100, 200, 255}, "=== Weather Sync Status ===")
    chatMessage({255, 255, 255}, "Sync Enabled", tostring(state.syncEnabled))
    chatMessage({255, 255, 255}, "Weather", state.weather or "unknown")
    chatMessage({255, 255, 255}, "Time", FormatTime(WeatherSync.computeLocalTime()))
    chatMessage({255, 255, 255}, "Timescale", string.format("%.2f", state.timescale))
    chatMessage({255, 255, 255}, "Time Frozen", tostring(state.timeFrozen))
    chatMessage({255, 255, 255}, "Temperature", string.format("%d °%s", temp, tempUnit))
    chatMessage({255, 255, 255}, "Wind", string.format("%d %s %s", windSpeed, windUnit, GetCardinalDirection(state.windDirection)))
    chatMessage({255, 255, 255}, "Altitude (Sea)", string.format("%dm", math.floor(pos.z - WeatherSync.MEAN_SEA_LEVEL)))
    chatMessage({255, 255, 255}, "Altitude (Ground)", string.format("%dm", math.floor(GetEntityHeightAboveGround(ped))))
    chatMessage({255, 255, 255}, "Snow on Ground", tostring(state.snowOnGround))
    chatMessage({255, 255, 255}, "Region", WeatherSync.getRegionName(x, y, z))
    chatMessage({255, 255, 255}, "Position", string.format("%.1f, %.1f, %.1f", x, y, z))

    local stats = WeatherSync.getDebugStats()

    chatMessage({100, 200, 255}, "=== Sync Events Received ===")
    chatMessage({255, 255, 255}, "Weather Syncs", tostring(stats.weatherSyncCount))
    chatMessage({255, 255, 255}, "Time Syncs", tostring(stats.timeSyncCount))
    chatMessage({255, 255, 255}, "Wind Syncs", tostring(stats.windSyncCount))
end, false)

-- ============================================================================
-- /weatherdebug and /testweather
-- ============================================================================

RegisterCommand("weatherdebug", function(source, args, raw)
    local enabled = WeatherSync.toggleDebug()
    chatMessage({255, 255, 128}, "WeatherSync Debug", enabled and "Enabled" or "Disabled")
end, false)

-- Locally preview a weather type with region translation applied
RegisterCommand("testweather", function(source, args, raw)
    if not args[1] then
        chatMessage({255, 0, 0}, "Error", "Please specify a weather type")
        return
    end

    if not TableContains(Config.weatherTypes, args[1]) then
        chatMessage({255, 0, 0}, "Error", "Invalid weather type: " .. args[1])
        chatMessage({255, 255, 128}, "Available types", table.concat(Config.weatherTypes, ", "))
        return
    end

    local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
    local translatedWeather = WeatherSync.translateWeatherForRegion(args[1], x, y, z)

    chatMessage({100, 255, 100}, "Test Weather", string.format("Testing %s -> %s", args[1], translatedWeather))

    WeatherSync.setWeatherNative(translatedWeather, 5.0)

    if WeatherSync.isSnowyWeather(translatedWeather) then
        WeatherSync.setSnowCoverage(3)
    end
end, false)

-- ============================================================================
-- CHAT SUGGESTIONS
-- ============================================================================

AddEventHandler("weathersync:clientReady", function()
    TriggerEvent("chat:addSuggestion", "/forecast", "Toggle display of weather forecast", {})

    TriggerEvent("chat:addSuggestion", "/syncdelay", "Change the server tick interval", {
        {name = "delay", help = "The time in milliseconds between server ticks"}
    })

    TriggerEvent("chat:addSuggestion", "/time", "Change the time", {
        {name = "day", help = "0 = Sun, 1 = Mon, 2 = Tue, 3 = Wed, 4 = Thu, 5 = Fri, 6 = Sat"},
        {name = "hour", help = "0-23"},
        {name = "minute", help = "0-59"},
        {name = "second", help = "0-59"},
        {name = "transition", help = "Transition time in milliseconds"},
        {name = "freeze", help = "0 = don't freeze time, 1 = freeze time"}
    })

    TriggerEvent("chat:addSuggestion", "/timescale", "Change the rate at which time passes", {
        {name = "scale", help = "In-game seconds per real second (0 = real time)"}
    })

    TriggerEvent("chat:addSuggestion", "/weather", "Change the weather", {
        {name = "type", help = "The type of weather to change to"},
        {name = "transition", help = "Transition time in seconds"},
        {name = "freeze", help = "0 = don't freeze weather, 1 = freeze weather"},
        {name = "snow", help = "0 = temporary snow coverage, 1 = permanent snow coverage"}
    })

    TriggerEvent("chat:addSuggestion", "/weatherui", "Open weather admin UI", {})

    TriggerEvent("chat:addSuggestion", "/wind", "Change wind direction and speed", {
        {name = "direction", help = "Direction of the wind in degrees"},
        {name = "speed", help = "Minimum wind speed"},
        {name = "freeze", help = "0 = don't freeze wind, 1 = freeze wind"}
    })

    TriggerEvent("chat:addSuggestion", "/weathersync", "Enable/disable weather and time sync", {})

    TriggerEvent("chat:addSuggestion", "/mytime", "Change local time (disables sync)", {
        {name = "hour", help = "0-23"},
        {name = "minute", help = "0-59"},
        {name = "second", help = "0-59"},
        {name = "transition", help = "Transition time in milliseconds"}
    })

    TriggerEvent("chat:addSuggestion", "/myweather", "Change local weather (disables sync)", {
        {name = "type", help = "The type of weather to change to"},
        {name = "transition", help = "Transition time in seconds"},
        {name = "snow", help = "0 = no snow on ground, 1 = snow on ground"}
    })

    TriggerEvent("chat:addSuggestion", "/synccheck", "Compare local weather/time state with the server", {})
    TriggerEvent("chat:addSuggestion", "/weatherstatus", "Display current weather/time sync status", {})
    TriggerEvent("chat:addSuggestion", "/weatherdebug", "Toggle weather sync debug mode", {})

    TriggerEvent("chat:addSuggestion", "/testweather", "Locally preview a weather type", {
        {name = "weather", help = "Weather type to test"}
    })
end)
