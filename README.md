# Hide & Seek

A LAN prop-hunt party game for up to 20 players, made with Godot 4.7.

**Hiders** turn into any of 70 props around the village and try to survive until the timer runs out.
**Seekers** shoot bolts at anything that looks suspicious. Every hider who gets found joins the seekers.
Both teams have spells, and bots can fill in when there aren't enough people.

## Playing at a LAN party

1. On every PC, download `Hide-Seek-Launcher.exe` from the
   [latest release](https://github.com/Thyestee/Hide-Seek/releases/latest) and run it.
   It installs the game in a `game` folder next to itself, updates it whenever a new release is out, and starts it.
2. One player clicks **Host a game**. The lobby shows that PC's LAN IP address.
3. Everyone else either picks the game from **Games on your network** or types the host's IP and clicks **Join**.
4. Everyone picks a team preference and two spells per team in the lobby (also available in the Esc menu).
   The host can add or remove bots, chooses how long hiding and seeking last, then clicks **Start game**.
   Players who join late come in as seekers.

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
- **Seek** (4 min by default): seekers shoot arcing bolts (5 charges that refill over time), each dealing 20 damage.
  During the last minute, every hider makes a noise every 20 seconds.
- **Health:** hiders have 50 to 150 HP depending on the size of their prop, so a mug is fragile and a wardrobe is tough.
  Health grows back after 5 seconds without being hit.
- Hiders win if anyone survives the timer. Seekers win if they find everyone.
- Points: a catch is +100, surviving the round is +200, each taunt is +10.
- About one player in five starts as a seeker. Players who chose a team get it when possible; the rest rotate.
  A hider who switches to Seekers mid-round changes sides immediately.

## Spells

Each player equips two spells per team, cast with Q and F.

| Hiders | | Seekers | |
|---|---|---|---|
| Decoy | Drop a copy of your current prop | Sonar | Hiders within 14 m ping |
| Blink | Dash a few metres | Reveal Flare | Hiders near where it lands are marked for 4 s |
| Smoke Cloud | Thick smoke around you for 7 s | Snare | Hidden trap that roots and marks a hider |
| Echo | A taunt plays where you aim | Scatter Shot | Five bolts at once |
| Clutter | Five random small props sprout around you | Haste | Run 60% faster for 4 s |
| Regrow | Heal 40 HP | Shockwave | 15 damage to hiders within 4 m |

## Controls

Movement keys are bound by position, so AZERTY keyboards use ZQSD automatically (and the spell key shows as A).

| | |
|---|---|
| Everyone | WASD move · Space jump · Shift run · Q / F spells · Tab scores · Esc menu |
| Hider | E mimic the prop you're looking at · R lock rotation · T taunt |
| Seeker | Left click (hold) shoot bolts |

## Testing helpers

Command-line flags go after `--`. They let you run several copies on one PC:

```
godot --path . -- --host --name=Host --bots=7 --autostart=9
godot --path . -- --join=127.0.0.1 --name=Alice --team=hider
```

`--bots=N` adds AI bots on the host. `--team=`, `--hide=`, `--seek=`, `--log`, `--quit-after-round` and
`--screenshot=file.png` are also available; see `scripts/main.gd`.

## Layout

- `scripts/autoload/net.gd`: hosting, joining, lobby list, LAN discovery, settings
- `scripts/autoload/game.gd`: round logic (the host checks every action and broadcasts the result)
- `scripts/autoload/sfx.gd`: all sounds, generated in code
- `scripts/spells.gd`: spell catalogue
- `scripts/world/`: map builder, prop catalogue, mesh merging, world effects
- `scripts/player/player.gd`: movement, cameras and abilities; `bot_brain.gd`: bot AI (runs on the host)
- `scripts/ui/`: menu, lobby, team and spell picker, HUD
- `launcher/`: the launcher, a separate small Godot project (`launcher/launcher.gd`)
- `tools/build.sh`: exports the game zip and the launcher
