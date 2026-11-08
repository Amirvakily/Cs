# BREACHLINE architecture (contract between modules)

Godot 4.4.1, GDScript, Forward+. Everything is built from code (no editor scenes besides `scenes/main.tscn`).
Units: metres. Y up. Forward is -Z.

* `yaw` (radians) rotates about Y. Flat forward = `Vector3(-sin(yaw), 0, -cos(yaw))`.
* `pitch` (radians), positive looks up. Aim dir = `Vector3(-sin(yaw)*cos(pitch), sin(pitch), -cos(yaw)*cos(pitch))`.
* Teams: `Cfg.ATK = 0` (RED VIPER, attackers), `Cfg.DEF = 1` (IRON GUARD, defenders), `Cfg.SPEC = -1`.
  In Squad Hunt: team 0 = players' squad (uses IRON GUARD look), team 1 = hostiles (RED VIPER look).
* Physics layers (bit values, in `Cfg`): `L_WORLD = 1` static geometry + props, `L_DYNAMIC = 2` doors/barricades,
  `L_SOLDIER = 4` soldier bodies, `L_DEBRIS = 8` cosmetic physics. Soldiers collide with `L_WORLD|L_DYNAMIC` only.
* Surface material of any collider: `collider.get_meta("mat")` → `"concrete" | "metal" | "wood" | "dirt" | "glass" | "flesh"`.
  Breakables (doors, barricades) also have `get_meta("breakable_id")` (int).

## Autoloads (exist)
* `Cfg` – constants, `Cfg.WEAPONS`, `Cfg.EQUIPMENT`, `Cfg.BUY_MENU`, `Cfg.settings` (persisted), `Cfg.recoil_patterns`.
* `Sfx` – `Sfx.play(name, vol_db, pitch)`, `Sfx.play3d(name, pos, vol_db, pitch, max_dist)`. Sound names are listed in `sfx.gd`.
* `Net` – connection layer (host/join/handshake). Game replication lives in `Game`.

## Scene tree at runtime
```
/root/Main           (scripts/main.gd)   owns MainMenu UI, starts/stops games
/root/Game           (scripts/game/game.gd, class Game, Node3D)  — exists only during a match
    World            (class World, built by MapBuilder) – geometry, lights, doors, nav
    Soldiers         Node3D – Soldier nodes, named by soldier id
    Projectiles      Node3D – Grenade / BreachCharge / BombProp
    Pickups          Node3D – dropped weapons
    Fx               (class Effects)
    Hud              (class Hud, CanvasLayer)
    PlayerController (class PlayerController) – local input, camera, cover; owns Camera3D + Viewmodel
```
`Game.inst` is a static var pointing at the current Game (null when none).

## Game (core – scripts/game/game.gd)
Fields: `config: Dictionary` {mode, map, bots, difficulty, rounds, friendly_fire}; `world: World`; `soldiers: Dictionary` id→Soldier;
`local_soldier: Soldier` (may be null); `local_team: int`; `fx: Effects`; `hud: Hud`; `mode` (rules object);
`rs: Dictionary` replicated round state:
```
{ "phase": "warmup"|"freeze"|"live"|"post"|"over", "time_left": float, "round": int, "score": [int,int],
  "max_rounds": int, "bomb": {"state": "none"|"carried"|"dropped"|"planted"|"defused"|"exploded",
  "carrier": String, "pos": Vector3, "time_left": float}, "hostiles_left": int, "kill_limit": int,
  "winner": int, "buy_time_left": float }
```
Signals (fire on every peer): `kill_event(killer_id, victim_id, weapon_id, headshot, wallbang)`,
`round_event(kind: String, data: Dictionary)` kinds: round_start, round_end{winner,reason}, bomb_planted{site}, bomb_defused,
bomb_exploded, halftime, match_over{winner}; `chat_message(from_name, team, text, team_only)`;
`soldier_spawned(s)`, `soldier_removed(id)`; `local_damaged(amount: float, from_dir: Vector3)`; `hit_confirmed(headshot: bool, killed: bool)`.

Methods usable by any module:
* `get_soldier(id) -> Soldier`, `alive_soldiers(team := -2) -> Array` (team -2 = all), `is_server() -> bool`, `now() -> float` (seconds).
* Requests (route to server automatically): `request_buy(item_id)`, `request_join_team(team)`, `request_chat(text, team_only)`,
  `request_drop()`, `request_use()` (doors/bomb/pickups in front of local soldier).
* `can_buy(s: Soldier, item_id) -> String` – "" if allowed, otherwise reason text. `in_buy_zone(s) -> bool`.
* `spawn_grenade(owner: Soldier, type: String, origin: Vector3, velocity: Vector3)` – replicated to all peers.
* `place_breach(owner: Soldier, pos: Vector3, normal: Vector3)` – replicated.
* Server only: `apply_damage(victim, attacker_id, dmg, zone, weapon_id, dir, armor_ratio)`,
  `explosion(pos, radius, max_dmg, attacker_id, weapon_id, breach := false)`, `noise(pos, loudness, source_id)`,
  `add_smoke(pos, radius, duration)`, `destroy_breakable(id, dir)`.
