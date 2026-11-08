extends Node
## Global configuration: teams, weapons, economy, user settings and key bindings.

const VERSION := "1.0.0"
const GAME_TITLE := "BREACHLINE"
const DEFAULT_PORT := 27777
const MAX_PLAYERS := 12

const CELL := 2.0 # metres per map grid cell

# --- Teams -------------------------------------------------------------
const ATK := 0
const DEF := 1
const SPEC := -1
const TEAM_NAMES := ["RED VIPER", "IRON GUARD"]
const TEAM_SHORT := ["VIPER", "GUARD"]
const TEAM_COLORS := [Color(0.92, 0.42, 0.22), Color(0.36, 0.62, 0.95)]
const HUNT_TEAM_NAMES := ["IRON GUARD", "HOSTILES"]

# --- Modes ---------------------------------------------------------------
const MODE_DEFUSAL := "defusal"
const MODE_TDM := "tdm"
const MODE_HUNT := "hunt"
const MODE_NAMES := {"defusal": "Demolition", "tdm": "Team Deathmatch", "hunt": "Squad Hunt"}
const MODE_DESC := {
	"defusal": "Red Viper plants the charge at site A or B. Iron Guard defends or defuses. Earn money, buy gear, win rounds.",
	"tdm": "Respawning firefight. Free loadouts. First team to the kill limit wins.",
	"hunt": "You and your squad clear the map of hostiles. No respawns for the squad if everyone goes down.",
}

# --- Economy -------------------------------------------------------------
const START_MONEY := 800
const MAX_MONEY := 16000
const WIN_ELIM := 3250
const WIN_BOMB := 3500
const WIN_DEFUSE := 3500
const WIN_TIME := 3250
const LOSS_BASE := 1400
const LOSS_STEP := 500
const LOSS_MAX := 3400
const PLANT_BONUS := 300
const PLANT_TEAM_BONUS := 800
const DEFUSE_BONUS := 300
const TEAMKILL_PENALTY := 300

# --- Round timings ---------------------------------------------------------
const FREEZE_TIME := 6.0
const BUY_TIME := 25.0
const ROUND_TIME := 115.0
const BOMB_TIME := 40.0
const PLANT_TIME := 3.2
const DEFUSE_TIME := 10.0
const DEFUSE_TIME_KIT := 5.0
const POST_ROUND_TIME := 6.0

# --- Movement (metres / seconds) ----------------------------------------
const GRAVITY := 20.0
const JUMP_VELOCITY := 6.9
const GROUND_ACCEL := 5.5
const AIR_ACCEL := 12.0
const AIR_WISH_CAP := 0.8
const FRICTION := 5.0
const STOP_SPEED := 2.5
const WALK_MULT := 0.52
const CROUCH_MULT := 0.36
const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.2
const STAND_EYE := 1.62
const CROUCH_EYE := 1.06
const RADIUS := 0.3

