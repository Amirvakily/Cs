class_name Viewmodel
extends Node3D
## First-person weapon + gloved arms. Child of the local Camera3D.
## All meshes use shaders/viewmodel.gdshader (fixed FOV, depth squashed so it never clips walls).

const SHADER := preload("res://shaders/viewmodel.gdshader")
const F_ON_FLOOR := 1
const F_COVER := 8

static var _mat_cache := {}
static var _arm_meshes := {}

var team := 1
var weapon_id := ""
var hold := "rifle"
var sight_y := 0.1

var rig: Node3D
var holder: Node3D
var gun: Node3D
var _sleeve_r: MeshInstance3D
var _sleeve_l: MeshInstance3D
var _glove_r: MeshInstance3D
var _glove_l: MeshInstance3D
var _mag: Node3D
var _mag_rest := Vector3.ZERO
var _pump: Node3D
var _pump_rest := Vector3.ZERO
var _bolt: Node3D
var _bolt_rest := Transform3D.IDENTITY
var _slide: Node3D
var _slide_rest := Vector3.ZERO
var _sight := Vector3(0, 0.1, -0.1)
var _eye := 0.18
var _cls := "rifle"
# Recoil springs (position / rotation offsets and their velocities)
var _rp := Vector3.ZERO
var _rpv := Vector3.ZERO
var _rr := Vector3.ZERO
var _rrv := Vector3.ZERO
var _slide_t := -1.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()

var _t := 0.0
var _draw := 1.0
var _draw_time := 0.45
var _kick := 0.0
var _reload := -1.0
var _reload_dur := 1.0
var _knife := -1.0
var _knife_alt := false
var _throw := -1.0
var _pump_t := -1.0
var _bolt_t := -1.0
var _bob := 0.0
var _bob_amp := 0.0
var _sway := Vector2.ZERO
var _fall := 0.0
var _ads := 0.0


func _ready() -> void:
	if rig == null:
		_build_rig()


func _build_rig() -> void:
	rig = Node3D.new()
	rig.name = "Rig"
	add_child(rig)
	holder = Node3D.new()
	holder.name = "Holder"
	rig.add_child(holder)
	var meshes := _arms_for(team)
	_sleeve_r = _vm_mesh(rig, "SleeveR", meshes["sleeve"])
	_sleeve_l = _vm_mesh(rig, "SleeveL", meshes["sleeve_l"])
	_glove_r = _vm_mesh(rig, "GloveR", meshes["glove"])
	_glove_l = _vm_mesh(rig, "GloveL", meshes["glove_l"])


func setup(p_team: int) -> void:
	team = p_team
	if rig:
		rig.queue_free()
		rig = null
	_build_rig()
	if weapon_id != "":
		var w := weapon_id
		weapon_id = ""
		set_weapon(w)


