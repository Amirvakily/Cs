class_name SoldierModel
extends Node3D
## STUB - visuals worker replaces this file.

func setup(team: int, seed: int, hostile := false) -> void:
	pass

func set_weapon(id: String) -> void:
	pass

func update_anim(delta: float, s: Soldier) -> void:
	pass

func play_fire() -> void:
	pass

func play_reload(duration: float) -> void:
	pass

func play_throw() -> void:
	pass

func play_knife() -> void:
	pass

func die(dir: Vector3) -> void:
	pass

func reset() -> void:
	pass

func muzzle_global() -> Vector3:
	return global_position + Vector3(0, 1.4, 0)

func head_global() -> Vector3:
	return global_position + Vector3(0, 1.62, 0)

func set_first_person(v: bool) -> void:
	pass
