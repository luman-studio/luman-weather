# Installation & permissions

## Install

1. Copy the `weathersync` folder into your resources directory:

   ```
   resources/[local]/weathersync
   ```

2. Add to `server.cfg`:

   ```cfg
   exec @weathersync/permissions.cfg
   ensure weathersync
   ```

3. Restart the server.

The server console should show:

```
[success] WeatherSync initialized successfully
```

In game, run `/synccheck` — every line should say `OK`.

## Give admins access

Open `permissions.cfg` and uncomment the admin lines:

```cfg
add_ace group.admin command.syncdelay allow
add_ace group.admin command.time allow
add_ace group.admin command.timescale allow
add_ace group.admin command.weather allow
add_ace group.admin command.weatherui allow
add_ace group.admin command.wind allow
```

Then make sure your admins are in `group.admin`, e.g. in `server.cfg`:

```cfg
add_principal identifier.license:xxxxxxxx group.admin
```

{% hint style="info" %}
An admin needs **all six** aces to use every panel of the admin UI. These
permissions protect not just the commands but also the network events behind
the UI — players without them cannot change server weather in any way.
{% endhint %}

Player commands (`/forecast`, `/mytime`, `/myweather`, `/weathersync`) are
enabled for everyone by default.
