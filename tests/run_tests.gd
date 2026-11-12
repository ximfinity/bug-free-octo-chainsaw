extends SceneTree
## Headless test runner.
##   godot --headless --import            (first time, imports assets)
##   godot --headless -s tests/run_tests.gd
## Exits with code 0 when everything passes, 1 otherwise.

const Tiles = preload("res://scripts/world/tiles.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const Inventory = preload("res://scripts/systems/inventory.gd")
const Exploration = preload("res://scripts/systems/exploration.gd")

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
	check(int(counts.get(Tiles.RIVER, 0)) > 0, tag + ": has rivers")
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
