class_name MainMenu
extends Control
## Title screen. Transparent so Main's 3D map flythrough shows behind it.

const MAPS := [["outpost", "Outpost", "Desert compound at dusk. Long sightlines outside, tight rooms and doors inside."],
	["neon_row", "Neon Row", "Rain-slick casino strip at night. Wide open street, close-quarters lobby and kitchen."]]
const MODES := ["defusal", "tdm", "hunt"]
const ROUNDS := [8, 16, 30]

var _content: PanelContainer
var _pages := {}
var _nav := {}
var _status: Label
var _forms := {}
var _current := ""


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	_build_left()
	_content = PanelContainer.new()
	_content.add_theme_stylebox_override("panel", UiTheme.box(Color(0.05, 0.055, 0.065, 0.86), UiTheme.BORDER, 3, 1, 28.0))
	_content.anchor_left = 1.0
	_content.anchor_right = 1.0
	_content.anchor_top = 0.5
	_content.anchor_bottom = 0.5
	_content.offset_left = -800
	_content.offset_right = -90
	_content.offset_top = -330
	_content.offset_bottom = 330
	add_child(_content)
	_pages["play"] = _build_match_page(false)
	_pages["host"] = _build_match_page(true)
	var sb := ServerBrowser.new()
	sb.status_requested.connect(show_status)
	_pages["browser"] = sb
	_pages["join"] = _build_join_page()
	_pages["settings"] = _build_settings_page()
	_pages["controls"] = _build_controls_page()
	for k in _pages:
		_content.add_child(_pages[k])
	show_page("play")


func show_status(text: String) -> void:
	_status.text = text
	var low := text.to_lower()
	var bad := low.contains("fail") or low.contains("could not") or low.contains("lost") or low.contains("mismatch") or low.contains("error")
	UiTheme.set_label_color(_status, UiTheme.BAD if bad else UiTheme.ACCENT)
	_status.modulate.a = 0.0
	create_tween().tween_property(_status, "modulate:a", 1.0, 0.25)


func show_page(name: String) -> void:
	_current = name
	for k in _pages:
		_pages[k].visible = k == name
	for k in _nav:
		var b: Button = _nav[k]
		b.add_theme_color_override("font_color", UiTheme.ACCENT if k == name else UiTheme.TEXT)


# --- Layout ------------------------------------------------------------------
func _build_background() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.025, 0.92))
	g.set_color(1, Color(0.02, 0.02, 0.025, 0.25))
	g.add_point(0.45, Color(0.02, 0.02, 0.025, 0.55))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 4
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var vg := Gradient.new()
	vg.set_color(0, Color(0, 0, 0, 0))
	vg.set_color(1, Color(0, 0, 0, 0.7))
	vg.set_offset(0, 0.55)
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.05, 1.05)
	vt.width = 256
	vt.height = 256
	var vig := TextureRect.new()
	vig.texture = vt
	vig.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vig)


func _build_left() -> void:
	var col := VBoxContainer.new()
	col.anchor_top = 0.0
	col.anchor_bottom = 1.0
	col.offset_left = 90
	col.offset_top = 90
	col.offset_right = 600
	col.offset_bottom = -60
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	var title := UiTheme.label("BREACHLINE", 88, Color.WHITE, 800, 0)
	title.label_settings.shadow_size = 8
	title.label_settings.shadow_color = Color(0, 0, 0, 0.6)
	title.label_settings.shadow_offset = Vector2(3, 4)
	col.add_child(title)
	var bar := ColorRect.new()
	bar.color = UiTheme.ACCENT
	bar.custom_minimum_size = Vector2(120, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)
	var tag := UiTheme.label("PLANT  //  BREACH  //  HOLD THE LINE", 18, UiTheme.TEXT_DIM, 500, 0)
	col.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 48)
	col.add_child(gap)

	for item in [["play", "PLAY OFFLINE"], ["host", "HOST ONLINE"], ["browser", "SERVER BROWSER"], ["join", "JOIN BY IP"], ["settings", "SETTINGS"], ["controls", "CONTROLS"], ["quit", "QUIT"]]:
		var b := _nav_button(String(item[1]))
		var key := String(item[0])
		if key == "quit":
			b.pressed.connect(func():
				Sfx.play("click")
				get_tree().quit())
		else:
			b.pressed.connect(func():
				Sfx.play("click")
				show_page(key))
			_nav[key] = b
		col.add_child(b)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	_status = UiTheme.label("", 18, UiTheme.ACCENT, 500, 3)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(480, 0)
	col.add_child(_status)
	var ver := UiTheme.label("v%s  ·  Offline vs bots  ·  Online host/join" % Cfg.VERSION, 14, Color(1, 1, 1, 0.35), 400, 0)
	col.add_child(ver)