func _vm_mesh(parent: Node3D, name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in mesh.get_surface_count():
		mi.set_surface_override_material(i, vm_material(mesh.surface_get_material(i)))
	parent.add_child(mi)
	return mi


## Converts a StandardMaterial3D into the viewmodel shader with equivalent parameters.
static func vm_material(src: Material) -> ShaderMaterial:
	if src != null and _mat_cache.has(src):
		return _mat_cache[src]
	var sm := ShaderMaterial.new()
	sm.shader = SHADER
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		sm.set_shader_parameter("albedo", b.albedo_color)
		if b.albedo_texture:
			sm.set_shader_parameter("albedo_tex", b.albedo_texture)
		sm.set_shader_parameter("use_vertex_color", b.vertex_color_use_as_albedo)
		sm.set_shader_parameter("use_triplanar", b.uv1_triplanar)
		sm.set_shader_parameter("triplanar_scale", b.uv1_scale.x)
		sm.set_shader_parameter("roughness", b.roughness)
		sm.set_shader_parameter("metallic", b.metallic)
		if b.roughness_texture:
			sm.set_shader_parameter("rough_tex", b.roughness_texture)
			sm.set_shader_parameter("rough_channel", 1 if b.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN else 0)
		if b.metallic_texture:
			sm.set_shader_parameter("metal_tex", b.metallic_texture)
			sm.set_shader_parameter("metal_from_blue", b.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE)
		if b.ao_enabled and b.ao_texture:
			sm.set_shader_parameter("use_ao", true)
			sm.set_shader_parameter("ao_tex", b.ao_texture)
		if b.normal_enabled and b.normal_texture:
			sm.set_shader_parameter("use_normal", true)
			sm.set_shader_parameter("normal_tex", b.normal_texture)
			sm.set_shader_parameter("normal_depth", b.normal_scale)
		if b.emission_enabled:
			sm.set_shader_parameter("emission_color", b.emission)
			sm.set_shader_parameter("emission_energy", b.emission_energy_multiplier)
	if src != null:
		_mat_cache[src] = sm
	return sm


static func _convert(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					var src: Material = mi.get_surface_override_material(i)
					if src == null:
						src = mi.mesh.surface_get_material(i)
					if mi.material_override:
						src = mi.material_override
					mi.set_surface_override_material(i, vm_material(src))
				mi.material_override = null
		_convert(c)


func set_weapon(id: String) -> void:
	if rig == null:
		_build_rig()
	if id == weapon_id and gun != null:
		return
	weapon_id = id
	if gun:
		gun.queue_free()
		gun = null
	_mag = null
	_pump = null
	_bolt = null
	_slide = null
	if id == "":
		return
	gun = WeaponModels.build(id)
	_convert(gun)
	holder.add_child(gun)
	hold = String(gun.get_meta("hold", "rifle"))
	# Small weapons are drawn slightly larger so they read well on screen.
	var k := 1.0
	if id == "m9":
		k = 1.32
	elif hold == "pistol":
		k = 1.12
	gun.scale = Vector3.ONE * k
	sight_y = float(gun.get_meta("sight_y", 0.1)) * k
	_eye = float(gun.get_meta("eye_relief", 0.18))
	var sm := gun.get_node_or_null("Sight") as Node3D
	_sight = gun.transform * (sm.position if sm else Vector3(0, sight_y / k, -0.1))
	_cls = String(Cfg.w(id).get("cls", "rifle"))
	_slide = gun.get_node_or_null("Slide") as Node3D
	if _slide:
		_slide_rest = _slide.position
	_mag = gun.get_node_or_null("Mag") as Node3D
	if _mag:
		_mag_rest = _mag.position
	_pump = gun.get_node_or_null("Pump") as Node3D
	if _pump:
		_pump_rest = _pump.position
	_bolt = gun.get_node_or_null("Bolt") as Node3D
	if _bolt:
		_bolt_rest = _bolt.transform
	var w := Cfg.w(id)
	_draw_time = clampf(float(w.get("deploy", 0.5)) * 0.7, 0.25, 0.8)
	_draw = 0.0
	_reload = -1.0
	_knife = -1.0
	_throw = -1.0
	_pump_t = -1.0
	_bolt_t = -1.0
	_slide_t = -1.0
	_rp = Vector3.ZERO
	_rpv = Vector3.ZERO
	_rr = Vector3.ZERO
	_rrv = Vector3.ZERO


## Per-shot recoil: instant snap plus a velocity impulse, then a damped spring brings it home.
func on_fire() -> void:
	# back (m), rise (rad), yaw/roll jitter (rad), shake
	var p := [0.022, 0.045, 0.015, 0.025, 0.0]
	match _cls:
		"pistol":
			p = [0.02, 0.085, 0.015, 0.03, 0.0]
		"smg":
			p = [0.013, 0.03, 0.013, 0.02, 0.0]
		"shotgun":
			p = [0.05, 0.14, 0.02, 0.05, 0.0]
			_pump_t = 0.0
		"sniper":
			p = [0.06, 0.16, 0.02, 0.04, 0.0]
			if _bolt:
				_bolt_t = 0.0
		"lmg":
			p = [0.02, 0.035, 0.024, 0.035, 1.0]
	var a := smoothstep(0.0, 1.0, _ads)
	var pos_k := lerpf(1.0, 0.45, a)
	var rot_k := lerpf(1.0, 0.35, a)
	var back: float = p[0] * pos_k
	var rise: float = p[1] * rot_k
	var yaw: float = _rng.randf_range(-1.0, 1.0) * p[2] * rot_k
	var roll: float = _rng.randf_range(-1.0, 1.0) * p[3] * rot_k
	_rp.z += back * 0.6
	_rpv.z += back * 24.0
	_rp.y += back * 0.1
	_rr.x += rise * 0.55
	_rrv.x += rise * 20.0
	_rr.y += yaw * 0.5
	_rrv.y += yaw * 18.0
	_rr.z += roll * 0.5
	_rrv.z += roll * 18.0
	_shake = minf(1.0, _shake + float(p[4]) * 0.5)
	_rp.z = minf(_rp.z, 0.09)
	_rr.x = minf(_rr.x, 0.3)
	if _slide:
		_slide_t = 0.0


func _spring(x: Vector3, v: Vector3, k: float, zeta: float, dt: float) -> Array:
	var c := 2.0 * zeta * sqrt(k)
	var steps := 3
	var h := dt / steps
	for i in steps:
		v += (-k * x - c * v) * h
		x += v * h
	return [x, v]


func on_reload(duration: float) -> void:
	_reload = 0.0
	_reload_dur = maxf(0.2, duration)


func on_throw() -> void:
	_throw = 0.0


func on_knife(alt: bool) -> void:
	_knife = 0.0
	_knife_alt = alt


func muzzle_global() -> Vector3:
	if gun:
		var m := gun.get_node_or_null("Muzzle") as Node3D
		if m:
			return m.global_position
	return global_position + global_transform.basis * Vector3(0.1, -0.1, -0.6)


func update_vm(delta: float, s: Soldier, look_delta: Vector2) -> void:
	if rig == null:
		_build_rig()
	if s == null:
		return
	visible = s.alive and s.scope_level == 0 and (s.flags & F_COVER) == 0
	if not visible:
		return
	_t += delta
	_draw = minf(1.0, _draw + delta / _draw_time)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-13.0 * delta))
	if _reload >= 0.0:
		_reload += delta / _reload_dur
		if _reload >= 1.0:
			_reload = -1.0
	if _knife >= 0.0:
		_knife += delta / (0.6 if _knife_alt else 0.36)
		if _knife >= 1.0:
			_knife = -1.0
	if _throw >= 0.0:
		_throw += delta / 0.5
		if _throw >= 1.0:
			_throw = -1.0
	if _pump_t >= 0.0:
		_pump_t += delta / 0.62
		if _pump_t >= 1.0:
			_pump_t = -1.0
	if _bolt_t >= 0.0:
		_bolt_t += delta / 1.15
		if _bolt_t >= 1.0:
			_bolt_t = -1.0
	if _slide_t >= 0.0:
		_slide_t += delta / 0.09
		if _slide_t >= 1.0:
			_slide_t = -1.0
	var sp := _spring(_rp, _rpv, 330.0, 0.42, delta)
	_rp = sp[0]
	_rpv = sp[1]
	var sr := _spring(_rr, _rrv, 260.0, 0.4, delta)
	_rr = sr[0]
	_rrv = sr[1]
	_shake = maxf(0.0, _shake - delta * 4.0)
	# Snipers aim through the scope overlay, so their unscoped ADS pose is never used.
	_ads = 0.0 if _cls == "sniper" else smoothstep(0.0, 1.0, s.ads_amount)
	var hv := Vector2(s.velocity.x, s.velocity.z).length()
	var on_floor := (s.flags & F_ON_FLOOR) != 0 or s.is_on_floor()
	var target_amp := clampf(hv / 5.5, 0.0, 1.0) if on_floor else 0.0
	_bob_amp = lerpf(_bob_amp, target_amp, clampf(delta * 8.0, 0.0, 1.0))
	_bob += delta * (1.5 + hv * 1.75)
	_fall = lerpf(_fall, clampf(-s.velocity.y * 0.006, -0.03, 0.04), clampf(delta * 10.0, 0.0, 1.0))
	var sway_k := 1.0 - 0.8 * _ads
	var sway_target := Vector2(clampf(-look_delta.x * 0.0009, -0.07, 0.07), clampf(-look_delta.y * 0.0009, -0.07, 0.07)) * sway_k
	_sway = _sway.lerp(sway_target, clampf(delta * 9.0, 0.0, 1.0))
	_apply_pose(s)


