extends Node
## Keeps a population of animals in a ring around the player, by biome.

const Tiles = preload("res://scripts/world/tiles.gd")
const AnimalScript = preload("res://scripts/entities/animal.gd")

const SPAWN_MIN := 22
const SPAWN_MAX := 34
const DESPAWN_DIST := 48 * 32
const MAX_PREY := 16
const MAX_WOLVES := 5
const MAX_DANGER := 4

var main
var _timer: float = 0.0
var _rare_timer: float = 20.0
const RARE_CHANCE := 0.22


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.2
	var prey: int = 0
	var wolves: int = 0
	var danger: int = 0
	var rares: int = 0
	for a in get_tree().get_nodes_in_group("animals"):
		if a.position.distance_to(main.player.position) > DESPAWN_DIST:
			a.queue_free()
			continue
		if a.is_rare():
			rares += 1
		elif a.kind == "wolf":
			wolves += 1
		elif a.is_predator():
			danger += 1
		else:
			prey += 1
	if prey < MAX_PREY:
		_try_spawn(false)
	if main.day_night.is_night() and wolves < MAX_WOLVES:
		_try_spawn(true)
	if danger < MAX_DANGER and randf() < 0.5:
		_try_spawn_danger()
	_rare_timer -= 1.2
	if rares == 0 and _rare_timer <= 0.0:
		_rare_timer = randf_range(12.0, 24.0)
		if randf() < RARE_CHANCE * (3.0 if main.in_grove(main.player.position) else 1.0):
			try_spawn_rare()


func _try_spawn(predator: bool) -> void:
	var world = main.world
	var center: Vector2i = world.tile_at_pos(main.player.position)
	for _i in 8:
		var ang: float = randf() * TAU
		var r: float = randf_range(SPAWN_MIN, SPAWN_MAX)
		var t := Vector2i(center.x + int(cos(ang) * r), center.y + int(sin(ang) * r))
		if not world.in_bounds(t.x, t.y):
			continue
		var tt: int = world.get_tile(t.x, t.y)
		var kind: String = ""
		if predator:
			if tt == Tiles.GRASS or Tiles.is_forest(tt) or tt == Tiles.HILL or tt == Tiles.ROCKY:
				kind = "wolf"
		else:
			match tt:
				Tiles.GRASS, Tiles.SAND:
					kind = "rabbit" if randf() < 0.7 else "deer"
				Tiles.FOREST, Tiles.BIRCH, Tiles.MAPLE:
					kind = "deer" if randf() < 0.6 else "rabbit"
				Tiles.MEADOW:
					kind = "rabbit" if randf() < 0.8 else "deer"
				Tiles.SHALLOW, Tiles.DEEP:
					if randf() < 0.5:
						kind = "duck"
				Tiles.HILL, Tiles.ROCKY:
					if randf() < 0.4:
						kind = "deer"
		if kind == "":
			continue
		var a = AnimalScript.new()
		a.kind = kind
		a.main = main
		a.position = world.tile_center(t)
		main.entities.add_child(a)
		return


## Spiders, wildcats and bears by biome (spiders more common at night).
func _try_spawn_danger() -> void:
	var world = main.world
	var center: Vector2i = world.tile_at_pos(main.player.position)
	var night: bool = main.day_night.is_night()
	for _i in 6:
		var ang: float = randf() * TAU
		var r: float = randf_range(SPAWN_MIN + 2, SPAWN_MAX + 4)
		var t := Vector2i(center.x + int(cos(ang) * r), center.y + int(sin(ang) * r))
		if not world.in_bounds(t.x, t.y) or main.is_in_safe_zone(world.tile_center(t)) \
				or main.in_grove(world.tile_center(t)):
			continue
		var tt: int = world.get_tile(t.x, t.y)
		var kind: String = ""
		var roll: float = randf()
		match tt:
			Tiles.FOREST, Tiles.MAPLE:
				if roll < (0.6 if night else 0.3):
					kind = "spider"
				elif roll < 0.5:
					kind = "wildcat"
			Tiles.BIRCH:
				if roll < 0.25:
					kind = "bear"
				elif roll < 0.4:
					kind = "spider"
			Tiles.ROCKY, Tiles.HILL:
				if roll < 0.35:
					kind = "wildcat"
		if kind == "":
			continue
		var count: int = 1
		if kind == "spider":
			count = 3 if night else 2
		for k in count:
			var a = AnimalScript.new()
			a.kind = kind
			a.main = main
			a.position = world.tile_center(t) + Vector2(randf_range(-24, 24), randf_range(-24, 24))
			main.entities.add_child(a)
		return


## Picks a rare creature suited to a nearby tile, time of day and season of
## the game. Returns the spawned animal (or null).
func try_spawn_rare(force_kind: String = ""):
	var world = main.world
	var center: Vector2i = world.tile_at_pos(main.player.position)
	var hour: float = main.day_night.time_of_day
	var night: bool = main.day_night.is_night()
	var dusk_dawn: bool = (hour >= 4.5 and hour < 8.5) or (hour >= 17.0 and hour < 21.5)
	for _i in 24:
		var ang: float = randf() * TAU
		var r: float = randf_range(14, SPAWN_MAX)
		var t := Vector2i(center.x + int(cos(ang) * r), center.y + int(sin(ang) * r))
		if not world.in_bounds(t.x, t.y):
			continue
		var tt: int = world.get_tile(t.x, t.y)
		var options: Array = []
		match tt:
			Tiles.GRASS, Tiles.MEADOW:
				if dusk_dawn:
					options.append(["fox", 6])
			Tiles.BIRCH, Tiles.MAPLE:
				if not night:
					options.append(["white_stag", 1])
				if night:
					options.append(["owl", 4])
			Tiles.FOREST:
				if night:
					options.append(["owl", 4])
				options.append(["moose", 2])
			Tiles.MARSH:
				options.append(["moose", 5])
			Tiles.RIVER:
				if not night:
					options.append(["otter", 6])
			Tiles.DEEP:
				options.append(["loon", 4])
				if night:
					options.append(["spirit", 2])
			Tiles.SHALLOW:
				options.append(["loon", 1])
		if force_kind != "":
			options = [[force_kind, 1]]
		if options.is_empty():
			continue
		var total: int = 0
		for o in options:
			total += int(o[1])
		var roll: int = randi_range(1, total)
		var kind: String = options[0][0]
		for o in options:
			roll -= int(o[1])
			if roll <= 0:
				kind = o[0]
				break
		var a = AnimalScript.new()
		a.kind = kind
		a.main = main
		a.position = world.tile_center(t)
		if not a._can_stand_kind(a.position):
			a.free()
			continue
		main.entities.add_child(a)
		return a
	return null


## Wolves slink away at dawn.
func on_morning() -> void:
	for a in get_tree().get_nodes_in_group("animals"):
		if a.kind == "wolf":
			a.leaving = true
			var tw: Tween = a.create_tween()
			tw.tween_interval(6.0)
			tw.tween_callback(a.queue_free)


func clear_wolves() -> void:
	for a in get_tree().get_nodes_in_group("animals"):
		if a.is_predator():
			a.queue_free()
