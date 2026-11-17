extends Node
## End-to-end smoke test: boots the real game scene headless and drives the
## core loop (board/paddle/land, carry, camp, cook, map, store, dig, save).
##   godot --headless res://tests/smoke_test.tscn
## Exits 0 on success, 1 on failure.

const Tiles = preload("res://scripts/world/tiles.gd")
const Decor = preload("res://scripts/world/decor.gd")

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
	check(_has_action(acts, "switch_character"), "action bar offers switching characters")
	check(acts.size() <= 8, "action bar fits on screen (%d entries)" % acts.size())

	# Board, paddle a bit, glide, get out.
	p.try_board()
	check(p.is_paddling(), "boarded kayak from the start dock")
	check(_has_action(main.available_actions(), "board") or _has_action(main.available_actions(), "switch_character"), "action bar shows paddling actions")
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
	_unseat_all()
	p.position = w.tile_center(w.start)
	p.inventory.add("wood", 6)
	p.inventory.add("meat_raw", 2)
	p.inventory.add("potato", 1)
	main.toggle_camp()
	check(main.camp != null, "camp pitched")
	check(main.camp != null and main.camp.lit, "fire lit with wood")
	check(main.is_in_safe_zone(p.position), "player safe by the fire")
	main._camp_interact()
	check(p.inventory.count("meat_cooked") == 2, "cooked meat at the fire")
	check(p.inventory.count("potato_baked") == 1, "potatoes bake at the fire too")
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

	# --- Phase B1: chopping, farming, pickups, party, combat ---
	_unseat_all()
	var now: float = main.game_days()
	var tree_tile: Vector2i = _find_decor(w, p, func(d): return Decor.is_tree(d))
	check(tree_tile.x >= 0, "found a tree to chop")
	if tree_tile.x >= 0:
		var tree_id: int = w.get_decor(tree_tile.x, tree_tile.y)
		var wood_before: int = p.inventory.count("wood")
		p.inventory.add("wood", 0)
		p.perform_action("chop", tree_tile)
		check(w.get_decor(tree_tile.x, tree_tile.y) == Decor.STUMP, "chopped tree leaves a stump")
		check(p.inventory.count("wood") > wood_before or p.inventory.room_for("wood") == 0, "chopping gives firewood")
		main.edits.tick(now + 1.6)
		check(w.get_decor(tree_tile.x, tree_tile.y) == Decor.SAPLING, "stump regrows into a sapling")
		main.edits.tick(now + 3.2)
		check(w.get_decor(tree_tile.x, tree_tile.y) == tree_id, "sapling grows back into the tree")
	# Hold-to-repeat targeting: stand next to a tree, Space target is chop.
	var t2: Vector2i = _find_decor(w, p, func(d): return Decor.is_tree(d))
	if t2.x >= 0:
		var stand: Vector2i = t2 + Vector2i(-1, 0)
		p.position = w.tile_center(stand)
		p.facing = Vector2.RIGHT
		var tgt: Dictionary = p.space_target()
		check(not tgt.is_empty() and tgt["action"] == "chop", "facing a tree targets Chop")
	# Farming: till, plant, grow, harvest.
	var farm: Vector2i = _find_tile(w, p, func(x, y): return w.get_tile(x, y) == Tiles.GRASS and w.get_decor(x, y) == -1 and main.edits.kind_at(Vector2i(x, y)) == "")
	check(farm.x >= 0, "found open grass to farm")
	if farm.x >= 0:
		p.inventory.add("shovel", 1)
		p.inventory.add("carrot_seeds", 2)
		check(p.action_for_tile(farm) == "till", "open grass with a shovel can be tilled")
		p.perform_action("till", farm)
		check(main.edits.kind_at(farm) == "plot", "tilling makes a plot")
		check(p.action_for_tile(farm) == "plant", "plot with seeds can be planted")
		p.perform_action("plant", farm)
		check(main.edits.kind_at(farm) == "crop", "planting makes a crop")
		main.edits.tick(main.game_days() + 1.2)
		check(main.edits.is_ripe(farm), "crop ripens after growing")
		var carrots: int = p.inventory.count("carrot")
		p.perform_action("harvest", farm)
		check(p.inventory.count("carrot") > carrots, "harvest gives carrots")
	# Gradual eating.
	p.hunger = 40.0
	p.digesting = 0.0
	p.inventory.add("trail_mix", 1)
	p.eat("trail_mix")
	check(p.hunger < 45.0 and p.digesting > 0.0, "food digests gradually instead of instantly")
	await get_tree().create_timer(1.0).timeout
	check(p.hunger > 42.0, "food meter rises over time (%.1f)" % p.hunger)
	# Pickups collect by walking over them.
	var stones: int = p.inventory.count("stone")
	main.spawn_pickup("stone", 1, p.position + Vector2(10, 0))
	await get_tree().create_timer(0.8).timeout
	check(p.inventory.count("stone") > stones, "walking over a pickup collects it")
	# Party: switch characters.
	var juniper = main.party[0]
	var rowan = main.party[1]
	check(rowan != null and rowan.char_name == "Rowan", "second character exists")
	main.switch_character()
	check(main.player == rowan and rowan.controlled and not juniper.controlled, "switched to Rowan")
	main.switch_character()
	check(main.player == juniper, "switched back to Juniper")
	# Tandem kayak: both board, Juniper leaves Rowan in the kayak.
	main.kayak.position = w.tile_center(w.start_water)
	juniper.position = w.tile_center(w.start)
	rowan.position = w.tile_center(w.start)
	juniper.try_board()
	rowan._enter_kayak(main.kayak.position)
	check(main.kayak.riders.size() == 2, "both characters fit in the kayak")
	var land: Vector2 = juniper._find_spot(juniper.position, false, true)
	if juniper.can_be_at(land, false):
		juniper.exit_kayak(land)
		check(not juniper.is_paddling() and rowan.is_paddling(), "Rowan stays in the kayak when Juniper gets out")
	_unseat_all()
	# Partner explores and forages near their anchor over time.
	rowan.position = w.tile_center(w.start)
	rowan.anchor = rowan.position
	await get_tree().create_timer(2.5).timeout
	check(rowan.position.distance_to(rowan.anchor) < 32.0 * 10, "idle partner stays near their anchor")
	# Combat: melee kills a spider; a bear's hit hurts.
	juniper.position = w.tile_center(w.start)
	var Animal = load("res://scripts/entities/animal.gd")
	var spider = Animal.new()
	spider.kind = "spider"
	spider.main = main
	spider.position = juniper.position + Vector2(20, 0)
	main.entities.add_child(spider)
	await frames(2)
	juniper.inventory.add("hatchet", 1)
	juniper._attack_cd = 0.0
	juniper.facing = Vector2.RIGHT
	juniper.try_attack(false)
	check(not spider.alive, "a hatchet swing kills a spider")
	juniper.health = 100.0
	var hp_before: float = juniper.health
	juniper._invuln = 0.0
	juniper.take_damage(30.0)
	check(juniper.health < hp_before, "a bear-sized hit hurts")
	# Downed + revive.
	juniper.health = 100.0
	rowan.position = juniper.position + Vector2(24, 0)
	rowan._invuln = 0.0
	rowan.take_damage(500.0)
	check(rowan.downed, "partner can be knocked out")
	juniper.facing = Vector2.RIGHT
	var rt: Dictionary = juniper.space_target()
	check(not rt.is_empty() and rt["action"] == "revive", "Space targets Revive next to a downed partner")
	juniper.perform_action("revive", Vector2i.ZERO)
	check(not rowan.downed and rowan.health > 0.0, "partner revived")

	# --- Rare creatures, rare drops, journal ---
	var j = main.player
	j.position = w.tile_center(w.start)
	var Animal2 = load("res://scripts/entities/animal.gd")
	var fox = Animal2.new()
	fox.kind = "fox"
	fox.main = main
	fox.position = j.position + Vector2(120, 0)
	main.entities.add_child(fox)
	var coins_b: int = main.coins
	await frames(3)
	check(int(main.journal["creatures"].get("fox", 0)) >= 1, "seeing a rare fox logs it in the journal")
	check(main.coins > coins_b, "first rare sighting pays a naturalist reward")
	# Watch-only creatures can't be hurt.
	var otter = Animal2.new()
	otter.kind = "otter"
	otter.main = main
	otter.position = j.position + Vector2(-30, 0)
	main.entities.add_child(otter)
	await frames(2)
	otter.hit(5, Vector2.RIGHT)
	check(otter.alive, "otters are watch-only and can't be harmed")
	otter.queue_free()
	# The owl flies off when approached.
	var owl = Animal2.new()
	owl.kind = "owl"
	owl.main = main
	owl.position = j.position + Vector2(40, 0)
	main.entities.add_child(owl)
	await frames(3)
	check(not owl.alive, "the owl flies away when you get close")
	# The lake spirit leaves a Spirit Pearl.
	var pearls: int = j.inventory.count("spirit_pearl")
	main.day_night.set_time(23.0, false)
	var spirit = Animal2.new()
	spirit.kind = "spirit"
	spirit.main = main
	spirit.position = j.position + Vector2(30, 0)
	main.entities.add_child(spirit)
	await frames(3)
	check(j.inventory.count("spirit_pearl") > pearls or int(main.journal["finds"].get("spirit_pearl", 0)) > 0, "the Lake Spirit grants a Spirit Pearl")
	main.day_night.set_time(10.0, true)
	# Rare drop tables (forced luck).
	j.inventory.add("rabbit_foot", 1)
	check(main.luck_mult() == 2.0, "a Lucky Rabbit's Foot doubles rare chances")
	var fangs: int = 0
	for k in 60:
		main.roll_rare_drops("wolf", j.position, j)
	fangs = j.inventory.count("wolf_fang")
	check(fangs > 0, "wolves drop rare fangs (%d in 60 rolls)" % fangs)
	check(int(main.journal["finds"].get("wolf_fang", 0)) > 0, "rare finds are logged in the journal")
	# Healing food.
	j.health = 40.0
	j.hunger = 20.0
	j.digesting = 0.0
	j.poison = 0.0
	j.inventory.max_slots = 99
	j.inventory.add("golden_mushroom", 1)
	j.eat("golden_mushroom")
	check(j.health >= 70.0, "a Golden Mushroom heals")
	# Rare spawner finds a valid spot.
	var rare = main.spawner.try_spawn_rare("loon")
	check(rare == null or rare.kind == "loon", "rare spawner places a loon on water")
	# Colour variants: a golden rabbit is logged separately and drops a trophy.
	var ItemDB2 = load("res://scripts/data/item_db.gd")
	check(ItemDB2.roll_variant(1000.0) == 3, "huge luck always rolls a Golden variant")
	var normals: int = 0
	for k in 400:
		if ItemDB2.roll_variant(1.0) == 0:
			normals += 1
	check(normals > 320, "most creatures are normal colour (%d / 400)" % normals)
	var gold = Animal2.new()
	gold.kind = "rabbit"
	gold.variant = 3
	gold.main = main
	gold.position = j.position + Vector2(36, 0)
	main.entities.add_child(gold)
	var coins_v: int = main.coins
	await frames(3)
	check(int(main.journal["variants"].get("rabbit:3", 0)) >= 1, "golden rabbit logged as its own journal entry")
	check(main.coins >= coins_v + 300, "first golden sighting pays a bonus")
	check(gold.sprite.material != null, "golden variant uses the metallic shader")
	gold.hit(10, Vector2.RIGHT)
	await frames(2)
	var trophy_found := false
	for n in main.entities.get_children():
		if n.get("item_id") == "golden_pelt":
			trophy_found = true
	check(trophy_found or j.inventory.has("golden_pelt"), "golden rabbit drops a Golden Pelt")

	# Journal screen opens.
	main.open_screen(main.journal_screen)
	await frames(3)
	main.close_screen()
	check(not get_tree().paused, "journal opens and closes")

	# --- v6: review fixes, unique areas, story trail, sound ---
	_unseat_all()
	j = main.party[0]
	var rw = main.party[1]
	if main.player != j:
		main.switch_character()
	check(Sfx._stream("coin") != null, "sound effects load")
	Sfx.play("coin")
	# Idle partners can't starve or freeze to death.
	rw.health = 20.0
	rw.hunger = 0.0
	rw._update_survival(30.0)
	check(rw.health >= 15.0 and not rw.downed, "a waiting partner can't starve to death")
	rw.health = 100.0
	rw.hunger = 80.0
	# The kayak shuttle is off while someone sits in the kayak.
	main.kayak.position = w.tile_center(w.start_water) + Vector2(4000, 0)
	rw._enter_kayak(main.kayak.position)
	check(not main.kayak_far_from_store(0), "kayak shuttle is disabled while a partner is aboard")
	_unseat_all()
	main.kayak.position = w.tile_center(w.start_water)
	rw.position = w.tile_center(w.start)
	# Unique areas.
	check(main.landmarks.size() == 7, "all 7 unique areas exist in the world")
	var lh = main.landmarks["lighthouse"]
	var seen_before: int = main.exploration.discovered_count
	j.position = lh.position + Vector2(20, 20)
	lh.interact(j)
	await frames(2)
	main.close_screen()
	check(main.exploration.discovered_count > seen_before + 500, "climbing the lighthouse reveals the map")
	check(bool(main.places.get("lighthouse_climbed", false)), "lighthouse climb is remembered")
	var sp = main.landmarks["springs"]
	j.position = sp.position + Vector2(-22, -8)
	j.health = 50.0
	await get_tree().create_timer(1.0).timeout
	check(j.health > 50.5, "soaking in the hot springs heals (%.1f)" % j.health)
	check(main.is_in_safe_zone(j.position), "the hot springs are a safe, warm place")
	var ru = main.landmarks["ruins"]
	ru.interact(j)
	check(j.inventory.has("stone_tablet") and int(main.places["ruins_left"]) == 2, "diving at the ruins finds a relic")
	var fa = main.landmarks["falls"]
	var coins_f: int = main.coins
	fa.interact(j)
	check(main.coins >= coins_f + 150 and bool(main.places["falls_open"]), "the cove chest behind the falls opens")
	var ho = main.landmarks["hollow"]
	j.position = ho.position + Vector2(0, 60)
	await get_tree().create_timer(0.3).timeout
	main.ensure_elder_bear(ho.position + Vector2(0, 44))
	var bears: int = 0
	for a in get_tree().get_nodes_in_group("animals"):
		if a.kind == "elder_bear" and a.alive:
			bears += 1
			a.queue_free()
	check(bears == 1, "the Elder Bear lives at Bear's Hollow (and only one)")
	j.position = w.tile_center(w.start)
	await frames(3)
	# Story trail: drive every step through its goals.
	var QuestDB = load("res://scripts/data/quest_db.gd")
	var guard: int = 0
	while not main.quests.is_complete() and guard < 40:
		guard += 1
		var st: Dictionary = main.quests.current()
		for g in st["goals"]:
			if main.quests.is_complete() or main.quests.current() != st:
				break
			if g["kind"] == "have":
				j.inventory.add(str(g["id"]), int(g["n"]))
				main.quests.tick(1.0)
			else:
				main.quest_event(str(g["kind"]), str(g.get("id", "")), int(g["n"]))
	check(main.quests.is_complete(), "the story trail can be completed (%d/%d steps)" % [main.quests.step, QuestDB.STEPS.size()])
	check(main.paddle_level == 3, "finishing the trail awards the Founder's Paddle")
	check(main.party_has("token_light") and main.party_has("token_ruin") and main.party_has("token_falls"), "trail tokens were awarded")
	main.talk_to("paddler")
	await frames(2)
	check(main.current_screen == main.dialogue, "talking opens the dialogue panel")
	main.close_screen()
	main.open_screen(main.journal_screen)
	main.journal_screen._set_tab(0)
	await frames(2)
	main.journal_screen._set_tab(2)
	await frames(2)
	main.close_screen()
	Engine.time_scale = 1.0

	# Save and reload data round trip.
	check(main.save_game(), "game saved")
	var data: Dictionary = GameState.read_save()
	check(int(data.get("seed", -1)) == 4242, "save has seed")
	check((data.get("dug", []) as Array).size() == 1, "save has dug site")
	check((data.get("party", []) as Array).size() == 2, "save has both characters")
	check((data.get("edits", []) as Array).size() > 0, "save has world edits")
	check((data.get("journal", {}) as Dictionary).has("creatures"), "save has the creature journal")
	check((data.get("journal", {}) as Dictionary).has("variants"), "save has journal variant entries")
	check(int((data.get("quests", {}) as Dictionary).get("step", -1)) == 14, "save has trail progress")
	check((data.get("places", {}) as Dictionary).has("found"), "save has discovered places")
	_finish()


func _unseat_all() -> void:
	for c in main.party:
		if c.is_paddling():
			main.kayak.remove_rider(c)
			c.mode = 0
	main.kayak.set_state(0)


func _find_tile(w, p, pred: Callable) -> Vector2i:
	var c: Vector2i = w.tile_at_pos(p.position)
	for r in range(1, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var x: int = c.x + dx
				var y: int = c.y + dy
				if w.in_bounds(x, y) and pred.call(x, y):
					return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_decor(w, p, pred: Callable) -> Vector2i:
	return _find_tile(w, p, func(x, y): return pred.call(w.get_decor(x, y)) and w.is_walkable(x - 1, y))


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
