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
	if "--testclient" in args:
		_run_testclient(args)
		return
	browser = ServerList.new()
	browser.name = "ServerList"
	add_child(browser)
	if "--querytest" in args:
		_run_querytest(args)
		return
	if "--shots" in args:
		_run_shots(args)
		return
	if "--actiontest" in args:
		_run_actiontest()
		return
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
const SERVER_CFG_DEFAULT := """
; BREACHLINE dedicated server configuration
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


# ---------------------------------------------------------------------------
# Test client: joins a server, auto-picks a team, walks and shoots, logs what happens.
#   --testclient <host> <port> <seconds>
# ---------------------------------------------------------------------------
var _tc_t := 0.0
var _tc_secs := 30.0
var _tc_joined_team := false
var _tc_log_t := 0.0


func _run_testclient(args: PackedStringArray) -> void:
	var i := args.find("--testclient")
	var host_ip := args[i + 1] if args.size() > i + 1 else "127.0.0.1"
	var port := int(args[i + 2]) if args.size() > i + 2 else Cfg.DEFAULT_PORT
	_tc_secs = float(args[i + 3]) if args.size() > i + 3 else 30.0
	Cfg.settings["player_name"] = "TestClient"
	print("TESTCLIENT connecting to %s:%d" % [host_ip, port])
	Net.join(host_ip, port)
	Net.disconnected.connect(func(r): print("TESTCLIENT disconnected: ", r))
	Net.join_failed.connect(func(r): print("TESTCLIENT join failed: ", r); get_tree().quit(1))
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not OS.get_cmdline_user_args().has("--testclient") and not OS.get_cmdline_args().has("--testclient"):
		return
	_tc_t += delta
	if game and is_instance_valid(game) and not _tc_joined_team and _tc_t > 3.0:
		_tc_joined_team = true
		game.kill_event.connect(func(k, v, w, hs, wb): print("TESTCLIENT kill %s -> %s (%s)" % [k, v, w]))
		game.round_event.connect(func(kind, data): print("TESTCLIENT event %s" % kind))
		game.chat_message.connect(func(n, t, text, to): print("TESTCLIENT chat %s: %s" % [n, text]))
		game.local_damaged.connect(func(a, d): print("TESTCLIENT took %d damage" % int(a)))
		game.hit_confirmed.connect(func(hs, k): print("TESTCLIENT hit confirmed hs=%s killed=%s" % [hs, k]))
		print("TESTCLIENT in game: soldiers=%d map=%s" % [game.soldiers.size(), game.config.get("map")])
		game.request_join_team(2)
	if game and is_instance_valid(game) and game.local_soldier:
		var ls := game.local_soldier
		if game.hud and game.hud.get("_team") and game.hud.get("_team").visible:
			game.hud.get("_team").visible = false
		if ls.alive:
			Input.action_press("move_forward")
			if int(_tc_t * 2.0) % 3 == 0:
				Input.action_press("fire")
			else:
				Input.action_release("fire")
			if game.controller:
				game.controller.look_yaw += delta * 0.6
		_tc_log_t += delta
		if _tc_log_t > 3.0:
			_tc_log_t = 0.0
			var others := 0
			for s in game.soldiers.values():
				if s != ls and s.alive:
					others += 1
			print("TESTCLIENT t=%.0f alive=%s hp=%d pos=%s team=%d others_alive=%d phase=%s" % [_tc_t, ls.alive, ls.health, str(ls.global_position.snapped(Vector3(0.1, 0.1, 0.1))), ls.team, others, game.rs["phase"]])
	if _tc_t > _tc_secs:
		print("TESTCLIENT done")
		Net.stop()
		get_tree().quit()


# --querytest: refresh the server browser and print what was found.
func _run_querytest(args: PackedStringArray) -> void:
	var mi := args.find("--master-list")
	if mi >= 0 and args.size() > mi + 1:
		Cfg.settings["master_servers"] = args[mi + 1]
	var i := args.find("--querytest")
	if args.size() > i + 1 and not args[i + 1].begins_with("--"):
		browser.add_favorite(args[i + 1], int(args[i + 2]) if args.size() > i + 2 else Cfg.DEFAULT_PORT)
	browser.refresh()
	await get_tree().create_timer(2.0).timeout
	print("QUERYTEST found %d server(s)" % browser.servers.size())
	for e in browser.servers:
		print("  ", e)
	get_tree().quit()


# ---------------------------------------------------------------------------
# --shots <map> <mode> <out_dir> [quality]: in-game screenshots for visual checks.
# ---------------------------------------------------------------------------
var _sh_frames := 0
var _sh_idx := -1
var _sh_out := ""
var _sh_spots := []


func _run_shots(args: PackedStringArray) -> void:
	var i := args.find("--shots")
	var map := args[i + 1]
	var mode := args[i + 2]
	_sh_out = args[i + 3]
	if args.size() > i + 4:
		Cfg.settings["quality"] = int(args[i + 4])
	start_offline({"map": map, "mode": mode, "bots": 9, "difficulty": 1})
	set_process(true)
	get_tree().process_frame.connect(_shots_tick)


func _shots_tick() -> void:
	_sh_frames += 1
	if game == null or not is_instance_valid(game):
		return
	if _sh_idx == -1 and _sh_frames == 20:
		game.request_join_team(Cfg.ATK)
		var w := game.world
		var c := w.bounds.get_center()
		_sh_spots = [
			["spawn", Vector3.INF, Vector3.INF],
			["siteA", w.site_center("A") + Vector3(4, 0, 6), w.site_center("A")],
			["siteB", w.site_center("B") + Vector3(-4, 0, 6), w.site_center("B")],
			["mid", Vector3(c.x, 0, c.z + 8), Vector3(c.x, 0, c.z - 10)],
		]
		_sh_idx = 0
		_sh_frames = 0
		return
	if _sh_idx < 0:
		return
	if game.hud and game.hud.get("_team") and game.hud.get("_team").visible:
		game.hud.get("_team").visible = false
	var s := game.local_soldier
	if s == null:
		return
	if _sh_frames == 2:
		var spot: Array = _sh_spots[_sh_idx]
		if spot[1] != Vector3.INF:
			var p: Vector3 = game.world.closest_nav_point(spot[1])
			var to: Vector3 = spot[2] - p
			var yaw := atan2(-to.x, -to.z)
			s.force_position(p, yaw)
			game.controller.look_yaw = yaw
			game.controller.look_pitch = -0.05
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _sh_frames == 45:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s.png" % [_sh_out, game.config["map"], _sh_spots[_sh_idx][0]])
		print("SHOT ", _sh_spots[_sh_idx][0])
		_sh_idx += 1
		_sh_frames = 0
		if _sh_idx >= _sh_spots.size():
			get_tree().quit()


# ---------------------------------------------------------------------------
# --actiontest: scripted human actions (buy, shoot a bot, throw a frag, plant) in a headless match.
# ---------------------------------------------------------------------------
var _at_step := 0
var _at_timer := 0.0
var _at_log := []


func _run_actiontest() -> void:
	start_offline({"map": "outpost", "mode": "defusal", "bots": 3, "difficulty": 0})
	game.kill_event.connect(func(k, v, w, hs, wb): _at_log.append("kill %s->%s %s" % [k, v, w]))
	game.round_event.connect(func(kind, d): _at_log.append("event " + kind))
	game.hit_confirmed.connect(func(hs, k): _at_log.append("hit hs=%s killed=%s" % [hs, k]))
	get_tree().physics_frame.connect(_actiontest_tick)


func _actiontest_tick() -> void:
	var dt := 1.0 / 60.0
	_at_timer += dt
	var g := game
	if g == null:
		return
	if g.hud and g.hud.get("_team") and g.hud.get("_team").visible:
		g.hud.get("_team").visible = false
	var s := g.local_soldier
	for a in ["fire", "use", "slot1", "slot4", "slot5"]:
		Input.action_release(a)
	match _at_step:
		0:
			if _at_timer > 1.0:
				g.request_join_team(Cfg.ATK)
				_at_step = 1
				_at_timer = 0.0
		1:
			if s and s.alive and _at_timer > 0.5:
				# Freeze the bots so the scripted player is not interrupted.
				for b in g.soldiers.values():
					if b.is_bot:
						b.brain = null
				s.money = 16000
				for item in ["kv74", "helmet", "frag", "breach"]:
					g.request_buy(item)
				print("ACTION sounds loaded: kv74=%s kv74_far=%s reload=%s" % [Sfx.has("shot_kv74"), Sfx.has("shot_kv74_far"), Sfx.has("reload_rifle")])
				print("ACTION bought: primary=%s armor=%d helmet=%s frag=%d breach=%d money=%d cur=%s" % [s.primary, s.armor, s.helmet, s.grenades["frag"], s.breach_charges, s.money, s.cur])
				_at_step = 2
				_at_timer = 0.0
		2:
			# wait for live phase, then face the nearest enemy from close range
			if g.rs["phase"] == "live" and _at_timer > 0.5:
				var target: Soldier = null
				for o in g.alive_soldiers(Cfg.DEF):
					target = o
					break
				if target:
					if target.brain:
						target.brain.set_physics_process(false)
					var p := target.global_position + target.flat_forward() * 6.0
					s.force_position(p, 0.0)
					var to := target.global_position + Vector3(0, 1.3, 0) - s.eye_pos()
					g.controller.look_yaw = atan2(-to.x, -to.z)
					g.controller.look_pitch = asin(to.normalized().y)
					print("ACTION shooting at %s from %.1fm (hp %d)" % [target.display_name, s.global_position.distance_to(target.global_position), target.health])
				_at_step = 3
				_at_timer = 0.0
		3:
			if _at_timer < 0.02:
				s.switch_to(s.primary)
			if _at_timer > 1.0 and _at_timer < 2.5:
				Input.action_press("fire")
			if _at_timer > 3.0:
				print("ACTION after firing: ammo=%s log=%s" % [str(s.ammo.get(s.primary)), str(_at_log)])
				_at_step = 4
				_at_timer = 0.0
		4:
			if _at_timer < 0.02:
				s.switch_to("frag")
			if _at_timer > 1.2 and _at_timer < 1.25:
				Input.action_press("fire")
			if _at_timer > 4.5:
				print("ACTION after frag: frags=%d log=%s" % [s.grenades["frag"], str(_at_log)])
				_at_step = 5
				_at_timer = 0.0
		5:
			# give the charge and plant it in site A
			s.has_bomb = true
			g.sync_inventory(s)
			var site := g.world.closest_nav_point(g.world.site_center("A"))
			s.force_position(site, 0.0)
			_at_step = 6
			_at_timer = 0.0
		6:
			if _at_timer > 0.3:
				Input.action_press("use")
			if _at_timer > 4.5:
				print("ACTION after plant: bomb=%s log=%s" % [str(g.rs["bomb"]["state"]), str(_at_log)])
				_at_step = 7
				_at_timer = 0.0
		7:
			# Cover: stand in front of a wall facing it and take cover.
			if _at_timer < 0.02:
				var c := g.world.cell_to_world(Vector2i(16, 13)) # open mid area; wall is 3 cells west at col 12
				s.force_position(Vector3(27.0, 0.0, c.z), PI * 0.5)
				g.controller.look_yaw = PI * 0.5 # face -X (west)
				g.controller.look_pitch = 0.0
			if _at_timer > 0.3 and _at_timer < 0.32:
				g.controller._try_enter_cover()
				print("ACTION cover: in_cover=%s low=%s normal=%s pos=%s" % [g.controller.in_cover, g.controller.cover_low, str(g.controller.cover_normal), str(s.global_position.snapped(Vector3(0.01, 0.01, 0.01)))])
			if _at_timer > 0.4 and _at_timer < 1.6:
				Input.action_press("move_right")
			else:
				Input.action_release("move_right")
			if _at_timer > 1.7:
				print("ACTION cover after sliding: phase=%s in_cover=%s pos=%s cam_dist=%.2f first_person=%s" % [g.rs["phase"], g.controller.in_cover, str(s.global_position.snapped(Vector3(0.01, 0.01, 0.01))), g.controller.cam.global_position.distance_to(s.eye_pos()), g.controller.first_person()])
				get_tree().quit()
