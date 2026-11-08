class_name HudOverlay
extends Control
## Damage-direction arcs and hit markers around the screen centre.

var _damage: Array = [] # {angle, t, amount}
var _hit_t := -10.0
var _hit_kill := false
var _hit_head := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## angle: screen angle (radians, 0 = up/forward, clockwise positive). NAN = all around.
func add_damage(angle: float, amount: float) -> void:
	_damage.append({"angle": angle, "t": _now(), "amount": amount})
	if _damage.size() > 8:
		_damage.pop_front()


func add_hit(headshot: bool, killed: bool) -> void:
	_hit_t = _now()
	_hit_kill = killed
	_hit_head = headshot


func _process(_d: float) -> void:
	var t := _now()
	var i := _damage.size() - 1
	while i >= 0:
		if t - float(_damage[i]["t"]) > 1.6:
			_damage.remove_at(i)
		i -= 1
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var t := _now()
	for d in _damage:
		var age := t - float(d["t"])
		var a := clampf(1.0 - age / 1.6, 0.0, 1.0)
		var strength := clampf(float(d["amount"]) / 40.0, 0.4, 1.0)
		var col := Color(0.95, 0.12, 0.08, 0.85 * a * strength)
		var ang := float(d["angle"])
		var r := minf(size.x, size.y) * 0.17
		if is_nan(ang):
			draw_arc(c, r, 0.0, TAU, 64, Color(col.r, col.g, col.b, col.a * 0.5), 6.0, true)
			continue
		# screen angle 0 = up; convert to draw_arc angle (0 = +x)
		var base := ang - PI * 0.5
		draw_arc(c, r, base - 0.32, base + 0.32, 24, col, 7.0, true)
		draw_arc(c, r + 9.0, base - 0.2, base + 0.2, 16, Color(col.r, col.g, col.b, col.a * 0.5), 3.0, true)
	var ht := t - _hit_t
	if ht < 0.3:
		var a2 := 1.0 - ht / 0.3
		var col2 := Color(0.95, 0.15, 0.1, a2) if _hit_kill else Color(1, 1, 1, a2)
		var inner := 7.0
		var outer := 15.0 if not _hit_head else 19.0
		for dv in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dir: Vector2 = dv.normalized()
			draw_line(c + dir * inner, c + dir * outer, Color(0, 0, 0, a2 * 0.6), 4.0, true)
			draw_line(c + dir * inner, c + dir * outer, col2, 2.0, true)
