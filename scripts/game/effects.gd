class_name Effects
extends Node3D
## Visual effects: muzzle flashes, tracers, impacts, decals, blood, explosions,
## smoke clouds, flashbangs, debris and shell casings. Everything is pooled.

signal camera_shake(pos: Vector3, strength: float)

const MAX_DECALS := 96
const MAX_SCORCH := 10
const TRACER_SPEED := 340.0
const ADD_SHADER := preload("res://shaders/fx_add.gdshader")
const STREAK_SHADER := preload("res://shaders/fx_streak.gdshader")

## Effects.shot() plays the weapon sound (2D for the local view, 3D otherwise).
var play_shot_sounds := true

static var _tex := {}
static var _mats := {}

var _rng := RandomNumberGenerator.new()
var _pools := {} # kind -> {"items": Array, "i": int}
var _decals: Array[Decal] = []
var _decal_i := 0
var _scorch: Array[Decal] = []
var _scorch_i := 0
var _tracers: Array = [] # {node, pos, dir, travelled, total}
var _tracer_pool: Array[MeshInstance3D] = []
var _flashes: Array = [] # {node, t, dur}
var _flash_pool: Array[Node3D] = []
var _lights: Array = [] # {light, t, dur, energy}
var _light_pool: Array[OmniLight3D] = []
var _shot_n := 0
var _smokes: Array = [] # {pos, radius, t, dur}
var _smoke_overlay: ColorRect


func _ready() -> void:
	_rng.randomize()
	_build_textures()


func _process(delta: float) -> void:
	_update_tracers(delta)
	_update_flashes(delta)
	_update_lights(delta)
	if not _smokes.is_empty() or (_smoke_overlay and _smoke_overlay.visible):
		_update_smoke_overlay(delta)


# =============================================================================
# Public API
# =============================================================================

func shot(origin: Vector3, ends: PackedVector3Array, weapon_id: String, from_local_view: bool) -> void:
	var w := Cfg.w(weapon_id)
	if w.is_empty():
		return
	var cls: String = w.get("cls", "rifle")
	var dir := Vector3.FORWARD
	if ends.size() > 0 and ends[0].distance_to(origin) > 0.01:
		dir = (ends[0] - origin).normalized()
	if cls != "knife" and cls != "grenade" and cls != "bomb" and cls != "breach":
		muzzle_flash(origin, dir, weapon_id)
	if play_shot_sounds and w.has("snd") and cls != "knife":
		if from_local_view:
			Sfx.play(w["snd"], -3.0, _rng.randf_range(0.97, 1.03))
		else:
			Sfx.play3d(w["snd"], origin, 3.0, 1.0, 160.0)
	# Tracers: only some bullets get one, like real tracer rounds.
	var chance := 0.3
	match cls:
		"lmg":
			chance = 0.5
		"smg":
			chance = 0.25
		"pistol":
			chance = 0.12
		"shotgun":
			chance = 0.18
		"sniper":
			chance = 1.0
	_shot_n += 1
	for e in ends:
		if _rng.randf() < chance or (cls == "rifle" and _shot_n % 3 == 0 and e == ends[0]):
			var start := origin
			if from_local_view:
				start = origin + (e - origin).normalized() * 1.2
			_spawn_tracer(start, e, cls == "sniper")
	if from_local_view and (cls == "rifle" or cls == "smg" or cls == "lmg" or cls == "pistol" or weapon_id == "sentry"):
		var right := dir.cross(Vector3.UP).normalized()
		if right.length() < 0.1:
			right = Vector3.RIGHT
		shell(origin - dir * 0.32 + right * 0.04, (right + Vector3.UP * 0.6 - dir * 0.2).normalized())
	if cls == "shotgun" or cls == "sniper" or weapon_id == "hawk":
		camera_shake.emit(origin, 0.18 if from_local_view else 0.05)


func muzzle_flash(pos: Vector3, dir: Vector3, weapon_id: String) -> void:
	var w := Cfg.w(weapon_id)
	var cls: String = w.get("cls", "rifle")
	var s := 0.32
	match cls:
		"pistol":
			s = 0.36 if weapon_id == "hawk" else 0.24
		"smg":
			s = 0.27
		"rifle":
			s = 0.34
		"shotgun":
			s = 0.46
		"sniper":
			s = 0.44
		"lmg":
			s = 0.38
	s *= _rng.randf_range(0.85, 1.15)
	var node := _get_flash_node()
	node.global_position = pos
	node.basis = _basis_from_z(dir.normalized())
	node.visible = true
	var star: MeshInstance3D = node.get_child(0)
	star.scale = Vector3.ONE * s * 1.7
	star.set_instance_shader_parameter("inst_roll", _rng.randf() * TAU)
	var core: MeshInstance3D = node.get_child(1)
	core.scale = Vector3.ONE * s * 1.1
	var roll := _rng.randf() * PI
	for i in [2, 3]:
		var petal: MeshInstance3D = node.get_child(i)
		var b := Basis(Vector3(0, 0, 1), roll + (i - 2) * PI * 0.5) * Basis(Vector3(1, 0, 0), PI * 0.5)
		petal.transform = Transform3D(b * Basis.from_scale(Vector3(s * 0.75, s * 2.6, 1.0)), Vector3(0, 0, s * 1.2))
	_flashes.append({"node": node, "t": 0.0, "dur": 0.05})
	_light(pos + dir * 0.15, Color(1.0, 0.72, 0.4), 2.5 + s * 6.0, 4.0 + s * 6.0, 0.06)
	_emit("muzzle_smoke", pos + dir * 0.1, dir)


