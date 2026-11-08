class_name BotBrain
extends Node
## Server-side AI for bot soldiers. Produces the same command dictionary a human's
## PlayerController does: perception -> objective -> navigation -> combat.

const RADIO_COOLDOWN := 10.0
const MEMORY := 5.0
static var _team_radio_t := {0: -100.0, 1: -100.0}
static var _site_alert := {"A": -100.0, "B": -100.0}

var s: Soldier
var diff := 1
var reaction := 0.45
var aim_err := 4.5
var turn_rate := 420.0
var spray_comp := 0.45
var head_pref := 0.15
var aim_decay := 1.8
var see_range := 70.0
var fov_cos := cos(deg_to_rad(57.0))

var yaw := 0.0
var pitch := 0.0
var _rng := RandomNumberGenerator.new()

# Perception
var _perc_t := 0.0
var target: Soldier
var target_visible := false
var _acquire_t := 0.0
var _last_seen_t := -100.0
var last_known := Vector3.INF
var _aim_off := Vector3.ZERO
var _aim_head := false
var _crouch_fire := false
var heard_pos := Vector3.INF
var _heard_t := -100.0
var _hurt_t := -100.0

# Navigation
var goal := Vector3.INF
var path := PackedVector3Array()
var path_i := 0
var _repath_t := 0.0
var _stuck_t := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_n := 0
var _unstuck_until := 0.0
var _unstuck_dir := Vector3.ZERO
var _jump_until := 0.0
var _door_t := 0.0
var _use_flip := false

# Objectives
var task := "idle"
var _decide_t := 0.0
var _site := "A"
var _site_point := Vector3.INF
var _hold_point := Vector3.INF
var _hold_look := Vector3.INF
var _hold_crouch := false
var _wander_until := 0.0
var _retreat_until := 0.0
var _retreat_point := Vector3.INF
var _camp := false
var _home := Vector3.ZERO
var _wait_until := 0.0
var _said_plant := false
var _said_defuse := false
var _said_clear := false
var _rotated := false

# Firing
var _semi := false
var _burst_start := -1.0
var _burst_pause_until := 0.0
var _strafe := 1.0
var _strafe_t := 0.0
var _scope_wait := 0.0
var _alt_flip := false

# Grenades
var _nade := {}
var _flash_used := false
var _smoke_used := false
var _nade_check_t := 0.0

var _last_radio := -100.0


func setup(p_s: Soldier, difficulty: int) -> void:
	s = p_s
	diff = clampi(difficulty, 0, 3)
	reaction = [0.7, 0.45, 0.28, 0.18][diff]
	aim_err = [7.0, 4.5, 2.8, 1.6][diff]
	turn_rate = [280.0, 420.0, 620.0, 900.0][diff]
	spray_comp = [0.15, 0.45, 0.7, 0.9][diff]
	head_pref = [0.05, 0.15, 0.35, 0.55][diff]
	aim_decay = [1.0, 1.8, 2.8, 4.0][diff]
	# Squad Hunt: hostiles are many but weaker; squad bots are a little sharper.
	if Game.inst and Game.inst.game_mode() == Cfg.MODE_HUNT:
		if s.team == 1:
			reaction *= 1.5
			aim_err *= 1.6
			aim_decay *= 0.7
			head_pref *= 0.5
			see_range = 45.0
			fov_cos = cos(deg_to_rad(50.0))
		else:
			reaction *= 0.85
			aim_err *= 0.8
	_rng.seed = hash(s.id) ^ Time.get_ticks_usec()
	_perc_t = _rng.randf() * 0.15
	yaw = s.yaw


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
func on_round_start() -> void:
	yaw = s.yaw
	pitch = 0.0
	target = null
	target_visible = false
	last_known = Vector3.INF
	heard_pos = Vector3.INF
	_last_seen_t = -100.0
	_heard_t = -100.0
	goal = Vector3.INF
	path = PackedVector3Array()
	task = "idle"
	_site_point = Vector3.INF
	_hold_point = Vector3.INF
	_hold_look = Vector3.INF
	_hold_crouch = _rng.randf() < 0.3
	_retreat_until = 0.0
	_nade.clear()
	_flash_used = false
	_smoke_used = false
	_said_plant = false
	_said_defuse = false
	_said_clear = false
	_rotated = false
	_stuck_n = 0
	_home = s.global_position
	_camp = _rng.randf() < 0.4
	_wander_until = 0.0
	_decide_t = 0.0
	var g := Game.inst
	if g == null:
		return
	if g.game_mode() == Cfg.MODE_DEFUSAL and s.team == Cfg.DEF:
		var defs := []
		for o in g.team_soldiers(Cfg.DEF):
			if o.is_bot:
				defs.append(o.id)
		defs.sort()
		var idx := defs.find(s.id)
		_site = "A" if (idx + int(g.rs.get("round", 1))) % 2 == 0 else "B"
		if _rng.randf() < 0.2:
			_site = "B" if _site == "A" else "A"
	if g.game_mode() == Cfg.MODE_DEFUSAL and s.team == Cfg.ATK:
		var atks := []
		for o in g.team_soldiers(Cfg.ATK):
			if o.is_bot:
				atks.append(o.id)
		atks.sort()
		if not atks.is_empty() and atks[0] == s.id and _rng.randf() < 0.6:
			_radio("Going %s, stick together." % g.mode.atk_plan, 1.0)


