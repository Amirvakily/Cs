class_name Tex
extends RefCounted
## Procedural textures & materials. Everything is generated from noise + patterns
## and cached, so maps need no image assets.

const S := 256
static var _mats := {}
static var _tex := {}


static func _noise(seed: int, freq: float, octaves := 4, cellular := false) -> PackedByteArray:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = octaves
	n.noise_type = FastNoiseLite.TYPE_CELLULAR if cellular else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var img: Image = n.get_seamless_image(S, S, false, false, 0.1, true)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


static func _make(rgb: PackedByteArray, height: PackedByteArray, bump := 3.0) -> Array:
	var albedo := Image.create_from_data(S, S, false, Image.FORMAT_RGB8, rgb)
	albedo.generate_mipmaps()
	var h := Image.create_from_data(S, S, false, Image.FORMAT_L8, height)
	h.convert(Image.FORMAT_RGBA8)
	h.bump_map_to_normal_map(bump)
	h.generate_mipmaps()
	return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(h)]


static func _put(rgb: PackedByteArray, i: int, c: Color) -> void:
	rgb[i * 3] = clampi(int(c.r * 255.0), 0, 255)
	rgb[i * 3 + 1] = clampi(int(c.g * 255.0), 0, 255)
	rgb[i * 3 + 2] = clampi(int(c.b * 255.0), 0, 255)


## Generates [albedo, normal] textures for a named surface.
static func get_textures(kind: String) -> Array:
	if _tex.has(kind):
		return _tex[kind]
	var rgb := PackedByteArray()
	rgb.resize(S * S * 3)
	var hgt := PackedByteArray()
	hgt.resize(S * S)
	var n1 := _noise(hash(kind), 0.012, 5)
	var n2 := _noise(hash(kind) + 7, 0.06, 3)
	var bump := 3.0
	match kind:
		"sand":
			for i in S * S:
				var a := n1[i] / 255.0
				var b := n2[i] / 255.0
				var c := Color(0.62, 0.5, 0.35).lerp(Color(0.74, 0.62, 0.45), a)
				c = c.darkened(0.12 * b)
				if b > 0.82:
					c = c.darkened(0.25)
				_put(rgb, i, c)
				hgt[i] = int(a * 120 + b * 80)
			bump = 2.0
		"sandstone":
			for y in S:
				for x in S:
					var i := y * S + x
					var row := y / 32
					var ox := (row % 2) * 32
					var bx := (x + ox) % 64
					var by := y % 32
					var mortar := bx < 3 or by < 3
					var a := n1[i] / 255.0
					var b := n2[i] / 255.0
					var tint := float(hash(Vector2i((x + ox) / 64, row)) % 100) / 100.0
					var c := Color(0.72, 0.58, 0.4).lerp(Color(0.6, 0.47, 0.32), tint * 0.6 + a * 0.4)
					c = c.darkened(b * 0.15)
					var h := 170 + int(a * 60)
					if mortar:
						c = Color(0.5, 0.42, 0.32).darkened(b * 0.2)
						h = 60
					_put(rgb, i, c)
					hgt[i] = h
			bump = 4.0
		"plaster":
			for i in S * S:
				var a := n1[i] / 255.0
				var b := n2[i] / 255.0
				var c := Color(0.78, 0.74, 0.66).lerp(Color(0.62, 0.57, 0.5), a)
				if b > 0.7:
					c = c.darkened((b - 0.7) * 0.8)
				_put(rgb, i, c)
				hgt[i] = int(a * 90 + b * 40)
			bump = 1.5
		"tiles":
			for y in S:
				for x in S:
					var i := y * S + x
					var grout := (x % 64) < 3 or (y % 64) < 3
					var a := n1[i] / 255.0
					var t := float(hash(Vector2i(x / 64, y / 64)) % 100) / 100.0
					var c := Color(0.6, 0.33, 0.22).lerp(Color(0.7, 0.42, 0.3), t).darkened(a * 0.2)
					if grout:
						c = Color(0.35, 0.3, 0.26)
					_put(rgb, i, c)
					hgt[i] = 40 if grout else 200
			bump = 3.0
		"wood", "crate":
			for y in S:
				for x in S:
					var i := y * S + x
					var pw := 42
					var plank := x / pw
					var gap := (x % pw) < 2
					var a := n1[i] / 255.0
					var t := float(hash(plank) % 100) / 100.0
					var grain := sin(float(y) * 0.11 + a * 9.0 + t * 20.0) * 0.5 + 0.5
					var c := Color(0.45, 0.31, 0.18).lerp(Color(0.6, 0.43, 0.26), grain * 0.6 + t * 0.4)
					c = c.darkened(n2[i] / 255.0 * 0.2)
					var h := 150 + int(grain * 50)
					if kind == "crate":
						var border := x < 18 or x > S - 19 or y < 18 or y > S - 19
						var diag := absi(x - y) < 10 or absi(x - (S - y)) < 10
						if border or diag:
							c = c.lightened(0.08)
							h = 230
					if gap:
						c = Color(0.15, 0.1, 0.06)
						h = 30
					_put(rgb, i, c)
					hgt[i] = h
			bump = 3.0
		"metal_red", "metal_blue", "metal_green", "metal_grey":
			var base := {"metal_red": Color(0.5, 0.16, 0.12), "metal_blue": Color(0.14, 0.26, 0.42),
				"metal_green": Color(0.2, 0.32, 0.2), "metal_grey": Color(0.38, 0.39, 0.4)}[kind] as Color
			for y in S:
				for x in S:
					var i := y * S + x
					var ridge := sin(float(x) / S * TAU * 8.0)
					var a := n1[i] / 255.0
					var b := n2[i] / 255.0
					var c := base.lerp(base.lightened(0.2), ridge * 0.5 + 0.5)
					var rust := clampf((a - 0.55) * 3.0, 0.0, 1.0) * b
					c = c.lerp(Color(0.42, 0.24, 0.12), rust)
					_put(rgb, i, c)
					hgt[i] = int(128 + ridge * 100)
			bump = 4.0
		"concrete":
			for i in S * S:
				var a := n1[i] / 255.0
				var b := n2[i] / 255.0
				var c := Color(0.5, 0.5, 0.48).lerp(Color(0.38, 0.38, 0.37), a)
				c = c.darkened(clampf(b - 0.6, 0.0, 1.0) * 0.7)
				_put(rgb, i, c)
				hgt[i] = int(a * 70 + b * 60)
			bump = 1.8
		"asphalt":
			var n3 := _noise(91, 0.25, 2)
			for i in S * S:
				var a := n1[i] / 255.0
				var g := n3[i] / 255.0
				var c := Color(0.12, 0.12, 0.13).lerp(Color(0.2, 0.2, 0.21), g)
				c = c.darkened(a * 0.4)
				_put(rgb, i, c)
				hgt[i] = int(g * 160)
			bump = 2.0
		"brick":
			for y in S:
				for x in S:
					var i := y * S + x
					var row := y / 21
					var ox := (row % 2) * 24
					var bx := (x + ox) % 48
					var by := y % 21
					var mortar := bx < 3 or by < 3
					var a := n1[i] / 255.0
					var t := float(hash(Vector2i((x + ox) / 48, row)) % 100) / 100.0
					var c := Color(0.42, 0.18, 0.13).lerp(Color(0.55, 0.27, 0.18), t).darkened(a * 0.25)
					var h := 190
					if mortar:
						c = Color(0.3, 0.28, 0.26).darkened(a * 0.3)
						h = 50
					_put(rgb, i, c)
					hgt[i] = h
			bump = 4.0
		"carpet":
			for y in S:
				for x in S:
					var i := y * S + x
					var cx := (x % 64) - 32
					var cy := (y % 64) - 32
					var d := absi(cx) + absi(cy)
					var c := Color(0.32, 0.05, 0.08)
					if d < 20 and d > 14:
						c = Color(0.75, 0.55, 0.15)
					elif d < 8:
						c = Color(0.1, 0.18, 0.35)
					elif (x / 8 + y / 8) % 2 == 0 and d > 26:
						c = Color(0.26, 0.04, 0.07)
					c = c.darkened(n2[i] / 255.0 * 0.25)
					_put(rgb, i, c)
					hgt[i] = 120 + int(n2[i] / 4)
			bump = 1.0
		"marble":
			for i in S * S:
				var a := n1[i] / 255.0
				var x := i % S
				var y := i / S
				var vein := absf(sin(float(x + y) * 0.03 + a * 12.0))
				var c := Color(0.86, 0.84, 0.8).lerp(Color(0.55, 0.52, 0.5), pow(1.0 - vein, 8.0))
				if (x % 128) < 2 or (y % 128) < 2:
					c = Color(0.3, 0.28, 0.27)
				_put(rgb, i, c)
				hgt[i] = 200 if (x % 128) >= 2 and (y % 128) >= 2 else 60
			bump = 1.0
		_:
			for i in S * S:
				_put(rgb, i, Color(0.5, 0.5, 0.5))
				hgt[i] = 128
	var r := _make(rgb, hgt, bump)
	_tex[kind] = r
	return r