func impact(pos: Vector3, normal: Vector3, mat: String) -> void:
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	match mat:
		"metal":
			_emit("sparks", pos, n)
			_emit("dust_small", pos, n, Color(0.55, 0.55, 0.55, 0.35))
			_light(pos + n * 0.1, Color(1.0, 0.7, 0.35), 1.5, 2.5, 0.05)
			_decal(pos, n, "hole_metal", 0.11)
			Sfx.play3d("imp_metal", pos, -4.0, _rng.randf_range(0.9, 1.15), 45.0)
		"wood":
			_emit("splinters", pos, n)
			_emit("dust_small", pos, n, Color(0.5, 0.38, 0.24, 0.5))
			_decal(pos, n, "hole_wood", 0.15)
			Sfx.play3d("imp_wood", pos, -4.0, _rng.randf_range(0.9, 1.1), 45.0)
		"dirt":
			_emit("dirt", pos, n)
			_emit("dust", pos, n, Color(0.52, 0.42, 0.3, 0.85))
			_decal(pos, n, "hole_dirt", 0.22)
			Sfx.play3d("imp_concrete", pos, -6.0, 0.7, 40.0)
		"glass":
			_emit("glass", pos, n)
			_decal(pos, n, "hole_glass", 0.2)
			Sfx.play3d("imp_metal", pos, -6.0, 1.6, 40.0)
		"flesh":
			blood(pos, -n)
		_:
			_emit("dust", pos, n, Color(0.66, 0.64, 0.6, 0.85))
			_emit("chips", pos, n)
			if _rng.randf() < 0.35:
				_emit("sparks_few", pos, n)
			_decal(pos, n, "hole_concrete", 0.17)
			Sfx.play3d("imp_concrete", pos, -4.0, _rng.randf_range(0.9, 1.1), 45.0)


func blood(pos: Vector3, dir: Vector3) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	_emit("blood_mist", pos, d)
	_emit("blood_drops", pos, (d + Vector3.UP * 0.3).normalized())
	Sfx.play3d("imp_flesh", pos, -2.0, _rng.randf_range(0.9, 1.1), 40.0)
	# Splatter on whatever is behind the victim, and drops on the floor.
	var hit := _ray(pos, pos + d * 2.6)
	if not hit.is_empty():
		_decal(hit["position"], hit["normal"], "blood%d" % _rng.randi_range(0, 2), _rng.randf_range(0.5, 0.95), 0.25)
	var down := _ray(pos, pos + Vector3.DOWN * 2.2)
	if not down.is_empty() and _rng.randf() < 0.7:
		_decal(down["position"] + d * _rng.randf_range(0.0, 0.5), down["normal"], "blood%d" % _rng.randi_range(0, 2), _rng.randf_range(0.3, 0.6), 0.2)


func explosion(pos: Vector3, kind: String) -> void:
	var big := 1.0
	var shake := 1.0
	match kind:
		"breach":
			big = 0.75
			shake = 0.8
		"bomb":
			big = 2.6
			shake = 2.2
	_light(pos + Vector3.UP * 0.8 * big, Color(1.0, 0.6, 0.28), 16.0 * big, 11.0 * big, 0.6 * sqrt(big))
	_emit("fire_core", pos + Vector3.UP * 0.35 * big, Vector3.UP, Color(1, 1, 1, 1), big)
	_emit("fireball", pos + Vector3.UP * 0.45 * big, Vector3.UP, Color(1, 1, 1, 1), big)
	_emit("exp_sparks", pos + Vector3.UP * 0.2, Vector3.UP, Color(1, 1, 1, 1), big)
	_emit("exp_debris", pos + Vector3.UP * 0.1, Vector3.UP, Color(0.22, 0.2, 0.18, 1.0), big)
	_emit("dust_ring", pos + Vector3.UP * 0.2, Vector3.UP, Color(0.55, 0.48, 0.4, 0.75), big)
	var smoke_col := Color(0.16, 0.15, 0.14, 0.95)
	get_tree().create_timer(0.12).timeout.connect(func(): _emit("smoke_column", pos + Vector3.UP * 0.8 * big, Vector3.UP, smoke_col, big))
	if kind == "bomb":
		get_tree().create_timer(0.3).timeout.connect(func(): _emit("smoke_column", pos + Vector3.UP * 4.0, Vector3.UP, Color(0.1, 0.1, 0.1, 0.95), big))
		get_tree().create_timer(0.08).timeout.connect(func(): _emit("fireball", pos + Vector3.UP * 3.0, Vector3.UP, Color(1, 1, 1, 1), big * 0.8))
	if kind == "breach":
		_emit("planks", pos, Vector3.UP, Color(1, 1, 1, 1), 1.0)
		Sfx.play3d("wood_break", pos, 2.0, 1.0, 80.0)
	# Scorch mark on the ground (and wall for breach charges).
	var g := _ray(pos + Vector3.UP * 0.6, pos + Vector3.DOWN * 2.5)
	if not g.is_empty():
		_scorch_decal(g["position"], g["normal"], 3.2 * big)
	Sfx.play3d("explode", pos, 6.0 if kind != "bomb" else 12.0, 1.0 if kind != "breach" else 1.15, 220.0)
	camera_shake.emit(pos, shake)


func smoke_cloud(pos: Vector3, radius: float, duration: float) -> void:
	var cloud := Node3D.new()
	add_child(cloud)
	cloud.global_position = pos
	var life := duration + 2.0
	# Billowing puffs pushed out from the canister; damping makes them settle into a dome.
	var p := CPUParticles3D.new()
	cloud.add_child(p)
	p.mesh = _quad(radius * 0.62)
	p.material_override = _lit_mat("smoke_cloud", "puff", 0.8)
	p.amount = 90
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0 - 1.6 / life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.position = Vector3.UP * 0.6
	p.direction = Vector3.UP
	p.spread = 100.0
	p.flatness = 0.5
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = radius * 1.15
	p.damping_min = 2.2
	p.damping_max = 2.8
	p.gravity = Vector3(0.04, 0.05, 0.02)
	p.anim_offset_max = 1.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.1, 0.9), Vector2(0.6, 1.05), Vector2(1.0, 1.25)])
	var grad := Gradient.new()
	grad.set_color(0, Color(0.8, 0.8, 0.78, 0.0))
	grad.set_color(1, Color(0.7, 0.7, 0.68, 0.0))
	grad.add_point(0.015, Color(0.82, 0.82, 0.8, 0.95))
	grad.add_point(clampf((duration - 2.0) / life, 0.1, 0.95), Color(0.76, 0.76, 0.74, 0.92))
	p.color_ramp = grad
	p.emitting = true
	# Volumetric fill (only visible when the environment has volumetric fog enabled).
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = Vector3(radius * 1.7, radius * 1.0, radius * 1.7)
	fv.position = Vector3.UP * radius * 0.35
	var fm := FogMaterial.new()
	fm.density = 0.0
	fm.albedo = Color(0.75, 0.75, 0.74)
	fm.edge_fade = 0.7
	fv.material = fm
	cloud.add_child(fv)
	var tw := cloud.create_tween()
	tw.tween_property(fm, "density", 0.45, 2.0)
	tw.tween_interval(maxf(0.1, duration - 4.5))
	tw.tween_property(fm, "density", 0.0, 2.5)
	_smokes.append({"pos": pos + Vector3.UP * radius * 0.4, "radius": radius, "t": 0.0, "dur": duration})
	Sfx.play3d("smoke", pos, 0.0, 1.0, 50.0)
	get_tree().create_timer(life + 1.0).timeout.connect(cloud.queue_free)