func on_damaged(attacker_id: String, dir: Vector3) -> void:
	var g := Game.inst
	if g == null:
		return
	var t := now()
	_hurt_t = t
	var a: Soldier = g.soldiers.get(attacker_id)
	if a and a.team != s.team:
		heard_pos = a.global_position
		_heard_t = t
		if target == null:
			last_known = a.global_position
	if s.health < 30 and s.health > 0:
		_radio("Taking fire, need backup!", 0.12)


# ---------------------------------------------------------------------------
# Buying
# ---------------------------------------------------------------------------
func _buy(item: String) -> bool:
	var g := Game.inst
	if g.can_buy(s, item) != "":
		return false
	g.server_buy(s, item)
	return true


func buy_loadout() -> void:
	var g := Game.inst
	if g == null or not s.alive:
		return
	var mode := g.game_mode()
	if mode != Cfg.MODE_DEFUSAL:
		if mode == Cfg.MODE_HUNT and s.team == 1:
			if _rng.randf() < 0.4:
				_buy("frag")
			return
		var picks := ["kv74", "ar7", "hornet", "vespa", "mako", "breacher", "thresher", "sentry", "longbow", "kv74", "ar7"]
		if s.primary == "" or _rng.randf() < 0.5:
			_buy(picks[_rng.randi() % picks.size()])
		_buy("helmet")
		for n in ["frag", "flash", "smoke"]:
			if _rng.randf() < 0.5:
				_buy(n)
		return
	var rifle := "kv74" if s.team == Cfg.ATK else "ar7"
	var first_round := int(g.rs.get("round", 1)) == 1 or int(g.rs.get("round", 1)) == g.mode.max_rounds() / 2 + 1
	if first_round:
		var r := _rng.randf()
		if r < 0.45:
			_buy("kevlar")
		elif r < 0.7:
			_buy("hawk")
		else:
			_buy("flash")
			_buy("frag")
		return
	if s.primary == "":
		var m := s.money
		var rifle_price := Cfg.item_price(rifle)
		var save := m < rifle_price and m < 2300 and _rng.randf() < 0.55
		if not save:
			if m >= rifle_price + 1000:
				var r := _rng.randf()
				var choice := rifle
				if m >= 6000 and r < 0.12:
					choice = "longbow"
				elif m >= 6500 and r < 0.18:
					choice = "thresher"
				elif r < 0.26:
					choice = "hornet"
				elif r < 0.33 and m >= 4800:
					choice = "sentry"
				if not _buy(choice):
					_buy(rifle)
			elif m >= rifle_price:
				_buy(rifle)
			elif m >= 1700:
				var smg := ["vespa", "mako", "breacher", "vespa"]
				_buy(smg[_rng.randi() % smg.size()])
		elif m >= 700 and _rng.randf() < 0.4:
			_buy("hawk")
	if s.armor < 100 or not s.helmet:
		if not _buy("helmet"):
			_buy("kevlar")
	if s.team == Cfg.DEF and not s.has_kit and s.money >= 900 and _rng.randf() < 0.65:
		_buy("kit")
	if s.money >= 500 and _rng.randf() < 0.6:
		_buy("frag")
	if s.money >= 400 and _rng.randf() < 0.5:
		_buy("flash")
	if s.money >= 600 and _rng.randf() < 0.35:
		_buy("smoke")
	if s.money >= 2500 and _rng.randf() < 0.1:
		_buy("breach")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func think(delta: float) -> Dictionary:
	var g := Game.inst
	if g == null or s == null or not s.alive:
		return {}
	var t := now()
	var cmd := {}
	_perc_t -= delta
	if _perc_t <= 0.0:
		_perc_t = 0.14 + _rng.randf() * 0.04
		_perceive(g, t)
	if target and (not is_instance_valid(target) or not target.alive):
		target = null
		target_visible = false
	var engaged := target != null and target_visible and t - _acquire_t >= reaction
	var move := Vector3.ZERO
	var walk := false
	var crouch := false
	_manage_weapon(cmd, engaged, t)
	if engaged:
		_nade.clear()
		var res := _combat(cmd, delta, t, g)
		move = res["move"]
		crouch = res["crouch"]
		walk = res["walk"]
		if t < _retreat_until:
			_set_goal(_retreat_point)
			move = _follow(g, t)
	else:
		_release_fire(cmd)
		if not _nade.is_empty() and _do_nade(cmd, delta, t, g):
			return _finish(cmd, Vector3.ZERO, false, false, t, g)
		_decide_t -= delta
		if _decide_t <= 0.0:
			_decide_t = 0.35 + _rng.randf() * 0.15
			_decide(g, t)
			_plan_nade(g, t)
		move = _follow(g, t)
		if target and target_visible:
			# Reaction delay: start turning toward the threat before shooting.
			_turn_toward_point(target.global_position + Vector3(0, 1.3, 0), delta, 0.6)
		else:
			_turn_toward_point(_look_point(g, t, move), delta, 0.75)
		match task:
			"plant", "defuse":
				move = Vector3.ZERO
				cmd["use"] = true
				crouch = task == "defuse" and diff >= 2
			"hold", "guard", "camp":
				if move == Vector3.ZERO:
					crouch = _hold_crouch
				walk = true
			"patrol":
				walk = true
	return _finish(cmd, move, walk, crouch, t, g)


