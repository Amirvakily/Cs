class_name Combat
extends RefCounted
## Hitscan tracing, hit zones, penetration and line-of-sight helpers.

const Z_HEAD := 0
const Z_CHEST := 1
const Z_STOMACH := 2
const Z_LEGS := 3
const ZONE_MULT := [4.0, 1.0, 1.25, 0.75]

# How hard each surface is to shoot through (metres of wood-equivalent per metre).
const PEN_FACTOR := {"wood": 1.0, "glass": 0.25, "flesh": 1.0, "dirt": 4.0, "metal": 2.6, "concrete": 3.5}


static func _space() -> PhysicsDirectSpaceState3D:
	return Game.inst.get_world_3d().direct_space_state


static func mat_of(collider: Object) -> String:
	if collider and collider.has_meta("mat"):
		return str(collider.get_meta("mat"))
	return "concrete"


## True when nothing solid blocks the segment (soldiers are ignored).
static func can_see(from: Vector3, to: Vector3) -> bool:
	if Game.inst == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, Cfg.L_WORLD | Cfg.L_DYNAMIC)
	return _space().intersect_ray(q).is_empty()


static func ray(from: Vector3, to: Vector3, mask := Cfg.L_WORLD | Cfg.L_DYNAMIC) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask)
	return _space().intersect_ray(q)


## Ray vs a soldier's hit volumes (in the soldier's yaw frame). Returns {t, zone} or {}.
static func hit_soldier(s: Soldier, origin: Vector3, dir: Vector3, max_t: float) -> Dictionary:
	var b := Basis(Vector3.UP, -s.yaw)
	var lo := b * (origin - s.global_position)
	var ld := b * dir
	var k := lerpf(1.0, Cfg.CROUCH_EYE / Cfg.STAND_EYE, s.crouch_amount)
	var best := max_t
	var zone := -1
	# Head sphere
	var hc := Vector3(0, 1.62 * k, -0.02)
	var oc := lo - hc
	var bb := oc.dot(ld)
	var cc := oc.dot(oc) - 0.17 * 0.17
	var disc := bb * bb - cc
	if disc >= 0.0:
		var t := -bb - sqrt(disc)
		if t > 0.0 and t < best:
			best = t
			zone = Z_HEAD
	var boxes := [
		[Vector3(-0.3, 1.05 * k, -0.17), Vector3(0.3, 1.47 * k, 0.17), Z_CHEST],
		[Vector3(-0.23, 0.8 * k, -0.15), Vector3(0.23, 1.05 * k, 0.15), Z_STOMACH],
		[Vector3(-0.22, 0.0, -0.15), Vector3(0.22, 0.8 * k, 0.15), Z_LEGS],
	]
	for bx in boxes:
		var t := _ray_aabb(lo, ld, bx[0], bx[1])
		if t >= 0.0 and t < best:
			best = t
			zone = int(bx[2])
	if zone < 0:
		return {}
	return {"t": best, "zone": zone}


