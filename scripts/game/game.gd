class_name Game
extends Node3D
## Match hub: world, soldiers, replication (listen/dedicated server), damage, economy actions.
## Lives at /root/Game on every peer. Round rules live in Rules (server side).

signal kill_event(killer_id: String, victim_id: String, weapon_id: String, headshot: bool, wallbang: bool)
signal round_event(kind: String, data: Dictionary)
signal chat_message(from_name: String, team: int, text: String, team_only: bool)
signal soldier_spawned(s: Soldier)
signal soldier_removed(id: String)
signal local_damaged(amount: float, from_dir: Vector3)
signal hit_confirmed(headshot: bool, killed: bool)

const BOT_NAMES := ["Hawk", "Viper", "Ghost", "Rook", "Atlas", "Bishop", "Cobra", "Dune", "Echo", "Falcon", "Grim",
	"Havoc", "Jackal", "Kodiak", "Lynx", "Mako", "Nomad", "Onyx", "Pike", "Raven", "Saber", "Talon", "Vandal", "Wolf",
	"Yeti", "Zulu", "Brick", "Cipher", "Drift", "Flint", "Gunner", "Hex"]

static var inst: Game

var config := {}
var dedicated := false
var world: World
var soldiers := {}
var local_soldier: Soldier
var local_team := -1
var fx: Effects
var hud: Hud
var controller: PlayerController
var mode: Rules
var recent_noises: Array = []
var smokes: Array = []
var pickups := {}
var rs := {"phase": "warmup", "time_left": 0.0, "round": 1, "score": [0, 0], "max_rounds": 16,
	"bomb": {"state": "none", "carrier": "", "pos": Vector3.ZERO, "time_left": 0.0, "site": ""},
	"hostiles_left": 0, "kill_limit": 0, "winner": -1, "buy_time_left": 0.0, "mode": "defusal", "map": ""}

var _soldier_root: Node3D
var _proj_root: Node3D
var _pickup_root: Node3D
var _next_net_id := 1
var _next_pickup := 1
var _bot_seq := 0
var _bomb_prop: BombProp
var _out_states := {}
var _state_timer := 0.0
var _rs_timer := 0.0
var _score_timer := 0.0
var _spot_timer := 0.0
var _pickup_timer := 0.0
var _rs_recv_t := 0.0


func setup(p_config: Dictionary, p_dedicated := false) -> void:
	config = p_config.duplicate()
	dedicated = p_dedicated
	name = "Game"


func _enter_tree() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null
	Sfx.stop_ambient()


func _ready() -> void:
	inst = self
	rs["mode"] = config.get("mode", Cfg.MODE_DEFUSAL)
	rs["map"] = config.get("map", "outpost")
	world = World.new()
	world.name = "World"
	add_child(world)
	world.build(str(config.get("map", "outpost")), is_server(), not dedicated)
	_soldier_root = Node3D.new()
	_soldier_root.name = "Soldiers"
	add_child(_soldier_root)
	_proj_root = Node3D.new()
	_proj_root.name = "Projectiles"
	add_child(_proj_root)
	_pickup_root = Node3D.new()
	_pickup_root.name = "Pickups"
	add_child(_pickup_root)
	fx = Effects.new()
	fx.name = "Fx"
	add_child(fx)
	if not dedicated:
		controller = PlayerController.new()
		controller.name = "PlayerController"
		add_child(controller)
		hud = Hud.new()
		hud.name = "Hud"
		add_child(hud)
	mode = Rules.new(self)
	Net.peer_loaded.connect(_on_peer_loaded)
	Net.peer_gone.connect(_on_peer_gone)
	if is_server():
		mode.start()
	else:
		Net.send_loaded()


func is_server() -> bool:
	return Net.is_server()


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func game_mode() -> String:
	return str(config.get("mode", Cfg.MODE_DEFUSAL))


func get_soldier(id: String) -> Soldier:
	return soldiers.get(id)


func alive_soldiers(team := -2) -> Array:
	var out := []
	for s in soldiers.values():
		if s.alive and (team == -2 or s.team == team):
			out.append(s)
	return out


func team_soldiers(team: int) -> Array:
	var out := []
	for s in soldiers.values():
		if s.team == team:
			out.append(s)
	return out


func movement_frozen() -> bool:
	return rs["phase"] == "freeze" and game_mode() == Cfg.MODE_DEFUSAL


func team_name(team: int) -> String:
	if team < 0:
		return "SPECTATOR"
	if game_mode() == Cfg.MODE_HUNT:
		return ["SQUAD", "HOSTILES"][team]
	return Cfg.TEAM_NAMES[team]


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	var t := now()
	# Expire noises and smokes.
	while not recent_noises.is_empty() and t - float(recent_noises[0]["t"]) > 4.0:
		recent_noises.pop_front()
	for i in range(smokes.size() - 1, -1, -1):
		if t > float(smokes[i]["until"]):
			smokes.remove_at(i)
	if is_server():
		mode.update(delta)
		_state_timer += delta
		if _state_timer >= 1.0 / 30.0:
			_state_timer = 0.0
			_flush_states()
		_rs_timer += delta
		if _rs_timer >= 1.0:
			_rs_timer = 0.0
			broadcast_rs()
		_score_timer += delta
		if _score_timer >= 1.0:
			_score_timer = 0.0
			_send_scores()
		_pickup_timer += delta
		if _pickup_timer >= 0.15:
			_pickup_timer = 0.0
			_auto_pickups()
	else:
		var dt := t - _rs_recv_t
		_rs_recv_t = t
		rs["time_left"] = maxf(0.0, float(rs["time_left"]) - dt)
		rs["buy_time_left"] = maxf(0.0, float(rs["buy_time_left"]) - dt)
		var bomb: Dictionary = rs["bomb"]
		if bomb["state"] == "planted":
			bomb["time_left"] = maxf(0.0, float(bomb["time_left"]) - dt)
	if _bomb_prop and rs["bomb"]["state"] == "planted":
		_bomb_prop.set_time_left(float(rs["bomb"]["time_left"]))
	_spot_timer += delta
	if _spot_timer > 0.25:
		_spot_timer = 0.0
		_update_spotting()


func _update_spotting() -> void:
	var my_team := local_team
	if local_soldier:
		my_team = local_soldier.team
	if my_team < 0:
		return
	var t := now()
	var friends := alive_soldiers(my_team)
	for e in soldiers.values():
		var es: Soldier = e
		if not es.alive or es.team == my_team:
			continue
		for f in friends:
			var fs: Soldier = f
			if fs.eye_pos().distance_to(es.global_position) > 70.0:
				continue
			if Combat.can_see(fs.eye_pos(), es.global_position + Vector3(0, 1.3, 0)) and not smoke_blocks(fs.eye_pos(), es.global_position):
				es.spotted_until = t + 1.2
				break


