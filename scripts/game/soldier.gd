class_name Soldier
extends CharacterBody3D
## A player or bot. The owning peer (bots: server) simulates movement/weapons from a
## command dictionary; other peers interpolate replicated state. See docs/ARCHITECTURE.md.

signal fired(weapon_id: String)
signal reload_started(weapon_id: String, duration: float)
signal weapon_switched(weapon_id: String)
signal knifed(alt: bool)
signal threw(type: String)
signal died(killer_id: String)
signal spawned()

const F_ON_FLOOR := 1
const F_CROUCH := 2
const F_WALK := 4
const F_COVER := 8
const F_AIM := 16
const F_RELOAD := 32
const F_PLANT := 64
const F_DEFUSE := 128
const F_LIGHT := 256
const F_SCOPED := 512

const INTERP_DELAY := 0.1
const SEND_RATE := 1.0 / 30.0

var id := ""
var display_name := ""
var team := 0
var is_bot := false
var owner_peer := 1

var alive := false
var health := 100
var armor := 0
var helmet := false
var has_kit := false
var money := 800
var kills := 0
var deaths := 0
var score := 0

var primary := ""
var secondary := "m9"
var grenades := {"frag": 0, "flash": 0, "smoke": 0}
var has_bomb := false
var breach_charges := 0
var cur := "knife"
var ammo := {}

var yaw := 0.0
var pitch := 0.0
var punch := Vector2.ZERO
var crouch_amount := 0.0
var flags := 0
var scope_level := 0
var ads_amount := 0.0
var action_progress := 0.0
var action_label := ""
var flash_until := 0.0
var flash_strength := 0.0
var spotted_until := 0.0
var spawn_protect_until := 0.0
var last_damage_time := 0.0
var model: SoldierModel
var brain: BotBrain
var controller: Node # PlayerController for the local human

var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _light: SpotLight3D
var _next_fire := 0.0
var _reload_end := 0.0
var _switch_end := 0.0
var _shots := 0
var _last_shot_t := -10.0
var _inaccuracy := 0.0
var _prev_weapon := ""
var _was_on_floor := true
var _fall_speed := 0.0
var _step_dist := 0.0
var _jump_held := false
var _dry_clicked := false
var _use_held := false
var _defusing := false
var _send_accum := 0.0
var _snaps: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	collision_layer = Cfg.L_SOLDIER
	collision_mask = Cfg.L_WORLD | Cfg.L_DYNAMIC
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35
	floor_constant_speed = true
	wall_min_slide_angle = deg_to_rad(10.0)
	_capsule = CapsuleShape3D.new()
	_capsule.radius = Cfg.RADIUS
	_capsule.height = Cfg.STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = Cfg.STAND_HEIGHT * 0.5
	add_child(_shape)
	model = SoldierModel.new()
	add_child(model)
	model.setup(team, hash(id), is_hostile_look())
	_light = SpotLight3D.new()
	_light.light_energy = 3.5
	_light.spot_range = 22.0
	_light.spot_angle = 24.0
	_light.light_color = Color(1.0, 0.96, 0.88)
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	_rng.seed = hash(id) ^ Time.get_ticks_usec()


func setup(info: Dictionary) -> void:
	id = info["id"]
	name = id
	display_name = info.get("name", id)
	team = int(info.get("team", 0))
	is_bot = bool(info.get("bot", false))
	owner_peer = int(info.get("peer", 1))


func is_hostile_look() -> bool:
	return Game.inst != null and Game.inst.config.get("mode", "") == Cfg.MODE_HUNT and team == 1


func is_authority() -> bool:
	if is_bot:
		return Net.is_server()
	return owner_peer == Net.my_id()


func is_local_player() -> bool:
	return not is_bot and owner_peer == Net.my_id()


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func eye_height() -> float:
	return lerpf(Cfg.STAND_EYE, Cfg.CROUCH_EYE, crouch_amount)


func eye_pos() -> Vector3:
	return global_position + Vector3(0, eye_height(), 0)


func aim_dir() -> Vector3:
	var p := pitch + deg_to_rad(punch.x)
	var y := yaw + deg_to_rad(punch.y)
	return Vector3(-sin(y) * cos(p), sin(p), -cos(y) * cos(p))


func flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func weapon_data() -> Dictionary:
	return Cfg.w(cur)


func has_flag(f: int) -> bool:
	return flags & f != 0


