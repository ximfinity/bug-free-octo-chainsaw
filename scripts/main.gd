extends Node2D
## Game scene root: builds the world, owns the systems and UI, routes
## interactions, handles camp/sleep/death and save/load.

const Tiles = preload("res://scripts/world/tiles.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const WorldRenderer = preload("res://scripts/world/world_renderer.gd")
const Art = preload("res://scripts/art.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const UI = preload("res://scripts/ui/ui_util.gd")
const PlayerScript = preload("res://scripts/player/player.gd")
const KayakScript = preload("res://scripts/entities/kayak.gd")
const StoreScript = preload("res://scripts/entities/store.gd")
const CampScript = preload("res://scripts/entities/camp.gd")
const PickupScript = preload("res://scripts/entities/pickup.gd")
const DayNight = preload("res://scripts/systems/day_night.gd")
const Exploration = preload("res://scripts/systems/exploration.gd")
const Spawner = preload("res://scripts/systems/animal_spawner.gd")
const HUD = preload("res://scripts/ui/hud.gd")
const MapScreen = preload("res://scripts/ui/map_screen.gd")
const InventoryScreen = preload("res://scripts/ui/inventory_screen.gd")
const StoreScreen = preload("res://scripts/ui/store_screen.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")

const STORE_REACH := 34.0
const CAMP_REACH := 28.0
const REVEAL_LAND := 7
const REVEAL_WATER := 10
const REVEAL_HILL := 11

var world
var player
var kayak
var day_night
var exploration
var spawner
var entities: Node2D
var ground: TileMapLayer
var overlay: TileMapLayer
var hint_layer: Node2D
var stores: Array = []
var store_seen: Array = []
var camp = null
## tile index -> loot id
var treasure_by_idx: Dictionary = {}
## tile index -> true
var dug: Dictionary = {}
var revealed_treasures: Dictionary = {}
var stats: Dictionary = {"kills": 0, "treasures": 0}
var respawn_point: Vector2 = Vector2.ZERO

var ui_layer: CanvasLayer
var hud
var map_screen
var inventory_screen
var store_screen
var pause_menu
var death_panel: Control
var fade: ColorRect
var current_screen = null
var ready_done: bool = false
var _flush_timer: float = 0.0
var _hint_timer: float = 0.0


func _ready() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	var loading := ColorRect.new()
	loading.color = Color(0.08, 0.16, 0.26)
	UI.place(loading, 0, 0, 1, 1, 0, 0, 0, 0)
	ui_layer.add_child(loading)
	var ll := UI.label("Charting the waterways...", 16, Color(1.0, 0.9, 0.6))
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(ll, 0, 0, 1, 1, 0, 0, 0, 0)
	loading.add_child(ll)
	await get_tree().process_frame
	await get_tree().process_frame

	var data: Dictionary = GameState.pending_load
	var seed_value: int = GameState.new_game_seed
	var world_size: int = GameState.new_game_size
	if not data.is_empty():
		seed_value = int(data.get("seed", seed_value))
		world_size = int(data.get("size", world_size))
	var t0: int = Time.get_ticks_msec()
	world = WorldGen.generate(seed_value, world_size, world_size)
	print("World %d (%dx%d) generated in %d ms: %d stores, %d treasures" % [
		seed_value, world_size, world_size, Time.get_ticks_msec() - t0, world.stores.size(), world.treasures.size()])
	_build_world()
	_build_ui()
	if data.is_empty():
		_new_game()
	else:
		_apply_save(data)
	GameState.pending_load = {}
	loading.queue_free()
	ready_done = true
	on_player_tile_changed(world.tile_at_pos(player.position))
	exploration.flush()
	if data.is_empty():
		message("Welcome to the waterways! Find the 100's of Kayaks store nearby (F to trade).")
		message("E: board/leave kayak   R: carry it   Esc: controls")
	else:
		message("Welcome back, paddler.")


func _build_world() -> void:
	ground = WorldRenderer.new()
	add_child(ground)
	ground.paint(world)
	overlay = TileMapLayer.new()
	overlay.tile_set = WorldRenderer.make_tileset()
	add_child(overlay)
	hint_layer = Node2D.new()
	hint_layer.draw.connect(_draw_hints)
	add_child(hint_layer)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	day_night = DayNight.new()
	add_child(day_night)
	day_night.night_started.connect(_on_night)
	day_night.morning.connect(_on_morning)
	for i in world.stores.size():
		var s = StoreScript.new()
		s.store_index = i
		s.tile = world.stores[i]
		s.dock_tile = world.store_docks[i]
		s.position = world.tile_center(s.tile) + Vector2(0, 6)
		entities.add_child(s)
		stores.append(s)
		store_seen.append(false)
	kayak = KayakScript.new()
	entities.add_child(kayak)
	player = PlayerScript.new()
	entities.add_child(player)
	player.setup(self, world, kayak)
	exploration = Exploration.new()
	exploration.setup(world)
	spawner = Spawner.new()
	spawner.main = self
	add_child(spawner)
	for t in world.treasures:
		var p: Vector2i = t["pos"]
		treasure_by_idx[world.idx(p.x, p.y)] = t["loot"]


func _build_ui() -> void:
	hud = HUD.new()
	ui_layer.add_child(hud)
	hud.setup(self)
	map_screen = MapScreen.new()
	map_screen.main = self
	map_screen.visible = false
	ui_layer.add_child(map_screen)
	inventory_screen = InventoryScreen.new()
	inventory_screen.main = self
	inventory_screen.visible = false
	ui_layer.add_child(inventory_screen)
	store_screen = StoreScreen.new()
	store_screen.main = self
	store_screen.visible = false
	ui_layer.add_child(store_screen)
	pause_menu = PauseMenu.new()
	pause_menu.main = self
	pause_menu.visible = false
	ui_layer.add_child(pause_menu)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.process_mode = Node.PROCESS_MODE_ALWAYS
	UI.place(fade, 0, 0, 1, 1, 0, 0, 0, 0)
	ui_layer.add_child(fade)
	_build_death_panel()


func _build_death_panel() -> void:
	var m: Array = UI.modal("You collapsed...", GameState.ui_theme)
	death_panel = m[0]
	var vb: VBoxContainer = m[1]
	vb.add_child(UI.label("Fellow paddlers found you and brought you back to camp.\nYou lost half of your supplies and a quarter of your coins.", 10))
	vb.add_child(UI.button("Wake up", _respawn))
	death_panel.visible = false
	ui_layer.add_child(death_panel)


func _new_game() -> void:
	player.position = world.tile_center(world.start)
	player.coins = 50
	player.inventory.from_dict({"bow": 1, "tent": 1, "arrows": 15, "trail_mix": 2, "wood": 3})
	kayak.position = world.tile_center(world.start_water)
	kayak.set_state(KayakScript.State.PARKED)
	respawn_point = player.position
	day_night.time_of_day = 8.0


# ------------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if not ready_done:
		return
	_flush_timer -= delta
	if _flush_timer <= 0.0:
		_flush_timer = 0.25
		exploration.flush()
		var dark: float = day_night.darkness()
		for s in stores:
			s.set_light(dark)
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = 0.2
		hint_layer.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not ready_done or current_screen != null or player.dead:
		return
	if event.is_action_pressed("pause"):
		open_screen(pause_menu)
	elif event.is_action_pressed("map"):
		open_screen(map_screen)
	elif event.is_action_pressed("inventory"):
		open_screen(inventory_screen)


func open_screen(screen) -> void:
	if current_screen != null:
		close_screen()
	current_screen = screen
	get_tree().paused = true
	screen.open()
	get_viewport().set_input_as_handled()


func close_screen() -> void:
	if current_screen != null:
		current_screen.visible = false
	current_screen = null
	get_tree().paused = false


func message(text: String) -> void:
	if hud:
		hud.message(text)


func on_player_tile_changed(t: Vector2i) -> void:
	var tt: int = world.get_tile(t.x, t.y)
	var r: int = REVEAL_LAND
	if player.is_paddling() or Tiles.is_water(tt):
		r = REVEAL_WATER
	elif tt == Tiles.HILL:
		r = REVEAL_HILL
	exploration.reveal(t, r)
	for i in stores.size():
		if not store_seen[i] and exploration.is_discovered(world.stores[i]):
			store_seen[i] = true
			if ready_done and i != 0:
				message("You spot a 100's of Kayaks store!")


# ---------------------------------------------------------- interactions
func _store_near(p: Vector2) -> int:
	for i in stores.size():
		if p.distance_to(stores[i].position) < STORE_REACH:
			return i
	return -1


func try_interact() -> void:
	var si: int = _store_near(player.position)
	if si >= 0:
		if player.is_carrying():
			message("Put the kayak down first (R).")
			return
		current_screen = store_screen
		get_tree().paused = true
		store_screen.open(si)
		get_viewport().set_input_as_handled()
		return
	if camp != null and player.position.distance_to(camp.fire_position()) < CAMP_REACH:
		_camp_interact()
		return
	message("Nothing to interact with here.")


func context_hint() -> String:
	var parts := PackedStringArray()
	var p = player
	if _store_near(p.position) >= 0:
		parts.append("F: Trade at 100's of Kayaks")
	if p.is_paddling():
		parts.append("E: Get out")
		if p.inventory.has("fishing_rod"):
			parts.append("G: Fish")
	elif p.is_carrying():
		parts.append("E: Launch   R: Put down")
	else:
		if p.near_kayak():
			parts.append("E: Board   R: Carry kayak")
		if camp != null and p.position.distance_to(camp.fire_position()) < CAMP_REACH:
			if not camp.lit:
				parts.append("F: Light fire (%d wood)   C: Pack camp" % CampScript.WOOD_TO_LIGHT)
			else:
				parts.append("F: Cook / Sleep   C: Pack camp")
		if p.inventory.has("shovel") and treasure_hint_near(p.position):
			parts.append("Hold Space: Dig")
		elif p._forest_nearby():
			parts.append("Hold Space: Chop wood")
	return "    ".join(parts)


# ------------------------------------------------------------------ camp
func toggle_camp() -> void:
	if not player.is_paddling() and not player.is_carrying():
		if camp != null and player.position.distance_to(camp.position) < CAMP_REACH + 6.0:
			camp.queue_free()
			camp = null
			player.inventory.add("tent", 1)
			message("You pack up your camp.")
			return
	if player.mode != PlayerScript.Mode.WALKING:
		message("Make camp on foot.")
		return
	var tt: int = world.tile_type_at_pos(player.position)
	if tt == Tiles.SHALLOW or tt == Tiles.MARSH:
		message("Too wet to camp here. Find dry ground.")
		return
	var moving_old: bool = camp != null
	if not moving_old and not player.inventory.has("tent"):
		message("You need a tent to make camp.")
		return
	if moving_old:
		camp.queue_free()
		camp = null
	else:
		player.inventory.remove("tent", 1)
	_spawn_camp(player.position, false)
	if player.inventory.has("wood", CampScript.WOOD_TO_LIGHT):
		player.inventory.remove("wood", CampScript.WOOD_TO_LIGHT)
		camp.set_lit(true)
		message("Camp made and the fire is lit. You're safe here tonight.")
	else:
		message("Camp made. Gather %d firewood (hold Space by trees), then F to light." % CampScript.WOOD_TO_LIGHT)
	if moving_old:
		message("(You moved your tent here.)")


func _spawn_camp(pos: Vector2, lit: bool) -> void:
	camp = CampScript.new()
	camp.position = pos
	camp.lit = lit
	entities.add_child(camp)
	respawn_point = pos


func is_in_safe_zone(pos: Vector2) -> bool:
	return camp != null and camp.lit and pos.distance_to(camp.fire_position()) < CampScript.SAFE_RADIUS


func _camp_interact() -> void:
	var inv = player.inventory
	if not camp.lit:
		if inv.has("wood", CampScript.WOOD_TO_LIGHT):
			inv.remove("wood", CampScript.WOOD_TO_LIGHT)
			camp.set_lit(true)
			message("The fire crackles to life.")
		else:
			message("You need %d firewood to light the fire." % CampScript.WOOD_TO_LIGHT)
		return
	var cooked: int = 0
	for raw in ["meat_raw", "fish_raw"]:
		var n: int = inv.count(raw)
		if n <= 0:
			continue
		var target: String = ItemDB.item(raw).get("cook", "")
		inv.remove(raw, n)
		var added: int = inv.add(target, n)
		if added < n:
			inv.add(raw, n - added)
		cooked += added
	if cooked > 0:
		message("You cook %d pieces of food over the fire." % cooked)
		return
	if day_night.is_evening():
		_sleep()
	else:
		message("The fire is warm. Sleep here once evening comes.")


func _sleep() -> void:
	get_tree().paused = true
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fade, "color:a", 1.0, 0.8)
	tw.tween_callback(func():
		var next_day: bool = day_night.time_of_day >= 12.0
		day_night.set_time(6.0, next_day)
		player.health = minf(100.0, player.health + 40.0)
		player.stamina = 100.0
		player.hunger = maxf(0.0, player.hunger - 20.0)
		player.exposure = 0.0
		spawner.clear_wolves()
		if camp != null:
			camp.set_lit(false)
		save_game())
	tw.tween_interval(0.6)
	tw.tween_property(fade, "color:a", 0.0, 0.8)
	tw.tween_callback(func():
		get_tree().paused = false
		message("You wake at dawn, rested. (Game saved)"))


func _on_night() -> void:
	message("Night falls. Stay close to a lit campfire!")


func _on_morning() -> void:
	spawner.on_morning()
	if camp != null and camp.lit:
		camp.set_lit(false)
		message("Dawn breaks. Your campfire burns down to embers.")
	else:
		message("Dawn breaks.")


# -------------------------------------------------------------- treasure
func treasure_hint_near(pos: Vector2) -> bool:
	var t: Vector2i = world.tile_at_pos(pos)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x: int = t.x + dx
			var y: int = t.y + dy
			if not world.in_bounds(x, y):
				continue
			var i: int = world.idx(x, y)
			if treasure_by_idx.has(i) and not dug.has(i):
				return true
	return false


func dig_at(pos: Vector2) -> void:
	var t: Vector2i = world.tile_at_pos(pos)
	var found: int = -1
	var best: int = 99
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = t.x + dx
			var y: int = t.y + dy
			if not world.in_bounds(x, y):
				continue
			var i: int = world.idx(x, y)
			if treasure_by_idx.has(i) and not dug.has(i) and absi(dx) + absi(dy) < best:
				best = absi(dx) + absi(dy)
				found = i
	if found < 0:
		message("Nothing here but dirt and worms.")
		return
	dug[found] = true
	var tile := Vector2i(found % world.width, found / world.width)
	overlay.set_cell(tile, 0, Tiles.HOLE_ATLAS)
	var loot: String = treasure_by_idx[found]
	var bonus: int = randi_range(5, 25)
	player.coins += bonus
	stats["treasures"] = int(stats.get("treasures", 0)) + 1
	if player.inventory.add(loot, 1) == 0:
		spawn_pickup(loot, 1, pos)
	message("Treasure! You found a %s and %d coins." % [ItemDB.item_name(loot), bonus])
	_chest_effect(world.tile_center(tile))


func _chest_effect(at: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = Art.sprite(Art.CHEST)
	s.position = at + Vector2(0, -6)
	add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "position:y", s.position.y - 14.0, 0.8)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.8).set_delay(0.6)
	tw.tween_callback(s.queue_free)