# ---------------------------------------------------------------------------
# Networking helpers
# ---------------------------------------------------------------------------
func _peers() -> Array:
	if not Net.online:
		return []
	return Net.loaded_peers()


## Server: send an RPC to every loaded client (optionally excluding one).
func _send(method: String, args: Array, exclude := 0) -> void:
	for p in _peers():
		if p == exclude:
			continue
		callv("rpc_id", [p, method] + args)


func _send_to(peer: int, method: String, args: Array) -> void:
	if peer == 1 or not Net.online:
		return
	callv("rpc_id", [peer, method] + args)


func _to_server(method: String, args: Array) -> void:
	callv("rpc_id", [1, method] + args)


func _sender() -> int:
	return multiplayer.get_remote_sender_id()


func _owned_by_sender(id: String) -> Soldier:
	var s: Soldier = soldiers.get(id)
	if s == null or s.owner_peer != _sender():
		return null
	return s


# ---------------------------------------------------------------------------
# Soldier lifecycle
# ---------------------------------------------------------------------------
func _make_soldier(info: Dictionary) -> Soldier:
	if soldiers.has(info["id"]):
		return soldiers[info["id"]]
	var s := Soldier.new()
	s.setup(info)
	soldiers[s.id] = s
	_soldier_root.add_child(s)
	s.global_position = Vector3(0, -50, 0)
	s.visible = false
	if s.is_local_player():
		local_soldier = s
		local_team = s.team
		if controller:
			controller.attach(s)
	if s.is_bot and is_server():
		var b := BotBrain.new()
		b.name = "Brain"
		s.add_child(b)
		s.brain = b
		b.setup(s, int(config.get("difficulty", 1)))
	soldier_spawned.emit(s)
	return s


func server_add_soldier(info: Dictionary) -> Soldier:
	var s := _make_soldier(info)
	_send("cl_add_soldier", [info])
	return s


func server_remove_soldier(id: String) -> void:
	var s: Soldier = soldiers.get(id)
	if s == null:
		return
	if s.has_bomb:
		_drop_bomb(s)
	_remove_soldier(id)
	_send("cl_remove_soldier", [id])


func _remove_soldier(id: String) -> void:
	var s: Soldier = soldiers.get(id)
	if s == null:
		return
	soldiers.erase(id)
	if s == local_soldier:
		local_soldier = null
	s.queue_free()
	soldier_removed.emit(id)


func next_bot_name() -> String:
	var used := {}
	for s in soldiers.values():
		used[s.display_name] = true
	for i in BOT_NAMES.size():
		var n: String = BOT_NAMES[(i + _bot_seq * 7) % BOT_NAMES.size()]
		if not used.has(n):
			return n
	return "Bot%d" % _bot_seq


func server_add_bot(team: int) -> Soldier:
	_bot_seq += 1
	var info := {"id": "b%d" % _bot_seq, "name": next_bot_name(), "team": team, "bot": true, "peer": 1}
	return server_add_soldier(info)


## Server: place a soldier at a transform and replicate (inventory included).
func server_spawn(s: Soldier, xf: Transform3D) -> void:
	s.visible = true
	s.respawn_at(xf)
	s.spawn_protect_until = now() + (2.0 if game_mode() != Cfg.MODE_DEFUSAL else 0.0)
	_send("cl_spawn", [s.id, xf.origin, xf.basis.get_euler().y, s.inventory(), s.team])
	if s.brain:
		s.brain.on_round_start()


@rpc("authority", "call_remote", "reliable")
func cl_add_soldier(info: Dictionary) -> void:
	_make_soldier(info)


@rpc("authority", "call_remote", "reliable")
func cl_remove_soldier(id: String) -> void:
	_remove_soldier(id)


@rpc("authority", "call_remote", "reliable")
func cl_spawn(id: String, pos: Vector3, yaw: float, inv: Dictionary, team: int) -> void:
	var s: Soldier = soldiers.get(id)
	if s == null:
		return
	if s.team != team:
		set_team_local(s, team)
	s.set_inventory(inv)
	s.visible = true
	s.respawn_at(Transform3D(Basis(Vector3.UP, yaw), pos))


func set_team_local(s: Soldier, team: int) -> void:
	s.team = team
	if s.model:
		s.model.queue_free()
		s.model = SoldierModel.new()
		s.add_child(s.model)
		s.model.setup(team, hash(s.id), s.is_hostile_look())
		s.model.set_weapon(s.cur)
	if s == local_soldier:
		local_team = team
		if controller:
			controller.attach(s)


func server_set_team(s: Soldier, team: int) -> void:
	set_team_local(s, team)
	_send("cl_team", [s.id, team])


@rpc("authority", "call_remote", "reliable")
func cl_team(id: String, team: int) -> void:
	var s: Soldier = soldiers.get(id)
	if s:
		set_team_local(s, team)


func server_teleport(s: Soldier, pos: Vector3, yaw: float) -> void:
	s.force_position(pos, yaw)
	_send("cl_teleport", [s.id, pos, yaw])


@rpc("authority", "call_remote", "reliable")
func cl_teleport(id: String, pos: Vector3, yaw: float) -> void:
	var s: Soldier = soldiers.get(id)
	if s:
		s.force_position(pos, yaw)


# --- joining ------------------------------------------------------------------
func _on_peer_loaded(id: int, pname: String) -> void:
	if not is_server():
		return
	_send_to(id, "cl_init", [_full_state()])
	server_message("%s connected." % pname)


func _on_peer_gone(id: int) -> void:
	if not is_server():
		return
	var sid := "p%d" % id
	if soldiers.has(sid):
		server_message("%s left the game." % soldiers[sid].display_name)
		server_remove_soldier(sid)
		mode.balance_bots()


func _full_state() -> Dictionary:
	var list := []
	for s in soldiers.values():
		var so: Soldier = s
		list.append({"info": {"id": so.id, "name": so.display_name, "team": so.team, "bot": so.is_bot, "peer": so.owner_peer},
			"alive": so.alive, "pos": so.global_position, "yaw": so.yaw, "inv": so.inventory(), "hp": so.health,
			"k": so.kills, "d": so.deaths, "sc": so.score})
	var doors := []
	for d in world.breakables.values():
		doors.append([d.id, d.is_open, d.broken])
	var pk := []
	for pid in pickups.keys():
		pk.append([pid, pickups[pid]["wid"], pickups[pid]["pos"]])
	var bomb_pos = null
	if _bomb_prop:
		bomb_pos = _bomb_prop.global_position
	return {"soldiers": list, "doors": doors, "pickups": pk, "rs": _rs_for_send(), "bomb_prop": bomb_pos}