static func _ray_aabb(o: Vector3, d: Vector3, mn: Vector3, mx: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for i in 3:
		if absf(d[i]) < 1e-8:
			if o[i] < mn[i] or o[i] > mx[i]:
				return -1.0
		else:
			var t1 := (mn[i] - o[i]) / d[i]
			var t2 := (mx[i] - o[i]) / d[i]
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			tmin = maxf(tmin, t1)
			tmax = minf(tmax, t2)
			if tmin > tmax:
				return -1.0
	if tmax < 0.0:
		return -1.0
	return maxf(tmin, 0.0)


## Nearest soldier hit along a segment, skipping ids in `skip`.
static func _soldier_along(pos: Vector3, dir: Vector3, max_t: float, skip: Dictionary) -> Array:
	var best_s: Soldier = null
	var best_t := max_t
	var best_zone := -1
	for s in Game.inst.soldiers.values():
		var so: Soldier = s
		if not so.alive or skip.has(so.id):
			continue
		var c := so.global_position + Vector3(0, 0.9, 0)
		var to_c := c - pos
		var proj := to_c.dot(dir)
		if proj < -1.0 or proj > best_t + 1.0:
			continue
		if (to_c - dir * proj).length_squared() > 1.6:
			continue
		var r := hit_soldier(so, pos, dir, best_t)
		if not r.is_empty():
			best_s = so
			best_t = r["t"]
			best_zone = r["zone"]
	return [best_s, best_t, best_zone]


## Traces one bullet with penetration. Returns {end, hits: [{victim, dmg, zone, pos, dir, wallbang}],
## impacts: [{pos, normal, mat, obj}]}.
static func trace_bullet(shooter: Soldier, origin: Vector3, dir: Vector3, w: Dictionary) -> Dictionary:
	var hits := []
	var impacts := []
	var dmg: float = w.get("dmg", 30.0)
	var pen_total: float = maxf(float(w.get("pen", 0.5)), 0.01)
	var pen_left := pen_total
	var falloff: float = w.get("falloff", 0.95)
	var max_range := 70.0 if w.get("cls", "") == "shotgun" else 220.0
	var pos := origin
	var travelled := 0.0
	var skip := {shooter.id: true}
	var wallbang := false
	var end := origin + dir * max_range
	var space := _space()
	for iter in 8:
		var far := pos + dir * (max_range - travelled)
		var q := PhysicsRayQueryParameters3D.create(pos, far, Cfg.L_WORLD | Cfg.L_DYNAMIC)
		var wh := space.intersect_ray(q)
		var wt := pos.distance_to(wh["position"]) if not wh.is_empty() else max_range - travelled
		var sh := _soldier_along(pos, dir, wt, skip)
		if sh[0] != null:
			var so: Soldier = sh[0]
			var t: float = sh[1]
			var d := dmg * pow(falloff, (travelled + t) / 10.0)
			hits.append({"victim": so.id, "dmg": d, "zone": sh[2], "pos": pos + dir * t, "dir": dir, "wallbang": wallbang})
			skip[so.id] = true
			dmg *= 0.5
			if dmg < 6.0:
				end = pos + dir * t
				break
			continue
		if wh.is_empty():
			end = far
			break
		var hp: Vector3 = wh["position"]
		var mat := mat_of(wh["collider"])
		var imp := {"pos": hp, "normal": wh["normal"], "mat": mat, "obj": 0}
		if wh["collider"] is Object and (wh["collider"] as Object).has_meta("breakable_id"):
			imp["obj"] = int((wh["collider"] as Object).get_meta("breakable_id"))
			imp["dmg"] = dmg
		impacts.append(imp)
		travelled += pos.distance_to(hp)
		end = hp
		# Penetration: find where the bullet exits this shape.
		var probe := 1.6
		var back_q := PhysicsRayQueryParameters3D.create(hp + dir * probe, hp, Cfg.L_WORLD | Cfg.L_DYNAMIC)
		var back := space.intersect_ray(back_q)
		if back.is_empty() or back["collider"] != wh["collider"] or back["shape"] != wh["shape"]:
			break
		var thick := probe - (hp + dir * probe).distance_to(back["position"])
		var cost := thick * float(PEN_FACTOR.get(mat, 3.0))
		if cost >= pen_left:
			break
		pen_left -= cost
		dmg *= 1.0 - clampf(cost / pen_total, 0.0, 1.0) * 0.6
		wallbang = true
		pos = back["position"] + dir * 0.02
		impacts.append({"pos": back["position"], "normal": back["normal"], "mat": mat, "obj": 0, "exit": true})
		travelled += thick
		if travelled >= max_range or dmg < 4.0:
			break
	return {"end": end, "hits": hits, "impacts": impacts}


## Melee trace: returns {victim: Soldier, zone, pos, dir} or {pos, normal, mat, obj} for a wall hit, or {}.
static func melee(shooter: Soldier, origin: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var wh := ray(origin, origin + dir * reach)
	var wt := origin.distance_to(wh["position"]) if not wh.is_empty() else reach
	# Slightly fat melee: test three rays.
	var right := dir.cross(Vector3.UP).normalized() * 0.18
	for off in [Vector3.ZERO, right, -right]:
		var sh := _soldier_along(origin + off, dir, wt, {shooter.id: true})
		if sh[0] != null:
			return {"victim": sh[0], "zone": sh[2], "pos": origin + dir * float(sh[1]), "dir": dir}
	if not wh.is_empty():
		var r := {"pos": wh["position"], "normal": wh["normal"], "mat": mat_of(wh["collider"]), "obj": 0}
		if wh["collider"] is Object and (wh["collider"] as Object).has_meta("breakable_id"):
			r["obj"] = int((wh["collider"] as Object).get_meta("breakable_id"))
		return r
	return {}