## Grey screen overlay while the camera is inside a smoke cloud (billboards vanish up close).
func _update_smoke_overlay(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var a := 0.0
	var i := _smokes.size() - 1
	while i >= 0:
		var sm: Dictionary = _smokes[i]
		sm["t"] += delta
		var t: float = sm["t"]
		var dur: float = sm["dur"]
		if t > dur + 2.0:
			_smokes.remove_at(i)
		elif cam:
			var r: float = sm["radius"]
			var c: Vector3 = sm["pos"]
			var d := cam.global_position.distance_to(c) / r
			var life := clampf(t / 1.8, 0.0, 1.0) * clampf((dur + 1.5 - t) / 2.5, 0.0, 1.0)
			a = maxf(a, smoothstep(1.05, 0.55, d) * life * 0.96)
		i -= 1
	if a <= 0.001:
		if _smoke_overlay:
			_smoke_overlay.visible = false
		return
	if _smoke_overlay == null:
		var layer := CanvasLayer.new()
		layer.layer = 0
		add_child(layer)
		_smoke_overlay = ColorRect.new()
		_smoke_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_smoke_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_smoke_overlay)
	_smoke_overlay.visible = true
	_smoke_overlay.color = Color(0.6, 0.6, 0.58, a)


func flash_burst(pos: Vector3) -> void:
	_light(pos + Vector3.UP * 0.3, Color(0.95, 0.97, 1.0), 40.0, 18.0, 0.28)
	_emit("flash_glow", pos + Vector3.UP * 0.2, Vector3.UP)
	_emit("flash_sparks", pos + Vector3.UP * 0.1, Vector3.UP)
	_emit("dust_small", pos, Vector3.UP, Color(0.75, 0.75, 0.75, 0.5))
	var g := _ray(pos + Vector3.UP * 0.4, pos + Vector3.DOWN * 1.5)
	if not g.is_empty():
		_scorch_decal(g["position"], g["normal"], 0.9)
	Sfx.play3d("flashbang", pos, 6.0, 1.0, 120.0)
	camera_shake.emit(pos, 0.35)


func debris(pos: Vector3, dir: Vector3, mat: String) -> void:
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	match mat:
		"metal":
			_emit("exp_debris", pos, d, Color(0.35, 0.35, 0.36, 1.0), 0.6)
			_emit("sparks", pos, d)
			Sfx.play3d("imp_metal", pos, 2.0, 0.8, 60.0)
		"concrete":
			_emit("exp_debris", pos, d, Color(0.5, 0.48, 0.45, 1.0), 0.7)
			_emit("dust", pos, d, Color(0.6, 0.58, 0.55, 0.7), 2.0)
			Sfx.play3d("imp_concrete", pos, 2.0, 0.7, 60.0)
		_:
			_emit("planks", pos, d)
			_emit("splinters", pos, d, Color(1, 1, 1, 1), 2.0)
			_emit("dust", pos, d, Color(0.5, 0.4, 0.28, 0.6), 2.0)
			Sfx.play3d("wood_break", pos, 3.0, _rng.randf_range(0.9, 1.1), 70.0)


func shell(pos: Vector3, dir: Vector3) -> void:
	_emit("shell", pos, dir.normalized())
	var land := pos + dir * 0.5 + Vector3.DOWN * 1.2
	get_tree().create_timer(_rng.randf_range(0.45, 0.6)).timeout.connect(func(): Sfx.play3d("shell", land, -8.0, _rng.randf_range(0.9, 1.2), 20.0))


# =============================================================================
# Tracers
# =============================================================================

func _spawn_tracer(from: Vector3, to: Vector3, sniper: bool) -> void:
	var total := from.distance_to(to)
	if total < 2.0:
		return
	var node: MeshInstance3D
	if _tracer_pool.is_empty():
		node = MeshInstance3D.new()
		node.mesh = _quad(1.0)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = STREAK_SHADER
		node.material_override = m
		add_child(node)
	else:
		node = _tracer_pool.pop_back()
	node.visible = true
	var m2: ShaderMaterial = node.material_override
	m2.set_shader_parameter("tint", Color(0.8, 0.9, 1.0, 0.6) if sniper else Color(1.0, 0.8, 0.5, 1.0))
	m2.set_shader_parameter("intensity", 3.0 if sniper else 7.0)
	var dir := (to - from) / total
	_tracers.append({"node": node, "pos": from, "dir": dir, "travelled": 0.0, "total": total, "sniper": sniper})


func _update_tracers(delta: float) -> void:
	if _tracers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	var i := _tracers.size() - 1
	while i >= 0:
		var t: Dictionary = _tracers[i]
		var node: MeshInstance3D = t["node"]
		t["travelled"] += TRACER_SPEED * delta
		var trav: float = t["travelled"]
		var total: float = t["total"]
		if trav >= total + 3.0:
			node.visible = false
			_tracer_pool.append(node)
			_tracers.remove_at(i)
			i -= 1
			continue
		var length := 3.2 if not t["sniper"] else 9.0
		var head := minf(trav, total)
		var tail := maxf(0.0, trav - length)
		var seg := head - tail
		if seg <= 0.01:
			node.visible = false
		else:
			var dir: Vector3 = t["dir"]
			var start: Vector3 = t["pos"]
			var center := start + dir * (tail + seg * 0.5)
			var width := 0.025
			if cam:
				width = maxf(0.02, cam.global_position.distance_to(center) * 0.0016)
			if t["sniper"]:
				width *= 0.7
			var b2 := _basis_from_z(dir)
			node.global_transform = Transform3D(Basis(b2.x * width, b2.y, b2.z * seg), center)
			node.visible = true
		i -= 1