@rpc("authority", "call_remote", "reliable")
func cl_init(st: Dictionary) -> void:
	for e in st["soldiers"]:
		var s := _make_soldier(e["info"])
		s.set_inventory(e["inv"])
		s.kills = int(e["k"])
		s.deaths = int(e["d"])
		s.score = int(e["sc"])
		if e["alive"]:
			s.visible = true
			s.respawn_at(Transform3D(Basis(Vector3.UP, float(e["yaw"])), e["pos"]))
			s.health = int(e["hp"])
	for d in st["doors"]:
		var door := world.get_breakable(int(d[0]))
		if door:
			if d[2]:
				door.set_broken()
			else:
				door.set_open(bool(d[1]))
	for p in st["pickups"]:
		_add_pickup_local(int(p[0]), str(p[1]), p[2])
	cl_rs(st["rs"])
	if st["bomb_prop"] != null:
		_set_bomb_prop(st["bomb_prop"])


func request_join_team(team: int) -> void:
	if is_server():
		_join_team(Net.my_id(), Cfg.settings["player_name"], team)
	else:
		_to_server("sv_join_team", [team])


@rpc("any_peer", "call_remote", "reliable")
func sv_join_team(team: int) -> void:
	_join_team(_sender(), Net.peer_name(_sender()), team)


func _join_team(peer: int, pname: String, team: int) -> void:
	if team != Cfg.SPEC and team != Cfg.ATK and team != Cfg.DEF:
		team = mode.auto_team()
	if team == 2:
		team = mode.auto_team()
	var sid := "p%d" % peer
	var s: Soldier = soldiers.get(sid)
	if team == Cfg.SPEC:
		if s:
			server_remove_soldier(sid)
			mode.balance_bots()
		return
	if s == null:
		s = server_add_soldier({"id": sid, "name": pname, "team": team, "bot": false, "peer": peer})
		s.money = mode.start_money()
	elif s.team != team:
		if s.alive:
			apply_damage(s, s.id, 1000.0, Combat.Z_CHEST, "suicide", Vector3.UP, 1.0)
		server_set_team(s, team)
	server_message("%s joined %s." % [pname, team_name(team)])
	mode.balance_bots()
	mode.on_player_joined(s)


# --- states -----------------------------------------------------------------------
func send_state(s: Soldier) -> void:
	if is_server():
		_out_states[s.id] = s.get_state()
	elif Net.online:
		_to_server("sv_state", [s.id, s.get_state()])


func _flush_states() -> void:
	if _out_states.is_empty() or _peers().is_empty():
		_out_states.clear()
		return
	var arr := []
	for id in _out_states.keys():
		arr.append(id)
		arr.append(_out_states[id])
	_out_states.clear()
	for p in _peers():
		rpc_id(p, "cl_states", arr)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func sv_state(id: String, st: Array) -> void:
	var s := _owned_by_sender(id)
	if s == null or not s.alive:
		return
	s.push_state(st)
	_out_states[id] = st


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func cl_states(arr: Array) -> void:
	for i in range(0, arr.size() - 1, 2):
		var s: Soldier = soldiers.get(arr[i])
		if s and not s.is_authority() and s.alive:
			s.push_state(arr[i + 1])


# ---------------------------------------------------------------------------
# Shooting / damage
# ---------------------------------------------------------------------------
func _shot_origin(s: Soldier) -> Vector3:
	if s == local_soldier and controller and controller.first_person():
		return controller.muzzle_global()
	if s.model:
		return s.model.muzzle_global()
	return s.eye_pos()


func _play_shot_fx(s: Soldier, wid: String, ends: PackedVector3Array, impacts: Array) -> void:
	if dedicated or fx == null:
		return
	var origin := _shot_origin(s)
	fx.shot(origin, ends, wid, s == local_soldier and controller != null and controller.first_person())
	for imp in impacts:
		fx.impact(imp["pos"], imp["normal"], imp["mat"])


## Called by the soldier's authority after firing.
func on_local_shot(s: Soldier, wid: String, origin: Vector3, ends: PackedVector3Array, impacts: Array, hits: Array) -> void:
	_play_shot_fx(s, wid, ends, impacts)
	for h in hits:
		if not dedicated:
			fx.blood(h["pos"], h["dir"])
	if is_server():
		_send("cl_shot", [s.id, wid, ends, impacts], s.owner_peer if not s.is_bot else 0)
		noise(origin, 1.0, s.id)
		_apply_hits(s, wid, hits)
		_apply_object_hits(impacts)
	else:
		_to_server("sv_shot", [s.id, wid, ends, impacts, hits])


@rpc("any_peer", "call_remote", "reliable")
func sv_shot(id: String, wid: String, ends: PackedVector3Array, impacts: Array, hits: Array) -> void:
	var s := _owned_by_sender(id)
	if s == null or not s.alive:
		return
	_play_shot_fx(s, wid, ends, impacts)
	for h in hits:
		if not dedicated:
			fx.blood(h["pos"], h["dir"])
	_send("cl_shot", [id, wid, ends, impacts], _sender())
	noise(s.eye_pos(), 1.0, id)
	_apply_hits(s, wid, hits)
	_apply_object_hits(impacts)


@rpc("authority", "call_remote", "unreliable", 2)
func cl_shot(id: String, wid: String, ends: PackedVector3Array, impacts: Array) -> void:
	var s: Soldier = soldiers.get(id)
	if s == null:
		return
	if s.model and not s.is_authority():
		s.model.play_fire()
	_play_shot_fx(s, wid, ends, impacts)


func _apply_hits(s: Soldier, wid: String, hits: Array) -> void:
	var w := Cfg.w(wid)
	for h in hits:
		var v: Soldier = soldiers.get(h["victim"])
		if v == null or not v.alive:
			continue
		var zone := int(h["zone"])
		var dmg := float(h["dmg"]) * float(Combat.ZONE_MULT[zone])
		apply_damage(v, s.id, dmg, zone, wid, h["dir"], float(w.get("armor", 0.7)), bool(h.get("wallbang", false)))


