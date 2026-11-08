class_name Rules
extends RefCounted
## Server-side match rules for Demolition (defusal), Team Deathmatch and Squad Hunt.

var g: Game
var mode := Cfg.MODE_DEFUSAL
var atk_plan := "A"
var loss_streak := [0, 0]
var phase_end := 0.0
var buy_end := 0.0
var bomb_end := 0.0
var planter_id := ""
var respawn_at := {} # soldier id -> time
var spawn_time := {} # soldier id -> time of last spawn
var round_start_time := 0.0
var _rng := RandomNumberGenerator.new()
var _over_handled := false
var _last_beep := 0.0

const TDM_TIME := 600.0
const TDM_KILLS := 60
const HUNT_FREEZE := 8.0
const RESPAWN_TDM := 3.0
const RESPAWN_HUNT := 12.0


func _init(p_game: Game) -> void:
	g = p_game
	mode = g.game_mode()
	_rng.randomize()


func now() -> float:
	return g.now()


func max_rounds() -> int:
	return int(g.config.get("rounds", 16))


func start_money() -> int:
	return Cfg.START_MONEY if mode == Cfg.MODE_DEFUSAL else 16000


func price(s: Soldier, item: String) -> int:
	if mode != Cfg.MODE_DEFUSAL:
		return 0
	if item == "helmet" and s.armor >= 100 and not s.helmet:
		return 350
	return Cfg.item_price(item)


func buy_allowed(s: Soldier) -> bool:
	match mode:
		Cfg.MODE_DEFUSAL:
			return g.rs["phase"] == "freeze" or (g.rs["phase"] == "live" and now() < buy_end)
		Cfg.MODE_TDM:
			return now() - float(spawn_time.get(s.id, -100.0)) < 15.0
		_:
			return g.rs["phase"] == "freeze" or now() - float(spawn_time.get(s.id, -100.0)) < 10.0


# ---------------------------------------------------------------------------
func start() -> void:
	g.rs["max_rounds"] = max_rounds()
	g.rs["score"] = [0, 0]
	g.rs["round"] = 1
	balance_bots()
	match mode:
		Cfg.MODE_DEFUSAL:
			start_round(true)
		Cfg.MODE_TDM:
			g.rs["kill_limit"] = TDM_KILLS
			g.rs["phase"] = "live"
			phase_end = now() + TDM_TIME
			for s in g.soldiers.values():
				_spawn_free(s)
			g.emit_round_event("round_start", {"round": 1})
		Cfg.MODE_HUNT:
			_start_hunt()
	_sync()


func _sync() -> void:
	g.rs["time_left"] = maxf(0.0, phase_end - now())
	g.rs["buy_time_left"] = maxf(0.0, buy_end - now())
	if g.rs["bomb"]["state"] == "planted":
		g.rs["bomb"]["time_left"] = maxf(0.0, bomb_end - now())
	g.broadcast_rs()


func humans_on(team: int) -> int:
	var n := 0
	for s in g.soldiers.values():
		if not s.is_bot and s.team == team:
			n += 1
	return n


func count_on(team: int) -> int:
	return g.team_soldiers(team).size()


func auto_team() -> int:
	if mode == Cfg.MODE_HUNT:
		return 0
	var a := humans_on(Cfg.ATK)
	var d := humans_on(Cfg.DEF)
	if a != d:
		return Cfg.ATK if a < d else Cfg.DEF
	return Cfg.ATK if count_on(Cfg.ATK) <= count_on(Cfg.DEF) else Cfg.DEF


## Keeps team sizes at the configured total, replacing bots with humans as they join.
func balance_bots() -> void:
	if mode == Cfg.MODE_HUNT:
		_balance_hunt()
		return
	var total := int(g.config.get("bots", 9)) + (0 if g.dedicated else 1)
	total = maxi(total, humans_on(0) + humans_on(1))
	var per_team := [int(ceil(total / 2.0)), total / 2]
	# Put the extra slot on the team with more humans.
	if humans_on(Cfg.DEF) > humans_on(Cfg.ATK):
		per_team = [total / 2, int(ceil(total / 2.0))]
	for team in [Cfg.ATK, Cfg.DEF]:
		var want: int = maxi(per_team[team], humans_on(team))
		var have := count_on(team)
		while have > want:
			var bot := _pick_bot(team)
			if bot == null:
				break
			g.server_remove_soldier(bot.id)
			have -= 1
		while have < want:
			var b := g.server_add_bot(team)
			b.money = start_money()
			have += 1
			_late_spawn(b)


