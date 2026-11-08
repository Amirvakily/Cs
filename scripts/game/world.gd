class_name World
extends Node3D
## Builds a playable map from a JSON grid: merged PBR geometry, collision, props, doors,
## lights, sky/environment and a baked navigation mesh. Also answers spatial queries.

signal nav_ready

const FLOORS := ".,^ "
const WALLISH := "#XW-|+Dw"
const THICK := "#XW"
const OBSTACLES := "=cCkvoPLBshtgjy"

var data := {}
var map_id := ""
var theme := "desert"
var cols := 0
var rows := 0
var grid := PackedStringArray()
var wall_h := 6.0
var ceil_h := 4.0
var sites := {}
var spawn_points := {0: [], 1: []}
var spawn_zones := {}
var bounds := AABB()
var breakables := {}
var nav_baked := false
var quality := 2
var sun: DirectionalLight3D
var env: WorldEnvironment

var _heights := PackedFloat32Array()
var _indoor := PackedByteArray()
var _st := {} # material kind -> SurfaceTool
var _bodies := {} # phys material -> StaticBody3D
var _nav_faces := PackedVector3Array()
var _nav_region: NavigationRegion3D
var _nav_mesh: NavigationMesh
var _rng := RandomNumberGenerator.new()
var _radar: Image
var _next_breakable := 1
var _shadow_lights := 0
var _mat_wall := "sandstone"
var _mat_wall2 := "plaster_ext"
var _mat_thin := "plaster_int"
var _mat_out := "ground_desert"
var _mat_in := "pavement"
var _mat_pillar := "concrete"
var _mat_counter := "wood"