func _apply_object_hits(impacts: Array) -> void:
	for imp in impacts:
		var oid := int(imp.get("obj", 0))
		if oid > 0 and imp.has("dmg"):
			damage_breakable(oid, float(imp["dmg"]), Vector3.ZERO)


func on_local_melee(s: Soldier, res: Dictionary, dmg: float) -> void:
	if res.has("victim"):
		var v: Soldier = res["victim"]
		if not dedicated:
			fx.blood(res["pos"], res["dir"])
			Sfx.play3d("knife_hit", res["pos"], -2.0)
		if is_server():
			apply_damage(v, s.id, dmg, Combat.Z_CHEST, "knife", res["dir"], 0.85)
		else:
			_to_server("sv_melee", [s.id, v.id, dmg, res["dir"]])
	elif res.has("pos"):
		if not dedicated:
			fx.impact(res["pos"], res["normal"], res["mat"])
		if int(res.get("obj", 0)) > 0:
			if is_server():
				damage_breakable(int(res["obj"]), dmg, Vector3.ZERO)
			else:
				_to_server("sv_obj_damage", [s.id, int(res["obj"]), dmg])


@rpc("any_peer", "call_remote", "reliable")
func sv_melee(id: String, victim_id: String, dmg: float, dir: Vector3) -> void:
	var s := _owned_by_sender(id)
	var v: Soldier = soldiers.get(victim_id)
	if s == null or v == null or not s.alive:
		return
	if s.global_position.distance_to(v.global_position) > 3.5:
		return
	apply_damage(v, s.id, minf(dmg, 200.0), Combat.Z_CHEST, "knife", dir, 0.85)


@rpc("any_peer", "call_remote", "reliable")
func sv_obj_damage(id: String, obj: int, dmg: float) -> void:
	if _owned_by_sender(id):
		damage_breakable(obj, minf(dmg, 200.0), Vector3.ZERO)


## Server: apply damage with armour, friendly fire rules, and kill handling.
func apply_damage(victim: Soldier, attacker_id: String, dmg: float, zone: int, weapon_id: String, dir: Vector3, armor_ratio: float, wallbang := false) -> void:
	if not is_server() or victim == null or not victim.alive:
		return
	if now() < victim.spawn_protect_until and attacker_id != victim.id:
		return
	var attacker: Soldier = soldiers.get(attacker_id)
	if attacker and attacker != victim and attacker.team == victim.team and not bool(config.get("friendly_fire", false)) \
			and weapon_id != "suicide":
		return
	var d := dmg
	if victim.armor > 0 and zone != Combat.Z_LEGS and (zone != Combat.Z_HEAD or victim.helmet) and weapon_id != "fall":
		var to_health := d * armor_ratio
		var absorbed := (d - to_health) * 0.5
		if absorbed > victim.armor:
			to_health = d - victim.armor * 2.0
			victim.armor = 0
		else:
			victim.armor -= int(round(absorbed))
		d = to_health
	var amount := maxi(1, int(round(d)))
	victim.health = maxi(0, victim.health - amount)
	victim.last_damage_time = now()
	var killed := victim.health <= 0
	_damage_feedback(victim.id, victim.health, victim.armor, attacker_id, dir, zone, amount, killed)
	_send("cl_damage", [victim.id, victim.health, victim.armor, attacker_id, dir, zone, amount, killed])
	if victim.brain and attacker_id != victim.id:
		victim.brain.on_damaged(attacker_id, dir)
	if killed:
		_kill(victim, attacker_id, weapon_id, zone == Combat.Z_HEAD, wallbang, dir)


func _damage_feedback(victim_id: String, hp: int, armor: int, attacker_id: String, dir: Vector3, zone: int, amount: int, killed: bool) -> void:
	var v: Soldier = soldiers.get(victim_id)
	if v == null:
		return
	v.health = hp
	v.armor = armor
	if v == local_soldier:
		local_damaged.emit(float(amount), dir)
		if controller:
			controller.on_hurt(float(amount), dir)
	if local_soldier and attacker_id == local_soldier.id and v != local_soldier:
		hit_confirmed.emit(zone == Combat.Z_HEAD, killed)


@rpc("authority", "call_remote", "reliable")
func cl_damage(victim_id: String, hp: int, armor: int, attacker_id: String, dir: Vector3, zone: int, amount: int, killed: bool) -> void:
	_damage_feedback(victim_id, hp, armor, attacker_id, dir, zone, amount, killed)


func _kill(victim: Soldier, killer_id: String, wid: String, headshot: bool, wallbang: bool, dir: Vector3) -> void:
	var killer: Soldier = soldiers.get(killer_id)
	victim.deaths += 1
	if killer and killer != victim:
		if killer.team == victim.team:
			killer.kills -= 1
			killer.score -= 1
		else:
			killer.kills += 1
			killer.score += 1
	elif killer == victim:
		victim.score -= 1
	# Drop the best weapon and the charge.
	var drop := victim.primary if victim.primary != "" else (victim.secondary if game_mode() == Cfg.MODE_DEFUSAL else "")
	if drop != "" and game_mode() != Cfg.MODE_TDM:
		_spawn_pickup(drop, victim.global_position + Vector3(0, 0.05, 0))
	if victim.has_bomb:
		_drop_bomb(victim)
	if game_mode() == Cfg.MODE_DEFUSAL:
		victim.primary = ""
		victim.secondary = ""
		victim.grenades = {"frag": 0, "flash": 0, "smoke": 0}
		victim.breach_charges = 0
		victim.has_kit = false
		victim.armor = 0
		victim.helmet = false
	_on_kill_local(victim.id, killer_id, wid, headshot, wallbang, dir)
	_send("cl_kill", [victim.id, killer_id, wid, headshot, wallbang, dir])
	mode.on_kill(killer, victim, wid)


func _on_kill_local(victim_id: String, killer_id: String, wid: String, headshot: bool, wallbang: bool, dir: Vector3) -> void:
	var v: Soldier = soldiers.get(victim_id)
	if v:
		v.kill(killer_id, dir)
	kill_event.emit(killer_id, victim_id, wid, headshot, wallbang)
	if v == local_soldier and controller:
		controller.on_local_death(killer_id)


@rpc("authority", "call_remote", "reliable")
func cl_kill(victim_id: String, killer_id: String, wid: String, headshot: bool, wallbang: bool, dir: Vector3) -> void:
	var v: Soldier = soldiers.get(victim_id)
	var k: Soldier = soldiers.get(killer_id)
	if v:
		v.deaths += 1
	if k and k != v:
		k.kills += 1 if (v == null or k.team != v.team) else -1
	_on_kill_local(victim_id, killer_id, wid, headshot, wallbang, dir)


