class_name BuyMenu
extends PanelContainer
## Category/item buy menu. Mouse or number keys (category, then item; 0 = back).

signal close_requested

var _cat := 0
var _money: Label
var _status: Label
var _cat_buttons: Array[Button] = []
var _items_box: VBoxContainer
var _item_buttons: Array = [] # {button, id, reason_label, price_label}
var _detail_title: Label
var _detail_body: VBoxContainer
var _refresh_t := 0.0


func _ready() -> void:
	theme = UiTheme.get_theme()
	add_theme_stylebox_override("panel", UiTheme.box(Color(0.045, 0.05, 0.058, 0.96), UiTheme.BORDER, 3, 1, 20.0))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(980, 600)
	position = -custom_minimum_size * 0.5
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -490
	offset_right = 490
	offset_top = -300
	offset_bottom = 300

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiTheme.label("BUY MENU", 28, UiTheme.ACCENT, 700, 0))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_status = UiTheme.label("", 16, UiTheme.TEXT_DIM, 500, 0)
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_status)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(24, 0)
	head.add_child(sp2)
	_money = UiTheme.label("$0", 28, UiTheme.MONEY, 700, 0)
	head.add_child(_money)
	var line := ColorRect.new()
	line.color = UiTheme.BORDER
	line.custom_minimum_size = Vector2(0, 1)
	v.add_child(line)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	var cats := VBoxContainer.new()
	cats.custom_minimum_size = Vector2(220, 0)
	cats.add_theme_constant_override("separation", 5)
	body.add_child(cats)
	for i in Cfg.BUY_MENU.size():
		var b := Button.new()
		b.text = "%d   %s" % [i + 1, String(Cfg.BUY_MENU[i][0]).to_upper()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(220, 44)
		b.add_theme_font_override("font", UiTheme.font(600))
		var idx := i
		b.pressed.connect(func():
			Sfx.play("click")
			select_category(idx))
		b.mouse_entered.connect(func(): Sfx.play("click", -16.0, 1.5))
		cats.add_child(b)
		_cat_buttons.append(b)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	_items_box = VBoxContainer.new()
	_items_box.add_theme_constant_override("separation", 6)
	mid.add_child(_items_box)

	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.06), 2, 1, 16.0))
	detail.custom_minimum_size = Vector2(300, 0)
	body.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	detail.add_child(dv)
	_detail_title = UiTheme.label("", 20, Color.WHITE, 700, 0)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_detail_title)
	_detail_body = VBoxContainer.new()
	_detail_body.add_theme_constant_override("separation", 6)
	dv.add_child(_detail_body)

	var foot := UiTheme.label("Number keys select  ·  0 back  ·  B or Esc to close  ·  Buy inside your spawn during buy time", 14, UiTheme.TEXT_DIM, 400, 0)
	v.add_child(foot)
	select_category(0)


func select_category(i: int) -> void:
	_cat = clampi(i, 0, Cfg.BUY_MENU.size() - 1)
	for k in _cat_buttons.size():
		_cat_buttons[k].add_theme_color_override("font_color", UiTheme.ACCENT if k == _cat else UiTheme.TEXT)
	for c in _items_box.get_children():
		c.queue_free()
	_item_buttons.clear()
	var ids: Array = Cfg.BUY_MENU[_cat][1]
	var s := _soldier()
	var n := 0
	for id in ids:
		var item_id := String(id)
		var it := Cfg.item_team(item_id)
		if s != null and it >= 0 and it != s.team and not UiTheme.is_hunt():
			continue
		n += 1
		_add_item(n, item_id)
	if _item_buttons.size() > 0:
		_show_detail(String(_item_buttons[0]["id"]))
	refresh()


func _add_item(num: int, id: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 56)
	b.mouse_entered.connect(func():
		_show_detail(id)
		Sfx.play("click", -16.0, 1.5))
	b.pressed.connect(func(): _buy(id))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 14
	h.offset_right = -14
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var numl := UiTheme.label(str(num), 18, UiTheme.ACCENT, 700, 0)
	numl.custom_minimum_size = Vector2(26, 0)
	numl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(numl)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.alignment = BoxContainer.ALIGNMENT_CENTER
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nv)
	var name_l := UiTheme.label(Cfg.item_name(id), 18, UiTheme.TEXT, 600, 0)
	nv.add_child(name_l)
	var reason := UiTheme.label("", 13, UiTheme.BAD, 400, 0)
	nv.add_child(reason)
	var price := UiTheme.label(UiTheme.fmt_money(Cfg.item_price(id)), 18, UiTheme.MONEY, 600, 0)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(price)
	_items_box.add_child(b)
	_item_buttons.append({"button": b, "id": id, "reason": reason, "price": price, "name": name_l})


func _soldier() -> Soldier:
	if Game.inst == null:
		return null
	return Game.inst.local_soldier


func _buy(id: String) -> void:
	var s := _soldier()
	if s == null or Game.inst == null:
		return
	var why := Game.inst.can_buy(s, id)
	if why != "":
		Sfx.play("dry")
		return
	Sfx.play("buy")
	Game.inst.request_buy(id)
	refresh.call_deferred()