# ---------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------
func build(p_map_id: String, with_nav: bool, with_visuals := true) -> void:
	map_id = p_map_id
	var f := FileAccess.open("res://maps/%s.json" % map_id, FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	theme = data.get("theme", "desert")
	grid = PackedStringArray(data["grid"])
	rows = grid.size()
	cols = grid[0].length()
	wall_h = float(data.get("wall_h", 6.0))
	ceil_h = float(data.get("ceil_h", 4.0))
	quality = int(Cfg.settings.get("quality", 2))
	_rng.seed = int(data.get("seed", 1))
	bounds = AABB(Vector3.ZERO, Vector3(cols * Cfg.CELL, wall_h + 2.0, rows * Cfg.CELL))
	if theme == "night":
		_mat_wall = "brick_dark"
		_mat_wall2 = "facade"
		_mat_thin = "block_wall"
		_mat_out = "asphalt"
		_mat_in = "lobby"
		_mat_pillar = "facade"
		_mat_counter = "metal_plate"
	_compute_heights()
	_compute_indoor()
	_build_floors()
	_build_cells()
	_build_ceilings()
	_commit_meshes()
	_build_sites_and_spawns()
	if with_visuals:
		_build_neons()
		_build_wall_decor()
		_build_environment()
	_build_radar()
	if with_nav:
		_bake_nav()


func _ch(c: int, r: int) -> String:
	if c < 0 or r < 0 or c >= cols or r >= rows:
		return "#"
	return grid[r][c]


func _idx(c: int, r: int) -> int:
	return r * cols + c


func _compute_heights() -> void:
	_heights.resize(cols * rows)
	_heights.fill(0.0)
	for p in data.get("platforms", []):
		for r in range(int(p[1]), int(p[3]) + 1):
			for c in range(int(p[0]), int(p[2]) + 1):
				_heights[_idx(c, r)] = float(p[4])
	for p in data.get("ramps", []):
		for r in range(int(p[1]), int(p[3]) + 1):
			for c in range(int(p[0]), int(p[2]) + 1):
				_heights[_idx(c, r)] = (float(p[4]) + float(p[5])) * 0.5


func _compute_indoor() -> void:
	_indoor.resize(cols * rows)
	_indoor.fill(0)
	for r in rows:
		for c in cols:
			var ch := _ch(c, r)
			if ch == "," or ch == "^":
				_indoor[_idx(c, r)] = 1
	# Obstacles take the indoor/outdoor state of their surroundings.
	for r in rows:
		for c in cols:
			var ch := _ch(c, r)
			if OBSTACLES.contains(ch):
				var ins := 0
				var outs := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := _ch(c + d.x, r + d.y)
					if n == "," or n == "^":
						ins += 1
					elif n == "." or n == " ":
						outs += 1
				if ins > 0 and ins >= outs:
					_indoor[_idx(c, r)] = 2


func is_indoor(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return false
	return _indoor[_idx(c.x, c.y)] > 0


func _floor_kind(c: int, r: int) -> String:
	for z in data.get("floor_zones", []):
		if c >= int(z[0]) and c <= int(z[2]) and r >= int(z[1]) and r <= int(z[3]):
			return str(z[4])
	return _mat_in if _indoor[_idx(c, r)] > 0 else _mat_out


# --- geometry helpers --------------------------------------------------------
func _surface(kind: String) -> SurfaceTool:
	if not _st.has(kind):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[kind] = st
	return _st[kind]


func _body(phys: String) -> StaticBody3D:
	if not _bodies.has(phys):
		var b := StaticBody3D.new()
		b.name = "Static_" + phys
		b.collision_layer = Cfg.L_WORLD
		b.collision_mask = 0
		b.set_meta("mat", phys)
		add_child(b)
		_bodies[phys] = b
	return _bodies[phys]


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(d)


## Adds a box (visual + collision + nav). `xf` places the box centre; `size` is its full extent.
func add_box(xf: Transform3D, size: Vector3, kind: String, phys := "", collide := true, nav := true, visual := true) -> void:
	var h := size * 0.5
	var corners := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var p := []
	for v in corners:
		p.append(xf * v)
	var faces := [
		[4, 5, 6, 7, Vector3(0, 0, 1)], [1, 0, 3, 2, Vector3(0, 0, -1)], [5, 1, 2, 6, Vector3(1, 0, 0)],
		[0, 4, 7, 3, Vector3(-1, 0, 0)], [7, 6, 2, 3, Vector3(0, 1, 0)], [0, 1, 5, 4, Vector3(0, -1, 0)],
	]
	if visual and kind != "":
		var st := _surface(kind)
		for fc in faces:
			var n: Vector3 = xf.basis * (fc[4] as Vector3)
			if n.y < -0.9 and xf.origin.y - h.y <= 0.01:
				continue # bottom faces on the ground are never seen
			# Counter-clockwise when viewed from outside (Godot front faces are clockwise -> reverse).
			_quad(st, p[fc[0]], p[fc[3]], p[fc[2]], p[fc[1]], n.normalized())
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = xf
		_body(phys if phys != "" else Mats.phys(kind)).add_child(cs)
	if nav:
		for fc in faces:
			_nav_faces.append_array([p[fc[0]], p[fc[1]], p[fc[2]], p[fc[0]], p[fc[2]], p[fc[3]]])


func add_aabox(pos_min: Vector3, pos_max: Vector3, kind: String, phys := "", collide := true, nav := true) -> void:
	var size := pos_max - pos_min
	add_box(Transform3D(Basis.IDENTITY, (pos_min + pos_max) * 0.5), size, kind, phys, collide, nav)


func _cell_min(c: int, r: int) -> Vector3:
	return Vector3(c * Cfg.CELL, 0, r * Cfg.CELL)


## Greedy rectangle merge over cells for which `pred(c, r)` is true. Returns Array[Rect2i].
func _merge_rects(pred: Callable) -> Array:
	var used := PackedByteArray()
	used.resize(cols * rows)
	var out := []
	for r in rows:
		for c in cols:
			if used[_idx(c, r)] or not pred.call(c, r):
				continue
			var w := 1
			while c + w < cols and not used[_idx(c + w, r)] and pred.call(c + w, r):
				w += 1
			var h := 1
			var ok := true
			while ok and r + h < rows:
				for k in w:
					if used[_idx(c + k, r + h)] or not pred.call(c + k, r + h):
						ok = false
						break
				if ok:
					h += 1
			for rr in range(r, r + h):
				for cc in range(c, c + w):
					used[_idx(cc, rr)] = 1
			out.append(Rect2i(c, r, w, h))
	return out


func _rect_box(rc: Rect2i, y0: float, y1: float, kind: String, inset := 0.0, phys := "") -> void:
	var mn := Vector3(rc.position.x * Cfg.CELL + inset, y0, rc.position.y * Cfg.CELL + inset)
	var mx := Vector3((rc.position.x + rc.size.x) * Cfg.CELL - inset, y1, (rc.position.y + rc.size.y) * Cfg.CELL - inset)
	# Negative inset = decorative overhang (trim): visual only.
	add_aabox(mn, mx, kind, phys, inset >= 0.0, inset >= 0.0)


# --- floors / platforms / ramps -------------------------------------------------
func _build_floors() -> void:
	var kinds := {}
	for r in rows:
		for c in cols:
			kinds[_floor_kind(c, r)] = true
	for k in kinds.keys():
		var rects := _merge_rects(func(c, r): return _floor_kind(c, r) == k)
		for rc in rects:
			_rect_box(rc, -1.0, 0.0, k)
	var plat_kind := "concrete" if theme == "night" else "sandstone"
	for p in data.get("platforms", []):
		var rc := Rect2i(int(p[0]), int(p[1]), int(p[2]) - int(p[0]) + 1, int(p[3]) - int(p[1]) + 1)
		_rect_box(rc, 0.0, float(p[4]), plat_kind)
		# Railing posts along the open platform edges for readability.
	for p in data.get("ramps", []):
		_build_ramp(p, plat_kind)


func _build_ramp(p: Array, kind: String) -> void:
	var c0 := int(p[0])
	var r0 := int(p[1])
	var c1 := int(p[2])
	var r1 := int(p[3])
	var h0 := float(p[4])
	var h1 := float(p[5])
	var dir := str(p[6])
	var d := Vector3.ZERO
	var start := Vector3.ZERO
	var length := 0.0
	var width := 0.0
	var cx := (c0 + c1 + 1) * 0.5 * Cfg.CELL
	var cz := (r0 + r1 + 1) * 0.5 * Cfg.CELL
	match dir:
		"N":
			d = Vector3(0, 0, -1)
			start = Vector3(cx, 0, (r1 + 1) * Cfg.CELL)
			length = (r1 - r0 + 1) * Cfg.CELL
			width = (c1 - c0 + 1) * Cfg.CELL
		"S":
			d = Vector3(0, 0, 1)
			start = Vector3(cx, 0, r0 * Cfg.CELL)
			length = (r1 - r0 + 1) * Cfg.CELL
			width = (c1 - c0 + 1) * Cfg.CELL
		"E":
			d = Vector3(1, 0, 0)
			start = Vector3(c0 * Cfg.CELL, 0, cz)
			length = (c1 - c0 + 1) * Cfg.CELL
			width = (r1 - r0 + 1) * Cfg.CELL
		_:
			d = Vector3(-1, 0, 0)
			start = Vector3((c1 + 1) * Cfg.CELL, 0, cz)
			length = (c1 - c0 + 1) * Cfg.CELL
			width = (r1 - r0 + 1) * Cfg.CELL
	var xa := Vector3.UP.cross(d)
	var basis := Basis(xa, Vector3.UP, d)
	var xf := Transform3D(basis, start)
	var w := width * 0.5
	# local: x across, z along (0 = low end), y up
	var lb0 := xf * Vector3(-w, 0, 0)
	var lb1 := xf * Vector3(w, 0, 0)
	var hb0 := xf * Vector3(-w, 0, length)
	var hb1 := xf * Vector3(w, 0, length)
	var lt0 := xf * Vector3(-w, h0, 0)
	var lt1 := xf * Vector3(w, h0, 0)
	var ht0 := xf * Vector3(-w, h1, length)
	var ht1 := xf * Vector3(w, h1, length)
	var st := _surface(kind)
	var top_n := (ht0 - lt0).cross(lt1 - lt0).normalized()
	if top_n.y < 0:
		top_n = -top_n
	_tri_quad(st, lt0, lt1, ht1, ht0, top_n)
	_tri_quad(st, lb0, lt0, ht0, hb0, -xa)
	_tri_quad(st, lb1, hb1, ht1, lt1, xa)
	_tri_quad(st, hb0, ht0, ht1, hb1, d)
	if h0 > 0.01:
		_tri_quad(st, lb0, lb1, lt1, lt0, -d)
	var pts := PackedVector3Array([lb0, lb1, hb0, hb1, lt0, lt1, ht0, ht1])
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	cs.shape = shape
	_body("concrete").add_child(cs)
	_nav_faces.append_array([lt0, ht0, ht1, lt0, ht1, lt1])


## Adds a quad choosing winding so the face points along `n`.
func _tri_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var fn := (b - a).cross(c - a)
	if fn.dot(n) > 0.0:
		_quad(st, a, d, c, b, n)
	else:
		_quad(st, a, b, c, d, n)


# --- cells ------------------------------------------------------------------------
func _wallish(c: int, r: int) -> bool:
	return WALLISH.contains(_ch(c, r))


func _build_cells() -> void:
	# Thick walls (merged), windows.
	for ch in ["#", "X"]:
		var kind := _mat_wall if ch == "#" else _mat_wall2
		for rc in _merge_rects(func(c, r): return _ch(c, r) == ch):
			var border: bool = rc.position.x == 0 or rc.position.y == 0 or rc.end.x >= cols or rc.end.y >= rows
			var top: float = wall_h + (0.0 if border else float(_rng.randi() % 3) * 1.0)
			_rect_box(rc, 0.0, top, kind)
			_rect_box(rc, 0.0, 0.45, "trim", -0.06)
			_rect_box(rc, top, top + 0.22, "trim", -0.12)
	for rc in _merge_rects(func(c, r): return _ch(c, r) == "W"):
		_rect_box(rc, 0.0, 1.0, _mat_wall)
		_rect_box(rc, 2.2, wall_h, _mat_wall)
	for rc in _merge_rects(func(c, r): return _ch(c, r) == "k"):
		var y0 := _heights[_idx(rc.position.x, rc.position.y)]
		_rect_box(rc, y0, y0 + 2.6, "container", 0.04)
	for rc in _merge_rects(func(c, r): return _ch(c, r) == "B"):
		_rect_box(rc, 0.0, 1.1, _mat_counter, 0.2)
	var car_used := {}
	for r in rows:
		for c in cols:
			var ch := _ch(c, r)
			var cell := Vector2i(c, r)
			var base := _cell_min(c, r)
			var centre := base + Vector3(Cfg.CELL * 0.5, _heights[_idx(c, r)], Cfg.CELL * 0.5)
			match ch:
				"-", "|", "+":
					_thin_wall(c, r, ch)
				"D", "w":
					_doorway(c, r, ch)
				"=":
					_barrier(c, r, centre)
				"c":
					_crate(centre, false)
				"C":
					_crate(centre, true)
				"o":
					_barrels(centre)
				"P":
					var ph := ceil_h if is_indoor(cell) else wall_h
					add_aabox(centre + Vector3(-0.45, 0, -0.45), centre + Vector3(0.45, ph, 0.45), _mat_pillar)
				"L":
					_street_lamp(centre)
				"v":
					if not car_used.has(cell):
						_car(c, r, car_used)
				"s":
					_slots(centre, r)
				"h":
					_decor("fire_hydrant", centre, Vector3(0.45, 0.85, 0.45), "metal")
				"t":
					_decor("metal_trash_can", centre, Vector3(0.75, 1.05, 0.75), "metal")
				"g":
					_decor("portable_generator", centre, Vector3(1.3, 0.95, 0.9), "metal")
				"j":
					_decor("ammo_box", centre + Vector3(-0.35, 0, 0.2), Vector3(0.7, 0.45, 0.4), "metal")
					_decor("metal_jerrycan", centre + Vector3(0.4, 0, -0.2), Vector3(0.4, 0.5, 0.25), "metal")
					_decor("propane_tank", centre + Vector3(0.2, 0, 0.55), Vector3(0.35, 0.7, 0.35), "metal")
				"y":
					for i in 3:
						_decor("old_tyre", centre + Vector3(0, i * 0.24, 0), Vector3(0.75, 0.25, 0.75), "dirt", i == 0)
				"^":
					_ceiling_lamp(centre)


func _thin_wall(c: int, r: int, ch: String) -> void:
	var t := 0.3
	var base := _cell_min(c, r)
	var cx := base.x + Cfg.CELL * 0.5
	var cz := base.z + Cfg.CELL * 0.5
	var h := wall_h
	add_aabox(Vector3(cx - t * 0.5, 0, cz - t * 0.5), Vector3(cx + t * 0.5, h, cz + t * 0.5), _mat_thin)
	var arms := []
	if ch == "-" or ch == "+":
		if ch == "-" or _wallish(c - 1, r):
			arms.append(Vector2i(-1, 0))
		if ch == "-" or _wallish(c + 1, r):
			arms.append(Vector2i(1, 0))
	if ch == "|" or ch == "+":
		if ch == "|" or _wallish(c, r - 1):
			arms.append(Vector2i(0, -1))
		if ch == "|" or _wallish(c, r + 1):
			arms.append(Vector2i(0, 1))
	for a in arms:
		if a.x != 0:
			var x0 := cx + t * 0.5 if a.x > 0 else base.x
			var x1 := base.x + Cfg.CELL if a.x > 0 else cx - t * 0.5
			add_aabox(Vector3(x0, 0, cz - t * 0.5), Vector3(x1, h, cz + t * 0.5), _mat_thin)
		else:
			var z0 := cz + t * 0.5 if a.y > 0 else base.z
			var z1 := base.z + Cfg.CELL if a.y > 0 else cz - t * 0.5
			add_aabox(Vector3(cx - t * 0.5, 0, z0), Vector3(cx + t * 0.5, h, z1), _mat_thin)


func _doorway(c: int, r: int, ch: String) -> void:
	var span_x := false
	var lw := _wallish(c - 1, r)
	var rw := _wallish(c + 1, r)
	var uw := _wallish(c, r - 1)
	var dw := _wallish(c, r + 1)
	if lw and rw:
		span_x = true
	elif uw and dw:
		span_x = false
	else:
		span_x = lw or rw
	var thick := false
	if span_x:
		thick = THICK.contains(_ch(c - 1, r)) or THICK.contains(_ch(c + 1, r))
	else:
		thick = THICK.contains(_ch(c, r - 1)) or THICK.contains(_ch(c, r + 1))
	var t := Cfg.CELL if thick else 0.3
	var kind := _mat_wall if thick else _mat_thin
	var base := _cell_min(c, r)
	var cx := base.x + Cfg.CELL * 0.5
	var cz := base.z + Cfg.CELL * 0.5
	var door_h := 2.4
	var jamb := 0.15
	if span_x:
		add_aabox(Vector3(base.x, door_h, cz - t * 0.5), Vector3(base.x + Cfg.CELL, wall_h, cz + t * 0.5), kind)
		add_aabox(Vector3(base.x, 0, cz - t * 0.5), Vector3(base.x + jamb, door_h, cz + t * 0.5), kind)
		add_aabox(Vector3(base.x + Cfg.CELL - jamb, 0, cz - t * 0.5), Vector3(base.x + Cfg.CELL, door_h, cz + t * 0.5), kind)
	else:
		add_aabox(Vector3(cx - t * 0.5, door_h, base.z), Vector3(cx + t * 0.5, wall_h, base.z + Cfg.CELL), kind)
		add_aabox(Vector3(cx - t * 0.5, 0, base.z), Vector3(cx + t * 0.5, door_h, base.z + jamb), kind)
		add_aabox(Vector3(cx - t * 0.5, 0, base.z + Cfg.CELL - jamb), Vector3(cx + t * 0.5, door_h, base.z + Cfg.CELL), kind)
	var door := Door.new()
	door.name = "Door%d" % _next_breakable
	door.position = Vector3(cx, 0, cz)
	add_child(door)
	door.build(_next_breakable, "door" if ch == "D" else "barricade", Cfg.CELL - jamb * 2.0, door_h - 0.05, span_x)
	breakables[_next_breakable] = door
	_next_breakable += 1
	if ch == "w":
		# Barricades block navigation until destroyed.
		var size := Vector3(Cfg.CELL, door_h, 0.2) if span_x else Vector3(0.2, door_h, Cfg.CELL)
		var p := Vector3(cx, door_h * 0.5, cz)
		door.set_meta("nav_box", [p, size])


func _place(node: Node3D, pos: Vector3, yaw := 0.0) -> void:
	node.position = pos
	node.rotation.y = yaw
	add_child(node)


func _barrier(c: int, r: int, centre: Vector3) -> void:
	var along_x := true
	if _ch(c - 1, r) == "=" or _ch(c + 1, r) == "=":
		along_x = true
	elif _ch(c, r - 1) == "=" or _ch(c, r + 1) == "=":
		along_x = false
	var a := Props.aabb("concrete_road_barrier")
	var model_long_x := a.size.x >= a.size.z
	var m := Props.fit("concrete_road_barrier", Vector3(1.98, 1.0, 0.75), not model_long_x)
	var sz: Vector3 = m.get_meta("size")
	_place(m, centre, 0.0 if along_x else PI * 0.5)
	var box := Vector3(1.98, sz.y, sz.z) if along_x else Vector3(sz.z, sz.y, 1.98)
	add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0, sz.y * 0.5, 0)), box, "", "concrete", true, true, false)