func explosion(pos: Vector3, radius: float, max_dmg: float, attacker_id: String, weapon_id: String, breach := false) -> void:
	if not is_server():
		return
	noise(pos, 2.0, attacker_id)
	for s in alive_soldiers():
		var so: Soldier = s
		var target := so.global_position + Vector3(0, 1.0, 0)
		var dist := pos.distance_to(target)
		if dist > radius:
			continue
		var visible := Combat.can_see(pos + Vector3(0, 0.15, 0), target) or Combat.can_see(pos + Vector3(0, 0.15, 0), so.eye_pos())
		if not visible:
			continue
		var dmg := max_dmg * pow(1.0 - dist / radius, 1.3)
		if dmg >= 1.0:
			apply_damage(so, attacker_id, dmg, Combat.Z_CHEST, weapon_id, (target - pos).normalized(), 0.55)
	if breach:
		for d in world.breakables.values():
			var door: Door = d
			if not door.broken and door.global_position.distance_to(pos) < radius * 0.9:
				destroy_breakable(door.id, (door.global_position - pos).normalized())
	if not dedicated and controller:
		controller.on_explosion(pos, radius)


func noise(pos: Vector3, loudness: float, source_id: String) -> void:
	if not is_server():
		return
	var s: Soldier = soldiers.get(source_id)
	recent_noises.append({"pos": pos, "t": now(), "loud": loudness, "src": source_id, "team": s.team if s else -1})
	if recent_noises.size() > 64:
		recent_noises.pop_front()


func footstep(s: Soldier) -> void:
	if not dedicated:
		var vol := -8.0 if s == local_soldier else -2.0
		Sfx.play3d("step%d" % (randi() % 4), s.global_position, vol, 1.0, 40.0)
	if is_server():
		noise(s.global_position, 0.35, s.id)


func send_flash(s: Soldier, strength: float) -> void:
	_send_to(s.owner_peer, "cl_flash", [s.id, strength])


@rpc("authority", "call_remote", "reliable")
func cl_flash(id: String, strength: float) -> void:
	var s: Soldier = soldiers.get(id)
	if s:
		s.apply_flash(strength)


func add_smoke(pos: Vector3, radius: float, duration: float) -> void:
	smokes.append({"pos": pos, "radius": radius, "until": now() + duration})


func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	for sm in smokes:
		var c: Vector3 = sm["pos"] + Vector3(0, 1.4, 0)
		var r: float = sm["radius"]
		var ab := b - a
		var len2 := ab.length_squared()
		if len2 < 0.0001:
			continue
		var t := clampf((c - a).dot(ab) / len2, 0.0, 1.0)
		if (a + ab * t).distance_to(c) < r * 0.85:
			return true
	return false


# --- breakables / doors ---------------------------------------------------------------
func damage_breakable(id: int, dmg: float, dir: Vector3) -> void:
	if not is_server():
		return
	var d := world.get_breakable(id)
	if d == null or d.broken:
		return
	d.health -= dmg * (1.0 if d.kind == "barricade" else 0.5)
	if d.health <= 0.0:
		destroy_breakable(id, dir)


func destroy_breakable(id: int, dir: Vector3) -> void:
	var d := world.get_breakable(id)
	if d == null or d.broken:
		return
	d.set_broken(dir)
	if is_server():
		_send("cl_door", [id, true, true, d.global_position])
		if d.kind == "barricade":
			world.rebake_nav()


func toggle_door(id: int, from_pos: Vector3, open := -1) -> void:
	var d := world.get_breakable(id)
	if d == null or d.broken or d.kind != "door":
		return
	var v := not d.is_open if open < 0 else open == 1
	d.set_open(v, from_pos)
	_send("cl_door", [id, v, false, from_pos])


@rpc("authority", "call_remote", "reliable")
func cl_door(id: int, open: bool, broken: bool, from_pos: Vector3) -> void:
	var d := world.get_breakable(id)
	if d == null:
		return
	if broken:
		d.set_broken()
	else:
		d.set_open(open, from_pos)


@rpc("any_peer", "call_remote", "reliable")
func sv_door(id: String, door_id: int) -> void:
	var s := _owned_by_sender(id)
	var d := world.get_breakable(door_id)
	if s and d and s.global_position.distance_to(d.global_position) < 3.5:
		toggle_door(door_id, s.global_position)


## Use key: doors first, then weapon pickups.
func use_pressed(s: Soldier) -> void:
	var hit := Combat.ray(s.eye_pos(), s.eye_pos() + s.aim_dir() * 2.4, Cfg.L_DYNAMIC)
	if not hit.is_empty() and hit["collider"] is Door:
		var d: Door = hit["collider"]
		if is_server():
			toggle_door(d.id, s.global_position)
		else:
			_to_server("sv_door", [s.id, d.id])
		return
	# Doors that are open have no collision: look for nearby open doors in view.
	for dd in world.breakables.values():
		var door: Door = dd
		if door.kind == "door" and door.is_open and not door.broken:
			var to := door.global_position + Vector3(0, 1.2, 0) - s.eye_pos()
			if to.length() < 2.4 and to.normalized().dot(s.aim_dir()) > 0.6:
				if is_server():
					toggle_door(door.id, s.global_position)
				else:
					_to_server("sv_door", [s.id, door.id])
				return
	var pid := _pickup_in_view(s)
	if pid > 0:
		if is_server():
			_take_pickup(s, pid, true)
		else:
			_to_server("sv_pickup", [s.id, pid])


# ---------------------------------------------------------------------------
# Pickups & dropping
# ---------------------------------------------------------------------------
func _spawn_pickup(wid: String, pos: Vector3) -> void:
	var pid := _next_pickup
	_next_pickup += 1
	var ground := Combat.ray(pos + Vector3(0, 0.6, 0), pos + Vector3(0, -3.0, 0), Cfg.L_WORLD)
	if not ground.is_empty():
		pos = ground["position"]
	_add_pickup_local(pid, wid, pos)
	_send("cl_pickup_add", [pid, wid, pos])


func _add_pickup_local(pid: int, wid: String, pos: Vector3) -> void:
	var node := Node3D.new()
	node.position = pos + Vector3(0, 0.06, 0)
	if not dedicated:
		var m := WeaponModels.build(wid)
		m.rotation = Vector3(0, randf() * TAU, PI * 0.5)
		node.add_child(m)
	_pickup_root.add_child(node)
	pickups[pid] = {"wid": wid, "pos": pos, "node": node}
	_next_pickup = maxi(_next_pickup, pid + 1)


