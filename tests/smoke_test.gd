extends Node
## End-to-end smoke test: boots the real game scene headless and drives the
## core loop (board/paddle/land, carry, camp, cook, map, store, dig, save).
##   godot --headless res://tests/smoke_test.tscn
## Exits 0 on success, 1 on failure.

const Tiles = preload("res://scripts/world/tiles.gd")

var failures: int = 0
var main


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run()


func check(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		failures += 1
		print("FAIL ", what)


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	GameState.new_game_seed = 4242
	GameState.new_game_size = 320
	GameState.pending_load = {}
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	var waited: int = 0
	while not main.ready_done and waited < 3000:
		await get_tree().process_frame
		waited += 1
	check(main.ready_done, "world generated and game ready")
	if not main.ready_done:
		_finish()
		return
	var p = main.player
	var w = main.world
	check(p.can_be_at(p.position, false), "player starts on walkable ground")
	check(main.stores.size() >= 4, "stores spawned (%d)" % main.stores.size())

	var acts: Array = main.available_actions()
	check(_has_action(acts, "board"), "action bar offers Board next to the kayak")
	check(_has_action(acts, "map"), "action bar always offers the map")

	# Board, paddle a bit, glide, get out.
	p.try_board()
	check(p.is_paddling(), "boarded kayak from the start dock")
	check(_has_action(main.available_actions(), "sprint"), "action bar offers Power stroke while paddling")
	var dir_name: String = _open_water_direction(p, w)
	Input.action_press(dir_name)
	await frames(40)
	Input.action_release(dir_name)
	var spd_after_paddle: float = p.velocity.length()
	check(spd_after_paddle > 20.0, "kayak builds up speed (%.0f px/s)" % spd_after_paddle)
	await frames(10)
	check(p.velocity.length() > 5.0 or not p.can_be_at(p.position, true), "kayak glides after paddling stops")
	check(p.can_be_at(p.position, true), "kayak stays on water while paddling")
	p.try_board()
	await frames(2)
	if not p.is_paddling():
		check(p.can_be_at(p.position, false), "landed on walkable ground")
		# Carry the kayak and put it down.
		p.try_carry()
		check(p.is_carrying(), "picked up kayak")
		p.try_carry()
		check(not p.is_carrying(), "put kayak down")
	else:
		print("note: no landing spot after paddling; skipping carry test")

	# Exploration
	check(main.exploration.discovered_count > 0, "exploration revealed tiles")

	# Camp, light and cook.
	p.position = w.tile_center(w.start)
	p.mode = 0
	p.inventory.add("wood", 6)
	p.inventory.add("meat_raw", 2)
	main.toggle_camp()
	check(main.camp != null, "camp pitched")
	check(main.camp != null and main.camp.lit, "fire lit with wood")
	check(main.is_in_safe_zone(p.position), "player safe by the fire")
	main._camp_interact()
	check(p.inventory.count("meat_cooked") == 2, "cooked meat at the fire")
	p.eat_best()
	check(p.inventory.count("meat_cooked") == 1 or p.hunger >= 98.0, "ate food")

	# Night: wolves can spawn, sleeping skips to morning.
	main.day_night.set_time(21.0, false)
	await frames(5)
	check(main.day_night.is_night(), "night set")
	main._sleep()
	await get_tree().create_timer(3.0).timeout
	check(not main.day_night.is_night(), "slept until morning")
	check(not get_tree().paused, "game unpaused after sleep")

	# Screens open and close.
	main.open_screen(main.map_screen)
	await frames(3)
	main.close_screen()
	main.open_screen(main.inventory_screen)
	await frames(3)
	main.close_screen()
	main.current_screen = main.store_screen
	get_tree().paused = true
	main.store_screen.open(0)
	await frames(3)
	main.close_screen()
	check(not get_tree().paused, "screens close cleanly")

	# Store: sell and buy.
	p.inventory.add("hide", 2)
	var coins_before: int = p.coins
	main.store_screen._sell("hide", 2)
	check(p.coins == coins_before + 16, "sold hides")
	p.coins = 1000
	main.store_screen._upgrade("hull", 1)
	check(p.hull_level == 1 and p.inventory.max_slots == 16, "hull upgrade applied")
	main.store_screen._buy("shovel", 1, 40)
	check(p.inventory.has("shovel"), "bought shovel")

	# Treasure map + dig.
	check(main.reveal_treasure_near(w.stores[0]), "treasure map reveals a site")
	var idx: int = main.revealed_treasures.keys()[0]
	var tile := Vector2i(idx % w.width, idx / w.width)
	p.position = w.tile_center(tile)
	check(main.treasure_hint_near(p.position), "dig hint near treasure")
	main.dig_at(p.position)
	check(int(main.stats["treasures"]) == 1, "dug up treasure")

	# Shoot an arrow.
	var arrows: int = p.inventory.count("arrows")
	p.try_shoot(false)
	check(p.inventory.count("arrows") == arrows - 1, "fired an arrow")
	await frames(10)

	# Save and reload data round trip.
	check(main.save_game(), "game saved")
	var data: Dictionary = GameState.read_save()
	check(int(data.get("seed", -1)) == 4242, "save has seed")
	check((data.get("dug", []) as Array).size() == 1, "save has dug site")
	_finish()


func _has_action(acts: Array, action: String) -> bool:
	for a in acts:
		if str(a[0]) == action:
			return true
	return false


## Which arrow direction from the start leads onto open water.
func _open_water_direction(p, w) -> String:
	var best: String = "move_right"
	var best_n: int = -1
	for pair in [["move_right", Vector2.RIGHT], ["move_left", Vector2.LEFT], ["move_up", Vector2.UP], ["move_down", Vector2.DOWN]]:
		var n: int = 0
		for k in range(1, 6):
			if p.can_be_at(p.position + (pair[1] as Vector2) * 32.0 * k, true):
				n += 1
		if n > best_n:
			best_n = n
			best = pair[0]
	return best


func _finish() -> void:
	print("\nSMOKE TEST: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().paused = false
	get_tree().quit(1 if failures > 0 else 0)
