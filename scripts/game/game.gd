class_name Game
extends Node3D
## STUB (interface only) - core logic is being implemented. See docs/ARCHITECTURE.md.

signal kill_event(killer_id: String, victim_id: String, weapon_id: String, headshot: bool, wallbang: bool)
signal round_event(kind: String, data: Dictionary)
signal chat_message(from_name: String, team: int, text: String, team_only: bool)
signal soldier_spawned(s: Soldier)
signal soldier_removed(id: String)
signal local_damaged(amount: float, from_dir: Vector3)
signal hit_confirmed(headshot: bool, killed: bool)

static var inst: Game

var config := {"mode": "defusal", "map": "outpost", "bots": 9, "difficulty": 1, "rounds": 16, "friendly_fire": false}
var world: World
var soldiers := {}
var local_soldier: Soldier
var local_team := -1
var fx: Effects
var hud: Hud
var mode: Object
var recent_noises: Array = []
var rs := {"phase": "freeze", "time_left": 0.0, "round": 1, "score": [0, 0], "max_rounds": 16,
	"bomb": {"state": "none", "carrier": "", "pos": Vector3.ZERO, "time_left": 0.0},
	"hostiles_left": 0, "kill_limit": 0, "winner": -1, "buy_time_left": 0.0}


func get_soldier(id: String) -> Soldier:
	return soldiers.get(id)


func alive_soldiers(team := -2) -> Array:
	var out := []
	for s in soldiers.values():
		if s.alive and (team == -2 or s.team == team):
			out.append(s)
	return out


func is_server() -> bool:
	return Net.is_server()


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func request_buy(item_id: String) -> void:
	pass


func request_join_team(team: int) -> void:
	pass


func request_chat(text: String, team_only: bool) -> void:
	pass


func request_drop() -> void:
	pass


func request_use() -> void:
	pass


func can_buy(s: Soldier, item_id: String) -> String:
	return ""


func in_buy_zone(s: Soldier) -> bool:
	return true


func server_buy(s: Soldier, item_id: String) -> void:
	pass


func spawn_grenade(owner: Soldier, type: String, origin: Vector3, velocity: Vector3) -> void:
	pass


func place_breach(owner: Soldier, pos: Vector3, normal: Vector3) -> void:
	pass


func apply_damage(victim: Soldier, attacker_id: String, dmg: float, zone: int, weapon_id: String, dir: Vector3, armor_ratio: float) -> void:
	pass


func explosion(pos: Vector3, radius: float, max_dmg: float, attacker_id: String, weapon_id: String, breach := false) -> void:
	pass


func noise(pos: Vector3, loudness: float, source_id: String) -> void:
	pass


func add_smoke(pos: Vector3, radius: float, duration: float) -> void:
	pass


func destroy_breakable(id: int, dir: Vector3) -> void:
	pass


func smoke_blocks(a: Vector3, b: Vector3) -> bool:
	return false


func grenade_detonated(net_id: int, pos: Vector3) -> void:
	pass