func refresh() -> void:
	var s := _soldier()
	var g := Game.inst
	if s == null or g == null:
		return
	_money.text = UiTheme.fmt_money(s.money)
	var bt := float(g.rs.get("buy_time_left", 0.0))
	if not g.in_buy_zone(s):
		_status.text = "Not in buy zone"
		UiTheme.set_label_color(_status, UiTheme.BAD)
	elif bt > 0.0:
		_status.text = "Buy time  %s" % UiTheme.fmt_time(bt)
		UiTheme.set_label_color(_status, UiTheme.TEXT_DIM)
	else:
		_status.text = ""
	for e in _item_buttons:
		var id := String(e["id"])
		var why := g.can_buy(s, id)
		var b: Button = e["button"]
		var r: Label = e["reason"]
		r.text = why
		r.visible = why != ""
		b.modulate = Color(1, 1, 1, 1) if why == "" else Color(1, 1, 1, 0.5)
		UiTheme.set_label_color(e["price"], UiTheme.MONEY if s.money >= Cfg.item_price(id) else UiTheme.BAD)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.2
		refresh()


## Returns true if the key was used.
func handle_key(keycode: int) -> bool:
	if keycode == KEY_0 or keycode == KEY_BACKSPACE:
		if _cat != 0:
			select_category(0)
		return true
	if keycode >= KEY_1 and keycode <= KEY_9:
		var n := keycode - KEY_1
		if _item_buttons.size() > 0 and _items_shown_by_key:
			if n < _item_buttons.size():
				_buy(String(_item_buttons[n]["id"]))
			_items_shown_by_key = false
			return true
		if n < Cfg.BUY_MENU.size():
			Sfx.play("click")
			select_category(n)
			_items_shown_by_key = true
		return true
	return false


var _items_shown_by_key := false


func reset_keys() -> void:
	_items_shown_by_key = false


func _show_detail(id: String) -> void:
	_detail_title.text = Cfg.item_name(id)
	for c in _detail_body.get_children():
		c.queue_free()
	var price := Cfg.item_price(id)
	_detail_body.add_child(_kv("Price", UiTheme.fmt_money(price)))
	if Cfg.WEAPONS.has(id):
		var d: Dictionary = Cfg.WEAPONS[id]
		var cls := String(d.get("cls", ""))
		if d.has("dmg") and cls != "knife":
			var pellets := int(d.get("pellets", 1))
			var dmg_txt := str(int(d["dmg"])) if pellets <= 1 else "%d × %d" % [int(d["dmg"]), pellets]
			var rpm := 60.0 / maxf(0.01, float(d["rof"]))
			_detail_body.add_child(_kv("Damage", dmg_txt))
			_detail_body.add_child(_kv("Fire rate", "%d RPM%s" % [roundi(rpm), "" if bool(d.get("auto", false)) else " (semi)"]))
			_detail_body.add_child(_kv("Magazine", "%d / %d" % [int(d.get("mag", 0)), int(d.get("reserve", 0))]))
			_detail_body.add_child(_kv("Armor pen.", "%d%%" % roundi(float(d.get("armor", 0.5)) * 100.0)))
			_detail_body.add_child(_kv("Kill reward", UiTheme.fmt_money(int(d.get("reward", 300)))))
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 8)
			_detail_body.add_child(gap)
			var acc := 1.0 - clampf((float(d.get("spread", 1.0)) + float(d.get("spread_fire", 0.5)) * 2.0) / 6.0, 0.0, 0.95)
			if d.has("spread_scoped"):
				acc = maxf(acc, 0.9)
			_detail_body.add_child(_bar("Power", clampf(float(d["dmg"]) * pellets / 120.0, 0.05, 1.0)))
			_detail_body.add_child(_bar("Rate", clampf(rpm / 900.0, 0.05, 1.0)))
			_detail_body.add_child(_bar("Accuracy", acc))
			_detail_body.add_child(_bar("Mobility", clampf((float(d.get("speed", 5.0)) - 4.5) / 1.8, 0.05, 1.0)))
			if d.has("scope"):
				_detail_body.add_child(_note("Right click to scope."))
			elif d.has("ads_fov"):
				_detail_body.add_child(_note("Right click to aim down sights."))
		elif cls == "grenade":
			var txt := {"frag": "Explodes after a short fuse. Deadly within a few metres.",
				"flash": "Blinds anyone looking at it. Max 2.",
				"smoke": "Blocks vision for about 16 seconds."}.get(id, "") as String
			_detail_body.add_child(_note(txt))
		elif cls == "breach":
			_detail_body.add_child(_note("Place on a door or barricade, then stand back. Destroys it and stuns anyone behind. Max 2."))
	else:
		var t2 := {"kevlar": "Body armor. Reduces damage to chest, stomach and arms.",
			"helmet": "Body armor plus helmet. Protects against headshots from most weapons.",
			"kit": "Halves defuse time (5 s instead of 10 s)."}.get(id, "") as String
		_detail_body.add_child(_note(t2))


func _kv(k: String, v: String) -> Control:
	var h := HBoxContainer.new()
	var a := UiTheme.label(k, 15, UiTheme.TEXT_DIM, 400, 0)
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	h.add_child(UiTheme.label(v, 15, UiTheme.TEXT, 600, 0))
	return h


func _bar(k: String, f: float) -> Control:
	var h := HBoxContainer.new()
	var a := UiTheme.label(k, 13, UiTheme.TEXT_DIM, 400, 0)
	a.custom_minimum_size = Vector2(90, 0)
	h.add_child(a)
	var bg := ColorRect.new()
	bg.color = Color(1, 1, 1, 0.08)
	bg.custom_minimum_size = Vector2(170, 8)
	bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fg := ColorRect.new()
	fg.color = UiTheme.ACCENT
	fg.anchor_bottom = 1.0
	fg.anchor_right = f
	bg.add_child(fg)
	h.add_child(bg)
	return h


func _note(t: String) -> Control:
	var l := UiTheme.label(t, 14, UiTheme.TEXT_DIM, 400, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(260, 0)
	return l
