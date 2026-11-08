class_name World
extends Node3D
## STUB (interface only) - core logic is being implemented.

var data := {}
var theme := "desert"
var cols := 0
var rows := 0
var grid := PackedStringArray()
var sites := {}
var spawn_points := {0: [], 1: []}
var bounds := AABB()
var breakables := {}


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x * Cfg.CELL + Cfg.CELL * 0.5, floor_height(c), c.y * Cfg.CELL + Cfg.CELL * 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Cfg.CELL), floori(p.z / Cfg.CELL))


func floor_height(c: Vector2i) -> float:
	return 0.0


func is_blocked(c: Vector2i) -> bool:
	return false


func site_center(name: String) -> Vector3:
	return Vector3.ZERO


func in_site(pos: Vector3) -> String:
	return ""


func in_spawn(pos: Vector3, team: int) -> bool:
	return false


func get_nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	return PackedVector3Array([from, to])


func random_nav_point(center := Vector3.INF, radius := 0.0) -> Vector3:
	return Vector3.ZERO


func radar_image() -> Image:
	return Image.create(8, 8, false, Image.FORMAT_RGBA8)