func _crate_box(pos: Vector3, size: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	add_box(Transform3D(b, pos + Vector3(0, h, 0)), Vector3(size, size, size) * 0.96, "crate", "wood")
	# Frame strips along the 12 edges give the crate its silhouette.
	var t := 0.09
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			add_box(Transform3D(b, pos + b * Vector3(sx * (h - t * 0.5), h, sz * (h - t * 0.5))), Vector3(t, size, t), "crate_frame", "wood", false, false)
			add_box(Transform3D(b, pos + b * Vector3(0, h + sx * (h - t * 0.5), sz * (h - t * 0.5))), Vector3(size, t, t), "crate_frame", "wood", false, false)
			add_box(Transform3D(b, pos + b * Vector3(sz * (h - t * 0.5), h + sx * (h - t * 0.5), 0)), Vector3(t, t, size), "crate_frame", "wood", false, false)


func _crate(centre: Vector3, stack: bool) -> void:
	var yaw := (_rng.randi() % 4) * PI * 0.5 + _rng.randf_range(-0.05, 0.05)
	var off := Vector3(_rng.randf_range(-0.15, 0.15), 0, _rng.randf_range(-0.15, 0.15))
	var size := 1.3 if stack else 1.15
	_crate_box(centre + off, size, yaw)
	if stack:
		var y2 := yaw + _rng.randf_range(-0.35, 0.35)
		_crate_box(centre + off + Vector3(_rng.randf_range(-0.1, 0.1), size, _rng.randf_range(-0.1, 0.1)), 1.0, y2)
	elif _rng.randf() < 0.45:
		var deco := "cardboard_box_01" if _rng.randf() < 0.6 else "wooden_crate_02"
		var m := Props.fit(deco, Vector3(0.6, 0.45, 0.6) if deco == "cardboard_box_01" else Vector3(0.5, 0.45, 1.0))
		_place(m, centre + off + Vector3(_rng.randf_range(-0.2, 0.2), size, _rng.randf_range(-0.2, 0.2)), _rng.randf() * TAU)


func _barrels(centre: Vector3) -> void:
	var offs := [Vector3(-0.4, 0, -0.3), Vector3(0.38, 0, -0.25), Vector3(0.0, 0, 0.42)]
	for i in offs.size():
		if i == 2 and _rng.randf() < 0.35:
			continue
		var name := "Barrel_01" if (i + _rng.randi()) % 2 == 0 else "barrel_03"
		var m := Props.fit(name, Vector3(0.62, 0.95, 0.62))
		var sz: Vector3 = m.get_meta("size")
		var p: Vector3 = centre + offs[i]
		_place(m, p, _rng.randf() * TAU)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = sz.x * 0.5
		cyl.height = sz.y
		cs.shape = cyl
		cs.position = p + Vector3(0, sz.y * 0.5, 0)
		_body("metal").add_child(cs)
		add_box(Transform3D(Basis.IDENTITY, p + Vector3(0, sz.y * 0.5, 0)), Vector3(sz.x, sz.y, sz.x), "", "metal", false, true, false)


func _car(c: int, r: int, used: Dictionary) -> void:
	var along_x := _ch(c + 1, r) == "v" and not used.has(Vector2i(c + 1, r))
	var other := Vector2i(c + 1, r) if along_x else Vector2i(c, r + 1)
	used[Vector2i(c, r)] = true
	if _ch(other.x, other.y) == "v":
		used[other] = true
	else:
		other = Vector2i(c, r)
	var a := _cell_min(c, r) + Vector3(Cfg.CELL * 0.5, 0, Cfg.CELL * 0.5)
	var b := _cell_min(other.x, other.y) + Vector3(Cfg.CELL * 0.5, 0, Cfg.CELL * 0.5)
	var centre := (a + b) * 0.5
	centre.y = _heights[_idx(c, r)]
	var ab := Props.aabb("covered_car")
	var model_long_x := ab.size.x >= ab.size.z
	var m := Props.fit("covered_car", Vector3(4.1, 1.7, 1.95), not model_long_x)
	var sz: Vector3 = m.get_meta("size")
	var yaw := (0.0 if along_x else PI * 0.5) + (PI if _rng.randf() < 0.5 else 0.0) + _rng.randf_range(-0.05, 0.05)
	_place(m, centre, yaw)
	add_box(Transform3D(Basis(Vector3.UP, yaw), centre + Vector3(0, sz.y * 0.45, 0)), Vector3(sz.x * 0.96, sz.y * 0.9, sz.z * 0.92), "", "metal", true, true, false)


func _slots(centre: Vector3, r: int) -> void:
	var facing := 0.0 if r % 2 == 0 else PI
	var body_mat := Tex.flat(Color(0.08, 0.08, 0.09), 0.35, 0.6)
	var trim_mat := Tex.flat(Color(0.85, 0.65, 0.25), 0.3, 0.9)
	for i in 2:
		var x := -0.45 + i * 0.9
		var root := Node3D.new()
		_place(root, centre + Basis(Vector3.UP, facing) * Vector3(x, 0, 0), facing)
		var body := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.82, 1.6, 0.7)
		body.mesh = bm
		body.material_override = body_mat
		body.position = Vector3(0, 0.8, 0)
		root.add_child(body)
		var hue := _rng.randf()
		var screen := MeshInstance3D.new()
		var sm := QuadMesh.new()
		sm.size = Vector2(0.62, 0.5)
		screen.mesh = sm
		screen.material_override = Tex.flat(Color.from_hsv(hue, 0.7, 1.0), 0.2, 0.0, 2.5)
		screen.position = Vector3(0, 1.15, 0.352)
		root.add_child(screen)
		var top := MeshInstance3D.new()
		var tm := BoxMesh.new()
		tm.size = Vector3(0.84, 0.18, 0.72)
		top.mesh = tm
		top.material_override = Tex.flat(Color.from_hsv(fmod(hue + 0.5, 1.0), 0.8, 1.0), 0.2, 0.0, 4.0)
		top.position = Vector3(0, 1.69, 0)
		root.add_child(top)
		var ledge := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.84, 0.06, 0.25)
		ledge.mesh = lm
		ledge.material_override = trim_mat
		ledge.position = Vector3(0, 0.82, 0.42)
		root.add_child(ledge)
	add_box(Transform3D(Basis(Vector3.UP, facing), centre + Vector3(0, 0.85, 0)), Vector3(1.8, 1.7, 0.75), "", "metal", true, true, false)
	if quality >= 1 and _rng.randf() < 0.5:
		var l := OmniLight3D.new()
		l.light_color = Color.from_hsv(_rng.randf(), 0.6, 1.0)
		l.light_energy = 0.8
		l.omni_range = 4.0
		l.position = centre + Vector3(0, 2.0, 0)
		add_child(l)


