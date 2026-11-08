class_name HudIcons
extends RefCounted
## Small vector icons drawn with CanvasItem primitives (no font glyph dependencies).


static func health(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var t := s * 0.34
	ci.draw_rect(Rect2(c.x - t * 0.5, c.y - s * 0.5, t, s), col)
	ci.draw_rect(Rect2(c.x - s * 0.5, c.y - t * 0.5, s, t), col)


static func shield(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var h := s * 0.5
	var pts := PackedVector2Array([
		c + Vector2(-h, -h * 0.9), c + Vector2(0, -h * 1.05), c + Vector2(h, -h * 0.9),
		c + Vector2(h * 0.9, h * 0.1), c + Vector2(0, h * 1.05), c + Vector2(-h * 0.9, h * 0.1)])
	ci.draw_colored_polygon(pts, col)


static func helmet(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var r := s * 0.5
	var pts := PackedVector2Array()
	for i in 13:
		var a := PI + PI * float(i) / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r + Vector2(0, r * 0.25))
	pts.append(c + Vector2(r * 1.15, r * 0.25))
	pts.append(c + Vector2(r * 1.15, r * 0.45))
	pts.append(c + Vector2(-r * 1.15, r * 0.45))
	pts.append(c + Vector2(-r * 1.15, r * 0.25))
	ci.draw_colored_polygon(pts, col)


static func bomb(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var w := s
	var h := s * 0.62
	ci.draw_rect(Rect2(c.x - w * 0.5, c.y - h * 0.5, w, h), col)
	ci.draw_rect(Rect2(c.x - w * 0.32, c.y - h * 0.3, w * 0.35, h * 0.32), Color(0, 0, 0, 0.55))
	ci.draw_line(c + Vector2(w * 0.25, -h * 0.5), c + Vector2(w * 0.4, -h * 0.95), col, maxf(1.5, s * 0.08))


static func grenade(ci: CanvasItem, c: Vector2, s: float, col: Color, type: String) -> void:
	var r := s * 0.36
	match type:
		"flash":
			ci.draw_rect(Rect2(c.x - r * 0.75, c.y - r, r * 1.5, r * 2.2), col)
		"smoke":
			ci.draw_rect(Rect2(c.x - r * 0.85, c.y - r * 0.9, r * 1.7, r * 2.1), col)
			ci.draw_rect(Rect2(c.x - r * 0.85, c.y - r * 0.2, r * 1.7, r * 0.3), Color(0, 0, 0, 0.5))
		_:
			ci.draw_circle(c + Vector2(0, r * 0.25), r, col)
	ci.draw_rect(Rect2(c.x - r * 0.35, c.y - r * 1.45, r * 0.7, r * 0.5), col)
	ci.draw_line(c + Vector2(r * 0.3, -r * 1.3), c + Vector2(r * 0.95, -r * 0.4), col, maxf(1.5, s * 0.08))


static func kit(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(c.x - s * 0.45, c.y - s * 0.28, s * 0.9, s * 0.56), col)
	ci.draw_rect(Rect2(c.x - s * 0.18, c.y - s * 0.42, s * 0.36, s * 0.16), col)
	ci.draw_rect(Rect2(c.x - s * 0.05, c.y - s * 0.18, s * 0.1, s * 0.36), Color(0, 0, 0, 0.6))
	ci.draw_rect(Rect2(c.x - s * 0.18, c.y - s * 0.05, s * 0.36, s * 0.1), Color(0, 0, 0, 0.6))


static func charge(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_rect(Rect2(c.x - s * 0.5, c.y - s * 0.16, s, s * 0.32), col)
	for i in 3:
		ci.draw_rect(Rect2(c.x - s * 0.42 + i * s * 0.3, c.y - s * 0.3, s * 0.18, s * 0.14), col)


static func skull(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(0, -s * 0.08), s * 0.42, col)
	ci.draw_rect(Rect2(c.x - s * 0.24, c.y + s * 0.15, s * 0.48, s * 0.3), col)
	ci.draw_circle(c + Vector2(-s * 0.16, -s * 0.06), s * 0.11, Color(0, 0, 0, 0.85))
	ci.draw_circle(c + Vector2(s * 0.16, -s * 0.06), s * 0.11, Color(0, 0, 0, 0.85))


static func arrow(ci: CanvasItem, c: Vector2, s: float, angle: float, col: Color) -> void:
	var f := Vector2(sin(angle), -cos(angle))
	var r := Vector2(-f.y, f.x)
	var pts := PackedVector2Array([c + f * s, c - f * s * 0.6 + r * s * 0.6, c - f * s * 0.25, c - f * s * 0.6 - r * s * 0.6])
	ci.draw_colored_polygon(pts, col)