func _apply_pose(s: Soldier) -> void:
	# Base pose (hip / ADS)
	var hip_pos := Vector3(0.115, -0.178, -0.3)
	var hip_rot := Vector3(0.035, 0.075, -0.035)
	# ADS: put the sight line on the view axis, `_eye` metres in front of the eye.
	var ads_pos := Vector3(-_sight.x, -_sight.y, -_eye - _sight.z)
	match hold:
		"pistol":
			hip_pos = Vector3(0.13, -0.135, -0.42)
			hip_rot = Vector3(0.02, 0.2, -0.05)
		"knife":
			hip_pos = Vector3(0.15, -0.16, -0.29)
			hip_rot = Vector3(0.35, 0.4, -0.45)
			ads_pos = hip_pos
		"grenade":
			hip_pos = Vector3(0.13, -0.13, -0.29)
			hip_rot = Vector3(0.1, 0.12, -0.15)
			ads_pos = hip_pos
		"bomb":
			hip_pos = Vector3(0.0, -0.2, -0.33)
			hip_rot = Vector3(0.55, 0.0, 0.0)
			ads_pos = hip_pos
	var ads := _ads if hold in ["rifle", "pistol"] else 0.0
	var pos := hip_pos.lerp(ads_pos, ads)
	var rot := hip_rot.lerp(Vector3.ZERO, ads)
	# Bob, breathing, landing
	var amp := _bob_amp * (1.0 - ads * 0.9)
	pos += Vector3(sin(_bob) * 0.01 * amp, -absf(cos(_bob)) * 0.012 * amp + sin(_t * 1.5) * 0.0018 * (1.0 - ads), 0.0)
	pos.y += _fall
	rot.z += sin(_bob) * 0.012 * amp
	# Recoil springs (+ LMG shake)
	pos += _rp
	rot += _rr
	if _shake > 0.0:
		pos += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * 0.0025 * _shake
		rot.z += _rng.randf_range(-1, 1) * 0.01 * _shake
	# Draw
	var e := 1.0 - pow(1.0 - _draw, 3.0)
	pos.y -= (1.0 - e) * 0.22
	rot.x -= (1.0 - e) * 0.9
	# Reload: tilt the weapon, drop & replace the magazine
	var r := _reload
	if r >= 0.0:
		var k := sin(PI * clampf(r * 1.1, 0.0, 1.0))
		rot += Vector3(0.18 * k, 0.12 * k, 0.55 * k)
		pos += Vector3(-0.02 * k, -0.035 * k, 0.02 * k)
	if _mag:
		var mo := Vector3.ZERO
		if r >= 0.0 and hold != "bomb":
			if weapon_id == "breacher":
				mo = Vector3(0, -0.15 + 0.15 * absf(sin(r * PI * 4.0)), 0.0)
			elif r < 0.4:
				mo = Vector3(0, -0.35 * smoothstep(0.12, 0.4, r), 0.02 * smoothstep(0.12, 0.4, r))
			elif r < 0.75:
				mo = Vector3(0, -0.35 * (1.0 - smoothstep(0.45, 0.72, r)), 0.0)
		_mag.position = _mag_rest + mo
		_mag.visible = not (r >= 0.38 and r < 0.47)
	# Pump / bolt cycling
	if _pump:
		var pk := 0.0
		if _pump_t >= 0.0:
			pk = sin(PI * clampf((_pump_t - 0.15) / 0.7, 0.0, 1.0))
		_pump.position = _pump_rest + Vector3(0, 0, 0.09 * pk)
		rot.x += 0.05 * pk
	if _bolt:
		var bk := 0.0
		if _bolt_t >= 0.0:
			bk = sin(PI * clampf((_bolt_t - 0.15) / 0.75, 0.0, 1.0))
		_bolt.transform = _bolt_rest.translated_local(Vector3(0, 0, 0.09 * bk)) * Transform3D(Basis(Vector3.BACK, -1.2 * minf(1.0, bk * 2.0)), Vector3.ZERO)
		rot += Vector3(0.06 * bk, 0.0, -0.12 * bk)
	# Knife
	if _knife >= 0.0:
		var k := _knife
		if _knife_alt:
			var th := sin(PI * k)
			pos += Vector3(-0.08 * th, 0.03 * th, -0.18 * th)
			rot += Vector3(-0.35 * th, 0.25 * th, 0.4 * th)
		else:
			var sw := smoothstep(0.0, 1.0, k)
			var arc := sin(PI * k)
			pos += Vector3(0.06 - 0.24 * sw, 0.06 * arc, -0.08 * arc)
			rot += Vector3(0.1 * arc, 1.1 - 2.0 * sw, 0.6 * arc)
	# Throw
	if _throw >= 0.0:
		var k := _throw
		if k < 0.45:
			var a := smoothstep(0.0, 0.45, k)
			pos += Vector3(0.03 * a, 0.08 * a, 0.12 * a)
			rot += Vector3(0.9 * a, 0.0, 0.2 * a)
		else:
			var a := smoothstep(0.45, 0.8, k)
			pos += Vector3(0.03 - 0.1 * a, 0.08 - 0.12 * a, 0.12 - 0.42 * a)
			rot += Vector3(0.9 - 1.6 * a, 0.0, 0.2)
		if gun:
			gun.visible = k < 0.55
	elif gun:
		gun.visible = true
	# Sway (already reduced while aiming)
	rot.y += _sway.x
	rot.x += _sway.y
	pos.x += _sway.x * 0.15 * (1.0 - ads)
	# Slide / bolt carrier cycling
	if _slide:
		var sk := 0.0
		if _slide_t >= 0.0:
			sk = _slide_t / 0.3 if _slide_t < 0.3 else 1.0 - (_slide_t - 0.3) / 0.7
		_slide.position = _slide_rest + Vector3(0, 0, (0.026 if hold == "pistol" else 0.03) * sk)
	holder.transform = Transform3D(Basis.from_euler(rot), pos)
	_place_arms()