func _decor(name: String, pos: Vector3, fit: Vector3, phys: String, collide := true) -> void:
	var m := Props.fit(name, fit)
	var sz: Vector3 = m.get_meta("size")
	var yaw := _rng.randf() * TAU
	_place(m, pos, yaw)
	if collide:
		add_box(Transform3D(Basis(Vector3.UP, yaw), pos + Vector3(0, sz.y * 0.5, 0)), sz, "", phys, true, true, false)


func _street_lamp(centre: Vector3) -> void:
	var m := Props.fit("street_lamp_01", Vector3(1.6, 5.2, 1.6))
	var a := Props.aabb("street_lamp_01")
	var yaw := _rng.randi() % 4 * PI * 0.5
	_place(m, centre, yaw)
	add_box(Transform3D(Basis.IDENTITY, centre + Vector3(0, 2.6, 0)), Vector3(0.3, 5.2, 0.3), "", "metal", true, true, false)
	var light := SpotLight3D.new()
	var night := theme == "night"
	light.light_color = Color(1.0, 0.68, 0.36) if night else Color(1.0, 0.82, 0.6)
	light.light_energy = 9.0 if night else 3.0
	light.spot_range = 16.0
	light.spot_angle = 62.0
	light.spot_attenuation = 0.9
	light.shadow_enabled = quality >= 2 and _shadow_lights < 12
	if light.shadow_enabled:
		_shadow_lights += 1
	light.position = centre + Vector3(0, 4.9, 0)
	light.rotation.x = -PI * 0.5
	add_child(light)
	var glow := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.16
	gm.height = 0.2
	glow.mesh = gm
	glow.material_override = Tex.flat(light.light_color, 0.5, 0.0, 6.0)
	glow.position = centre + Vector3(0, 4.95, 0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glow)