func _finish(cmd: Dictionary, move: Vector3, walk: bool, crouch: bool, t: float, g: Game) -> Dictionary:
	var pos := s.global_position
	# Keep some distance from teammates.
	if move != Vector3.ZERO or task == "hold":
		var push := Vector3.ZERO
		for o in g.alive_soldiers(s.team):
			if o == s:
				continue
			var d := Vector3(pos.x - o.global_position.x, 0, pos.z - o.global_position.z)
			var l := d.length()
			if l < 1.3 and l > 0.01:
				push += d / l * (1.3 - l)
		move += push * 1.5
	# Stuck detection.
	if t > _stuck_t:
		_stuck_t = t + 0.8
		var wanted := move.length() > 0.2 and not g.movement_frozen() and not s.has_flag(Soldier.F_PLANT)
		if wanted and pos.distance_to(_stuck_pos) < 0.35:
			_stuck_n += 1
			if _stuck_n >= 2:
				var side := Vector3(-move.z, 0, move.x).normalized() * (1.0 if _rng.randf() < 0.5 else -1.0)
				_unstuck_dir = (side - move.normalized() * 0.4).normalized()
				_unstuck_until = t + 0.6
				_jump_until = t + 0.1
				path = PackedVector3Array()
			if _stuck_n >= 5:
				_stuck_n = 0
				if task in ["roam", "patrol", "follow", "hunt", "investigate"]:
					goal = Vector3.INF
					_wander_until = 0.0
		else:
			_stuck_n = 0
		_stuck_pos = pos
	if t < _unstuck_until:
		move = _unstuck_dir
	# Doors in the way: face them and press use.
	if move.length() > 0.2 and t > _door_t and not target_visible:
		var from := pos + Vector3(0, 1.1, 0)
		var hit := Combat.ray(from, from + move.normalized() * 1.5, Cfg.L_DYNAMIC)
		if not hit.is_empty() and hit["collider"] is Door:
			var door: Door = hit["collider"]
			if not door.is_open and not door.broken:
				var to := door.global_position + Vector3(0, 1.2, 0) - s.eye_pos()
				yaw = atan2(-to.x, -to.z)
				pitch = 0.0
				_use_flip = not _use_flip
				if _use_flip:
					cmd["use"] = true
				else:
					_door_t = t + 0.5
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var mv := Vector2(move.dot(right), move.dot(fwd))
	cmd["move"] = mv.limit_length(1.0)
	cmd["yaw"] = yaw
	cmd["pitch"] = pitch
	cmd["walk"] = walk
	cmd["crouch"] = crouch or cmd.get("crouch", false)
	cmd["jump"] = t < _jump_until
	return cmd


# ---------------------------------------------------------------------------
# Perception
# ---------------------------------------------------------------------------
func _perceive(g: Game, t: float) -> void:
	var eye := s.eye_pos()
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var blind := s.is_flashed() and s.flash_amount() > 0.25
	var best: Soldier = null
	var best_score := INF
	if not blind:
		for e in g.soldiers.values():
			var so: Soldier = e
			if not so.alive or so.team == s.team:
				continue
			var chest := so.global_position + Vector3(0, lerpf(1.25, 0.85, so.crouch_amount), 0)
			var to := chest - eye
			var d := to.length()
			if d > see_range:
				continue
			var tracking := so == target and t - _last_seen_t < 1.0
			if not tracking and d > 2.5:
				var flat := Vector3(to.x, 0, to.z).normalized()
				if flat.dot(fwd) < fov_cos:
					continue
			var vis := Combat.can_see(eye, chest) or Combat.can_see(eye, so.eye_pos())
			if vis and g.smoke_blocks(eye, chest):
				vis = false
			if not vis:
				continue
			var score := d * (0.7 if so == target else 1.0)
			if score < best_score:
				best_score = score
				best = so
	if best:
		if best != target:
			var quick := t - _last_seen_t < 1.2
			target = best
			_acquire_t = t - (reaction * 0.5 if quick else 0.0)
			# Holding an angle: an enemy appearing near the crosshair is answered faster.
			var to_e := (best.global_position + Vector3(0, 1.2, 0) - eye).normalized()
			var look := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
			if task in ["hold", "guard", "camp"] and look.dot(to_e) > cos(deg_to_rad(18.0)):
				_acquire_t -= reaction * 0.45
			_new_aim_error(best)
			if t - _last_seen_t > 6.0:
				var where := g.world.in_site(best.global_position)
				_radio("Enemy spotted%s!" % (" at " + where if where != "" else ""), 0.2 if where == "" else 0.45)
		elif not target_visible:
			_acquire_t = t - reaction * 0.5
			_new_aim_error(best)
		target_visible = true
		_last_seen_t = t
		last_known = best.global_position
		if s.team == Cfg.DEF and g.game_mode() == Cfg.MODE_DEFUSAL:
			_alert_near(g, best.global_position, t)
	else:
		target_visible = false
		if target and t - _last_seen_t > MEMORY:
			target = null
	# Hearing
	for n in g.recent_noises:
		if int(n["team"]) == s.team or str(n["src"]) == s.id:
			continue
		if t - float(n["t"]) > 0.6:
			continue
		var p: Vector3 = n["pos"]
		var hear := 38.0
		if g.game_mode() == Cfg.MODE_HUNT and s.team == 1:
			hear = 22.0
		if s.global_position.distance_to(p) < hear * float(n["loud"]):
			heard_pos = p
			_heard_t = float(n["t"])
			if s.team == Cfg.DEF and g.game_mode() == Cfg.MODE_DEFUSAL and float(n["loud"]) >= 1.0:
				_alert_near(g, p, t)


