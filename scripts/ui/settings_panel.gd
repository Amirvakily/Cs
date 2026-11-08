class_name SettingsPanel
extends PanelContainer
## Player/graphics/audio settings. Applies changes live, saves on close.

signal closed

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]
const CROSSHAIR_NAMES := ["Green", "White", "Cyan", "Yellow", "Magenta"]

var show_back := true
var _name_edit: LineEdit


func _init(p_show_back := true) -> void:
	show_back = p_show_back


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_SOLID, UiTheme.BORDER, 3, 1, 22.0))
	custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var title := UiTheme.label("SETTINGS", 26, UiTheme.ACCENT, 700, 0)
	v.add_child(title)
	v.add_child(_sep())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)

	_name_edit = LineEdit.new()
	_name_edit.text = String(Cfg.settings["player_name"])
	_name_edit.max_length = 20
	_name_edit.custom_minimum_size = Vector2(300, 0)
	_name_edit.text_changed.connect(func(t: String):
		var n := t.strip_edges()
		if n != "":
			Cfg.settings["player_name"] = n)
	_row(grid, "Player name", _name_edit)

	_row(grid, "Mouse sensitivity", _slider("sensitivity", 0.2, 8.0, 0.05, "%.2f"))
	_row(grid, "Field of view", _slider("fov", 70.0, 110.0, 1.0, "%d°"))
	_row(grid, "Invert mouse Y", _check("invert_y"))
	_row(grid, "Master volume", _slider("master_volume", 0.0, 1.0, 0.01, "pct"))
	_row(grid, "Graphics quality", _option("quality", QUALITY_NAMES))
	_row(grid, "Fullscreen", _check("fullscreen"))
	_row(grid, "Crosshair colour", _option("crosshair_color", CROSSHAIR_NAMES))
	_row(grid, "Show FPS", _check("show_fps"))

	var hint := UiTheme.label("Ultra enables global illumination and volumetric fog — needs a strong GPU.", 14, UiTheme.TEXT_DIM, 400, 0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(560, 0)
	v.add_child(hint)

	if show_back:
		v.add_child(_sep())
		var back := Button.new()
		back.text = "BACK"
		back.custom_minimum_size = Vector2(160, 42)
		back.size_flags_horizontal = Control.SIZE_SHRINK_END
		back.pressed.connect(close)
		v.add_child(back)


func close() -> void:
	Sfx.play("click")
	Cfg.save_settings()
	closed.emit()


func _sep() -> Control:
	var r := ColorRect.new()
	r.color = UiTheme.BORDER
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _row(grid: GridContainer, text: String, ctrl: Control) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(ctrl)


func _apply() -> void:
	Cfg.apply_display_settings()


func _slider(key: String, lo: float, hi: float, step: float, fmt: String) -> Control:
	var h := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Cfg.settings[key])
	s.custom_minimum_size = Vector2(230, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size = Vector2(64, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var upd := func(x: float):
		if fmt == "pct":
			val.text = "%d%%" % roundi(x * 100.0)
		else:
			val.text = fmt % x
	upd.call(s.value)
	s.value_changed.connect(func(x: float):
		Cfg.settings[key] = x
		upd.call(x)
		if key == "master_volume":
			_apply())
	h.add_child(s)
	h.add_child(val)
	return h


func _check(key: String) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = bool(Cfg.settings[key])
	c.text = "On" if c.button_pressed else "Off"
	c.toggled.connect(func(on: bool):
		Sfx.play("click")
		Cfg.settings[key] = on
		c.text = "On" if on else "Off"
		_apply())
	return c


func _option(key: String, names: Array) -> OptionButton:
	var o := OptionButton.new()
	for n in names:
		o.add_item(String(n))
	o.selected = clampi(int(Cfg.settings[key]), 0, names.size() - 1)
	o.item_selected.connect(func(i: int):
		Sfx.play("click")
		Cfg.settings[key] = i
		_apply())
	return o
