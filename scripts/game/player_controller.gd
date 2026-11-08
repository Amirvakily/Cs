class_name PlayerController
extends Node3D
## Local player: input -> command, first-person camera + viewmodel, third-person cover system,
## spectator camera. Exists on every non-dedicated peer.

var s: Soldier
var cam: Camera3D
var viewmodel: Viewmodel
var look_yaw := 0.0
var look_pitch := 0.0
var _look_delta := Vector2.ZERO
var _cycle := 0
var _shake := 0.0
var _shake_t := 0.0
var _kick := Vector2.ZERO

# Cover state
var in_cover := false
var cover_normal := Vector3.ZERO
var cover_low := false
var cover_side := 1.0 # which shoulder / edge we favour
var _peek := 0.0
var _peek_dir := 0.0
var _cam_dist := 0.0
var _cam_side := 0.6

# Spectator
var spec_target: Soldier
var _free_pos := Vector3(40, 30, 40)
var _death_time := -10.0
var _killer_id := ""


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.04
	cam.far = 400.0
	cam.fov = float(Cfg.settings["fov"])
	add_child(cam)
	cam.make_current()
	viewmodel = Viewmodel.new()
	viewmodel.name = "Viewmodel"
	cam.add_child(viewmodel)
	viewmodel.visible = false
	var g := Game.inst
	if g and g.world:
		_free_pos = g.world.bounds.get_center() + Vector3(0, 25, g.world.bounds.size.z * 0.45)
	if g and g.fx and g.fx.has_signal("camera_shake"):
		g.fx.camera_shake.connect(_on_fx_shake)


func attach(soldier: Soldier) -> void:
	if s != soldier:
		if s and is_instance_valid(s):
			_disconnect_all(s)
		s = soldier
		s.controller = self
		s.fired.connect(_on_fired)
		s.reload_started.connect(_on_reload)
		s.weapon_switched.connect(_on_switched)
		s.knifed.connect(_on_knifed)
		s.threw.connect(_on_threw)
		s.spawned.connect(_on_spawned)
	viewmodel.setup(s.team)
	viewmodel.set_weapon(s.cur)


func _disconnect_all(o: Soldier) -> void:
	for pair in [["fired", _on_fired], ["reload_started", _on_reload], ["weapon_switched", _on_switched],
			["knifed", _on_knifed], ["threw", _on_threw], ["spawned", _on_spawned]]:
		if o.is_connected(pair[0], pair[1]):
			o.disconnect(pair[0], pair[1])


func _on_fired(_w: String) -> void:
	viewmodel.on_fire()
	_kick += Vector2(0.35, randf_range(-0.2, 0.2))


func _on_reload(_w: String, d: float) -> void:
	viewmodel.on_reload(d)


func _on_switched(w: String) -> void:
	viewmodel.set_weapon(w)


func _on_knifed(alt: bool) -> void:
	viewmodel.on_knife(alt)


func _on_threw(_t: String) -> void:
	viewmodel.on_throw()


func _on_spawned() -> void:
	look_yaw = s.yaw
	look_pitch = 0.0
	in_cover = false
	_peek = 0.0
	spec_target = null
	viewmodel.set_weapon(s.cur)


func first_person() -> bool:
	return s != null and s.alive and not in_cover


func muzzle_global() -> Vector3:
	return viewmodel.muzzle_global()


func _menu_open() -> bool:
	var g := Game.inst
	return g != null and g.hud != null and g.hud.is_menu_open()


