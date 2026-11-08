extends Node3D
## Dev tool: builds a map and saves screenshots from preset camera spots.
## Usage: godot --path . res://tools/world_shots.tscn -- <map> <out_dir> [quality]

var shots := []
var idx := 0
var frames := 0
var out_dir := ""
var cam: Camera3D
var world: World


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id: String = args[0] if args.size() > 0 else "outpost"
	out_dir = args[1] if args.size() > 1 else "user://"
	if args.size() > 2:
		Cfg.settings["quality"] = int(args[2])
	Sfx.wait_ready()
	world = World.new()
	add_child(world)
	var t0 := Time.get_ticks_msec()
	world.build(map_id, true)
	print("build ms: ", Time.get_ticks_msec() - t0)
	cam = Camera3D.new()
	cam.fov = 80
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	var w := world.cols * Cfg.CELL
	var h := world.rows * Cfg.CELL
	# (position, look target)
	shots = [
		[Vector3(w * 0.5, 45, h * 1.02), Vector3(w * 0.5, 0, h * 0.45)],
		[world.cell_to_world(Vector2i(19, 28)) + Vector3(0, 1.7, 0), world.cell_to_world(Vector2i(19, 12)) + Vector3(0, 1.5, 0)],
		[world.cell_to_world(Vector2i(4, 9)) + Vector3(0, 1.7, 0), world.cell_to_world(Vector2i(8, 2)) + Vector3(0, 1.0, 0)],
		[world.cell_to_world(Vector2i(34, 20)) + Vector3(0, 1.7, 0), world.cell_to_world(Vector2i(34, 11)) + Vector3(0, 1.2, 0)],
		[world.cell_to_world(Vector2i(20, 6)) + Vector3(0, 1.7, 0), world.cell_to_world(Vector2i(10, 3)) + Vector3(0, 1.2, 0)],
	]
	world.nav_ready.connect(func(): print("nav ready"))
	_apply()


func _apply() -> void:
	var s: Array = shots[idx]
	cam.global_position = s[0]
	cam.look_at(s[1])


func _process(_d: float) -> void:
	frames += 1
	if frames < 40:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%d.png" % [out_dir, world.map_id, idx])
	print("saved shot ", idx)
	idx += 1
	frames = 0
	if idx >= shots.size():
		var p := world.get_nav_path(world.spawn_points[0][0].origin, world.site_center("A"))
		print("nav path A points: ", p.size(), " baked: ", world.nav_baked)
		get_tree().quit()
		return
	_apply()