# ---------------------------------------------------------------------------
# Frame update
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if Game.inst == null:
		return
	if not alive:
		if is_authority() and not is_on_floor():
			velocity.y -= Cfg.GRAVITY * delta
			velocity.x = 0.0
			velocity.z = 0.0
		return
	if is_authority():
		var cmd := {}
		if is_bot and brain != null:
			cmd = brain.think(delta)
		elif controller != null and controller.has_method("make_cmd"):
			cmd = controller.make_cmd(delta)
		simulate(cmd, delta)
		_send_accum += delta
		if _send_accum >= SEND_RATE:
			_send_accum = 0.0
			Game.inst.send_state(self)
	else:
		_interpolate()


func _process(delta: float) -> void:
	if model:
		model.rotation.y = yaw
		model.update_anim(delta, self)
	if _light:
		var on := alive and has_flag(F_LIGHT)
		_light.visible = on
		if on:
			_light.position = Vector3(0, eye_height() - 0.1, 0)
			_light.rotation = Vector3(pitch, yaw, 0)


# ---------------------------------------------------------------------------
# Simulation (authority only)
# ---------------------------------------------------------------------------
func simulate(cmd: Dictionary, delta: float) -> void:
	var g := Game.inst
	var frozen := g.movement_frozen()
	yaw = float(cmd.get("yaw", yaw))
	pitch = clampf(float(cmd.get("pitch", pitch)), deg_to_rad(-88.0), deg_to_rad(88.0))
	var locked := has_flag(F_PLANT) or has_flag(F_DEFUSE)
	var move: Vector2 = cmd.get("move", Vector2.ZERO)
	if frozen or locked:
		move = Vector2.ZERO
	var walk: bool = cmd.get("walk", false)
	_update_crouch(bool(cmd.get("crouch", false)) or locked, delta)
	var want_jump: bool = cmd.get("jump", false)
	_move(move, want_jump and not frozen and not locked and not _jump_held, walk, delta)
	_jump_held = want_jump
	_weapons(cmd, delta, frozen)
	_actions(cmd, delta)
	if cmd.get("light", false):
		flags ^= F_LIGHT
	var f := flags & (F_LIGHT | F_PLANT | F_DEFUSE | F_COVER)
	if is_on_floor():
		f |= F_ON_FLOOR
	if crouch_amount > 0.5:
		f |= F_CROUCH
	if walk:
		f |= F_WALK
	if ads_amount > 0.5:
		f |= F_AIM
	if _reload_end > 0.0:
		f |= F_RELOAD
	if scope_level > 0:
		f |= F_SCOPED
	if cmd.get("cover", false):
		f |= F_COVER
	else:
		f &= ~F_COVER
	flags = f


func _max_speed(walk: bool) -> float:
	var w := weapon_data()
	var sp: float = w.get("speed", 6.0)
	if scope_level > 0:
		sp *= 0.72
	elif ads_amount > 0.5:
		sp *= 0.8
	if crouch_amount > 0.5:
		sp *= Cfg.CROUCH_MULT
	elif walk:
		sp *= Cfg.WALK_MULT
	return sp


func _accelerate(v: Vector3, wishdir: Vector3, wishspeed: float, cap: float, accel: float, delta: float) -> Vector3:
	var current := Vector3(v.x, 0, v.z).dot(wishdir)
	var add := minf(wishspeed, cap) - current
	if add <= 0.0:
		return v
	var acc := minf(accel * delta * wishspeed, add)
	v.x += acc * wishdir.x
	v.z += acc * wishdir.z
	return v


