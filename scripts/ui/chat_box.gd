class_name ChatBox
extends VBoxContainer
## Chat log + input line. Messages fade unless the input is open.

signal submitted(text: String, team_only: bool)
signal closed

const MAX_LINES := 8
const LIFETIME := 10.0

var is_open := false
var team_only := false
var _log: VBoxContainer
var _input_row: HBoxContainer
var _prefix: Label
var _input: LineEdit
var _lines: Array = [] # {node, t}


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 2)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.alignment = BoxContainer.ALIGNMENT_END
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_log)
	_input_row = HBoxContainer.new()
	_input_row.visible = false
	add_child(_input_row)
	_prefix = UiTheme.label("ALL:", 16, UiTheme.ACCENT, 600, 3)
	_input_row.add_child(_prefix)
	_input = LineEdit.new()
	_input.max_length = 120
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Type a message…"
	_input.context_menu_enabled = false
	_input_row.add_child(_input)
	_input.text_submitted.connect(_on_submit)
	_input.gui_input.connect(_on_input_gui)


func open(p_team_only: bool) -> void:
	is_open = true
	team_only = p_team_only
	_prefix.text = "TEAM:" if team_only else "ALL:"
	_input_row.visible = true
	_input.text = ""
	_input.grab_focus.call_deferred()
	for l in _lines:
		(l["node"] as Control).modulate.a = 1.0


func close() -> void:
	if not is_open:
		return
	is_open = false
	_input_row.visible = false
	_input.release_focus()
	closed.emit()


func add_message(from_name: String, team: int, text: String, p_team_only: bool) -> void:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(440, 0)
	rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rt.add_theme_font_override("normal_font", UiTheme.font(500))
	rt.add_theme_font_override("bold_font", UiTheme.font(700))
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 16)
	rt.add_theme_constant_override("outline_size", 4)
	rt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	var safe := text.replace("[", "[lb]")
	if from_name == "":
		rt.text = "[color=#%s]%s[/color]" % [UiTheme.ACCENT.to_html(false), safe]
	else:
		var tag := "[TEAM] " if p_team_only else ""
		var col := UiTheme.team_color(team).to_html(false)
		rt.text = "[color=#aaaaaa]%s[/color][b][color=#%s]%s[/color][/b]: %s" % [tag.replace("[", "[lb]"), col, from_name.replace("[", "[lb]"), safe]
	_log.add_child(rt)
	_lines.append({"node": rt, "t": Time.get_ticks_msec() / 1000.0})
	while _lines.size() > MAX_LINES:
		var old: Dictionary = _lines.pop_front()
		(old["node"] as Node).queue_free()


func _process(_d: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for l in _lines:
		var n: Control = l["node"]
		if is_open:
			n.modulate.a = 1.0
		else:
			var age := now - float(l["t"])
			n.modulate.a = clampf((LIFETIME - age) / 1.0, 0.0, 1.0)


func _on_submit(t: String) -> void:
	var msg := t.strip_edges()
	if msg != "":
		submitted.emit(msg, team_only)
	close()


func _on_input_gui(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and (ev as InputEventKey).keycode == KEY_ESCAPE:
		_input.accept_event()
		close()