func _sens() -> float:
	var base := float(Cfg.settings["fov"])
	return float(Cfg.settings["sensitivity"]) * 0.022 * (cam.fov / base)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = event.relative
		var k := deg_to_rad(_sens())
		look_yaw -= rel.x * k
		var dy := rel.y * k * (-1.0 if Cfg.settings["invert_y"] else 1.0)
		look_pitch = clampf(look_pitch - dy, deg_to_rad(-88.0), deg_to_rad(88.0))
		_look_delta += rel
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle = 1
		if event.button_index == MOUSE_BUTTON_LEFT and (s == null or not s.alive):
			_next_spec_target(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT and (s == null or not s.alive):
			_next_spec_target(-1)


# ---------------------------------------------------------------------------
# Command
# ---------------------------------------------------------------------------
func make_cmd(delta: float) -> Dictionary:
	var cmd := {"yaw": look_yaw, "pitch": look_pitch}
	if _menu_open():
		_cycle = 0
		if in_cover:
			cmd["cover"] = true
			cmd["crouch"] = cover_low
		return cmd
	var mv := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
	cmd["jump"] = Input.is_action_pressed("jump")
	cmd["crouch"] = Input.is_action_pressed("crouch")
	cmd["walk"] = Input.is_action_pressed("walk")
	cmd["fire"] = Input.is_action_pressed("fire")
	cmd["fire_pressed"] = Input.is_action_just_pressed("fire")
	cmd["alt"] = Input.is_action_pressed("aim")
	cmd["alt_pressed"] = Input.is_action_just_pressed("aim")
	cmd["reload"] = Input.is_action_just_pressed("reload")
	cmd["use"] = Input.is_action_pressed("use")
	cmd["drop"] = Input.is_action_just_pressed("drop")
	cmd["light"] = Input.is_action_just_pressed("flashlight")
	cmd["last"] = Input.is_action_just_pressed("last_weapon")
	for i in range(1, 6):
		if Input.is_action_just_pressed("slot%d" % i):
			cmd["slot"] = i
	cmd["cycle"] = _cycle
	_cycle = 0
	if Input.is_action_just_pressed("cover"):
		if in_cover:
			_leave_cover()
		else:
			_try_enter_cover()
	if in_cover:
		_cover_cmd(cmd, mv, delta)
	else:
		cmd["move"] = mv
	return cmd


# ---------------------------------------------------------------------------
# Cover system (third person)
# ---------------------------------------------------------------------------
func _try_enter_cover() -> void:
	if s == null or not s.alive or not s.is_on_floor():
		return
	var fwd := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
	var origin := s.global_position + Vector3(0, 0.75, 0)
	var hit := Combat.ray(origin, origin + fwd * 1.6)
	if hit.is_empty():
		# Try the nearest wall in any direction.
		var best := {}
		var best_d := 1.4
		for i in 8:
			var a := look_yaw + i * TAU / 8.0
			var d := Vector3(-sin(a), 0, -cos(a))
			var h := Combat.ray(origin, origin + d * 1.4)
			if not h.is_empty() and origin.distance_to(h["position"]) < best_d:
				best = h
				best_d = origin.distance_to(h["position"])
		hit = best
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	n.y = 0.0
	if n.length() < 0.5:
		return
	cover_normal = n.normalized()
	var high := Combat.ray(s.global_position + Vector3(0, 1.5, 0), s.global_position + Vector3(0, 1.5, 0) - cover_normal * 1.6)
	cover_low = high.is_empty()
	var p: Vector3 = hit["position"] + cover_normal * (Cfg.RADIUS + 0.06)
	s.global_position = Vector3(p.x, s.global_position.y, p.z)
	s.velocity = Vector3.ZERO
	in_cover = true
	_peek = 0.0
	_cam_dist = 0.0
	Sfx.play3d("step1", s.global_position, -6.0)


func _leave_cover() -> void:
	in_cover = false
	_peek = 0.0


func _has_cover_at(p: Vector3) -> bool:
	var o := p + Vector3(0, 0.75, 0)
	return not Combat.ray(o, o - cover_normal * 0.9).is_empty()


func _cover_cmd(cmd: Dictionary, mv: Vector2, delta: float) -> void:
	cmd["cover"] = true
	var tangent := cover_normal.cross(Vector3.UP).normalized()
	var cam_right := Vector3(cos(look_yaw), 0, -sin(look_yaw))
	var lateral := mv.x * signf(cam_right.dot(tangent) + 0.0001)
	# Pull away from the wall (or jump) to leave cover.
	var cam_fwd := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
	var away := mv.y * cam_fwd.dot(cover_normal) + mv.x * cam_right.dot(cover_normal)
	if away > 0.7 or cmd.get("jump", false) or not _has_cover_at(s.global_position):
		_leave_cover()
		cmd["move"] = mv
		return
	var aiming: bool = cmd.get("alt", false) or Input.is_action_pressed("aim")
	var at_edge_pos := not _has_cover_at(s.global_position + tangent * 0.5)
	var at_edge_neg := not _has_cover_at(s.global_position - tangent * 0.5)
	if lateral > 0.0 and at_edge_pos:
		lateral = 0.0
		cover_side = 1.0
	elif lateral < 0.0 and at_edge_neg:
		lateral = 0.0
		cover_side = -1.0
	elif lateral != 0.0:
		cover_side = signf(lateral)
	if aiming:
		lateral = 0.0
	# Peeking: over low cover by standing, around high cover at an edge by leaning out.
	var want_peek := 0.0
	_peek_dir = 0.0
	if aiming:
		if cover_low:
			want_peek = 1.0
		elif at_edge_pos or at_edge_neg:
			want_peek = 1.0
			_peek_dir = 1.0 if (at_edge_pos and (cover_side > 0.0 or not at_edge_neg)) else -1.0
	_peek = move_toward(_peek, want_peek, delta / 0.15)
	var desired := tangent * lateral
	if _peek_dir != 0.0:
		var edge_target := tangent * _peek_dir * 0.7
		desired = edge_target * 3.0 * (_peek - 0.5)
	# Hug the wall.
	desired += -cover_normal * 0.5
	var fwd := Vector3(-sin(look_yaw), 0, -cos(look_yaw))
	cmd["move"] = Vector2(desired.dot(cam_right), desired.dot(fwd)).limit_length(1.0)
	cmd["walk"] = true
	cmd["crouch"] = cover_low and _peek < 0.5
	# Without peeking you can only blind-fire; aim direction follows the camera ray.
	var aim := _camera_aim()
	cmd["yaw"] = aim.x
	cmd["pitch"] = aim.y


func _camera_aim() -> Vector2:
	# Direction from the soldier's eye to the point under the crosshair.
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var hit := Combat.ray(from + dir * 0.5, from + dir * 200.0)
	var target: Vector3 = from + dir * 200.0 if hit.is_empty() else hit["position"]
	var to := (target - s.eye_pos()).normalized()
	return Vector2(atan2(-to.x, -to.z), asin(clampf(to.y, -1.0, 1.0)))


# ---------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	var g := Game.inst
	if g == null:
		return
	_shake = maxf(0.0, _shake - delta * 2.5)
	_shake_t += delta * 40.0
	_kick = _kick.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	var shake_off := Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.7 + 1.0), 0) * _shake * 0.06
	if s and is_instance_valid(s) and s.alive:
		if s.model:
			s.model.set_first_person(not in_cover)
		viewmodel.visible = not in_cover and s.scope_level == 0
		if in_cover:
			_cover_camera(delta)
		else:
			_fp_camera(delta)
		cam.position += shake_off
		viewmodel.update_vm(delta, s, _look_delta)
	else:
		viewmodel.visible = false
		if s and is_instance_valid(s) and s.model:
			s.model.set_first_person(false)
		_spectate(delta)
	_look_delta = Vector2.ZERO