func _place_arms() -> void:
	if gun == null:
		return
	var gx := holder.transform
	# Right glove wraps the grip.
	var grip_xf := gx * Transform3D(Basis(Vector3.RIGHT, -0.28), Vector3(0, -0.035, 0.012))
	if hold == "knife":
		grip_xf = gx * Transform3D(Basis(Vector3.RIGHT, 1.35), Vector3(0, 0.0, 0.03))
	elif hold == "grenade":
		grip_xf = gx * Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0, -0.02, 0.03))
	elif hold == "bomb":
		grip_xf = gx * Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 0.0, 0.0))
	_glove_r.transform = grip_xf
	_glove_r.visible = gun.visible or hold != "grenade"
	# Left glove under the handguard / support grip.
	var lh := Vector3(0, -0.035, -0.25)
	var lm := gun.get_node_or_null("LeftHand") as Node3D
	if lm:
		lh = gun.transform * lm.position
	var left_xf := gx * Transform3D(Basis(Vector3.RIGHT, -0.15), lh + Vector3(0, -0.028, 0))
	var show_left := true
	if hold == "pistol":
		left_xf = gx * Transform3D(Basis(Vector3.FORWARD, 0.6) * Basis(Vector3.RIGHT, -0.28), Vector3(-0.03, -0.05, 0.01))
	elif hold in ["knife", "grenade"]:
		show_left = false
	elif hold == "bomb":
		left_xf = gx * Transform3D(Basis(Vector3.UP, -0.4), Vector3(-0.1, 0.0, 0.0))
	if _reload >= 0.0 and _mag and hold != "bomb":
		var r := _reload
		var mag_xf := gx * gun.transform * Transform3D(Basis.IDENTITY, _mag.position + Vector3(0, -0.08, 0.0))
		var w := smoothstep(0.05, 0.25, r) * (1.0 - smoothstep(0.78, 0.95, r))
		left_xf = left_xf.interpolate_with(mag_xf, w)
		if r > 0.4 and r < 0.47:
			left_xf.origin += Vector3(0, -0.15, 0.05)
	_glove_l.visible = show_left
	_glove_l.transform = left_xf
	# Sleeves run from fixed off-screen elbows to the wrists.
	_sleeve(_sleeve_r, Vector3(0.24, -0.34, 0.12), _glove_r.transform * Vector3(0, -0.04, 0.03), 1.0)
	_sleeve_l.visible = show_left
	if show_left:
		_sleeve(_sleeve_l, Vector3(-0.2, -0.36, 0.02), _glove_l.transform * Vector3(0, -0.04, 0.03), -1.0)