## Returns a cached StandardMaterial3D for a surface kind.
static func mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	var scale := 0.5 # texture repeats every 2 m
	var rough := 0.9
	var metal := 0.0
	var tex_kind := kind
	match kind:
		"sand":
			scale = 0.2
		"sandstone":
			scale = 0.33
		"plaster":
			scale = 0.25
		"tiles":
			scale = 0.4
		"wood":
			scale = 0.6
			rough = 0.8
		"crate":
			scale = 0.55
			rough = 0.8
		"metal_red", "metal_blue", "metal_green", "metal_grey":
			scale = 0.33
			rough = 0.55
			metal = 0.5
		"concrete":
			scale = 0.25
		"asphalt":
			scale = 0.2
			rough = 0.45
		"brick":
			scale = 0.4
		"carpet":
			scale = 0.5
			rough = 1.0
		"marble":
			scale = 0.25
			rough = 0.2
	var t := get_textures(tex_kind)
	m.albedo_texture = t[0]
	m.normal_enabled = true
	m.normal_texture = t[1]
	m.normal_scale = 1.0
	m.roughness = rough
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[kind] = m
	return m


## Flat colored material (characters, weapons, props).
static func flat(c: Color, rough := 0.8, metal := 0.0, emissive := 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%.2f_%.2f" % [c.to_html(), rough, metal, emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	_mats[key] = m
	return m


static func unshaded(c: Color, additive := false) -> StandardMaterial3D:
	var key := "unshaded_%s_%s" % [c.to_html(), str(additive)]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m