# --- Weapons ---------------------------------------------------------------
# slot: 1 primary, 2 sidearm, 3 melee, 4 grenade, 5 special
# spread/recoil values are degrees. pen = metres of wood-equivalent the bullet can pass.
# armor = fraction of damage that reaches health when the hit lands on armour.
# falloff = damage multiplier per 10 m travelled.
const WEAPONS := {
	"knife": {"name": "Combat Knife", "slot": 3, "cls": "knife", "price": 0, "team": -1, "dmg": 40, "dmg_alt": 65,
		"rof": 0.45, "rof_alt": 1.0, "reach": 1.9, "speed": 6.3, "reward": 1500, "model": "knife", "snd": "knife"},
	"m9": {"name": "M9 Service", "slot": 2, "cls": "pistol", "price": 200, "team": -1, "dmg": 30, "rof": 0.15, "auto": false,
		"mag": 13, "reserve": 52, "reload": 2.2, "deploy": 0.6, "spread": 0.9, "spread_move": 3.0, "spread_air": 8.0, "spread_fire": 1.2,
		"recoil": 2.0, "recoil_h": 0.6, "pen": 0.4, "armor": 0.55, "falloff": 0.88, "speed": 6.1, "reward": 300, "model": "pistol", "snd": "pistol"},
	"raptor": {"name": "Raptor MP", "slot": 2, "cls": "pistol", "price": 500, "team": -1, "dmg": 22, "rof": 0.065, "auto": true,
		"mag": 18, "reserve": 90, "reload": 2.3, "deploy": 0.6, "spread": 1.6, "spread_move": 3.0, "spread_air": 9.0, "spread_fire": 0.9,
		"recoil": 1.3, "recoil_h": 1.0, "pen": 0.3, "armor": 0.5, "falloff": 0.82, "speed": 6.0, "reward": 300, "model": "mpistol", "snd": "pistol"},
	"hawk": {"name": "Hawk .50", "slot": 2, "cls": "pistol", "price": 700, "team": -1, "dmg": 54, "rof": 0.26, "auto": false,
		"mag": 7, "reserve": 35, "reload": 2.2, "deploy": 0.7, "spread": 1.0, "spread_move": 4.0, "spread_air": 10.0, "spread_fire": 2.4,
		"recoil": 4.5, "recoil_h": 1.0, "pen": 1.0, "armor": 0.75, "falloff": 0.85, "speed": 6.0, "reward": 300, "model": "magnum", "snd": "magnum"},
	"vespa": {"name": "Vespa SMG", "slot": 1, "cls": "smg", "price": 1250, "team": -1, "dmg": 25, "rof": 0.075, "auto": true,
		"mag": 30, "reserve": 120, "reload": 2.6, "deploy": 0.7, "spread": 1.1, "spread_move": 2.2, "spread_air": 8.0, "spread_fire": 0.6,
		"recoil": 0.9, "recoil_h": 0.8, "pen": 0.5, "armor": 0.6, "falloff": 0.84, "speed": 6.0, "reward": 600, "model": "smg", "snd": "smg"},
	"mako": {"name": "Mako .45", "slot": 1, "cls": "smg", "price": 1700, "team": -1, "dmg": 30, "rof": 0.09, "auto": true,
		"mag": 25, "reserve": 100, "reload": 3.0, "deploy": 0.7, "spread": 1.0, "spread_move": 2.4, "spread_air": 8.0, "spread_fire": 0.7,
		"recoil": 1.1, "recoil_h": 0.7, "pen": 0.6, "armor": 0.65, "falloff": 0.86, "speed": 5.9, "reward": 600, "model": "smg2", "snd": "smg"},
	"breacher": {"name": "Breacher 12", "slot": 1, "cls": "shotgun", "price": 1200, "team": -1, "dmg": 20, "pellets": 9, "rof": 0.88, "auto": false,
		"mag": 8, "reserve": 32, "reload": 0.5, "deploy": 0.8, "spread": 4.2, "spread_move": 1.5, "spread_air": 4.0, "spread_fire": 0.0,
		"recoil": 5.0, "recoil_h": 1.5, "pen": 0.3, "armor": 0.5, "falloff": 0.55, "speed": 5.7, "reward": 900, "model": "shotgun", "snd": "shotgun"},
	"kv74": {"name": "KV-74 Rifle", "slot": 1, "cls": "rifle", "price": 2700, "team": 0, "dmg": 36, "rof": 0.1, "auto": true,
		"mag": 30, "reserve": 90, "reload": 2.5, "deploy": 0.9, "spread": 0.25, "spread_move": 5.0, "spread_air": 12.0, "spread_fire": 0.45,
		"recoil": 1.35, "recoil_h": 1.0, "pen": 1.5, "armor": 0.78, "falloff": 0.98, "speed": 5.5, "reward": 300, "model": "ak", "snd": "rifle_heavy", "ads_fov": 58.0},
	"ar7": {"name": "AR-7 Carbine", "slot": 1, "cls": "rifle", "price": 3100, "team": 1, "dmg": 33, "rof": 0.09, "auto": true,
		"mag": 30, "reserve": 90, "reload": 3.0, "deploy": 0.9, "spread": 0.22, "spread_move": 4.6, "spread_air": 12.0, "spread_fire": 0.38,
		"recoil": 1.15, "recoil_h": 0.8, "pen": 1.4, "armor": 0.7, "falloff": 0.97, "speed": 5.6, "reward": 300, "model": "m4", "snd": "rifle", "ads_fov": 58.0},
	"hornet": {"name": "Hornet Bullpup", "slot": 1, "cls": "rifle", "price": 3300, "team": -1, "dmg": 32, "rof": 0.095, "auto": true,
		"mag": 30, "reserve": 90, "reload": 2.8, "deploy": 0.9, "spread": 0.25, "spread_move": 4.6, "spread_air": 12.0, "spread_fire": 0.4,
		"recoil": 1.0, "recoil_h": 0.7, "pen": 1.4, "armor": 0.75, "falloff": 0.97, "speed": 5.5, "reward": 300, "model": "bullpup", "snd": "rifle", "ads_fov": 38.0},
	"sentry": {"name": "Sentry DMR", "slot": 1, "cls": "sniper", "price": 3800, "team": -1, "dmg": 58, "rof": 0.25, "auto": false,
		"mag": 20, "reserve": 60, "reload": 3.0, "deploy": 1.0, "spread": 3.5, "spread_scoped": 0.12, "spread_move": 6.0, "spread_air": 14.0, "spread_fire": 0.9,
		"recoil": 2.6, "recoil_h": 0.6, "pen": 2.0, "armor": 0.85, "falloff": 0.98, "speed": 5.3, "reward": 300, "model": "dmr", "snd": "sniper_light", "scope": [32.0]},
	"longbow": {"name": "Longbow .338", "slot": 1, "cls": "sniper", "price": 4750, "team": -1, "dmg": 115, "rof": 1.45, "auto": false,
		"mag": 10, "reserve": 30, "reload": 3.6, "deploy": 1.1, "spread": 8.0, "spread_scoped": 0.0, "spread_move": 7.0, "spread_air": 15.0, "spread_fire": 0.0,
		"recoil": 6.0, "recoil_h": 0.5, "pen": 2.5, "armor": 0.97, "falloff": 0.99, "speed": 5.2, "reward": 100, "model": "sniper", "snd": "sniper", "scope": [36.0, 12.0]},
	"thresher": {"name": "Thresher LMG", "slot": 1, "cls": "lmg", "price": 5200, "team": -1, "dmg": 32, "rof": 0.08, "auto": true,
		"mag": 100, "reserve": 200, "reload": 5.0, "deploy": 1.2, "spread": 0.6, "spread_move": 6.0, "spread_air": 14.0, "spread_fire": 0.5,
		"recoil": 1.0, "recoil_h": 1.3, "pen": 1.6, "armor": 0.78, "falloff": 0.97, "speed": 4.9, "reward": 300, "model": "lmg", "snd": "rifle_heavy"},
	"frag": {"name": "Frag Grenade", "slot": 4, "cls": "grenade", "price": 300, "team": -1, "max": 1, "speed": 6.1, "model": "frag", "reward": 300},
	"flash": {"name": "Flashbang", "slot": 4, "cls": "grenade", "price": 200, "team": -1, "max": 2, "speed": 6.1, "model": "flash", "reward": 300},
	"smoke": {"name": "Smoke Grenade", "slot": 4, "cls": "grenade", "price": 300, "team": -1, "max": 1, "speed": 6.1, "model": "smoke", "reward": 300},
	"bomb": {"name": "Demo Charge", "slot": 5, "cls": "bomb", "price": 0, "team": 0, "speed": 6.0, "model": "bomb", "reward": 300},
	"breach": {"name": "Breach Charge", "slot": 5, "cls": "breach", "price": 400, "team": -1, "max": 2, "speed": 6.0, "model": "breach", "reward": 300},
}

