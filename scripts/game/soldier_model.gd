class_name SoldierModel
extends Node3D
## Third-person operator: procedural gear meshes + procedural animation (two-bone IK for arms/legs).
## Origin at the feet, facing -Z. Soldier sets rotation.y = yaw every frame.

const HIP_Y := 0.95
const UARM := 0.3
const FARM := 0.3
const THIGH := 0.425
const SHIN := 0.41
const ANKLE_Y := 0.088

const F_ON_FLOOR := 1
const F_COVER := 8
const F_AIM := 16
const F_RELOAD := 32
const F_PLANT := 64
const F_DEFUSE := 128

static var _mesh_cache := {}

var team := 0
var hostile := false
var weapon_id := ""
var hold := "rifle"
var first_person := false

var body: Node3D
var hips: Node3D
var spine: Node3D
var head: Node3D
var gun_pivot: Node3D
var weapon: Node3D
var _seg := {}

var _phase := 0.0
var _t := 0.0
var _kick := 0.0
var _reload_t := -1.0
var _reload_dur := 1.0
var _throw_t := -1.0
var _knife_t := -1.0
var _dead := false
var _death_t := 0.0
var _fall_sign := 1.0
var _fall_side := 0.0
var _crouch := 0.0
var _speed_s := 0.0
var _lv := Vector3.ZERO
var _hit_t := -1.0
var _hit_dir := Vector3.ZERO


func setup(p_team: int, seed: int, p_hostile := false) -> void:
	team = p_team
	hostile = p_hostile
	for c in get_children():
		c.queue_free()
	_seg.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var v := _variant(rng)
	var meshes := _meshes_for(v)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	hips = Node3D.new()
	hips.name = "Hips"
	hips.position.y = HIP_Y
	body.add_child(hips)
	_mi(hips, "Pelvis", meshes["pelvis"])
	spine = Node3D.new()
	spine.name = "Spine"
	spine.position.y = 0.05
	hips.add_child(spine)
	_mi(spine, "Torso", meshes["torso"])
	head = Node3D.new()
	head.name = "Head"
	head.position.y = 0.57
	spine.add_child(head)
	_mi(head, "HeadMesh", meshes["head"])
	for k in ["uarm_l", "uarm_r", "farm_l", "farm_r", "thigh_l", "thigh_r", "shin_l", "shin_r", "foot_l", "foot_r"]:
		var key: String = k.substr(0, k.length() - 2) if not (k.begins_with("thigh") or k.begins_with("foot")) else k
		if k.begins_with("foot"):
			key = "foot"
		_seg[k] = _mi(body, k, meshes[key])
	gun_pivot = Node3D.new()
	gun_pivot.name = "GunPivot"
	body.add_child(gun_pivot)
	if weapon_id != "":
		var w := weapon_id
		weapon_id = ""
		set_weapon(w)
	_apply_shadow_mode()


