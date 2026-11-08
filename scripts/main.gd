extends Node
## Entry point. Modes:
##   (default)            main menu with a 3D map flythrough behind it
##   --server             dedicated server (headless), configured by server.cfg
##   --master             master server only (server list registry)
##   --autotest ...       bots-only match for automated testing
## Arguments may be passed after "--" (godot) or directly to the exported exe.

var menu: MainMenu
var browser: ServerList
var game: Game
var beacon: ServerBeacon
var master: MasterServer
var dedicated := false
var server_cfg := {}
var _bg: Node3D
var _bg_cam: Camera3D
var _bg_t := 0.0
var _stdin_thread: Thread
var _stdin_lines: Array = []
var _stdin_mutex := Mutex.new()
var _autotest_end := 0.0
var _status_timer := 0.0


func _args() -> PackedStringArray:
	var a := OS.get_cmdline_user_args()
	a.append_array(OS.get_cmdline_args())
	return a


func _ready() -> void:
	_boot.call_deferred()


func _boot() -> void:
	var args := _args()
	if "--master" in args:
		_run_master(args)
		return
	if "--server" in args or OS.has_feature("dedicated_server"):
		_run_dedicated(args)
		return
	if "--autotest" in args:
		_run_autotest(args)
		return
	Net.joined.connect(_on_joined)
	Net.join_failed.connect(_on_join_failed)
	Net.disconnected.connect(_on_disconnected)
	browser = ServerList.new()
	browser.name = "ServerList"
	add_child(browser)
	_show_menu()


# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
func _show_menu(status := "") -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	if menu == null:
		menu = MainMenu.new()
		menu.name = "MainMenu"
		var layer := CanvasLayer.new()
		layer.name = "MenuLayer"
		layer.layer = 5
		add_child(layer)
		menu.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(menu)
	menu.get_parent().visible = true
	menu.visible = true
	if status != "":
		menu.show_status(status)


func _hide_menu() -> void:
	if menu:
		menu.get_parent().visible = false
	if _bg:
		_bg.queue_free()
		_bg = null
		_bg_cam = null


func _build_background() -> void:
	if _bg or DisplayServer.get_name() == "headless":
		return
	_bg = Node3D.new()
	_bg.name = "MenuBackground"
	add_child(_bg)
	var w := World.new()
	_bg.add_child(w)
	w.build("neon_row" if randf() < 0.5 else "outpost", false, true)
	_bg_cam = Camera3D.new()
	_bg_cam.fov = 70.0
	_bg.add_child(_bg_cam)
	_bg_cam.make_current()
	_bg_t = randf() * 100.0


func _process(delta: float) -> void:
	if _bg_cam and is_instance_valid(_bg_cam):
		_bg_t += delta * 0.035
		var w: World = _bg.get_child(0)
		var c := w.bounds.get_center()
		var r := minf(w.bounds.size.x, w.bounds.size.z) * 0.33
		var p := c + Vector3(cos(_bg_t) * r, 7.5 + sin(_bg_t * 0.7) * 2.0, sin(_bg_t) * r)
		_bg_cam.global_position = p
		_bg_cam.look_at(c + Vector3(cos(_bg_t + 1.2) * r * 0.3, 1.5, sin(_bg_t + 1.2) * r * 0.3))
	if dedicated:
		_dedicated_tick(delta)
	if _autotest_end > 0.0 and Time.get_ticks_msec() / 1000.0 > _autotest_end:
		_autotest_end = 0.0
		_autotest_report()
		get_tree().quit()


# ---------------------------------------------------------------------------
# Starting / leaving games (called by the menu)
# ---------------------------------------------------------------------------
func _menu_config(config: Dictionary) -> Dictionary:
	var c := {"mode": Cfg.MODE_DEFUSAL, "map": "outpost", "bots": 9, "difficulty": 1, "rounds": 16, "friendly_fire": false}
	c.merge(config, true)
	return c