# =============================================================================
# Muzzle flash nodes and transient lights
# =============================================================================

func _get_flash_node() -> Node3D:
	if not _flash_pool.is_empty():
		return _flash_pool.pop_back()
	var n := Node3D.new()
	add_child(n)
	var star := MeshInstance3D.new()
	star.mesh = _quad(1.0)
	star.material_override = _add_mat("flash_star", "star", Color(1.0, 0.7, 0.38), 5.0, 2, 0.0)
	n.add_child(star)
	var core := MeshInstance3D.new()
	core.mesh = _quad(1.0)
	core.material_override = _add_mat("flash_core", "soft", Color(1.0, 0.8, 0.55), 6.0, 2, 0.0)
	n.add_child(core)
	for i in 2:
		var petal := MeshInstance3D.new()
		petal.mesh = _quad(1.0)
		petal.material_override = _add_mat("flash_petal", "flame", Color(1.0, 0.6, 0.25), 5.0, 0, 0.0)
		n.add_child(petal)
	for c in n.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func _update_flashes(delta: float) -> void:
	var i := _flashes.size() - 1
	while i >= 0:
		var f: Dictionary = _flashes[i]
		f["t"] += delta
		if f["t"] >= f["dur"]:
			var n: Node3D = f["node"]
			n.visible = false
			_flash_pool.append(n)
			_flashes.remove_at(i)
		i -= 1


func _light(pos: Vector3, color: Color, energy: float, rng: float, dur: float) -> void:
	var l: OmniLight3D
	if _light_pool.is_empty():
		l = OmniLight3D.new()
		l.shadow_enabled = false
		l.omni_attenuation = 1.6
		add_child(l)
	else:
		l = _light_pool.pop_back()
	l.visible = true
	l.global_position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	_lights.append({"light": l, "t": 0.0, "dur": dur, "energy": energy})


func _update_lights(delta: float) -> void:
	var i := _lights.size() - 1
	while i >= 0:
		var e: Dictionary = _lights[i]
		e["t"] += delta
		var l: OmniLight3D = e["light"]
		var k: float = e["t"] / e["dur"]
		if k >= 1.0:
			l.visible = false
			_light_pool.append(l)
			_lights.remove_at(i)
		else:
			l.light_energy = e["energy"] * pow(1.0 - k, 1.6)
		i -= 1


# =============================================================================
# Decals
# =============================================================================

func _decal(pos: Vector3, normal: Vector3, kind: String, size: float, depth := 0.08) -> void:
	var d: Decal
	if _decals.size() < MAX_DECALS:
		d = Decal.new()
		d.distance_fade_enabled = true
		d.distance_fade_begin = 35.0
		d.distance_fade_length = 15.0
		d.normal_fade = 0.35
		d.upper_fade = 0.05
		d.lower_fade = 0.05
		add_child(d)
		_decals.append(d)
	else:
		d = _decals[_decal_i]
		_decal_i = (_decal_i + 1) % MAX_DECALS
	var t: Array = _tex[kind]
	d.texture_albedo = t[0]
	d.texture_normal = t[1] if t.size() > 1 else null
	d.size = Vector3(size, depth * 2.0, size)
	d.modulate = Color(1, 1, 1, 1)
	d.albedo_mix = 1.0
	d.global_transform = Transform3D(_basis_from_y(normal.normalized()).rotated(normal.normalized(), _rng.randf() * TAU), pos)


func _scorch_decal(pos: Vector3, normal: Vector3, size: float) -> void:
	var d: Decal
	if _scorch.size() < MAX_SCORCH:
		d = Decal.new()
		d.normal_fade = 0.2
		add_child(d)
		_scorch.append(d)
	else:
		d = _scorch[_scorch_i]
		_scorch_i = (_scorch_i + 1) % MAX_SCORCH
	d.texture_albedo = _tex["scorch"][0]
	d.size = Vector3(size, 1.2, size)
	d.global_transform = Transform3D(_basis_from_y(normal.normalized()).rotated(normal.normalized(), _rng.randf() * TAU), pos)


# =============================================================================
# Particle emitters (pooled CPUParticles3D, world-space, one-shot)
# =============================================================================

func _emit(kind: String, pos: Vector3, dir: Vector3, color := Color(1, 1, 1, 1), scale := 1.0) -> void:
	if not _pools.has(kind):
		_pools[kind] = {"items": [], "i": 0}
	var pool: Dictionary = _pools[kind]
	var items: Array = pool["items"]
	var size := _pool_size(kind)
	var p: CPUParticles3D
	if items.size() < size:
		p = _make_emitter(kind)
		add_child(p)
		items.append(p)
	else:
		p = items[pool["i"]]
		pool["i"] = (int(pool["i"]) + 1) % size
	p.global_transform = Transform3D(_basis_from_z(dir.normalized() if dir.length() > 0.01 else Vector3.UP), pos)
	if not p.has_meta("b"):
		p.set_meta("b", [p.scale_amount_min, p.scale_amount_max, p.initial_velocity_min, p.initial_velocity_max, p.emission_sphere_radius])
	var b: Array = p.get_meta("b")
	p.scale_amount_min = b[0] * scale
	p.scale_amount_max = b[1] * scale
	p.initial_velocity_min = b[2] * sqrt(scale)
	p.initial_velocity_max = b[3] * sqrt(scale)
	p.emission_sphere_radius = b[4] * scale
	p.color = color
	p.restart()
	p.emitting = true


func _pool_size(kind: String) -> int:
	match kind:
		"dust", "chips", "sparks", "dust_small":
			return 14
		"splinters", "blood_mist", "blood_drops", "muzzle_smoke", "shell", "sparks_few":
			return 10
		_:
			return 4