func _balance_hunt() -> void:
	var squad_target := maxi(4, humans_on(0))
	var have := count_on(0)
	while have > squad_target:
		var bot := _pick_bot(0)
		if bot == null:
			break
		g.server_remove_soldier(bot.id)
		have -= 1
	while have < squad_target:
		var b := g.server_add_bot(0)
		b.money = 16000
		have += 1
		_late_spawn(b)


func _pick_bot(team: int) -> Soldier:
	var best: Soldier = null
	for s in g.soldiers.values():
		if s.is_bot and s.team == team:
			if best == null or (not s.alive and best.alive):
				best = s
	return best


func _late_spawn(s: Soldier) -> void:
	match mode:
		Cfg.MODE_DEFUSAL:
			if g.rs["phase"] == "freeze" or (g.rs["phase"] == "live" and now() - round_start_time < 20.0):
				_give_defaults(s)
				g.server_spawn(s, _spawn_point(s.team))
		Cfg.MODE_TDM:
			_spawn_free(s)
		Cfg.MODE_HUNT:
			if s.team == 0 and g.rs["phase"] in ["freeze", "live"]:
				_spawn_free(s)


func on_player_joined(s: Soldier) -> void:
	_late_spawn(s)
	_sync()


func _give_defaults(s: Soldier) -> void:
	if s.secondary == "":
		s.secondary = "m9"
	s.ammo.clear()


func _spawn_point(team: int) -> Transform3D:
	var pts: Array = g.world.spawn_points.get(team, [])
	if pts.is_empty():
		return Transform3D(Basis.IDENTITY, g.world.random_nav_point())
	# Prefer points with no one standing on them.
	for i in pts.size():
		var xf: Transform3D = pts[_rng.randi() % pts.size()]
		var free := true
		for s in g.alive_soldiers():
			if s.global_position.distance_to(xf.origin) < 1.2:
				free = false
				break
		if free:
			return xf
	var base: Transform3D = pts[_rng.randi() % pts.size()]
	return base.translated(Vector3(_rng.randf_range(-0.6, 0.6), 0, _rng.randf_range(-0.6, 0.6)))


func _spawn_free(s: Soldier) -> void:
	# TDM / hunt: free loadout from the buy menu, sensible defaults for bots.
	if s.secondary == "":
		s.secondary = "m9"
	s.ammo.clear()
	if s.is_bot:
		_bot_default_loadout(s)
	var xf := _spawn_point(s.team) if mode != Cfg.MODE_HUNT or s.team == 0 else _hostile_point()
	spawn_time[s.id] = now()
	g.server_spawn(s, xf)
	if s.is_bot and s.brain:
		s.brain.buy_loadout()


func _bot_default_loadout(s: Soldier) -> void:
	var picks := ["kv74", "ar7", "hornet", "vespa", "mako", "breacher", "thresher", "sentry"]
	if mode == Cfg.MODE_HUNT and s.team == 1:
		picks = ["kv74", "vespa", "mako", "breacher", "kv74", "raptor"]
	var p: String = picks[_rng.randi() % picks.size()]
	if Cfg.w(p).get("slot", 1) == 2:
		s.secondary = p
	else:
		s.primary = p
	s.armor = 100
	s.helmet = mode != Cfg.MODE_HUNT or s.team == 0
	if _rng.randf() < 0.5:
		s.grenades["frag"] = 1


func _hostile_point() -> Transform3D:
	var squad_spawn: AABB = g.world.spawn_zones.get(Cfg.ATK, AABB())
	for i in 30:
		var p := g.world.random_nav_point()
		if p.distance_to(squad_spawn.get_center()) > 28.0:
			return Transform3D(Basis(Vector3.UP, _rng.randf() * TAU), p)
	return Transform3D(Basis.IDENTITY, g.world.random_nav_point())


# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------
func update(delta: float) -> void:
	match mode:
		Cfg.MODE_DEFUSAL:
			_update_defusal()
		Cfg.MODE_TDM:
			_update_tdm()
		Cfg.MODE_HUNT:
			_update_hunt()
	g.rs["time_left"] = maxf(0.0, phase_end - now())
	g.rs["buy_time_left"] = maxf(0.0, buy_end - now())
	if g.rs["bomb"]["state"] == "planted":
		g.rs["bomb"]["time_left"] = maxf(0.0, bomb_end - now())


