class_name Grenade
extends Node3D
## STUB - fx worker replaces this file.
var net_id := 0

func setup(p_net_id: int, type: String, owner_id: String, origin: Vector3, vel: Vector3) -> void:
	net_id = p_net_id

func detonate(pos: Vector3) -> void:
	queue_free()
