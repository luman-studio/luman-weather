-- ============================================================================
-- WeatherSync - client test suite
--
-- Only active when Config.enableTests = true.
--   /weathertest       - read-only tests
--   /weathertest full  - adds mutating tests that change and then restore
--                        server time/weather/timescale/wind (requires the
--                        same ace permissions as the admin commands)
--
-- Can also be launched remotely from the server console:
--   weathertest client <id> [full]
-- ============================================================================

if not Config.enableTests then
    return
end

local testRunning = false

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
            local got = WeatherSync.translateWeatherForRegion(c[1], c[2], c[3], 0.0)
            if got ~= c[4] then
                ok, detail = false, string.format("%s in %s -> %s, expected %s", c[1], c[5], got, c[4])
                break
            end
        end

        report("T3 region translation", ok, detail)
    end

    -- T4: initialization completed and server state received
    local state = WeatherSync.getState()
    report("T4 init", state.initialized and state.baseNetworkTime > 0 and state.serverWeather ~= nil,
        string.format("initialized=%s, timeSynced=%s, weather=%s",
            tostring(state.initialized), tostring(state.baseNetworkTime > 0), tostring(state.serverWeather)))

    -- T5: client state vs authoritative server state
    local server = WeatherSync.fetchServerState()

    if not server then
        report("T5 server sync", false, "no response from server within 3s")
    else
        state = WeatherSync.getState()

        local scale = server.timescale == 0 and 1 or server.timescale
        local tolerance = scale * 2 + 5

        local timeDiff = WrapDiff(WeatherSync.computeLocalTime(), server.time, WEEK_SECONDS)
        report("T5a time sync", timeDiff <= tolerance, string.format("diff %ds (tolerance %ds)", timeDiff, tolerance))

        local clockDiff = WrapDiff(gameClockTime(), WeatherSync.computeLocalTime() % DAY_SECONDS, DAY_SECONDS)
        report("T5b game clock", clockDiff <= tolerance, string.format("diff %ds", clockDiff))

        report("T5c weather received", state.serverWeather == server.weather,
            string.format("server %s, client %s", server.weather, tostring(state.serverWeather)))

        local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
        local expected = WeatherSync.translateWeatherForRegion(server.weather, x, y, z)
        report("T5d weather applied", state.weather == expected,
            string.format("expected %s, applied %s", expected, tostring(state.weather)))

        report("T5e wind", state.serverWindDirection == server.windDirection and state.serverWindSpeed == server.windSpeed,
            string.format("server %.1f°/%.1f, client %s/%.1f", server.windDirection, server.windSpeed,
                state.serverWindDirection and string.format("%.1f°", state.serverWindDirection) or "none", state.serverWindSpeed))

        report("T5f timescale", state.timescale == server.timescale,
            string.format("server %.2f, client %.2f", server.timescale, state.timescale))

        report("T5g frozen flag", state.timeFrozen == server.frozen,
            string.format("server %s, client %s", tostring(server.frozen), tostring(state.timeFrozen)))
    end

    -- T6: clock advances at the expected rate
    state = WeatherSync.getState()

    if state.timeFrozen then
        skip("T6 clock advance", "time is frozen")
    else
        local scale = state.timescale == 0 and 1 or state.timescale
        local t1 = WeatherSync.computeLocalTime()
        local c1 = gameClockTime()

        say({255, 255, 255}, "T6", "measuring clock advance over 4s...")
        Wait(4000)

        local computedAdvance = (WeatherSync.computeLocalTime() - t1) % WEEK_SECONDS
        local clockAdvance = (gameClockTime() - c1) % DAY_SECONDS
        local expected = 4 * scale
        local tol = 2 * scale + 3

        report("T6a computed time advance", math.abs(computedAdvance - expected) <= tol,
            string.format("%ds over 4s (expected ~%ds)", computedAdvance, expected))
        report("T6b in-game clock advance", math.abs(clockAdvance - expected) <= tol,
            string.format("%ds over 4s (expected ~%ds)", clockAdvance, expected))
    end

    -- T7: no sync traffic while idle
    do
        local stats = WeatherSync.getDebugStats()
        local w1, t1 = stats.weatherSyncCount, stats.timeSyncCount

        say({255, 255, 255}, "T7", "monitoring network traffic for 5s...")
        Wait(5000)

        local dw = stats.weatherSyncCount - w1
        local dt = stats.timeSyncCount - t1

        report("T7 idle traffic", dw == 0 and dt == 0,
            (dw == 0 and dt == 0) and "no sync events received"
            or string.format("%d weather / %d time events (could be a scheduled weather change — rerun to confirm)", dw, dt))
    end

    -- Mutating tests
    if not full then
        say({255, 255, 255}, "weathertest", "read-only tests done; run '/weathertest full' to also test set/restore of time, weather, timescale and wind (requires admin permissions)")
    else
        local st = WeatherSync.fetchServerState()

        if not st then
            skip("T8-T11", "no response from server")
        else
            -- T8: weather set/restore
            local origSnow = WeatherSync.getState().serverPermanentSnow
            local testWeather = st.weather ~= "rain" and "rain" or "clouds"

            TriggerServerEvent("weathersync:setWeather", testWeather, 0.1, false, false)
            local canMutate = pollUntil(3000, function() return WeatherSync.getState().serverWeather == testWeather end)

            if not canMutate then
                skip("T8-T11", "no weather event within 3s — missing admin permissions (command.weather etc.)?")
            else
                local x, y, z = table.unpack(GetEntityCoords(PlayerPedId()))
                local applied = WeatherSync.getState().weather
                report("T8 weather set", applied == WeatherSync.translateWeatherForRegion(testWeather, x, y, z),
                    string.format("set %s, applied %s", testWeather, tostring(applied)))

                TriggerServerEvent("weathersync:setWeather", st.weather, 2.0, false, origSnow)
                pollUntil(3000, function() return WeatherSync.getState().serverWeather == st.weather end)

                -- T9: time set/restore
                local before = WeatherSync.fetchServerState()

                if before then
                    local target = DHMSToTime(2, 3, 45, 0)
                    local startTimer = GetGameTimer()
                    local scale = before.timescale == 0 and 1 or before.timescale

                    TriggerServerEvent("weathersync:setTime", 2, 3, 45, 0, 0, false)
                    local okSet = pollUntil(3000, function() return WrapDiff(WeatherSync.getState().baseGameTime, target, WEEK_SECONDS) <= 5 end)

                    local clockOk = false
                    if okSet then
                        pollUntil(2500, function() return WrapDiff(gameClockTime(), target % DAY_SECONDS, DAY_SECONDS) <= scale * 3 + 5 end)
                        clockOk = WrapDiff(gameClockTime(), target % DAY_SECONDS, DAY_SECONDS) <= scale * 3 + 5
                    end

                    report("T9 time set", okSet and clockOk,
                        okSet and string.format("target Tue 03:45, in-game %.2d:%.2d:%.2d", GetClockHours(), GetClockMinutes(), GetClockSeconds())
                        or "changeTime event not received")

                    -- Restore original time, compensating for real time spent testing
                    local elapsed = math.floor((GetGameTimer() - startTimer) / 1000 * scale)
                    local rd, rh, rm, rs = TimeToDHMS((before.time + elapsed) % WEEK_SECONDS)
                    TriggerServerEvent("weathersync:setTime", rd, rh, rm, rs, 0, before.frozen)
                    Wait(500)
                else
                    skip("T9 time set", "no server response")
                end

                -- T10: timescale set/restore, checks speed and absence of time jumps
                local st10 = WeatherSync.fetchServerState()

                if st10 then
                    local oldScale = st10.timescale == 0 and 1 or st10.timescale
                    local t0 = WeatherSync.computeLocalTime()

                    TriggerServerEvent("weathersync:setTimescale", 120.0)
                    local okScale = pollUntil(3000, function() return WeatherSync.getState().timescale == 120.0 end)

                    if okScale then
                        local t1 = WeatherSync.computeLocalTime()
                        local jump = WrapDiff(t1, t0, WEEK_SECONDS)
                        local noJump = jump <= oldScale * 4 + 10

                        Wait(3000)

                        local advance = (WeatherSync.computeLocalTime() - t1) % WEEK_SECONDS
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
                local st11 = WeatherSync.fetchServerState()

                if st11 then
                    TriggerServerEvent("weathersync:setWind", 123.0, 4.5, false)
                    local okWind = pollUntil(3000, function()
                        local s = WeatherSync.getState()
                        return s.serverWindDirection == 123.0 and s.serverWindSpeed == 4.5
                    end)

                    report("T11 wind", okWind, okWind and "changeWind received and applied" or "changeWind event not received")

                    TriggerServerEvent("weathersync:setWind", st11.windDirection, st11.windSpeed, false)
                    pollUntil(2000, function() return WeatherSync.getState().serverWindDirection == st11.windDirection end)
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

    if not WeatherSync.getState().syncEnabled then
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

RegisterCommand("weathertest", function(source, args, raw)
    startTestSuite(args[1] == "full", false)
end, false)

RegisterNetEvent("weathersync:runClientTests")
AddEventHandler("weathersync:runClientTests", function(full)
    startTestSuite(full, true)
end)

AddEventHandler("weathersync:clientReady", function()
    TriggerEvent("chat:addSuggestion", "/weathertest", "Run the weather sync test suite", {
        {name = "full", help = "add 'full' to also test set/restore of time/weather/wind (admin only)"}
    })
end)