func _nav_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(320, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", UiTheme.font(600))
	b.add_theme_font_size_override("font_size", 21)
	var n := UiTheme.box(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0), 0, 0, 18.0)
	var h := UiTheme.box(Color(0.91, 0.565, 0.18, 0.16), Color(0, 0, 0, 0), 0, 0, 18.0)
	h.border_width_left = 4
	h.border_color = UiTheme.ACCENT
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_stylebox_override("hover_pressed", h)
	b.mouse_entered.connect(func(): Sfx.play("click", -14.0, 1.4))
	return b


func _page(title: String, subtitle: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(UiTheme.label(title, 30, UiTheme.ACCENT, 700, 0))
	if subtitle != "":
		var s := UiTheme.label(subtitle, 16, UiTheme.TEXT_DIM, 400, 0)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	var r := ColorRect.new()
	r.color = UiTheme.BORDER
	r.custom_minimum_size = Vector2(0, 1)
	v.add_child(r)
	return v


func _field(grid: GridContainer, text: String, ctrl: Control) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	grid.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctrl)


func _option(items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(String(it))
	o.selected = clampi(selected, 0, items.size() - 1)
	o.item_selected.connect(func(_i: int): Sfx.play("click"))
	return o


func _primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.add_theme_font_override("font", UiTheme.font(700))
	b.add_theme_font_size_override("font_size", 20)
	var n := UiTheme.box(Color(0.91, 0.565, 0.18, 0.85), UiTheme.ACCENT, 2, 1, 18.0)
	var h := UiTheme.box(Color(1.0, 0.66, 0.3, 0.95), Color.WHITE, 2, 1, 18.0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	b.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.02))
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.03, 0.02))
	return b