func _make_emitter(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.gravity = Vector3.ZERO
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"dust", "dust_small":
			var small := kind == "dust_small"
			p.amount = 4 if small else 7
			p.lifetime = 0.9 if small else 1.6
			p.mesh = _quad(0.55 if small else 0.85)
			p.material_override = _lit_mat("dust", "puff", 0.4)
			p.spread = 40.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 2.4
			p.damping_min = 3.0
			p.damping_max = 4.5
			p.gravity = Vector3(0, 0.25, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.0
			p.scale_amount_curve = _curve([Vector2(0, 0.35), Vector2(0.3, 0.85), Vector2(1, 1.5)])
			p.color_ramp = _fade_ramp(0.08)

		"chips":
			p.amount = 9
			p.lifetime = 0.9
			p.mesh = _box(Vector3(0.022, 0.018, 0.02))
			p.material_override = _solid_mat("chips", Color(0.45, 0.43, 0.4), 0.9)
			p.spread = 50.0
			p.initial_velocity_min = 2.5
			p.initial_velocity_max = 6.0
			p.gravity = Vector3(0, -14, 0)
			p.angular_velocity_min = -720.0
			p.angular_velocity_max = 720.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.4
			p.particle_flag_rotate_y = true
		"sparks", "sparks_few", "exp_sparks", "flash_sparks":
			p.amount = {"sparks": 18, "sparks_few": 5, "exp_sparks": 48, "flash_sparks": 22}[kind]
			p.lifetime = 0.9 if kind == "exp_sparks" else 0.4
			p.mesh = _box(Vector3(0.007, 0.11 if kind == "exp_sparks" else 0.07, 0.007))
			var col := Color(1.0, 0.95, 0.85) if kind == "flash_sparks" else Color(1.0, 0.62, 0.22)
			p.material_override = _add_mat("spark_" + kind, "white", col, 9.0, 0, 0.0)
			p.particle_flag_align_y = true
			p.spread = 180.0 if kind == "exp_sparks" or kind == "flash_sparks" else 60.0
			p.initial_velocity_min = 3.0 if kind != "exp_sparks" else 7.0
			p.initial_velocity_max = 9.0 if kind != "exp_sparks" else 20.0
			p.gravity = Vector3(0, -9.8, 0)
			p.damping_min = 0.5
			p.damping_max = 1.5
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.3
			p.scale_amount_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.15)])
			p.color_ramp = _fade_ramp(0.0)
		"splinters":
			p.amount = 9
			p.lifetime = 1.0
			p.mesh = _box(Vector3(0.012, 0.08, 0.012))
			p.material_override = _solid_mat("splinters", Color(0.62, 0.47, 0.3), 0.8)
			p.particle_flag_align_y = true
			p.spread = 55.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.5
			p.gravity = Vector3(0, -12, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.3
		"dirt":
			p.amount = 14
			p.lifetime = 1.0
			p.mesh = _box(Vector3(0.03, 0.03, 0.03))
			p.material_override = _solid_mat("dirt", Color(0.33, 0.25, 0.17), 1.0)
			p.spread = 30.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 6.0
			p.gravity = Vector3(0, -14, 0)
			p.angular_velocity_min = -400.0
			p.angular_velocity_max = 400.0
			p.scale_amount_min = 0.4
			p.scale_amount_max = 1.2
		"glass":
			p.amount = 12
			p.lifetime = 1.0
			p.mesh = _box(Vector3(0.025, 0.035, 0.003))
			p.material_override = _add_mat("glass_shard", "white", Color(0.7, 0.85, 1.0), 2.0, 0, 0.0)
			p.spread = 50.0
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 5.0
			p.gravity = Vector3(0, -14, 0)
			p.angular_velocity_min = -720.0
			p.angular_velocity_max = 720.0
			p.color_ramp = _fade_ramp(0.0)
		"blood_mist":
			p.amount = 7
			p.lifetime = 0.55
			p.mesh = _quad(0.45)
			p.material_override = _lit_mat("blood_mist", "puff", 0.25)
			p.spread = 35.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 2.4
			p.damping_min = 3.0
			p.damping_max = 5.0
			p.gravity = Vector3(0, -0.6, 0)
			p.angle_max = 360.0
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.1
			p.scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.4, 0.9), Vector2(1, 1.3)])
			var g := Gradient.new()
			g.set_color(0, Color(0.42, 0.03, 0.03, 0.85))
			g.set_color(1, Color(0.25, 0.02, 0.02, 0.0))
			p.color_ramp = g
		"blood_drops":
			p.amount = 12
			p.lifetime = 0.7
			p.mesh = _box(Vector3(0.014, 0.03, 0.014))
			p.material_override = _solid_mat("blood_drop", Color(0.35, 0.02, 0.02), 0.3)
			p.particle_flag_align_y = true
			p.spread = 40.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 4.5
			p.gravity = Vector3(0, -12, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.2
		"muzzle_smoke":
			p.amount = 3
			p.lifetime = 0.9
			p.mesh = _quad(0.3)
			p.material_override = _lit_mat("muzzle_smoke", "puff", 0.2)
			p.spread = 25.0
			p.initial_velocity_min = 0.4
			p.initial_velocity_max = 1.4
			p.damping_min = 2.0
			p.damping_max = 3.0
			p.gravity = Vector3(0, 0.35, 0)
			p.angle_max = 360.0
			p.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 1.6)])
			var g2 := Gradient.new()
			g2.set_color(0, Color(0.8, 0.8, 0.8, 0.22))
			g2.set_color(1, Color(0.8, 0.8, 0.8, 0.0))
			p.color_ramp = g2
		"fireball", "fire_core":
			var core := kind == "fire_core"
			p.amount = 12 if core else 26
			p.lifetime = 0.45 if core else 0.9
			p.mesh = _quad(2.0 if core else 1.8)
			p.material_override = _add_mat("fire", "glowpuff", Color(1.0, 0.7, 0.4), 3.2, 1, 0.5)
			p.spread = 180.0
			p.initial_velocity_min = 0.8 if core else 2.0
			p.initial_velocity_max = 2.5 if core else 6.0
			p.damping_min = 5.0
			p.damping_max = 8.0
			p.gravity = Vector3(0, 3.0, 0)
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.5
			p.angle_max = 360.0
			p.angular_velocity_min = -60.0
			p.angular_velocity_max = 60.0
			p.scale_amount_min = 0.7
			p.scale_amount_max = 1.3
			p.scale_amount_curve = _curve([Vector2(0, 0.45), Vector2(0.2, 1.0), Vector2(1, 1.35)])
			var g3 := Gradient.new()
			g3.set_color(0, Color(1.0, 0.85, 0.55, 1.0))
			g3.set_color(1, Color(0.15, 0.03, 0.0, 0.0))
			g3.add_point(0.18, Color(1.0, 0.55, 0.16, 1.0))
			g3.add_point(0.5, Color(0.6, 0.16, 0.03, 0.7))
			p.color_ramp = g3

		"flash_glow":
			p.amount = 2
			p.lifetime = 0.16
			p.mesh = _quad(2.6)
			p.material_override = _add_mat("flash_glow", "star", Color(0.95, 0.97, 1.0), 7.0, 1, 0.0)
			p.spread = 0.0
			p.initial_velocity_min = 0.0
			p.initial_velocity_max = 0.0
			p.angle_max = 360.0
			p.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(0.25, 1.0), Vector2(1, 0.4)])
			p.color_ramp = _fade_ramp(0.0)

		"smoke_column":
			p.amount = 30
			p.lifetime = 6.0
			p.explosiveness = 0.7
			p.mesh = _quad(2.6)
			p.material_override = _lit_mat("smoke_dark", "puff", 0.8)
			p.spread = 25.0
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.8
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 2.4
			p.damping_min = 0.6
			p.damping_max = 1.0
			p.gravity = Vector3(0.25, 1.1, 0.1)
			p.scale_amount_min = 0.8
			p.scale_amount_max = 1.3
			p.scale_amount_curve = _curve([Vector2(0, 0.45), Vector2(0.25, 1.1), Vector2(1, 2.3)])
			p.color_ramp = _fade_ramp(0.06)

		"dust_ring":
			p.amount = 22
			p.lifetime = 2.2
			p.mesh = _quad(1.8)
			p.material_override = _lit_mat("dust_ring", "puff", 0.6)
			p.direction = Vector3(1, 0, 0)
			p.spread = 180.0
			p.flatness = 1.0
			p.initial_velocity_min = 5.0
			p.initial_velocity_max = 9.0
			p.damping_min = 4.0
			p.damping_max = 6.0
			p.gravity = Vector3(0, 0.4, 0)
			p.scale_amount_curve = _curve([Vector2(0, 0.5), Vector2(1, 2.0)])
			p.color_ramp = _fade_ramp(0.05)

		"exp_debris":
			p.amount = 22
			p.lifetime = 1.6
			p.mesh = _box(Vector3(0.06, 0.05, 0.07))
			p.material_override = _solid_mat("exp_debris", Color(1, 1, 1), 1.0)
			p.spread = 70.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 11.0
			p.gravity = Vector3(0, -14, 0)
			p.angular_velocity_min = -540.0
			p.angular_velocity_max = 540.0
			p.particle_flag_rotate_y = true
			p.scale_amount_min = 0.4
			p.scale_amount_max = 1.6
		"planks":
			p.amount = 8
			p.lifetime = 2.2
			p.mesh = _box(Vector3(0.09, 0.5, 0.025))
			p.material_override = _wood_mat()
			p.spread = 65.0
			p.initial_velocity_min = 3.0
			p.initial_velocity_max = 7.5
			p.gravity = Vector3(0, -14, 0)
			p.angular_velocity_min = -360.0
			p.angular_velocity_max = 360.0
			p.particle_flag_rotate_y = true
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.2
		"shell":
			p.amount = 1
			p.lifetime = 0.9
			p.mesh = _cylinder(0.0045, 0.022)
			p.material_override = _solid_mat("brass", Color(0.85, 0.62, 0.25), 0.3, 1.0)
			p.spread = 15.0
			p.initial_velocity_min = 1.8
			p.initial_velocity_max = 2.6
			p.gravity = Vector3(0, -11, 0)
			p.angular_velocity_min = 600.0
			p.angular_velocity_max = 900.0
			p.particle_flag_rotate_y = true
	var lm := p.material_override as StandardMaterial3D
	if lm and lm.particles_anim_h_frames > 1:
		p.anim_offset_max = 1.0
		p.angle_max = 0.0
		p.angular_velocity_min = 0.0
		p.angular_velocity_max = 0.0
	return p


