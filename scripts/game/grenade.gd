class_name Grenade
extends Node3D
## Thrown grenade (frag / flash / smoke). Every peer simulates the flight;
## only the server decides when it detonates (Game.grenade_detonated → detonate on all peers).

const RADIUS := 0.07
const RESTITUTION := 0.45
const FRICTION := 0.7
const FRAG_FUSE := 1.8
const FLASH_FUSE := 1.6
const SMOKE_MIN := 1.5
const SMOKE_MAX := 3.0
const FRAG_RADIUS := 7.5
const FRAG_DAMAGE := 100.0
const FLASH_RANGE := 22.0
const SMOKE_RADIUS := 4.5
const SMOKE_TIME := 16.0

var net_id := 0
var type := "frag"
var owner_id := ""
var vel := Vector3.ZERO
var age := 0.0
var rest_time := 0.0
var detonated := false
var _requested := false
var _resting := false
var _visual: Node3D
var _spin_axis := Vector3.RIGHT
var _spin := 0.0
var _last_bounce := -1.0


func setup(p_net_id: int, p_type: String, p_owner_id: String, origin: Vector3, p_vel: Vector3) -> void:
	net_id = p_net_id
	type = p_type
	owner_id = p_owner_id
	vel = p_vel
	name = "Grenade%d" % net_id
	_visual = WeaponModels.build(type)
	add_child(_visual)
	if not _has_mesh(_visual):
		_visual.add_child(_fallback_mesh())
	top_level = false
	position = origin
	if is_inside_tree():
		global_position = origin
	_spin = vel.length() * 3.0
	var flat := Vector3(vel.x, 0, vel.z)
	_spin_axis = flat.cross(Vector3.UP).normalized() if flat.length() > 0.1 else Vector3.RIGHT


func _physics_process(delta: float) -> void:
	if detonated:
		return
	age += delta
	_simulate(delta)
	if _visual and _spin > 0.05:
		_visual.rotate(_spin_axis, -_spin * delta)
	if _game_is_server() and not _requested and _fuse_done():
		_requested = true
		var g := Game.inst
		if g:
			g.grenade_detonated(net_id, global_position)
		else:
			detonate(global_position)


func _fuse_done() -> bool:
	match type:
		"frag":
			return age >= FRAG_FUSE
		"flash":
			return age >= FLASH_FUSE
		"smoke":
			return (age >= SMOKE_MIN and _resting and rest_time > 0.25) or age >= SMOKE_MAX
	return age >= 2.0


func _simulate(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	vel.y -= Cfg.GRAVITY * delta
	var remaining := delta
	var pos := global_position
	for i in 3:
		var motion := vel * remaining
		var dist := motion.length()
		if dist < 0.00001:
			break
		var dir := motion / dist
		var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * (dist + RADIUS), Cfg.L_WORLD | Cfg.L_DYNAMIC)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			pos += motion
			break
		var n: Vector3 = hit["normal"]
		var hit_pos: Vector3 = hit["position"]
		var travelled := maxf(0.0, pos.distance_to(hit_pos) - RADIUS)
		pos += dir * travelled
		var vn := vel.dot(n)
		if vn < 0.0:
			var normal_v := n * vn
			var tangent_v := vel - normal_v
			var impact_speed := -vn
			if impact_speed < 1.2 and n.y > 0.6:
				vel = tangent_v * (1.0 - FRICTION * 0.25)
			else:
				vel = tangent_v * FRICTION - normal_v * RESTITUTION
			if impact_speed > 1.5 and age - _last_bounce > 0.08:
				_last_bounce = age
				Sfx.play3d("bounce", pos, clampf(-14.0 + impact_speed * 1.4, -14.0, 0.0), randf_range(0.9, 1.15), 40.0)
			_spin *= 0.7
		remaining *= 1.0 - travelled / maxf(dist, 0.0001)
		pos += n * 0.002
	# Ground contact / rolling
	var down := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * (RADIUS + 0.03), Cfg.L_WORLD | Cfg.L_DYNAMIC)
	var g := space.intersect_ray(down)
	_resting = false
	if not g.is_empty() and vel.y <= 0.5:
		var gn: Vector3 = g["normal"]
		if gn.y > 0.6:
			var gp: Vector3 = g["position"]
			pos.y = maxf(pos.y, gp.y + RADIUS)
			if vel.y < 0.0:
				vel.y = 0.0
			var flat := Vector3(vel.x, 0, vel.z)
			flat = flat.move_toward(Vector3.ZERO, 4.0 * delta)
			vel.x = flat.x
			vel.z = flat.z
			_spin = flat.length() / RADIUS * 0.3
			if flat.length() > 0.05:
				_spin_axis = flat.cross(Vector3.UP).normalized()
			if vel.length() < 0.15:
				vel = Vector3.ZERO
				_resting = true
	if _resting:
		rest_time += delta
	else:
		rest_time = 0.0
	global_position = pos