# --- Demolition -----------------------------------------------------------------
func start_round(first := false) -> void:
	_over_handled = false
	g.reset_map()
	g.rs["phase"] = "freeze"
	g.rs["winner"] = -1
	g.rs["bomb"] = {"state": "none", "carrier": "", "pos": Vector3.ZERO, "time_left": 0.0, "site": ""}
	phase_end = now() + Cfg.FREEZE_TIME
	buy_end = now() + Cfg.FREEZE_TIME + Cfg.BUY_TIME
	round_start_time = now()
	planter_id = ""
	atk_plan = "A" if _rng.randf() < 0.5 else "B"
	var atk := []
	for s in g.soldiers.values():
		var so: Soldier = s
		if first:
			so.money = start_money()
			so.primary = ""
			so.secondary = ""
			so.armor = 0
			so.helmet = false
			so.has_kit = false
			so.grenades = {"frag": 0, "flash": 0, "smoke": 0}
			so.breach_charges = 0
		so.has_bomb = false
		_give_defaults(so)
		if so.team == Cfg.ATK:
			atk.append(so)
	# Spread soldiers over the spawn points.
	for team in [Cfg.ATK, Cfg.DEF]:
		var pts: Array = g.world.spawn_points.get(team, []).duplicate()
		pts.shuffle()
		var i := 0
		for s in g.team_soldiers(team):
			var xf: Transform3D = pts[i % pts.size()] if not pts.is_empty() else _spawn_point(team)
			if i >= pts.size():
				xf = xf.translated(Vector3(0.6, 0, 0.6))
			i += 1
			g.server_spawn(s, xf)
	if not atk.is_empty():
		var carrier: Soldier = atk[_rng.randi() % atk.size()]
		carrier.has_bomb = true
		g.rs["bomb"]["state"] = "carried"
		g.rs["bomb"]["carrier"] = carrier.id
	for s in g.soldiers.values():
		g.sync_inventory(s)
		if s.is_bot and s.brain:
			s.brain.buy_loadout()
	g.emit_round_event("round_start", {"round": g.rs["round"], "plan": atk_plan})
	_sync()


func _update_defusal() -> void:
	var phase: String = g.rs["phase"]
	var t := now()
	match phase:
		"freeze":
			if t >= phase_end:
				g.rs["phase"] = "live"
				phase_end = t + Cfg.ROUND_TIME
				_sync()
		"live":
			var bomb: Dictionary = g.rs["bomb"]
			var atk_alive := g.alive_soldiers(Cfg.ATK).size()
			var def_alive := g.alive_soldiers(Cfg.DEF).size()
			var atk_total := count_on(Cfg.ATK)
			var def_total := count_on(Cfg.DEF)
			if bomb["state"] == "planted":
				if t >= bomb_end:
					_explode_bomb()
				elif def_alive == 0 and def_total > 0:
					pass # nothing can stop it now; wait for the explosion
			else:
				if atk_alive == 0 and atk_total > 0:
					end_round(Cfg.DEF, "elimination")
				elif def_alive == 0 and def_total > 0:
					end_round(Cfg.ATK, "elimination")
				elif t >= phase_end:
					end_round(Cfg.DEF, "time")
		"post":
			if t >= phase_end:
				_after_round()
		"over":
			if t >= phase_end and not _over_handled:
				_over_handled = true
				_next_match()


func plant(s: Soldier, pos: Vector3) -> void:
	if mode != Cfg.MODE_DEFUSAL or g.rs["phase"] != "live" or not s.alive or not s.has_bomb:
		return
	var site := g.world.in_site(pos)
	if site == "":
		return
	s.has_bomb = false
	g.sync_inventory(s)
	planter_id = s.id
	bomb_end = now() + Cfg.BOMB_TIME
	g.rs["bomb"] = {"state": "planted", "carrier": "", "pos": pos, "time_left": Cfg.BOMB_TIME, "site": site}
	s.money = mini(Cfg.MAX_MONEY, s.money + Cfg.PLANT_BONUS)
	s.score += 2
	g.set_bomb_prop(pos)
	g.emit_round_event("bomb_planted", {"site": site, "by": s.display_name})
	g.server_message("The charge has been planted at site %s." % site)
	_sync()