func _ceiling_lamp(centre: Vector3) -> void:
	var m := Props.fit("hanging_industrial_lamp", Vector3(0.7, 1.0, 0.7))
	var sz: Vector3 = m.get_meta("size")
	_place(m, centre + Vector3(0, ceil_h - sz.y, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.86, 0.68)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.omni_attenuation = 1.2
	l.shadow_enabled = quality >= 2 and _shadow_lights < 18
	if l.shadow_enabled:
		_shadow_lights += 1
	l.position = centre + Vector3(0, ceil_h - sz.y - 0.15, 0)
	add_child(l)


func _build_ceilings() -> void:
	for rc in _merge_rects(func(c, r): return _indoor[_idx(c, r)] > 0):
		_rect_box(rc, ceil_h, ceil_h + 0.3, "ceiling")


func _commit_meshes() -> void:
	for kind in _st.keys():
		var st: SurfaceTool = _st[kind]
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + kind
		mi.mesh = mesh
		mi.material_override = Mats.world(kind)
		add_child(mi)
	_st.clear()


# --- neon signs & decoration ----------------------------------------------------
func _build_neons() -> void:
	for n in data.get("neons", []):
		var c := int(n[0])
		var r := int(n[1])
		var facing := str(n[2])
		var text := str(n[3])
		var col := Color(str(n[4]))
		var hgt := float(n[5])
		var base := _cell_min(c, r) + Vector3(Cfg.CELL * 0.5, 0, Cfg.CELL * 0.5)
		var nrm := Vector3.ZERO
		var yaw := 0.0
		match facing:
			"S":
				nrm = Vector3(0, 0, 1)
				yaw = 0.0
			"N":
				nrm = Vector3(0, 0, -1)
				yaw = PI
			"E":
				nrm = Vector3(1, 0, 0)
				yaw = PI * 0.5
			_:
				nrm = Vector3(-1, 0, 0)
				yaw = -PI * 0.5
		var pos := base + nrm * (Cfg.CELL * 0.5 + 0.12) + Vector3(0, hgt, 0)
		var holder := Node3D.new()
		_place(holder, pos, yaw)
		var label := Label3D.new()
		label.text = text
		label.font_size = 160
		label.pixel_size = 0.006
		label.outline_size = 28
		label.modulate = Color(col.r * 3.0, col.g * 3.0, col.b * 3.0)
		label.outline_modulate = Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, 0.9)
		label.shaded = false
		label.double_sided = false
		label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		holder.add_child(label)
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := text.length() * 0.62 + 0.6
		bm.size = Vector3(w, 1.35, 0.1)
		board.mesh = bm
		board.material_override = Tex.flat(Color(0.03, 0.03, 0.035), 0.5, 0.3)
		board.position = Vector3(0, 0, -0.08)
		holder.add_child(board)
		var frame := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(w + 0.1, 1.45, 0.04)
		frame.mesh = fm
		frame.material_override = Tex.flat(col, 0.4, 0.0, 3.0)
		frame.position = Vector3(0, 0, -0.12)
		holder.add_child(frame)
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 3.0
		light.omni_range = 9.0
		light.position = Vector3(0, 0, 1.2)
		holder.add_child(light)


