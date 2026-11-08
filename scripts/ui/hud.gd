class_name Hud
extends CanvasLayer
## In-game HUD and overlay menus. Reads Game.inst / local_soldier every frame.

const SCOPE_SHADER := """
shader_type canvas_item;
uniform float radius = 0.47;
uniform float aspect = 1.7778;
void fragment() {
	vec2 p = (UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p);
	float outside = smoothstep(radius - 0.003, radius + 0.002, d);
	float vign = smoothstep(radius * 0.5, radius, d) * 0.6;
	float a = max(outside, vign);
	float lw = 0.0011;
	if (d < radius) {
		if (abs(p.x) < lw || abs(p.y) < lw) a = 0.95;
		if (d > radius * 0.6 && (abs(p.x) < lw * 3.5 || abs(p.y) < lw * 3.5)) a = 1.0;
	}
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

const REASONS := {
	"elim": "All enemies eliminated", "elimination": "All enemies eliminated",
	"bomb": "Target destroyed", "exploded": "Target destroyed", "bomb_exploded": "Target destroyed",
	"defuse": "The charge was defused", "defused": "The charge was defused", "bomb_defused": "The charge was defused",
	"time": "Time ran out", "timeout": "Time ran out", "kill_limit": "Kill limit reached",
	"hostiles": "All hostiles eliminated", "squad_dead": "The squad was wiped out",
}

var _game: Game
var _bound := false
var _root: Control

var _crosshair: HudCrosshair
var _overlay: HudOverlay
var _radar: HudRadar
var _killfeed: KillFeed
var _chat: ChatBox
var _buy: BuyMenu
var _score: Scoreboard
var _team: TeamSelect
var _pause: PauseMenu
var _flash: ColorRect
var _scope: ColorRect
var _scope_mat: ShaderMaterial
var _hurt: TextureRect
var _dmg_flash := 0.0

# top bar
var _score_l: Array[Label] = []
var _team_l: Array[Label] = []
var _pips: Array[HBoxContainer] = []
var _pip_sig := ["", ""]
var _timer: Label
var _bomb_icon: HudIcon
var _phase: Label
var _info: Label
var _top: Control

# money
var _money: Label
var _money_delta: Label
var _last_money := -1
var _last_money_owner: Soldier

# vitals
var _vitals: Control
var _hp: Label
var _hp_fill: ColorRect
var _hp_icon: HudIcon
var _ar: Label
var _ar_fill: ColorRect
var _helmet: HudIcon

# weapon
var _weapon_box: Control
var _wname: Label
var _ammo: Label
var _reserve: Label
var _reload_l: Label
var _equip: HBoxContainer
var _equip_sig := ""

# center
var _ann: VBoxContainer
var _ann_title: Label
var _ann_sub: Label
var _ann_tween: Tween
var _hint: Label
var _progress: PanelContainer
var _progress_l: Label
var _progress_fill: ColorRect
var _spectator: PanelContainer
var _spec_title: Label
var _spec_name: Label
var _spec_hint: Label
var _fps: Label

var _team_dismissed := false
var _blink := 0.0


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)
	_build()
	_bind_game()


func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_menu_open() -> bool:
	if _buy == null:
		return false
	return _buy.visible or _team.visible or _pause.visible or _chat.is_open


# --- Construction ------------------------------------------------------------
func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


func _panel(bg := Color(0.035, 0.04, 0.045, 0.62), margin := 12.0) -> PanelContainer:
	var p := PanelContainer.new()
	var st := UiTheme.box(bg, Color(1, 1, 1, 0.07), 3, 1, margin)
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _bar(w: float, h: float, col: Color) -> Array:
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.1)
	bg.custom_minimum_size = Vector2(w, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = col
	fill.anchor_bottom = 1.0
	fill.anchor_right = 1.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(fill)
	return [bg, fill]


func _build() -> void:
	# Scope overlay (bottom-most)
	_scope = ColorRect.new()
	_scope.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scope.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SCOPE_SHADER
	_scope_mat = ShaderMaterial.new()
	_scope_mat.shader = sh
	_scope.material = _scope_mat
	_scope.visible = false
	_root.add_child(_scope)

	# Low-health / damage vignette
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.6, 0.0, 0.0, 0.85))
	g.set_offset(0, 0.45)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 128
	gt.height = 128
	_hurt = TextureRect.new()
	_hurt.texture = gt
	_hurt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hurt.stretch_mode = TextureRect.STRETCH_SCALE
	_hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hurt.modulate.a = 0.0
	_root.add_child(_hurt)

	_crosshair = HudCrosshair.new()
	_root.add_child(_crosshair)
	_overlay = HudOverlay.new()
	_root.add_child(_overlay)

	_build_top()
	_build_radar_money()
	_build_vitals()
	_build_weapon()
	_build_center()

	_killfeed = KillFeed.new()
	_anchor(_killfeed, 1, 0, 1, 0, -620, 20, -20, 300)
	_root.add_child(_killfeed)

	_chat = ChatBox.new()
	_anchor(_chat, 0, 1, 0, 1, 24, -470, 504, -150)
	_root.add_child(_chat)
	_chat.submitted.connect(func(text: String, team_only: bool):
		if _game:
			_game.request_chat(text, team_only))

	_fps = UiTheme.label("", 14, UiTheme.TEXT_DIM, 500, 3)
	_anchor(_fps, 0, 0, 0, 0, 22, 0, 160, 18)
	_root.add_child(_fps)

	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)

	_score = Scoreboard.new()
	_score.visible = false
	_root.add_child(_score)
	_buy = BuyMenu.new()
	_buy.visible = false
	_root.add_child(_buy)
	_team = TeamSelect.new()
	_team.visible = false
	_team.chosen.connect(func(t: int):
		_team_dismissed = true
		_team.visible = false)
	_team.close_requested.connect(func():
		_team_dismissed = true
		_team.visible = false)
	_root.add_child(_team)
	_pause = PauseMenu.new()
	_pause.visible = false
	_pause.resume_requested.connect(func(): _pause.visible = false)
	_root.add_child(_pause)
	for m in [_buy, _team]:
		_no_focus(m)


func _no_focus(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).focus_mode = Control.FOCUS_NONE
	for c in n.get_children():
		_no_focus(c)


func _build_top() -> void:
	_top = HBoxContainer.new()
	(_top as HBoxContainer).add_theme_constant_override("separation", 0)
	(_top as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	_anchor(_top, 0.5, 0, 0.5, 0, -330, 14, 330, 100)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_top)
	for t in 2:
		var side := VBoxContainer.new()
		side.custom_minimum_size = Vector2(220, 0)
		side.add_theme_constant_override("separation", 2)
		side.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var head := HBoxContainer.new()
		head.alignment = BoxContainer.ALIGNMENT_END if t == 0 else BoxContainer.ALIGNMENT_BEGIN
		head.add_theme_constant_override("separation", 12)
		var name := UiTheme.label("", 15, UiTheme.team_color(t), 700, 3)
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sc := UiTheme.label("0", 34, Color.WHITE, 800, 4)
		if t == 0:
			head.add_child(name)
			head.add_child(sc)
		else:
			head.add_child(sc)
			head.add_child(name)
		side.add_child(head)
		var pips := HBoxContainer.new()
		pips.alignment = head.alignment
		pips.add_theme_constant_override("separation", 3)
		side.add_child(pips)
		_team_l.append(name)
		_score_l.append(sc)
		_pips.append(pips)
		if t == 0:
			_top.add_child(side)
			var mid := _panel(Color(0.03, 0.035, 0.04, 0.72), 10.0)
			mid.custom_minimum_size = Vector2(170, 0)
			var mv := VBoxContainer.new()
			mv.add_theme_constant_override("separation", 0)
			mv.alignment = BoxContainer.ALIGNMENT_CENTER
			mid.add_child(mv)
			var tc := CenterContainer.new()
			tc.custom_minimum_size = Vector2(0, 44)
			mv.add_child(tc)
			_timer = UiTheme.label("0:00", 36, Color.WHITE, 700, 3)
			tc.add_child(_timer)
			_bomb_icon = HudIcon.new("bomb", Color(1, 0.25, 0.15), 30.0)
			_bomb_icon.visible = false
			tc.add_child(_bomb_icon)
			_phase = UiTheme.label("", 13, UiTheme.ACCENT, 700, 0)
			_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mv.add_child(_phase)
			_info = UiTheme.label("", 13, UiTheme.TEXT_DIM, 500, 0)
			_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mv.add_child(_info)
			var lpad := Control.new()
			lpad.custom_minimum_size = Vector2(14, 0)
			_top.add_child(lpad)
			_top.add_child(mid)
			var rpad := Control.new()
			rpad.custom_minimum_size = Vector2(14, 0)
			_top.add_child(rpad)
		else:
			_top.add_child(side)


func _build_radar_money() -> void:
	var col := VBoxContainer.new()
	_anchor(col, 0, 0, 0, 0, 20, 20, 260, 330)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 8)
	_root.add_child(col)
	_radar = HudRadar.new()
	_radar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_radar)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 12)
	col.add_child(mrow)
	_money = UiTheme.label("$0", 28, UiTheme.MONEY, 700, 4)
	mrow.add_child(_money)
	_money_delta = UiTheme.label("", 20, UiTheme.MONEY, 700, 4)
	_money_delta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_money_delta.modulate.a = 0.0
	mrow.add_child(_money_delta)


func _build_vitals() -> void:
	var p := _panel(Color(0.03, 0.035, 0.04, 0.6), 14.0)
	_anchor(p, 0, 1, 0, 1, 20, -20, 380, -20)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(p)
	_vitals = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 10)
	v.add_child(hr)
	_hp_icon = HudIcon.new("health", Color.WHITE, 22.0)
	hr.add_child(_hp_icon)
	_hp = UiTheme.label("100", 34, Color.WHITE, 800, 3)
	_hp.custom_minimum_size = Vector2(70, 0)
	hr.add_child(_hp)
	var hb := _bar(200, 8, Color(0.92, 0.92, 0.9))
	(hb[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(hb[0])
	_hp_fill = hb[1]
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 10)
	v.add_child(ar)
	ar.add_child(HudIcon.new("shield", Color(0.62, 0.75, 0.9), 20.0))
	_ar = UiTheme.label("0", 24, Color(0.75, 0.84, 0.95), 700, 3)
	_ar.custom_minimum_size = Vector2(70, 0)
	ar.add_child(_ar)
	var ab := _bar(164, 6, Color(0.5, 0.68, 0.9))
	(ab[0] as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ar.add_child(ab[0])
	_ar_fill = ab[1]
	_helmet = HudIcon.new("helmet", Color(0.75, 0.84, 0.95), 18.0)
	ar.add_child(_helmet)


func _build_weapon() -> void:
	var p := _panel(Color(0.03, 0.035, 0.04, 0.6), 14.0)
	_anchor(p, 1, 1, 1, 1, -20, -20, -20, -20)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.custom_minimum_size = Vector2(260, 0)
	_root.add_child(p)
	_weapon_box = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_END
	p.add_child(v)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(top)
	_reload_l = UiTheme.label("RELOADING", 14, UiTheme.ACCENT, 700, 3)
	_reload_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_reload_l)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_wname = UiTheme.label("", 17, UiTheme.TEXT, 600, 3)
	_wname.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_wname)
	var ar := HBoxContainer.new()
	ar.alignment = BoxContainer.ALIGNMENT_END
	ar.add_theme_constant_override("separation", 6)
	v.add_child(ar)
	_ammo = UiTheme.label("30", 46, Color.WHITE, 800, 4)
	ar.add_child(_ammo)
	_reserve = UiTheme.label("/ 90", 22, UiTheme.TEXT_DIM, 600, 3)
	_reserve.size_flags_vertical = Control.SIZE_SHRINK_END
	ar.add_child(_reserve)
	_equip = HBoxContainer.new()
	_equip.alignment = BoxContainer.ALIGNMENT_END
	_equip.add_theme_constant_override("separation", 4)
	v.add_child(_equip)


func _build_center() -> void:
	_ann = VBoxContainer.new()
	_anchor(_ann, 0, 0, 1, 0, 0, 150, 0, 260)
	_ann.alignment = BoxContainer.ALIGNMENT_CENTER
	_ann.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ann.add_theme_constant_override("separation", 2)
	_root.add_child(_ann)
	_ann_title = UiTheme.label("", 44, Color.WHITE, 800, 6)
	_ann_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ann.add_child(_ann_title)
	_ann_sub = UiTheme.label("", 20, UiTheme.TEXT, 500, 4)
	_ann_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ann.add_child(_ann_sub)
	_ann.modulate.a = 0.0

	_hint = UiTheme.label("", 18, Color(1, 1, 1, 0.92), 500, 4)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_hint, 0, 1, 1, 1, 0, -250, 0, -222)
	_root.add_child(_hint)

	_progress = _panel(Color(0.03, 0.035, 0.04, 0.72), 12.0)
	_anchor(_progress, 0.5, 1, 0.5, 1, -200, -210, 200, -150)
	_root.add_child(_progress)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	_progress.add_child(pv)
	_progress_l = UiTheme.label("", 16, UiTheme.ACCENT, 700, 0)
	_progress_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(_progress_l)
	var pb := _bar(376, 10, UiTheme.ACCENT)
	pv.add_child(pb[0])
	_progress_fill = pb[1]
	_progress.visible = false

	_spectator = _panel(Color(0.03, 0.035, 0.04, 0.72), 16.0)
	_anchor(_spectator, 0.5, 1, 0.5, 1, -260, -150, 260, -40)
	_root.add_child(_spectator)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_theme_constant_override("separation", 2)
	_spectator.add_child(sv)
	_spec_title = UiTheme.label("SPECTATING", 13, UiTheme.TEXT_DIM, 700, 0)
	_spec_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_spec_title)
	_spec_name = UiTheme.label("", 26, Color.WHITE, 700, 0)
	_spec_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_spec_name)
	_spec_hint = UiTheme.label("", 14, UiTheme.TEXT_DIM, 400, 0)
	_spec_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_spec_hint)
	_spectator.visible = false


# --- Game binding -------------------------------------------------------------
func _bind_game() -> void:
	if _bound:
		return
	var g: Game = Game.inst
	if g == null and get_parent() is Game:
		g = get_parent() as Game
	if g == null:
		return
	_game = g
	_bound = true
	g.kill_event.connect(_on_kill)
	g.round_event.connect(_on_round_event)
	g.chat_message.connect(_on_chat)
	g.local_damaged.connect(_on_damaged)
	g.hit_confirmed.connect(_on_hit)


func _on_kill(killer_id: String, victim_id: String, weapon_id: String, headshot: bool, wallbang: bool) -> void:
	var k: Soldier = _game.get_soldier(killer_id)
	var v: Soldier = _game.get_soldier(victim_id)
	var me: Soldier = _game.local_soldier
	var kn := k.display_name if k != null else ""
	var kt := k.team if k != null else -1
	var vn := v.display_name if v != null else victim_id
	var vt := v.team if v != null else -1
	var mine := me != null and (k == me or v == me)
	_killfeed.add_kill(kn, kt, vn, vt, weapon_id, headshot, wallbang, mine)


func _on_chat(from_name: String, team: int, text: String, team_only: bool) -> void:
	_chat.add_message(from_name, team, text, team_only)
	if from_name != "":
		Sfx.play("click", -10.0, 0.8)
	else:
		Sfx.play("radio", -8.0)


func _on_damaged(amount: float, from_dir: Vector3) -> void:
	var yaw := 0.0
	var s: Soldier = _game.local_soldier
	if s != null:
		yaw = s.yaw
	var ang := NAN
	var flat := Vector3(from_dir.x, 0, from_dir.z)
	if flat.length() > 0.01:
		var f := Vector3(-sin(yaw), 0, -cos(yaw))
		var r := Vector3(cos(yaw), 0, -sin(yaw))
		ang = atan2(flat.dot(r), flat.dot(f))
	_overlay.add_damage(ang, amount)
	_dmg_flash = clampf(amount / 50.0, 0.25, 0.7)


func _on_hit(headshot: bool, killed: bool) -> void:
	_overlay.add_hit(headshot, killed)
	Sfx.play("hitmark", -4.0 if killed else -8.0, 0.8 if killed else 1.0)


func _my_team() -> int:
	if _game == null:
		return -1
	if _game.local_soldier != null:
		return _game.local_soldier.team
	return _game.local_team


func _on_round_event(kind: String, data: Dictionary) -> void:
	var mode := String(_game.config.get("mode", Cfg.MODE_DEFUSAL))
	match kind:
		"round_start":
			Sfx.play("round_start")
			match mode:
				"defusal":
					_announce("ROUND %d" % int(_game.rs.get("round", 1)), "Press B to buy  ·  plant or prevent the demo charge", Color.WHITE)
				"tdm":
					_announce("FIGHT", "First team to %d kills wins" % int(_game.rs.get("kill_limit", 0)), Color.WHITE)
				_:
					_announce("CLEAR THE AREA", "%d hostiles reported" % int(_game.rs.get("hostiles_left", 0)), Color.WHITE)
		"round_end":
			var w := int(data.get("winner", -1))
			var reason := String(data.get("reason", ""))
			reason = String(REASONS.get(reason, reason))
			var title := "ROUND DRAW"
			if w >= 0:
				if mode == Cfg.MODE_HUNT:
					title = "MISSION COMPLETE" if w == 0 else "MISSION FAILED"
				else:
					title = "%s WIN" % UiTheme.team_name(w)
			_announce(title, reason, UiTheme.team_color(w) if w >= 0 else Color.WHITE, 4.5)
			var mt := _my_team()
			if mt >= 0 and w >= 0:
				Sfx.play("win" if w == mt else "lose")
		"bomb_planted":
			var site := String(data.get("site", ""))
			_announce("CHARGE PLANTED", ("Site %s  ·  " % site if site != "" else "") + "%d seconds to detonation" % int(Cfg.BOMB_TIME), Color(1, 0.35, 0.25))
		"bomb_defused":
			_announce("CHARGE DEFUSED", "", UiTheme.team_color(Cfg.DEF))
		"halftime":
			_announce("HALFTIME", "Switching sides  ·  money reset", UiTheme.ACCENT, 5.0)
		"match_over":
			var w2 := int(data.get("winner", -1))
			var sc: Array = _game.rs.get("score", [0, 0])
			var t2 := "MATCH DRAW"
			if w2 >= 0:
				t2 = ("MISSION COMPLETE" if w2 == 0 else "MISSION FAILED") if mode == Cfg.MODE_HUNT else "%s WIN THE MATCH" % UiTheme.team_name(w2)
			var sub := "" if mode == Cfg.MODE_HUNT else "%d  :  %d" % [int(sc[0]) if sc.size() > 0 else 0, int(sc[1]) if sc.size() > 1 else 0]
			_announce(t2, sub, UiTheme.team_color(w2) if w2 >= 0 else Color.WHITE, 8.0)
			_score.visible = true
			_score.refresh()


func _announce(title: String, sub: String, col: Color, hold := 3.0) -> void:
	_ann_title.text = title
	UiTheme.set_label_color(_ann_title, col)
	_ann_sub.text = sub
	if _ann_tween:
		_ann_tween.kill()
	_ann.modulate.a = 0.0
	_ann.scale = Vector2.ONE
	_ann_tween = create_tween()
	_ann_tween.tween_property(_ann, "modulate:a", 1.0, 0.2)
	_ann_tween.tween_interval(hold)
	_ann_tween.tween_property(_ann, "modulate:a", 0.0, 0.6)


# --- Input ----------------------------------------------------------------------
func _close_all() -> void:
	_buy.visible = false
	_team.visible = false
	_pause.visible = false
	_chat.close()


func _unhandled_input(ev: InputEvent) -> void:
	if _game == null:
		return
	if _chat.is_open:
		return
	if ev.is_action_pressed("pause"):
		if _buy.visible:
			_buy.visible = false
		elif _team.visible:
			_team.visible = false
			_team_dismissed = true
		elif _pause.visible:
			if _pause.back():
				_pause.visible = false
		else:
			_close_all()
			_pause.open()
			Sfx.play("click")
		get_viewport().set_input_as_handled()
		return
	if _pause.visible:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var kc := (ev as InputEventKey).physical_keycode
		if _buy.visible and _buy.handle_key(kc):
			get_viewport().set_input_as_handled()
			return
		if _team.visible and _team.handle_key(kc):
			get_viewport().set_input_as_handled()
			return
	if ev.is_action_pressed("buy"):
		if _buy.visible:
			_buy.visible = false
		else:
			var s: Soldier = _game.local_soldier
			if s != null and s.alive and s.team >= 0:
				_team.visible = false
				_buy.reset_keys()
				_buy.select_category(0)
				_buy.visible = true
				Sfx.play("click")
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("team_menu"):
		_buy.visible = false
		_team.visible = not _team.visible
		if _team.visible:
			_team.rebuild()
			_no_focus(_team)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("chat") or ev.is_action_pressed("team_chat"):
		_buy.visible = false
		_team.visible = false
		_chat.open(ev.is_action_pressed("team_chat"))
		get_viewport().set_input_as_handled()


# --- Per-frame update ------------------------------------------------------------
func _process(delta: float) -> void:
	if not _bound:
		_bind_game()
	if _game == null or not is_instance_valid(_game):
		_root.visible = false
		return
	_root.visible = true
	_blink += delta
	var g := _game
	var s: Soldier = g.local_soldier
	var alive := s != null and s.alive
	var now := g.now()

	# Auto team select for fresh joins
	if g.local_team == Cfg.SPEC and s == null and not _team_dismissed and not _team.visible and not _pause.visible:
		_team.rebuild()
		_no_focus(_team)
		_team.visible = true
	if _buy.visible and not alive:
		_buy.visible = false

	_score.visible = Input.is_action_pressed("scoreboard") or String(g.rs.get("phase", "")) == "over"
	_ann.visible = not (_buy.visible or _team.visible or _pause.visible or _score.visible)
	_update_top(g)
	_update_money(s)
	_update_vitals(s, alive)
	_update_weapon(s, alive)
	_update_crosshair(s, alive)
	_update_overlays(g, s, alive, now, delta)
	_update_hints(g, s, alive)
	_update_spectator(g, s, alive)

	_fps.visible = bool(Cfg.settings.get("show_fps", false))
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()

	if DisplayServer.get_name() != "headless":
		var want := Input.MOUSE_MODE_VISIBLE if is_menu_open() else Input.MOUSE_MODE_CAPTURED
		if Input.mouse_mode != want:
			Input.mouse_mode = want


func _update_top(g: Game) -> void:
	var mode := String(g.config.get("mode", Cfg.MODE_DEFUSAL))
	var score: Array = g.rs.get("score", [0, 0])
	for t in 2:
		_team_l[t].text = UiTheme.team_name(t)
		UiTheme.set_label_color(_team_l[t], UiTheme.team_color(t))
		_score_l[t].text = str(int(score[t])) if t < score.size() else "0"
		_score_l[t].visible = mode != Cfg.MODE_HUNT
		var total := 0
		var alive := 0
		for so in g.soldiers.values():
			var sol: Soldier = so
			if sol.team == t:
				total += 1
				if sol.alive:
					alive += 1
		var sig := "%d/%d" % [alive, total]
		if sig != _pip_sig[t]:
			_pip_sig[t] = sig
			_rebuild_pips(_pips[t], t, alive, total)
	var phase := String(g.rs.get("phase", "live"))
	var bomb: Dictionary = g.rs.get("bomb", {})
	var planted := String(bomb.get("state", "")) == "planted"
	var tl := float(g.rs.get("time_left", 0.0))
	_timer.visible = not planted
	_bomb_icon.visible = planted
	if planted:
		var bt := float(bomb.get("time_left", 10.0))
		var period := clampf(bt / 20.0, 0.12, 1.0)
		_bomb_icon.set_color(Color(1, 0.2, 0.12) if fmod(_blink, period) < period * 0.5 else Color(0.55, 0.12, 0.08))
	else:
		_timer.text = UiTheme.fmt_time(tl)
		var urgent := tl <= 10.0 and phase == "live"
		UiTheme.set_label_color(_timer, Color(1, 0.3, 0.25) if urgent and fmod(_blink, 0.5) < 0.25 else (Color(1, 0.35, 0.3) if urgent else Color.WHITE))
	match phase:
		"warmup":
			_phase.text = "WARMUP"
		"freeze":
			_phase.text = "BUY TIME" if mode == Cfg.MODE_DEFUSAL else "GET READY"
		"post":
			_phase.text = "ROUND OVER"
		"over":
			_phase.text = "MATCH OVER"
		_:
			_phase.text = "CHARGE PLANTED" if planted else ""
	UiTheme.set_label_color(_phase, Color(1, 0.35, 0.25) if planted else UiTheme.ACCENT)
	match mode:
		"defusal":
			_info.text = "ROUND %d / %d" % [int(g.rs.get("round", 1)), int(g.rs.get("max_rounds", 16))]
		"tdm":
			_info.text = "FIRST TO %d" % int(g.rs.get("kill_limit", 0))
		_:
			_info.text = "HOSTILES  %d" % int(g.rs.get("hostiles_left", 0))


func _rebuild_pips(box: HBoxContainer, team: int, alive: int, total: int) -> void:
	for c in box.get_children():
		c.queue_free()
	var col := UiTheme.team_color(team)
	if total > 8:
		box.add_child(UiTheme.label("%d / %d ALIVE" % [alive, total], 14, col, 700, 3))
		return
	var order := range(total)
	if team == 0:
		order.reverse()
	for i in order:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(14, 6)
		r.color = col if i < alive else Color(1, 1, 1, 0.15)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(r)


func _update_money(s: Soldier) -> void:
	var show_money := s != null and String(_game.config.get("mode", "")) == Cfg.MODE_DEFUSAL
	_money.visible = show_money
	if not show_money:
		_last_money = -1
		return
	_money.text = UiTheme.fmt_money(s.money)
	if s != _last_money_owner:
		_last_money_owner = s
		_last_money = s.money
	if s.money != _last_money and _last_money >= 0:
		var d := s.money - _last_money
		_money_delta.text = ("+" if d > 0 else "") + UiTheme.fmt_money(d)
		UiTheme.set_label_color(_money_delta, UiTheme.MONEY if d > 0 else UiTheme.BAD)
		_money_delta.modulate.a = 1.0
		var tw := create_tween()
		tw.tween_interval(1.4)
		tw.tween_property(_money_delta, "modulate:a", 0.0, 0.6)
	_last_money = s.money


func _update_vitals(s: Soldier, alive: bool) -> void:
	_vitals.visible = alive
	if not alive:
		return
	_hp.text = str(s.health)
	var hc := Color.WHITE
	if s.health <= 25:
		hc = Color(1, 0.3, 0.25)
	elif s.health <= 50:
		hc = Color(1, 0.7, 0.3)
	UiTheme.set_label_color(_hp, hc)
	_hp_icon.set_color(hc)
	_hp_fill.anchor_right = clampf(s.health / 100.0, 0.0, 1.0)
	_hp_fill.color = hc
	_ar.text = str(s.armor)
	_ar_fill.anchor_right = clampf(s.armor / 100.0, 0.0, 1.0)
	_helmet.visible = s.helmet and s.armor > 0
	_ar.modulate.a = 1.0 if s.armor > 0 else 0.5


func _update_weapon(s: Soldier, alive: bool) -> void:
	_weapon_box.visible = alive
	if not alive:
		return
	var id := s.cur
	var d := Cfg.w(id)
	var cls := String(d.get("cls", ""))
	_wname.text = Cfg.item_name(id).to_upper()
	_reload_l.visible = (s.flags & Soldier.F_RELOAD) != 0 and fmod(_blink, 0.6) < 0.4
	match cls:
		"knife":
			_ammo.text = "—"
			_reserve.text = ""
		"grenade":
			_ammo.text = str(int(s.grenades.get(id, 0)))
			_reserve.text = ""
		"bomb":
			_ammo.text = "1"
			_reserve.text = "CHARGE"
		"breach":
			_ammo.text = str(s.breach_charges)
			_reserve.text = ""
		_:
			if s.ammo.has(id):
				var a: Array = s.ammo[id]
				var mag := int(a[0]) if a.size() > 0 else 0
				var res := int(a[1]) if a.size() > 1 else 0
				_ammo.text = str(mag)
				_reserve.text = "/ %d" % res
				var maxm := int(d.get("mag", 30))
				UiTheme.set_label_color(_ammo, Color(1, 0.3, 0.25) if mag <= maxi(1, maxm / 4) else Color.WHITE)
			else:
				_ammo.text = "—"
				_reserve.text = ""
	if cls != "" and not (cls in ["pistol", "smg", "shotgun", "rifle", "sniper", "lmg"]):
		UiTheme.set_label_color(_ammo, Color.WHITE)
	# Equipment strip
	var sig := "%s|%d|%d|%d|%s|%s|%d" % [id, int(s.grenades.get("frag", 0)), int(s.grenades.get("flash", 0)), int(s.grenades.get("smoke", 0)), str(s.has_bomb), str(s.has_kit), s.breach_charges]
	if sig != _equip_sig:
		_equip_sig = sig
		for c in _equip.get_children():
			c.queue_free()
		for gt in Cfg.GRENADE_ORDER:
			var n := int(s.grenades.get(gt, 0))
			if n > 0:
				_add_equip(gt, n, id == gt)
		if s.breach_charges > 0:
			_add_equip("breach", s.breach_charges, id == "breach")
		if s.has_bomb:
			_add_equip("bomb", 1, id == "bomb", Color(1, 0.45, 0.3))
		if s.has_kit:
			_add_equip("kit", 1, false, Color(0.55, 0.75, 1.0))


func _add_equip(kind: String, n: int, active: bool, tint := Color(0.85, 0.85, 0.82)) -> void:
	var col := UiTheme.ACCENT if active else tint
	_equip.add_child(HudIcon.new(kind, col, 19.0))
	if n > 1:
		var l := UiTheme.label("×%d" % n, 13, col, 600, 3)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_equip.add_child(l)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(6, 0)
	_equip.add_child(sp)


func _update_crosshair(s: Soldier, alive: bool) -> void:
	if not alive:
		_crosshair.mode = 2
		_crosshair.queue_redraw()
		return
	var d := s.weapon_data()
	var cls := String(d.get("cls", ""))
	var mode := 0
	var in_cover := (s.flags & Soldier.F_COVER) != 0
	if s.scope_level > 0:
		mode = 2
	elif s.ads_amount > 0.3 and not in_cover:
		mode = 2 # aiming down sights: the gun's own sights are the reticle
	elif in_cover and (s.flags & Soldier.F_AIM) == 0:
		mode = 1
	elif cls == "sniper":
		mode = 2 if d.has("scope") and float(d.get("spread", 0.0)) > 5.0 else 0
	var spread := s.current_spread()
	var cam := get_viewport().get_camera_3d()
	var fov := cam.fov if cam != null else 90.0
	var h := _crosshair.size.y if _crosshair.size.y > 0 else 900.0
	var px := tan(deg_to_rad(maxf(spread, 0.0))) / tan(deg_to_rad(fov) * 0.5) * h * 0.5
	var target := clampf(px, 4.0, 140.0)
	_crosshair.gap = lerpf(_crosshair.gap, target, clampf(get_process_delta_time() * 18.0, 0.0, 1.0))
	if _crosshair.mode != mode or absf(_crosshair.gap - target) > 0.05:
		_crosshair.mode = mode
	_crosshair.queue_redraw()


func _update_overlays(g: Game, s: Soldier, alive: bool, now: float, delta: float) -> void:
	# Flashbang
	var fa := 0.0
	if s != null and s.flash_until > now:
		var rem := s.flash_until - now
		fa = clampf(rem / 1.3, 0.0, 1.0) * clampf(s.flash_strength, 0.0, 1.0)
	_flash.color.a = fa
	# Scope
	var scoped := alive and s.scope_level > 0
	_scope.visible = scoped
	if scoped:
		var sz := _scope.size
		_scope_mat.set_shader_parameter("aspect", sz.x / maxf(1.0, sz.y))
	# Hurt vignette
	_dmg_flash = maxf(0.0, _dmg_flash - delta * 1.4)
	var low := 0.0
	if alive and s.health < 30:
		low = 0.18 + (0.45 + 0.15 * sin(_blink * 5.0)) * (1.0 - s.health / 30.0)
	_hurt.modulate.a = clampf(maxf(low, _dmg_flash), 0.0, 0.85)
	# Plant / defuse progress
	var prog := alive and s.action_progress > 0.0
	_progress.visible = prog
	if prog:
		_progress_l.text = s.action_label.to_upper() if s.action_label != "" else "WORKING"
		_progress_fill.anchor_right = clampf(s.action_progress, 0.0, 1.0)


func _update_hints(g: Game, s: Soldier, alive: bool) -> void:
	var hint := ""
	if alive and s.action_progress <= 0.0:
		var phase := String(g.rs.get("phase", ""))
		var bomb: Dictionary = g.rs.get("bomb", {})
		var site := ""
		if g.world != null:
			site = g.world.in_site(s.global_position)
		if (s.flags & Soldier.F_COVER) != 0:
			hint = "RIGHT CLICK aim  ·  LEFT CLICK blind fire  ·  Q leave cover"
		elif s.has_bomb and s.cur == "bomb":
			hint = "Hold LEFT CLICK to plant the charge" if site != "" else "Take the charge to site A or B"
		elif s.has_bomb and site != "":
			hint = "Press 5 to equip the demo charge"
		elif String(bomb.get("state", "")) == "planted" and s.team == Cfg.DEF and not UiTheme.is_hunt():
			var bp: Vector3 = bomb.get("pos", Vector3.ZERO)
			if s.global_position.distance_to(bp) < 2.5:
				hint = "Hold E to defuse" + ("" if s.has_kit else "  (no kit: 10 s)")
		elif phase == "freeze" and String(g.config.get("mode", "")) == Cfg.MODE_DEFUSAL and g.in_buy_zone(s) and not _buy.visible:
			hint = "Press B to buy equipment"
	_hint.text = hint


func _update_spectator(g: Game, s: Soldier, alive: bool) -> void:
	var dead_view := not alive
	_spectator.visible = dead_view and not _team.visible
	if not dead_view:
		return
	var tgt := UiTheme.spectate_target(g)
	var mode := String(g.config.get("mode", ""))
	if tgt != null and tgt.alive and tgt != s:
		var t: Soldier = tgt
		_spec_title.text = "SPECTATING"
		_spec_name.text = "%s   %d HP" % [t.display_name, t.health]
		UiTheme.set_label_color(_spec_name, UiTheme.team_color(t.team))
	elif g.local_team == Cfg.SPEC:
		_spec_title.text = "SPECTATOR"
		_spec_name.text = "FREE CAMERA"
		UiTheme.set_label_color(_spec_name, Color.WHITE)
	else:
		_spec_title.text = "YOU ARE DEAD" if s != null else "WAITING"
		_spec_name.text = "RESPAWNING…" if mode == Cfg.MODE_TDM else "WAITING FOR NEXT ROUND"
		UiTheme.set_label_color(_spec_name, Color.WHITE)
	if g.local_team == Cfg.SPEC:
		_spec_hint.text = "Press M to join a team"
	else:
		_spec_hint.text = "Click to switch player  ·  M to change team"
