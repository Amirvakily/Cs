class_name WeaponModels
extends RefCounted
## Weapon visuals. build(id) returns a fresh Node3D (shared meshes) with:
##   barrel along -Z, origin at the pistol grip, Marker3D "Muzzle", "LeftHand", "Sight",
##   Node3D "Mag" (moved during reloads) and optional "Pump" / "Bolt".
## Meta on the root: "hold" (rifle/pistol/knife/grenade/bomb), "sight_y" (sight line height above grip).

static var _templates := {}

const GM := Color(0.16, 0.16, 0.17)
const GM2 := Color(0.11, 0.11, 0.115)
const BLK := Color(0.075, 0.075, 0.08)
const DGRY := Color(0.22, 0.22, 0.23)
const TAN := Color(0.66, 0.57, 0.42)
const OD := Color(0.31, 0.33, 0.24)
const WOOD := Color(0.48, 0.27, 0.14)
const WOOD2 := Color(0.38, 0.2, 0.1)
const STEEL := Color(0.7, 0.7, 0.72)
const BRASS := Color(0.85, 0.66, 0.32)
const RED := Color(0.55, 0.08, 0.06)


static func build(id: String) -> Node3D:
	if not _templates.has(id):
		# Templates are kept as PackedScenes (meshes shared between instances, no orphan nodes).
		var root := _make(id)
		_own(root, root)
		var ps := PackedScene.new()
		ps.pack(root)
		root.free()
		_templates[id] = ps
	return (_templates[id] as PackedScene).instantiate() as Node3D


