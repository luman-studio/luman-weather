# Configuration

Everything is in `config.lua`. The defaults work out of the box — you only
need this page to customize.

## Time

| Option | Default | What it does |
|---|---|---|
| `Config.timescale` | `0` | In-game seconds per real second. `0` = clock mirrors the real server clock. `30` = standard game speed (full day in 48 real minutes). |
| `Config.timezoneOffset` | `0` | Shift the real-time clock by N hours (e.g. `3` for UTC+3). Only used when `timescale = 0`. |
| `Config.time` | `nil` | Fixed starting time, e.g. `DHMSToTime(0, 6, 0, 0)` = Sunday 06:00. `nil` = automatic. |
| `Config.timeIsFrozen` | `false` | Start with the clock stopped. |

**Popular setups:**

```lua
-- Real time, players mostly in UTC+3
Config.timescale = 0
Config.timezoneOffset = 3
```

```lua
-- Classic RDR2 pace: full day-night cycle every 48 real minutes
Config.timescale = 30
Config.time = DHMSToTime(0, 6, 0, 0)
```

```lua
-- Slow roleplay days: one cycle every 2 real hours
Config.timescale = 12
```

## Weather

| Option | Default | What it does |
|---|---|---|
| `Config.weather` | `"sunny"` | Starting weather. |
| `Config.weatherInterval` | 1 in-game hour | How often the weather changes (in game time). |
| `Config.weatherIsFrozen` | `false` | Start with weather changes disabled. |
| `Config.maxForecast` | `23` | How many upcoming changes the `/forecast` shows. |
| `Config.dynamicSnow` | `false` | Put snow on the ground during snowy weather / in snowy regions. |
| `Config.permanentSnow` | `false` | Snow on the ground everywhere, always (winter events). |

### How weather changes

`Config.weatherPattern` decides what comes after what. For each weather type,
list what can follow with a percentage (must total 100):

```lua
["sunny"] = {
    ["sunny"]  = 60,   -- usually stays sunny
    ["clouds"] = 40    -- sometimes clouds roll in
},
```

The default pattern gives mild, believable weather with occasional storms.
If you break a rule (sum ≠ 100, unknown weather type), the server console
tells you exactly where at startup.

### Regional weather

Applied automatically on each client — no configuration needed:

| Server weather | In the mountains | In the desert | On Guarma |
|---|---|---|---|
| rain / drizzle / shower | snow | thunder / sunny | — |
| thunderstorm / hurricane | blizzard / whiteout | rain / sandstorm | — |
| snow / blizzard | — | — | sunny |

Full table and the region boundaries: see `regionWeatherRules` in
`client/main.lua`.

## Wind

| Option | Default | What it does |
|---|---|---|
| `Config.windDirection` | `0.0` | Starting direction in degrees (0 = North). |
| `Config.windSpeed` | `0.0` | Base speed. |
| `Config.windShear*` | — | Wind gets stronger and shifts direction at altitude. Defaults are fine for most servers. |

## Other

| Option | Default | What it does |
|---|---|---|
| `Config.Notify` | `false` | Chat message when a player toggles `/weathersync`. |
| `Config.syncDelay` | `5000` | Internal server tick in ms. Does **not** create network traffic — no need to touch it. |
| `Config.enableTests` | `false` | Enables `/weathertest`. Keep off in production. |

## Weather types

`sunny`, `highpressure`, `clouds`, `overcast`, `overcastdark`, `misty`,
`fog`, `drizzle`, `shower`, `rain`, `thunder`, `thunderstorm`, `hurricane`,
`sleet`, `hail`, `snowlight`, `snow`, `blizzard`, `groundblizzard`,
`whiteout`, `sandstorm`
