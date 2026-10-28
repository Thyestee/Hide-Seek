# Hide & Seek

A LAN prop-hunt party game for up to 20 players, made with Godot 4.7.

**Hiders** turn into props around the village and try to survive until the timer runs out.
**Seekers** bonk anything that looks suspicious. Every hider who gets found joins the seekers.

## Playing at a LAN party

1. Export the game (or run it from the editor) on every PC.
2. One player clicks **Host a game**. The lobby shows that PC's LAN IP address.
3. Everyone else either picks the game from **Games on your network** or types the host's IP and clicks **Join**.
4. The host chooses how long hiding and seeking last, then clicks **Start game**. Players who join late come in as seekers.

The first time a PC hosts or joins, Windows Firewall asks for permission. Allow **private networks**.
The game uses UDP port 7777 (game traffic) and UDP port 7778 (LAN discovery).

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
