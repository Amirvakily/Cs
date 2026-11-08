class_name UiTheme
extends RefCounted
## Shared look for menus and HUD: dark translucent panels, thin borders, orange accent.

const ACCENT := Color("e8902e")
const ACCENT_DIM := Color(0.91, 0.565, 0.18, 0.35)
const BG := Color(0.055, 0.06, 0.07, 0.82)
const BG_SOLID := Color(0.06, 0.065, 0.075, 0.96)
const BG_LIGHT := Color(1, 1, 1, 0.045)
const BORDER := Color(1, 1, 1, 0.11)
const TEXT := Color(0.93, 0.93, 0.91)
const TEXT_DIM := Color(0.6, 0.62, 0.64)
const GOOD := Color(0.45, 0.86, 0.42)
const BAD := Color(0.96, 0.3, 0.26)
const MONEY := Color(0.55, 0.9, 0.45)

static var _theme: Theme
static var _fonts := {}


## Condensed/tactical system font with sensible fallbacks (Bahnschrift ships with Windows 10+).
static func font(weight := 400) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Inter", "Roboto", "Noto Sans", "DejaVu Sans", "Arial"])
	f.font_weight = weight
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.generate_mipmaps = false
	_fonts[weight] = f
	return f


static func box(bg := BG, border := BORDER, radius := 3, border_w := 1, margin := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.7
	s.content_margin_bottom = margin * 0.7
	s.anti_aliasing = true
	return s


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font(400)
	t.default_font_size = 18

	# Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)

	# Panels
	t.set_stylebox("panel", "Panel", box())
	t.set_stylebox("panel", "PanelContainer", box())

	# Buttons
	var bn := box(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.08), 2, 1, 14.0)
	var bh := box(Color(0.91, 0.565, 0.18, 0.2), ACCENT, 2, 1, 14.0)
	bh.border_width_left = 4
	var bp := box(Color(0.91, 0.565, 0.18, 0.38), ACCENT, 2, 1, 14.0)
	bp.border_width_left = 4
	var bd := box(Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.04), 2, 1, 14.0)
	var bf := StyleBoxEmpty.new()
	for cls in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, bn)
		t.set_stylebox("hover", cls, bh)
		t.set_stylebox("pressed", cls, bp)
		t.set_stylebox("hover_pressed", cls, bp)
		t.set_stylebox("disabled", cls, bd)
		t.set_stylebox("focus", cls, bf)
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color.WHITE)
		t.set_color("font_hover_pressed_color", cls, Color.WHITE)
		t.set_color("font_focus_color", cls, TEXT)
		t.set_color("font_disabled_color", cls, Color(0.45, 0.46, 0.48))
	# CheckBox: keep default icons, flat background
	var cb := StyleBoxEmpty.new()
	cb.content_margin_left = 4
	cb.content_margin_right = 4
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "CheckBox", cb)
	t.set_icon("checked", "CheckBox", _check_icon(true, false))
	t.set_icon("unchecked", "CheckBox", _check_icon(false, false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true, true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false, true))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)

	# Line edits / spin boxes
	var le := box(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.14), 2, 1, 10.0)
	var lef := box(Color(0, 0, 0, 0.55), ACCENT, 2, 1, 10.0)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_stylebox("read_only", "LineEdit", le)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", ACCENT_DIM)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.3))

	# Sliders
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.12)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	track.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	fill.set_corner_radius_all(2)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)

	# Popups (OptionButton lists)
	var pp := box(BG_SOLID, BORDER, 2, 1, 6.0)
	t.set_stylebox("panel", "PopupMenu", pp)
	t.set_stylebox("hover", "PopupMenu", box(Color(0.91, 0.565, 0.18, 0.3), Color(0, 0, 0, 0), 2, 0, 6.0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "TooltipPanel", box(BG_SOLID, ACCENT_DIM, 2, 1, 8.0))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# Scroll bars: slim
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.content_margin_left = 3
	sb.content_margin_right = 3
	var sg := StyleBoxFlat.new()
	sg.bg_color = Color(1, 1, 1, 0.25)
	sg.set_corner_radius_all(3)
	sg.content_margin_left = 3
	sg.content_margin_right = 3
	var sgh := sg.duplicate() as StyleBoxFlat
	sgh.bg_color = ACCENT
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", sg)
	t.set_stylebox("grabber_highlight", "VScrollBar", sgh)
	t.set_stylebox("grabber_pressed", "VScrollBar", sgh)

	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)
	_theme = t
	return t


static func _check_icon(on: bool, disabled: bool) -> ImageTexture:
	var n := 20
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var a := 0.45 if disabled else 1.0
	var border := Color(ACCENT, a) if on else Color(1, 1, 1, 0.55 * a)
	for i in n:
		for k in 2:
			img.set_pixel(i, k, border)
			img.set_pixel(i, n - 1 - k, border)
			img.set_pixel(k, i, border)
			img.set_pixel(n - 1 - k, i, border)
	if on:
		img.fill_rect(Rect2i(4, 4, n - 8, n - 8), Color(ACCENT, a))
		var dark := Color(0.08, 0.06, 0.04, a)
		for p in [Vector2i(6, 10), Vector2i(7, 11), Vector2i(8, 12), Vector2i(9, 13), Vector2i(10, 12), Vector2i(11, 11), Vector2i(12, 10), Vector2i(13, 9), Vector2i(14, 8)]:
			img.set_pixel(p.x, p.y, dark)
			img.set_pixel(p.x, p.y - 1, dark)
	return ImageTexture.create_from_image(img)


## Label with outline + shadow for in-game readability.
static func label(text: String, size := 18, color := TEXT, weight := 400, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font = font(weight)
	ls.font_size = size
	ls.font_color = color
	if outline > 0:
		ls.outline_size = outline
		ls.outline_color = Color(0, 0, 0, 0.75)
	ls.shadow_size = 2
	ls.shadow_color = Color(0, 0, 0, 0.45)
	ls.shadow_offset = Vector2(1, 1)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func set_label_color(l: Label, c: Color) -> void:
	if l.label_settings:
		l.label_settings.font_color = c


## Soldier the local camera is following while dead/spectating (or null).
static func spectate_target(g: Game) -> Soldier:
	if g == null:
		return null
	var t = g.get("spectate_target")
	if t is Soldier and is_instance_valid(t):
		return t
	var c = g.get("controller")
	if c is Object and is_instance_valid(c):
		var st = (c as Object).get("spec_target")
		if st is Soldier and is_instance_valid(st):
			return st
	return null


static func is_hunt() -> bool:
	return Game.inst != null and String(Game.inst.config.get("mode", "")) == Cfg.MODE_HUNT


## Team colour, accounting for Squad Hunt (team 0 wears IRON GUARD colours there).
static func team_color(team: int) -> Color:
	if team < 0 or team > 1:
		return TEXT_DIM
	if is_hunt():
		return Cfg.TEAM_COLORS[1 - team]
	return Cfg.TEAM_COLORS[team]


static func team_name(team: int) -> String:
	if team < 0 or team > 1:
		return "SPECTATORS"
	if is_hunt():
		return Cfg.HUNT_TEAM_NAMES[team]
	return Cfg.TEAM_NAMES[team]


static func fmt_time(t: float) -> String:
	var s := maxi(0, ceili(t))
	return "%d:%02d" % [s / 60, s % 60]


static func fmt_money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if v < 0 else "$") + out
