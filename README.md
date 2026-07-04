# WeatherSync

Optimized time and weather synchronization for RedM.

The server broadcasts an event only when something actually changes; each
client runs its own clock from the shared network time. **Idle network
traffic is zero.** Framework independent — works standalone and with any
framework.

📖 **[Full documentation](docs/README.md)** (GitBook)

## Features

- Zero-traffic time & weather sync for all players
- Real-time clock mode (with timezone offset) or any timescale
- Configurable weather patterns with a queued forecast (`/forecast`)
- Regional weather: snow in the mountains, sandstorms in the desert — applied
  locally as players move
- Altitude wind shear
- In-game admin UI (`/weatherui`)
- Per-player local overrides (`/mytime`, `/myweather`)
- Ace-permission gating on every state-changing command and event
- Built-in automated test suite (`/weathertest`, console `weathertest`)

## Installation

1. Copy the `weathersync` folder into your resources directory.
2. Add to `server.cfg`:

   ```cfg
   exec @weathersync/permissions.cfg
   ensure weathersync
   ```

3. Review [permissions.cfg](permissions.cfg) and grant the admin aces to your
   staff — details in [docs/installation.md](docs/installation.md).

## Documentation

| Section | |
|---|---|
| [Installation & permissions](docs/installation.md) | Setup and admin access |
| [Configuration](docs/configuration.md) | Every `Config.*` option with examples |
| [Commands](docs/commands.md) | Admin, player and diagnostic commands |
| [API (exports)](docs/api.md) | Integration with other resources |
| [FAQ & troubleshooting](docs/faq.md) | Common issues and self-testing |

## Credits

Based on [kibook/weathersync](https://github.com/kibook/weathersync),
rewritten with an optimized synchronization model, hardened permissions and
an automated test suite.