func _build_wall_decor() -> void:
	# Air-con units and security lights on outward wall faces next to open ground.
	for r in range(1, rows - 1):
		for c in range(1, cols - 1):
			if _ch(c, r) != "#":
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := _ch(c + d.x, r + d.y)
				if n != ".":
					continue
				var roll := _rng.randf()
				var nrm := Vector3(d.x, 0, d.y)
				var face := _cell_min(c, r) + Vector3(Cfg.CELL * 0.5, 0, Cfg.CELL * 0.5) + nrm * Cfg.CELL * 0.5
				var yaw := atan2(nrm.x, nrm.z)
				var face_c := _cell_min(c, r) + Vector3(Cfg.CELL * 0.5, 0, Cfg.CELL * 0.5) + nrm * (Cfg.CELL * 0.5 + 0.03)
				if _rng.randf() < 0.3:
					var lit := theme == "night" and _rng.randf() < 0.45
					var wb := Basis(Vector3.UP, yaw)
					add_box(Transform3D(wb, face_c + Vector3(0, 3.9, 0)), Vector3(1.15, 1.45, 0.08), "trim", "", false, false)
					add_box(Transform3D(wb, face_c + nrm * 0.03 + Vector3(0, 3.9, 0)), Vector3(0.95, 1.25, 0.06), "window_lit" if lit else "window", "", false, false)
				if theme == "night" and _rng.randf() < 0.18:
					add_box(Transform3D(Basis(Vector3.UP, yaw), face_c + Vector3(0, 1.25, 0)), Vector3(1.8, 2.5, 0.07), "shutter", "", false, false)
				if roll < 0.035:
					var ac := Props.fit("exterior_aircon_unit", Vector3(1.0, 0.8, 0.6))
					_place(ac, face + nrm * 0.3 + Vector3(0, 2.6, 0), yaw)
				elif roll < 0.06:
					var ub := Props.fit("utility_box_01", Vector3(0.7, 0.9, 0.35))
					_place(ub, face + nrm * 0.18 + Vector3(0, 1.0, 0), yaw)
				elif roll < 0.075:
					var sl := Props.fit("security_light", Vector3(0.4, 0.4, 0.4))
					_place(sl, face + nrm * 0.2 + Vector3(0, 3.4, 0), yaw)
					var l := SpotLight3D.new()
					l.light_color = Color(0.95, 0.95, 1.0) if theme == "night" else Color(1.0, 0.9, 0.75)
					l.light_energy = 4.0 if theme == "night" else 1.5
					l.spot_range = 10.0
					l.spot_angle = 50.0
					l.position = face + nrm * 0.45 + Vector3(0, 3.3, 0)
					add_child(l)
					l.look_at(l.position + nrm * 0.6 + Vector3(0, -1, 0))