func _build_match_page(online: bool) -> Control:
	var v := _page("HOST ONLINE MATCH" if online else "PLAY OFFLINE",
		"Friends join with your IP address and port. Empty slots are filled with bots." if online else "Fight against bots. Pick a mode, a map and how tough the opposition is.")
	var f := {}
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)

	var mode_names := []
	for m in MODES:
		mode_names.append(Cfg.MODE_NAMES[m])
	f["mode"] = _option(mode_names, maxi(0, MODES.find(String(Cfg.settings["mode"]))))
	_field(grid, "Mode", f["mode"])
	var map_names := []
	var map_idx := 0
	for i in MAPS.size():
		map_names.append(MAPS[i][1])
		if MAPS[i][0] == String(Cfg.settings["map"]):
			map_idx = i
	f["map"] = _option(map_names, map_idx)
	_field(grid, "Map", f["map"])

	var bots_box := HBoxContainer.new()
	var bots := HSlider.new()
	bots.min_value = 0
	bots.max_value = 11
	bots.step = 1
	bots.value = int(Cfg.settings["bots"])
	bots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bots.custom_minimum_size = Vector2(200, 24)
	var bots_lbl := Label.new()
	bots_lbl.custom_minimum_size = Vector2(40, 0)
	bots_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bots_lbl.text = str(int(bots.value))
	bots.value_changed.connect(func(x: float): bots_lbl.text = str(int(x)))
	bots_box.add_child(bots)
	bots_box.add_child(bots_lbl)
	f["bots"] = bots
	_field(grid, "Bots", bots_box)

	f["difficulty"] = _option(Cfg.DIFFICULTY_NAMES, int(Cfg.settings["difficulty"]))
	_field(grid, "Bot difficulty", f["difficulty"])
	var round_names := []
	for r in ROUNDS:
		round_names.append("%d rounds (first to %d)" % [r, r / 2 + 1])
	f["rounds"] = _option(round_names, maxi(0, ROUNDS.find(int(Cfg.settings["rounds"]))))
	var rounds_lbl := Label.new()
	rounds_lbl.text = "Match length"
	rounds_lbl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	grid.add_child(rounds_lbl)
	f["rounds"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(f["rounds"])
	var ff := CheckBox.new()
	ff.button_pressed = bool(Cfg.settings["friendly_fire"])
	ff.text = "On" if ff.button_pressed else "Off"
	ff.toggled.connect(func(on: bool): ff.text = "On" if on else "Off")
	f["friendly_fire"] = ff
	_field(grid, "Friendly fire", ff)

	if online:
		var port := LineEdit.new()
		port.text = str(int(Cfg.settings["last_port"]))
		port.placeholder_text = str(Cfg.DEFAULT_PORT)
		port.max_length = 5
		f["port"] = port
		_field(grid, "Port (UDP)", port)

	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.035), Color(1, 1, 1, 0.06), 2, 1, 14.0))
	var iv := VBoxContainer.new()
	info.add_child(iv)
	var mode_desc := UiTheme.label("", 16, UiTheme.TEXT, 400, 0)
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc.custom_minimum_size = Vector2(560, 0)
	var map_desc := UiTheme.label("", 15, UiTheme.TEXT_DIM, 400, 0)
	map_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_desc.custom_minimum_size = Vector2(560, 0)
	iv.add_child(mode_desc)
	iv.add_child(map_desc)
	if online:
		var note := UiTheme.label("The game tries to open the port on your router automatically (UPnP). If friends can't connect, forward UDP port %d to this PC. Players on the same network can use your local IP." % int(Cfg.settings["last_port"]), 14, UiTheme.ACCENT, 400, 0)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(560, 0)
		iv.add_child(note)
	v.add_child(info)

	var refresh := func():
		var m: String = MODES[f["mode"].selected]
		mode_desc.text = String(Cfg.MODE_DESC[m])
		map_desc.text = "%s — %s" % [MAPS[f["map"].selected][1], MAPS[f["map"].selected][2]]
		var defusal := m == Cfg.MODE_DEFUSAL
		f["rounds"].visible = defusal
		rounds_lbl.visible = defusal
	f["mode"].item_selected.connect(func(_i: int): refresh.call())
	f["map"].item_selected.connect(func(_i: int): refresh.call())
	refresh.call()

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var go := _primary_button("HOST MATCH" if online else "DEPLOY")
	go.pressed.connect(func(): _start(online))
	v.add_child(go)
	_forms["host" if online else "play"] = f
	return v


func _read_config(f: Dictionary) -> Dictionary:
	var cfg := {
		"mode": MODES[f["mode"].selected],
		"map": MAPS[f["map"].selected][0],
		"bots": int(f["bots"].value),
		"difficulty": int(f["difficulty"].selected),
		"rounds": int(ROUNDS[f["rounds"].selected]),
		"friendly_fire": bool(f["friendly_fire"].button_pressed),
	}
	for k in cfg:
		Cfg.settings[k] = cfg[k]
	return cfg


func _start(online: bool) -> void:
	Sfx.play("click")
	var f: Dictionary = _forms["host" if online else "play"]
	var cfg := _read_config(f)
	var main := get_node_or_null("/root/Main")
	if online:
		var port := int(String(f["port"].text).strip_edges())
		if port < 1024 or port > 65535:
			show_status("Enter a port between 1024 and 65535.")
			return
		Cfg.settings["last_port"] = port
		Cfg.save_settings()
		show_status("Starting server on port %d…" % port)
		if main and main.has_method("host"):
			main.host(cfg, port)
	else:
		Cfg.save_settings()
		show_status("Deploying…")
		if main and main.has_method("start_offline"):
			main.start_offline(cfg)


