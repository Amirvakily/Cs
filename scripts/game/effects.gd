class_name Effects
extends Node3D
## STUB - fx worker replaces this file.

func shot(origin: Vector3, ends: PackedVector3Array, weapon_id: String, from_local_view: bool) -> void:
	pass

func muzzle_flash(pos: Vector3, dir: Vector3, weapon_id: String) -> void:
	pass

func impact(pos: Vector3, normal: Vector3, mat: String) -> void:
	pass

func blood(pos: Vector3, dir: Vector3) -> void:
	pass

func explosion(pos: Vector3, kind: String) -> void:
	pass

func smoke_cloud(pos: Vector3, radius: float, duration: float) -> void:
	pass

func flash_burst(pos: Vector3) -> void:
	pass

func debris(pos: Vector3, dir: Vector3, mat: String) -> void:
	pass

func shell(pos: Vector3, dir: Vector3) -> void:
	pass