* `smoke_blocks(a: Vector3, b: Vector3) -> bool` (any peer), `recent_noises: Array` of {pos, t, loud, src, team} (server).
* `grenade_detonated(net_id, pos)` – server → all peers; calls `Grenade.detonate(pos)` on each peer.
* `mode.atk_plan: String` ("A"/"B") chosen at round start for bots in defusal.

## World (core – scripts/game/world.gd, class World extends Node3D)
`data` (map JSON), `theme` ("desert"/"night"), `cols`, `rows`, `grid: PackedStringArray`.
`cell_to_world(c: Vector2i) -> Vector3` (cell centre at floor height), `world_to_cell(p) -> Vector2i`, `floor_height(c) -> float`,
`is_blocked(c) -> bool` (walls/obstacles), `sites: Dictionary` "A"/"B" → AABB, `site_center(name) -> Vector3`,
`in_site(pos) -> String` ("A"/"B"/""), `spawn_points: Dictionary` team → Array[Transform3D], `in_spawn(pos, team) -> bool`,
`get_nav_path(from, to) -> PackedVector3Array`, `random_nav_point(center := Vector3.INF, radius := 0.0) -> Vector3`,
`radar_image() -> Image` (1 px = 0.5 m, walls opaque), `bounds: AABB`, `breakables: Dictionary` id → Door.

## Soldier (core – scripts/game/soldier.gd, class Soldier extends CharacterBody3D)
Origin at feet. Identity: `id: String`, `display_name`, `team`, `is_bot`, `owner_peer: int`.
State: `alive`, `health` (0-100), `armor` (0-100), `helmet`, `has_kit`, `money`, `kills`, `deaths`, `score`.
Inventory: `primary: String` ("" = none), `secondary: String`, `grenades: Dictionary` {"frag":n,"flash":n,"smoke":n},
`has_bomb: bool`, `breach_charges: int`. `cur: String` = current weapon id (knife/m9/…/frag/bomb/breach).
`ammo: Dictionary` id → [mag, reserve] (authoritative on the owning peer).
Look: `yaw`, `pitch`, `punch: Vector2` (recoil, degrees; x = pitch up, y = yaw). `crouch_amount` 0..1.
`flags: int` bits: `F_ON_FLOOR=1, F_CROUCH=2, F_WALK=4, F_COVER=8, F_AIM=16, F_RELOAD=32, F_PLANT=64, F_DEFUSE=128,
F_LIGHT=256, F_SCOPED=512` (constants on Soldier). `scope_level: int` (0 none). `ads_amount: float` 0..1.
`action_progress: float` 0..1 + `action_label: String` (planting/defusing progress for HUD).
`flash_until: float`, `flash_strength: float` (0..1), `spotted_until: float` (enemy visible on radar).
`model: SoldierModel`.
Methods: `eye_pos() -> Vector3`, `aim_dir() -> Vector3`, `is_authority() -> bool`, `current_spread() -> float` (degrees, for HUD crosshair),
`weapon_data() -> Dictionary` (Cfg entry of `cur`), `apply_flash(strength)`.
Signals (owner peer): `fired(weapon_id)`, `reload_started(weapon_id, duration)`, `weapon_switched(weapon_id)`, `knifed(alt)`,
`threw(type)`; (all peers): `died(killer_id)`, `spawned()`.
Movement/weapon simulation consumes a command dictionary each physics tick:
```
{ "move": Vector2 (x right, y forward, -1..1), "jump": bool, "crouch": bool, "walk": bool,
  "fire": bool, "fire_pressed": bool, "alt": bool, "alt_pressed": bool, "reload": bool, "use": bool,
  "yaw": float, "pitch": float, "slot": int (0 = none, 1..5), "cycle": int (-1/0/1), "drop": bool, "light": bool }
```
Bots and PlayerController both produce this via `think(delta)` / `make_cmd(delta)`.

## SoldierModel (worker: visuals – scripts/game/soldier_model.gd, class SoldierModel extends Node3D)
Third-person character. Origin at feet, faces -Z. Soldier sets `model.rotation.y = yaw` each frame.
* `setup(team: int, seed: int, hostile := false)` – builds the low/mid-poly operator (helmet/vest/pouches/etc).
* `set_weapon(id: String)` – shows `WeaponModels.build(id)` in the right hand.
* `update_anim(delta: float, s: Soldier)` – called every frame; reads `s.velocity`, `s.crouch_amount`, `s.pitch`, `s.flags`, `s.alive`.
* `play_fire()`, `play_reload(duration)`, `play_throw()`, `play_knife()`, `die(dir: Vector3)`, `reset()`.
* `muzzle_global() -> Vector3`, `head_global() -> Vector3`, `set_first_person(v: bool)` (true = only shadows rendered).
* Hitboxes are NOT part of the model; Combat uses fixed proportions: head sphere centre at 1.62 m (r 0.17) standing,
  chest 1.05–1.45 m, stomach 0.80–1.05 m, legs 0–0.8 m, half-width 0.24; all heights scale by
  `lerp(1.0, CROUCH_EYE/STAND_EYE, crouch_amount)`. Keep the model's proportions consistent with this.

