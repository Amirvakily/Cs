class_name BombProp
extends Node3D
## Planted demolition charge: wrapped explosive blocks, wiring, a keypad/timer with
## glowing digits and a red LED that blinks and beeps faster as time runs out.

var time_left := 40.0
var total := 40.0
var _beep_t := 0.0
var _led: MeshInstance3D
var _light: OmniLight3D
var _screen: Label3D
var _defusing := false
var _exploded := false
var _scramble_t := 0.0


func _ready() -> void:
	total = Cfg.BOMB_TIME
	if time_left > total:
		time_left = total
	_build()


func set_time_left(t: float) -> void:
	time_left = t


## Optional: shows a green defuse indicator on the keypad.
func set_defusing(v: bool) -> void:
	_defusing = v


func _build() -> void:
	var explosive := StandardMaterial3D.new()
	explosive.albedo_color = Color(0.42, 0.4, 0.3)
	explosive.roughness = 0.85
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.2, 0.22, 0.17)
	wrap.roughness = 0.7
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.06, 0.06, 0.06)
	tape.roughness = 0.45
	var case_mat := StandardMaterial3D.new()
	case_mat.albedo_color = Color(0.14, 0.14, 0.15)
	case_mat.roughness = 0.35
	case_mat.metallic = 0.4
	var screen_bg := StandardMaterial3D.new()
	screen_bg.albedo_color = Color(0.02, 0.02, 0.02)
	screen_bg.roughness = 0.1
	# Explosive blocks
	for i in 4:
		var x := -0.105 + i * 0.07
		_box(Vector3(0.062, 0.06, 0.24), Vector3(x, 0.03, 0.0), explosive if i % 2 == 0 else wrap)
	# Tape straps
	for z in [-0.08, 0.08]:
		_box(Vector3(0.3, 0.065, 0.03), Vector3(0, 0.032, z), tape)
	# Timer / keypad module on top
	_box(Vector3(0.16, 0.035, 0.11), Vector3(0, 0.08, -0.01), case_mat)
	_box(Vector3(0.12, 0.004, 0.04), Vector3(0, 0.0995, -0.035), screen_bg)
	# Keypad buttons
	var btn := StandardMaterial3D.new()
	btn.albedo_color = Color(0.5, 0.5, 0.48)
	btn.roughness = 0.5
	for r in 3:
		for c in 4:
			_box(Vector3(0.018, 0.006, 0.014), Vector3(-0.04 + c * 0.027, 0.1, 0.0 + r * 0.019), btn)
	_screen = Label3D.new()
	_screen.text = "ARMED"
	_screen.font_size = 48
	_screen.pixel_size = 0.0006
	_screen.modulate = Color(3.0, 0.25, 0.15)
	_screen.outline_size = 0
	_screen.shaded = false
	_screen.double_sided = false
	_screen.rotation = Vector3(-PI * 0.5, 0, 0)
	_screen.position = Vector3(0, 0.102, -0.035)
	add_child(_screen)
	# LED + light
	_led = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.008
	s.height = 0.016
	_led.mesh = s
	var led_mat := StandardMaterial3D.new()
	led_mat.albedo_color = Color(1, 0.1, 0.05)
	led_mat.emission_enabled = true
	led_mat.emission = Color(1, 0.08, 0.04)
	led_mat.emission_energy_multiplier = 8.0
	_led.material_override = led_mat
	_led.position = Vector3(0.065, 0.1, -0.05)
	add_child(_led)
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.12, 0.06)
	_light.omni_range = 1.4
	_light.light_energy = 0.0
	_light.position = Vector3(0.06, 0.2, -0.05)
	add_child(_light)
	# Wires looping from the module into the blocks
	var colors := [Color(0.75, 0.1, 0.08), Color(0.1, 0.3, 0.75), Color(0.85, 0.75, 0.1)]
	for i in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = colors[i]
		m.roughness = 0.55
		var a := Vector3(-0.07 + i * 0.012, 0.09, 0.04)
		var mid := Vector3(-0.12 + i * 0.02, 0.1, 0.09)
		var b := Vector3(-0.105 + i * 0.07, 0.06, 0.1)
		_wire(a, mid, m)
		_wire(mid, b, m)


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
	c.top_radius = 0.003
	c.bottom_radius = 0.003
	c.height = maxf(0.001, a.distance_to(b))
	c.radial_segments = 6
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	var y := (b - a).normalized()
	var ref := Vector3(0, 0, 1) if absf(y.z) < 0.9 else Vector3.RIGHT
	var x := y.cross(ref).normalized()
	var z := x.cross(y).normalized()
	m.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	add_child(m)


func _process(delta: float) -> void:
	if _exploded:
		return
	time_left = maxf(0.0, time_left - delta)
	_beep_t -= delta
	if time_left <= 0.0:
		_led.visible = true
		_light.light_energy = 1.2
		return
	if _beep_t <= 0.0:
		# 1 beep/s at the start, accelerating to ~10/s at the end.
		var k := clampf(time_left / maxf(total, 1.0), 0.0, 1.0)
		_beep_t = lerpf(0.1, 1.0, pow(k, 1.3))
		Sfx.play3d("beep", global_position, -2.0 if time_left > 10.0 else 0.0, 1.0, 70.0)
		_light.light_energy = 0.9
	_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 6.0)
	_led.visible = _light.light_energy > 0.15
	if _defusing:
		_screen.modulate = Color(0.3, 2.5, 0.4)
		_screen.text = "DEFUSE"
	else:
		_screen.modulate = Color(3.0, 0.25, 0.15)
		# Scrambled read-out so the exact time isn't given away.
		_scramble_t -= delta
		if fmod(time_left, 2.0) > 1.0:
			_screen.text = "ARMED"
		elif _scramble_t <= 0.0:
			_scramble_t = 0.12
			_screen.text = "%02d%02d" % [randi() % 100, randi() % 100]