# --- environment ----------------------------------------------------------------
func _build_environment() -> void:
	env = WorldEnvironment.new()
	var e := Environment.new()
	var night := theme == "night"
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = load("res://assets/hdri/%s_2k.hdr" % ("kloppenheim_07_puresky" if night else "wasteland_clouds_puresky"))
	pano.energy_multiplier = 0.55 if night else 0.75
	sky.sky_material = pano
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.55 if night else 0.55
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.25 if night else 0.9
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_normalized = false
	e.glow_intensity = 0.9 if night else 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.06 if night else 0.03
	e.glow_hdr_threshold = 0.9
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		e.set_glow_level(i, [0.0, 0.6, 1.0, 1.0, 0.8, 0.5, 0.2][i])
	e.ssao_enabled = quality >= 1
	e.ssao_radius = 1.4
	e.ssao_intensity = 2.2
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	e.ssil_enabled = quality >= 3
	e.ssr_enabled = quality >= 2 and night
	e.ssr_max_steps = 64
	e.ssr_fade_out = 1.6
	e.sdfgi_enabled = quality >= 2
	e.sdfgi_use_occlusion = true
	e.sdfgi_cascades = 4
	e.sdfgi_min_cell_size = 0.25
	e.sdfgi_energy = 0.9 if night else 1.0
	e.sdfgi_bounce_feedback = 0.4
	e.fog_enabled = true
	e.fog_light_color = Color(0.07, 0.08, 0.12) if night else Color(0.72, 0.58, 0.45)
	e.fog_light_energy = 1.0
	e.fog_density = 0.004 if night else 0.0011
	e.fog_sky_affect = 0.12
	e.fog_aerial_perspective = 0.15
	e.volumetric_fog_enabled = quality >= 2
	e.volumetric_fog_density = 0.018 if night else 0.004
	e.volumetric_fog_albedo = Color(0.65, 0.7, 0.85) if night else Color(0.95, 0.8, 0.62)
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 70.0
	e.volumetric_fog_ambient_inject = 0.15
	e.volumetric_fog_sky_affect = 0.3
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.1 if night else 1.08
	e.adjustment_saturation = 1.12 if night else 0.88
	env.environment = e
	add_child(env)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	# The HDRI's sun sits at azimuth 35.9 deg; rotate the sky so it lights the lanes from the side.
	var az := deg_to_rad(35.9 if night else 115.0)
	if not night:
		e.sky_rotation = Vector3(0, deg_to_rad(115.0 - 35.9), 0)
	var el := deg_to_rad(48.0 if night else 24.0)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	sun.light_color = Color(0.55, 0.65, 0.95) if night else Color(1.0, 0.76, 0.52)
	sun.light_energy = 0.12 if night else 3.2
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP)
	Sfx.play_ambient("amb_city" if night else "amb_wind")


# --- sites, spawns ----------------------------------------------------------------------
func _build_sites_and_spawns() -> void:
	for k in data.get("sites", {}).keys():
		var rc: Array = data["sites"][k]
		sites[k] = AABB(Vector3(rc[0] * Cfg.CELL, -1.0, rc[1] * Cfg.CELL),
			Vector3((rc[2] - rc[0] + 1) * Cfg.CELL, 6.0, (rc[3] - rc[1] + 1) * Cfg.CELL))
	var centre := Vector3(cols * Cfg.CELL * 0.5, 0, rows * Cfg.CELL * 0.5)
	for key in ["atk", "def"]:
		var team := Cfg.ATK if key == "atk" else Cfg.DEF
		var rc: Array = data["spawn"][key]
		spawn_zones[team] = AABB(Vector3(rc[0] * Cfg.CELL, -1.0, rc[1] * Cfg.CELL),
			Vector3((rc[2] - rc[0] + 1) * Cfg.CELL, 6.0, (rc[3] - rc[1] + 1) * Cfg.CELL))
		var pts := []
		for r in range(int(rc[1]), int(rc[3]) + 1):
			for c in range(int(rc[0]), int(rc[2]) + 1):
				if not FLOORS.contains(_ch(c, r)):
					continue
				# Skip cells touching obstacles so soldiers never spawn inside props.
				var clear := true
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n := _ch(c + d.x, r + d.y)
					if OBSTACLES.contains(n):
						clear = false
				if not clear:
					continue
				var p := cell_to_world(Vector2i(c, r))
				var to_c := centre - p
				var yaw := atan2(-to_c.x, -to_c.z)
				pts.append(Transform3D(Basis(Vector3.UP, yaw), p))
		pts.shuffle()
		spawn_points[team] = pts