@rpc("authority", "call_remote", "reliable")
func cl_pickup_add(pid: int, wid: String, pos: Vector3) -> void:
	_add_pickup_local(pid, wid, pos)


func _remove_pickup(pid: int) -> void:
	if not pickups.has(pid):
		return
	var n: Node3D = pickups[pid]["node"]
	n.queue_free()
	pickups.erase(pid)


@rpc("authority", "call_remote", "reliable")
func cl_pickup_remove(pid: int) -> void:
	_remove_pickup(pid)


func clear_pickups() -> void:
	for pid in pickups.keys():
		_remove_pickup(pid)
	_send("cl_clear_pickups", [])


@rpc("authority", "call_remote", "reliable")
func cl_clear_pickups() -> void:
	for pid in pickups.keys():
		_remove_pickup(pid)


func _pickup_in_view(s: Soldier) -> int:
	var best := 0
	var best_d := 2.6
	for pid in pickups.keys():
		var p: Vector3 = pickups[pid]["pos"]
		var d := s.global_position.distance_to(p)
		if d < best_d:
			var to := (p - s.eye_pos()).normalized()
			if to.dot(s.aim_dir()) > 0.75 or d < 1.2:
				best = pid
				best_d = d
	return best


func _auto_pickups() -> void:
	for pid in pickups.keys():
		var p: Vector3 = pickups[pid]["pos"]
		var wid: String = pickups[pid]["wid"]
		for s in alive_soldiers():
			var so: Soldier = s
			if so.global_position.distance_to(p) > 1.1:
				continue
			var w := Cfg.w(wid)
			var ok := false
			if wid == "bomb":
				ok = so.team == Cfg.ATK and game_mode() == Cfg.MODE_DEFUSAL
			elif int(w.get("slot", 0)) == 1:
				ok = so.primary == ""
			elif int(w.get("slot", 0)) == 2:
				ok = so.secondary == ""
			if ok:
				_take_pickup(so, pid, false)
				break


@rpc("any_peer", "call_remote", "reliable")
func sv_pickup(id: String, pid: int) -> void:
	var s := _owned_by_sender(id)
	if s and pickups.has(pid) and s.global_position.distance_to(pickups[pid]["pos"]) < 3.0:
		_take_pickup(s, pid, true)


func _take_pickup(s: Soldier, pid: int, swap: bool) -> void:
	if not pickups.has(pid) or not s.alive:
		return
	var wid: String = pickups[pid]["wid"]
	var pos: Vector3 = pickups[pid]["pos"]
	var w := Cfg.w(wid)
	if wid == "bomb":
		if s.team != Cfg.ATK:
			return
		s.has_bomb = true
		rs["bomb"]["state"] = "carried"
		rs["bomb"]["carrier"] = s.id
		broadcast_rs()
	elif int(w.get("slot", 0)) == 1:
		if s.primary != "":
			if not swap:
				return
			_spawn_pickup(s.primary, s.global_position)
		s.primary = wid
	elif int(w.get("slot", 0)) == 2:
		if s.secondary != "":
			if not swap:
				return
			_spawn_pickup(s.secondary, s.global_position)
		s.secondary = wid
	else:
		return
	_remove_pickup(pid)
	_send("cl_pickup_remove", [pid])
	sync_inventory(s)
	if not dedicated and s == local_soldier:
		Sfx.play("mag_in", -8.0)
	pos = pos


func request_drop() -> void:
	if local_soldier:
		request_drop_for(local_soldier)


func request_drop_for(s: Soldier) -> void:
	if is_server():
		_drop_current(s)
	else:
		_to_server("sv_drop", [s.id, s.cur])


@rpc("any_peer", "call_remote", "reliable")
func sv_drop(id: String, wid: String) -> void:
	var s := _owned_by_sender(id)
	if s:
		s.cur = wid
		_drop_current(s)


func _drop_current(s: Soldier) -> void:
	if not s.alive:
		return
	var front := s.global_position + s.flat_forward() * 1.2
	var blocked := Combat.ray(s.eye_pos(), front + Vector3(0, 1.0, 0), Cfg.L_WORLD | Cfg.L_DYNAMIC)
	if not blocked.is_empty():
		front = s.global_position
	if s.cur == "bomb" and s.has_bomb:
		_drop_bomb(s, front)
	elif s.cur == s.primary and s.primary != "":
		_spawn_pickup(s.primary, front)
		s.primary = ""
	elif s.cur == s.secondary and s.secondary != "":
		_spawn_pickup(s.secondary, front)
		s.secondary = ""
	else:
		return
	sync_inventory(s)


func _drop_bomb(s: Soldier, at := Vector3.INF) -> void:
	s.has_bomb = false
	var pos := s.global_position if at == Vector3.INF else at
	_spawn_pickup("bomb", pos)
	rs["bomb"]["state"] = "dropped"
	rs["bomb"]["carrier"] = ""
	rs["bomb"]["pos"] = pos
	sync_inventory(s)
	broadcast_rs()


# ---------------------------------------------------------------------------
# Buying
# ---------------------------------------------------------------------------
func in_buy_zone(s: Soldier) -> bool:
	if s == null:
		return false
	if game_mode() != Cfg.MODE_DEFUSAL:
		return true
	return world.in_spawn(s.global_position, s.team)


func can_buy(s: Soldier, item: String) -> String:
	if s == null or not s.alive:
		return "You are dead"
	if not mode.buy_allowed(s):
		return "Buy time is over" if game_mode() == Cfg.MODE_DEFUSAL else "Loadout locked"
	if not in_buy_zone(s):
		return "Not in buy zone"
	var team_req := Cfg.item_team(item)
	if team_req >= 0 and team_req != s.team and game_mode() == Cfg.MODE_DEFUSAL:
		return "Not available to your team"
	if item == "bomb":
		return "Not for sale"
	var price := mode.price(s, item)
	if s.money < price:
		return "Not enough money"
	if Cfg.WEAPONS.has(item):
		var w := Cfg.w(item)
		var slot := int(w["slot"])
		if slot == 1 and s.primary == item:
			return "Already owned"
		if slot == 2 and s.secondary == item:
			return "Already owned"
		if slot == 4 and int(s.grenades.get(item, 0)) >= int(w.get("max", 1)):
			return "Carrying the maximum"
		if item == "breach" and s.breach_charges >= int(w.get("max", 2)):
			return "Carrying the maximum"
	else:
		match item:
			"kevlar":
				if s.armor >= 100:
					return "Already owned"
			"helmet":
				if s.armor >= 100 and s.helmet:
					return "Already owned"
			"kit":
				if s.team != Cfg.DEF:
					return "Not available to your team"
				if s.has_kit:
					return "Already owned"
	return ""


