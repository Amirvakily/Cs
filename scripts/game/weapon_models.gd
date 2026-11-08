class_name WeaponModels
extends RefCounted
## STUB - visuals worker replaces this file.

static func build(id: String) -> Node3D:
	var n := Node3D.new()
	var m := Marker3D.new()
	m.name = "Muzzle"
	m.position = Vector3(0, 0.05, -0.5)
	n.add_child(m)
	return n
