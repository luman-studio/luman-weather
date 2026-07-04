-- ============================================================================
-- WeatherSync - shared utilities
-- Loaded on both server and client before config.lua.
-- ============================================================================

DAY_SECONDS = 86400
WEEK_SECONDS = 604800

-- All weather types available in RDR3
RDR2WeatherTypes = {
    "blizzard",
    "clouds",
    "drizzle",
    "fog",
    "groundblizzard",
    "hail",
    "highpressure",
    "hurricane",
    "misty",
    "overcast",
    "overcastdark",
    "rain",
    "sandstorm",
    "shower",
    "sleet",
    "snow",
    "snowlight",
    "sunny",
    "thunder",
    "thunderstorm",
    "whiteout"
}

-- Convert game time in seconds to day of week, hour, minute, second
function TimeToDHMS(time)
    local day = math.floor(time / DAY_SECONDS)
    local hour = math.floor(time / 60 / 60) % 24
    local minute = math.floor(time / 60) % 60
    local second = time % 60

    return day, hour, minute, second
end

-- Convert day of week, hour, minute, second to game time in seconds
function DHMSToTime(day, hour, minute, second)
    return day * DAY_SECONDS + hour * 3600 + minute * 60 + second
end

-- Convert a wind heading in degrees to a cardinal direction label
function GetCardinalDirection(heading)
    if heading <= 22.5 then
        return "N"
    elseif heading <= 67.5 then
        return "NE"
    elseif heading <= 112.5 then
        return "E"
    elseif heading <= 157.5 then
        return "SE"
    elseif heading <= 202.5 then
        return "S"
    elseif heading <= 247.5 then
        return "SW"
    elseif heading <= 292.5 then
        return "W"
    elseif heading <= 337.5 then
        return "NW"
    else
        return "N"
    end
end

function GetDayOfWeek(day)
    return ({"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"})[day + 1]
end

-- Format game time in seconds as "Sun 06:00:00"
function FormatTime(time)
    local day, hour, minute, second = TimeToDHMS(time)
    return string.format("%s %.2d:%.2d:%.2d", GetDayOfWeek(day), hour, minute, second)
end

-- Absolute difference between two values on a circular scale
-- (e.g. day or week time, where 23:59 and 00:01 are 2 minutes apart)
function WrapDiff(a, b, period)
    local diff = math.abs(a - b) % period

    if diff > period / 2 then
        diff = period - diff
    end

    return diff
end

function TableContains(t, value)
    for _, v in pairs(t) do
        if v == value then
            return true
        end
    end

    return false
end