func _draw_hints() -> void:
	if player == null:
		return
	var pt: Vector2i = world.tile_at_pos(player.position)
	var hint_tex: Texture2D = Art.sprite(Art.DIG_HINT)
	var x_tex: Texture2D = Art.sprite(Art.X_MARK)
	for i in treasure_by_idx:
		if dug.has(i):
			continue
		var tile := Vector2i(i % world.width, i / world.width)
		var d: int = absi(tile.x - pt.x) + absi(tile.y - pt.y)
		var pos: Vector2 = Vector2(tile * 16)
		if revealed_treasures.has(i) and d < 30:
			hint_layer.draw_texture(x_tex, pos, Color(1, 1, 1, 0.8))
		elif d <= 5:
			hint_layer.draw_texture(hint_tex, pos, Color(1, 1, 1, clampf(1.0 - d / 6.0, 0.25, 1.0)))


func unrevealed_treasure_count() -> int:
	var n: int = 0
	for i in treasure_by_idx:
		if not dug.has(i) and not revealed_treasures.has(i):
			n += 1
	return n


func reveal_treasure_near(from_tile: Vector2i) -> bool:
	var candidates: Array = []
	for i in treasure_by_idx:
		if dug.has(i) or revealed_treasures.has(i):
			continue
		var tile := Vector2i(i % world.width, i / world.width)
		candidates.append([Vector2(tile).distance_to(Vector2(from_tile)), i])
	if candidates.is_empty():
		message("The shopkeeper has no maps left that you haven't seen.")
		return false
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var pick: Array = candidates[randi_range(0, mini(2, candidates.size() - 1))]
	var idx: int = pick[1]
	revealed_treasures[idx] = true
	exploration.reveal(Vector2i(idx % world.width, idx / world.width), 4)
	return true