const GRENADE_ORDER := ["frag", "flash", "smoke"]

const EQUIPMENT := {
	"kevlar": {"name": "Kevlar Vest", "price": 650, "team": -1},
	"helmet": {"name": "Kevlar + Helmet", "price": 1000, "team": -1},
	"kit": {"name": "Defuse Kit", "price": 400, "team": 1},
}

# Buy menu layout: category -> list of item ids
const BUY_MENU := [
	["Pistols", ["m9", "raptor", "hawk"]],
	["SMGs", ["vespa", "mako"]],
	["Shotgun", ["breacher"]],
	["Rifles", ["kv74", "ar7", "hornet"]],
	["Marksman", ["sentry", "longbow"]],
	["Heavy", ["thresher"]],
	["Gear", ["kevlar", "helmet", "kit", "breach"]],
	["Grenades", ["frag", "flash", "smoke"]],
]

const DIFFICULTY_NAMES := ["Recruit", "Regular", "Veteran", "Elite"]

var recoil_patterns := {}

# --- Settings ----------------------------------------------------------------
const SETTINGS_PATH := "user://settings.cfg"
var settings := {
	"player_name": "Operator",
	"sensitivity": 2.0,
	"fov": 90.0,
	"invert_y": false,
	"master_volume": 0.8,
	"quality": 2, # 0 low, 1 medium, 2 high, 3 ultra
	"fullscreen": false,
	"show_fps": false,
	"crosshair_color": 0,
	"last_ip": "127.0.0.1",
	"last_port": DEFAULT_PORT,
	"mode": MODE_DEFUSAL,
	"map": "outpost",
	"bots": 9,
	"difficulty": 1,
	"rounds": 16,
	"friendly_fire": false,
}

