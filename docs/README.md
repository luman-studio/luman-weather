# WeatherSync

**Time and weather synchronization for RedM. Optimized, framework independent.**

Every player sees the same time and the same weather. Unlike most weather
scripts, WeatherSync doesn't spam the network every few seconds — the server
sends a message only when something actually changes, and each client runs
its own clock in perfect sync. When nothing happens, nothing is sent.

## Features

* ⏱ Real-time clock (with timezone offset) or any custom timescale
* 🌦 Weather changes naturally, following a configurable pattern
* 📋 Forecast of upcoming weather for players (`/forecast`)
* 🏔 Regional weather — rain becomes snow in the mountains, storms become
  sandstorms in the desert
* 🎛 In-game admin panel (`/weatherui`)
* 📷 Players can detach from sync and set personal time/weather
* 🔒 All admin actions protected by ace permissions
* ✅ Built-in self-test (`/synccheck`)
* 🔌 Works standalone and with any framework (RSGCore, VORP, ...)

## Quick start

```cfg
# server.cfg
exec @weathersync/permissions.cfg
ensure weathersync
```

Done. By default the in-game clock mirrors the real server clock and the
weather starts sunny, changing every in-game hour.

Next steps:

* [Installation & permissions](installation.md)
* [Configuration](configuration.md)
* [Commands](commands.md)
