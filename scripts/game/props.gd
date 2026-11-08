class_name Props
extends RefCounted
## Loads CC0 Poly Haven models and fits them into target boxes.

static var _scenes := {}
static var _aabbs := {}


static func scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		_scenes[name] = load("res://assets/models/%s/%s_1k.gltf" % [name, name])
	return _scenes[name]


static func _mesh_aabb(root: Node, xf: Transform3D, acc: Array) -> void:
	for c in root.get_children():
		var cxf := xf
		if c is Node3D:
			cxf = xf * (c as Node3D).transform
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var a := cxf * (c as MeshInstance3D).mesh.get_aabb()
			if acc.is_empty():
				acc.append(a)
			else:
				acc[0] = (acc[0] as AABB).merge(a)
		_mesh_aabb(c, cxf, acc)


## Local-space bounds of a model as authored.
static func aabb(name: String) -> AABB:
	if not _aabbs.has(name):
		var inst := scene(name).instantiate()
		var acc := []
		_mesh_aabb(inst, Transform3D.IDENTITY, acc)
		inst.free()
		_aabbs[name] = acc[0] if not acc.is_empty() else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)
	return _aabbs[name]


## Returns a wrapper whose child model is uniformly scaled to fit `target` (x, y, z) with its
## base at y = 0 and centred on x/z. The wrapper's meta "size" holds the fitted size.
## If `swap_xz` the model is rotated 90 degrees first (to align its long side with X).
static func fit(name: String, target: Vector3, swap_xz := false) -> Node3D:
	var a := aabb(name)
	var sz := a.size
	if swap_xz:
		sz = Vector3(sz.z, sz.y, sz.x)
	var k := minf(target.x / maxf(sz.x, 0.001), minf(target.y / maxf(sz.y, 0.001), target.z / maxf(sz.z, 0.001)))
	var wrapper := Node3D.new()
	var model := scene(name).instantiate() as Node3D
	wrapper.add_child(model)
	var basis := Basis.IDENTITY
	if swap_xz:
		basis = Basis(Vector3.UP, PI * 0.5)
	basis = basis.scaled(Vector3(k, k, k))
	var centre := a.get_center()
	var offset := basis * Vector3(-centre.x, -a.position.y, -centre.z)
	model.transform = Transform3D(basis, offset)
	wrapper.set_meta("size", sz * k)
	return wrapper
