class_name Soldier
extends CharacterBody3D
## STUB (interface only) - core logic is being implemented. See docs/ARCHITECTURE.md.

signal fired(weapon_id: String)
signal reload_started(weapon_id: String, duration: float)
signal weapon_switched(weapon_id: String)
signal knifed(alt: bool)
signal threw(type: String)
signal died(killer_id: String)
signal spawned()

const F_ON_FLOOR := 1
const F_CROUCH := 2
const F_WALK := 4
const F_COVER := 8
const F_AIM := 16
const F_RELOAD := 32
const F_PLANT := 64
const F_DEFUSE := 128
const F_LIGHT := 256
const F_SCOPED := 512

var id := ""
var display_name := ""
var team := 0
var is_bot := false
var owner_peer := 1

var alive := true
var health := 100
var armor := 0
var helmet := false
var has_kit := false
var money := 800
var kills := 0
var deaths := 0
var score := 0

var primary := ""
var secondary := "m9"
var grenades := {"frag": 0, "flash": 0, "smoke": 0}
var has_bomb := false
var breach_charges := 0
var cur := "m9"
var ammo := {}

var yaw := 0.0
var pitch := 0.0
var punch := Vector2.ZERO
var crouch_amount := 0.0
var flags := 0
var scope_level := 0
var ads_amount := 0.0
var action_progress := 0.0
var action_label := ""
var flash_until := 0.0
var flash_strength := 0.0
var spotted_until := 0.0
var model: SoldierModel


func eye_pos() -> Vector3:
	return global_position + Vector3(0, lerpf(Cfg.STAND_EYE, Cfg.CROUCH_EYE, crouch_amount), 0)


func aim_dir() -> Vector3:
	var p := pitch + deg_to_rad(punch.x)
	var y := yaw + deg_to_rad(punch.y)
	return Vector3(-sin(y) * cos(p), sin(p), -cos(y) * cos(p))


func is_authority() -> bool:
	return true


func current_spread() -> float:
	return 1.0


func weapon_data() -> Dictionary:
	return Cfg.w(cur)


func apply_flash(strength: float) -> void:
	pass