func _alert_near(g: Game, p: Vector3, t: float) -> void:
	for k in g.world.sites.keys():
		if g.world.in_site(p) == k or g.world.site_center(k).distance_to(p) < 16.0:
			_site_alert[k] = t


func _new_aim_error(tgt: Soldier) -> void:
	var d := s.eye_pos().distance_to(tgt.global_position)
	var mag := d * tan(deg_to_rad(aim_err)) * _rng.randf_range(0.5, 1.0)
	if s.is_flashed():
		mag *= 3.0
	_aim_off = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)).normalized() * mag
	_aim_head = _rng.randf() < head_pref
	_crouch_fire = diff >= 1 and _rng.randf() < 0.55


# ---------------------------------------------------------------------------
# Aiming helpers
# ---------------------------------------------------------------------------
func _angle_step(cur: float, target_a: float, step: float) -> float:
	var d := wrapf(target_a - cur, -PI, PI)
	return cur + clampf(d, -step, step)


func _turn_to(want_yaw: float, want_pitch: float, delta: float, mult: float) -> void:
	var d := absf(wrapf(want_yaw - yaw, -PI, PI))
	# Faster flicks for large angles, fine tracking near the target.
	var step := deg_to_rad(turn_rate) * delta * mult * (1.0 + clampf(d * 1.5, 0.0, 2.0))
	yaw = _angle_step(yaw, want_yaw, step)
	pitch = clampf(_angle_step(pitch, want_pitch, step * 0.8), deg_to_rad(-85.0), deg_to_rad(85.0))


func _turn_toward_point(p: Vector3, delta: float, mult: float) -> void:
	if p == Vector3.INF:
		return
	var to := p - s.eye_pos()
	if to.length() < 0.2:
		return
	to = to.normalized()
	_turn_to(atan2(-to.x, -to.z), asin(clampf(to.y, -1.0, 1.0)), delta, mult)


func _look_point(g: Game, t: float, move: Vector3) -> Vector3:
	if target and t - _last_seen_t < 3.0 and last_known != Vector3.INF:
		return last_known + Vector3(0, 1.3, 0)
	if t - _heard_t < 1.5 and heard_pos != Vector3.INF:
		return heard_pos + Vector3(0, 1.3, 0)
	if t - _hurt_t < 1.0 and heard_pos != Vector3.INF:
		return heard_pos + Vector3(0, 1.3, 0)
	if move == Vector3.ZERO and _hold_look != Vector3.INF and task in ["hold", "guard", "camp", "defuse", "plant"]:
		# Scan around the hold direction.
		var base := _hold_look - s.global_position
		var a := sin(t * 0.5 + float(hash(s.id) % 100)) * 0.3
		var rot := Basis(Vector3.UP, a) * Vector3(base.x, 0, base.z)
		return s.global_position + rot + Vector3(0, 1.4 + base.y * 0.0, 0)
	if move != Vector3.ZERO:
		var ahead := s.global_position + move.normalized() * 4.0
		if path_i + 1 < path.size():
			ahead = path[mini(path_i + 1, path.size() - 1)]
		return Vector3(ahead.x, s.eye_pos().y, ahead.z)
	return Vector3.INF


# ---------------------------------------------------------------------------
# Weapons & combat
# ---------------------------------------------------------------------------
func _ammo(wid: String) -> Array:
	if wid == "":
		return [0, 0]
	return s.ammo.get(wid, [int(Cfg.w(wid).get("mag", 0)), int(Cfg.w(wid).get("reserve", 0))])


func _manage_weapon(cmd: Dictionary, engaged: bool, t: float) -> void:
	var w := s.weapon_data()
	var cls: String = w.get("cls", "")
	if not _nade.is_empty():
		return
	if task == "plant":
		return
	# Never walk around holding utility.
	if cls in ["grenade", "bomb", "breach"]:
		cmd["slot"] = _best_slot()
		return
	var a := _ammo(s.cur)
	if engaged:
		if cls == "knife":
			var bs := _best_slot()
			if bs != 3:
				cmd["slot"] = bs
		elif s.cur == s.primary and int(a[0]) == 0:
			var sa := _ammo(s.secondary)
			if s.secondary != "" and int(sa[0]) > 0:
				cmd["slot"] = 2
			elif int(a[1]) > 0:
				cmd["reload"] = true
			else:
				cmd["slot"] = 3
		elif s.cur == s.secondary and int(a[0]) == 0:
			if int(a[1]) > 0:
				cmd["reload"] = true
			else:
				cmd["slot"] = 3
		return
	# Out of combat
	if s.cur != s.primary and s.primary != "":
		var pa := _ammo(s.primary)
		if int(pa[0]) + int(pa[1]) > 0:
			cmd["slot"] = 1
			return
	if s.cur == "knife" and s.secondary != "" and s.primary == "":
		cmd["slot"] = 2
		return
	if w.has("mag"):
		var mag := int(w["mag"])
		if int(a[1]) > 0 and (int(a[0]) == 0 or (int(a[0]) < mag * 0.45 and t - _last_seen_t > 1.5)):
			cmd["reload"] = true
	if cls == "sniper" and s.scope_level > 0 and t - _last_seen_t > 2.5:
		_alt_flip = not _alt_flip
		cmd["alt_pressed"] = _alt_flip


