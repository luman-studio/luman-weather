# Commands

## Admin

| Command | Example | Description |
|---|---|---|
| `/weatherui` | | Open the admin panel — weather, time, timescale and wind in one place. |
| `/weather <type> [transition s] [freeze 0/1] [snow 0/1]` | `/weather rain 10` | Change the weather for everyone. |
| `/time <day> <hour> <min> <sec>` | `/time 0 21 30 0` | Set the time (day: 0 = Sun … 6 = Sat). Without arguments — show current time. |
| `/timescale <n>` | `/timescale 30` | In-game seconds per real second. `0` = real time. |
| `/wind <direction°> <speed> [freeze 0/1]` | `/wind 90 3` | Set wind direction and speed. |

Freeze examples: `/weather snow 10 1` locks the weather on snow;
`/time 0 12 0 0 0 1` stops the clock at noon. Repeat without the flag to
unlock.

## Players

| Command | Description |
|---|---|
| `/forecast` | Show/hide the weather forecast widget. |
| `/weathersync` | Detach from / re-attach to the server weather and time. |
| `/mytime <h> <m> <s>` | Personal local time (detaches automatically). |
| `/myweather <type> [transition s] [snow 0/1]` | Personal local weather (detaches automatically). |

Personal settings affect only that player. `/weathersync` snaps them back to
the server state.

Example — a photographer sets up a night snow scene just for themselves:

```
/mytime 22 0 0
/myweather snow 2 1
```

...and returns to normal with `/weathersync`.

## Diagnostics

| Command | Description |
|---|---|
| `/synccheck` | Checks that this client matches the server — every line should say `OK`. |
| `/weatherstatus` | Local state: weather, time, region, altitude, temperature. |
| `/weatherdebug` | Detailed client logs in the F8 console. |
| `/testweather <type>` | Preview a weather type locally (with region translation). |

## Server console

| Command | Description |
|---|---|
| `weatherstats` | Current state and statistics. |
| `weatherdebug_sv` | Toggle server debug logging. |
| `forecast` | Print the forecast. |
| `weathertest [full]` | Self-test (needs `Config.enableTests = true`, see [FAQ](faq.md)). |

All admin chat commands also work from the console.
