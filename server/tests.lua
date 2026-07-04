-- ============================================================================
-- WeatherSync - server test suite
--
-- Console commands (only when Config.enableTests = true):
--   weathertest              - read-only server tests
--   weathertest full         - adds mutating tests (state is restored)
--   weathertest client <id>  - run the client test suite on player <id>,
--                              results are echoed to this console
--                              (add "full" as the last argument for the full suite)
-- ============================================================================

if not Config.enableTests then
    return
end

local log = WeatherSync.log
local pendingClientTests = {}

RegisterNetEvent("weathersync:clientTestResult")
AddEventHandler("weathersync:clientTestResult", function(line)
    local src = tonumber(source)

    -- Only echo results from players we actually asked to run tests
    if src and pendingClientTests[src] and os.time() - pendingClientTests[src] < 180 then
        print(string.format("[weathertest][player %d] %s", src, tostring(line)))
    end
end)

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
            local pattern = WeatherSync.getWeatherPattern()
            local ok, detail = true, nil

            for weather, choices in pairs(pattern) do
                local sum = 0

                for nextW, chance in pairs(choices) do
                    sum = sum + chance

                    if not pattern[nextW] then
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
            local forecast = WeatherSync.getForecast()
            local ok = #forecast == Config.maxForecast + 1
            local detail = string.format("%d entries (expected %d)", #forecast, Config.maxForecast + 1)

            if ok then
                for i = 1, #forecast do
                    if not TableContains(Config.weatherTypes, forecast[i].weather) then
                        ok, detail = false, string.format("entry %d has invalid weather %s", i, tostring(forecast[i].weather))
                        break
                    end
                end
            end

            if ok and forecast[1].weather ~= WeatherSync.getWeather() then
                ok, detail = false, string.format("first entry %s != current weather %s", forecast[1].weather, WeatherSync.getWeather())
            end

            report("S4 forecast", ok, detail)
        end

        -- S5: nextWeather only produces known weather types
        do
            local pattern = WeatherSync.getWeatherPattern()
            local ok, detail = true, nil

            for weather in pairs(pattern) do
                for i = 1, 50 do
                    local nw = WeatherSync.peekNextWeather(weather)

                    if not pattern[nw] then
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
        if WeatherSync.getState().timeFrozen then
            skip("S6 time progression", "time is frozen")
        else
            local t1 = WeatherSync.getTimeSeconds()

            Wait(3000)

            local state = WeatherSync.getState()
            local scale = state.timescale == 0 and 1 or state.timescale
            local advance = (state.time - t1) % WEEK_SECONDS
            local expected = 3 * scale

            report("S6 time progression", math.abs(advance - expected) <= scale + 2,
                string.format("%ds over 3s (expected ~%ds)", advance, expected))
        end

        -- Mutating tests
        if full then
            -- S7: time set/restore
            do
                local before = WeatherSync.getState()
                local t0 = GetGameTimer()
                local target = DHMSToTime(2, 3, 45, 0)

                WeatherSync.setTime(2, 3, 45, 0, 0, false)

                report("S7 time set", math.abs(WeatherSync.getTimeSeconds() - target) <= 2,
                    string.format("set %s, now %s", FormatTime(target), FormatTime(WeatherSync.getTimeSeconds())))

                -- Restore, compensating for real time spent testing
                local scale = before.timescale == 0 and 1 or before.timescale
                local elapsed = math.floor((GetGameTimer() - t0) / 1000 * scale)
                local rd, rh, rm, rs = TimeToDHMS((before.time + elapsed) % WEEK_SECONDS)
                WeatherSync.setTime(rd, rh, rm, rs, 0, before.timeFrozen)
            end

            -- S8: timescale set/restore
            if WeatherSync.getState().timeFrozen then
                skip("S8 timescale", "time is frozen")
            else
                local orig = WeatherSync.getState().timescale

                WeatherSync.setTimescale(120.0)
                local t1 = WeatherSync.getTimeSeconds()

                Wait(2000)

                local state = WeatherSync.getState()
                local advance = (state.time - t1) % WEEK_SECONDS

                report("S8 timescale", state.timescale == 120.0 and math.abs(advance - 240) <= 130,
                    string.format("advance %ds over 2s (expected ~240s)", advance))

                WeatherSync.setTimescale(orig)
            end

            -- S9: weather set/restore (freeze/snow flags restored exactly)
            do
                local before = WeatherSync.getState()
                local testWeather = before.weather ~= "rain" and "rain" or "clouds"

                WeatherSync.setWeather(testWeather, 0.1, before.weatherFrozen, before.permanentSnow)
                report("S9 weather set", WeatherSync.getWeather() == testWeather,
                    string.format("%s -> %s", before.weather, tostring(WeatherSync.getWeather())))
                WeatherSync.setWeather(before.weather, 2.0, before.weatherFrozen, before.permanentSnow)
            end

            -- S10: wind set/restore
            do
                local before = WeatherSync.getState()

                WeatherSync.setWind(123.0, 4.5, before.windFrozen)
                local state = WeatherSync.getState()

                report("S10 wind set", state.windDirection == 123.0 and state.windSpeed == 4.5,
                    string.format("direction %.1f°, speed %.1f", state.windDirection, state.windSpeed))

                WeatherSync.setWind(before.windDirection, before.windSpeed, before.windFrozen)
            end
        end

        log(failed == 0 and "success" or "error",
            string.format("weathertest done: %d passed, %d failed, %d skipped", passed, failed, skipped))
    end)
end

RegisterCommand("weathertest", function(source, args, raw)
    if source and source > 0 then
        WeatherSync.printMessage(source, {color = {255, 255, 128}, args = {"weathertest", "Use /weathertest in game, or run this command from the server console"}})
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
