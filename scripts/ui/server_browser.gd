class_name ServerBrowser
extends VBoxContainer
## Main-menu server list. Reads get_node("/root/Main").browser (ServerList):
## signal servers_changed, servers: Array[Dictionary], refresh(), add_favorite(host, port), remove_favorite(host, port).
## Works (with an "unavailable" note) when the browser object is missing.

signal status_requested(text: String)

const FILTERS := [["all", "ALL"], ["lan", "LAN"], ["master", "INTERNET"], ["favorite", "FAVORITES"]]
const MAP_NAMES := {"outpost": "Outpost", "neon_row": "Neon Row"}
const COLS := [["SERVER", 0], ["MAP", 120], ["MODE", 150], ["PLAYERS", 120], ["PING", 64], ["", 64]]

var _filter := "all"
var _filter_buttons := {}
var _rows: VBoxContainer
var _status: Label
var _addr: LineEdit
var _join_btn: Button
var _fav_btn: Button
var _selected := {}
var _row_nodes: Array = [] # {button, server}
var _bound_browser: Object


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(UiTheme.label("SERVER BROWSER", 30, UiTheme.ACCENT, 700, 0))
	var sub := UiTheme.label("Games on your local network, the public list and your favourites. Double-click to join.", 16, UiTheme.TEXT_DIM, 400, 0)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(sub)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	var group := ButtonGroup.new()
	for f in FILTERS:
		var b := Button.new()
		b.text = String(f[1])
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 36)
		b.add_theme_font_size_override("font_size", 15)
		var key := String(f[0])
		b.button_pressed = key == _filter
		b.pressed.connect(func():
			Sfx.play("click")
			_filter = key
			_rebuild())
		bar.add_child(b)
		_filter_buttons[key] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	var refresh := Button.new()
	refresh.text = "REFRESH"
	refresh.custom_minimum_size = Vector2(110, 36)
	refresh.add_theme_font_size_override("font_size", 15)
	refresh.pressed.connect(func():
		Sfx.play("click")
		do_refresh())
	bar.add_child(refresh)

	# Table
	var table := PanelContainer.new()
	table.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.07), 2, 1, 6.0))
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(table)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	table.add_child(tv)
	tv.add_child(_header())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 200)
	tv.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)

	_status = UiTheme.label("", 14, UiTheme.TEXT_DIM, 400, 0)
	add_child(_status)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	add_child(bottom)
	_addr = LineEdit.new()
	_addr.placeholder_text = "IP:port  e.g. 203.0.113.7:%d" % Cfg.DEFAULT_PORT
	_addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_addr.text_submitted.connect(func(_t: String): _direct_connect())
	bottom.add_child(_addr)
	_fav_btn = Button.new()
	_fav_btn.text = "ADD FAVORITE"
	_fav_btn.custom_minimum_size = Vector2(150, 44)
	_fav_btn.add_theme_font_size_override("font_size", 15)
	_fav_btn.pressed.connect(_favorite_pressed)
	bottom.add_child(_fav_btn)
	var direct := Button.new()
	direct.text = "DIRECT CONNECT"
	direct.custom_minimum_size = Vector2(160, 44)
	direct.add_theme_font_size_override("font_size", 15)
	direct.pressed.connect(_direct_connect)
	bottom.add_child(direct)
	_join_btn = Button.new()
	_join_btn.text = "JOIN"
	_join_btn.custom_minimum_size = Vector2(110, 44)
	_join_btn.add_theme_font_override("font", UiTheme.font(700))
	var n := UiTheme.box(Color(0.91, 0.565, 0.18, 0.85), UiTheme.ACCENT, 2, 1, 14.0)
	var h := UiTheme.box(Color(1.0, 0.66, 0.3, 0.95), Color.WHITE, 2, 1, 14.0)
	_join_btn.add_theme_stylebox_override("normal", n)
	_join_btn.add_theme_stylebox_override("hover", h)
	_join_btn.add_theme_stylebox_override("pressed", h)
	_join_btn.add_theme_color_override("font_color", Color(0.08, 0.06, 0.04))
	_join_btn.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.02))
	_join_btn.pressed.connect(func(): _join(_selected))
	bottom.add_child(_join_btn)

	visibility_changed.connect(func():
		if is_visible_in_tree():
			do_refresh())
	_rebuild()