func start_offline(config: Dictionary) -> void:
	var c := _menu_config(config)
	Net.start_offline(c)
	_start_game(c)


func host(config: Dictionary, port: int) -> void:
	var c := _menu_config(config)
	var err := Net.host(port, c, true)
	if err != OK:
		menu.show_status("Could not host on port %d (%s)." % [port, error_string(err)])
		return
	Net.server_name = "%s's game" % str(Cfg.settings["player_name"])
	_start_beacon(port, [])
	_start_game(c)


func join(ip: String, port: int, password := "") -> void:
	var err := Net.join(ip.strip_edges(), port, password)
	if err != OK:
		menu.show_status("Could not connect (%s)." % error_string(err))
		return
	menu.show_status("Connecting to %s:%d ..." % [ip, port])


func _on_joined(config: Dictionary) -> void:
	_start_game(config)


func _on_join_failed(reason: String) -> void:
	if menu:
		menu.show_status(reason)


func _on_disconnected(reason: String) -> void:
	_end_game()
	_show_menu(reason)


func leave_game() -> void:
	_end_game()
	Net.stop()
	_show_menu()


func _end_game() -> void:
	if game and is_instance_valid(game):
		game.queue_free()
		get_tree().root.remove_child(game)
	game = null
	if beacon:
		beacon.queue_free()
		beacon = null
	Engine.time_scale = 1.0


func _start_game(config: Dictionary) -> void:
	_hide_menu()
	if game and is_instance_valid(game):
		get_tree().root.remove_child(game)
		game.queue_free()
	game = Game.new()
	game.setup(config, dedicated)
	get_tree().root.add_child(game)


## Map rotation / map change: rebuilds the match on this peer.
func restart_game(config: Dictionary) -> void:
	if Net.is_server():
		Net.match_config = config
		for id in Net.peers.keys():
			Net.peers[id]["loaded"] = false
	_start_game(config)
	if dedicated:
		print("Map changed to %s (%s)" % [config.get("map", "?"), config.get("mode", "?")])


func _start_beacon(port: int, masters: Array) -> void:
	if beacon:
		beacon.queue_free()
	beacon = ServerBeacon.new()
	beacon.name = "ServerBeacon"
	add_child(beacon)
	beacon.start(port, masters, _server_info)


func _server_info() -> Dictionary:
	var humans := Net.loaded_peers().size() + (0 if dedicated else 1)
	var bots := 0
	var mode := str(Net.match_config.get("mode", ""))
	var map := str(Net.match_config.get("map", ""))
	if game and is_instance_valid(game):
		for s in game.soldiers.values():
			if s.is_bot:
				bots += 1
		mode = game.game_mode()
		map = str(game.config.get("map", map))
	return {"name": Net.server_name, "map": map, "mode": mode, "players": humans, "bots": bots,
		"max_players": int(server_cfg.get("max_players", Cfg.MAX_PLAYERS)), "password": Net.password != ""}


# ---------------------------------------------------------------------------
# Dedicated server
# ---------------------------------------------------------------------------
const SERVER_CFG_DEFAULT := """; BREACHLINE dedicated server configuration
; Edit and restart the server to apply.
[server]
name="BREACHLINE Server"
port=27777
max_players=12
password=""
; Map rotation: map:mode pairs. Maps: outpost, neon_row. Modes: defusal, tdm, hunt
rotation="outpost:defusal,neon_row:defusal,outpost:tdm,neon_row:tdm"
; Bots fill empty slots (total soldiers = bots, humans replace bots)
bots=10
; 0 Recruit, 1 Regular, 2 Veteran, 3 Elite
difficulty=1
rounds=16
friendly_fire=false
; Try to open the port on your router automatically
upnp=true
; Master servers to register with (comma separated host:port), e.g. "my-vps.example.com:27900"
master_servers=""
"""


func _server_cfg_path() -> String:
	# Exported builds keep server.cfg next to the exe; editor runs use the user data folder.
	if OS.has_feature("template"):
		return OS.get_executable_path().get_base_dir().path_join("server.cfg")
	return "user://server.cfg"


