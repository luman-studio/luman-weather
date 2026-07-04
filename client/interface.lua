-- ============================================================================
-- WeatherSync - client interface (NUI)
--
-- The forecast widget (/forecast) and the admin UI (/weatherui). While either
-- is open, the client polls the server once a second for fresh data; when
-- both are closed there is no traffic.
-- ============================================================================

local forecastIsDisplayed = false
local adminUiIsOpen = false

-- ============================================================================
-- FORECAST WIDGET
-- ============================================================================

local function updateForecast(forecast)
    local h24 = ShouldUse_24HourClock()

    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local x, y, z = table.unpack(pos)

    for i = 1, #forecast do
        if h24 then
            forecast[i].time = string.format("%.2d:%.2d", forecast[i].hour, forecast[i].minute)
        else
            local h = forecast[i].hour % 12
            forecast[i].time = string.format(
                "%d:%.2d %s",
                h == 0 and 12 or h,
                forecast[i].minute,
                forecast[i].hour > 12 and "PM" or "AM")
        end

        forecast[i].weather = WeatherSync.translateWeatherForRegion(forecast[i].weather, x, y, z)
        forecast[i].wind = GetCardinalDirection(forecast[i].wind)
    end

    local metric = ShouldUseMetricTemperature()

    local temperature, temperatureUnit
    if metric then
        temperature = math.floor(GetTemperatureAtCoords(x, y, z))
        temperatureUnit = "C"
    else
        temperature = math.floor(GetTemperatureAtCoords(x, y, z) * 9 / 5 + 32)
        temperatureUnit = "F"
    end

    local windSpeed, windSpeedUnit
    if metric then
        windSpeed = math.floor(GetWindSpeed() * 3.6)
        windSpeedUnit = "kph"
    else
        windSpeed = math.floor(GetWindSpeed() * 3.6 * 0.621371)
        windSpeedUnit = "mph"
    end

    local state = WeatherSync.getState()

    SendNUIMessage({
        action = "updateForecast",
        forecast = json.encode(forecast),
        temperature = string.format("%d °%s", temperature, temperatureUnit),
        wind = string.format("🌬️ %d %s %s", windSpeed, windSpeedUnit, GetCardinalDirection(state.windDirection)),
        syncEnabled = state.syncEnabled,
        altitudeSea = string.format("%d", math.floor(pos.z - WeatherSync.MEAN_SEA_LEVEL)),
        altitudeTerrain = string.format("%d", math.floor(GetEntityHeightAboveGround(ped)))
    })
end

RegisterNetEvent("weathersync:toggleForecast")
RegisterNetEvent("weathersync:updateForecast")

AddEventHandler("weathersync:updateForecast", updateForecast)

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

-- ============================================================================
-- ADMIN UI
-- ============================================================================

local function buildAdminUiMessage(action, weather, time, timescale, windDirection, windSpeed, syncDelay)
    local d, h, m, s = TimeToDHMS(time)

    return {
        action = action,
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
    }
end

RegisterNetEvent("weathersync:openAdminUi")
RegisterNetEvent("weathersync:updateAdminUi")

AddEventHandler("weathersync:openAdminUi", function(weather, time, timescale, windDirection, windSpeed, syncDelay)
    adminUiIsOpen = true

    SetNuiFocus(true, true)
    SendNUIMessage(buildAdminUiMessage("openAdminUi", weather, time, timescale, windDirection, windSpeed, syncDelay))

    CreateThread(function()
        while adminUiIsOpen do
            TriggerServerEvent("weathersync:requestUpdatedAdminUi")
            Wait(1000)
        end
    end)
end)

AddEventHandler("weathersync:updateAdminUi", function(weather, time, timescale, windDirection, windSpeed, syncDelay)
    SendNUIMessage(buildAdminUiMessage("updateAdminUi", weather, time, timescale, windDirection, windSpeed, syncDelay))
end)

-- ============================================================================
-- NUI CALLBACKS
-- All mutating callbacks go through server events, which are permission-gated
-- ============================================================================

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