func _move(move: Vector2, jump: bool, walk: bool, delta: float) -> void:
	var fwd := flat_forward()
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var wish := fwd * move.y + right * move.x
	var wl := wish.length()
	var wishdir := wish / wl if wl > 0.01 else Vector3.ZERO
	var wishspeed := _max_speed(walk) * minf(wl, 1.0)
	var v := velocity
	var on_floor := is_on_floor()
	if on_floor:
		if jump:
			v.y = Cfg.JUMP_VELOCITY
			on_floor = false
			Game.inst.noise(global_position, 0.5, id)
		else:
			var speed := Vector2(v.x, v.z).length()
			if speed > 0.001:
				var control := maxf(speed, Cfg.STOP_SPEED)
				var drop := control * Cfg.FRICTION * delta
				var k := maxf(speed - drop, 0.0) / speed
				v.x *= k
				v.z *= k
			v = _accelerate(v, wishdir, wishspeed, wishspeed, Cfg.GROUND_ACCEL, delta)
	if not on_floor:
		v = _accelerate(v, wishdir, wishspeed, Cfg.AIR_WISH_CAP, Cfg.AIR_ACCEL, delta)
		v.y -= Cfg.GRAVITY * delta
	velocity = v
	move_and_slide()
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		if _fall_speed > 4.0:
			Sfx.play3d("land", global_position, -6.0 + minf(_fall_speed, 12.0) * 0.6)
		if _fall_speed > 11.5 and Net.is_server():
			Game.inst.apply_damage(self, id, (_fall_speed - 11.5) * 9.0, Combat.Z_LEGS, "fall", Vector3.DOWN, 1.0)
	if not grounded:
		_fall_speed = maxf(-velocity.y, 0.0)
	_was_on_floor = grounded
	# Footsteps (and noise for bots) when running.
	var hs := Vector2(velocity.x, velocity.z).length()
	if grounded and hs > 3.0 and not walk and crouch_amount < 0.5:
		_step_dist += hs * delta
		if _step_dist > 2.3:
			_step_dist = 0.0
			Game.inst.footstep(self)
	else:
		_step_dist = minf(_step_dist, 1.6)


func _update_crouch(want: bool, delta: float) -> void:
	var target := 1.0 if want else 0.0
	if target < crouch_amount and not _can_stand():
		target = crouch_amount
	crouch_amount = move_toward(crouch_amount, target, delta / 0.14)
	var h := lerpf(Cfg.STAND_HEIGHT, Cfg.CROUCH_HEIGHT, crouch_amount)
	if absf(_capsule.height - h) > 0.001:
		_capsule.height = h
		_shape.position.y = h * 0.5


func _can_stand() -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Cfg.RADIUS - 0.02
	cap.height = Cfg.STAND_HEIGHT - 0.05
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0, Cfg.STAND_HEIGHT * 0.5 + 0.03, 0))
	q.collision_mask = Cfg.L_WORLD | Cfg.L_DYNAMIC
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


# ---------------------------------------------------------------------------
# Weapons
# ---------------------------------------------------------------------------
func ensure_ammo(wid: String) -> void:
	var w := Cfg.w(wid)
	if w.has("mag") and not ammo.has(wid):
		ammo[wid] = [int(w["mag"]), int(w["reserve"])]


func owns(wid: String) -> bool:
	if wid == "knife":
		return true
	if wid == primary or wid == secondary:
		return wid != ""
	if grenades.has(wid):
		return int(grenades[wid]) > 0
	if wid == "bomb":
		return has_bomb
	if wid == "breach":
		return breach_charges > 0
	return false


func best_weapon() -> String:
	if primary != "":
		return primary
	if secondary != "":
		return secondary
	return "knife"


func switch_to(wid: String, instant := false) -> void:
	if wid == "" or wid == cur or not owns(wid):
		return
	_prev_weapon = cur
	cur = wid
	ensure_ammo(wid)
	scope_level = 0
	_reload_end = 0.0
	_shots = 0
	var w := weapon_data()
	_switch_end = 0.0 if instant else now() + float(w.get("deploy", 0.45))
	_next_fire = maxf(_next_fire, _switch_end)
	weapon_switched.emit(wid)
	if model:
		model.set_weapon(wid)


func _select_slot(slot: int) -> void:
	match slot:
		1:
			switch_to(primary)
		2:
			switch_to(secondary)
		3:
			switch_to("knife")
		4:
			var start := Cfg.GRENADE_ORDER.find(cur)
			for i in range(1, Cfg.GRENADE_ORDER.size() + 1):
				var g: String = Cfg.GRENADE_ORDER[(start + i) % Cfg.GRENADE_ORDER.size()] if start >= 0 else Cfg.GRENADE_ORDER[i - 1]
				if owns(g):
					switch_to(g)
					return
		5:
			if has_bomb:
				switch_to("bomb")
			elif breach_charges > 0:
				switch_to("breach")


func _cycle(dir: int) -> void:
	var order := [primary, secondary, "knife", "frag", "flash", "smoke", "bomb", "breach"]
	var avail := []
	for o in order:
		if o != "" and owns(o):
			avail.append(o)
	if avail.is_empty():
		return
	var i := avail.find(cur)
	switch_to(avail[(i + dir + avail.size()) % avail.size()])