func defuse(s: Soldier) -> void:
	var bomb: Dictionary = g.rs["bomb"]
	if bomb["state"] != "planted" or not s.alive or s.team != Cfg.DEF:
		return
	if s.global_position.distance_to(bomb["pos"]) > 2.2:
		return
	bomb["state"] = "defused"
	s.money = mini(Cfg.MAX_MONEY, s.money + Cfg.DEFUSE_BONUS)
	s.score += 2
	g.emit_round_event("bomb_defused", {"by": s.display_name})
	g.set_bomb_prop(null)
	end_round(Cfg.DEF, "defused")


func _explode_bomb() -> void:
	var bomb: Dictionary = g.rs["bomb"]
	bomb["state"] = "exploded"
	var pos: Vector3 = bomb["pos"]
	g.bomb_explode_fx(pos)
	g.explosion(pos, 26.0, 520.0, planter_id, "bomb")
	g.emit_round_event("bomb_exploded", {})
	end_round(Cfg.ATK, "bomb")


func end_round(winner: int, reason: String) -> void:
	if g.rs["phase"] != "live":
		return
	g.rs["phase"] = "post"
	g.rs["winner"] = winner
	phase_end = now() + Cfg.POST_ROUND_TIME
	var score: Array = g.rs["score"]
	score[winner] = int(score[winner]) + 1
	var loser := 1 - winner
	loss_streak[winner] = 0
	loss_streak[loser] = mini(int(loss_streak[loser]) + 1, 5)
	var win_money := Cfg.WIN_ELIM
	match reason:
		"bomb":
			win_money = Cfg.WIN_BOMB
		"defused":
			win_money = Cfg.WIN_DEFUSE
		"time":
			win_money = Cfg.WIN_TIME
	var loss_money := mini(Cfg.LOSS_BASE + Cfg.LOSS_STEP * (int(loss_streak[loser]) - 1), Cfg.LOSS_MAX)
	for s in g.soldiers.values():
		var so: Soldier = s
		if so.team == winner:
			so.money = mini(Cfg.MAX_MONEY, so.money + win_money)
		elif so.team == loser:
			var bonus := Cfg.PLANT_TEAM_BONUS if (loser == Cfg.ATK and planter_id != "") else 0
			so.money = mini(Cfg.MAX_MONEY, so.money + loss_money + bonus)
		g.sync_inventory(so)
	var reason_text: String = {"elimination": "eliminated the enemy", "bomb": "destroyed the target", "defused": "defused the charge",
		"time": "held until time ran out"}.get(reason, "")
	g.emit_round_event("round_end", {"winner": winner, "reason": reason, "text": "%s %s" % [Cfg.TEAM_NAMES[winner], reason_text]})
	_sync()


func _after_round() -> void:
	var score: Array = g.rs["score"]
	var to_win := max_rounds() / 2 + 1
	var played := int(score[0]) + int(score[1])
	if int(score[0]) >= to_win or int(score[1]) >= to_win or played >= max_rounds():
		var winner := 0 if int(score[0]) > int(score[1]) else (1 if int(score[1]) > int(score[0]) else -1)
		g.rs["phase"] = "over"
		g.rs["winner"] = winner
		phase_end = now() + 12.0
		g.emit_round_event("match_over", {"winner": winner})
		_sync()
		return
	g.rs["round"] = played + 1
	if played == max_rounds() / 2:
		_halftime()
		start_round(true)
		return
	start_round(false)


func _halftime() -> void:
	var score: Array = g.rs["score"]
	g.rs["score"] = [score[1], score[0]]
	loss_streak = [0, 0]
	for s in g.soldiers.values():
		g.server_set_team(s, 1 - s.team)
	g.emit_round_event("halftime", {})


func _next_match() -> void:
	var rot: Array = g.config.get("rotation", [])
	if g.dedicated and rot.size() > 1:
		var idx := int(g.config.get("rotation_index", 0)) + 1
		var entry: Dictionary = rot[idx % rot.size()]
		var cfg := g.config.duplicate(true)
		cfg["map"] = entry.get("map", cfg["map"])
		cfg["mode"] = entry.get("mode", cfg["mode"])
		cfg["rotation_index"] = idx % rot.size()
		g.change_map(cfg)
		return
	g.rs["score"] = [0, 0]
	g.rs["round"] = 1
	for s in g.soldiers.values():
		s.kills = 0
		s.deaths = 0
		s.score = 0
	loss_streak = [0, 0]
	match mode:
		Cfg.MODE_DEFUSAL:
			start_round(true)
		Cfg.MODE_TDM:
			start()
		Cfg.MODE_HUNT:
			_start_hunt()


