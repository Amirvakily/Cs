class_name Viewmodel
extends Node3D
## STUB - visuals worker replaces this file.

func setup(team: int) -> void:
	pass

func set_weapon(id: String) -> void:
	pass

func on_fire() -> void:
	pass

func on_reload(duration: float) -> void:
	pass

func on_throw() -> void:
	pass

func on_knife(alt: bool) -> void:
	pass

func update_vm(delta: float, s: Soldier, look_delta: Vector2) -> void:
	pass

func muzzle_global() -> Vector3:
	return global_position
