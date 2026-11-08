class_name HudRadar
extends Control
## Rotating top-down radar: map image from World.radar_image() (1 px = 0.5 m), view direction up.

const SCALE := 3.0 # screen px per metre
var _tex: Texture2D
var _world_ref: World
var _blink := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(220, 220)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_blink += delta
	queue_redraw()


func _get_tex(w: World) -> Texture2D:
	if w != _world_ref or _tex == null:
		_world_ref = w
		var img := w.radar_image()
		_tex = ImageTexture.create_from_image(img) if img != null else null
	return _tex


func _to_screen(c: Vector2, p: Vector2, yaw: float, q: Vector3) -> Vector2:
	var v := (Vector2(q.x, q.z) - p) * SCALE
	return c + v.rotated(yaw)


func _clamp_edge(c: Vector2, sp: Vector2) -> Vector2:
	var lim := size * 0.5 - Vector2(7, 7)
	var d := sp - c
	if absf(d.x) <= lim.x and absf(d.y) <= lim.y:
		return sp
	var k := minf(lim.x / maxf(absf(d.x), 0.001), lim.y / maxf(absf(d.y), 0.001))
	return c + d * k


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.03, 0.035, 0.04, 0.72))
	var g := Game.inst
	if g == null or g.world == null:
		draw_rect(rect, UiTheme.BORDER, false, 1.0)
		return
	var c := size * 0.5
	var me: Soldier = g.local_soldier
	var focus: Node3D = me
	var spec := UiTheme.spectate_target(g)
	if (me == null or not me.alive) and spec != null:
		focus = spec
	var p := Vector2.ZERO
	var yaw := 0.0
	if focus != null:
		p = Vector2(focus.global_position.x, focus.global_position.z)
		yaw = float(focus.get("yaw"))
	else:
		var cam := get_viewport().get_camera_3d()
		if cam:
			p = Vector2(cam.global_position.x, cam.global_position.z)
			yaw = cam.global_rotation.y
	var tex := _get_tex(g.world)
	if tex:
		draw_set_transform(c, yaw, Vector2(SCALE * 0.5, SCALE * 0.5))
		draw_texture(tex, -p * 2.0, Color(0.85, 0.88, 0.9, 0.9))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var my_team: int = g.local_team
	if me != null:
		my_team = me.team
	var now: float = g.now()
	var w: World = g.world
	# Sites
	for name in w.sites.keys():
		var sc := w.site_center(String(name))
		var sp := _clamp_edge(c, _to_screen(c, p, yaw, sc))
		var col := Color(1, 0.85, 0.3, 0.9)
		var bomb: Dictionary = g.rs.get("bomb", {})
		if String(bomb.get("state", "")) == "planted" and w.in_site(bomb.get("pos", Vector3.ZERO)) == String(name) and fmod(_blink, 0.6) < 0.3:
			col = Color(1, 0.2, 0.15)
		_draw_letter(sp, String(name), col)
	# Soldiers
	for s in g.soldiers.values():
		var so: Soldier = s
		if not so.alive or so == focus:
			continue
		var friendly := so.team == my_team
		if not friendly and so.spotted_until <= now and my_team >= 0:
			continue
		if my_team < 0 and not friendly:
			pass # spectators see everyone
		var sp := _clamp_edge(c, _to_screen(c, p, yaw, so.global_position))
		var col := UiTheme.team_color(so.team)
		if not friendly and my_team >= 0:
			col = Color(0.95, 0.2, 0.15)
		if not friendly and my_team >= 0:
			var dm := PackedVector2Array([sp + Vector2(0, -6), sp + Vector2(6, 0), sp + Vector2(0, 6), sp + Vector2(-6, 0)])
			var di := PackedVector2Array([sp + Vector2(0, -4.5), sp + Vector2(4.5, 0), sp + Vector2(0, 4.5), sp + Vector2(-4.5, 0)])
			draw_colored_polygon(dm, Color(0, 0, 0, 0.75))
			draw_colored_polygon(di, col)
		else:
			draw_circle(sp, 5.0, Color(0, 0, 0, 0.7))
			draw_circle(sp, 3.8, col)
			var fd := Vector2(-sin(float(so.yaw)), -cos(float(so.yaw))).rotated(yaw)
			draw_line(sp + fd * 4.0, sp + fd * 8.5, col, 2.0)
		if friendly and so.has_bomb and my_team == Cfg.ATK and not UiTheme.is_hunt():
			draw_arc(sp, 6.5, 0, TAU, 16, Color(1, 0.3, 0.2), 1.5)
	# Bomb
	var b: Dictionary = g.rs.get("bomb", {})
	var st := String(b.get("state", "none"))
	if (st == "dropped" or st == "planted") and (my_team == Cfg.ATK or my_team < 0):
		var bp := _clamp_edge(c, _to_screen(c, p, yaw, b.get("pos", Vector3.ZERO)))
		var bc := Color(1, 0.25, 0.15) if st == "planted" and fmod(_blink, 0.5) < 0.25 else Color(1, 0.75, 0.2)
		HudIcons.bomb(self, bp, 11.0, bc)
	# Self arrow
	HudIcons.arrow(self, c, 7.0, 0.0, Color(0, 0, 0, 0.7))
	HudIcons.arrow(self, c, 6.0, 0.0, Color.WHITE)
	# Frame
	draw_rect(rect, Color(1, 1, 1, 0.14), false, 1.0)
	var k := 14.0
	var ac := UiTheme.ACCENT
	for corner in [Vector2(0, 0), Vector2(size.x, 0), Vector2(0, size.y), size]:
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		draw_line(corner, corner + Vector2(k * sx, 0), ac, 2.0)
		draw_line(corner, corner + Vector2(0, k * sy), ac, 2.0)


func _draw_letter(pos: Vector2, text: String, col: Color) -> void:
	var f := UiTheme.font(700)
	var fs := 18
	var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var o := pos + Vector2(-sz.x * 0.5, sz.y * 0.3)
	draw_string_outline(f, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
	draw_string(f, o, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
