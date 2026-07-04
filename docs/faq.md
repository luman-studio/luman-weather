# FAQ & troubleshooting

### How do I check that everything works?

Run `/synccheck` in game. Every line should say `OK`. It compares your
client's time, weather and wind against the server and names the exact layer
if something is off.

For a full automated check, set `Config.enableTests = true` in `config.lua`,
restart the resource and run `/weathertest` in game (read-only, ~15 s) or
`weathertest` in the server console. `/weathertest full` additionally tests
changing time/weather and restores everything afterwards (admin permissions
required). Turn the option back off when you're done.

### The clock is wrong for one player, correct for everyone else

That player detached from sync — `/weathersync` or `/mytime` does that.
`/synccheck` shows a warning when sync is off. Ask them to run
`/weathersync` to re-attach.

### The clock is wrong for everyone

* In real-time mode the clock follows the **server's** clock. If your players
  live in a different timezone, set `Config.timezoneOffset`.
* Check whether the clock is frozen: `weatherstats` in the server console
  shows `Time Frozen`. Unfreeze with `/time <d> <h> <m> <s> 0 0`.

### The weather never changes

* `Config.weatherIsFrozen = true`, or an admin froze it with
  `/weather <type> <transition> 1`. Unfreeze: `/weather <type> 10 0`.
* By default the weather changes once per **in-game** hour. In real-time mode
  that's a real hour — that's expected.

### Admin UI opens but nothing applies

Missing permissions. The UI needs all six aces (`command.weather`,
`command.time`, `command.timescale`, `command.wind`, `command.syncdelay`,
`command.weatherui`) — see [Installation](installation.md). Every rejected
attempt is logged in the server console:

```
[warning] Player 3 tried to use weather without permission
```

### It's raining in the snowy mountains / snowing in the desert

It shouldn't — regional translation handles this automatically. Check the
player's actual region with `/weatherstatus` (Region row). If it says
`Snowy` but rain is falling, run `/synccheck` and report the output.

### Does `Config.syncDelay` affect network usage?

No. It's an internal server tick. WeatherSync only sends network messages
when the weather actually changes (about once per in-game hour) and when a
player joins. You can verify with `/weatherstatus` — the "Sync Events
Received" counters stay flat while nothing changes.

### How do I make it always winter?

```lua
Config.weather = "snow"
Config.permanentSnow = true
```

and replace `Config.weatherPattern` with snow types — a ready-made example is
in [API](api.md#example-winter-season).

### Something else is broken

1. Turn on debug logs: `/weatherdebug` (client, F8 console) and
   `weatherdebug_sv` (server console).
2. Reproduce the issue.
3. Run `weathertest client <player id> full` from the server console — it
   prints a pass/fail line for every part of the system and pinpoints the
   failing layer.