const CROSSHAIR_COLORS := [Color(0.3, 1.0, 0.35), Color(1, 1, 1), Color(0.2, 0.9, 1.0), Color(1.0, 0.9, 0.2), Color(1.0, 0.3, 0.8)]


func _ready() -> void:
	_build_input_map()
	_build_recoil_patterns()
	load_settings()
	apply_display_settings()


func w(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


func item_name(id: String) -> String:
	if WEAPONS.has(id):
		return WEAPONS[id]["name"]
	if EQUIPMENT.has(id):
		return EQUIPMENT[id]["name"]
	return id


func item_price(id: String) -> int:
	if WEAPONS.has(id):
		return int(WEAPONS[id]["price"])
	if EQUIPMENT.has(id):
		return int(EQUIPMENT[id]["price"])
	return 0


func item_team(id: String) -> int:
	if WEAPONS.has(id):
		return int(WEAPONS[id]["team"])
	if EQUIPMENT.has(id):
		return int(EQUIPMENT[id]["team"])
	return -1


func _build_recoil_patterns() -> void:
	for id in WEAPONS:
		var d: Dictionary = WEAPONS[id]
		if not d.has("recoil"):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var pat: Array[Vector2] = []
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var phase := rng.randf() * TAU
		for i in 120:
			var v: float = d["recoil"]
			if i >= 7:
				v *= 0.3
			elif i >= 4:
				v *= 0.65
			v *= rng.randf_range(0.85, 1.15)
			var h: float = 0.0
			if i < 3:
				h = rng.randf_range(-0.15, 0.15) * d["recoil_h"]
			else:
				h = sin(phase + i * 0.45) * d["recoil_h"] * side + rng.randf_range(-0.2, 0.2) * d["recoil_h"]
			pat.append(Vector2(v, h))
		recoil_patterns[id] = pat


# --- Settings persistence ----------------------------------------------------
func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		if cf.has_section_key("game", k):
			var v = cf.get_value("game", k)
			if typeof(v) == typeof(settings[k]) or (typeof(settings[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				settings[k] = v


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("game", k, settings[k])
	cf.save(SETTINGS_PATH)


func apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if settings["fullscreen"]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(settings["master_volume"]))))
	var vp := get_viewport()
	var q: int = settings["quality"]
	vp.msaa_3d = Viewport.MSAA_DISABLED if q <= 1 else (Viewport.MSAA_2X if q == 2 else Viewport.MSAA_4X)
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q >= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_scale = 0.75 if q == 0 else 1.0
	RenderingServer.directional_shadow_atlas_set_size(2048 if q <= 1 else 4096, true)


func crosshair_color() -> Color:
	return CROSSHAIR_COLORS[clampi(int(settings["crosshair_color"]), 0, CROSSHAIR_COLORS.size() - 1)]


# --- Input -------------------------------------------------------------------
func _key(action: String, keys: Array, mouse: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in mouse:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)


func _build_input_map() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("crouch", [KEY_CTRL, KEY_C])
	_key("walk", [KEY_SHIFT])
	_key("fire", [], [MOUSE_BUTTON_LEFT])
	_key("aim", [], [MOUSE_BUTTON_RIGHT])
	_key("reload", [KEY_R])
	_key("use", [KEY_E])
	_key("cover", [KEY_Q])
	_key("buy", [KEY_B])
	_key("drop", [KEY_G])
	_key("flashlight", [KEY_F])
	_key("slot1", [KEY_1])
	_key("slot2", [KEY_2])
	_key("slot3", [KEY_3])
	_key("slot4", [KEY_4])
	_key("slot5", [KEY_5])
	_key("next_weapon", [], [MOUSE_BUTTON_WHEEL_DOWN])
	_key("prev_weapon", [], [MOUSE_BUTTON_WHEEL_UP])
	_key("last_weapon", [KEY_X])
	_key("scoreboard", [KEY_TAB])
	_key("chat", [KEY_Y, KEY_T])
	_key("team_chat", [KEY_U])
	_key("team_menu", [KEY_M])
	_key("pause", [KEY_ESCAPE])