func _fp_camera(delta: float) -> void:
	var base := float(Cfg.settings["fov"])
	var w := s.weapon_data()
	var target_fov := base
	if s.scope_level > 0:
		var levels: Array = w.get("scope", [40.0])
		target_fov = float(levels[mini(s.scope_level - 1, levels.size() - 1)])
	elif s.ads_amount > 0.0:
		target_fov = lerpf(base, float(w.get("ads_fov", base * 0.8)), s.ads_amount)
	cam.fov = lerpf(cam.fov, target_fov, clampf(delta * 18.0, 0.0, 1.0)) if s.scope_level == 0 else target_fov
	cam.global_position = s.eye_pos()
	cam.rotation = Vector3(look_pitch + deg_to_rad(s.punch.x + _kick.x), look_yaw + deg_to_rad(s.punch.y + _kick.y), 0)


func _cover_camera(delta: float) -> void:
	var aiming := _peek > 0.5
	var target_dist := 1.55 if aiming else 2.7
	_cam_dist = lerpf(_cam_dist if _cam_dist > 0.0 else 0.8, target_dist, clampf(delta * 8.0, 0.0, 1.0))
	_cam_side = lerpf(_cam_side, 0.55 * cover_side, clampf(delta * 6.0, 0.0, 1.0))
	var base := float(Cfg.settings["fov"])
	cam.fov = lerpf(cam.fov, base * (0.72 if aiming else 1.0), clampf(delta * 10.0, 0.0, 1.0))
	var rot := Basis.from_euler(Vector3(look_pitch, look_yaw, 0))
	var pivot := s.global_position + Vector3(0, s.eye_height() + 0.15, 0)
	var offset := rot * Vector3(_cam_side, 0.1, _cam_dist)
	var hit := Combat.ray(pivot, pivot + offset)
	var final := pivot + offset
	if not hit.is_empty():
		final = hit["position"] - offset.normalized() * 0.2
	cam.global_position = final
	cam.rotation = Vector3(look_pitch + deg_to_rad(s.punch.x), look_yaw + deg_to_rad(s.punch.y), 0)


