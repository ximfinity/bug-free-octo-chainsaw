extends Node
## Renders a set of style-review screenshots with the real renderer.
##   xvfb-run -a godot --rendering-driver opengl3 res://tests/screenshot.tscn
## Images go to $SHOT_DIR (default: <project>/screenshots).

const Tiles = preload("res://scripts/world/tiles.gd")
const Decor = preload("res://scripts/world/decor.gd")

var main
var out_dir: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run()


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path: String = out_dir.path_join(name + ".png")
	img.save_png(path)
	print("saved ", path)


## Finds a tile matching pred(x, y) nearest to the world start.
func find_tile(pred: Callable) -> Vector2i:
	var w = main.world
	var best := Vector2i(-1, -1)
	var best_d: float = 1e20
	for y in range(4, w.height - 4, 2):
		for x in range(4, w.width - 4, 2):
			if pred.call(x, y):
				var d: float = Vector2(x - w.start.x, y - w.start.y).length()
				if d < best_d:
					best_d = d
					best = Vector2i(x, y)
	return best


func interior(x: int, y: int, t: int, r: int) -> bool:
	var w = main.world
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if w.get_tile(x + dx, y + dy) != t:
				return false
	return true


func _unseat_all() -> void:
	for c in main.party:
		if c.is_paddling():
			main.kayak.remove_rider(c)
			c.mode = 0
	main.kayak.set_state(0)


func walk_to(tile: Vector2i, face: Vector2 = Vector2.DOWN) -> void:
	var p = main.player
	_unseat_all()
	p.position = main.world.tile_center(tile)
	p.facing = face
	var other = main.partner_of(p)
	other.position = main._beside(p.position)
	other.anchor = other.position
	other.facing = Vector2.LEFT
	main.camera.position = p.position
	main.camera.reset_smoothing()


func paddle_at(tile: Vector2i, heading: float, both: bool = true) -> void:
	var p = main.player
	_unseat_all()
	main.kayak.position = main.world.tile_center(tile)
	main.kayak.heading = heading
	p.position = main.world.tile_center(tile)
	p._enter_kayak(main.world.tile_center(tile))
	p.heading = heading
	if both:
		main.partner_of(p)._enter_kayak(main.kayak.position)
	main.camera.position = p.position
	main.camera.reset_smoothing()