# ------------------------------------------------------------- kayak help
func kayak_far_from_store(i: int) -> bool:
	if player.is_paddling() or player.is_carrying():
		return false
	var dock: Vector2 = world.tile_center(world.store_docks[i])
	return kayak.position.distance_to(dock) > 10.0 * 16.0


func retrieve_kayak_to_store(i: int) -> void:
	player.place_kayak_near(world.tile_center(world.store_docks[i]))


func spawn_pickup(id: String, amount: int, pos: Vector2) -> void:
	var p = PickupScript.new()
	p.item_id = id
	p.amount = amount
	p.main = self
	p.position = pos
	entities.add_child(p)


# ------------------------------------------------------------ death/respawn
func player_died() -> void:
	get_tree().paused = true
	death_panel.visible = true


func _respawn() -> void:
	death_panel.visible = false
	var inv = player.inventory
	var d: Dictionary = inv.to_dict()
	for id in d:
		if not ItemDB.is_key(id):
			d[id] = int(d[id]) / 2
	inv.from_dict(d)
	player.coins = int(player.coins * 0.75)
	player.health = 60.0
	player.hunger = maxf(player.hunger, 50.0)
	player.stamina = 100.0
	player.exposure = 0.0
	player.velocity = Vector2.ZERO
	player.mode = PlayerScript.Mode.WALKING
	player.dead = false
	var pos: Vector2 = respawn_point
	if camp != null:
		pos = camp.position + Vector2(0, 14)
	if not player.can_be_at(pos, false):
		pos = player._find_spot(pos, false, false)
	if not player.can_be_at(pos, false):
		pos = world.tile_center(world.start)
	player.position = pos
	player.place_kayak_near(pos)
	if day_night.is_night():
		day_night.set_time(7.0, day_night.time_of_day >= 12.0)
	spawner.clear_wolves()
	get_tree().paused = false