# --- radar ------------------------------------------------------------------------------
func _build_radar() -> void:
	var px := 4 # pixels per cell (0.5 m per pixel)
	_radar = Image.create(cols * px, rows * px, false, Image.FORMAT_RGBA8)
	_radar.fill(Color(0, 0, 0, 0))
	for r in rows:
		for c in cols:
			var ch := _ch(c, r)
			var col := Color(0.16, 0.17, 0.19, 0.85)
			if THICK.contains(ch) or ch in ["-", "|", "+"]:
				col = Color(0.62, 0.64, 0.66, 0.95)
			elif ch == "D" or ch == "w":
				col = Color(0.55, 0.38, 0.2, 0.95)
			elif OBSTACLES.contains(ch):
				col = Color(0.38, 0.39, 0.41, 0.9)
			elif _heights[_idx(c, r)] > 0.1:
				col = Color(0.24, 0.25, 0.28, 0.9)
			for site in sites.values():
				var p := cell_to_world(Vector2i(c, r))
				if (site as AABB).has_point(Vector3(p.x, 0.5, p.z)) and FLOORS.contains(ch):
					col = Color(0.32, 0.16, 0.14, 0.9)
			_radar.fill_rect(Rect2i(c * px, r * px, px, px), col)


func radar_image() -> Image:
	return _radar


# --- navigation -----------------------------------------------------------------------
func _bake_nav() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "Nav"
	add_child(_nav_region)
	_nav_mesh = NavigationMesh.new()
	_nav_mesh.agent_radius = 0.5
	_nav_mesh.agent_height = 1.75
	_nav_mesh.agent_max_climb = 0.25
	_nav_mesh.agent_max_slope = 40.0
	_nav_mesh.cell_size = 0.25
	_nav_mesh.cell_height = 0.25
	_nav_mesh.region_min_size = 4.0
	_nav_mesh.filter_walkable_low_height_spans = true
	rebake_nav()


func rebake_nav() -> void:
	if _nav_mesh == null:
		return
	var src := NavigationMeshSourceGeometryData3D.new()
	var faces := _nav_faces.duplicate()
	for d in breakables.values():
		if d.kind == "barricade" and not d.broken and d.has_meta("nav_box"):
			var nb: Array = d.get_meta("nav_box")
			var p: Vector3 = nb[0]
			var s: Vector3 = nb[1] * 0.5
			var c := [p + Vector3(-s.x, -s.y, -s.z), p + Vector3(s.x, -s.y, -s.z), p + Vector3(s.x, s.y, -s.z), p + Vector3(-s.x, s.y, -s.z),
				p + Vector3(-s.x, -s.y, s.z), p + Vector3(s.x, -s.y, s.z), p + Vector3(s.x, s.y, s.z), p + Vector3(-s.x, s.y, s.z)]
			for q in [[0, 1, 2, 3], [5, 4, 7, 6], [1, 5, 6, 2], [4, 0, 3, 7], [3, 2, 6, 7]]:
				faces.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	src.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data_async(_nav_mesh, src, _on_nav_baked)


func _on_nav_baked() -> void:
	call_deferred("_apply_nav")


func _apply_nav() -> void:
	if not is_inside_tree():
		return
	_nav_region.navigation_mesh = _nav_mesh
	_nav_region.navigation_mesh = _nav_mesh
	NavigationServer3D.region_set_navigation_mesh(_nav_region.get_rid(), _nav_mesh)
	nav_baked = true
	nav_ready.emit()


func _nav_map() -> RID:
	return get_world_3d().navigation_map


func get_nav_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not nav_baked:
		return PackedVector3Array([from, to])
	return NavigationServer3D.map_get_path(_nav_map(), from, to, true)


func closest_nav_point(p: Vector3) -> Vector3:
	if not nav_baked:
		return p
	return NavigationServer3D.map_get_closest_point(_nav_map(), p)


func random_nav_point(center := Vector3.INF, radius := 0.0) -> Vector3:
	for i in 24:
		var c: Vector2i
		if center == Vector3.INF:
			c = Vector2i(_rng.randi_range(1, cols - 2), _rng.randi_range(1, rows - 2))
		else:
			var off := Vector2(_rng.randf_range(-radius, radius), _rng.randf_range(-radius, radius))
			c = world_to_cell(center + Vector3(off.x, 0, off.y))
		if c.x < 1 or c.y < 1 or c.x >= cols - 1 or c.y >= rows - 1:
			continue
		if FLOORS.contains(_ch(c.x, c.y)):
			return closest_nav_point(cell_to_world(c))
	return closest_nav_point(center if center != Vector3.INF else cell_to_world(Vector2i(cols / 2, rows / 2)))


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------
func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x * Cfg.CELL + Cfg.CELL * 0.5, floor_height(c), c.y * Cfg.CELL + Cfg.CELL * 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / Cfg.CELL), floori(p.z / Cfg.CELL))


func floor_height(c: Vector2i) -> float:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return 0.0
	return _heights[_idx(c.x, c.y)]


func is_blocked(c: Vector2i) -> bool:
	return not FLOORS.contains(_ch(c.x, c.y)) and _ch(c.x, c.y) != "D"


func site_center(name: String) -> Vector3:
	if not sites.has(name):
		return Vector3.ZERO
	var a: AABB = sites[name]
	var p := a.get_center()
	return Vector3(p.x, 0.0, p.z)


func in_site(pos: Vector3) -> String:
	for k in sites.keys():
		if (sites[k] as AABB).has_point(pos + Vector3(0, 0.5, 0)):
			return k
	return ""


func in_spawn(pos: Vector3, team: int) -> bool:
	if not spawn_zones.has(team):
		return false
	return (spawn_zones[team] as AABB).grow(1.0).has_point(pos + Vector3(0, 0.5, 0))


func get_breakable(id: int) -> Door:
	return breakables.get(id)


func reset_breakables() -> void:
	var rebake := false
	for d in breakables.values():
		if d.kind == "barricade" and d.broken:
			rebake = true
		d.restore()
	if rebake:
		rebake_nav()
