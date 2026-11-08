class_name HudCrosshair
extends Control
## Dynamic crosshair. `gap` in pixels; mode 0 = lines, 1 = centre dot (cover), 2 = hidden.

var gap := 8.0
var mode := 0
var flash := 0.0 # brief expansion on firing


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if mode == 2:
		return
	var c := (size * 0.5).round()
	var col := Cfg.crosshair_color()
	var outline := Color(0, 0, 0, 0.7)
	if mode == 1:
		draw_circle(c, 3.2, outline)
		draw_circle(c, 2.0, col)
		return
	var g := roundf(gap + flash)
	var ln := 9.0
	var th := 2.0
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var dir: Vector2 = d
		var a := c + dir * g
		var b := c + dir * (g + ln)
		var r := Rect2(a, b - a).abs()
		if dir.x != 0.0:
			r = Rect2(Vector2(minf(a.x, b.x), c.y - th * 0.5), Vector2(ln, th))
		else:
			r = Rect2(Vector2(c.x - th * 0.5, minf(a.y, b.y)), Vector2(th, ln))
		draw_rect(r.grow(1.0), outline)
		draw_rect(r, col)
