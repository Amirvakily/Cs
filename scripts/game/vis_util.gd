class_name VisUtil
extends RefCounted
## Shared helpers for procedural character / weapon meshes: a primitive batcher that merges
## many primitives (with per-part vertex colours) into one surface per material, plus a small
## PBR material library and generated detail textures.

static var _mats := {}
static var _tex := {}


## Accumulates transformed primitive geometry for one material.
class Batch:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func add(prim: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arr := prim.get_mesh_arrays()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		var has_uv := uv.size() == v.size()
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			uvs.append(uv[i] if has_uv else Vector2.ZERO)
			cols.append(col)
		for i in ind.size():
			idx.append(base + ind[i])

	func is_empty() -> bool:
		return verts.is_empty()

	func commit(mesh: ArrayMesh, mat: Material) -> void:
		if is_empty():
			return
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Builds a multi-material mesh out of primitives. Material keys map to VisUtil.mat(key).
class Builder:
	var batches := {}
	var base := Transform3D.IDENTITY

	func _b(key: String) -> Batch:
		if not batches.has(key):
			batches[key] = Batch.new()
		return batches[key]

	func _xf(pos: Vector3, rot_deg: Vector3, scl := Vector3.ONE) -> Transform3D:
		var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
		if scl != Vector3.ONE:
			b = b * Basis.from_scale(scl)
		return base * Transform3D(b, pos)

	func box(key: String, size: Vector3, pos: Vector3, rot := Vector3.ZERO, col := Color.WHITE) -> void:
		var m := BoxMesh.new()
		m.size = size
		_b(key).add(m, _xf(pos, rot), col)

	## Cylinder along local Y (rotate (90,0,0) to lay it along Z).
	func cyl(key: String, r: float, h: float, pos: Vector3, rot := Vector3.ZERO, col := Color.WHITE, r_top := -1.0, segs := 14, scl := Vector3.ONE) -> void:
		var m := CylinderMesh.new()
		m.bottom_radius = r
		m.top_radius = r if r_top < 0.0 else r_top
		m.height = h
		m.radial_segments = segs
		m.rings = 1
		_b(key).add(m, _xf(pos, rot, scl), col)

	func sphere(key: String, r: float, pos: Vector3, col := Color.WHITE, scl := Vector3.ONE, rot := Vector3.ZERO, hemi := false, segs := 16) -> void:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * (1.0 if hemi else 2.0)
		m.is_hemisphere = hemi
		m.radial_segments = segs
		m.rings = maxi(4, segs / 2)
		_b(key).add(m, _xf(pos, rot, scl), col)

	## Capsule along local Y.
	func capsule(key: String, r: float, h: float, pos: Vector3, rot := Vector3.ZERO, col := Color.WHITE, scl := Vector3.ONE) -> void:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0 + 0.001)
		m.radial_segments = 14
		m.rings = 4
		_b(key).add(m, _xf(pos, rot, scl), col)

	func prism(key: String, size: Vector3, pos: Vector3, rot := Vector3.ZERO, col := Color.WHITE, ltr := 0.5) -> void:
		var m := PrismMesh.new()
		m.size = size
		m.left_to_right = ltr
		_b(key).add(m, _xf(pos, rot), col)

	func torus(key: String, inner: float, outer: float, pos: Vector3, rot := Vector3.ZERO, col := Color.WHITE) -> void:
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 16
		m.ring_segments = 8
		_b(key).add(m, _xf(pos, rot), col)

	func is_empty() -> bool:
		for b in batches.values():
			if not b.is_empty():
				return false
		return true

	## Commits all batches into a single ArrayMesh (one surface per material key).
	func build(mat_override := {}) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		var keys := batches.keys()
		keys.sort()
		for k in keys:
			var m: Material = mat_override.get(k, VisUtil.mat(k))
			batches[k].commit(mesh, m)
		return mesh


## Material library. Albedo comes from vertex colours (sRGB) multiplied by a subtle grime texture.
static func mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_texture = grime_tex(true)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(6, 6, 6)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match key:
		"metal":
			m.metallic = 0.75
			m.roughness = 0.42
			m.roughness_texture = rough_tex()
		"steel":
			m.metallic = 0.95
			m.roughness = 0.3
			m.albedo_texture = null
		"polymer":
			m.roughness = 0.68
		"parker":
			m.metallic = 0.55
			m.roughness = 0.55
			m.roughness_texture = rough_tex()
		"rubber":
			m.roughness = 0.88
			m.albedo_texture = grime_tex(false)
		"wood":
			m.roughness = 0.5
			m.albedo_texture = wood_tex()
			m.uv1_scale = Vector3(3, 3, 3)
		"glass":
			m.metallic = 0.6
			m.roughness = 0.05
			m.albedo_texture = null
			m.emission_enabled = true
			m.emission = Color(0.05, 0.12, 0.16)
			m.emission_energy_multiplier = 0.6
		"lens_red":
			m.albedo_texture = null
			m.emission_enabled = true
			m.emission = Color(1.0, 0.12, 0.08)
			m.emission_energy_multiplier = 3.0
		"emit_red":
			m.albedo_texture = null
			m.emission_enabled = true
			m.emission = Color(1.0, 0.1, 0.05)
			m.emission_energy_multiplier = 4.0
		"emit_green":
			m.albedo_texture = null
			m.emission_enabled = true
			m.emission = Color(0.2, 1.0, 0.3)
			m.emission_energy_multiplier = 3.0
		"brass":
			m.metallic = 0.9
			m.roughness = 0.3
		"fabric_atk", "fabric_def", "fabric_hostile":
			m.roughness = 0.95
			m.albedo_texture = camo_tex(key)
			m.uv1_scale = Vector3(6.5, 6.5, 6.5)
			m.normal_enabled = true
			m.normal_texture = weave_tex()
			m.normal_scale = 0.6
		"nylon":
			m.roughness = 0.85
			m.normal_enabled = true
			m.normal_texture = weave_tex()
			m.normal_scale = 0.8
		"skin":
			m.albedo_texture = grime_tex(true)
			m.uv1_scale = Vector3(12, 12, 12)
			m.roughness = 0.55
			m.rim_enabled = true
			m.rim = 0.25
			m.rim_tint = 0.6
		_:
			m.roughness = 0.7
	_mats[key] = m
	return m