func _best_slot() -> int:
	if s.primary != "":
		var a := _ammo(s.primary)
		if int(a[0]) + int(a[1]) > 0:
			return 1
	if s.secondary != "":
		return 2
	return 3


func _release_fire(cmd: Dictionary) -> void:
	cmd["fire"] = false
	cmd["fire_pressed"] = false
	_semi = false
	_burst_start = -1.0


func _friend_in_line(g: Game, from: Vector3, to: Vector3) -> bool:
	var dir := to - from
	var seg_len := dir.length()
	if seg_len < 0.1:
		return false
	dir /= seg_len
	for o in g.alive_soldiers(s.team):
		if o == s:
			continue
		var c: Vector3 = o.global_position + Vector3(0, 1.1, 0)
		var proj := (c - from).dot(dir)
		if proj <= 0.0 or proj >= seg_len:
			continue
		if (from + dir * proj).distance_to(c) < 0.55:
			return true
	return false


func _combat(cmd: Dictionary, delta: float, t: float, g: Game) -> Dictionary:
	var tgt := target
	var eye := s.eye_pos()
	var aim_pt: Vector3
	if _aim_head:
		aim_pt = tgt.eye_pos() + Vector3(0, 0.02, 0)
	else:
		aim_pt = tgt.global_position + Vector3(0, lerpf(1.2, 0.8, tgt.crouch_amount), 0)
	_aim_off *= exp(-aim_decay * delta)
	var dist := eye.distance_to(aim_pt)
	var intended := aim_pt + tgt.velocity * 0.04
	var aim_with_err := intended + _aim_off
	var dir := (aim_with_err - eye).normalized()
	var want_yaw := atan2(-dir.x, -dir.z)
	var want_pitch := asin(clampf(dir.y, -1.0, 1.0))
	want_pitch -= deg_to_rad(s.punch.x) * spray_comp
	want_yaw -= deg_to_rad(s.punch.y) * spray_comp
	_turn_to(want_yaw, want_pitch, delta, 1.0)
	var ap := pitch + deg_to_rad(s.punch.x)
	var ay := yaw + deg_to_rad(s.punch.y)
	var cur_dir := Vector3(-sin(ay) * cos(ap), sin(ap), -cos(ay) * cos(ap))
	var ang := rad_to_deg(cur_dir.angle_to((intended - eye).normalized()))
	var tol := rad_to_deg(atan2(0.42, dist)) + 0.5 + aim_err * 0.15
	var w := s.weapon_data()
	var cls: String = w.get("cls", "")
	var can_fire := ang < tol and not _friend_in_line(g, eye, intended)
	var move := Vector3.ZERO
	var crouch := false
	var walk := false
	var to_t := Vector3(intended.x - s.global_position.x, 0, intended.z - s.global_position.z).normalized()
	var side := Vector3(-to_t.z, 0, to_t.x)
	if t > _strafe_t:
		_strafe = -_strafe if _rng.randf() < 0.7 else _strafe
		_strafe_t = t + _rng.randf_range(0.35, 0.9)
	match cls:
		"sniper":
			if s.scope_level == 0:
				_alt_flip = not _alt_flip
				cmd["alt_pressed"] = _alt_flip
				_scope_wait = t + 0.35 - diff * 0.05
				can_fire = false
			elif t < _scope_wait:
				can_fire = false
		"rifle", "lmg":
			if dist > 16.0:
				cmd["alt"] = diff >= 1
				crouch = _crouch_fire or cls == "lmg"
			else:
				move = side * _strafe * 0.6
				walk = diff < 2
		"smg", "pistol":
			move = side * _strafe
		"shotgun":
			move = side * _strafe * 0.6 + (to_t if dist > 7.0 else Vector3.ZERO)
		"knife":
			move = to_t
			can_fire = dist < 2.2
	# Low health: fall back to cover while firing.
	if s.health < 35 and dist > 6.0 and t > _retreat_until and t - _hurt_t < 2.0 and _rng.randf() < 0.5:
		var rp := _find_cover(g, tgt)
		if rp != Vector3.INF:
			_retreat_point = rp
			_retreat_until = t + 3.0
	if can_fire:
		if w.get("auto", false):
			var rof: float = w.get("rof", 0.1)
			var burst := 40 if dist < 10.0 else (6 if dist < 24.0 else 3)
			if diff == 0:
				burst = mini(burst, 8)
			if t < _burst_pause_until:
				cmd["fire"] = false
			else:
				if _burst_start < 0.0:
					_burst_start = t
				if t - _burst_start > burst * rof:
					_burst_start = -1.0
					_burst_pause_until = t + _rng.randf_range(0.22, 0.45)
					cmd["fire"] = false
				else:
					cmd["fire"] = true
					cmd["fire_pressed"] = true
		else:
			_semi = not _semi
			cmd["fire"] = _semi
			cmd["fire_pressed"] = _semi
	else:
		cmd["fire"] = false
		cmd["fire_pressed"] = false
		_burst_start = -1.0
	return {"move": move, "crouch": crouch, "walk": walk}


