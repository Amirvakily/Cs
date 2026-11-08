class_name HudIcon
extends Control
## A Control that draws one HudIcons glyph.

var kind := "health"
var color := Color.WHITE
var glyph_size := 18.0


func _init(p_kind := "health", p_color := Color.WHITE, p_size := 18.0) -> void:
	kind = p_kind
	color = p_color
	glyph_size = p_size
	custom_minimum_size = Vector2(p_size + 6.0, p_size + 6.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_color(c: Color) -> void:
	if c != color:
		color = c
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var s := glyph_size
	var shadow := Color(0, 0, 0, 0.55 * color.a)
	for pass_i in 2:
		var off := Vector2(1.5, 1.5) if pass_i == 0 else Vector2.ZERO
		var col := shadow if pass_i == 0 else color
		match kind:
			"health":
				HudIcons.health(self, c + off, s, col)
			"shield":
				HudIcons.shield(self, c + off, s, col)
			"helmet":
				HudIcons.helmet(self, c + off, s, col)
			"bomb":
				HudIcons.bomb(self, c + off, s, col)
			"kit":
				HudIcons.kit(self, c + off, s, col)
			"breach":
				HudIcons.charge(self, c + off, s, col)
			"frag", "flash", "smoke":
				HudIcons.grenade(self, c + off, s, col, kind)
			"skull":
				HudIcons.skull(self, c + off, s, col)
