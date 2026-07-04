# API (exports)

For integrating WeatherSync with your own resources — seasons, photo modes,
quests, hunting scripts.

## Server

```lua
-- Read
local time     = exports.weathersync:getTime()      -- {day, hour, minute, second}
local weather  = exports.weathersync:getWeather()   -- "sunny"
local wind     = exports.weathersync:getWind()      -- {direction, speed}
local forecast = exports.weathersync:getForecast()  -- {{day, hour, ..., weather, wind}, ...}

-- Write (broadcast to all players immediately)
exports.weathersync:setWeather(weather, transitionSec, freeze, permanentSnow)
exports.weathersync:setTime(day, hour, minute, second, transitionMs, freeze)
exports.weathersync:setTimescale(scale)             -- 0 = real time
exports.weathersync:setWind(direction, speed, freeze)
exports.weathersync:setWeatherPattern(pattern)      -- same format as config

-- Reset to config defaults
exports.weathersync:resetWeather()
exports.weathersync:resetTime()
exports.weathersync:resetTimescale()
exports.weathersync:resetWind()
exports.weathersync:resetWeatherPattern()
```

### Example: winter season

```lua
exports.weathersync:setWeatherPattern({
    ["snowlight"] = { ["snowlight"] = 50, ["snow"] = 30, ["clouds"] = 20 },
    ["snow"]      = { ["snow"] = 40, ["snowlight"] = 40, ["blizzard"] = 20 },
    ["blizzard"]  = { ["snow"] = 70, ["blizzard"] = 30 },
    ["clouds"]    = { ["clouds"] = 40, ["snowlight"] = 60 }
})
exports.weathersync:setWeather("snow", 30.0, false, true)  -- true = snow on the ground
```

## Client

```lua
-- Is there snow on the ground? (for footprints, sounds, etc.)
local snowy = exports.weathersync:isSnowOnGround()

-- Personal time/weather for this player only (detaches from sync)
exports.weathersync:setMyTime(hour, minute, second, transitionMs)
exports.weathersync:setMyWeather(weather, transitionSec, permanentSnow)

-- Attach/detach from server sync
exports.weathersync:setSyncEnabled(true)
exports.weathersync:toggleSync()
```

### Example: photo mode

```lua
-- while the camera is open
exports.weathersync:setMyTime(19, 30, 0, 500)

-- when it closes
exports.weathersync:setSyncEnabled(true)
```

## Events

Everything above is also available as `weathersync:*` server events
(`TriggerEvent("weathersync:setWeather", ...)` from server code works like
the export). Events arriving **from clients** are checked against the same
ace permissions as the admin commands, so players can't abuse them.