func _find_cover(g: Game, threat: Soldier) -> Vector3:
	var teye := threat.eye_pos()
	for i in 8:
		var p := g.world.random_nav_point(s.global_position, 9.0)
		if p.distance_to(s.global_position) < 2.0:
			continue
		if not Combat.can_see(teye, p + Vector3(0, 1.3, 0)):
			return p
	return Vector3.INF


# ---------------------------------------------------------------------------
# Grenades
# ---------------------------------------------------------------------------
func _plan_nade(g: Game, t: float) -> void:
	if not _nade.is_empty() or t < _nade_check_t:
		return
	_nade_check_t = t + 1.0
	var mode := g.game_mode()
	var pos := s.global_position
	if int(s.grenades.get("frag", 0)) > 0 and target and not target_visible and last_known != Vector3.INF:
		var age := t - _last_seen_t
		var d := pos.distance_to(last_known)
		if age > 0.5 and age < 6.0 and d > 7.0 and d < 26.0 and _rng.randf() < 0.45 + diff * 0.1:
			_nade = {"type": "frag", "point": last_known, "until": t + 3.0, "switch_t": 0.0, "ready_t": -1.0}
			return
	if mode == Cfg.MODE_DEFUSAL and g.rs["phase"] == "live":
		if s.team == Cfg.ATK and task == "go" and not _flash_used and int(s.grenades.get("flash", 0)) > 0 and _site_point != Vector3.INF:
			var d := pos.distance_to(_site_point)
			if d > 10.0 and d < 24.0 and _rng.randf() < 0.5 and Combat.can_see(s.eye_pos(), _site_point + Vector3(0, 1.5, 0)):
				_flash_used = true
				_nade = {"type": "flash", "point": _site_point + Vector3(0, 2.0, 0), "until": t + 3.0, "switch_t": 0.0, "ready_t": -1.0}
				return
		if s.team == Cfg.DEF and task == "hold" and not _smoke_used and int(s.grenades.get("smoke", 0)) > 0 and _hold_look != Vector3.INF:
			if float(g.rs["time_left"]) > 85.0 and pos.distance_to(_hold_point) < 1.5 and _rng.randf() < 0.35:
				_smoke_used = true
				_nade = {"type": "smoke", "point": _hold_look, "until": t + 3.0, "switch_t": 0.0, "ready_t": -1.0}


func _throw_pitch(origin: Vector3, point: Vector3) -> float:
	var dh := point.y - origin.y
	var dist := Vector2(point.x - origin.x, point.z - origin.z).length()
	for deg in range(-20, 61):
		var p := deg_to_rad(float(deg))
		var vx := 17.5 * cos(p)
		var vy := 17.5 * sin(p) + 1.6
		var tt := dist / maxf(vx, 0.1)
		var y := vy * tt - 0.5 * Cfg.GRAVITY * tt * tt
		if y >= dh - 0.3:
			return p
	return deg_to_rad(35.0)


func _do_nade(cmd: Dictionary, delta: float, t: float, g: Game) -> bool:
	var type: String = _nade["type"]
	if t > float(_nade["until"]) or target_visible:
		_nade.clear()
		return false
	if int(s.grenades.get(type, 0)) <= 0 and s.cur != type:
		_nade.clear()
		return false
	var point: Vector3 = _nade["point"]
	var origin := s.eye_pos()
	var to := point - origin
	var want_yaw := atan2(-to.x, -to.z)
	var want_pitch := _throw_pitch(origin, point)
	_turn_to(want_yaw, want_pitch, delta, 1.0)
	if s.cur != type:
		if t > float(_nade["switch_t"]):
			cmd["slot"] = 4
			_nade["switch_t"] = t + 0.55
		return true
	if float(_nade["ready_t"]) < 0.0:
		_nade["ready_t"] = t + 0.5
	var err := absf(wrapf(want_yaw - yaw, -PI, PI)) + absf(want_pitch - pitch)
	if t >= float(_nade["ready_t"]) and err < deg_to_rad(3.0):
		cmd["fire"] = true
		cmd["fire_pressed"] = true
		if type == "frag":
			_radio("Fire in the hole!", 0.4)
		_nade.clear()
	return true


# ---------------------------------------------------------------------------
# Objectives
# ---------------------------------------------------------------------------
func _set_goal(p: Vector3) -> void:
	if p == Vector3.INF:
		goal = Vector3.INF
		path = PackedVector3Array()
		return
	if goal == Vector3.INF or goal.distance_to(p) > 1.5:
		goal = p
		path = PackedVector3Array()
		_repath_t = 0.0


func _arrived(r := 1.0) -> bool:
	if goal == Vector3.INF:
		return true
	var p := s.global_position
	return Vector2(goal.x - p.x, goal.z - p.z).length() < r


func _follow(g: Game, t: float) -> Vector3:
	if goal == Vector3.INF:
		return Vector3.ZERO
	var pos := s.global_position
	if _arrived(0.8):
		return Vector3.ZERO
	if path.is_empty() or t > _repath_t:
		path = g.world.get_nav_path(pos, goal)
		if path.size() < 2:
			path = PackedVector3Array([pos, goal])
		path_i = 1
		_repath_t = t + 1.5 + _rng.randf() * 0.6
	while path_i < path.size() and Vector2(path[path_i].x - pos.x, path[path_i].z - pos.z).length() < 0.6:
		path_i += 1
	var wp: Vector3 = goal if path_i >= path.size() else path[path_i]
	var d := Vector3(wp.x - pos.x, 0, wp.z - pos.z)
	if d.length() < 0.05:
		return Vector3.ZERO
	return d.normalized()