func current_spread() -> float:
	var w := weapon_data()
	if not w.has("spread"):
		return 0.0
	var cls: String = w["cls"]
	var sp: float = w["spread"]
	if cls == "sniper":
		sp = float(w["spread_scoped"]) if scope_level > 0 else float(w["spread"])
	var hs := Vector2(velocity.x, velocity.z).length()
	var mv := clampf(hs / maxf(float(w.get("speed", 6.0)), 1.0), 0.0, 1.0)
	sp += float(w["spread_move"]) * mv * mv
	if alive and not has_flag(F_ON_FLOOR) and not is_on_floor():
		sp += float(w["spread_air"])
	sp += _inaccuracy
	if crouch_amount > 0.5:
		sp *= 0.75
	if ads_amount > 0.5 and cls != "sniper":
		sp *= 0.6
	if has_flag(F_COVER) and ads_amount < 0.5:
		sp += 5.0 # blind fire
	return sp


func _spread_dir(dir: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.0:
		return dir
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(dir).normalized()
	var r := tan(deg_to_rad(spread_deg * _rng.randf()))
	var a := _rng.randf() * TAU
	return (dir + right * cos(a) * r + up * sin(a) * r).normalized()


func _weapons(cmd: Dictionary, delta: float, frozen: bool) -> void:
	var t := now()
	var slot: int = cmd.get("slot", 0)
	if slot > 0:
		_select_slot(slot)
	elif int(cmd.get("cycle", 0)) != 0:
		_cycle(int(cmd["cycle"]))
	if cmd.get("last", false) and _prev_weapon != "":
		switch_to(_prev_weapon)
	if cmd.get("drop", false):
		Game.inst.request_drop_for(self)
	if not owns(cur):
		switch_to(best_weapon(), true)
	var w := weapon_data()
	var cls: String = w.get("cls", "")
	if _reload_end > 0.0 and t >= _reload_end:
		_finish_reload()
	# Recoil recovery.
	if t - _last_shot_t > maxf(float(w.get("rof", 0.1)) * 1.5, 0.15):
		punch = punch.lerp(Vector2.ZERO, clampf(delta * 6.0, 0.0, 1.0))
		if t - _last_shot_t > 0.35:
			_shots = 0
	_inaccuracy = move_toward(_inaccuracy, 0.0, delta * 5.0)
	# ADS / scope
	var aim_held: bool = cmd.get("alt", false)
	if cls == "sniper":
		if cmd.get("alt_pressed", false) and _reload_end == 0.0:
			var levels: Array = w.get("scope", [])
			scope_level = (scope_level + 1) % (levels.size() + 1)
			Sfx.play3d("click", eye_pos(), -10.0)
		ads_amount = 0.0
	elif cls in ["pistol", "smg", "rifle", "lmg", "shotgun"]:
		var target := 1.0 if aim_held and _reload_end == 0.0 and t >= _switch_end else 0.0
		ads_amount = move_toward(ads_amount, target, delta / 0.16)
	else:
		ads_amount = move_toward(ads_amount, 0.0, delta / 0.16)
	if frozen or has_flag(F_PLANT) or has_flag(F_DEFUSE) or t < _switch_end:
		return
	match cls:
		"knife":
			if t >= _next_fire:
				if cmd.get("fire", false):
					_knife(false)
				elif cmd.get("alt", false):
					_knife(true)
		"grenade":
			if t >= _next_fire and (cmd.get("fire_pressed", false) or cmd.get("alt_pressed", false)):
				_throw(cur, bool(cmd.get("alt_pressed", false)))
		"breach":
			if t >= _next_fire and cmd.get("fire_pressed", false):
				_place_breach()
		"bomb":
			pass
		_:
			if not w.has("mag"):
				return
			ensure_ammo(cur)
			var a: Array = ammo[cur]
			if cmd.get("reload", false):
				start_reload()
			var want: bool = cmd.get("fire", false) if w.get("auto", false) else cmd.get("fire_pressed", false)
			if not cmd.get("fire", false):
				_dry_clicked = false
			if want and t >= _next_fire:
				if cls == "shotgun" and _reload_end > 0.0 and int(a[0]) > 0:
					_reload_end = 0.0
				if _reload_end > 0.0:
					return
				if int(a[0]) > 0:
					_fire()
				elif not _dry_clicked:
					_dry_clicked = true
					Sfx.play3d("dry", eye_pos(), -6.0)
					if int(a[1]) > 0:
						start_reload()


func start_reload() -> void:
	var w := weapon_data()
	if not w.has("mag") or _reload_end > 0.0:
		return
	var a: Array = ammo.get(cur, [0, 0])
	if int(a[0]) >= int(w["mag"]) or int(a[1]) <= 0:
		return
	var dur: float = w["reload"]
	_reload_end = now() + dur
	scope_level = 0
	reload_started.emit(cur, dur)
	if model:
		model.play_reload(dur)
	Sfx.play3d("mag_out", eye_pos(), -4.0)


func _finish_reload() -> void:
	var w := weapon_data()
	var a: Array = ammo.get(cur, [0, 0])
	if w.get("cls", "") == "shotgun":
		if int(a[1]) > 0 and int(a[0]) < int(w["mag"]):
			a[0] = int(a[0]) + 1
			a[1] = int(a[1]) - 1
			Sfx.play3d("shell", eye_pos(), -4.0)
		if int(a[0]) < int(w["mag"]) and int(a[1]) > 0:
			_reload_end = now() + float(w["reload"])
			return
		Sfx.play3d("pump", eye_pos(), -4.0)
	else:
		var take := mini(int(w["mag"]) - int(a[0]), int(a[1]))
		a[0] = int(a[0]) + take
		a[1] = int(a[1]) - take
		Sfx.play3d("mag_in", eye_pos(), -4.0)
	ammo[cur] = a
	_reload_end = 0.0


func reload_progress() -> float:
	if _reload_end <= 0.0:
		return -1.0
	var w := weapon_data()
	var dur: float = w.get("reload", 1.0)
	return clampf(1.0 - (_reload_end - now()) / dur, 0.0, 1.0)


func _fire() -> void:
	var w := weapon_data()
	var wid := cur
	var a: Array = ammo[wid]
	a[0] = int(a[0]) - 1
	var t := now()
	_next_fire = t + float(w["rof"])
	_last_shot_t = t
	var spread := current_spread()
	var origin := eye_pos()
	var base_dir := aim_dir()
	var pellets := int(w.get("pellets", 1))
	var ends := PackedVector3Array()
	var hits := []
	var impacts := []
	for i in pellets:
		var dir := _spread_dir(base_dir, spread)
		var res := Combat.trace_bullet(self, origin, dir, w)
		ends.append(res["end"])
		hits.append_array(res["hits"])
		impacts.append_array(res["impacts"])
	var pat: Array = Cfg.recoil_patterns.get(wid, [])
	if not pat.is_empty():
		var k: Vector2 = pat[mini(_shots, pat.size() - 1)]
		var mult := 0.75 if crouch_amount > 0.5 else 1.0
		if ads_amount > 0.5:
			mult *= 0.85
		punch.x = minf(punch.x + k.x * mult, float(w["recoil"]) * 9.0)
		punch.y += k.y * mult
	_shots += 1
	_inaccuracy = minf(_inaccuracy + float(w.get("spread_fire", 0.5)), float(w.get("spread_fire", 0.5)) * 7.0 + 1.0)
	if w["cls"] == "sniper" and float(w["rof"]) > 1.0:
		scope_level = 0
		Sfx.play3d("bolt", origin, -6.0)
	fired.emit(wid)
	if model:
		model.play_fire()
	Game.inst.on_local_shot(self, wid, origin, ends, impacts, hits)


func _knife(alt: bool) -> void:
	var w := weapon_data()
	_next_fire = now() + float(w["rof_alt"] if alt else w["rof"])
	var dmg: float = w["dmg_alt"] if alt else w["dmg"]
	var res := Combat.melee(self, eye_pos(), aim_dir(), float(w["reach"]))
	knifed.emit(alt)
	if model:
		model.play_knife()
	Sfx.play3d("knife", eye_pos(), -4.0)
	if not res.is_empty():
		var victim: Soldier = res.get("victim")
		if victim:
			# Back-stabs hit much harder.
			if victim.flat_forward().dot(flat_forward()) > 0.5:
				dmg *= 3.0
		Game.inst.on_local_melee(self, res, dmg)


func _throw(type: String, lob: bool) -> void:
	_next_fire = now() + 0.9
	grenades[type] = maxi(0, int(grenades[type]) - 1)
	var dir := aim_dir()
	var speed := 9.0 if lob else 17.5
	var vel := dir * speed + Vector3(0, 2.2 if lob else 1.6, 0) + velocity * 0.6
	var origin := eye_pos() + dir * 0.35 + Vector3(0, -0.1, 0)
	threw.emit(type)
	if model:
		model.play_throw()
	Sfx.play3d("pin", origin, -8.0)
	Game.inst.spawn_grenade(self, type, origin, vel)
	if not owns(type):
		get_tree().create_timer(0.45).timeout.connect(func():
			if alive and cur == type:
				switch_to(best_weapon()))


func _place_breach() -> void:
	var space := get_world_3d().direct_space_state
	var from := eye_pos()
	var q := PhysicsRayQueryParameters3D.create(from, from + aim_dir() * 2.2, Cfg.L_WORLD | Cfg.L_DYNAMIC)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	_next_fire = now() + 1.0
	breach_charges = maxi(0, breach_charges - 1)
	Game.inst.place_breach(self, hit["position"], hit["normal"])
	if breach_charges <= 0:
		get_tree().create_timer(0.4).timeout.connect(func():
			if alive and cur == "breach":
				switch_to(best_weapon()))


# ---------------------------------------------------------------------------
# Use / plant / defuse
# ---------------------------------------------------------------------------
func _actions(cmd: Dictionary, delta: float) -> void:
	var g := Game.inst
	var use: bool = cmd.get("use", false)
	var use_pressed := use and not _use_held
	_use_held = use
	var bomb: Dictionary = g.rs["bomb"]
	# Planting: hold fire with the charge selected (or hold use) inside a site.
	var plant_input := (cur == "bomb" and bool(cmd.get("fire", false))) or (use and has_bomb)
	if has_bomb and plant_input and is_on_floor() and g.world.in_site(global_position) != "" and g.rs["phase"] == "live":
		if not has_flag(F_PLANT):
			flags |= F_PLANT
			action_progress = 0.0
			Sfx.play3d("plant", global_position, -4.0)
			if cur != "bomb":
				switch_to("bomb", true)
		action_label = "PLANTING"
		action_progress += delta / Cfg.PLANT_TIME
		if action_progress >= 1.0:
			flags &= ~F_PLANT
			action_progress = 0.0
			action_label = ""
			g.request_plant(self)
		return
	elif has_flag(F_PLANT):
		flags &= ~F_PLANT
		action_progress = 0.0
		action_label = ""
	# Defusing: hold use near the planted charge.
	var can_defuse: bool = team == Cfg.DEF and bomb["state"] == "planted" and use and is_on_floor() \
		and global_position.distance_to(bomb["pos"]) < 1.7
	if can_defuse:
		if not has_flag(F_DEFUSE):
			flags |= F_DEFUSE
			action_progress = 0.0
			g.notify_defuse(self, true)
		action_label = "DEFUSING"
		action_progress += delta / (Cfg.DEFUSE_TIME_KIT if has_kit else Cfg.DEFUSE_TIME)
		if action_progress >= 1.0:
			flags &= ~F_DEFUSE
			action_progress = 0.0
			action_label = ""
			g.request_defuse(self)
		return
	elif has_flag(F_DEFUSE):
		flags &= ~F_DEFUSE
		action_progress = 0.0
		action_label = ""
		g.notify_defuse(self, false)
	if use_pressed:
		g.use_pressed(self)


# ---------------------------------------------------------------------------
# State changes (all peers)
# ---------------------------------------------------------------------------
func respawn_at(xf: Transform3D) -> void:
	alive = true
	health = 100
	global_position = xf.origin
	yaw = xf.basis.get_euler().y
	pitch = 0.0
	velocity = Vector3.ZERO
	punch = Vector2.ZERO
	crouch_amount = 0.0
	flags = 0
	scope_level = 0
	ads_amount = 0.0
	action_progress = 0.0
	action_label = ""
	flash_until = 0.0
	_reload_end = 0.0
	_switch_end = 0.0
	_next_fire = 0.0
	_inaccuracy = 0.0
	_shots = 0
	_snaps.clear()
	_shape.set_deferred("disabled", false)
	_capsule.height = Cfg.STAND_HEIGHT
	_shape.position.y = Cfg.STAND_HEIGHT * 0.5
	if model:
		model.reset()
		model.visible = true
	cur = best_weapon()
	ensure_ammo(primary)
	ensure_ammo(secondary)
	if model:
		model.set_weapon(cur)
	spawned.emit()


func kill(killer_id: String, dir: Vector3) -> void:
	if not alive:
		return
	alive = false
	health = 0
	flags = 0
	scope_level = 0
	ads_amount = 0.0
	action_progress = 0.0
	velocity = Vector3.ZERO
	_shape.set_deferred("disabled", true)
	if model:
		model.die(dir)
	died.emit(killer_id)


func apply_flash(strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	if strength <= 0.02:
		return
	var until := now() + 0.4 + strength * 4.2
	if until > flash_until:
		flash_until = until
		flash_strength = strength
	if Net.is_server() and not is_bot and owner_peer != Net.my_id() and Game.inst:
		Game.inst.send_flash(self, strength)


func is_flashed() -> bool:
	return now() < flash_until


func flash_amount() -> float:
	var left := flash_until - now()
	if left <= 0.0:
		return 0.0
	return clampf(left / 1.5, 0.0, 1.0) * flash_strength


func inventory() -> Dictionary:
	return {"primary": primary, "secondary": secondary, "grenades": grenades.duplicate(), "bomb": has_bomb,
		"breach": breach_charges, "kit": has_kit, "armor": armor, "helmet": helmet, "money": money}


func set_inventory(inv: Dictionary) -> void:
	var old_primary := primary
	primary = inv.get("primary", primary)
	secondary = inv.get("secondary", secondary)
	grenades = (inv.get("grenades", grenades) as Dictionary).duplicate()
	has_bomb = inv.get("bomb", has_bomb)
	breach_charges = int(inv.get("breach", breach_charges))
	has_kit = inv.get("kit", has_kit)
	armor = int(inv.get("armor", armor))
	helmet = inv.get("helmet", helmet)
	money = int(inv.get("money", money))
	if primary != old_primary and primary != "":
		ammo.erase(primary)
	ensure_ammo(primary)
	ensure_ammo(secondary)
	if is_authority():
		if primary != old_primary and primary != "" and alive:
			switch_to(primary)
		elif not owns(cur):
			switch_to(best_weapon(), true)


# ---------------------------------------------------------------------------
# Replication
# ---------------------------------------------------------------------------
func get_state() -> Array:
	return [global_position, velocity, yaw, pitch, flags, crouch_amount, cur, ads_amount]


func push_state(st: Array) -> void:
	_snaps.append([now(), st])
	if _snaps.size() > 20:
		_snaps.pop_front()
	var wid: String = st[6]
	if wid != cur:
		cur = wid
		if model:
			model.set_weapon(wid)
	flags = int(st[4])
	ads_amount = float(st[7])


func force_position(pos: Vector3, p_yaw: float) -> void:
	global_position = pos
	yaw = p_yaw
	velocity = Vector3.ZERO
	_snaps.clear()


func _interpolate() -> void:
	if _snaps.is_empty():
		return
	var rt := now() - INTERP_DELAY
	var a: Array = _snaps[0]
	var b: Array = _snaps[_snaps.size() - 1]
	if rt <= float(a[0]):
		_apply_snap(a[1], a[1], 0.0)
		return
	if rt >= float(b[0]):
		_apply_snap(b[1], b[1], 0.0)
		return
	for i in range(_snaps.size() - 1):
		var s0: Array = _snaps[i]
		var s1: Array = _snaps[i + 1]
		if rt >= float(s0[0]) and rt <= float(s1[0]):
			var k := (rt - float(s0[0])) / maxf(float(s1[0]) - float(s0[0]), 0.0001)
			_apply_snap(s0[1], s1[1], k)
			return


func _apply_snap(s0: Array, s1: Array, k: float) -> void:
	global_position = (s0[0] as Vector3).lerp(s1[0], k)
	velocity = (s0[1] as Vector3).lerp(s1[1], k)
	yaw = lerp_angle(float(s0[2]), float(s1[2]), k)
	pitch = lerpf(float(s0[3]), float(s1[3]), k)
	crouch_amount = lerpf(float(s0[5]), float(s1[5]), k)
	var h := lerpf(Cfg.STAND_HEIGHT, Cfg.CROUCH_HEIGHT, crouch_amount)
	_capsule.height = h
	_shape.position.y = h * 0.5