func _sleeve(mi: MeshInstance3D, elbow: Vector3, wrist: Vector3, side: float) -> void:
	var xf := VisUtil.seg_xf(elbow, wrist, Vector3(side, 0, 0))
	var len := elbow.distance_to(wrist)
	mi.transform = Transform3D(xf.basis * Basis.from_scale(Vector3(1, len / 0.3, 1)), xf.origin)


# --- Arm meshes --------------------------------------------------------------------
static func _arms_for(p_team: int) -> Dictionary:
	if _arm_meshes.has(p_team):
		return _arm_meshes[p_team]
	var atk := p_team == 0
	var fab := "fabric_atk" if atk else "fabric_def"
	var glove := Color(0.38, 0.31, 0.22) if atk else Color(0.07, 0.07, 0.075)
	var knuckle := Color(0.3, 0.25, 0.18) if atk else Color(0.12, 0.12, 0.12)
	var out := {}
	var fold := Color(0.7, 0.7, 0.7)
	for sk in ["", "_l"]:
		var b := VisUtil.Builder.new()
		# Sleeve hangs along -Y from the elbow: 0.3 m long (scaled to fit at runtime).
		b.capsule(fab, 0.05, 0.34, Vector3(0, -0.15, 0), Vector3.ZERO, Color.WHITE, Vector3(1, 1, 0.92))
		b.cyl(fab, 0.0515, 0.03, Vector3(0, -0.1, 0), Vector3.ZERO, fold, 0.05)
		b.cyl(fab, 0.053, 0.026, Vector3(0, -0.262, 0), Vector3.ZERO, fold, 0.052)
		b.cyl("rubber", 0.049, 0.05, Vector3(0, -0.297, 0), Vector3.ZERO, glove, 0.046)
		b.box("nylon", Vector3(0.03, 0.03, 0.006), Vector3(0, -0.297, -0.048), Vector3.ZERO, knuckle)
		if sk == "_l":
			b.cyl("metal", 0.05, 0.018, Vector3(0, -0.245, 0), Vector3.ZERO, Color(0.1, 0.1, 0.1))
			b.cyl("glass", 0.017, 0.007, Vector3(0, -0.245, -0.05), Vector3(90, 0, 0), Color(0.05, 0.06, 0.07))
		out["sleeve" + sk] = b.build()
		var g := VisUtil.Builder.new()
		var sx := -1.0 if sk == "_l" else 1.0
		# Hand wrapped around a grip running along local Y: rounded palm, finger wrap, knuckle pad, thumb.
		g.capsule("rubber", 0.028, 0.095, Vector3(0.0, 0.0, 0.004), Vector3.ZERO, glove, Vector3(0.95, 1, 1.25))
		g.capsule("rubber", 0.014, 0.084, Vector3(-sx * 0.006, -0.002, -0.04), Vector3.ZERO, glove, Vector3(1.9, 1, 1.0))
		for i in 4:
			g.box("rubber", Vector3(0.05, 0.0035, 0.03), Vector3(-sx * 0.006, 0.03 - i * 0.02, -0.04), Vector3.ZERO, glove.darkened(0.35))
		g.capsule("polymer", 0.011, 0.06, Vector3(-sx * 0.002, 0.004, -0.028), Vector3.ZERO, knuckle.darkened(0.2), Vector3(2.4, 1, 1.1))
		for i in 3:
			g.box("polymer", Vector3(0.055, 0.003, 0.004), Vector3(-sx * 0.002, 0.024 - i * 0.02, -0.039), Vector3.ZERO, Color(0.03, 0.03, 0.03))
		g.capsule("rubber", 0.012, 0.065, Vector3(sx * 0.03, 0.032, -0.022), Vector3(42, 0, 0), glove)
		g.cyl("rubber", 0.04, 0.045, Vector3(0, -0.062, 0.01), Vector3.ZERO, glove)
		out["glove" + sk] = g.build()
	_arm_meshes[p_team] = out
	return out