func _load_server_cfg() -> Dictionary:
	var path := _server_cfg_path()
	if not FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(SERVER_CFG_DEFAULT)
			f.close()
			print("Created default config: %s" % ProjectSettings.globalize_path(path))
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		cf.parse(SERVER_CFG_DEFAULT)
	var d := {}
	for k in cf.get_section_keys("server"):
		d[k] = cf.get_value("server", k)
	print("Using config: %s" % ProjectSettings.globalize_path(path))
	return d


func _parse_rotation(text: String) -> Array:
	var out := []
	for e in text.split(","):
		var parts := e.strip_edges().split(":")
		if parts.size() >= 1 and parts[0] != "":
			out.append({"map": parts[0], "mode": parts[1] if parts.size() > 1 else Cfg.MODE_DEFUSAL})
	if out.is_empty():
		out.append({"map": "outpost", "mode": Cfg.MODE_DEFUSAL})
	return out


func _run_dedicated(args: PackedStringArray) -> void:
	dedicated = true
	Engine.max_fps = 60
	print("==============================================")
	print(" BREACHLINE dedicated server v%s" % Cfg.VERSION)
	print("==============================================")
	server_cfg = _load_server_cfg()
	var port := int(server_cfg.get("port", Cfg.DEFAULT_PORT))
	var rot := _parse_rotation(str(server_cfg.get("rotation", "outpost:defusal")))
	var config := {"mode": rot[0]["mode"], "map": rot[0]["map"], "bots": int(server_cfg.get("bots", 10)),
		"difficulty": int(server_cfg.get("difficulty", 1)), "rounds": int(server_cfg.get("rounds", 16)),
		"friendly_fire": bool(server_cfg.get("friendly_fire", false)), "rotation": rot, "rotation_index": 0}
	Net.password = str(server_cfg.get("password", ""))
	Net.server_name = str(server_cfg.get("name", "BREACHLINE Server"))
	Net.upnp_done.connect(_on_upnp)
	var err := Net.host(port, config, bool(server_cfg.get("upnp", true)), int(server_cfg.get("max_players", Cfg.MAX_PLAYERS)))
	if err != OK:
		printerr("Could not open UDP port %d: %s" % [port, error_string(err)])
		get_tree().quit(1)
		return
	var masters := []
	for m in str(server_cfg.get("master_servers", "")).split(","):
		if m.strip_edges() != "":
			masters.append(m.strip_edges())
	_start_beacon(port, masters)
	print("Server '%s' listening on UDP %d (queries on %d)" % [Net.server_name, port, port + 1])
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			print("  LAN address: %s:%d" % [ip, port])
	if masters.size() > 0:
		print("Registering with master server(s): %s" % ", ".join(masters))
	print("Type 'help' for console commands.")
	Net.peer_loaded.connect(func(id, n): print("+ %s joined (peer %d)" % [n, id]))
	Net.peer_gone.connect(func(id): print("- peer %d left" % id))
	_start_game(config)
	_stdin_thread = Thread.new()
	_stdin_thread.start(_stdin_loop)


func _on_upnp(ok: bool, ext: String) -> void:
	if not dedicated:
		return
	var port := int(server_cfg.get("port", Cfg.DEFAULT_PORT))
	if ok:
		print("UPnP: router port %d opened. Internet players can join at %s:%d" % [port, ext, port])
	else:
		print("UPnP: could not open the port automatically. For internet play, forward UDP %d and %d" % [port, port + 1])
		print("      on your router to this PC, then share your public IP.")


func _stdin_loop() -> void:
	while true:
		var line := OS.read_string_from_stdin(1024)
		if line == "":
			OS.delay_msec(200)
			continue
		_stdin_mutex.lock()
		_stdin_lines.append(line.strip_edges())
		_stdin_mutex.unlock()


