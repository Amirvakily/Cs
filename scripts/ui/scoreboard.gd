class_name Scoreboard
extends PanelContainer
## Tab scoreboard: both teams side by side, sorted by score.

var _title: Label
var _sub: Label
var _cols: Array[VBoxContainer] = []
var _spec: Label
var _t := 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.04, 0.045, 0.052, 0.9), UiTheme.BORDER, 3, 1, 22.0))
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -620
	offset_right = 620
	offset_top = -140
	offset_bottom = 140
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UiTheme.label("", 26, UiTheme.ACCENT, 700, 0)
	head.add_child(_title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_sub = UiTheme.label("", 16, UiTheme.TEXT_DIM, 500, 0)
	_sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	v.add_child(body)
	for i in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 3)
		body.add_child(col)
		_cols.append(col)
	_spec = UiTheme.label("", 14, UiTheme.TEXT_DIM, 400, 0)
	_spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_spec)


func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		refresh()


func refresh() -> void:
	var g := Game.inst
	if g == null:
		return
	var mode := String(g.config.get("mode", Cfg.MODE_DEFUSAL))
	var map_name := String(g.config.get("map", ""))
	if g.world != null and g.world.data.has("name"):
		map_name = String(g.world.data["name"])
	_title.text = "%s  ·  %s" % [String(Cfg.MODE_NAMES.get(mode, mode)).to_upper(), map_name.to_upper()]
	match mode:
		"defusal":
			_sub.text = "Round %d of %d" % [int(g.rs.get("round", 1)), int(g.rs.get("max_rounds", 16))]
		"tdm":
			_sub.text = "First to %d kills" % int(g.rs.get("kill_limit", 0))
		_:
			_sub.text = "%d hostiles remaining" % int(g.rs.get("hostiles_left", 0))
	var me: Soldier = g.local_soldier
	var my_team: int = me.team if me != null else g.local_team
	var score: Array = g.rs.get("score", [0, 0])
	var specs: Array[String] = []
	var by_team := [[], []]
	for s in g.soldiers.values():
		var so: Soldier = s
		if so.team == 0 or so.team == 1:
			by_team[so.team].append(so)
		else:
			specs.append(so.display_name)
	for t in 2:
		var col := _cols[t]
		for c in col.get_children():
			c.queue_free()
		var list: Array = by_team[t]
		list.sort_custom(func(a: Soldier, b: Soldier): return a.score > b.score if a.score != b.score else a.kills > b.kills)
		var alive := 0
		for so in list:
			if (so as Soldier).alive:
				alive += 1
		var tc := UiTheme.team_color(t)
		var hdr := PanelContainer.new()
		var hs := UiTheme.box(Color(tc.r, tc.g, tc.b, 0.16), Color(tc.r, tc.g, tc.b, 0.6), 2, 0, 12.0)
		hs.border_width_bottom = 2
		hdr.add_theme_stylebox_override("panel", hs)
		var hh := HBoxContainer.new()
		hdr.add_child(hh)
		var tn := UiTheme.label(UiTheme.team_name(t), 22, tc, 700, 0)
		tn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(tn)
		hh.add_child(UiTheme.label("%d alive" % alive, 15, UiTheme.TEXT_DIM, 500, 0))
		var sc := UiTheme.label(str(int(score[t]) if t < score.size() else 0), 30, Color.WHITE, 800, 0)
		sc.custom_minimum_size = Vector2(56, 0)
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hh.add_child(sc)
		col.add_child(hdr)
		col.add_child(_row(["PLAYER", "K", "D", "SCORE", "MONEY" if t == my_team else ""], UiTheme.TEXT_DIM, 13, 600, false, null))
		for so in list:
			var s2: Soldier = so
			var name := s2.display_name
			if s2.is_bot:
				name += "  BOT"
			var money := UiTheme.fmt_money(s2.money) if t == my_team and mode == Cfg.MODE_DEFUSAL else ""
			var c := Color.WHITE if s2.alive else Color(1, 1, 1, 0.38)
			col.add_child(_row([name, str(s2.kills), str(s2.deaths), str(s2.score), money], c, 16, 500, s2 == me, s2))
	_spec.text = ("Spectators: " + ", ".join(PackedStringArray(specs))) if specs.size() > 0 else ""


func _row(cells: Array, col: Color, size: int, weight: int, highlight: bool, s: Soldier) -> Control:
	var p := PanelContainer.new()
	var st := UiTheme.box(Color(0.91, 0.565, 0.18, 0.14) if highlight else Color(1, 1, 1, 0.025), Color(0, 0, 0, 0), 2, 0, 10.0)
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	p.add_child(h)
	var widths := [0, 44, 44, 64, 86]
	for i in cells.size():
		var l := UiTheme.label(String(cells[i]), size, col, weight, 0)
		if i == 0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
			l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		else:
			l.custom_minimum_size = Vector2(widths[i], 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			if i == 4 and s != null:
				UiTheme.set_label_color(l, Color(UiTheme.MONEY, col.a))
		h.add_child(l)
		if i == 0 and s != null:
			if not s.alive:
				var dead := UiTheme.label("DEAD", 12, UiTheme.BAD, 700, 0)
				dead.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				h.add_child(dead)
				h.move_child(dead, 1)
	return p
