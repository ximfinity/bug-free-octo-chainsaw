extends RefCounted
## Drives the character you're not controlling. They hang around the spot
## where you left them ("anchor"): wandering, foraging berries and mushrooms,
## sometimes chopping firewood, eating when hungry, fleeing (or fighting
## back) when danger comes close, and heading to a lit camp at night.

const Decor = preload("res://scripts/world/decor.gd")

const ROAM_TILES := 6
const THREAT_RADIUS := 170.0
const FIGHT_RADIUS := 34.0

var state: String = "idle"
var timer: float = 1.5
var target: Vector2 = Vector2.ZERO
var job: String = ""
var job_tile: Vector2i = Vector2i.ZERO
var speed_mult: float = 0.6
var _stuck: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _alarm_cd: float = 0.0
var _fish_t: float = 60.0
var _greeted: bool = true


## Ask the partner to come to `pos` (they then stay there).
func come_to(c, pos: Vector2) -> void:
	c.anchor = pos
	state = "follow"
	target = pos
	speed_mult = 0.95


func tick(c, delta: float) -> void:
	c.ai_input = Vector2.ZERO
	_alarm_cd -= delta
	if c.downed or c.is_carrying():
		return
	if c.is_paddling():
		# Waiting in a parked kayak with a rod: catch the odd fish.
		if c.inventory.has("fishing_rod") and c.kayak.driver() == null:
			_fish_t -= delta
			if _fish_t <= 0.0:
				_fish_t = randf_range(50.0, 90.0)
				if c.inventory.add("fish_raw", 1) > 0:
					c.main.partner_message(c, "%s caught a fish." % c.char_name)
		return
	var main = c.main
	# Danger first.
	var threat = main.nearest_threat(c.position, THREAT_RADIUS)
	if threat != null:
		c._cancel_tool()
		var away: Vector2 = c.position - threat.position
		if away.length() < FIGHT_RADIUS:
			c.try_attack(false, threat.position)
		var safe: Vector2 = main.safe_point_for(c)
		var dir: Vector2 = away.normalized()
		if safe != Vector2.INF:
			dir = (dir + (safe - c.position).normalized() * 0.6).normalized()
		c.ai_input = dir
		speed_mult = 1.0
		if _alarm_cd <= 0.0:
			main.partner_message(c, "%s is being chased by a %s!" % [c.char_name, threat.kind])
			_alarm_cd = 12.0
		state = "idle"
		timer = 2.0
		return
	if c.hunger < 40.0 and c.digesting <= 0.0:
		c.eat_best()
	# Head for the lit camp when night falls.
	if main.day_night.is_night() and main.camp != null and main.camp.lit:
		var fire: Vector2 = main.camp.fire_position()
		if c.position.distance_to(fire) > 100.0 and c.position.distance_to(fire) < 32.0 * 30:
			if state != "follow":
				come_to(c, fire + Vector2(randf_range(-40, 40), 50))
	# A wave hello when you come back.
	var d_you: float = c.position.distance_to(main.player.position)
	if d_you > 400.0:
		_greeted = false
	elif d_you < 96.0 and not _greeted:
		_greeted = true
		main.emote(c, "wave")
	if c.tool_action != "":
		return
	timer -= delta
	match state:
		"follow", "walk":
			_walk_toward(c, delta)
			if c.position.distance_to(target) < 18.0:
				if state == "walk" and job != "":
					if c.action_for_tile(job_tile) == job:
						c.start_action(job, job_tile)
					job = ""
				state = "idle"
				timer = randf_range(2.0, 5.0)
				speed_mult = 0.6
			elif _stuck > 2.5:
				job = ""
				state = "idle"
				timer = randf_range(1.0, 3.0)
				if c.position.distance_to(c.anchor) > 32.0 * (ROAM_TILES + 4):
					# Can't get back: make here the new home.
					c.anchor = c.position
		_:
			if timer <= 0.0:
				_choose(c)


func _walk_toward(c, delta: float) -> void:
	var to: Vector2 = target - c.position
	if to.length() > 4.0:
		c.ai_input = to.normalized()
	if c.position.distance_to(_last_pos) < 0.5:
		_stuck += delta
	else:
		_stuck = 0.0
	_last_pos = c.position


func _choose(c) -> void:
	var w = c.world
	speed_mult = 0.6
	_stuck = 0.0
	var home: Vector2i = w.tile_at_pos(c.anchor)
	# Look for something useful to do near home.
	if randf() < 0.55:
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: float = 1e20
		var want_wood: bool = c.inventory.count("wood") < 8 and randf() < 0.35
		for i in 40:
			var t := Vector2i(home.x + randi_range(-ROAM_TILES, ROAM_TILES), home.y + randi_range(-ROAM_TILES, ROAM_TILES))
			var d: int = w.get_decor(t.x, t.y)
			var ok: bool = d == Decor.BERRYBUSH or d == Decor.MUSHROOMS or (want_wood and Decor.is_tree(d))
			if not ok:
				continue
			var dist: float = c.position.distance_to(w.tile_center(t))
			if dist < best_d:
				best_d = dist
				best = t
		if best.x >= 0:
			# Stand on a walkable neighbour facing the target.
			for off in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
				var stand: Vector2i = best + off
				if w.is_walkable(stand.x, stand.y) and c.can_be_at(w.tile_center(stand), false):
					target = w.tile_center(stand)
					job_tile = best
					job = c.action_for_tile(best)
					if job == "chop" or job == "forage":
						c.facing = (w.tile_center(best) - target).normalized()
						state = "walk"
						return
	# Otherwise wander near home.
	for i in 10:
		var p: Vector2 = c.anchor + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 32.0 * ROAM_TILES * 0.7
		if c.can_be_at(p, false):
			target = p
			job = ""
			state = "walk"
			return
	timer = 2.0