# --- deaths & kills ---------------------------------------------------------------
func on_kill(killer: Soldier, victim: Soldier, wid: String) -> void:
	if mode == Cfg.MODE_DEFUSAL:
		if killer and killer != victim:
			if killer.team == victim.team:
				killer.money = maxi(0, killer.money - Cfg.TEAMKILL_PENALTY)
			else:
				var reward := int(Cfg.w(wid).get("reward", 300))
				killer.money = mini(Cfg.MAX_MONEY, killer.money + reward)
			g.sync_inventory(killer)
	elif mode == Cfg.MODE_TDM:
		if killer and killer != victim and killer.team != victim.team:
			var score: Array = g.rs["score"]
			score[killer.team] = int(score[killer.team]) + 1
		respawn_at[victim.id] = now() + RESPAWN_TDM
		_sync()
	elif mode == Cfg.MODE_HUNT:
		if victim.team == 1:
			g.rs["hostiles_left"] = g.alive_soldiers(1).size()
		elif not victim.is_bot:
			respawn_at[victim.id] = now() + RESPAWN_HUNT
		_sync()


# --- TDM ----------------------------------------------------------------------------
func _update_tdm() -> void:
	var t := now()
	if g.rs["phase"] == "live":
		for id in respawn_at.keys():
			if t >= float(respawn_at[id]):
				respawn_at.erase(id)
				var s: Soldier = g.soldiers.get(id)
				if s and not s.alive:
					_spawn_free(s)
		var score: Array = g.rs["score"]
		if int(score[0]) >= TDM_KILLS or int(score[1]) >= TDM_KILLS or t >= phase_end:
			var winner := 0 if int(score[0]) > int(score[1]) else (1 if int(score[1]) > int(score[0]) else -1)
			g.rs["phase"] = "over"
			g.rs["winner"] = winner
			phase_end = t + 12.0
			g.emit_round_event("match_over", {"winner": winner})
			_sync()
	elif g.rs["phase"] == "over" and t >= phase_end and not _over_handled:
		_over_handled = true
		respawn_at.clear()
		_next_match()
		_over_handled = false


# --- Squad Hunt ---------------------------------------------------------------------
func _start_hunt() -> void:
	_over_handled = false
	g.reset_map()
	respawn_at.clear()
	# Hostile count by difficulty.
	var want: int = [12, 16, 20, 26][clampi(int(g.config.get("difficulty", 1)), 0, 3)]
	var have := count_on(1)
	while have < want:
		g.server_add_bot(1)
		have += 1
	while have > want:
		var b := _pick_bot(1)
		if b == null:
			break
		g.server_remove_soldier(b.id)
		have -= 1
	_balance_hunt()
	g.rs["phase"] = "freeze"
	phase_end = now() + HUNT_FREEZE
	for s in g.soldiers.values():
		var so: Soldier = s
		so.primary = ""
		so.grenades = {"frag": 0, "flash": 0, "smoke": 0}
		so.armor = 0
		so.helmet = false
		_spawn_free(so)
	g.rs["hostiles_left"] = count_on(1)
	g.emit_round_event("round_start", {"round": 1})
	_sync()


func _update_hunt() -> void:
	var t := now()
	match g.rs["phase"]:
		"freeze":
			if t >= phase_end:
				g.rs["phase"] = "live"
				phase_end = t + 1800.0
				_sync()
		"live":
			for id in respawn_at.keys():
				if t >= float(respawn_at[id]):
					respawn_at.erase(id)
					var s: Soldier = g.soldiers.get(id)
					if s and not s.alive and g.alive_soldiers(0).size() > 0:
						_spawn_free(s)
			g.rs["hostiles_left"] = g.alive_soldiers(1).size()
			if g.alive_soldiers(1).is_empty():
				_hunt_over(0)
			elif g.alive_soldiers(0).is_empty() and count_on(0) > 0:
				_hunt_over(1)
		"over":
			if t >= phase_end and not _over_handled:
				_over_handled = true
				_next_match()


func _hunt_over(winner: int) -> void:
	g.rs["phase"] = "over"
	g.rs["winner"] = winner
	phase_end = now() + 12.0
	var score: Array = g.rs["score"]
	score[winner] = int(score[winner]) + 1
	g.emit_round_event("match_over", {"winner": winner, "text": "AREA CLEARED" if winner == 0 else "SQUAD ELIMINATED"})
	_sync()