static func _own(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own(c, owner)


static func hold_of(id: String) -> String:
	var cls: String = Cfg.w(id).get("cls", "rifle")
	match cls:
		"pistol":
			return "pistol"
		"knife":
			return "knife"
		"grenade":
			return "grenade"
		"bomb", "breach":
			return "bomb"
	return "rifle"


# ---------------------------------------------------------------------------
static func _make(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_" + id
	var b := VisUtil.Builder.new()
	var mb := VisUtil.Builder.new()
	var extra := {} # name -> [Builder, position]
	var mk := {"muzzle": Vector3(0, 0.06, -0.5), "left": Vector3(0, 0.02, -0.3), "mag": Vector3(0, 0, -0.1), "sight_y": 0.1, "sight_z": -0.1}
	match id:
		"m9":
			return _polyhaven_pistol(root)
		"longbow":
			return _polyhaven_rifle(root)
		"kv74":
			_kv74(b, mb, mk)
		"ar7":
			_ar7(b, mb, mk)
		"hornet":
			_hornet(b, mb, mk)
		"vespa":
			_vespa(b, mb, mk)
		"mako":
			_mako(b, mb, mk)
		"raptor":
			_raptor(b, mb, mk)
		"hawk":
			_hawk(b, mb, mk)
		"breacher":
			_breacher(b, mb, mk, extra)
		"sentry":
			_sentry(b, mb, mk)
		"thresher":
			_thresher(b, mb, mk)
		"knife":
			_knife(b, mk)
		"frag", "flash", "smoke":
			_grenade(b, mk, id)
		"bomb":
			_bomb(b, mk)
		"breach":
			_breach(b, mk)
		_:
			_ar7(b, mb, mk)
	_add_mesh(root, "Body", b)
	var mag := Node3D.new()
	mag.name = "Mag"
	mag.position = mk["mag"]
	root.add_child(mag)
	if not mb.is_empty():
		_add_mesh(mag, "MagMesh", mb)
	for k in extra:
		var node := Node3D.new()
		node.name = k
		node.position = extra[k][1]
		root.add_child(node)
		_add_mesh(node, k + "Mesh", extra[k][0])
	_marker(root, "Muzzle", mk["muzzle"])
	_marker(root, "LeftHand", mk["left"])
	_marker(root, "Sight", Vector3(0, mk["sight_y"], mk["sight_z"]))
	root.set_meta("hold", hold_of(id))
	root.set_meta("sight_y", mk["sight_y"])
	return root


static func _add_mesh(parent: Node3D, name: String, b: VisUtil.Builder) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = b.build()
	parent.add_child(mi)


static func _marker(parent: Node3D, name: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	parent.add_child(m)


static func _trigger_group(b: VisUtil.Builder, z := 0.0, col := GM2) -> void:
	b.box("parker", Vector3(0.011, 0.006, 0.07), Vector3(0, -0.019, z - 0.036), Vector3.ZERO, col)
	b.cyl("parker", 0.006, 0.034, Vector3(0, -0.004, z - 0.072), Vector3.ZERO, col, -1.0, 8)
	b.capsule("steel", 0.003, 0.026, Vector3(0, 0.0, z - 0.04), Vector3(14, 0, 0), STEEL.darkened(0.3))


## Rounded pistol grip with finger grooves (grip top at `pos`, tilted back by `tilt` degrees).
static func _grip(b: VisUtil.Builder, pos: Vector3, tilt: float, col: Color, len := 0.11) -> void:
	var dir := Basis(Vector3.RIGHT, deg_to_rad(-tilt)) * Vector3.DOWN
	var c := pos + dir * (len * 0.5)
	b.capsule("polymer", 0.019, len, c, Vector3(-tilt, 0, 0), col, Vector3(0.8, 1, 1.2))
	for i in 3:
		var gp := pos + dir * (0.03 + i * 0.024) + Basis(Vector3.RIGHT, deg_to_rad(-tilt)) * Vector3(0, 0, -0.021)
		b.box("polymer", Vector3(0.031, 0.006, 0.006), gp, Vector3(-tilt, 0, 0), col.darkened(0.35))
	b.box("polymer", Vector3(0.029, 0.01, 0.046), pos + dir * len, Vector3(-tilt, 0, 0), col.darkened(0.2))


## Slotted flash hider along -Z, centred at `pos`.
static func _flash_hider(b: VisUtil.Builder, pos: Vector3, r: float, len: float, col := BLK) -> void:
	b.cyl("parker", r, len, pos, Vector3(90, 0, 0), col, -1.0, 12)
	b.cyl("polymer", r * 0.6, 0.004, pos + Vector3(0, 0, -len * 0.5 - 0.001), Vector3(90, 0, 0), Color(0.01, 0.01, 0.01), -1.0, 10)
	for i in 4:
		var a := TAU * (i + 0.5) / 4.0
		b.box("polymer", Vector3(0.003, 0.003, len * 0.55), pos + Vector3(sin(a) * r, cos(a) * r, -len * 0.2), Vector3(0, 0, -rad_to_deg(a)), Color(0.02, 0.02, 0.02))


## Ejection port on the right side of a receiver.
static func _eject_port(b: VisUtil.Builder, x: float, y: float, z: float, len := 0.06) -> void:
	b.box("polymer", Vector3(0.004, 0.018, len), Vector3(x, y, z), Vector3.ZERO, Color(0.02, 0.02, 0.02))
	b.box("steel", Vector3(0.002, 0.012, len * 0.7), Vector3(x - 0.002, y, z), Vector3.ZERO, STEEL.darkened(0.4))


## Round handguard along -Z with rib rings and side slots.
static func _round_guard(b: VisUtil.Builder, key: String, r: float, len: float, pos: Vector3, col: Color, ribs := 6) -> void:
	b.cyl(key, r, len, pos, Vector3(90, 0, 0), col, -1.0, 16)
	for i in ribs:
		var z := pos.z + len * 0.5 - (i + 0.5) * len / ribs
		b.cyl(key, r * 1.04, 0.008, Vector3(pos.x, pos.y, z), Vector3(90, 0, 0), col.darkened(0.25), -1.0, 16)
		for sx in [-1.0, 1.0]:
			b.box("polymer", Vector3(0.004, r * 0.5, len / ribs * 0.5), Vector3(pos.x + sx * r * 0.98, pos.y, z + len / ribs * 0.5), Vector3.ZERO, Color(0.02, 0.02, 0.02))


static func _rail(b: VisUtil.Builder, y: float, z0: float, z1: float, col := BLK) -> void:
	var len := z1 - z0
	b.box("parker", Vector3(0.022, 0.008, len), Vector3(0, y, (z0 + z1) * 0.5), Vector3.ZERO, col)
	var n := int(len / 0.01)
	for i in range(0, n, 2):
		b.box("parker", Vector3(0.025, 0.005, 0.005), Vector3(0, y + 0.006, z0 + 0.005 + i * 0.01), Vector3.ZERO, col)


# --- Rifles -----------------------------------------------------------------
static func _kv74(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	var rc := Color(0.15, 0.15, 0.145)
	b.box("parker", Vector3(0.052, 0.066, 0.31), Vector3(0, 0.046, -0.075), Vector3.ZERO, rc)
	b.cyl("parker", 0.026, 0.29, Vector3(0, 0.078, -0.07), Vector3(90, 0, 0), GM2, -1.0, 16)
	for i in 3:
		b.sphere("steel", 0.003, Vector3(0.027, 0.03, -0.17 + i * 0.09), STEEL.darkened(0.4))
	_eject_port(b, 0.027, 0.07, -0.1, 0.075)
	b.box("steel", Vector3(0.006, 0.012, 0.09), Vector3(0.029, 0.058, -0.02), Vector3.ZERO, STEEL.darkened(0.35))
	b.capsule("steel", 0.006, 0.04, Vector3(0.036, 0.074, -0.165), Vector3(0, 0, 90), STEEL.darkened(0.2))
	b.box("parker", Vector3(0.03, 0.026, 0.05), Vector3(0, 0.098, -0.245), Vector3.ZERO, rc)
	b.box("parker", Vector3(0.012, 0.012, 0.06), Vector3(0, 0.113, -0.24), Vector3.ZERO, GM2)
	b.cyl("parker", 0.0115, 0.44, Vector3(0, 0.064, -0.45), Vector3(90, 0, 0), GM2)
	b.box("parker", Vector3(0.028, 0.048, 0.03), Vector3(0, 0.078, -0.475), Vector3.ZERO, rc)
	b.cyl("parker", 0.012, 0.2, Vector3(0, 0.098, -0.37), Vector3(90, 0, 0), rc)
	b.cyl("wood", 0.022, 0.17, Vector3(0, 0.1, -0.34), Vector3(90, 0, 0), WOOD, -1.0, 14, Vector3(1.0, 1, 0.75))
	b.cyl("wood", 0.035, 0.2, Vector3(0, 0.052, -0.335), Vector3(90, 0, 0), WOOD, 0.033, 16, Vector3(1.0, 1, 0.85))
	for i in 3:
		b.box("wood", Vector3(0.071, 0.004, 0.012), Vector3(0, 0.068, -0.27 - i * 0.05), Vector3.ZERO, WOOD2)
	b.box("parker", Vector3(0.02, 0.055, 0.025), Vector3(0, 0.09, -0.61), Vector3.ZERO, rc)
	b.cyl("parker", 0.003, 0.03, Vector3(0, 0.13, -0.61), Vector3.ZERO, GM2, -1.0, 6)
	b.cyl("parker", 0.016, 0.07, Vector3(0, 0.064, -0.695), Vector3(90, 0, 0), GM2, 0.014)
	b.box("polymer", Vector3(0.022, 0.004, 0.03), Vector3(0, 0.08, -0.7), Vector3.ZERO, Color(0.02, 0.02, 0.02))
	_trigger_group(b, 0.0, GM2)
	_grip(b, Vector3(0, 0.005, 0.012), 18.0, Color(0.36, 0.17, 0.09))
	b.box("wood", Vector3(0.04, 0.062, 0.3), Vector3(0, 0.014, 0.23), Vector3(-6, 0, 0), WOOD)
	b.cyl("wood", 0.022, 0.3, Vector3(0, -0.012, 0.23), Vector3(84, 0, 0), WOOD, 0.03, 12, Vector3(0.95, 1, 1))
	b.box("wood", Vector3(0.042, 0.11, 0.07), Vector3(0, -0.006, 0.36), Vector3(-6, 0, 0), WOOD2)
	b.box("parker", Vector3(0.044, 0.116, 0.012), Vector3(0, -0.008, 0.398), Vector3(-6, 0, 0), GM2)
	# banana magazine
	for i in 6:
		var a := 6.0 + i * 6.5
		var r := deg_to_rad(a)
		var y := -0.02 - i * 0.03
		var z := -0.004 - i * i * 0.0028
		mb.box("parker", Vector3(0.026, 0.034, 0.066 - i * 0.001), Vector3(0, y, z), Vector3(a, 0, 0), Color(0.12, 0.12, 0.115))
		mb.box("parker", Vector3(0.028, 0.006, 0.02), Vector3(0, y, z - 0.026), Vector3(a, 0, 0), Color(0.09, 0.09, 0.09))
	mb.box("parker", Vector3(0.03, 0.012, 0.068), Vector3(0, -0.2, -0.105), Vector3(44, 0, 0), BLK)
	mk["mag"] = Vector3(0, 0.012, -0.115)
	mk["muzzle"] = Vector3(0, 0.064, -0.735)
	mk["left"] = Vector3(0, 0.04, -0.34)
	mk["sight_y"] = 0.118
	mk["sight_z"] = -0.24


static func _ar7(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	var c := Color(0.15, 0.15, 0.155)
	b.box("parker", Vector3(0.048, 0.054, 0.25), Vector3(0, 0.068, -0.06), Vector3.ZERO, c)
	b.box("parker", Vector3(0.044, 0.05, 0.17), Vector3(0, 0.024, -0.04), Vector3.ZERO, c)
	b.cyl("parker", 0.024, 0.17, Vector3(0, 0.03, -0.04), Vector3(90, 0, 0), c, -1.0, 14, Vector3(1, 1, 1.05))
	b.box("parker", Vector3(0.036, 0.05, 0.07), Vector3(0, -0.006, -0.1), Vector3.ZERO, c)
	b.cyl("parker", 0.008, 0.03, Vector3(0.03, 0.072, -0.01), Vector3(90, 0, 0), GM2)
	_eject_port(b, 0.025, 0.065, -0.07, 0.065)
	b.box("steel", Vector3(0.012, 0.012, 0.02), Vector3(0.028, 0.08, -0.03), Vector3.ZERO, STEEL.darkened(0.4))
	_rail(b, 0.1, -0.47, 0.07, BLK)
	_round_guard(b, "polymer", 0.031, 0.27, Vector3(0, 0.068, -0.32), Color(0.2, 0.2, 0.2), 6)
	for sx in [-1.0, 1.0]:
		b.box("parker", Vector3(0.008, 0.016, 0.26), Vector3(sx * 0.031, 0.068, -0.32), Vector3.ZERO, BLK)
	b.cyl("parker", 0.0095, 0.2, Vector3(0, 0.068, -0.55), Vector3(90, 0, 0), GM2)
	b.box("parker", Vector3(0.024, 0.034, 0.024), Vector3(0, 0.08, -0.5), Vector3.ZERO, BLK)
	_flash_hider(b, Vector3(0, 0.068, -0.67), 0.012, 0.055)
	b.box("parker", Vector3(0.014, 0.036, 0.018), Vector3(0, 0.12, -0.43), Vector3.ZERO, BLK)
	b.cyl("parker", 0.0025, 0.02, Vector3(0, 0.145, -0.43), Vector3.ZERO, BLK, -1.0, 6)
	b.box("steel", Vector3(0.03, 0.01, 0.03), Vector3(0, 0.092, 0.065), Vector3.ZERO, STEEL.darkened(0.45))
	b.cyl("parker", 0.015, 0.18, Vector3(0, 0.058, 0.15), Vector3(90, 0, 0), BLK)
	b.box("polymer", Vector3(0.04, 0.07, 0.15), Vector3(0, 0.038, 0.21), Vector3.ZERO, DGRY)
	b.capsule("polymer", 0.02, 0.13, Vector3(0, 0.078, 0.21), Vector3(90, 0, 0), DGRY, Vector3(1.0, 1, 0.9))
	b.box("rubber", Vector3(0.044, 0.11, 0.025), Vector3(0, 0.025, 0.29), Vector3.ZERO, BLK)
	_grip(b, Vector3(0, 0.002, 0.012), 20.0, BLK)
	_trigger_group(b, 0.0, c)
	# Holographic sight
	b.box("parker", Vector3(0.034, 0.016, 0.07), Vector3(0, 0.112, -0.12), Vector3.ZERO, BLK)
	for sx in [-1.0, 1.0]:
		b.box("parker", Vector3(0.006, 0.04, 0.07), Vector3(sx * 0.018, 0.14, -0.12), Vector3.ZERO, BLK)
	b.capsule("parker", 0.006, 0.048, Vector3(0, 0.162, -0.12), Vector3(0, 0, 90), BLK)
	b.box("parker", Vector3(0.042, 0.008, 0.07), Vector3(0, 0.16, -0.12), Vector3.ZERO, BLK)
	b.sphere("lens_red", 0.0022, Vector3(0, 0.142, -0.148), Color.WHITE)
	b.cyl("polymer", 0.015, 0.085, Vector3(0, 0.0, -0.34), Vector3.ZERO, BLK)
	for i in 4:
		b.cyl("polymer", 0.0158, 0.004, Vector3(0, -0.02 + i * 0.015, -0.34), Vector3.ZERO, Color(0.03, 0.03, 0.03))
	var mc := Color(0.22, 0.22, 0.2)
	for i in 4:
		var a := 3.0 + i * 3.5
		mb.box("parker", Vector3(0.024, 0.036, 0.064), Vector3(0, -0.02 - i * 0.034, -i * i * 0.0012), Vector3(a, 0, 0), mc)
		mb.box("parker", Vector3(0.0255, 0.004, 0.05), Vector3(0, -0.035 - i * 0.034, -i * i * 0.0012), Vector3(a, 0, 0), mc.darkened(0.3))
	mb.box("polymer", Vector3(0.028, 0.012, 0.068), Vector3(0, -0.142, -0.02), Vector3(14, 0, 0), BLK)
	mk["mag"] = Vector3(0, -0.01, -0.1)
	mk["muzzle"] = Vector3(0, 0.068, -0.7)
	mk["left"] = Vector3(0, -0.01, -0.34)
	mk["sight_y"] = 0.142
	mk["sight_z"] = -0.12


static func _hornet(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	var c := Color(0.42, 0.42, 0.33)
	b.box("polymer", Vector3(0.058, 0.07, 0.55), Vector3(0, 0.045, 0.02), Vector3.ZERO, c)
	b.cyl("polymer", 0.029, 0.55, Vector3(0, 0.012, 0.02), Vector3(90, 0, 0), c.darkened(0.12), -1.0, 16, Vector3(1, 1, 0.9))
	b.cyl("polymer", 0.029, 0.5, Vector3(0, 0.078, 0.0), Vector3(90, 0, 0), c, -1.0, 16, Vector3(1, 1, 0.5))
	b.box("polymer", Vector3(0.03, 0.035, 0.26), Vector3(0, 0.1, -0.03), Vector3.ZERO, c)
	b.cyl("parker", 0.022, 0.22, Vector3(0, 0.135, -0.04), Vector3(90, 0, 0), BLK)
	b.cyl("parker", 0.026, 0.04, Vector3(0, 0.135, -0.16), Vector3(90, 0, 0), BLK)
	b.cyl("glass", 0.021, 0.004, Vector3(0, 0.135, -0.18), Vector3(90, 0, 0))
	b.cyl("glass", 0.018, 0.004, Vector3(0, 0.135, 0.071), Vector3(90, 0, 0))
	b.cyl("parker", 0.01, 0.12, Vector3(0, 0.05, -0.31), Vector3(90, 0, 0), GM2)
	_flash_hider(b, Vector3(0, 0.05, -0.385), 0.013, 0.05)
	b.capsule("polymer", 0.024, 0.08, Vector3(0, -0.04, -0.2), Vector3(14, 0, 0), c, Vector3(1.0, 1, 1.2))
	_grip(b, Vector3(0, -0.005, -0.005), 15.0, c.darkened(0.2))
	b.cyl("polymer", 0.006, 0.13, Vector3(0, -0.085, -0.06), Vector3(90, 0, 0), c)
	b.box("rubber", Vector3(0.062, 0.12, 0.02), Vector3(0, 0.03, 0.3), Vector3.ZERO, BLK)
	b.capsule("rubber", 0.018, 0.12, Vector3(0, 0.09, 0.24), Vector3(90, 0, 0), BLK, Vector3(1.4, 1, 1))
	_eject_port(b, 0.03, 0.055, 0.15, 0.07)
	mb.box("parker", Vector3(0.024, 0.11, 0.062), Vector3(0, -0.055, 0), Vector3(6, 0, 0), BLK)
	mb.box("polymer", Vector3(0.028, 0.012, 0.066), Vector3(0, -0.112, -0.006), Vector3(6, 0, 0), BLK)
	mk["mag"] = Vector3(0, -0.01, 0.12)
	mk["muzzle"] = Vector3(0, 0.05, -0.415)
	mk["left"] = Vector3(0, -0.02, -0.2)
	mk["sight_y"] = 0.135
	mk["sight_z"] = -0.04


static func _sentry(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	var t := Color(0.6, 0.52, 0.38)
	b.box("parker", Vector3(0.052, 0.064, 0.3), Vector3(0, 0.055, -0.07), Vector3.ZERO, GM)
	_eject_port(b, 0.027, 0.065, -0.06, 0.07)
	_round_guard(b, "polymer", 0.031, 0.3, Vector3(0, 0.062, -0.37), t, 7)
	b.cyl("parker", 0.011, 0.26, Vector3(0, 0.064, -0.65), Vector3(90, 0, 0), GM2)
	b.box("parker", Vector3(0.03, 0.03, 0.06), Vector3(0, 0.064, -0.8), Vector3.ZERO, BLK)
	for i in 3:
		b.box("polymer", Vector3(0.032, 0.006, 0.008), Vector3(0, 0.064, -0.785 - i * 0.012), Vector3.ZERO, Color(0.02, 0.02, 0.02))
	_rail(b, 0.093, -0.3, 0.06, BLK)
	b.cyl("parker", 0.019, 0.3, Vector3(0, 0.14, -0.1), Vector3(90, 0, 0), BLK, -1.0, 18)
	b.cyl("parker", 0.028, 0.09, Vector3(0, 0.14, -0.285), Vector3(90, 0, 0), BLK, 0.019, 18)
	b.cyl("parker", 0.023, 0.06, Vector3(0, 0.14, 0.075), Vector3(90, 0, 0), BLK, -1.0, 18)
	b.cyl("glass", 0.025, 0.004, Vector3(0, 0.14, -0.332), Vector3(90, 0, 0))
	b.cyl("glass", 0.02, 0.004, Vector3(0, 0.14, 0.106), Vector3(90, 0, 0))
	b.cyl("parker", 0.012, 0.03, Vector3(0, 0.172, -0.1), Vector3.ZERO, BLK)
	b.cyl("parker", 0.012, 0.03, Vector3(0.032, 0.14, -0.1), Vector3(0, 0, 90), BLK)
	for zz in [-0.2, 0.0]:
		b.box("parker", Vector3(0.03, 0.045, 0.02), Vector3(0, 0.115, zz), Vector3.ZERO, GM2)
		b.torus("parker", 0.019, 0.024, Vector3(0, 0.14, zz), Vector3(90, 0, 0), GM2)
	b.box("polymer", Vector3(0.044, 0.088, 0.3), Vector3(0, 0.03, 0.22), Vector3(-3, 0, 0), t)
	b.cyl("polymer", 0.022, 0.3, Vector3(0, -0.012, 0.22), Vector3(87, 0, 0), t, -1.0, 12)
	b.capsule("polymer", 0.02, 0.12, Vector3(0, 0.085, 0.2), Vector3(90, 0, 0), t.darkened(0.1), Vector3(1.0, 1, 1.0))
	b.box("rubber", Vector3(0.047, 0.11, 0.02), Vector3(0, 0.025, 0.375), Vector3.ZERO, BLK)
	_grip(b, Vector3(0, 0.002, 0.012), 18.0, BLK)
	_trigger_group(b, 0.0, GM2)
	b.cyl("parker", 0.006, 0.2, Vector3(0.012, 0.025, -0.38), Vector3(90, 0, 0), BLK)
	b.cyl("parker", 0.006, 0.2, Vector3(-0.012, 0.025, -0.38), Vector3(90, 0, 0), BLK)
	mb.box("parker", Vector3(0.03, 0.09, 0.064), Vector3(0, -0.045, 0), Vector3(3, 0, 0), BLK)
	mb.box("parker", Vector3(0.0315, 0.004, 0.05), Vector3(0, -0.03, 0.0), Vector3(3, 0, 0), Color(0.03, 0.03, 0.03))
	mk["mag"] = Vector3(0, 0.0, -0.1)
	mk["muzzle"] = Vector3(0, 0.064, -0.83)
	mk["left"] = Vector3(0, 0.03, -0.36)
	mk["sight_y"] = 0.14
	mk["sight_z"] = -0.1


static func _thresher(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	b.box("parker", Vector3(0.07, 0.1, 0.36), Vector3(0, 0.06, -0.06), Vector3.ZERO, GM2)
	b.box("parker", Vector3(0.074, 0.03, 0.2), Vector3(0, 0.125, -0.04), Vector3.ZERO, GM)
	b.cyl("parker", 0.016, 0.075, Vector3(0, 0.126, -0.04), Vector3(0, 0, 90), GM2)
	b.box("parker", Vector3(0.016, 0.03, 0.03), Vector3(0, 0.15, 0.04), Vector3.ZERO, GM2)
	b.capsule("parker", 0.009, 0.13, Vector3(0, 0.178, -0.24), Vector3(90, 0, 0), BLK)
	b.box("parker", Vector3(0.012, 0.04, 0.012), Vector3(0, 0.15, -0.18), Vector3.ZERO, BLK)
	b.box("parker", Vector3(0.012, 0.04, 0.012), Vector3(0, 0.15, -0.3), Vector3.ZERO, BLK)
	_eject_port(b, 0.036, 0.05, -0.04, 0.09)
	b.cyl("parker", 0.013, 0.52, Vector3(0, 0.065, -0.57), Vector3(90, 0, 0), GM2)
	b.cyl("parker", 0.024, 0.3, Vector3(0, 0.075, -0.42), Vector3(90, 0, 0), GM, -1.0, 14)
	for i in 6:
		b.cyl("polymer", 0.0245, 0.016, Vector3(0, 0.075, -0.31 - i * 0.045), Vector3(90, 0, 0), Color(0.03, 0.03, 0.03), -1.0, 14)
	_flash_hider(b, Vector3(0, 0.065, -0.845), 0.018, 0.06)
	b.box("parker", Vector3(0.012, 0.05, 0.02), Vector3(0, 0.11, -0.78), Vector3.ZERO, BLK)
	b.cyl("polymer", 0.033, 0.2, Vector3(0, 0.03, -0.33), Vector3(90, 0, 0), BLK, -1.0, 14, Vector3(1, 1, 0.75))
	b.cyl("parker", 0.008, 0.32, Vector3(0.05, -0.06, -0.64), Vector3(-20, 0, 18), GM2)
	b.cyl("parker", 0.008, 0.32, Vector3(-0.05, -0.06, -0.64), Vector3(-20, 0, -18), GM2)
	b.sphere("rubber", 0.012, Vector3(0.1, -0.205, -0.69), BLK)
	b.sphere("rubber", 0.012, Vector3(-0.1, -0.205, -0.69), BLK)
	b.box("polymer", Vector3(0.045, 0.1, 0.28), Vector3(0, 0.035, 0.25), Vector3(-4, 0, 0), BLK)
	b.box("rubber", Vector3(0.05, 0.13, 0.025), Vector3(0, 0.03, 0.39), Vector3.ZERO, BLK)
	_grip(b, Vector3(0, 0.005, 0.02), 18.0, BLK)
	_trigger_group(b, 0.01, GM2)
	for i in 3:
		b.cyl("brass", 0.006, 0.05, Vector3(-0.042, 0.05 + i * 0.002, -0.1 + i * 0.012), Vector3(0, 0, 90), BRASS)
	mb.box("polymer", Vector3(0.085, 0.12, 0.13), Vector3(0, -0.06, 0), Vector3.ZERO, OD)
	mb.box("polymer", Vector3(0.087, 0.02, 0.132), Vector3(0, -0.005, 0), Vector3.ZERO, OD.darkened(0.3))
	mb.box("rubber", Vector3(0.01, 0.06, 0.04), Vector3(-0.045, -0.05, 0), Vector3.ZERO, BLK)
	mk["mag"] = Vector3(-0.02, -0.005, -0.1)
	mk["muzzle"] = Vector3(0, 0.065, -0.88)
	mk["left"] = Vector3(0, 0.0, -0.33)
	mk["sight_y"] = 0.165
	mk["sight_z"] = 0.04


# --- SMGs / pistols --------------------------------------------------------------
static func _vespa(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	var c := Color(0.13, 0.13, 0.135)
	b.box("parker", Vector3(0.046, 0.05, 0.28), Vector3(0, 0.058, -0.07), Vector3.ZERO, c)
	b.cyl("parker", 0.026, 0.28, Vector3(0, 0.07, -0.07), Vector3(90, 0, 0), c, -1.0, 16)
	_eject_port(b, 0.025, 0.075, -0.04, 0.05)
	_round_guard(b, "polymer", 0.031, 0.14, Vector3(0, 0.048, -0.275), BLK, 4)
	b.cyl("parker", 0.009, 0.1, Vector3(0, 0.068, -0.39), Vector3(90, 0, 0), GM2)
	b.cyl("parker", 0.012, 0.03, Vector3(0, 0.068, -0.44), Vector3(90, 0, 0), BLK)
	b.torus("parker", 0.012, 0.018, Vector3(0, 0.112, -0.34), Vector3(90, 0, 0), c)
	b.box("parker", Vector3(0.012, 0.03, 0.012), Vector3(0, 0.098, -0.34), Vector3.ZERO, c)
	b.cyl("parker", 0.014, 0.02, Vector3(0, 0.106, 0.02), Vector3(0, 0, 90), c)
	b.cyl("parker", 0.008, 0.2, Vector3(-0.02, 0.098, -0.18), Vector3(90, 0, 0), c)
	b.capsule("steel", 0.006, 0.03, Vector3(-0.034, 0.098, -0.26), Vector3(0, 0, 90), STEEL.darkened(0.3))
	_grip(b, Vector3(0, 0.002, 0.012), 15.0, BLK)
	_trigger_group(b, 0.0, c)
	b.cyl("steel", 0.005, 0.2, Vector3(0.018, 0.05, 0.17), Vector3(90, 0, 0), STEEL.darkened(0.2))
	b.cyl("steel", 0.005, 0.2, Vector3(-0.018, 0.05, 0.17), Vector3(90, 0, 0), STEEL.darkened(0.2))
	b.capsule("rubber", 0.012, 0.09, Vector3(0, 0.04, 0.275), Vector3.ZERO, BLK, Vector3(2.0, 1, 1))
	for i in 3:
		var a := 8.0 + i * 6.0
		mb.box("parker", Vector3(0.022, 0.05, 0.032), Vector3(0, -0.025 - i * 0.048, -i * i * 0.004), Vector3(a, 0, 0), GM2)
	mb.box("parker", Vector3(0.025, 0.01, 0.034), Vector3(0, -0.15, -0.02), Vector3(22, 0, 0), BLK)
	mk["mag"] = Vector3(0, 0.02, -0.1)
	mk["muzzle"] = Vector3(0, 0.068, -0.455)
	mk["left"] = Vector3(0, 0.03, -0.27)
	mk["sight_y"] = 0.112
	mk["sight_z"] = -0.34


static func _mako(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	b.box("polymer", Vector3(0.055, 0.085, 0.36), Vector3(0, 0.05, -0.08), Vector3.ZERO, BLK)
	b.cyl("polymer", 0.0275, 0.36, Vector3(0, 0.01, -0.08), Vector3(90, 0, 0), BLK, -1.0, 14, Vector3(1, 1, 0.7))
	for i in 4:
		b.box("polymer", Vector3(0.057, 0.008, 0.03), Vector3(0, 0.03, -0.2 - i * 0.03), Vector3.ZERO, Color(0.03, 0.03, 0.03))
	_eject_port(b, 0.028, 0.07, -0.05, 0.05)
	_rail(b, 0.097, -0.24, 0.07, BLK)
	b.cyl("parker", 0.01, 0.08, Vector3(0, 0.066, -0.3), Vector3(90, 0, 0), GM2)
	_flash_hider(b, Vector3(0, 0.066, -0.355), 0.014, 0.045)
	_grip(b, Vector3(0, 0.002, 0.018), 12.0, BLK)
	_trigger_group(b, 0.0, BLK)
	b.capsule("polymer", 0.01, 0.2, Vector3(0, 0.075, 0.2), Vector3(90, 0, 0), BLK, Vector3(1.5, 1, 1))
	b.capsule("polymer", 0.01, 0.2, Vector3(0, 0.0, 0.2), Vector3(90, 0, 0), BLK, Vector3(1.5, 1, 1))
	b.capsule("rubber", 0.012, 0.1, Vector3(0, 0.038, 0.3), Vector3.ZERO, BLK, Vector3(1.6, 1, 1))
	b.box("parker", Vector3(0.026, 0.012, 0.045), Vector3(0, 0.107, -0.1), Vector3.ZERO, BLK)
	b.box("parker", Vector3(0.03, 0.03, 0.006), Vector3(0, 0.128, -0.118), Vector3.ZERO, BLK)
	b.sphere("lens_red", 0.002, Vector3(0, 0.128, -0.12), Color.WHITE)
	mb.box("polymer", Vector3(0.028, 0.13, 0.05), Vector3(0, -0.065, 0), Vector3(4, 0, 0), BLK)
	for i in 3:
		mb.box("polymer", Vector3(0.0285, 0.003, 0.04), Vector3(0, -0.03 - i * 0.03, 0.0), Vector3(4, 0, 0), Color(0.03, 0.03, 0.03))
	mk["mag"] = Vector3(0, 0.0, -0.12)
	mk["muzzle"] = Vector3(0, 0.066, -0.378)
	mk["left"] = Vector3(0, 0.02, -0.22)
	mk["sight_y"] = 0.128
	mk["sight_z"] = -0.11


static func _raptor(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	b.box("parker", Vector3(0.029, 0.032, 0.19), Vector3(0, 0.07, -0.06), Vector3.ZERO, Color(0.1, 0.1, 0.11))
	for i in 5:
		b.box("parker", Vector3(0.031, 0.024, 0.003), Vector3(0, 0.07, 0.012 + i * 0.007), Vector3.ZERO, BLK)
	_eject_port(b, 0.0155, 0.078, -0.05, 0.04)
	b.box("polymer", Vector3(0.027, 0.026, 0.16), Vector3(0, 0.044, -0.055), Vector3.ZERO, BLK)
	b.box("parker", Vector3(0.03, 0.03, 0.035), Vector3(0, 0.068, -0.17), Vector3.ZERO, GM)
	b.box("polymer", Vector3(0.024, 0.006, 0.03), Vector3(0, 0.084, -0.17), Vector3.ZERO, Color(0.02, 0.02, 0.02))
	_grip(b, Vector3(0, 0.03, 0.008), 15.0, BLK, 0.1)
	b.box("parker", Vector3(0.005, 0.008, 0.005), Vector3(0, 0.09, -0.15), Vector3.ZERO, BLK)
	b.box("parker", Vector3(0.016, 0.008, 0.006), Vector3(0, 0.09, 0.025), Vector3.ZERO, BLK)
	_trigger_group(b, 0.0, BLK)
	mb.box("parker", Vector3(0.024, 0.17, 0.034), Vector3(0, -0.06, 0), Vector3(-15, 0, 0), GM2)
	mb.box("polymer", Vector3(0.028, 0.012, 0.04), Vector3(0, -0.142, 0.022), Vector3(-15, 0, 0), BLK)
	mk["mag"] = Vector3(0, -0.01, 0.015)
	mk["muzzle"] = Vector3(0, 0.068, -0.19)
	mk["left"] = Vector3(0.0, -0.035, 0.0)
	mk["sight_y"] = 0.094
	mk["sight_z"] = -0.1


static func _hawk(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary) -> void:
	b.box("steel", Vector3(0.036, 0.045, 0.27), Vector3(0, 0.075, -0.075), Vector3.ZERO, STEEL)
	b.capsule("steel", 0.012, 0.25, Vector3(0, 0.1, -0.08), Vector3(90, 0, 0), STEEL.darkened(0.15), Vector3(1.4, 1, 0.6))
	for i in 3:
		b.box("parker", Vector3(0.038, 0.012, 0.012), Vector3(0, 0.075, -0.2 + i * 0.02), Vector3.ZERO, GM2)
	_eject_port(b, 0.018, 0.08, -0.03, 0.045)
	b.box("parker", Vector3(0.033, 0.03, 0.2), Vector3(0, 0.04, -0.06), Vector3.ZERO, GM)
	_grip(b, Vector3(0, 0.03, 0.012), 12.0, BLK, 0.11)
	b.capsule("parker", 0.006, 0.03, Vector3(0, 0.09, 0.065), Vector3(-30, 0, 0), GM2)
	b.box("parker", Vector3(0.006, 0.012, 0.008), Vector3(0, 0.112, -0.2), Vector3.ZERO, GM2)
	_trigger_group(b, 0.0, GM)
	mb.box("parker", Vector3(0.026, 0.09, 0.034), Vector3(0, -0.045, 0), Vector3(-12, 0, 0), GM2)
	mk["mag"] = Vector3(0, -0.005, 0.02)
	mk["muzzle"] = Vector3(0, 0.08, -0.21)
	mk["left"] = Vector3(0.0, -0.035, 0.0)
	mk["sight_y"] = 0.115
	mk["sight_z"] = -0.18


static func _breacher(b: VisUtil.Builder, mb: VisUtil.Builder, mk: Dictionary, extra: Dictionary) -> void:
	var rc := Color(0.14, 0.14, 0.15)
	b.box("parker", Vector3(0.05, 0.07, 0.22), Vector3(0, 0.055, -0.03), Vector3.ZERO, rc)
	b.cyl("parker", 0.025, 0.22, Vector3(0, 0.075, -0.03), Vector3(90, 0, 0), rc, -1.0, 14, Vector3(1, 1, 0.8))
	_eject_port(b, 0.026, 0.06, -0.04, 0.07)
	b.box("parker", Vector3(0.052, 0.02, 0.06), Vector3(0.0, 0.03, -0.02), Vector3.ZERO, GM2)
	b.cyl("parker", 0.012, 0.6, Vector3(0, 0.078, -0.44), Vector3(90, 0, 0), GM2)
	b.cyl("parker", 0.012, 0.5, Vector3(0, 0.046, -0.39), Vector3(90, 0, 0), GM)
	b.cyl("parker", 0.0125, 0.02, Vector3(0, 0.046, -0.645), Vector3(90, 0, 0), BLK)
	b.box("parker", Vector3(0.026, 0.05, 0.02), Vector3(0, 0.062, -0.62), Vector3.ZERO, GM)
	b.sphere("brass", 0.004, Vector3(0, 0.094, -0.72), BRASS)
	b.box("polymer", Vector3(0.038, 0.075, 0.3), Vector3(0, 0.022, 0.23), Vector3(-6, 0, 0), BLK)
	b.cyl("polymer", 0.02, 0.3, Vector3(0, -0.014, 0.23), Vector3(84, 0, 0), BLK, 0.028, 12, Vector3(0.95, 1, 1))
	b.box("rubber", Vector3(0.044, 0.12, 0.025), Vector3(0, 0.008, 0.385), Vector3(-6, 0, 0), BLK)
	_grip(b, Vector3(0, 0.0, 0.012), 18.0, BLK)
	_trigger_group(b, 0.0, BLK)
	for i in 4:
		b.cyl("polymer", 0.0095, 0.06, Vector3(-0.033, 0.052, 0.035 - i * 0.022), Vector3.ZERO, RED)
		b.cyl("brass", 0.0098, 0.012, Vector3(-0.033, 0.026, 0.035 - i * 0.022), Vector3.ZERO, BRASS)
	b.box("polymer", Vector3(0.004, 0.07, 0.1), Vector3(-0.027, 0.05, 0.002), Vector3.ZERO, BLK)
	var pump := VisUtil.Builder.new()
	pump.cyl("polymer", 0.027, 0.17, Vector3.ZERO, Vector3(90, 0, 0), BLK, -1.0, 16, Vector3(1, 1, 0.85))
	for i in 7:
		pump.cyl("polymer", 0.0285, 0.008, Vector3(0, 0, -0.07 + i * 0.023), Vector3(90, 0, 0), Color(0.03, 0.03, 0.03), -1.0, 16, Vector3(1, 1, 0.85))
	extra["Pump"] = [pump, Vector3(0, 0.044, -0.37)]
	mb.cyl("polymer", 0.0095, 0.06, Vector3(0, -0.03, 0), Vector3.ZERO, RED)
	mb.cyl("brass", 0.0098, 0.012, Vector3(0, -0.06, 0), Vector3.ZERO, BRASS)
	mk["mag"] = Vector3(0, 0.0, -0.05)
	mk["muzzle"] = Vector3(0, 0.078, -0.745)
	mk["left"] = Vector3(0, 0.02, -0.37)
	mk["sight_y"] = 0.096
	mk["sight_z"] = -0.72


# --- Melee / throwables / objective ---------------------------------------------
static func _knife(b: VisUtil.Builder, mk: Dictionary) -> void:
	b.cyl("rubber", 0.014, 0.11, Vector3(0, 0, 0.025), Vector3(90, 0, 0), BLK)
	for i in 4:
		b.torus("rubber", 0.012, 0.0155, Vector3(0, 0, -0.01 + i * 0.022), Vector3(90, 0, 0), Color(0.12, 0.12, 0.12))
	b.cyl("metal", 0.016, 0.012, Vector3(0, 0, 0.083), Vector3(90, 0, 0), GM)
	b.box("metal", Vector3(0.014, 0.056, 0.009), Vector3(0, 0.004, -0.034), Vector3.ZERO, GM)
	b.box("steel", Vector3(0.004, 0.032, 0.14), Vector3(0, 0.004, -0.108), Vector3.ZERO, STEEL)
	b.box("metal", Vector3(0.0045, 0.008, 0.13), Vector3(0, 0.018, -0.1), Vector3.ZERO, GM)
	b.box("steel", Vector3(0.004, 0.0226, 0.0226), Vector3(0, -0.001, -0.178), Vector3(45, 0, 0), STEEL)
	mk["muzzle"] = Vector3(0, 0.0, -0.19)
	mk["left"] = Vector3(0, -0.05, 0.1)
	mk["sight_y"] = 0.0


static func _grenade(b: VisUtil.Builder, mk: Dictionary, id: String) -> void:
	match id:
		"frag":
			b.sphere("polymer", 0.034, Vector3(0, 0, 0), Color(0.3, 0.33, 0.22), Vector3(1, 1.15, 1))
			for i in 4:
				b.torus("polymer", 0.033, 0.0365, Vector3(0, -0.02 + i * 0.013, 0), Vector3.ZERO, Color(0.26, 0.29, 0.19))
		"flash":
			b.cyl("metal", 0.022, 0.1, Vector3(0, 0, 0), Vector3.ZERO, Color(0.25, 0.26, 0.27))
			for i in 6:
				var a := TAU * i / 6.0
				b.box("metal", Vector3(0.012, 0.03, 0.012), Vector3(cos(a) * 0.019, 0.01, sin(a) * 0.019), Vector3(0, -rad_to_deg(a), 0), BLK)
			b.cyl("polymer", 0.0225, 0.015, Vector3(0, -0.03, 0), Vector3.ZERO, Color(0.85, 0.75, 0.2))
		"smoke":
			b.cyl("metal", 0.028, 0.12, Vector3(0, 0, 0), Vector3.ZERO, Color(0.28, 0.32, 0.24))
			b.cyl("polymer", 0.0285, 0.02, Vector3(0, 0.02, 0), Vector3.ZERO, Color(0.85, 0.85, 0.82))
			b.cyl("metal", 0.024, 0.006, Vector3(0, -0.063, 0), Vector3.ZERO, GM)
	var top := 0.045 if id == "frag" else (0.055 if id == "flash" else 0.065)
	b.cyl("metal", 0.009, 0.03, Vector3(0, top, 0), Vector3.ZERO, GM)
	b.box("metal", Vector3(0.012, 0.06, 0.004), Vector3(0, top - 0.02, 0.026), Vector3(-12, 0, 0), Color(0.45, 0.45, 0.42))
	b.torus("steel", 0.007, 0.0095, Vector3(0.016, top + 0.01, 0), Vector3(0, 0, 90), STEEL)
	mk["muzzle"] = Vector3(0, top, 0)
	mk["left"] = Vector3(0.0, top, 0.04)
	mk["sight_y"] = 0.0


static func _bomb(b: VisUtil.Builder, mk: Dictionary) -> void:
	var putty := Color(0.74, 0.7, 0.55)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			b.box("polymer", Vector3(0.08, 0.05, 0.12), Vector3(sx * 0.042, 0.025, sz * 0.062), Vector3.ZERO, putty)
	b.box("rubber", Vector3(0.172, 0.054, 0.02), Vector3(0, 0.025, -0.035), Vector3.ZERO, Color(0.16, 0.16, 0.15))
	b.box("rubber", Vector3(0.172, 0.054, 0.02), Vector3(0, 0.025, 0.045), Vector3.ZERO, Color(0.16, 0.16, 0.15))
	b.box("metal", Vector3(0.09, 0.03, 0.08), Vector3(0, 0.065, 0.0), Vector3.ZERO, DGRY)
	b.box("emit_red", Vector3(0.055, 0.003, 0.022), Vector3(0, 0.081, 0.018), Vector3.ZERO, Color.WHITE)
	for i in 3:
		for j in 3:
			b.box("rubber", Vector3(0.012, 0.006, 0.009), Vector3(-0.018 + i * 0.018, 0.081, -0.012 - j * 0.012), Vector3.ZERO, Color(0.1, 0.1, 0.1))
	var wires := [Color(0.8, 0.1, 0.1), Color(0.1, 0.3, 0.8), Color(0.9, 0.8, 0.1)]
	for i in 3:
		b.cyl("rubber", 0.003, 0.11, Vector3(0.05 + i * 0.008, 0.06, -0.01 + i * 0.01), Vector3(70, 0, 20), wires[i])
	b.cyl("metal", 0.003, 0.12, Vector3(-0.035, 0.13, -0.03), Vector3.ZERO, BLK)
	mk["muzzle"] = Vector3(0, 0.08, 0)
	mk["left"] = Vector3(-0.08, 0.02, 0)
	mk["sight_y"] = 0.0


static func _breach(b: VisUtil.Builder, mk: Dictionary) -> void:
	b.box("polymer", Vector3(0.07, 0.02, 0.34), Vector3(0, 0, -0.08), Vector3.ZERO, Color(0.22, 0.24, 0.19))
	b.box("polymer", Vector3(0.05, 0.01, 0.32), Vector3(0, 0.014, -0.08), Vector3.ZERO, Color(0.55, 0.52, 0.4))
	b.box("metal", Vector3(0.045, 0.03, 0.055), Vector3(0, 0.025, 0.06), Vector3.ZERO, DGRY)
	b.sphere("emit_red", 0.004, Vector3(0.012, 0.042, 0.06), Color.WHITE)
	b.cyl("metal", 0.003, 0.08, Vector3(-0.012, 0.06, 0.07), Vector3.ZERO, BLK)
	mk["muzzle"] = Vector3(0, 0.0, -0.25)
	mk["left"] = Vector3(0, 0.0, -0.18)
	mk["sight_y"] = 0.0


# --- Poly Haven models ------------------------------------------------------------
static func _gltf_meshes(path: String) -> Dictionary:
	var out := {}
	var ps: PackedScene = load(path)
	if ps == null:
		return out
	var inst: Node3D = ps.instantiate()
	for c in inst.get_children():
		if c is MeshInstance3D:
			out[String(c.name)] = c
	for c in out.values():
		inst.remove_child(c)
	inst.free()
	return out


## Puts gltf meshes (whose muzzle points +X) under a holder rotated so the muzzle points -Z.
static func _ph_holder(parent: Node3D, name: String, grip: Vector3) -> Node3D:
	var h := Node3D.new()
	h.name = name
	h.rotation.y = PI * 0.5
	# (x,y,z) -> (z, y, -x) after rotation; shift so the grip lands at the origin
	h.position = Vector3(0, -grip.y, grip.x)
	parent.add_child(h)
	return h


static func _ph_point(p: Vector3, grip: Vector3) -> Vector3:
	return Vector3(p.z, p.y, -p.x) + Vector3(0, -grip.y, grip.x)


static func _polyhaven_pistol(root: Node3D) -> Node3D:
	var meshes := _gltf_meshes("res://assets/models/service_pistol/service_pistol_1k.gltf")
	var grip := Vector3(-0.012, 0.005, 0)
	var holder := _ph_holder(root, "Model", grip)
	var off := Vector3.ZERO
	for n in ["service_pistol_pistol_a", "service_pistol_slide_a", "service_pistol_hammer_a", "service_pistol_trigger_a"]:
		if meshes.has(n):
			var mi: MeshInstance3D = meshes[n]
			mi.position += off
			holder.add_child(mi)
	var mag := Node3D.new()
	mag.name = "Mag"
	root.add_child(mag)
	if meshes.has("service_pistol_magazine_loaded"):
		var mh := _ph_holder(mag, "MagModel", Vector3.ZERO)
		var mm: MeshInstance3D = meshes["service_pistol_magazine_loaded"]
		mm.position = Vector3.ZERO
		mm.rotation.z = deg_to_rad(-12)
		mh.add_child(mm)
		mag.position = _ph_point(Vector3(-0.008, 0.0, 0), grip)
	for m in meshes.values():
		if m.get_parent() == null:
			m.free()
	_marker(root, "Muzzle", _ph_point(Vector3(0.176, 0.062, 0), grip))
	_marker(root, "LeftHand", Vector3(0.0, -0.035, 0.0))
	_marker(root, "Sight", _ph_point(Vector3(0.05, 0.08, 0), grip))
	root.set_meta("hold", "pistol")
	root.set_meta("sight_y", 0.08 - grip.y)
	return root


static func _polyhaven_rifle(root: Node3D) -> Node3D:
	var meshes := _gltf_meshes("res://assets/models/bolt_action_rifle_7_62/bolt_action_rifle_7_62_1k.gltf")
	var grip := Vector3(-0.375, -0.035, 0)
	var holder := _ph_holder(root, "Model", grip)
	for n in ["bolt_action_rifle_7_62", "bolt_action_rifle_7_62_scope", "bolt_action_rifle_7_62_wrap", "bolt_action_rifle_7_62_trigger"]:
		if meshes.has(n):
			holder.add_child(meshes[n])
	var bolt := Node3D.new()
	bolt.name = "Bolt"
	bolt.position = _ph_point(Vector3(-0.237, 0.0507, 0), grip)
	root.add_child(bolt)
	if meshes.has("bolt_action_rifle_7_62_bolt_b"):
		var bh := _ph_holder(bolt, "BoltModel", Vector3.ZERO)
		var bm: MeshInstance3D = meshes["bolt_action_rifle_7_62_bolt_b"]
		bm.position = Vector3.ZERO
		bh.add_child(bm)
	var mag := Node3D.new()
	mag.name = "Mag"
	mag.position = _ph_point(Vector3(-0.2, -0.06, 0), grip)
	root.add_child(mag)
	for m in meshes.values():
		if m.get_parent() == null:
			m.free()
	_marker(root, "Muzzle", _ph_point(Vector3(0.6, 0.046, 0), grip))
	_marker(root, "LeftHand", _ph_point(Vector3(-0.02, 0.0, 0), grip))
	_marker(root, "Sight", _ph_point(Vector3(-0.2, 0.072, 0), grip))
	root.set_meta("hold", "rifle")
	root.set_meta("sight_y", 0.072 - grip.y)
	return root