func _dedicated_tick(delta: float) -> void:
	_stdin_mutex.lock()
	var lines := _stdin_lines.duplicate()
	_stdin_lines.clear()
	_stdin_mutex.unlock()
	for l in lines:
		_console(str(l))
	_status_timer += delta
	if _status_timer > 300.0:
		_status_timer = 0.0
		_console("status")


func _console(line: String) -> void:
	var parts := line.split(" ", false)
	if parts.is_empty():
		return
	var cmd := parts[0].to_lower()
	var rest := " ".join(parts.slice(1))
	match cmd:
		"help":
			print("Commands: status, say <text>, map <map> [mode], kick <name>, bots <n>, quit")
		"status":
			if game:
				print("Map %s  mode %s  phase %s  score %s" % [game.config.get("map"), game.game_mode(), game.rs["phase"], str(game.rs["score"])])
				for s in game.soldiers.values():
					print("  %-16s team %d  %s  K %d D %d" % [s.display_name, s.team, "BOT" if s.is_bot else "peer %d" % s.owner_peer, s.kills, s.deaths])
		"say":
			if game:
				game.server_message("[SERVER] " + rest)
		"map":
			if game and parts.size() >= 2:
				var cfg := game.config.duplicate(true)
				cfg["map"] = parts[1]
				if parts.size() >= 3:
					cfg["mode"] = parts[2]
				game.change_map(cfg)
		"kick":
			if game:
				for s in game.soldiers.values():
					if s.display_name.to_lower() == rest.to_lower() and not s.is_bot:
						Net.kick(s.owner_peer, "Kicked by server.")
		"bots":
			if game and parts.size() >= 2:
				game.config["bots"] = int(parts[1])
				game.mode.balance_bots()
		"quit", "exit":
			Net.stop()
			get_tree().quit()
		_:
			print("Unknown command. Type 'help'.")


# ---------------------------------------------------------------------------
# Master server
# ---------------------------------------------------------------------------
func _run_master(args: PackedStringArray) -> void:
	dedicated = true
	print("BREACHLINE master server v%s" % Cfg.VERSION)
	var port := MasterServer.DEFAULT_PORT
	var i := args.find("--port")
	if i >= 0 and i + 1 < args.size():
		port = int(args[i + 1])
	master = MasterServer.new()
	add_child(master)
	if not master.start(port):
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# Automated test: bots-only match, prints events, then quits.
#   --autotest <mode> <map> <seconds> [timescale]
# ---------------------------------------------------------------------------
var _at_kills := 0
var _at_events := []


func _run_autotest(args: PackedStringArray) -> void:
	var i := args.find("--autotest")
	var mode := args[i + 1] if args.size() > i + 1 else Cfg.MODE_DEFUSAL
	var map := args[i + 2] if args.size() > i + 2 else "outpost"
	var secs := float(args[i + 3]) if args.size() > i + 3 else 60.0
	var ts := float(args[i + 4]) if args.size() > i + 4 else 1.0
	dedicated = true
	Engine.time_scale = ts
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 16
	var config := {"mode": mode, "map": map, "bots": 10, "difficulty": 2, "rounds": 16, "friendly_fire": false}
	Net.start_offline(config)
	_start_game(config)
	game.kill_event.connect(func(k, v, w, hs, wb):
		_at_kills += 1
		print("KILL %s -> %s (%s)%s" % [k, v, w, " HS" if hs else ""]))
	game.round_event.connect(func(kind, data):
		_at_events.append(kind)
		print("EVENT %s %s" % [kind, str(data)]))
	_autotest_end = Time.get_ticks_msec() / 1000.0 + secs / ts
	print("AUTOTEST start mode=%s map=%s secs=%.0f timescale=%.1f" % [mode, map, secs, ts])


func _autotest_report() -> void:
	print("AUTOTEST done: kills=%d events=%s score=%s phase=%s round=%s" % [_at_kills, str(_at_events), str(game.rs["score"]), game.rs["phase"], str(game.rs["round"])])