## Called on every peer (from Game) when the server decides the grenade goes off.
func detonate(pos: Vector3) -> void:
	if detonated:
		return
	detonated = true
	global_position = pos
	var g := Game.inst
	var fx: Effects = g.fx if g else null
	var server := _game_is_server()
	match type:
		"frag":
			if fx:
				fx.explosion(pos, "frag")
			if server and g:
				g.explosion(pos, FRAG_RADIUS, FRAG_DAMAGE, owner_id, "frag")
				g.noise(pos, 1.0, owner_id)
			queue_free()
		"flash":
			if fx:
				fx.flash_burst(pos)
			if server and g:
				_apply_flash(g, pos)
				g.noise(pos, 0.8, owner_id)
			queue_free()
		"smoke":
			if fx:
				fx.smoke_cloud(pos, SMOKE_RADIUS, SMOKE_TIME)
			if server and g:
				g.add_smoke(pos, SMOKE_RADIUS, SMOKE_TIME)
				g.noise(pos, 0.3, owner_id)
			# The spent canister stays on the ground while the smoke lasts.
			get_tree().create_timer(SMOKE_TIME + 2.0).timeout.connect(queue_free)
		_:
			queue_free()


## Server: compute blindness for every living soldier that can see the flash.
func _apply_flash(g: Game, pos: Vector3) -> void:
	var src := pos + Vector3.UP * 0.15
	for s in g.alive_soldiers():
		var sol: Soldier = s
		var eye := sol.eye_pos()
		var d := eye.distance_to(src)
		if d > FLASH_RANGE:
			continue
		if not Combat.can_see(src, eye):
			continue
		if g.smoke_blocks(src, eye):
			continue
		var to_flash := (src - eye).normalized()
		var facing := sol.aim_dir().dot(to_flash) # 1 = looking straight at it
		var facing_mult := 1.0
		if facing < 0.5:
			# Looking away still dazzles a little, especially up close.
			facing_mult = lerpf(0.12, 1.0, clampf((facing + 1.0) / 1.5, 0.0, 1.0))
		var dist_mult := clampf(1.0 - pow(d / FLASH_RANGE, 1.4), 0.0, 1.0)
		var strength := clampf(dist_mult * facing_mult * 1.35, 0.0, 1.0)
		if strength > 0.05:
			sol.apply_flash(strength)


func _game_is_server() -> bool:
	if Game.inst:
		return Game.inst.is_server()
	return Net.is_server()


func _has_mesh(n: Node) -> bool:
	if n is MeshInstance3D:
		return true
	for c in n.get_children():
		if _has_mesh(c):
			return true
	return false


func _fallback_mesh() -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.6
	match type:
		"frag":
			var sp := SphereMesh.new()
			sp.radius = 0.05
			sp.height = 0.1
			m.mesh = sp
			mat.albedo_color = Color(0.22, 0.27, 0.18)
		_:
			var cy := CylinderMesh.new()
			cy.top_radius = 0.035
			cy.bottom_radius = 0.035
			cy.height = 0.13
			m.mesh = cy
			mat.albedo_color = Color(0.3, 0.32, 0.34) if type == "flash" else Color(0.25, 0.3, 0.25)
	m.material_override = mat
	return m