static func _noise_tex(key: String, freq: float, octaves: int, ramp: Gradient, normal := false, size := 256) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var n := FastNoiseLite.new()
	n.seed = hash(key)
	n.frequency = freq
	n.fractal_octaves = octaves
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = 4.0
	elif ramp:
		t.color_ramp = ramp
	t.generate_mipmaps = true
	_tex[key] = t
	return t


static func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


static func grime_tex(light := true) -> Texture2D:
	if light:
		return _noise_tex("grime_l", 0.03, 5, _ramp(Color(0.88, 0.87, 0.86), Color(1, 1, 1)))
	return _noise_tex("grime", 0.03, 5, _ramp(Color(0.74, 0.73, 0.71), Color(1, 1, 1)))


static func rough_tex() -> Texture2D:
	return _noise_tex("rough", 0.05, 4, _ramp(Color(0.55, 0.55, 0.55), Color(1, 1, 1)))


static func weave_tex() -> Texture2D:
	return _noise_tex("weave", 0.35, 2, null, true, 128)


static func wood_tex() -> Texture2D:
	if _tex.has("wood"):
		return _tex["wood"]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.04
	for y in s:
		for x in s:
			var g := sin(float(x) * 0.35 + n.get_noise_2d(x * 0.3, y * 3.0) * 6.0) * 0.5 + 0.5
			var v := lerpf(0.8, 1.0, g) * lerpf(0.92, 1.0, n.get_noise_2d(x * 4.0, y * 0.5) * 0.5 + 0.5)
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex["wood"] = t
	return t


## Camouflage pattern textures (white-balanced; tinted further by vertex colour).
static func camo_tex(key: String) -> Texture2D:
	if _tex.has(key):
		return _tex[key]
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGB8)
	var n1 := FastNoiseLite.new()
	n1.seed = hash(key)
	n1.frequency = 0.035
	n1.fractal_octaves = 2
	var n2 := FastNoiseLite.new()
	n2.seed = hash(key) + 11
	n2.frequency = 0.06
	n2.fractal_octaves = 2
	var cols: Array
	match key:
		"fabric_atk":
			cols = [Color(0.7, 0.62, 0.48), Color(0.62, 0.53, 0.39), Color(0.5, 0.41, 0.3), Color(0.76, 0.69, 0.55)]
		"fabric_hostile":
			cols = [Color(0.55, 0.53, 0.42), Color(0.43, 0.42, 0.32), Color(0.32, 0.3, 0.23), Color(0.62, 0.58, 0.47)]
		_:
			cols = [Color(0.27, 0.29, 0.33), Color(0.2, 0.22, 0.26), Color(0.15, 0.16, 0.19), Color(0.33, 0.35, 0.38)]
	for y in s:
		for x in s:
			# Sample on a torus so the pattern tiles seamlessly.
			var ax := float(x) / s * TAU
			var ay := float(y) / s * TAU
			var r := 30.0
			var px := cos(ax) * r
			var py := sin(ax) * r
			var pz := cos(ay) * r
			var pw := sin(ay) * r
			var a := n1.get_noise_3d(px + pw * 0.5, py, pz)
			var b := n2.get_noise_3d(px, py + pw * 0.5, pz + 40.0)
			var c: Color = cols[0]
			if a > 0.18:
				c = cols[1]
			if b > 0.25:
				c = cols[2]
			if a < -0.3:
				c = cols[3]
			var j := 1.0 + n2.get_noise_3d(px * 6.0, py * 6.0, pz * 6.0) * 0.05
			img.set_pixel(x, y, Color(c.r * j, c.g * j, c.b * j))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


## Two-bone IK: returns the joint (elbow/knee) position for a chain root→joint→end.
static func ik_joint(root: Vector3, target: Vector3, a: float, b: float, pole: Vector3) -> Vector3:
	var d := target - root
	var dist := clampf(d.length(), 0.01, a + b - 0.0005)
	var dir := d.normalized() if d.length() > 0.0001 else Vector3.DOWN
	var cos_a := clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
	var ang := acos(cos_a)
	var p := pole - dir * pole.dot(dir)
	if p.length() < 0.0001:
		p = Vector3.FORWARD.cross(dir)
	p = p.normalized()
	return root + (dir * cos(ang) + p * sin(ang)) * a


## Transform for a limb segment whose mesh hangs along local -Y from `start` toward `end`.
static func seg_xf(start: Vector3, end: Vector3, side: Vector3) -> Transform3D:
	var y := start - end
	if y.length() < 0.0001:
		y = Vector3.UP
	y = y.normalized()
	var x := side - y * side.dot(y)
	if x.length() < 0.0001:
		x = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
	x = x.normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x, y, z), start)