func _point_in_site(g: Game, name: String) -> Vector3:
	if not g.world.sites.has(name):
		return g.world.random_nav_point()
	var a: AABB = g.world.sites[name]
	for i in 16:
		var x := _rng.randf_range(a.position.x + 1.0, a.end.x - 1.0)
		var z := _rng.randf_range(a.position.z + 1.0, a.end.z - 1.0)
		var raw := Vector3(x, 0, z)
		var p := g.world.closest_nav_point(raw)
		if g.world.in_site(p) != "" and Vector2(p.x - x, p.z - z).length() < 1.5 and absf(p.y) < 2.0:
			return p
	return g.world.closest_nav_point(g.world.site_center(name))


## A defensive spot inside a site: near cover, with a view of the attackers' approach.
func _pick_hold(g: Game, site: String) -> Vector3:
	var approach := _approach_point(g, g.world.closest_nav_point(g.world.site_center(site)), _spawn_center(g, Cfg.ATK))
	var best := Vector3.INF
	var best_score := -INF
	for i in 10:
		var p := _point_in_site(g, site)
		var eye := p + Vector3(0, 1.5, 0)
		var sc := _rng.randf() * 0.6
		if Combat.can_see(eye, approach):
			sc += 2.0
		sc -= absf(p.distance_to(approach) - 14.0) * 0.08
		for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var o := p + Vector3(0, 0.8, 0)
			if not Combat.ray(o, o + d * 1.6).is_empty():
				sc += 0.7
				break
		if sc > best_score:
			best_score = sc
			best = p
	return best


## A point ~10 m along the path from `from` toward `to` (used as a look direction when holding).
func _approach_point(g: Game, from: Vector3, to: Vector3) -> Vector3:
	var p := g.world.get_nav_path(from, to)
	if p.size() < 2:
		return to + Vector3(0, 1.4, 0)
	for pt in p:
		if pt.distance_to(from) > 10.0:
			return pt + Vector3(0, 1.4, 0)
	return p[p.size() - 1] + Vector3(0, 1.4, 0)


func _spawn_center(g: Game, team: int) -> Vector3:
	var z: AABB = g.world.spawn_zones.get(team, AABB())
	var c := z.get_center()
	return Vector3(c.x, 0, c.z)


func _decide(g: Game, t: float) -> void:
	match g.game_mode():
		Cfg.MODE_DEFUSAL:
			_decide_defusal(g, t)
		Cfg.MODE_TDM:
			_decide_roam(g, t)
		Cfg.MODE_HUNT:
			if s.team == 0:
				_decide_squad(g, t)
			else:
				_decide_hostile(g, t)


func _decide_defusal(g: Game, t: float) -> void:
	var rs: Dictionary = g.rs
	var bomb: Dictionary = rs["bomb"]
	var w := g.world
	if t < _retreat_until:
		task = "retreat"
		_set_goal(_retreat_point)
		return
	if s.team == Cfg.ATK:
		if s.has_bomb:
			if _site_point == Vector3.INF:
				_site_point = _point_in_site(g, g.mode.atk_plan)
			var in_site := w.in_site(s.global_position) != ""
			var settled := in_site and (_arrived(2.5) or s.global_position.distance_to(_site_point) < 6.0)
			if settled and t - _last_seen_t > 1.5 and rs["phase"] == "live":
				task = "plant"
				_set_goal(Vector3.INF)
				if not _said_plant:
					_said_plant = true
					_radio("Planting the charge!", 0.8)
			else:
				task = "go"
				_set_goal(_site_point)
		elif bomb["state"] == "dropped":
			var bp: Vector3 = bomb["pos"]
			if _closest_alive(g, Cfg.ATK, bp) == s:
				task = "fetch"
				_set_goal(bp)
			else:
				_escort(g, t)
		elif bomb["state"] == "planted":
			var bp: Vector3 = bomb["pos"]
			if _hold_point == Vector3.INF or _hold_point.distance_to(bp) > 12.0:
				_hold_point = w.random_nav_point(bp, 7.0)
				_hold_look = _approach_point(g, bp, _spawn_center(g, Cfg.DEF))
			task = "hold"
			_set_goal(_hold_point)
		else:
			_escort(g, t)
	else:
		if bomb["state"] == "planted":
			var bp: Vector3 = bomb["pos"]
			var d := s.global_position.distance_to(bp)
			if d < 1.3 and not target_visible:
				task = "defuse"
				_set_goal(Vector3.INF)
				_hold_look = bp + Vector3(0, 1.4, 0) + (s.global_position - bp).normalized() * 3.0
				if not _said_defuse:
					_said_defuse = true
					_radio("Defusing, cover me!", 0.7)
			else:
				task = "retake"
				_set_goal(bp)
		else:
			var other := "B" if _site == "A" else "A"
			if not _rotated and t - float(_site_alert.get(other, -100.0)) < 12.0 and t - float(_site_alert.get(_site, -100.0)) > 12.0 \
					and t - _last_seen_t > 3.0:
				_rotated = true
				if _rng.randf() < 0.65:
					_site = other
					_hold_point = Vector3.INF
					_radio("Rotating to %s!" % other, 0.4)
			if _hold_point == Vector3.INF:
				_hold_point = _pick_hold(g, _site)
				_hold_look = _approach_point(g, _hold_point, _spawn_center(g, Cfg.ATK))
			# Investigate close enemy noise instead of standing still.
			if t - _heard_t < 2.0 and heard_pos != Vector3.INF and s.global_position.distance_to(heard_pos) < 14.0 and _rng.randf() < 0.3:
				task = "hunt"
				_set_goal(g.world.closest_nav_point(heard_pos))
			else:
				task = "hold"
				_set_goal(_hold_point)


