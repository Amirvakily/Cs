class_name BreachCharge
extends Node3D
## Frame breaching charge stuck to a door/wall. Every peer runs the same 2.5 s
## timer for visuals; the server also applies the explosion gameplay.

const FUSE := 2.5
const RADIUS := 3.5
const DAMAGE := 90.0

var net_id := 0
var owner_id := ""
var t := 0.0
var detonated := false
var _led: MeshInstance3D
var _led_light: OmniLight3D
var _next_beep := 0.0
var _normal := Vector3.FORWARD


func setup(p_net_id: int, p_owner_id: String, pos: Vector3, normal: Vector3) -> void:
	net_id = p_net_id
	owner_id = p_owner_id
	name = "Breach%d" % net_id
	_normal = normal.normalized() if normal.length() > 0.01 else Vector3.FORWARD
	var z := _normal
	var up := Vector3.UP if absf(z.y) < 0.9 else Vector3.FORWARD
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	transform = Transform3D(Basis(x, y, z), pos + _normal * 0.02)
	_build()


func _build() -> void:
	var putty := StandardMaterial3D.new()
	putty.albedo_color = Color(0.36, 0.38, 0.27)
	putty.roughness = 0.75
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.08, 0.08, 0.08)
	tape.roughness = 0.5
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.12, 0.12, 0.13)
	box_mat.roughness = 0.4
	box_mat.metallic = 0.3
	# Rectangular frame charge (local +Z points away from the surface).
	var w := 0.5
	var h := 0.7
	var t2 := 0.045
	_box(Vector3(w, t2, 0.03), Vector3(0, h * 0.5, 0.015), putty)
	_box(Vector3(w, t2, 0.03), Vector3(0, -h * 0.5, 0.015), putty)
	_box(Vector3(t2, h, 0.03), Vector3(-w * 0.5, 0, 0.015), putty)
	_box(Vector3(t2, h, 0.03), Vector3(w * 0.5, 0, 0.015), putty)
	for yy in [-0.2, 0.0, 0.2]:
		_box(Vector3(t2 + 0.01, 0.025, 0.034), Vector3(-w * 0.5, yy, 0.015), tape)
		_box(Vector3(t2 + 0.01, 0.025, 0.034), Vector3(w * 0.5, yy, 0.015), tape)
	# Detonator box with LED and wires.
	_box(Vector3(0.09, 0.07, 0.045), Vector3(w * 0.5 + 0.06, 0.12, 0.025), box_mat)
	_led = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.008
	s.height = 0.016
	_led.mesh = s
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(1, 0.1, 0.05)
	led_mat.emission_enabled = true
	led_mat.emission = Color(1, 0.1, 0.05)
	led_mat.emission_energy_multiplier = 6.0
	_led.material_override = led_mat
	_led.position = Vector3(w * 0.5 + 0.06, 0.14, 0.05)
	add_child(_led)
	_led_light = OmniLight3D.new()
	_led_light.light_color = Color(1, 0.15, 0.05)
	_led_light.omni_range = 0.8
	_led_light.light_energy = 0.0
	_led_light.position = _led.position + Vector3(0, 0, 0.05)
	add_child(_led_light)
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.7, 0.1, 0.08)
	wire.roughness = 0.6
	var wire2 := StandardMaterial3D.new()
	wire2.albedo_color = Color(0.1, 0.25, 0.7)
	wire2.roughness = 0.6
	_wire(Vector3(w * 0.5 + 0.03, 0.09, 0.03), Vector3(w * 0.5, 0.02, 0.03), wire)
	_wire(Vector3(w * 0.5 + 0.05, 0.09, 0.03), Vector3(w * 0.5 + 0.01, -0.08, 0.03), wire2)


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.material_override = mat
	m.position = pos
	add_child(m)


func _wire(a: Vector3, b: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.004
	c.bottom_radius = 0.004
	c.height = a.distance_to(b)
	c.radial_segments = 6
	m.mesh = c
	m.material_override = mat
	var y := (b - a).normalized()
	var x := y.cross(Vector3(0, 0, 1)).normalized()
	if x.length() < 0.1:
		x = Vector3.RIGHT
	var z := x.cross(y).normalized()
	m.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	add_child(m)


func _process(delta: float) -> void:
	if detonated:
		return
	t += delta
	# Blink + beep, getting faster towards detonation.
	var remaining := FUSE - t
	var interval := clampf(remaining * 0.22, 0.08, 0.5)
	if t >= _next_beep:
		_next_beep = t + interval
		Sfx.play3d("beep", global_position, -4.0, 1.35, 35.0)
		_led_light.light_energy = 1.5
	_led_light.light_energy = move_toward(_led_light.light_energy, 0.0, delta * 20.0)
	_led.visible = _led_light.light_energy > 0.3 or remaining < 0.4
	if t >= FUSE:
		if _is_server() and Game.inst:
			Game.inst.explosion(global_position + _normal * 0.1, RADIUS, DAMAGE, owner_id, "breach", true)
			Game.inst.noise(global_position, 1.0, owner_id)
		detonate()


func detonate() -> void:
	if detonated:
		return
	detonated = true
	if Game.inst and Game.inst.fx:
		Game.inst.fx.explosion(global_position + _normal * 0.15, "breach")
	queue_free()


func _is_server() -> bool:
	if Game.inst:
		return Game.inst.is_server()
	return Net.is_server()
