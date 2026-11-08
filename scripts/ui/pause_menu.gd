class_name PauseMenu
extends Control
## Esc menu: Resume / Settings / Leave match.

signal resume_requested

var _panel: PanelContainer
var _settings: SettingsPanel


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.045, 0.05, 0.058, 0.95), UiTheme.BORDER, 3, 1, 26.0))
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -190
	_panel.offset_right = 190
	_panel.offset_top = -170
	_panel.offset_bottom = 170
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	v.add_child(UiTheme.label("PAUSED", 30, UiTheme.ACCENT, 700, 0))
	var note := UiTheme.label("The match keeps running.", 14, UiTheme.TEXT_DIM, 400, 0)
	v.add_child(note)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	for item in [["RESUME", "resume"], ["SETTINGS", "settings"], ["LEAVE MATCH", "leave"]]:
		var b := Button.new()
		b.text = String(item[0])
		b.custom_minimum_size = Vector2(320, 48)
		b.add_theme_font_override("font", UiTheme.font(600))
		var act := String(item[1])
		b.pressed.connect(func(): _act(act))
		b.mouse_entered.connect(func(): Sfx.play("click", -16.0, 1.5))
		v.add_child(b)
	_settings = SettingsPanel.new()
	_settings.anchor_left = 0.5
	_settings.anchor_right = 0.5
	_settings.anchor_top = 0.5
	_settings.anchor_bottom = 0.5
	_settings.offset_left = -330
	_settings.offset_right = 330
	_settings.offset_top = -150
	_settings.offset_bottom = 150
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.visible = false
	_settings.closed.connect(func():
		_settings.visible = false
		_panel.visible = true)
	add_child(_settings)


func open() -> void:
	visible = true
	_panel.visible = true
	_settings.visible = false


func back() -> bool:
	## Esc pressed while open: close settings first, else resume. Returns true if menu closed.
	if _settings.visible:
		_settings.close()
		return false
	return true


func _act(a: String) -> void:
	Sfx.play("click")
	match a:
		"resume":
			resume_requested.emit()
		"settings":
			_panel.visible = false
			_settings.visible = true
		"leave":
			var main := get_node_or_null("/root/Main")
			if main and main.has_method("leave_game"):
				main.leave_game()
			else:
				get_tree().quit()