func _escort(g: Game, t: float) -> void:
	if _site_point == Vector3.INF:
		_site_point = _point_in_site(g, g.mode.atk_plan)
	if target and t - _last_seen_t < 4.0 and last_known != Vector3.INF:
		task = "hunt"
		_set_goal(g.world.closest_nav_point(last_known))
		return
	if _arrived(2.0) and goal != Vector3.INF and goal.distance_to(_site_point) < 0.5:
		task = "hold"
		if _hold_look == Vector3.INF:
			_hold_look = _approach_point(g, _site_point, _spawn_center(g, Cfg.DEF))
		if not _said_clear and g.alive_soldiers(Cfg.DEF).size() > 0 and _rng.randf() < 0.2:
			_said_clear = true
			_radio("Site clear.", 0.6)
		return
	task = "go"
	_set_goal(_site_point)


func _closest_alive(g: Game, team: int, p: Vector3) -> Soldier:
	var best: Soldier = null
	var bd := INF
	for o in g.alive_soldiers(team):
		var d := (o as Soldier).global_position.distance_to(p)
		if d < bd and (o as Soldier).is_bot:
			bd = d
			best = o
	return best


func _decide_roam(g: Game, t: float) -> void:
	if t < _retreat_until:
		task = "retreat"
		_set_goal(_retreat_point)
		return
	if target and t - _last_seen_t < 4.0 and last_known != Vector3.INF:
		task = "hunt"
		_set_goal(g.world.closest_nav_point(last_known))
		return
	if t - _heard_t < 3.0 and heard_pos != Vector3.INF:
		task = "hunt"
		_set_goal(g.world.closest_nav_point(heard_pos))
		return
	if goal == Vector3.INF or _arrived(1.5) or t > _wander_until or task != "roam":
		task = "roam"
		_wander_until = t + 18.0
		var enemies := []
		for o in g.alive_soldiers():
			if o.team != s.team:
				enemies.append(o)
		var p: Vector3
		if not enemies.is_empty() and _rng.randf() < 0.45:
			var e: Soldier = enemies[_rng.randi() % enemies.size()]
			p = g.world.random_nav_point(e.global_position, 10.0)
		else:
			p = g.world.random_nav_point()
		_set_goal(p)


func _decide_squad(g: Game, t: float) -> void:
	var leader: Soldier = null
	var bd := INF
	for o in g.alive_soldiers(0):
		var so: Soldier = o
		if so.is_bot:
			continue
		var d := so.global_position.distance_to(s.global_position)
		if d < bd:
			bd = d
			leader = so
	if leader == null:
		_decide_roam(g, t)
		return
	if t < _retreat_until:
		task = "retreat"
		_set_goal(_retreat_point)
		return
	if bd > 6.0:
		task = "follow"
		var behind := leader.global_position - leader.flat_forward() * 3.0 + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
		_set_goal(g.world.closest_nav_point(behind))
	elif bd < 3.0 or _arrived(1.0):
		task = "guard"
		_set_goal(Vector3.INF)
		_hold_look = s.global_position + leader.flat_forward() * 10.0 + Vector3(0, 1.4, 0)


func _decide_hostile(g: Game, t: float) -> void:
	if t < _retreat_until:
		task = "retreat"
		_set_goal(_retreat_point)
		return
	if target and t - _last_seen_t < 6.0 and last_known != Vector3.INF:
		task = "investigate"
		_set_goal(g.world.closest_nav_point(last_known))
		return
	if t - _heard_t < 4.0 and heard_pos != Vector3.INF and s.global_position.distance_to(heard_pos) < 30.0 \
			and (task == "investigate" or _rng.randf() < 0.25):
		task = "investigate"
		_set_goal(g.world.closest_nav_point(heard_pos))
		return
	if _camp:
		task = "camp"
		if s.global_position.distance_to(_home) > 3.0:
			_set_goal(_home)
		else:
			_set_goal(Vector3.INF)
			if _hold_look == Vector3.INF or _rng.randf() < 0.05:
				var a := _rng.randf() * TAU
				_hold_look = s.global_position + Vector3(sin(a), 0, cos(a)) * 10.0 + Vector3(0, 1.4, 0)
		return
	task = "patrol"
	if goal == Vector3.INF or _arrived(1.2):
		if _wait_until == 0.0:
			_wait_until = t + _rng.randf_range(1.5, 5.0)
		if t > _wait_until:
			_wait_until = 0.0
			_set_goal(g.world.random_nav_point(_home, 16.0))


# ---------------------------------------------------------------------------
func _radio(text: String, chance: float) -> void:
	var g := Game.inst
	if g == null:
		return
	var t := now()
	if t - _last_radio < RADIO_COOLDOWN or t - float(_team_radio_t.get(s.team, -100.0)) < 3.0:
		return
	if _rng.randf() > chance:
		return
	_last_radio = t
	_team_radio_t[s.team] = t
	g.bot_radio(s, text)
