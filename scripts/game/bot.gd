class_name BotBrain
extends Node
## STUB - ai worker replaces this file.
var s: Soldier

func setup(p_s: Soldier, difficulty: int) -> void:
	s = p_s

func think(delta: float) -> Dictionary:
	return {}

func on_round_start() -> void:
	pass

func on_damaged(attacker_id: String, dir: Vector3) -> void:
	pass

func buy_loadout() -> void:
	pass