func _mi(parent: Node3D, name: String, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	parent.add_child(mi)
	return mi


func set_weapon(id: String) -> void:
	if id == weapon_id and weapon != null:
		return
	weapon_id = id
	if gun_pivot == null:
		return
	if weapon != null:
		weapon.queue_free()
		weapon = null
	if id == "":
		return
	weapon = WeaponModels.build(id)
	hold = String(weapon.get_meta("hold", "rifle"))
	gun_pivot.add_child(weapon)
	_apply_shadow_mode()


func set_first_person(v: bool) -> void:
	first_person = v
	_apply_shadow_mode()


func _apply_shadow_mode() -> void:
	var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if first_person else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_set_shadow(self, mode)


func _set_shadow(n: Node, mode: int) -> void:
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = mode
		_set_shadow(c, mode)


func play_fire() -> void:
	_kick = 1.0


func play_reload(duration: float) -> void:
	_reload_t = 0.0
	_reload_dur = maxf(0.2, duration)


func play_throw() -> void:
	_throw_t = 0.0


func play_knife() -> void:
	_knife_t = 0.0


## Short upper-body flinch; `dir` is the direction the bullet/blast was travelling.
func play_hit(dir: Vector3) -> void:
	if _dead or body == null:
		return
	var ld := global_transform.basis.inverse() * dir
	ld.y = 0.0
	_hit_dir = ld.normalized() if ld.length() > 0.001 else Vector3(0, 0, 1)
	_hit_t = 0.0


func die(dir: Vector3) -> void:
	if _dead:
		return
	_dead = true
	_death_t = 0.0
	var ld := global_transform.basis.inverse() * dir
	_fall_sign = -1.0 if ld.z < 0.0 else 1.0
	_fall_side = clampf(ld.x, -1.0, 1.0) * 0.35
	if weapon:
		weapon.visible = false


func reset() -> void:
	_dead = false
	_death_t = 0.0
	_reload_t = -1.0
	_throw_t = -1.0
	_knife_t = -1.0
	if body:
		body.rotation = Vector3.ZERO
		body.position = Vector3.ZERO
	if weapon:
		weapon.visible = true


func muzzle_global() -> Vector3:
	if weapon:
		var m := weapon.get_node_or_null("Muzzle") as Node3D
		if m:
			return m.global_position
	return global_position + Vector3(0, 1.4, 0)


func head_global() -> Vector3:
	if head:
		return head.global_position + head.global_transform.basis.y * 0.05
	return global_position + Vector3(0, 1.62, 0)


# --- Animation -----------------------------------------------------------------------
func update_anim(delta: float, s: Soldier) -> void:
	if body == null:
		return
	_t += delta
	_kick = move_toward(_kick, 0.0, delta * 9.0)
	if _reload_t >= 0.0:
		_reload_t += delta / _reload_dur
		if _reload_t >= 1.0:
			_reload_t = -1.0
	if _throw_t >= 0.0:
		_throw_t += delta / 0.5
		if _throw_t >= 1.0:
			_throw_t = -1.0
	if _knife_t >= 0.0:
		_knife_t += delta / 0.38
		if _knife_t >= 1.0:
			_knife_t = -1.0
	if _hit_t >= 0.0:
		_hit_t += delta / 0.28
		if _hit_t >= 1.0:
			_hit_t = -1.0
	if not s.alive and not _dead:
		die(Vector3(0, 0, 1).rotated(Vector3.UP, rotation.y))
	if s.alive and _dead:
		reset()
	if _dead:
		_death_t += delta
		_pose(0.3, 0.0, 0.0, false, false, true)
		var f := clampf(_death_t / 0.6, 0.0, 1.0)
		f = f * f
		var bounce := sin(clampf((_death_t - 0.6) / 0.25, 0.0, 1.0) * PI) * 0.06
		body.rotation = Vector3(_fall_sign * (1.48 * f - bounce), 0.0, _fall_side * f)
		body.position = Vector3(0, 0.13 * f, 0)
		return
	var hv := Vector3(s.velocity.x, 0, s.velocity.z)
	var speed := hv.length()
	_speed_s = lerpf(_speed_s, speed, clampf(delta * 10.0, 0.0, 1.0))
	_lv = global_transform.basis.inverse() * hv
	_crouch = s.crouch_amount
	var on_floor := (s.flags & F_ON_FLOOR) != 0 or s.is_on_floor()
	var amp := clampf(_speed_s / 5.5, 0.0, 1.0)
	if _speed_s > 0.15:
		_phase += delta * (2.0 + _speed_s * 1.7)
	var cover := (s.flags & F_COVER) != 0
	var aiming := (s.flags & F_AIM) != 0
	_pose(_crouch, amp, s.pitch, cover and not aiming, not on_floor, false, (s.flags & (F_PLANT | F_DEFUSE)) != 0)


func _pose(c: float, amp: float, pitch: float, low_ready: bool, airborne: bool, dead: bool, kneel_task := false) -> void:
	var breathe := sin(_t * 1.7) * 0.012
	var hip_y := lerpf(HIP_Y, 0.5, c) - absf(sin(_phase)) * 0.035 * amp
	if kneel_task:
		hip_y = minf(hip_y, 0.55)
	hips.position = Vector3(0, hip_y, 0)
	hips.rotation = Vector3(0, -sin(_phase) * 0.1 * amp, 0)
	var rifle := hold == "rifle"
	var twist := -0.3 if rifle else 0.0
	var lean := -0.34 * c - 0.1 * amp + breathe
	if low_ready:
		lean += 0.08
	var aim := clampf(pitch, -1.2, 1.2)
	var spine_pitch := lean + aim * 0.3
	var flinch := Vector3.ZERO
	if _hit_t >= 0.0 and not dead:
		# fast snap, slower settle
		var k := sin(PI * pow(_hit_t, 0.6))
		flinch = Vector3(_hit_dir.z * 0.32, _hit_dir.x * 0.12, -_hit_dir.x * 0.26) * k
	spine.rotation = Vector3(spine_pitch, twist + sin(_phase) * 0.12 * amp, 0) + flinch
	head.rotation = Vector3(aim * 0.85 - spine_pitch, -twist * 0.8, 0) + flinch * 0.6
	# Legs
	var hips_xf := hips.transform
	var md := Vector2(_lv.x, _lv.z)
	md = md.normalized() if md.length() > 0.1 else Vector2(0, -1)
	for side in [-1.0, 1.0]:
		var ph: float = _phase + (PI if side > 0.0 else 0.0)
		var hip: Vector3 = hips_xf * Vector3(side * 0.1, -0.05, 0)
		var swing := sin(ph) * 0.3 * amp
		var lift := maxf(0.0, cos(ph)) * 0.14 * amp
		var stance := Vector3(side * 0.12, ANKLE_Y, 0.0)
		stance.z += (0.2 if side > 0.0 else -0.12) * c
		if kneel_task and side > 0.0:
			stance.z += 0.1
		var foot := stance + Vector3(md.x, 0, md.y) * swing + Vector3(0, lift, 0)
		if airborne:
			foot += Vector3(0, 0.22, 0.06 * side)
		var knee := VisUtil.ik_joint(hip, foot, THIGH, SHIN, Vector3(side * 0.1, 0.0, -1.0))
		var sk := "_l" if side < 0.0 else "_r"
		(_seg["thigh" + sk] as Node3D).transform = VisUtil.seg_xf(hip, knee, Vector3.RIGHT)
		(_seg["shin" + sk] as Node3D).transform = VisUtil.seg_xf(knee, foot, Vector3.RIGHT)
		var toe := -swing * 0.6 if lift > 0.01 else 0.0
		(_seg["foot" + sk] as Node3D).transform = Transform3D(Basis(Vector3.RIGHT, toe), foot)
	# Weapon & arms
	var spine_xf := hips_xf * spine.transform
	var sh_r: Vector3 = spine_xf * Vector3(0.2, 0.44, 0.0)
	var sh_l: Vector3 = spine_xf * Vector3(-0.2, 0.44, 0.0)
	var piv: Vector3 = spine_xf * Vector3(0.11, 0.42, -0.02)
	if rifle:
		piv = sh_r + Vector3(-0.08, -0.02, -0.02)
	var gun_aim := aim - (0.75 if low_ready else 0.0)
	var off := Vector3(0.02, -0.08, -0.18)
	match hold:
		"pistol":
			off = Vector3(-0.1, -0.03, -0.42)
		"knife":
			off = Vector3(0.04, -0.24, -0.26)
			gun_aim = aim * 0.5 - 0.2
		"grenade":
			off = Vector3(0.04, -0.12, -0.22)
			gun_aim = aim * 0.5
		"bomb":
			off = Vector3(-0.11, -0.3, -0.3)
			gun_aim = -0.25
	if dead:
		gun_aim = -0.9
	var gb := Basis(Vector3.RIGHT, gun_aim)
	var kick := Vector3(0, 0.01, 0.05) * _kick
	var roll := 0.0
	if _reload_t >= 0.0:
		roll = sin(PI * _reload_t) * 0.45
		gb = gb * Basis(Vector3.RIGHT, -sin(PI * _reload_t) * 0.25)
	gb = gb * Basis(Vector3.BACK, roll)
	var grip := piv + Basis(Vector3.RIGHT, gun_aim) * off + gb * kick
	if _throw_t >= 0.0 and hold == "grenade":
		var k := _throw_t
		var back := sh_r + Vector3(0.05, 0.22, 0.18)
		var fwd := sh_r + Vector3(-0.05, 0.1, -0.45)
		grip = grip.lerp(back, clampf(k / 0.45, 0.0, 1.0)) if k < 0.45 else back.lerp(fwd, clampf((k - 0.45) / 0.3, 0.0, 1.0))
	if _knife_t >= 0.0 and hold == "knife":
		var k := sin(_knife_t * PI)
		grip += Vector3(-0.3 * _knife_t + 0.1, 0.12 * k, -0.18 * k)
		gb = gb * Basis(Vector3.UP, 0.9 * k)
	gun_pivot.transform = Transform3D(gb, grip)
	var lh := grip + gb * Vector3(0, -0.03, -0.25)
	if weapon:
		var m := weapon.get_node_or_null("LeftHand") as Node3D
		if m:
			lh = gun_pivot.transform * m.position
	if hold in ["knife", "grenade"] or dead:
		lh = spine_xf * Vector3(-0.24, 0.05, -0.1)
	if _reload_t >= 0.0 and weapon:
		var mag := weapon.get_node_or_null("Mag") as Node3D
		var mp := gun_pivot.transform * (mag.position if mag else Vector3(0, -0.05, -0.1))
		var pouch := spine_xf * Vector3(-0.08, 0.2, -0.2)
		var r := _reload_t
		if r < 0.25:
			lh = lh.lerp(mp, r / 0.25)
		elif r < 0.5:
			lh = mp.lerp(pouch, (r - 0.25) / 0.25)
		elif r < 0.75:
			lh = pouch.lerp(mp, (r - 0.5) / 0.25)
		else:
			lh = mp.lerp(lh, (r - 0.75) / 0.25)
	_arm("_r", sh_r, grip, 1.0)
	_arm("_l", sh_l, lh, -1.0)


func _arm(sk: String, sh: Vector3, target: Vector3, side: float) -> void:
	var elbow := VisUtil.ik_joint(sh, target, UARM, FARM, Vector3(side * 0.8, -1.0, 0.3))
	(_seg["uarm" + sk] as Node3D).transform = VisUtil.seg_xf(sh, elbow, Vector3(side, 0, 0))
	(_seg["farm" + sk] as Node3D).transform = VisUtil.seg_xf(elbow, target, Vector3(side, 0, 0))


# --- Meshes ------------------------------------------------------------------------
const SKIN_TONES := [Color(0.8, 0.62, 0.5), Color(0.66, 0.47, 0.35), Color(0.47, 0.32, 0.23), Color(0.88, 0.72, 0.6)]


func _variant(rng: RandomNumberGenerator) -> Dictionary:
	var v := {"team": team, "hostile": hostile, "skin": rng.randi_range(0, SKIN_TONES.size() - 1)}
	if team == 1 and not hostile:
		v["vest"] = rng.randi_range(0, 2)
		v["helmet"] = 1
		v["pack"] = 1 if rng.randf() < 0.5 else 0
		v["wrap"] = 0
		v["face"] = 1 if rng.randf() < 0.6 else 0
	else:
		v["vest"] = rng.randi_range(0, 2)
		v["helmet"] = 1 if rng.randf() < (0.3 if hostile else 0.6) else 0
		v["pack"] = 1 if rng.randf() < 0.4 else 0
		v["wrap"] = rng.randi_range(0, 3) if hostile else rng.randi_range(0, 1)
		v["face"] = 0
	return v


func _meshes_for(v: Dictionary) -> Dictionary:
	var key := "%d_%s_%d_%d_%d_%d_%d_%d" % [v["team"], str(v["hostile"]), v["vest"], v["helmet"], v["pack"], v["wrap"], v["face"], v["skin"]]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var atk: bool = v["team"] == 0 or v["hostile"]
	var fab := "fabric_hostile" if v["hostile"] else ("fabric_atk" if v["team"] == 0 else "fabric_def")
	var vest_cols := [Color(0.5, 0.41, 0.28), Color(0.3, 0.32, 0.24), Color(0.6, 0.53, 0.39)] if atk else [Color(0.07, 0.07, 0.075), Color(0.15, 0.155, 0.16), Color(0.09, 0.105, 0.15)]
	var g: Color = vest_cols[v["vest"]]
	var wraps := [Color(0.36, 0.08, 0.07), Color(0.27, 0.07, 0.06), Color(0.12, 0.12, 0.12), Color(0.55, 0.5, 0.38)]
	var wrap: Color = wraps[v["wrap"]]
	var skin: Color = SKIN_TONES[v["skin"]]
	var boot := Color(0.44, 0.35, 0.24) if atk else Color(0.08, 0.08, 0.08)
	var glove := Color(0.38, 0.31, 0.22) if atk else Color(0.06, 0.06, 0.06)
	var pad := g.darkened(0.35) if atk else Color(0.1, 0.1, 0.1)
	var helm := Color(0.58, 0.5, 0.37) if atk else Color(0.12, 0.125, 0.13)
	var patch := Color(0.85, 0.18, 0.1) if v["team"] == 0 else Color(0.2, 0.42, 0.95)
	if v["hostile"]:
		patch = Color(0.2, 0.2, 0.2)
	var W := Color.WHITE
	var FOLD := Color(0.72, 0.72, 0.72)
	var BLK := Color(0.06, 0.06, 0.065)
	var LENS := Color(0.04, 0.045, 0.05)
	var out := {}
	# Pelvis (origin at hip height)
	var b := VisUtil.Builder.new()
	b.cyl(fab, 0.145, 0.17, Vector3(0, -0.01, 0), Vector3.ZERO, W, 0.14, 18, Vector3(1, 1, 0.72))
	b.sphere(fab, 0.145, Vector3(0, -0.09, 0), W, Vector3(1.0, 0.55, 0.72))
	b.cyl("nylon", 0.152, 0.045, Vector3(0, 0.06, 0), Vector3.ZERO, g.darkened(0.25), 0.152, 18, Vector3(1, 1, 0.75))
	b.box("metal", Vector3(0.05, 0.036, 0.012), Vector3(0, 0.06, -0.115), Vector3.ZERO, Color(0.22, 0.22, 0.22))
	b.box("nylon", Vector3(0.1, 0.1, 0.06), Vector3(-0.14, -0.02, 0.09), Vector3.ZERO, g)
	b.cyl("nylon", 0.05, 0.03, Vector3(-0.14, 0.035, 0.09), Vector3(90, 0, 0), g.darkened(0.15), 0.05, 10, Vector3(1.0, 1, 0.6))
	out["pelvis"] = b.build()
	# Torso (origin at waist): tapered body, rounded shoulders, plate carrier
	b = VisUtil.Builder.new()
	b.cyl(fab, 0.13, 0.44, Vector3(0, 0.22, 0), Vector3.ZERO, W, 0.172, 20, Vector3(1, 1, 0.66))
	b.sphere(fab, 0.17, Vector3(0, 0.42, 0), W, Vector3(1.08, 0.42, 0.68))
	for sx in [-1.0, 1.0]:
		b.sphere(fab, 0.068, Vector3(sx * 0.195, 0.435, 0), W)
	b.cyl(fab, 0.06, 0.06, Vector3(0, 0.5, 0.005), Vector3.ZERO, W)
	b.torus(fab, 0.055, 0.082, Vector3(0, 0.49, 0.005), Vector3.ZERO, FOLD)
	# carrier
	b.box("nylon", Vector3(0.31, 0.27, 0.05), Vector3(0, 0.3, -0.128), Vector3(4, 0, 0), g)
	b.capsule("nylon", 0.025, 0.31, Vector3(0, 0.432, -0.12), Vector3(0, 0, 90), g)
	b.box("nylon", Vector3(0.32, 0.29, 0.055), Vector3(0, 0.31, 0.125), Vector3.ZERO, g)
	b.capsule("nylon", 0.027, 0.32, Vector3(0, 0.452, 0.124), Vector3(0, 0, 90), g)
	b.cyl("nylon", 0.172, 0.12, Vector3(0, 0.17, 0), Vector3.ZERO, g.darkened(0.08), 0.174, 20, Vector3(1, 1, 0.74))
	for i in 4:
		b.box("nylon", Vector3(0.006, 0.1, 0.02), Vector3(-0.17 + i * 0.008 * 0.0, 0.17, -0.06 + i * 0.04), Vector3(0, 0, 0), g.darkened(0.2))
	for sx in [-1.0, 1.0]:
		b.capsule("nylon", 0.02, 0.27, Vector3(sx * 0.11, 0.465, 0), Vector3(90, 0, 0), g, Vector3(1.7, 1, 0.8))
	for i in 3:
		var x := -0.08 + i * 0.08
		b.box("nylon", Vector3(0.068, 0.105, 0.048), Vector3(x, 0.2, -0.172), Vector3.ZERO, g.darkened(0.06))
		b.capsule("nylon", 0.012, 0.07, Vector3(x, 0.253, -0.172), Vector3(0, 0, 90), g.darkened(0.15), Vector3(1, 1, 2.0))
		b.box("polymer", Vector3(0.026, 0.02, 0.044), Vector3(x, 0.266, -0.172), Vector3.ZERO, BLK)
	b.box("nylon", Vector3(0.16, 0.07, 0.035), Vector3(0, 0.345, -0.168), Vector3.ZERO, g)
	b.box("nylon", Vector3(0.06, 0.035, 0.006), Vector3(0.085, 0.395, -0.155), Vector3.ZERO, patch)
	b.box("polymer", Vector3(0.065, 0.14, 0.045), Vector3(-0.13, 0.29, 0.172), Vector3.ZERO, BLK)
	b.cyl("polymer", 0.012, 0.03, Vector3(-0.12, 0.375, 0.172), Vector3.ZERO, BLK)
	b.cyl("rubber", 0.004, 0.36, Vector3(-0.15, 0.53, 0.18), Vector3(0, 0, -8), BLK)
	b.sphere("emit_green", 0.005, Vector3(-0.11, 0.34, 0.196), W)
	b.cyl("polymer", 0.03, 0.075, Vector3(0.17, 0.16, -0.08), Vector3.ZERO, Color(0.28, 0.3, 0.22))
	b.sphere("polymer", 0.03, Vector3(0.17, 0.2, -0.08), Color(0.28, 0.3, 0.22), Vector3(1, 0.6, 1))
	if v["pack"] == 1:
		b.box("nylon", Vector3(0.26, 0.32, 0.1), Vector3(0, 0.3, 0.205), Vector3.ZERO, g.darkened(0.1))
		b.capsule("nylon", 0.05, 0.26, Vector3(0, 0.46, 0.205), Vector3(0, 0, 90), g.darkened(0.1), Vector3(1, 1, 1.0))
		b.box("nylon", Vector3(0.2, 0.1, 0.04), Vector3(0, 0.22, 0.27), Vector3.ZERO, g)
	else:
		b.box("nylon", Vector3(0.2, 0.26, 0.05), Vector3(0, 0.32, 0.17), Vector3.ZERO, g.darkened(0.12))
		b.cyl("rubber", 0.006, 0.2, Vector3(0.08, 0.46, 0.15), Vector3(60, 0, 0), BLK)
	out["torso"] = b.build()
	# Head (origin at neck top; skull centre 5 cm above)
	b = VisUtil.Builder.new()
	var hood: Color = wrap if atk else Color(0.07, 0.07, 0.075)
	var visible_face: bool = v["face"] == 1
	var head_col: Color = skin if visible_face else hood
	var head_key := "skin" if visible_face else "nylon"
	b.sphere(head_key, 0.098, Vector3(0, 0.055, 0.008), head_col, Vector3(0.88, 1.08, 1.0))
	b.sphere(head_key, 0.07, Vector3(0, 0.0, -0.028), head_col, Vector3(0.95, 0.85, 0.95))
	b.cyl(head_key, 0.052, 0.09, Vector3(0, -0.04, 0.008), Vector3.ZERO, head_col)
	if visible_face:
		b.sphere("skin", 0.022, Vector3(0, 0.045, -0.093), skin.darkened(0.05), Vector3(0.7, 1.1, 1.0))
		b.box("skin", Vector3(0.05, 0.008, 0.01), Vector3(0, -0.005, -0.086), Vector3.ZERO, skin.darkened(0.3))
		b.sphere("skin", 0.02, Vector3(0.087, 0.055, 0.008), skin, Vector3(0.5, 1.0, 0.8))
		b.sphere("skin", 0.02, Vector3(-0.087, 0.055, 0.008), skin, Vector3(0.5, 1.0, 0.8))
		# ballistic glasses
		b.box("glass", Vector3(0.14, 0.032, 0.008), Vector3(0, 0.072, -0.092), Vector3.ZERO, LENS)
		b.box("polymer", Vector3(0.006, 0.008, 0.1), Vector3(0.072, 0.075, -0.045), Vector3.ZERO, BLK)
		b.box("polymer", Vector3(0.006, 0.008, 0.1), Vector3(-0.072, 0.075, -0.045), Vector3.ZERO, BLK)
		# neck gaiter
		b.cyl("nylon", 0.06, 0.06, Vector3(0, -0.045, 0.008), Vector3.ZERO, Color(0.1, 0.1, 0.11), 0.056)
	else:
		# eye opening (skin) + goggles
		b.sphere("skin", 0.064, Vector3(0, 0.07, -0.05), skin, Vector3(1.25, 0.34, 0.75))
		b.capsule("rubber", 0.026, 0.17, Vector3(0, 0.072, -0.08), Vector3(0, 0, 90), BLK, Vector3(1, 1, 0.8))
		b.capsule("glass", 0.019, 0.15, Vector3(0, 0.072, -0.098), Vector3(0, 0, 90), LENS, Vector3(1, 1, 0.5))
		b.torus("rubber", 0.096, 0.104, Vector3(0, 0.074, 0.008), Vector3.ZERO, BLK)
		if atk:
			# shemagh folds over the lower face
			b.sphere("nylon", 0.072, Vector3(0, 0.004, -0.03), wrap.darkened(0.1), Vector3(1.0, 0.62, 0.95))
			b.torus("nylon", 0.058, 0.074, Vector3(0, -0.04, 0.004), Vector3(8, 0, 0), wrap.darkened(0.2))
	if v["helmet"] == 1:
		b.sphere("polymer", 0.128, Vector3(0, 0.075, 0.006), helm, Vector3(1.0, 0.95, 1.08), Vector3.ZERO, true, 24)
		b.cyl("polymer", 0.129, 0.014, Vector3(0, 0.076, 0.006), Vector3.ZERO, helm.darkened(0.25), 0.131, 24, Vector3(1, 1, 1.08))
		b.cyl("nylon", 0.13, 0.03, Vector3(0, 0.11, 0.006), Vector3.ZERO, helm.darkened(0.1), 0.122, 24, Vector3(1, 1, 1.08))
		for sx in [-1.0, 1.0]:
			b.box("polymer", Vector3(0.012, 0.024, 0.12), Vector3(sx * 0.126, 0.1, 0.0), Vector3.ZERO, helm.darkened(0.35))
			b.cyl("polymer", 0.042, 0.032, Vector3(sx * 0.103, 0.045, 0.004), Vector3(0, 0, 90), BLK)
			b.capsule("polymer", 0.009, 0.1, Vector3(sx * 0.1, 0.1, 0.004), Vector3(0, 0, sx * 25.0), BLK)
		b.box("metal", Vector3(0.042, 0.036, 0.02), Vector3(0, 0.16, -0.122), Vector3(-25, 0, 0), BLK)
		b.box("polymer", Vector3(0.03, 0.02, 0.05), Vector3(0, 0.185, 0.07), Vector3(20, 0, 0), BLK)
	else:
		b.sphere("nylon", 0.112, Vector3(0, 0.085, 0.004), wrap, Vector3(1.0, 0.85, 1.05))
		b.torus("nylon", 0.095, 0.115, Vector3(0, 0.095, 0.004), Vector3(-6, 0, 0), wrap.darkened(0.15))
		b.capsule("nylon", 0.03, 0.14, Vector3(0.035, -0.0, 0.1), Vector3(12, 0, 0), wrap.darkened(0.1), Vector3(1.4, 1, 0.6))
	out["head"] = b.build()
	# Upper arm: shoulder joint, sleeve, darker fold at the elbow
	b = VisUtil.Builder.new()
	b.sphere(fab, 0.062, Vector3(0, 0.0, 0), W)
	b.capsule(fab, 0.058, 0.32, Vector3(0, -0.15, 0), Vector3.ZERO, W, Vector3(1, 1, 0.95))
	b.cyl(fab, 0.059, 0.035, Vector3(0, -0.265, 0), Vector3.ZERO, FOLD, 0.056)
	for sx in [-1.0, 1.0]:
		b.box("nylon", Vector3(0.006, 0.055, 0.065), Vector3(sx * 0.058, -0.08, 0), Vector3.ZERO, patch)
	out["uarm"] = b.build()
	# Forearm: elbow joint, rolled sleeve band, glove cuff, hand with knuckle pad
	b = VisUtil.Builder.new()
	b.sphere(fab, 0.054, Vector3(0, 0.0, 0), W)
	b.capsule(fab, 0.05, 0.26, Vector3(0, -0.115, 0), Vector3.ZERO, W, Vector3(1, 1, 0.92))
	b.cyl(fab, 0.051, 0.03, Vector3(0, -0.205, 0), Vector3.ZERO, FOLD, 0.049)
	b.cyl("rubber", 0.047, 0.045, Vector3(0, -0.24, 0), Vector3.ZERO, glove, 0.044)
	b.capsule("rubber", 0.033, 0.11, Vector3(0, -0.3, 0), Vector3.ZERO, glove, Vector3(1.15, 1, 0.75))
	b.box("polymer", Vector3(0.055, 0.025, 0.016), Vector3(0, -0.31, -0.026), Vector3.ZERO, glove.darkened(0.3))
	b.capsule("rubber", 0.012, 0.06, Vector3(0.035, -0.285, -0.015), Vector3(0, 0, 22), glove)
	out["farm"] = b.build()
	# Legs
	for sk in ["_l", "_r"]:
		b = VisUtil.Builder.new()
		b.sphere(fab, 0.084, Vector3(0, 0.0, 0), W)
		b.capsule(fab, 0.082, 0.47, Vector3(0, -0.215, 0), Vector3.ZERO, Color(0.95, 0.95, 0.95), Vector3(1, 1, 0.95))
		b.cyl(fab, 0.078, 0.035, Vector3(0, -0.38, 0), Vector3.ZERO, FOLD, 0.072)
		if sk == "_r":
			b.box("nylon", Vector3(0.045, 0.16, 0.1), Vector3(0.09, -0.16, 0), Vector3.ZERO, g)
			b.capsule("polymer", 0.016, 0.12, Vector3(0.115, -0.14, -0.01), Vector3.ZERO, BLK, Vector3(1, 1, 1.6))
			b.cyl("nylon", 0.084, 0.03, Vector3(0, -0.12, 0), Vector3.ZERO, g.darkened(0.2))
		else:
			b.box(fab, Vector3(0.03, 0.12, 0.1), Vector3(-0.083, -0.22, 0), Vector3.ZERO, Color(0.88, 0.88, 0.88))
			b.box(fab, Vector3(0.032, 0.03, 0.102), Vector3(-0.084, -0.16, 0), Vector3.ZERO, FOLD)
		out["thigh" + sk] = b.build()
		b = VisUtil.Builder.new()
		b.sphere(fab, 0.068, Vector3(0, 0.0, 0), W)
		b.capsule(fab, 0.062, 0.42, Vector3(0, -0.19, 0), Vector3.ZERO, Color(0.95, 0.95, 0.95), Vector3(1, 1, 0.95))
		b.sphere("polymer", 0.058, Vector3(0, -0.02, -0.052), pad, Vector3(1.05, 1.2, 0.55))
		b.cyl("rubber", 0.066, 0.02, Vector3(0, -0.05, 0), Vector3.ZERO, BLK)
		b.cyl("rubber", 0.07, 0.15, Vector3(0, -0.36, 0), Vector3.ZERO, boot, 0.066)
		b.cyl("rubber", 0.072, 0.015, Vector3(0, -0.29, 0), Vector3.ZERO, boot.darkened(0.3))
		out["shin" + sk] = b.build()
	out["shin"] = out["shin_l"]
	b = VisUtil.Builder.new()
	b.capsule("rubber", 0.056, 0.27, Vector3(0, -0.035, -0.05), Vector3(90, 0, 0), boot, Vector3(1, 1, 0.85))
	b.box("rubber", Vector3(0.112, 0.022, 0.27), Vector3(0, -0.077, -0.05), Vector3.ZERO, Color(0.1, 0.09, 0.08))
	b.box("rubber", Vector3(0.06, 0.012, 0.1), Vector3(0, 0.015, -0.09), Vector3(-14, 0, 0), boot.darkened(0.35))
	out["foot"] = b.build()
	_mesh_cache[key] = out
	return out