func _run() -> void:
	GameState.new_game_seed = 4242
	GameState.new_game_size = 320
	GameState.pending_load = {}
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	while not main.ready_done:
		await get_tree().process_frame
	var w = main.world
	var p = main.player
	p.inventory.add("shovel", 1)
	p.inventory.add("fishing_rod", 1)
	await frames(20)

	# 1. Paddling on open water near the start, mid-morning.
	main.day_night.set_time(10.0, false)
	var near_shore: Vector2i = find_tile(func(x, y): return w.get_tile(x, y) == Tiles.SHALLOW and interior(x, y, Tiles.SHALLOW, 1) and w.get_tile(x + 3, y) != Tiles.SHALLOW)
	if near_shore.x < 0:
		near_shore = w.start_water
	paddle_at(near_shore, PI * 0.25)
	Input.action_press("move_right")
	Input.action_press("move_down")
	await frames(45)
	Input.action_release("move_right")
	Input.action_release("move_down")
	await frames(5)
	await shot("01_paddling_day")

	# 2. Start area with the store (beach, kayak, action bar).
	walk_to(w.start, Vector2.RIGHT)
	await frames(30)
	await shot("02_start_and_store")

	# 3. Pine forest.
	var pine: Vector2i = find_tile(func(x, y): return interior(x, y, Tiles.FOREST, 3))
	if pine.x >= 0:
		walk_to(pine)
		await frames(20)
		await shot("03_pine_forest")

	# 4. Maple / birch forest.
	var maple: Vector2i = find_tile(func(x, y): return interior(x, y, Tiles.MAPLE, 2))
	if maple.x < 0:
		maple = find_tile(func(x, y): return interior(x, y, Tiles.BIRCH, 2))
	if maple.x >= 0:
		walk_to(maple)
		await frames(20)
		await shot("04_maple_birch")

	# 5. Meadow.
	var meadow: Vector2i = find_tile(func(x, y): return interior(x, y, Tiles.MEADOW, 2))
	if meadow.x >= 0:
		walk_to(meadow)
		await frames(20)
		await shot("05_meadow")

	# 6. Lilies / marsh.
	var lily: Vector2i = find_tile(func(x, y): return w.get_decor(x, y) == Decor.LILYFLOWER)
	if lily.x < 0:
		lily = find_tile(func(x, y): return w.get_tile(x, y) == Tiles.MARSH)
	if lily.x >= 0 and w.is_kayak_water(lily.x, lily.y):
		paddle_at(lily, PI)
		await frames(20)
		await shot("06_lilies_marsh")

	# 7. River with current.
	var river: Vector2i = find_tile(func(x, y): return interior(x, y, Tiles.RIVER, 1))
	if river.x >= 0:
		paddle_at(river, 0.0)
		await frames(30)
		await shot("07_river")

	# 8. Dusk on the water.
	paddle_at(near_shore, PI * 1.25)
	main.day_night.set_time(19.6, false)
	await frames(20)
	await shot("08_dusk")

	# 9. Night camp.
	walk_to(w.start, Vector2.LEFT)
	p.inventory.add("wood", 3)
	main.toggle_camp()
	main.day_night.set_time(22.5, false)
	p.position += Vector2(0, 40)
	main.camera.position = p.position
	main.camera.reset_smoothing()
	await frames(30)
	await shot("09_night_camp")

	# 10. Treasure shimmer.
	main.day_night.set_time(11.0, true)
	var tr: Vector2i = w.treasures[0]["pos"]
	walk_to(tr + Vector2i(2, 1), Vector2.LEFT)
	await frames(40)
	await shot("10_treasure_shimmer")

	# 10b. Mountains.
	var mtn: Vector2i = find_tile(func(x, y): return w.get_tile(x, y) == Tiles.MOUNTAIN and w.is_walkable(x + 4, y + 3))
	if mtn.x >= 0:
		walk_to(mtn + Vector2i(4, 3), Vector2.UP)
		await frames(20)
		await shot("10b_mountains")

	# 13. Chopping, farming and stumps.
	var grove: Vector2i = find_tile(func(x, y): return interior(x, y, Tiles.BIRCH, 2) or interior(x, y, Tiles.MAPLE, 2))
	if grove.x >= 0:
		walk_to(grove, Vector2.RIGHT)
		var now: float = main.game_days()
		for dy in range(-2, 3):
			for dx in range(-3, 4):
				var t: Vector2i = grove + Vector2i(dx, dy)
				var d: int = w.get_decor(t.x, t.y)
				if Decor.is_tree(d) and (dx + dy) % 2 == 0:
					main.edits.set_edit(t, "stump", now, d)
		for k in 4:
			var pt: Vector2i = grove + Vector2i(-3 + k, 3)
			main.edits.set_edit(pt, "crop", now - 0.6 * k, ["carrot", "potato", "pumpkin", "carrot"][k], k)
		main.edits.set_edit(grove + Vector2i(1, 3), "plot", now)
		main.edits.set_edit(grove + Vector2i(2, 3), "dug", now)
		await frames(20)
		await shot("13_clearing_and_farm")

	# 14. Danger: a bear and spiders nearby.
	var forest: Vector2i = find_tile(func(x, y): return interior(x, y, Tiles.BIRCH, 1))
	if forest.x < 0:
		forest = grove
	if forest.x >= 0:
		walk_to(forest, Vector2.RIGHT)
		for kind in ["bear", "spider", "spider", "wildcat"]:
			var a = load("res://scripts/entities/animal.gd").new()
			a.kind = kind
			a.main = main
			a.position = p.position + Vector2(randf_range(90, 220), randf_range(-90, 90))
			main.entities.add_child(a)
		await frames(40)
		await shot("14_danger")

	# 15. Two-person kayak.
	paddle_at(near_shore, PI * 0.15, true)
	Input.action_press("move_right")
	await frames(30)
	Input.action_release("move_right")
	await frames(5)
	await shot("15_tandem_kayak")

	# 16. Rare creatures lineup by the start (daylight; spirit shown at dusk tint).
	main.day_night.set_time(9.0, true)
	walk_to(w.start, Vector2.RIGHT)
	var Animal3 = load("res://scripts/entities/animal.gd")
	var kinds: Array = ["fox", "white_stag", "moose", "elder_bear", "owl"]
	var k_i: int = 0
	for kind in kinds:
		var a3 = Animal3.new()
		a3.kind = kind
		a3.main = main
		var spot: Vector2 = p.position + Vector2(-260 + k_i * 120, 120)
		for tries in 12:
			if a3._can_stand_kind(spot):
				break
			spot += Vector2(0, -40)
		a3.position = spot
		main.entities.add_child(a3)
		k_i += 1
	for wk in ["loon", "otter"]:
		main.spawner.try_spawn_rare(wk)
	main.spawn_pickup("white_antler", 1, p.position + Vector2(60, -30))
	main.spawn_pickup("golden_trout", 1, p.position + Vector2(90, -30))
	await frames(30)
	await shot("16_rare_creatures")
	for kind in ["fox", "otter", "loon", "owl", "white_stag", "moose", "elder_bear"]:
		main.journal["creatures"][kind] = 1
	for id in ["rabbit_foot", "antler", "wolf_fang", "amber", "golden_trout", "white_antler", "gem"]:
		main.journal["finds"][id] = 1
	main.open_screen(main.journal_screen)
	await frames(10)
	await shot("17_journal")
	main.close_screen()

	# 11. Map screen and store screen.
	main.open_screen(main.map_screen)
	await frames(10)
	await shot("11_map")
	main.close_screen()
	main.current_screen = main.store_screen
	get_tree().paused = true
	main.store_screen.open(0)
	main.store_screen.tabs.current_tab = 2
	await frames(10)
	await shot("12_store")
	main.close_screen()
	print("SCREENSHOTS DONE")
	get_tree().quit(0)