# --- Browser access (all guarded) ------------------------------------------------
func _main() -> Node:
	return get_node_or_null("/root/Main")


func _browser() -> Object:
	var m := _main()
	if m == null:
		return null
	var b = m.get("browser")
	if b is Object and is_instance_valid(b):
		_bind(b)
		return b
	return null


func _bind(b: Object) -> void:
	if b == _bound_browser:
		return
	_bound_browser = b
	if b.has_signal("servers_changed"):
		b.connect("servers_changed", _on_servers_changed)


func _on_servers_changed(_a = null, _b = null) -> void:
	_rebuild()


func _servers() -> Array:
	var b := _browser()
	if b == null:
		return []
	var s = b.get("servers")
	return s if s is Array else []


func do_refresh() -> void:
	var b := _browser()
	if b != null and b.has_method("refresh"):
		b.call("refresh")
		_status.text = "Searching…"
	_rebuild()


# --- Table ----------------------------------------------------------------------
func _header() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(4, 0)
	h.add_child(pad)
	for c in COLS:
		var l := UiTheme.label(String(c[0]), 13, UiTheme.TEXT_DIM, 600, 0)
		_size_cell(l, int(c[1]))
		h.add_child(l)
	return h


func _size_cell(l: Label, w: int) -> void:
	if w == 0:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	else:
		l.custom_minimum_size = Vector2(w, 0)


func _visible_servers() -> Array:
	var out := []
	for s in _servers():
		if not (s is Dictionary):
			continue
		var src := String(s.get("source", ""))
		if _filter == "all" or src == _filter:
			out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary):
		var pa := int(a.get("ping_ms", 9999))
		var pb := int(b.get("ping_ms", 9999))
		if pa < 0:
			pa = 9999
		if pb < 0:
			pb = 9999
		return pa < pb)
	return out


func _rebuild() -> void:
	if _rows == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	_row_nodes.clear()
	var list := _visible_servers()
	var found_sel := false
	for s in list:
		var sd: Dictionary = s
		var row := _row(sd)
		_rows.add_child(row)
		_row_nodes.append({"button": row, "server": sd})
		if _same(sd, _selected):
			found_sel = true
	if not found_sel:
		_selected = {}
	_refresh_selection()
	var total := _servers().size()
	if _browser() == null:
		_status.text = "Server list unavailable — use Direct Connect with the host's IP."
	elif list.is_empty():
		_status.text = "No servers found%s. Host a match, or ask a friend for their IP." % ("" if _filter == "all" else " in this list")
	else:
		_status.text = "%d server%s  ·  %d total" % [list.size(), "" if list.size() == 1 else "s", total]


func _same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return String(a.get("host", "")) == String(b.get("host", "")) and int(a.get("port", 0)) == int(b.get("port", 0))


func _row(s: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 40)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = false
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -8
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var nm := String(s.get("name", "Unnamed server"))
	if bool(s.get("password", false)):
		nm = "[PW]  " + nm
	var cells := [
		nm,
		String(MAP_NAMES.get(String(s.get("map", "")), String(s.get("map", "?")).capitalize())),
		String(Cfg.MODE_NAMES.get(String(s.get("mode", "")), String(s.get("mode", "?")))),
		_players_text(s),
		_ping_text(s),
	]
	for i in cells.size():
		var col := UiTheme.TEXT
		if i == 4:
			col = _ping_color(int(s.get("ping_ms", -1)))
		elif i == 3 and int(s.get("players", 0)) >= int(s.get("max_players", 99)):
			col = UiTheme.BAD
		var l := UiTheme.label(String(cells[i]), 15, col, 600 if i == 0 else 400, 0)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_size_cell(l, int(COLS[i][1]))
		h.add_child(l)
	h.add_child(_source_tag(String(s.get("source", ""))))
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_selected = s
			_refresh_selection()
			if (ev as InputEventMouseButton).double_click:
				_join(s))
	return b


func _players_text(s: Dictionary) -> String:
	var t := "%d / %d" % [int(s.get("players", 0)), int(s.get("max_players", 0))]
	var bots := int(s.get("bots", 0))
	if bots > 0:
		t += "  +%d" % bots
	return t


func _ping_text(s: Dictionary) -> String:
	var p := int(s.get("ping_ms", -1))
	return "—" if p < 0 else "%d" % p