func request_buy(item_id: String) -> void:
	if local_soldier == null:
		return
	if is_server():
		server_buy(local_soldier, item_id)
	else:
		_to_server("sv_buy", [item_id])


@rpc("any_peer", "call_remote", "reliable")
func sv_buy(item_id: String) -> void:
	var s: Soldier = soldiers.get("p%d" % _sender())
	if s:
		server_buy(s, item_id)


func server_buy(s: Soldier, item: String) -> void:
	if can_buy(s, item) != "":
		return
	var price := mode.price(s, item)
	if Cfg.WEAPONS.has(item):
		var w := Cfg.w(item)
		match int(w["slot"]):
			1:
				if s.primary != "":
					_spawn_pickup(s.primary, s.global_position + s.flat_forward() * 0.6)
				s.primary = item
				s.ammo.erase(item)
			2:
				if s.secondary != "" and s.secondary != "m9":
					_spawn_pickup(s.secondary, s.global_position + s.flat_forward() * 0.6)
				s.secondary = item
				s.ammo.erase(item)
			4:
				s.grenades[item] = int(s.grenades.get(item, 0)) + 1
			5:
				s.breach_charges += 1
	else:
		match item:
			"kevlar":
				s.armor = 100
			"helmet":
				s.armor = 100
				s.helmet = true
			"kit":
				s.has_kit = true
	s.money -= price
	sync_inventory(s)
	if s == local_soldier:
		Sfx.play("buy", -6.0)


func sync_inventory(s: Soldier) -> void:
	var inv := s.inventory()
	s.set_inventory(inv)
	_send("cl_inv", [s.id, inv])


@rpc("authority", "call_remote", "reliable")
func cl_inv(id: String, inv: Dictionary) -> void:
	var s: Soldier = soldiers.get(id)
	if s:
		var had_primary := s.primary
		s.set_inventory(inv)
		if s == local_soldier and inv.get("primary", "") != had_primary:
			Sfx.play("buy", -8.0)


# ---------------------------------------------------------------------------
# Grenades & breach charges
# ---------------------------------------------------------------------------
func spawn_grenade(owner: Soldier, type: String, origin: Vector3, velocity: Vector3) -> void:
	if is_server():
		var nid := _next_net_id
		_next_net_id += 1
		if owner.is_bot or owner == local_soldier:
			pass
		owner.grenades[type] = maxi(0, int(owner.grenades.get(type, 0)))
		_make_grenade(nid, owner.id, type, origin, velocity)
		_send("cl_grenade", [nid, owner.id, type, origin, velocity])
		_send("cl_inv", [owner.id, owner.inventory()])
	else:
		_to_server("sv_grenade", [owner.id, type, origin, velocity])


@rpc("any_peer", "call_remote", "reliable")
func sv_grenade(id: String, type: String, origin: Vector3, velocity: Vector3) -> void:
	var s := _owned_by_sender(id)
	if s == null or not s.alive or not s.grenades.has(type):
		return
	s.grenades[type] = maxi(0, int(s.grenades[type]) - 1)
	var nid := _next_net_id
	_next_net_id += 1
	_make_grenade(nid, id, type, origin, velocity)
	_send("cl_grenade", [nid, id, type, origin, velocity])
	_send("cl_inv", [id, s.inventory()])


func _make_grenade(nid: int, owner_id: String, type: String, origin: Vector3, velocity: Vector3) -> void:
	var g := Grenade.new()
	g.name = "Grenade%d" % nid
	_proj_root.add_child(g)
	g.setup(nid, type, owner_id, origin, velocity)


@rpc("authority", "call_remote", "reliable")
func cl_grenade(nid: int, owner_id: String, type: String, origin: Vector3, velocity: Vector3) -> void:
	_make_grenade(nid, owner_id, type, origin, velocity)


func grenade_detonated(net_id: int, pos: Vector3) -> void:
	if not is_server():
		return
	_detonate_local(net_id, pos)
	_send("cl_grenade_det", [net_id, pos])


func _detonate_local(net_id: int, pos: Vector3) -> void:
	var g := _proj_root.get_node_or_null("Grenade%d" % net_id)
	if g and g.has_method("detonate"):
		g.detonate(pos)


@rpc("authority", "call_remote", "reliable")
func cl_grenade_det(net_id: int, pos: Vector3) -> void:
	_detonate_local(net_id, pos)


func place_breach(owner: Soldier, pos: Vector3, normal: Vector3) -> void:
	if is_server():
		var nid := _next_net_id
		_next_net_id += 1
		_make_breach(nid, owner.id, pos, normal)
		_send("cl_breach", [nid, owner.id, pos, normal])
		_send("cl_inv", [owner.id, owner.inventory()])
	else:
		_to_server("sv_breach", [owner.id, pos, normal])


@rpc("any_peer", "call_remote", "reliable")
func sv_breach(id: String, pos: Vector3, normal: Vector3) -> void:
	var s := _owned_by_sender(id)
	if s == null or not s.alive or s.global_position.distance_to(pos) > 4.0:
		return
	s.breach_charges = maxi(0, s.breach_charges - 1)
	var nid := _next_net_id
	_next_net_id += 1
	_make_breach(nid, id, pos, normal)
	_send("cl_breach", [nid, id, pos, normal])
	_send("cl_inv", [id, s.inventory()])


func _make_breach(nid: int, owner_id: String, pos: Vector3, normal: Vector3) -> void:
	var b := BreachCharge.new()
	b.name = "Breach%d" % nid
	_proj_root.add_child(b)
	b.setup(nid, owner_id, pos, normal)


@rpc("authority", "call_remote", "reliable")
func cl_breach(nid: int, owner_id: String, pos: Vector3, normal: Vector3) -> void:
	_make_breach(nid, owner_id, pos, normal)


func clear_projectiles() -> void:
	for c in _proj_root.get_children():
		c.queue_free()
	smokes.clear()


# ---------------------------------------------------------------------------
# Bomb
# ---------------------------------------------------------------------------
func request_plant(s: Soldier) -> void:
	if is_server():
		mode.plant(s, s.global_position)
	else:
		_to_server("sv_plant", [s.id, s.global_position])