## WeaponModels (worker: visuals – scripts/game/weapon_models.gd, class WeaponModels)
`static func build(id: String) -> Node3D` – barrel along -Z, origin at the pistol grip, contains `Marker3D` children
"Muzzle", "Mag" (Node3D moved during reload), "LeftHand" (support-hand position). Grenades/bomb/breach/knife included.
Uses Poly Haven `service_pistol` (m9) and `bolt_action_rifle_7_62` (longbow) models; others are detailed procedural meshes
with PBR materials.

## Viewmodel (worker: visuals – scripts/game/viewmodel.gd, class Viewmodel extends Node3D)
Child of the local Camera3D. Uses a spatial shader with vertex depth compression (reverse-Z) so it never clips into walls,
and its own fixed FOV. `setup(team)`, `set_weapon(id)` (draw animation), `on_fire()`, `on_reload(duration)`, `on_throw()`,
`on_knife(alt)`, `update_vm(delta, s: Soldier, look_delta: Vector2)` (bob, sway, ADS via `s.ads_amount`, hide when
`s.scope_level > 0` or in cover), `muzzle_global() -> Vector3`.

## Effects (worker: fx – scripts/game/effects.gd, class Effects extends Node3D)
`shot(origin: Vector3, ends: PackedVector3Array, weapon_id: String, from_local_view: bool)`, `muzzle_flash(pos, dir, weapon_id)`,
`impact(pos, normal, mat: String)` (particles + decal + sound), `blood(pos, dir)`, `explosion(pos, kind)` kinds frag/breach/bomb,
`smoke_cloud(pos, radius, duration)`, `flash_burst(pos)`, `debris(pos, dir, mat)` (door/barricade break), `shell(pos, dir)`.
Pool and cap everything (decals ≤ 96, particles reused).

## Projectiles (worker: fx)
* `scripts/game/grenade.gd` class Grenade extends Node3D: `setup(net_id, type, owner_id, origin, vel)`; simulates bounces
  (ray casts against `L_WORLD|L_DYNAMIC`), rolling, fuse (frag 1.8 s, flash 1.6 s, smoke 2.0 s after landing/1.5 s).
  On the server, when it fuses it calls `Game.inst.grenade_detonated(net_id, pos)`. `detonate(pos)` (all peers) plays effects;
  on the server it also applies gameplay: frag → `Game.explosion(pos, 7.5, 100, owner, "frag")`; flash → for each soldier with
  LOS compute strength from distance/facing → `s.apply_flash(strength)`; smoke → `Game.add_smoke(pos, 4.5, 16)`.
* `scripts/game/breach_charge.gd` class BreachCharge extends Node3D: `setup(net_id, owner_id, pos, normal)`; beeps,
  detonates after 2.5 s on the server → `Game.explosion(pos, 3.5, 90, owner, "breach", true)`.
* `scripts/game/bomb_prop.gd` class BombProp extends Node3D: planted charge visual (blinking light, beeps faster as
  `set_time_left(t)` approaches 0).

## Hud & menus (worker: ui – scripts/ui/*.gd)
* `scripts/ui/hud.gd` class Hud extends CanvasLayer: reads `Game.inst`/`local_soldier` each frame. Crosshair (gap from
  `current_spread()`), health/armor/money/ammo, timer/score/alive counts, radar, kill feed, chat (Y/U), center messages,
  plant/defuse progress, hints, damage direction, hit marker, flash whiteout, sniper scope overlay, buy menu (B),
  scoreboard (Tab), team select (M, and automatically after joining), pause menu (Esc) with settings & leave.
  `is_menu_open() -> bool` (PlayerController ignores input + frees mouse while true).
* `scripts/ui/main_menu.gd` class MainMenu extends Control: play offline / host / join / settings / quit.
  Calls `get_node("/root/Main").start_offline(config)`, `.host(config, port)`, `.join(ip, port)`, `show_status(text)`.
* `scripts/ui/settings_panel.gd` class SettingsPanel (reused by pause menu), `scripts/ui/ui_theme.gd` class UiTheme
  (`static func get_theme() -> Theme`).

## Bots (worker: ai – scripts/game/bot.gd, class BotBrain extends Node)
Server-only child of a bot Soldier. `setup(s: Soldier, difficulty: int)`, `think(delta) -> Dictionary` (command),
`on_round_start()`, `on_damaged(attacker_id: String, dir: Vector3)`, `buy_loadout()` (calls `Game.inst.server_buy(s, item)`).
Uses World nav, `Combat.can_see(from, to)`, `Game.smoke_blocks`, `Game.recent_noises`, `Game.rs`, `Game.mode.atk_plan`.
