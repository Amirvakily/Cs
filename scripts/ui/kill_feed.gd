class_name KillFeed
extends VBoxContainer
## Top-right kill notices: killer [weapon] (HS/WB) victim.

const LIFETIME := 7.0
const MAX_ROWS := 6


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_BEGIN
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func add_kill(killer_name: String, killer_team: int, victim_name: String, victim_team: int, weapon_id: String, headshot: bool, wallbang: bool, involves_me: bool) -> void:
	var row := PanelContainer.new()
	var bg := Color(0.04, 0.045, 0.05, 0.72)
	var border := Color(0.91, 0.565, 0.18, 0.9) if involves_me else Color(1, 1, 1, 0.06)
	var st := UiTheme.box(bg, border, 2, 1, 9.0)
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", st)
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	if killer_name != "" and killer_name != victim_name:
		h.add_child(UiTheme.label(killer_name, 16, UiTheme.team_color(killer_team), 600, 3))
	var wname := _short_weapon(weapon_id)
	h.add_child(UiTheme.label(wname, 14, Color(0.85, 0.85, 0.85), 500, 3))
	if wallbang:
		h.add_child(_badge("WB", Color(0.5, 0.75, 1.0)))
	if headshot:
		h.add_child(_badge("HS", Color(1.0, 0.35, 0.3)))
	h.add_child(UiTheme.label(victim_name, 16, UiTheme.team_color(victim_team), 600, 3))
	add_child(row)
	while get_child_count() > MAX_ROWS:
		var c := get_child(0)
		remove_child(c)
		c.queue_free()
	var tw := row.create_tween()
	tw.tween_interval(LIFETIME)
	tw.tween_property(row, "modulate:a", 0.0, 0.6)
	tw.tween_callback(row.queue_free)


func _badge(text: String, col: Color) -> Control:
	var p := PanelContainer.new()
	var st := UiTheme.box(Color(col.r, col.g, col.b, 0.2), col, 2, 1, 4.0)
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UiTheme.label(text, 13, col, 700, 0))
	return p


static func _short_weapon(id: String) -> String:
	match id:
		"":
			return "[ world ]"
		"world", "fall":
			return "[ fall ]"
		"bomb":
			return "[ demo charge ]"
		"frag":
			return "[ frag ]"
		"breach":
			return "[ breach ]"
		"knife":
			return "[ knife ]"
	var n := Cfg.item_name(id)
	return "[ %s ]" % n.to_lower()
