class_name TeamSelect
extends PanelContainer
## Choose team: two team cards + auto-assign + spectate.

signal chosen(team: int)
signal close_requested

var _cards: Array = []
var _box: HBoxContainer
var _title: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.045, 0.05, 0.058, 0.94), UiTheme.BORDER, 3, 1, 26.0))
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -440
	offset_right = 440
	offset_top = -240
	offset_bottom = 240
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	add_child(v)
	_title = UiTheme.label("CHOOSE YOUR TEAM", 28, UiTheme.ACCENT, 700, 0)
	v.add_child(_title)
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 16)
	_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_box)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	v.add_child(foot)
	var auto := Button.new()
	auto.text = "AUTO-ASSIGN"
	auto.custom_minimum_size = Vector2(200, 44)
	auto.pressed.connect(_auto)
	foot.add_child(auto)
	var spec := Button.new()
	spec.text = "SPECTATE"
	spec.custom_minimum_size = Vector2(160, 44)
	spec.pressed.connect(func(): _pick(Cfg.SPEC))
	foot.add_child(spec)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(120, 44)
	close.pressed.connect(func():
		Sfx.play("click")
		close_requested.emit())
	foot.add_child(close)
	rebuild()


func rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	_cards.clear()
	var hunt := UiTheme.is_hunt()
	var teams := [0] if hunt else [Cfg.ATK, Cfg.DEF]
	for t in teams:
		_box.add_child(_card(int(t), hunt))


func _counts(team: int) -> Vector2i:
	var humans := 0
	var bots := 0
	if Game.inst:
		for s in Game.inst.soldiers.values():
			var so: Soldier = s
			if so.team == team:
				if so.is_bot:
					bots += 1
				else:
					humans += 1
	return Vector2i(humans, bots)


func _card(team: int, hunt: bool) -> Control:
	var tc := UiTheme.team_color(team)
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 240)
	var n := UiTheme.box(Color(tc.r, tc.g, tc.b, 0.1), Color(tc.r, tc.g, tc.b, 0.45), 3, 1, 18.0)
	var h := UiTheme.box(Color(tc.r, tc.g, tc.b, 0.24), tc, 3, 2, 18.0)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.pressed.connect(func(): _pick(team))
	b.mouse_entered.connect(func(): Sfx.play("click", -16.0, 1.5))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 22
	v.offset_right = -22
	v.offset_top = 20
	v.offset_bottom = -20
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	b.add_child(v)
	var role := ""
	if hunt:
		role = "Squad — clear the map of hostiles"
	elif team == Cfg.ATK:
		role = "Attackers — plant the demo charge at A or B"
	else:
		role = "Defenders — protect the sites, defuse the charge"
	v.add_child(UiTheme.label(UiTheme.team_name(team), 34, tc, 800, 0))
	var r := UiTheme.label(role, 16, UiTheme.TEXT, 400, 0)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(r)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	var cnt := _counts(team)
	v.add_child(UiTheme.label("%d %s  ·  %d %s" % [cnt.x, "player" if cnt.x == 1 else "players", cnt.y, "bot" if cnt.y == 1 else "bots"], 16, UiTheme.TEXT_DIM, 500, 0))
	var key := UiTheme.label("JOIN", 20, Color.WHITE, 700, 0)
	v.add_child(key)
	_cards.append(b)
	return b


func _auto() -> void:
	if UiTheme.is_hunt():
		_pick(0)
		return
	var a := _counts(Cfg.ATK)
	var d := _counts(Cfg.DEF)
	_pick(Cfg.ATK if a.x <= d.x else Cfg.DEF)


func _pick(team: int) -> void:
	Sfx.play("click")
	if Game.inst:
		Game.inst.request_join_team(team)
	chosen.emit(team)


func handle_key(keycode: int) -> bool:
	if keycode == KEY_1:
		_pick(0)
		return true
	if keycode == KEY_2 and not UiTheme.is_hunt():
		_pick(1)
		return true
	if keycode == KEY_5:
		_auto()
		return true
	if keycode == KEY_6:
		_pick(Cfg.SPEC)
		return true
	return false