func _ping_color(p: int) -> Color:
	if p < 0:
		return UiTheme.TEXT_DIM
	if p < 60:
		return UiTheme.GOOD
	if p < 130:
		return Color(1, 0.82, 0.3)
	return UiTheme.BAD


func _source_tag(src: String) -> Control:
	var txt := {"lan": "LAN", "master": "NET", "favorite": "FAV"}.get(src, src.to_upper()) as String
	var col := {"lan": Color(0.45, 0.85, 0.55), "master": Color(0.5, 0.72, 1.0), "favorite": UiTheme.ACCENT}.get(src, UiTheme.TEXT_DIM) as Color
	var p := PanelContainer.new()
	var st := UiTheme.box(Color(col.r, col.g, col.b, 0.16), col, 2, 1, 6.0)
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.custom_minimum_size = Vector2(56, 0)
	var l := UiTheme.label(txt, 12, col, 700, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _refresh_selection() -> void:
	for r in _row_nodes:
		var b: Button = r["button"]
		var sel := _same(r["server"], _selected)
		if sel:
			var st := UiTheme.box(Color(0.91, 0.565, 0.18, 0.22), UiTheme.ACCENT, 2, 1, 14.0)
			st.border_width_left = 4
			b.add_theme_stylebox_override("normal", st)
		else:
			b.remove_theme_stylebox_override("normal")
	if _join_btn:
		_join_btn.disabled = _selected.is_empty()
	if _fav_btn:
		var is_fav := not _selected.is_empty() and String(_selected.get("source", "")) == "favorite" and _addr.text.strip_edges() == ""
		_fav_btn.text = "REMOVE FAVORITE" if is_fav else "ADD FAVORITE"


# --- Actions ---------------------------------------------------------------------
func _join(s: Dictionary) -> void:
	if s.is_empty():
		return
	Sfx.play("click")
	var host := String(s.get("host", ""))
	var port := int(s.get("port", Cfg.DEFAULT_PORT))
	if host == "":
		return
	Cfg.settings["last_ip"] = host
	Cfg.settings["last_port"] = port
	Cfg.save_settings()
	status_requested.emit("Connecting to %s (%s:%d)…" % [String(s.get("name", host)), host, port])
	var m := _main()
	if m != null and m.has_method("join"):
		m.call("join", host, port)


## Parses "host", "host:port". Returns ["", 0] on failure.
func _parse_addr(text: String) -> Array:
	var t := text.strip_edges()
	if t == "":
		return ["", 0]
	var host := t
	var port := Cfg.DEFAULT_PORT
	var i := t.rfind(":")
	if i > 0 and t.count(":") == 1:
		host = t.substr(0, i).strip_edges()
		var ps := t.substr(i + 1).strip_edges()
		if not ps.is_valid_int():
			return ["", 0]
		port = int(ps)
	if host == "" or port < 1 or port > 65535:
		return ["", 0]
	return [host, port]


func _direct_connect() -> void:
	var a := _parse_addr(_addr.text)
	if String(a[0]) == "":
		status_requested.emit("Enter an address like 203.0.113.7:%d" % Cfg.DEFAULT_PORT)
		return
	_join({"host": a[0], "port": a[1], "name": "%s:%d" % [a[0], a[1]]})


func _favorite_pressed() -> void:
	Sfx.play("click")
	var b := _browser()
	var typed := _parse_addr(_addr.text)
	if String(typed[0]) != "":
		if b != null and b.has_method("add_favorite"):
			b.call("add_favorite", String(typed[0]), int(typed[1]))
			status_requested.emit("Added %s:%d to favourites." % [typed[0], typed[1]])
			_addr.text = ""
			_filter = "favorite"
			(_filter_buttons["favorite"] as Button).button_pressed = true
		else:
			status_requested.emit("Server list unavailable.")
		_rebuild()
		return
	if not _selected.is_empty() and b != null:
		var host := String(_selected.get("host", ""))
		var port := int(_selected.get("port", 0))
		if String(_selected.get("source", "")) == "favorite":
			if b.has_method("remove_favorite"):
				b.call("remove_favorite", host, port)
				status_requested.emit("Removed %s:%d from favourites." % [host, port])
		elif b.has_method("add_favorite"):
			b.call("add_favorite", host, port)
			status_requested.emit("Added %s to favourites." % String(_selected.get("name", host)))
		_rebuild()
		return
	status_requested.emit("Select a server or type IP:port first.")
