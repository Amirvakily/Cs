class_name Door
extends StaticBody3D
## Wooden door (opens/closes, can be breached) or barricade (planks that break apart).

var id := 0
var kind := "door" # "door" | "barricade"
var is_open := false
var broken := false
var health := 100.0
var width := 1.7
var height := 2.3
var span_x := true
var _pivot: Node3D
var _shape: CollisionShape3D
var _target_angle := 0.0
var _angle := 0.0


func build(p_id: int, p_kind: String, p_width: float, p_height: float, p_span_x: bool) -> void:
	id = p_id
	kind = p_kind
	width = p_width
	height = p_height
	span_x = p_span_x
	collision_layer = Cfg.L_DYNAMIC
	collision_mask = 0
	set_meta("mat", "wood")
	set_meta("breakable_id", id)
	health = 60.0 if kind == "door" else 90.0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.12) if span_x else Vector3(0.12, height, width)
	_shape.shape = box
	_shape.position = Vector3(0, height * 0.5, 0)
	add_child(_shape)
	_pivot = Node3D.new()
	add_child(_pivot)
	var wood := Mats.world("wood")
	if kind == "door":
		# Hinge at the -side of the span; leaf extends toward +side.
		var hinge := Vector3(-width * 0.5, 0, 0) if span_x else Vector3(0, 0, -width * 0.5)
		_pivot.position = hinge
		var leaf := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(width - 0.02, height - 0.02, 0.07)
		leaf.mesh = bm
		leaf.material_override = wood
		leaf.position = Vector3(width * 0.5, height * 0.5, 0)
		var holder := Node3D.new()
		holder.rotation.y = 0.0 if span_x else -PI * 0.5
		_pivot.add_child(holder)
		holder.add_child(leaf)
		# Frame panels and handle for detail.
		for side in [-1.0, 1.0]:
			for py in [0.6, 1.65]:
				var panel := MeshInstance3D.new()
				var pm := BoxMesh.new()
				pm.size = Vector3(width * 0.36, 0.7, 0.02)
				panel.mesh = pm
				panel.material_override = wood
				panel.position = Vector3(width * 0.5 + side * width * 0.2, py, side * 0.0 + 0.045 * 1.0)
				holder.add_child(panel)
				var panel2 := panel.duplicate() as MeshInstance3D
				panel2.position.z = -0.045
				holder.add_child(panel2)
		var handle := MeshInstance3D.new()
		var hm := CylinderMesh.new()
		hm.top_radius = 0.025
		hm.bottom_radius = 0.025
		hm.height = 0.18
		handle.mesh = hm
		handle.material_override = Tex.flat(Color(0.55, 0.5, 0.42), 0.35, 0.9)
		handle.rotation.x = PI * 0.5
		handle.position = Vector3(width - 0.15, 1.0, 0)
		holder.add_child(handle)
	else:
		var holder := Node3D.new()
		holder.rotation.y = 0.0 if span_x else PI * 0.5
		_pivot.add_child(holder)
		var rng := RandomNumberGenerator.new()
		rng.seed = id * 7919
		for i in 6:
			var plank := MeshInstance3D.new()
			var pm := BoxMesh.new()
			pm.size = Vector3(width + 0.25, 0.22, 0.05)
			plank.mesh = pm
			plank.material_override = wood
			plank.position = Vector3(0, 0.25 + i * 0.36, rng.randf_range(-0.03, 0.03))
			plank.rotation.z = rng.randf_range(-0.12, 0.12)
			holder.add_child(plank)
		for sx in [-0.55, 0.55]:
			var post := MeshInstance3D.new()
			var po := BoxMesh.new()
			po.size = Vector3(0.14, height, 0.06)
			post.mesh = po
			post.material_override = wood
			post.position = Vector3(sx, height * 0.5, 0.06)
			holder.add_child(post)


func _process(delta: float) -> void:
	if kind != "door" or broken:
		return
	if absf(_angle - _target_angle) > 0.001:
		_angle = move_toward(_angle, _target_angle, delta * 4.5)
		_pivot.rotation.y = _angle


## Opens away from `from_pos` (or closes).
func set_open(v: bool, from_pos := Vector3.INF) -> void:
	if kind != "door" or broken or v == is_open:
		return
	is_open = v
	if v:
		var away := 1.0
		if from_pos != Vector3.INF:
			var rel := from_pos - global_position
			var side := rel.z if span_x else rel.x
			away = -1.0 if side > 0.0 else 1.0
			if not span_x:
				away = -away
		_target_angle = away * deg_to_rad(100.0)
		Sfx.play3d("door_open", global_position + Vector3(0, 1.2, 0), -4.0)
	else:
		_target_angle = 0.0
		Sfx.play3d("door_close", global_position + Vector3(0, 1.2, 0), -4.0)
	_shape.set_deferred("disabled", v)


func set_broken(dir := Vector3.ZERO) -> void:
	if broken:
		return
	broken = true
	is_open = true
	_shape.set_deferred("disabled", true)
	_pivot.visible = false
	Sfx.play3d("wood_break", global_position + Vector3(0, 1.2, 0), 2.0)
	if Game.inst and Game.inst.fx:
		Game.inst.fx.debris(global_position + Vector3(0, 1.1, 0), dir, "wood")


func restore() -> void:
	broken = false
	is_open = false
	_angle = 0.0
	_target_angle = 0.0
	health = 60.0 if kind == "door" else 90.0
	_pivot.visible = true
	_pivot.rotation.y = 0.0
	_shape.set_deferred("disabled", false)


func blocks_path() -> bool:
	return not broken and not is_open