# =============================================================================
# Helpers: meshes, materials, curves
# =============================================================================

func _quad(size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cylinder(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	for pt in points:
		c.add_point(pt)
	return c


func _fade_ramp(fade_in: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0 if fade_in > 0.0 else 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	if fade_in > 0.0:
		g.add_point(fade_in, Color(1, 1, 1, 1))
	return g


func _add_mat(key: String, tex: String, tint: Color, intensity: float, billboard: int, soft: float) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = ADD_SHADER
	m.set_shader_parameter("tex", _tex[tex][0])
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("soft_distance", soft)
	_mats[key] = m
	return m


## Lit, alpha-blended billboard for dust/smoke (receives scene lighting).
func _lit_mat(key: String, tex: String, soft: float) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _tex[tex][0]
	if tex == "puff":
		m.particles_anim_h_frames = 2
		m.particles_anim_v_frames = 2
		m.particles_anim_loop = false
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.disable_receive_shadows = false
	if soft > 0.0:
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = soft
	_mats[key] = m
	return m


func _solid_mat(key: String, c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.vertex_color_use_as_albedo = true
	_mats[key] = m
	return m


func _wood_mat() -> StandardMaterial3D:
	if _mats.has("wood_planks"):
		return _mats["wood_planks"]
	var m := StandardMaterial3D.new()
	var path := "res://assets/textures/weathered_planks/weathered_planks_diff_1k.jpg"
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.uv1_scale = Vector3(0.3, 1.0, 1.0)
	else:
		m.albedo_color = Color(0.45, 0.33, 0.2)
	m.roughness = 0.85
	m.vertex_color_use_as_albedo = true
	_mats["wood_planks"] = m
	return m


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var w := get_world_3d()
	if w == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, Cfg.L_WORLD | Cfg.L_DYNAMIC)
	return w.direct_space_state.intersect_ray(q)


static func _basis_from_z(z: Vector3) -> Basis:
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)


static func _basis_from_y(y: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# =============================================================================
# Procedural textures (generated once per process)
# =============================================================================

func _build_textures() -> void:
	if not _tex.is_empty():
		return
	_tex["white"] = [_img_tex(_solid_img(8, Color(1, 1, 1, 1)))]
	_tex["soft"] = [_img_tex(_soft_img(64))]
	_tex["puff"] = [_img_tex(_puff_atlas(128, 7, true))]
	_tex["glowpuff"] = [_img_tex(_puff_atlas(128, 11, false).get_region(Rect2i(0, 0, 128, 128)))]
	_tex["star"] = [_img_tex(_star_img(128))]
	_tex["flame"] = [_img_tex(_flame_img(64, 128))]
	_tex["hole_concrete"] = _hole_tex("concrete", 128, 1)
	_tex["hole_metal"] = _hole_tex("metal", 128, 2)
	_tex["hole_wood"] = _hole_tex("wood", 128, 3)
	_tex["hole_dirt"] = _hole_tex("dirt", 128, 4)
	_tex["hole_glass"] = _hole_tex("glass", 128, 5)
	for i in 3:
		_tex["blood%d" % i] = [_img_tex(_blood_img(128, 20 + i))]
	_tex["scorch"] = [_img_tex(_scorch_img(256, 9))]


func _img_tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _solid_img(s: int, c: Color) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return img


func _soft_img(s: int) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var h := s * 0.5
	for y in s:
		for x in s:
			var r := Vector2(x - h + 0.5, y - h + 0.5).length() / h
			var a := clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return img


func _noise_img(s: int, seed: int, freq: float, cellular := false) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 4
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if cellular else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n.get_image(s, s, false, false, true)


## 2x2 atlas of billowy cloud puffs. Each is a cluster of sphere caps with noise detail;
## `shaded` bakes top-down lighting into RGB so lit billboards read as volumes.
func _puff_atlas(s: int, seed: int, shaded: bool) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := _noise_img(s, seed, 0.06)
	var img := Image.create(s * 2, s * 2, false, Image.FORMAT_RGBA8)
	var light := Vector3(-0.35, 0.8, 0.5).normalized()
	for v in 4:
		var blobs: Array = []
		for i in rng.randi_range(11, 15):
			var a := rng.randf() * TAU
			var d := rng.randf_range(0.0, 0.5)
			blobs.append([Vector2(cos(a), sin(a) * 0.85 + 0.06) * d, rng.randf_range(0.14, 0.32)])
		var hf := PackedFloat32Array()
		hf.resize(s * s)
		for y in s:
			for x in s:
				var p := Vector2((x + 0.5) / s * 2.0 - 1.0, (y + 0.5) / s * 2.0 - 1.0)
				var h := 0.0
				for b in blobs:
					var c: Vector2 = b[0]
					var r: float = b[1]
					var dd := p.distance_squared_to(c)
					if dd < r * r:
						h = maxf(h, sqrt(r * r - dd))
				var nv := noise.get_pixel((x + v * 37) % s, (y + v * 53) % s).r
				var nv2 := noise.get_pixel((x * 2 + v * 11) % s, (y * 2 + v * 29) % s).r
				h += ((nv - 0.5) * 0.2 + (nv2 - 0.5) * 0.08) * clampf(h * 5.0, 0.0, 1.0) - 0.02
				hf[y * s + x] = maxf(h, 0.0)
		var ox := (v % 2) * s
		var oy := (v / 2) * s
		for y in s:
			for x in s:
				var h := hf[y * s + x]
				var edge := clampf(1.0 - Vector2((x + 0.5) / s * 2.0 - 1.0, (y + 0.5) / s * 2.0 - 1.0).length(), 0.0, 1.0)
				var a := smoothstep(0.0, 0.2, h) * clampf(edge * 4.0, 0.0, 1.0)
				var shade := 1.0
				if shaded:
					var hx := hf[y * s + mini(x + 1, s - 1)] - hf[y * s + maxi(x - 1, 0)]
					var hy := hf[mini(y + 1, s - 1) * s + x] - hf[maxi(y - 1, 0) * s + x]
					var n := Vector3(-hx * 6.0, hy * 6.0, 1.0).normalized()
					shade = clampf(0.62 + 0.38 * n.dot(light), 0.45, 1.0)
					shade *= 0.88 + 0.12 * clampf(h * 3.0, 0.0, 1.0)
				img.set_pixel(ox + x, oy + y, Color(shade, shade, shade, a))
	return img


func _star_img(s: int) -> Image:
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var h := s * 0.5
	var rays := 6
	for y in s:
		for x in s:
			var v := Vector2(x - h + 0.5, y - h + 0.5)
			var r := v.length() / h
			var ang := atan2(v.y, v.x)
			var k := absf(sin(ang * rays * 0.5))
			var ray := pow(1.0 - k, 6.0) * clampf(1.0 - r, 0.0, 1.0)
			var core := pow(clampf(1.0 - r * 2.2, 0.0, 1.0), 2.0)
			var a := clampf(ray * 1.2 + core, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.95 - r * 0.3, 0.85 - r * 0.5, a))
	return img


func _flame_img(w: int, h: int) -> Image:
	var noise := _noise_img(maxi(w, h), 3, 0.08)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := float(y) / h # 0 = top (tip), 1 = base
			var u := absf(float(x) / w * 2.0 - 1.0)
			var width := 0.15 + 0.85 * pow(v, 0.7)
			var nv := noise.get_pixel(x, y).r
			var a := clampf(1.0 - u / width, 0.0, 1.0) * pow(v, 1.2) * (0.6 + nv * 0.8)
			img.set_pixel(x, y, Color(1.0, 0.75 + v * 0.25, 0.4 + v * 0.5, clampf(a, 0.0, 1.0)))
	return img


func _hole_tex(kind: String, s: int, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919
	var noise := _noise_img(s, seed, 0.11)
	var noise2 := _noise_img(s, seed + 40, 0.03)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var hgt := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var h := s * 0.5
	var cracks: Array = []
	for i in rng.randi_range(3, 5):
		cracks.append([rng.randf() * TAU, rng.randf_range(0.45, 0.8), rng.randf_range(4.0, 9.0)])
	for y in s:
		for x in s:
			var v := Vector2(x - h + 0.5, y - h + 0.5)
			var r0 := v.length() / h
			var ang := atan2(v.y, v.x)
			var nv := noise.get_pixel(x, y).r
			var nv2 := noise2.get_pixel(x, y).r
			var r := r0 + (nv2 - 0.5) * 0.22 # irregular outline
			var col := Color(0, 0, 0, 0)
			var height := 0.5
			var crack := 0.0
			for c in cracks:
				var wob: float = c[0] + sin(r0 * c[2]) * 0.12
				var da := absf(wrapf(ang - wob, -PI, PI)) * r0
				var reach: float = c[1]
				if r0 < reach:
					crack = maxf(crack, clampf(1.0 - da * 60.0, 0.0, 1.0) * (1.0 - r0 / reach))
			match kind:
				"concrete":
					if r < 0.1:
						col = Color(0.03, 0.03, 0.03, 1.0)
						height = 0.0
					elif r < 0.27:
						var t := (r - 0.1) / 0.17
						var g := lerpf(0.2, 0.42, t) * (0.8 + nv * 0.4)
						col = Color(g, g * 0.97, g * 0.92, 1.0)
						height = 0.1 + t * 0.4 + nv * 0.1
					elif r < 0.5:
						var t2 := (r - 0.27) / 0.23
						var g2 := 0.62 + nv * 0.12
						col = Color(g2, g2 * 0.97, g2 * 0.92, clampf((1.0 - t2) * (0.25 + nv * 0.6), 0.0, 1.0))
						height = 0.55 + nv * 0.1
					if crack > 0.05:
						var ca := crack * 0.85
						col = Color(0.12, 0.12, 0.11, maxf(col.a, ca))
						height = minf(height, 0.5 - crack * 0.25)
				"metal":
					if r < 0.12:
						col = Color(0.02, 0.02, 0.02, 1.0)
						height = 0.0
					elif r < 0.2:
						var t3 := (r - 0.12) / 0.08
						var g3 := lerpf(0.75, 0.45, t3)
						col = Color(g3, g3, g3 * 0.97, 1.0)
						height = 0.9 - t3 * 0.3
					elif r < 0.48:
						var t4 := (r - 0.2) / 0.28
						col = Color(0.08, 0.07, 0.06, (1.0 - t4) * 0.6 * (0.6 + nv * 0.6))
						height = 0.55
				"wood":
					# Wood tears along the grain (vertical) rather than radially.
					var stretch := Vector2(v.x / h * 1.9, v.y / h * 0.75).length() + (nv2 - 0.5) * 0.3
					if r < 0.12:
						col = Color(0.06, 0.035, 0.02, 1.0)
						height = 0.0
					elif stretch < 0.55:
						var t5 := stretch / 0.55
						col = Color(0.74, 0.58, 0.38, clampf((1.0 - t5) * (0.5 + nv * 0.8), 0.0, 1.0))
						height = 0.75 - t5 * 0.2
				"dirt":
					var a := clampf((0.5 + nv * 0.35 - r0) * 3.0, 0.0, 1.0)
					col = Color(0.12, 0.09, 0.06, a * 0.8)
					height = 0.5 - a * 0.4
				"glass":
					if r0 < 0.07:
						col = Color(0.05, 0.05, 0.05, 0.95)
						height = 0.0
					else:
						var ring := absf(sin(r0 * 24.0 + nv * 2.0)) < 0.1 and r0 < 0.55
						var a2 := maxf(crack * 1.2, 0.45 if ring else 0.0)
						col = Color(0.92, 0.95, 1.0, clampf(a2, 0.0, 1.0) * 0.8)
						height = 0.5 + a2 * 0.3
			img.set_pixel(x, y, col)
			hgt.set_pixel(x, y, Color(height, height, height, 1.0))
	hgt.bump_map_to_normal_map(5.0)
	return [_img_tex(img), _img_tex(hgt)]


func _blood_img(s: int, seed: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var noise := _noise_img(s, seed, 0.05)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var h := s * 0.5
	var drops: Array = []
	for i in rng.randi_range(10, 18):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.25, 0.85)
		drops.append([Vector2(cos(ang), sin(ang)) * dist * h + Vector2(h, h), rng.randf_range(1.5, 6.0)])
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var r := (p - Vector2(h, h)).length() / h
			var nv := noise.get_pixel(x, y).r
			var a := clampf((0.32 + nv * 0.3 - r) * 5.0, 0.0, 1.0)
			for d in drops:
				var dc: Vector2 = d[0]
				var dr: float = d[1]
				a = maxf(a, clampf((dr - p.distance_to(dc)) * 0.8, 0.0, 1.0))
			var c := Color(0.32, 0.015, 0.015).lerp(Color(0.18, 0.0, 0.0), nv)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a * 0.92))
	return img


func _scorch_img(s: int, seed: int) -> Image:
	var noise := _noise_img(s, seed, 0.02)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var h := s * 0.5
	for y in s:
		for x in s:
			var v := Vector2(x - h + 0.5, y - h + 0.5)
			var r := v.length() / h
			var nv := noise.get_pixel(x, y).r
			var ang := atan2(v.y, v.x)
			var streak := 0.5 + 0.5 * sin(ang * 13.0 + nv * 6.0)
			var a := clampf((1.0 - r * (1.05 - streak * 0.15)) * (0.7 + nv * 0.6), 0.0, 1.0)
			a = pow(a, 0.8) * 0.9
			img.set_pixel(x, y, Color(0.03, 0.025, 0.02, a))
	return img
