extends SceneTree
## Headless test runner.
##   godot --headless --import            (first time, imports assets)
##   godot --headless -s tests/run_tests.gd
## Exits with code 0 when everything passes, 1 otherwise.

const Tiles = preload("res://scripts/world/tiles.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const Inventory = preload("res://scripts/systems/inventory.gd")
const Exploration = preload("res://scripts/systems/exploration.gd")
const WorldEdits = preload("res://scripts/systems/world_edits.gd")
const Decor = preload("res://scripts/world/decor.gd")

var failures: int = 0
var checks: int = 0


func _init() -> void:
	var t0: int = Time.get_ticks_msec()
	test_determinism()
	for s in [1, 2, 3, 42, 1234, 99999, 7777777, 31337, 2024, 555]:
		test_world(s, 320)
	test_world(8080, 448)
	test_inventory()
	test_exploration_roundtrip()
	test_world_edits()
	print("\n%d checks, %d failures (%d ms)" % [checks, failures, Time.get_ticks_msec() - t0])
	quit(1 if failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", what)


func test_determinism() -> void:
	var a = WorldGen.generate(12345, 160, 160)
	var b = WorldGen.generate(12345, 160, 160)
	check(a.tiles == b.tiles, "same seed produces identical tiles")
	check(a.stores == b.stores, "same seed produces identical stores")
	var c = WorldGen.generate(54321, 160, 160)
	check(a.tiles != c.tiles, "different seeds differ")


## Breadth-first flood over kayak-navigable tiles from `start`.
func _reachable_water(w, start: Vector2i) -> PackedByteArray:
	var seen := PackedByteArray()
	seen.resize(w.width * w.height)
	seen.fill(0)
	var queue: Array = [start]
	seen[w.idx(start.x, start.y)] = 1
	var head: int = 0
	while head < queue.size():
		var p: Vector2i = queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if not w.in_bounds(q.x, q.y):
				continue
			var i: int = w.idx(q.x, q.y)
			if seen[i] == 0 and w.is_kayak_water(q.x, q.y):
				seen[i] = 1
				queue.append(q)
	return seen


func test_world(seed_value: int, size: int) -> void:
	var t0: int = Time.get_ticks_msec()
	var w = WorldGen.generate(seed_value, size, size)
	var ms: int = Time.get_ticks_msec() - t0
	var tag: String = "seed %d" % seed_value
	check(w.is_kayak_water(w.start_water.x, w.start_water.y), tag + ": start_water is navigable")
	check(w.is_walkable(w.start.x, w.start.y), tag + ": start is walkable")
	var reach := _reachable_water(w, w.start_water)
	var water_total: int = 0
	var water_reached: int = 0
	var counts := {}
	for i in w.tiles.size():
		var t: int = w.tiles[i]
		counts[t] = int(counts.get(t, 0)) + 1
		if Tiles.kayak_ok(t):
			water_total += 1
			if reach[i] == 1:
				water_reached += 1
	check(water_total == water_reached, tag + ": all water connected (%d/%d)" % [water_reached, water_total])
	var water_frac: float = float(water_total) / float(w.tiles.size())
	check(water_frac > 0.12 and water_frac < 0.6, tag + ": water fraction sane (%.2f)" % water_frac)
	check(w.stores.size() >= 4, tag + ": at least 4 stores (%d)" % w.stores.size())
	for i in w.stores.size():
		var s: Vector2i = w.stores[i]
		var dock: Vector2i = w.store_docks[i]
		check(w.is_walkable(s.x, s.y), tag + ": store %d on walkable land" % i)
		check(reach[w.idx(dock.x, dock.y)] == 1, tag + ": store %d dock reachable by water" % i)
	check(w.treasures.size() >= 20, tag + ": at least 20 treasures (%d)" % w.treasures.size())
	for tr in w.treasures:
		var p: Vector2i = tr["pos"]
		var t: int = w.get_tile(p.x, p.y)
		check(t != Tiles.MOUNTAIN and t != Tiles.SNOW and Tiles.walk_ok(t), tag + ": treasure on walkable land")
	check(int(counts.get(Tiles.MOUNTAIN, 0)) > 0, tag + ": has mountains")
	var biome_kinds: int = 0
	for b in [Tiles.FOREST, Tiles.BIRCH, Tiles.MAPLE, Tiles.MEADOW, Tiles.GRASS, Tiles.ROCKY]:
		if int(counts.get(b, 0)) > 0:
			biome_kinds += 1
	check(biome_kinds >= 4, tag + ": varied biomes (%d kinds)" % biome_kinds)
	check(w.decor.size() == w.tiles.size(), tag + ": decor layer sized")
	var decor_count: int = 0
	for i in w.decor.size():
		if w.decor[i] != 0:
			decor_count += 1
	check(decor_count > w.tiles.size() / 20, tag + ": plenty of plant life (%d)" % decor_count)
	check(w.get_decor(w.start.x, w.start.y) == -1, tag + ": start tile clear of decor")
	for dk in w.store_docks:
		var dp: Vector2i = dk
		check(w.get_decor(dp.x, dp.y) == -1, tag + ": store dock clear of decor")
	for tr in w.treasures:
		var tp: Vector2i = tr["pos"]
		check(w.get_decor(tp.x, tp.y) == -1, tag + ": treasure tile clear of decor")
	check(int(counts.get(Tiles.RIVER, 0)) > 0, tag + ": has rivers")
	check(w.landmarks.size() == 7, tag + ": all 7 unique areas placed (%d)" % w.landmarks.size())
	var seen_ids := {}
	for lm in w.landmarks:
		var lt: Vector2i = lm["tile"]
		seen_ids[lm["id"]] = true
		check(w.in_bounds(lt.x, lt.y), tag + ": %s in bounds" % lm["id"])
		check(w.is_walkable(lt.x, lt.y) or w.is_kayak_water(lt.x, lt.y), tag + ": %s reachable" % lm["id"])
		for other in w.landmarks:
			if other["id"] != lm["id"]:
				check(Vector2(lt).distance_to(Vector2(other["tile"] as Vector2i)) >= 6.0,
					tag + ": %s and %s are apart" % [lm["id"], other["id"]])
	check(seen_ids.size() == 7, tag + ": landmark ids are unique")
	var falls: Dictionary = w.landmark("falls")
	if not falls.is_empty():
		var ft: Vector2i = falls["tile"]
		check(w.is_kayak_water(ft.x, ft.y), tag + ": Thunder Falls sits on navigable water")
	var hollow: Dictionary = w.landmark("hollow")
	if not hollow.is_empty():
		var ht: Vector2i = hollow["tile"]
		check(w.is_walkable(ht.x, ht.y), tag + ": Bear's Hollow is on walkable ground")
	print("%s size %d: %d ms, water %.0f%%, %d stores, %d treasures" % [
		tag, size, ms, water_frac * 100.0, w.stores.size(), w.treasures.size()])


func test_inventory() -> void:
	var inv = Inventory.new()
	inv.max_slots = 2
	check(inv.add("wood", 25) == 25, "wood fits in two stacks of 20")
	check(inv.slots_used() == 2, "two slots used")
	check(inv.add("hide", 1) == 0, "no room for hide")
	check(inv.add("shovel", 1) == 1, "key items ignore slots")
	check(inv.add("wood", 100) == 15, "fills remaining stack space")
	check(inv.remove("wood", 40), "remove works")
	check(inv.count("wood") == 0 and not inv.counts.has("wood"), "empty stacks erased")
	var d: Dictionary = inv.to_dict()
	var inv2 = Inventory.new()
	inv2.from_dict(d)
	check(inv2.has("shovel"), "inventory dict round trip")


func test_world_edits() -> void:
	var w = WorldGen.generate(91, 160, 160)
	var ed = WorldEdits.new()
	ed.setup(w, null, null)
	var t := Vector2i(50, 50)
	ed.set_edit(t, "stump", 1.0, Decor.OAK0)
	check(w.get_decor(t.x, t.y) == Decor.STUMP, "stump edit shows a stump")
	ed.tick(2.6)
	check(w.get_decor(t.x, t.y) == Decor.SAPLING, "stump becomes a sapling")
	ed.tick(4.2)
	check(w.get_decor(t.x, t.y) == Decor.OAK0 and ed.kind_at(t) == "", "sapling regrows into the original tree")
	var f := Vector2i(60, 60)
	ed.set_edit(f, "crop", 1.0, "pumpkin", 0)
	ed.tick(1.5)
	check(not ed.is_ripe(f), "pumpkin not ripe after half a day")
	ed.tick(3.1)
	check(ed.is_ripe(f), "pumpkin ripe after two days")
	var d := Vector2i(70, 70)
	ed.set_edit(d, "dug", 1.0)
	var arr: Array = ed.to_array()
	var ed2 = WorldEdits.new()
	ed2.setup(w, null, null)
	ed2.from_array(JSON.parse_string(JSON.stringify(arr)))
	check(ed2.kind_at(d) == "dug" and ed2.kind_at(f) == "crop", "world edits survive a JSON round trip")
	ed2.tick(2.2)
	check(ed2.kind_at(d) == "", "dug ground grasses over")


func test_exploration_roundtrip() -> void:
	var w = WorldGen.generate(77, 160, 160)
	var ex = Exploration.new()
	ex.setup(w)
	ex.reveal(Vector2i(80, 80), 10)
	ex.reveal(Vector2i(20, 30), 5)
	var s: String = ex.to_base64()
	var ex2 = Exploration.new()
	ex2.setup(w)
	ex2.from_base64(s)
	check(ex2.discovered == ex.discovered, "exploration base64 round trip")
	check(ex2.discovered_count == ex.discovered_count, "discovered count restored")
