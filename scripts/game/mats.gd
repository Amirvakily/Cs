class_name Mats
extends RefCounted
## World surface materials built from the CC0 Poly Haven texture sets in res://assets/textures.

const KINDS := {
	"ground_desert": {"tex": "dry_ground_rocks", "tile": 4.0, "grime": 0.0, "phys": "dirt"},
	"sandstone": {"tex": "sandstone_blocks_08", "tile": 3.0, "grime": 0.7, "phys": "concrete"},
	"plaster_ext": {"tex": "rough_plaster_brick_04", "tile": 3.0, "grime": 0.6, "phys": "concrete"},
	"plaster_int": {"tex": "clay_plaster", "tile": 3.0, "grime": 0.45, "phys": "concrete"},
	"pavement": {"tex": "red_sandstone_pavement", "tile": 3.0, "grime": 0.0, "phys": "concrete"},
	"wood": {"tex": "weathered_planks", "tile": 2.0, "grime": 0.2, "phys": "wood"},
	"container": {"tex": "container_side", "tile": 2.6, "grime": 0.5, "phys": "metal"},
	"ceiling": {"tex": "concrete_floor_worn_001", "tile": 3.0, "grime": 0.0, "phys": "concrete", "tint": Color(0.55, 0.53, 0.5)},
	"concrete": {"tex": "brushed_concrete", "tile": 3.0, "grime": 0.5, "phys": "concrete"},
	"rust": {"tex": "rusty_corrugated_iron", "tile": 2.0, "grime": 0.3, "phys": "metal"},
	"asphalt": {"tex": "asphalt_02", "tile": 5.0, "grime": 0.0, "wet": 1.0, "phys": "concrete"},
	"sidewalk": {"tex": "concrete_pavers_02", "tile": 2.5, "grime": 0.0, "wet": 0.7, "phys": "concrete"},
	"brick_dark": {"tex": "brick_wall_10", "tile": 3.0, "grime": 0.5, "phys": "concrete"},
	"brick_red": {"tex": "brick_4", "tile": 3.0, "grime": 0.5, "phys": "concrete"},
	"facade": {"tex": "concrete_tile_facade", "tile": 3.0, "grime": 0.3, "phys": "concrete"},
	"lobby": {"tex": "floor_tiles_06", "tile": 3.0, "grime": 0.0, "rough": 0.45, "phys": "concrete"},
	"kitchen": {"tex": "dirty_tiles", "tile": 2.0, "grime": 0.0, "phys": "concrete"},
	"shutter": {"tex": "painted_metal_shutter", "tile": 3.0, "grime": 0.3, "phys": "metal"},
	"metal_plate": {"tex": "metal_plate", "tile": 2.0, "grime": 0.2, "phys": "metal"},
	"block_wall": {"tex": "concrete_block_wall", "tile": 3.0, "grime": 0.5, "phys": "concrete"},
	"trim": {"tex": "brushed_concrete", "tile": 2.0, "grime": 0.0, "phys": "concrete", "tint": Color(0.82, 0.8, 0.76)},
	"crate": {"tex": "weathered_planks", "tile": 1.15, "grime": 0.0, "phys": "wood", "tint": Color(1.15, 1.0, 0.82)},
	"crate_frame": {"tex": "weathered_planks", "tile": 0.8, "grime": 0.0, "phys": "wood", "tint": Color(0.72, 0.6, 0.48)},
}

## Non-textured special surfaces.
static func special(kind: String) -> Material:
	if _cache.has(kind):
		return _cache[kind]
	var m := StandardMaterial3D.new()
	match kind:
		"window":
			m.albedo_color = Color(0.05, 0.06, 0.07)
			m.roughness = 0.08
			m.metallic = 0.6
		"window_lit":
			m.albedo_color = Color(0.9, 0.7, 0.45)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.72, 0.42)
			m.emission_energy_multiplier = 1.6
			m.roughness = 0.2
	_cache[kind] = m
	return m

static var _cache := {}
static var _macro: NoiseTexture2D
static var _shader: Shader


static func macro_tex() -> Texture2D:
	if _macro == null:
		var n := FastNoiseLite.new()
		n.seed = 4242
		n.frequency = 0.008
		n.fractal_octaves = 5
		_macro = NoiseTexture2D.new()
		_macro.width = 512
		_macro.height = 512
		_macro.seamless = true
		_macro.generate_mipmaps = true
		_macro.noise = n
	return _macro


static func world(kind: String) -> Material:
	if kind == "window" or kind == "window_lit":
		return special(kind)
	if _cache.has(kind):
		return _cache[kind]
	if _shader == null:
		_shader = load("res://shaders/world.gdshader")
	var d: Dictionary = KINDS.get(kind, KINDS["concrete"])
	var t: String = d["tex"]
	var base := "res://assets/textures/%s/%s_" % [t, t]
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("albedo_tex", load(base + "diff_1k.jpg"))
	m.set_shader_parameter("normal_tex", load(base + "nor_gl_1k.jpg"))
	m.set_shader_parameter("arm_tex", load(base + "arm_1k.jpg"))
	m.set_shader_parameter("macro_tex", macro_tex())
	m.set_shader_parameter("tile", float(d["tile"]))
	m.set_shader_parameter("grime", float(d.get("grime", 0.4)))
	m.set_shader_parameter("wet", float(d.get("wet", 0.0)))
	m.set_shader_parameter("rough_mul", float(d.get("rough", 1.0)))
	var tint: Color = d.get("tint", Color(1, 1, 1))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_cache[kind] = m
	return m


static func phys(kind: String) -> String:
	if kind.begins_with("window"):
		return "glass"
	return KINDS.get(kind, KINDS["concrete"])["phys"]
