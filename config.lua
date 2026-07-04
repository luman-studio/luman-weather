-- ============================================================================
-- WeatherSync - configuration
-- Full documentation: docs/getting-started/configuration.md
-- ============================================================================

Config = {}

-- ============================================================================
-- GENERAL
-- ============================================================================

-- Show a chat notification when a player toggles sync with /weathersync
Config.Notify = false

-- Enable the automated test suite commands: /weathertest (in game) and
-- weathertest (server console). Keep disabled on production servers;
-- /synccheck diagnostics stays available regardless of this setting.
Config.enableTests = false

-- Weather types available to /weather, /myweather and the admin UI
Config.weatherTypes = RDR2WeatherTypes

-- ============================================================================
-- TIME
-- ============================================================================

-- Time when the resource starts (game time in seconds).
--   nil                     = use the real server clock (when timescale is 0)
--                             or start at Sun 00:00 (when timescale > 0)
--   DHMSToTime(0, 6, 0, 0)  = always start at Sun 06:00
Config.time = nil

-- In-game seconds per real second.
--   0  = sync the in-game clock with the real server clock (1:1)
--   30 = standard game speed (1 in-game minute every 2 real seconds)
Config.timescale = 0

-- Timezone offset in hours relative to the server clock (e.g. 3 for UTC+3,
-- -5 for UTC-5). Only used when Config.timescale = 0 and Config.time = nil.
Config.timezoneOffset = 0

-- Freeze time when the resource starts
Config.timeIsFrozen = false

-- ============================================================================
-- WEATHER
-- ============================================================================

-- Weather when the resource starts
Config.weather = "sunny"

-- Interval between weather changes (game time in seconds)
Config.weatherInterval = DHMSToTime(0, 1, 0, 0)

-- Freeze weather when the resource starts
Config.weatherIsFrozen = false

-- Keep snow on the ground permanently, regardless of weather
Config.permanentSnow = false

-- Add snow on the ground dynamically when:
--   a) the player is in the snowy area of the map, or
--   b) the player is in the northern part of the map during snowy weather
Config.dynamicSnow = false

-- Number of weather intervals to queue for the forecast
Config.maxForecast = 23

-- ============================================================================
-- WIND
-- ============================================================================

-- Wind direction in degrees when the resource starts (0 = North)
Config.windDirection = 0.0

-- Base wind speed when the resource starts
Config.windSpeed = 0.0

-- Freeze wind direction when the resource starts
Config.windIsFrozen = false

-- Degrees by which wind direction shifts per altitude interval
Config.windShearDirection = 45

-- Amount by which wind speed increases per altitude interval
Config.windShearSpeed = 2.0

-- Altitude interval in metres for wind shear
Config.windShearInterval = 50.0

-- ============================================================================
-- SYNC
-- ============================================================================

-- Server tick interval in milliseconds. This only controls how often the
-- server advances its internal clock and weather queue - it does NOT cause
-- network traffic. Clients are only messaged when something actually changes.
Config.syncDelay = 5000

-- ============================================================================
-- WEATHER PATTERN
-- ============================================================================
-- For every weather type that may occur, list the types that may follow it
-- with a percentage chance. The chances for each type must add up to 100.
--
-- Example:
--     ["sunny"] = {
--         ["sunny"]  = 50,
--         ["clouds"] = 50
--     }
-- means sunny weather is followed by sunny (50%) or clouds (50%).
--
-- Every weather type referenced here must also have its own entry.

Config.weatherPattern = {
    ["sunny"] = {
        ["sunny"]  = 60,
        ["clouds"] = 40
    },

    ["clouds"] = {
        ["clouds"]       = 25,
        ["sunny"]        = 40,
        ["misty"]        = 10,
        ["fog"]          = 10,
        ["overcastdark"] = 15
    },

    ["overcastdark"] = {
        ["overcastdark"] = 5,
        ["clouds"]       = 60,
        ["overcast"]     = 30,
        ["thunder"]      = 5
    },

    ["misty"] = {
        ["misty"]  = 25,
        ["clouds"] = 50,
        ["fog"]    = 25
    },

    ["fog"] = {
        ["fog"]      = 25,
        ["clouds"]   = 25,
        ["misty"]    = 25,
        ["overcast"] = 25
    },

    ["overcast"] = {
        ["overcast"]     = 5,
        ["overcastdark"] = 40,
        ["drizzle"]      = 30,
        ["shower"]       = 10,
        ["rain"]         = 15,
    },

    ["drizzle"] = {
        ["drizzle"]      = 10,
        ["overcast"]     = 10,
        ["rain"]         = 10,
        ["shower"]       = 10,
        ["overcastdark"] = 30,
        ["clouds"]       = 30
    },

    ["rain"] = {
        ["rain"]         = 5,
        ["overcastdark"] = 55,
        ["drizzle"]      = 20,
        ["shower"]       = 5,
        ["thunderstorm"] = 10,
        ["hurricane"]    = 5
    },

    ["thunder"] = {
        ["thunder"]      = 10,
        ["overcastdark"] = 50,
        ["thunderstorm"] = 40
    },

    ["thunderstorm"] = {
        ["thunderstorm"] = 5,
        ["thunder"]      = 35,
        ["rain"]         = 30,
        ["drizzle"]      = 20,
        ["shower"]       = 10
    },

    ["hurricane"] = {
        ["hurricane"] = 5,
        ["rain"]      = 30,
        ["drizzle"]   = 65
    },

    ["shower"] = {
        ["shower"]       = 5,
        ["overcast"]     = 10,
        ["overcastdark"] = 85
    }
}