func _spectate(delta: float) -> void:
	var g := Game.inst
	cam.fov = lerpf(cam.fov, float(Cfg.settings["fov"]), clampf(delta * 6.0, 0.0, 1.0))
	var t := Time.get_ticks_msec() / 1000.0
	# Death cam: look from the body toward the killer for a moment.
	if s and is_instance_valid(s) and not s.alive and t - _death_time < 2.5:
		var killer: Soldier = g.soldiers.get(_killer_id)
		var from := s.global_position + Vector3(0, 2.2, 0) + s.flat_forward() * -1.5
		cam.global_position = cam.global_position.lerp(from, clampf(delta * 4.0, 0.0, 1.0))
		if killer and killer != s:
			cam.look_at(killer.global_position + Vector3(0, 1.4, 0))
		else:
			cam.look_at(s.global_position)
		return
	if spec_target == null or not is_instance_valid(spec_target) or not spec_target.alive:
		_next_spec_target(1)
	if spec_target and is_instance_valid(spec_target):
		var rot := Basis.from_euler(Vector3(look_pitch, look_yaw, 0))
		var pivot := spec_target.global_position + Vector3(0, 1.6, 0)
		var offset := rot * Vector3(0.4, 0.25, 3.2)
		var hit := Combat.ray(pivot, pivot + offset)
		cam.global_position = pivot + offset if hit.is_empty() else hit["position"] - offset.normalized() * 0.2
		cam.rotation = Vector3(look_pitch, look_yaw, 0)
		if spec_target.model:
			spec_target.model.set_first_person(false)
	else:
		# Free camera.
		var mv := Vector3(Input.get_axis("move_left", "move_right"), 0, -Input.get_axis("move_back", "move_forward"))
		if _menu_open():
			mv = Vector3.ZERO
		var rot := Basis.from_euler(Vector3(look_pitch, look_yaw, 0))
		var speed := 18.0 if Input.is_action_pressed("walk") else 9.0
		_free_pos += rot * mv * speed * delta
		cam.global_position = _free_pos
		cam.rotation = Vector3(look_pitch, look_yaw, 0)


func _next_spec_target(dir: int) -> void:
	var g := Game.inst
	if g == null:
		return
	var team := s.team if s and is_instance_valid(s) else -1
	var cands := []
	for so in g.soldiers.values():
		if so.alive and so != s and (team < 0 or so.team == team or g.alive_soldiers(team).is_empty()):
			cands.append(so)
	if cands.is_empty():
		spec_target = null
		return
	var i := cands.find(spec_target)
	spec_target = cands[(i + dir + cands.size()) % cands.size()]


func spectate_name() -> String:
	if spec_target and is_instance_valid(spec_target):
		return spec_target.display_name
	return ""


# ---------------------------------------------------------------------------
# Feedback
# ---------------------------------------------------------------------------
func on_hurt(amount: float, dir: Vector3) -> void:
	_shake = minf(_shake + amount * 0.02, 1.2)
	if s:
		s.punch.x += minf(amount * 0.05, 2.5)


func on_local_death(killer_id: String) -> void:
	_death_time = Time.get_ticks_msec() / 1000.0
	_killer_id = killer_id
	in_cover = false
	spec_target = null


func on_explosion(pos: Vector3, radius: float) -> void:
	var d := cam.global_position.distance_to(pos)
	if d < radius * 2.5:
		_shake = minf(_shake + (1.0 - d / (radius * 2.5)) * 1.5, 2.0)


func _on_fx_shake(pos: Vector3, strength: float) -> void:
	var d := cam.global_position.distance_to(pos)
	_shake = minf(_shake + strength / maxf(1.0, d * 0.25), 2.0)