# ------------------------------------------------------------- save/load
func save_game() -> bool:
	var d := {
		"seed": world.seed_value,
		"size": world.width,
		"time": day_night.time_of_day,
		"day": day_night.day,
		"player": player.to_dict(),
		"kayak": {"pos": [kayak.position.x, kayak.position.y], "rot": kayak.rotation, "state": kayak.state},
		"camp": null,
		"dug": dug.keys(),
		"revealed": revealed_treasures.keys(),
		"discovered": exploration.to_base64(),
		"respawn": [respawn_point.x, respawn_point.y],
		"stats": stats,
	}
	if camp != null:
		d["camp"] = {"pos": [camp.position.x, camp.position.y], "lit": camp.lit}
	return GameState.write_save(d)


func _apply_save(d: Dictionary) -> void:
	day_night.time_of_day = float(d.get("time", 8.0))
	day_night.day = int(d.get("day", 1))
	day_night._ready()
	player.from_dict(d.get("player", {}))
	var kd: Dictionary = d.get("kayak", {})
	var kp: Array = kd.get("pos", [player.position.x, player.position.y])
	kayak.position = Vector2(float(kp[0]), float(kp[1]))
	kayak.rotation = float(kd.get("rot", 0.0))
	kayak.set_state(int(kd.get("state", KayakScript.State.PARKED)))
	var cd = d.get("camp", null)
	if cd is Dictionary:
		var cp: Array = cd.get("pos", [0, 0])
		_spawn_camp(Vector2(float(cp[0]), float(cp[1])), bool(cd.get("lit", false)))
	for v in d.get("dug", []):
		var idx: int = int(v)
		dug[idx] = true
		overlay.set_cell(Vector2i(idx % world.width, idx / world.width), 0, Tiles.HOLE_ATLAS)
	for v in d.get("revealed", []):
		revealed_treasures[int(v)] = true
	exploration.from_base64(str(d.get("discovered", "")))
	var rp: Array = d.get("respawn", [player.position.x, player.position.y])
	respawn_point = Vector2(float(rp[0]), float(rp[1]))
	var st = d.get("stats", {})
	if st is Dictionary:
		stats = st
	for i in stores.size():
		store_seen[i] = exploration.is_discovered(world.stores[i])
