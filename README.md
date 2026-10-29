# Hide & Seek

A LAN prop-hunt party game for up to 20 players, made with Godot 4.7.

**Hiders** turn into props around the village and try to survive until the timer runs out.
**Seekers** bonk anything that looks suspicious. Every hider who gets found joins the seekers.

## Playing at a LAN party

1. On every PC, download `Hide-Seek-Launcher.exe` from the
   [latest release](https://github.com/Thyestee/Hide-Seek/releases/latest) and run it.
   It installs the game in a `game` folder next to itself, updates it whenever a new release is out, and starts it.
2. One player clicks **Host a game**. The lobby shows that PC's LAN IP address.
3. Everyone else either picks the game from **Games on your network** or types the host's IP and clicks **Join**.
4. The host chooses how long hiding and seeking last, then clicks **Start game**. Players who join late come in as seekers.

The first time a PC hosts or joins, Windows Firewall asks for permission. Allow **private networks**.
The game uses UDP port 7777 (game traffic) and UDP port 7778 (LAN discovery).

Everyone must run the same version: the host turns away players on a different build and tells them to update.
Without internet, the launcher still starts the version that's already installed.

## Publishing a new version

Push a version tag. The GitHub Actions workflow (`.github/workflows/release.yml`) builds the game and the launcher,
then publishes them as a GitHub release. Launchers pick up the new release the next time they start.

```bash
git tag v0.2.0
git push origin v0.2.0
```

To build locally instead, run `GODOT=path/to/godot tools/build.sh v0.2.0`.
The results go to `build/`: `Hide-Seek-windows.zip` (the game) and `Hide-Seek-Launcher.exe`.

## Rounds

- **Hide** (40 s by default): seekers are blinded while hiders find a spot.
- **Seek** (4 min by default): three bonks find a hider. Bonking ordinary furniture slows the seeker down.
  During the last minute, every hider makes a noise every 20 seconds.
- Hiders win if anyone survives the timer. Seekers win if they find everyone.
- Points: a catch is +100, surviving the round is +200, each taunt is +10.
- About one player in five starts as a seeker. Seeker duty rotates between rounds.

## Controls

Movement keys are bound by position, so AZERTY keyboards use ZQSD automatically.

| | |
|---|---|
| Everyone | WASD move · Space jump · Shift run · Tab scores · Esc menu |
| Hider | E mimic the prop you're looking at · R lock rotation · F taunt · G drop a decoy copy (2 per round) |
| Seeker | Left click bonk · Q or right click sonar (pings hiders within 14 m, 20 s cooldown) |

## Testing helpers

Command-line flags go after `--`. They let you run several copies on one PC:

```
godot --path . -- --host --name=Host --autostart=3
godot --path . -- --join=127.0.0.1 --name=Alice --bot
```

`--bot` makes the local player play by itself. `--hide=`, `--seek=`, `--quit-after-round` and
`--screenshot=file.png` are also available; see `scripts/main.gd`.

## Layout

- `scripts/autoload/net.gd`: hosting, joining, lobby list, LAN discovery, settings
- `scripts/autoload/game.gd`: round logic (the host checks every action and broadcasts the result)
- `scripts/autoload/sfx.gd`: all sounds, generated in code
- `scripts/world/`: map builder, prop catalogue, world effects
- `scripts/player/player.gd`: movement, cameras and abilities
- `scripts/ui/`: menu, lobby and HUD
- `launcher/`: the launcher, a separate small Godot project (`launcher/launcher.gd`)
- `tools/build.sh`: exports the game zip and the launcher