func _build_join_page() -> Control:
	var v := _page("JOIN BY IP", "Enter the host's IP address and port. The host's map and mode are used. Use the Server Browser to find LAN and public games.")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	var ip := LineEdit.new()
	ip.text = String(Cfg.settings["last_ip"])
	ip.placeholder_text = "e.g. 203.0.113.7"
	_field(grid, "Host IP", ip)
	var port := LineEdit.new()
	port.text = str(int(Cfg.settings["last_port"]))
	port.max_length = 5
	_field(grid, "Port", port)
	var who := UiTheme.label("", 15, UiTheme.TEXT_DIM, 400, 0)
	v.add_child(who)
	v.visibility_changed.connect(func(): who.text = "Playing as  %s  — change your name in Settings." % String(Cfg.settings["player_name"]))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var go := _primary_button("CONNECT")
	var do_join := func():
		Sfx.play("click")
		var addr := ip.text.strip_edges()
		var p := int(port.text.strip_edges())
		if addr == "":
			show_status("Enter the host's IP address.")
			return
		if p < 1 or p > 65535:
			show_status("Enter a valid port.")
			return
		Cfg.settings["last_ip"] = addr
		Cfg.settings["last_port"] = p
		Cfg.save_settings()
		show_status("Connecting to %s:%d…" % [addr, p])
		var main := get_node_or_null("/root/Main")
		if main and main.has_method("join"):
			main.join(addr, p)
	go.pressed.connect(do_join)
	ip.text_submitted.connect(func(_t: String): do_join.call())
	v.add_child(go)
	return v


func _build_settings_page() -> Control:
	var v := VBoxContainer.new()
	var sp := SettingsPanel.new(false)
	sp.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	v.add_child(sp)
	# The settings panel draws its own box; strip it here to sit inside the content panel.
	sp.ready.connect(func(): sp.add_theme_stylebox_override("panel", StyleBoxEmpty.new()))
	v.visibility_changed.connect(func():
		if not v.visible:
			Cfg.save_settings())
	return v


func _build_controls_page() -> Control:
	var v := _page("CONTROLS", "")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 7)
	v.add_child(grid)
	var binds := [
		["W A S D", "Move"], ["Mouse", "Look"],
		["Left click", "Fire"], ["Right click", "Aim / scope / stab"],
		["Space", "Jump"], ["Ctrl / C", "Crouch"],
		["Shift", "Walk (quiet)"], ["R", "Reload"],
		["Q", "Take cover / leave cover"], ["E", "Use: doors, plant, defuse, pick up"],
		["1 2 3", "Primary / sidearm / knife"], ["4", "Grenades (press again to cycle)"],
		["5", "Demo charge / breach charge"], ["Mouse wheel", "Cycle weapons"],
		["X", "Last weapon"], ["G", "Drop weapon"],
		["F", "Flashlight"], ["B", "Buy menu"],
		["Tab", "Scoreboard"], ["Y / U", "Chat / team chat"],
		["M", "Choose team"], ["Esc", "Pause menu"],
	]
	for b in binds:
		var k := UiTheme.label(String(b[0]), 16, UiTheme.ACCENT, 600, 0)
		k.custom_minimum_size = Vector2(120, 0)
		grid.add_child(k)
		var a := UiTheme.label(String(b[1]), 16, UiTheme.TEXT, 400, 0)
		a.custom_minimum_size = Vector2(170, 0)
		a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(a)
	var tip := UiTheme.label("In cover: hold right click to pop out and aim, fire without aiming to blind-fire. Move left/right to slide along the wall.", 15, UiTheme.TEXT_DIM, 400, 0)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(560, 0)
	v.add_child(tip)
	return v
