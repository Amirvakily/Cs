class_name BreachCharge
extends Node3D
## STUB - fx worker replaces this file.
var net_id := 0

func setup(p_net_id: int, owner_id: String, pos: Vector3, normal: Vector3) -> void:
	net_id = p_net_id

func detonate() -> void:
	queue_free()
