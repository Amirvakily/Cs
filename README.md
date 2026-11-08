# BREACHLINE

A round-based tactical shooter for Windows, built with Godot 4. It plays like a mix of classic
round-based bomb defusal (economy, buy menu, recoil spray patterns, wallbangs) and a third-person
cover shooter (snap-to-cover, blind fire, peeking, breaching charges), with bots and online play.

**Download:** [`release/BREACHLINE-windows.zip`](release/BREACHLINE-windows.zip): unzip, run `BREACHLINE.exe`.

## Features

- **Modes:** Demolition (plant/defuse, money, halftime side swap), Team Deathmatch (respawns, free
  loadouts) and Squad Hunt (you + AI squad clear the map of hostiles).
- **Maps:** *Outpost* (desert compound at sunset) and *Neon Row* (casino strip at night, wet streets).
- **Gunplay:** 14 weapons plus knife, frag/flash/smoke grenades and breach charges. Each gun has
  its own recoil pattern, movement and air inaccuracy, ADS or scopes, headshot multipliers, armour
  and helmet rules, and penetration through wood, doors, thin walls and crates.
- **Cover system:** press Q on a wall to switch to an over-the-shoulder camera. Slide along the
  wall, peek over or around edges to aim, or blind-fire.
- **Doors and barricades:** doors open, close and can be breached; barricades can be shot apart.
- **Bots:** navmesh pathfinding, perception, recoil control, buying, grenades, plant/defuse
  tactics, four difficulty levels.
- **Online:** host from the game, or run the dedicated server (`Start Dedicated Server.bat`,
  configured by `server.cfg`). The server tries UPnP to open the port. The server browser finds
  LAN servers automatically and supports favourites. An optional master server provides a public
  list.
- **Graphics:** Forward+ renderer with real-time global illumination (SDFGI), volumetric fog,
  SSAO, SSR, bloom, ACES tone mapping, photoscanned CC0 PBR textures, HDRI skies and props from
  Poly Haven. Four quality presets.

## Repository layout

| Path | What |
|------|------|
| `scripts/core` | Autoloads: settings and weapon data (`cfg.gd`), synthesized audio (`sfx.gd`), connections (`net.gd`) |
| `scripts/game` | World builder, soldier, combat, rules, bots, effects, models, player controller |
| `scripts/net` | Server query beacon, master server, server browser list |
| `scripts/ui` | HUD, menus, buy menu, scoreboard, server browser |
| `maps/*.json` | Map layouts (grid based, see `tools/map_preview.py`) |
| `assets/` | CC0 assets: Poly Haven textures/skies/props (`tools/fetch_assets.py`), recorded gun sounds (`tools/build_sounds.py`) |
| `docs/ARCHITECTURE.md` | Module contracts |

## Building from source

Requires Godot 4.4.1 with Windows export templates.

```
godot --headless --path . --import
tools/package.sh                 # exports build/BREACHLINE and zips release/BREACHLINE-windows.zip
```

Dev/test entry points (pass after `--`):

```
--server                      dedicated server (uses server.cfg)
--master [--port 27900]       master server
--autotest <mode> <map> <seconds> [timescale]   bots-only match, prints events
--testclient <host> <port> <seconds>            scripted client for multiplayer tests
--shots <map> <mode> <out_dir> [quality]        in-game screenshots
```

## Credits

Textures, HDRI skies and props by [Poly Haven](https://polyhaven.com) (CC0).
Gunshot recordings: [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) (CC0);
reload sounds from OpenGameArt CC0 packs ("Gun reload sounds", "Handgun reload sound effect",
"Shotgun reload sound effects", "2 Gun Reloads"). `tools/build_sounds.py` rebuilds `assets/sounds`.
Engine: Godot (MIT). All other code, the remaining sounds (synthesized at runtime) and the
procedural models are original to this project.