@rpc("any_peer", "call_remote", "reliable")
func sv_plant(id: String, pos: Vector3) -> void:
	var s := _owned_by_sender(id)
	if s and s.global_position.distance_to(pos) < 3.0:
		mode.plant(s, pos)


func request_defuse(s: Soldier) -> void:
	if is_server():
		mode.defuse(s)
	else:
		_to_server("sv_defuse", [s.id])


@rpc("any_peer", "call_remote", "reliable")
func sv_defuse(id: String) -> void:
	var s := _owned_by_sender(id)
	if s:
		mode.defuse(s)


func notify_defuse(s: Soldier, active: bool) -> void:
	if is_server():
		_set_defusing(active)
		_send("cl_defusing", [active])
		if active:
			noise(s.global_position, 0.6, s.id)
	else:
		_to_server("sv_defusing", [s.id, active])


@rpc("any_peer", "call_remote", "reliable")
func sv_defusing(id: String, active: bool) -> void:
	var s := _owned_by_sender(id)
	if s:
		notify_defuse(s, active)


func _set_defusing(active: bool) -> void:
	if _bomb_prop:
		_bomb_prop.set_defusing(active)
	if active and not dedicated and _bomb_prop:
		Sfx.play3d("defuse", _bomb_prop.global_position, -2.0)


@rpc("authority", "call_remote", "reliable")
func cl_defusing(active: bool) -> void:
	_set_defusing(active)


func set_bomb_prop(pos) -> void:
	_set_bomb_prop(pos)
	_send("cl_bomb_prop", [pos])


func _set_bomb_prop(pos) -> void:
	if _bomb_prop:
		_bomb_prop.queue_free()
		_bomb_prop = null
	if pos == null:
		return
	_bomb_prop = BombProp.new()
	_bomb_prop.name = "BombProp"
	_proj_root.add_child(_bomb_prop)
	_bomb_prop.global_position = pos


@rpc("authority", "call_remote", "reliable")
func cl_bomb_prop(pos) -> void:
	_set_bomb_prop(pos)


func bomb_explode_fx(pos: Vector3) -> void:
	_bomb_fx(pos)
	_send("cl_bomb_fx", [pos])


func _bomb_fx(pos: Vector3) -> void:
	if not dedicated:
		fx.explosion(pos, "bomb")
		if controller:
			controller.on_explosion(pos, 40.0)
	_set_bomb_prop(null)


@rpc("authority", "call_remote", "reliable")
func cl_bomb_fx(pos: Vector3) -> void:
	_bomb_fx(pos)


# ---------------------------------------------------------------------------
# Round state, events, chat, scores
# ---------------------------------------------------------------------------
func _rs_for_send() -> Dictionary:
	return rs.duplicate(true)


func broadcast_rs() -> void:
	if not is_server():
		return
	_send("cl_rs", [_rs_for_send()])


@rpc("authority", "call_remote", "reliable")
func cl_rs(new_rs: Dictionary) -> void:
	rs = new_rs
	_rs_recv_t = now()


func emit_round_event(kind: String, data: Dictionary) -> void:
	_on_round_event(kind, data)
	_send("cl_round_event", [kind, data])


func _on_round_event(kind: String, data: Dictionary) -> void:
	round_event.emit(kind, data)
	if dedicated:
		print("[round] %s %s" % [kind, str(data)])
		return
	# Round sounds (start/win/lose) are played by the HUD.
	if kind == "bomb_defused":
		Sfx.play("defused", -2.0)


@rpc("authority", "call_remote", "reliable")
func cl_round_event(kind: String, data: Dictionary) -> void:
	_on_round_event(kind, data)


func request_chat(text: String, team_only: bool) -> void:
	text = text.strip_edges().left(140)
	if text == "":
		return
	if is_server():
		var s := local_soldier
		_chat_bcast(Cfg.settings["player_name"], s.team if s else -1, text, team_only)
	else:
		_to_server("sv_chat", [text, team_only])


@rpc("any_peer", "call_remote", "reliable")
func sv_chat(text: String, team_only: bool) -> void:
	var s: Soldier = soldiers.get("p%d" % _sender())
	_chat_bcast(Net.peer_name(_sender()), s.team if s else -1, text.strip_edges().left(140), team_only)


func _chat_bcast(from_name: String, team: int, text: String, team_only: bool) -> void:
	if dedicated:
		print("[chat] %s: %s" % [from_name, text])
	chat_message.emit(from_name, team, text, team_only)
	_send("cl_chat", [from_name, team, text, team_only])


func server_message(text: String) -> void:
	_chat_bcast("", -1, text, false)


## Bots use this for radio chatter.
func bot_radio(s: Soldier, text: String) -> void:
	if is_server():
		_chat_bcast(s.display_name, s.team, "(RADIO) " + text, true)


@rpc("authority", "call_remote", "reliable")
func cl_chat(from_name: String, team: int, text: String, team_only: bool) -> void:
	if team_only and local_soldier and team >= 0 and team != local_soldier.team:
		return
	chat_message.emit(from_name, team, text, team_only)
	if team_only:
		Sfx.play("radio", -12.0)


func _send_scores() -> void:
	var arr := []
	for s in soldiers.values():
		var so: Soldier = s
		arr.append([so.id, so.kills, so.deaths, so.score, so.money, so.alive, so.health, so.armor])
	_send("cl_scores", [arr])


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func cl_scores(arr: Array) -> void:
	for e in arr:
		var s: Soldier = soldiers.get(e[0])
		if s == null:
			continue
		s.kills = int(e[1])
		s.deaths = int(e[2])
		s.score = int(e[3])
		s.money = int(e[4])
		if not s.is_authority():
			s.health = int(e[6])
			s.armor = int(e[7])


## Server: reset doors, pickups, projectiles at round start.
func reset_map() -> void:
	world.reset_breakables()
	clear_pickups()
	clear_projectiles()
	_set_bomb_prop(null)
	_send("cl_reset_map", [])


@rpc("authority", "call_remote", "reliable")
func cl_reset_map() -> void:
	world.reset_breakables()
	clear_projectiles()
	_set_bomb_prop(null)


## Server: change map/mode for everyone (map rotation).
func change_map(new_config: Dictionary) -> void:
	_send("cl_change_map", [new_config])
	get_node("/root/Main").call_deferred("restart_game", new_config)


@rpc("authority", "call_remote", "reliable")
func cl_change_map(new_config: Dictionary) -> void:
	get_node("/root/Main").call_deferred("restart_game", new_config)
