extends Node2D
## Game scene root: builds the world, owns the systems and UI, routes
## interactions, handles camp/sleep/death and save/load.

const Tiles = preload("res://scripts/world/tiles.gd")
const WorldGen = preload("res://scripts/world/world_gen.gd")
const TerrainRenderer = preload("res://scripts/world/terrain_renderer.gd")
const DecorLayer = preload("res://scripts/world/decor_layer.gd")
const Decor = preload("res://scripts/world/decor.gd")
const FX = preload("res://scripts/fx/fx.gd")
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
const WorldEdits = preload("res://scripts/systems/world_edits.gd")
const HUD = preload("res://scripts/ui/hud.gd")
const MapScreen = preload("res://scripts/ui/map_screen.gd")
const InventoryScreen = preload("res://scripts/ui/inventory_screen.gd")
const StoreScreen = preload("res://scripts/ui/store_screen.gd")
const PauseMenu = preload("res://scripts/ui/pause_menu.gd")
const JournalScreen = preload("res://scripts/ui/journal_screen.gd")
const RippleFX = preload("res://scripts/fx/ripple.gd")

const STORE_REACH := 84.0
const CAMP_REACH := 60.0
const SPARKLE_RANGE := 7
const SPARKLE_POOL := 6
const REVEAL_LAND := 7
const REVEAL_WATER := 10
const REVEAL_HILL := 11

var world
## The character you're controlling right now (party[active_index]).
var player
var party: Array = []
var active_index: int = 0
var kayak
## Shared party resources.
var coins: int = 50
var hull_level: int = 0
var paddle_level: int = 0
var edits
var camera: Camera2D
var day_night
var exploration
var spawner
var entities: Node2D
var ground
var flat_decor
var tall_decor
var hint_layer: Node2D
var sparkles: Array = []
var stores: Array = []
var store_seen: Array = []
var camp = null
## tile index -> loot id
var treasure_by_idx: Dictionary = {}
## tile index -> true
var dug: Dictionary = {}
var revealed_treasures: Dictionary = {}
var stats: Dictionary = {"kills": 0, "treasures": 0}
## Creature Journal: kind -> times sighted; rare item id -> times found.
var journal: Dictionary = {"creatures": {}, "finds": {}, "variants": {}}
var respawn_point: Vector2 = Vector2.ZERO

var ui_layer: CanvasLayer
var hud
var map_screen
var inventory_screen
var store_screen
var pause_menu
var journal_screen
var death_panel: Control
var fade: ColorRect
var current_screen = null
var ready_done: bool = false
var _flush_timer: float = 0.0
var _hint_timer: float = 0.0
var _edit_timer: float = 0.0
var _shake: float = 0.0
var _partner_msg_cd: float = 0.0
var vignette: ColorRect
var target_cursor: Node2D


func _ready() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	var loading := ColorRect.new()
	loading.color = Color(0.17, 0.53, 0.72)
	UI.place(loading, 0, 0, 1, 1, 0, 0, 0, 0)
	ui_layer.add_child(loading)
	var ll := UI.label("Charting the waterways...", 18, Color(1.0, 0.9, 0.6))
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
		message("Welcome to the waterways! The 100's of Kayaks store is right nearby.")
		message("Your available actions are always shown at the bottom of the screen.")
	else:
		message("Welcome back, paddler.")


func _build_world() -> void:
	ground = TerrainRenderer.new()
	add_child(ground)
	ground.build(world)
	hint_layer = Node2D.new()
	hint_layer.z_index = -15
	hint_layer.draw.connect(_draw_hints)
	add_child(hint_layer)
	var decor_set: TileSet = DecorLayer.make_tileset()
	flat_decor = DecorLayer.new()
	add_child(flat_decor)
	flat_decor.paint(world, false, decor_set)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	tall_decor = DecorLayer.new()
	entities.add_child(tall_decor)
	tall_decor.paint(world, true, decor_set)
	for i in SPARKLE_POOL:
		var sp: CPUParticles2D = FX.make_sparkles()
		sp.emitting = false
		sp.z_index = 5
		add_child(sp)
		sparkles.append(sp)
	day_night = DayNight.new()
	add_child(day_night)
	day_night.night_started.connect(_on_night)
	day_night.morning.connect(_on_morning)
	for i in world.stores.size():
		var s = StoreScript.new()
		s.store_index = i
		s.tile = world.stores[i]
		s.dock_tile = world.store_docks[i]
		s.position = world.tile_center(s.tile) + Vector2(0, 12)
		entities.add_child(s)
		stores.append(s)
		store_seen.append(false)
	kayak = KayakScript.new()
	entities.add_child(kayak)
	for i in 2:
		var c = PlayerScript.new()
		c.who = i
		entities.add_child(c)
		c.setup(self, world, kayak, i)
		c.controlled = i == 0
		party.append(c)
	player = party[0]
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	var px: Vector2 = world.pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(px.x)
	camera.limit_bottom = int(px.y)
	add_child(camera)
	camera.make_current()
	edits = WorldEdits.new()
	edits.setup(world, flat_decor, tall_decor)
	target_cursor = Node2D.new()
	target_cursor.z_index = -9
	target_cursor.draw.connect(_draw_cursor)
	add_child(target_cursor)
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
	journal_screen = JournalScreen.new()
	journal_screen.main = self
	journal_screen.visible = false
	ui_layer.add_child(journal_screen)
	pause_menu = PauseMenu.new()
	pause_menu.main = self
	pause_menu.visible = false
	ui_layer.add_child(pause_menu)
	vignette = ColorRect.new()
	vignette.color = Color(0.85, 0.1, 0.1, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(vignette, 0, 0, 1, 1, 0, 0, 0, 0)
	ui_layer.add_child(vignette)
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
	vb.add_child(UI.label("Juniper and Rowan were both knocked out.\nFellow paddlers brought you back to camp. You lost half of your\nsupplies and a quarter of your coins.", 10))
	vb.add_child(UI.button("Wake up", _respawn))
	death_panel.visible = false
	ui_layer.add_child(death_panel)


func _new_game() -> void:
	coins = 50
	party[0].position = world.tile_center(world.start)
	party[0].inventory.from_dict({"bow": 1, "tent": 1, "arrows": 15, "trail_mix": 2, "wood": 3})
	party[1].position = _beside(party[0].position)
	party[1].inventory.from_dict({"shovel": 1, "carrot_seeds": 4, "trail_mix": 2})
	for c in party:
		c.anchor = c.position
	kayak.position = world.tile_center(world.start_water)
	kayak.set_state(KayakScript.State.PARKED)
	respawn_point = player.position
	day_night.time_of_day = 8.0
	camera.position = player.position
	camera.reset_smoothing()


## A walkable spot next to `p` for a second character.
func _beside(p: Vector2) -> Vector2:
	for off in [Vector2(-28, 10), Vector2(28, 10), Vector2(0, 30), Vector2(0, -30), Vector2(-40, 0), Vector2(40, 0)]:
		if party[0].can_be_at(p + off, false):
			return p + off
	return p


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
		ground.set_daylight(clampf(1.0 - dark * 1.4, 0.0, 1.0))
		_update_sparkles()
	_hint_timer -= delta
	if _hint_timer <= 0.0:
		_hint_timer = 0.05
		hint_layer.queue_redraw()
	_edit_timer -= delta
	if _edit_timer <= 0.0:
		_edit_timer = 2.0
		edits.tick(game_days())
	_partner_msg_cd -= delta
	# Camera follows the active character (or the kayak they ride in).
	camera.position = player.position
	if _shake > 0.0:
		_shake -= delta
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 6.0 * (_shake / 0.3)
	else:
		camera.offset = Vector2.ZERO
	if vignette.color.a > 0.0:
		vignette.color.a = maxf(0.0, vignette.color.a - delta * 0.8)
	target_cursor.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not ready_done or current_screen != null or player.dead:
		return
	if event.is_action_pressed("pause"):
		open_screen(pause_menu)
	elif event.is_action_pressed("map"):
		open_screen(map_screen)
	elif event.is_action_pressed("inventory"):
		open_screen(inventory_screen)
	elif event.is_action_pressed("switch_character"):
		switch_character()
	elif event.is_action_pressed("journal"):
		open_screen(journal_screen)


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


func message(text: String, color: Color = Color.WHITE) -> void:
	if hud:
		hud.message(text, color)


# ------------------------------------------------------------ rare finds
## Doubles rare chances while anyone carries a Lucky Rabbit's Foot.
func luck_mult() -> float:
	for c in party:
		if c.inventory.has("rabbit_foot"):
			return 2.0
	return 1.0


## Rolls the rare drop table for a source (animal kind or activity).
func roll_rare_drops(source: String, at: Vector2, who = null) -> void:
	var table: Array = ItemDB.RARE_DROPS.get(source, [])
	var luck: float = luck_mult()
	for entry in table:
		if randf() < float(entry[1]) * luck:
			var id: String = entry[0]
			if who != null:
				who.gain(id, 1, at)
				on_rare_item(who, id)
			else:
				spawn_pickup(id, 1, at + Vector2(randf_range(-10, 10), randf_range(-6, 6)))


## Announces a rare item and logs it in the journal.
func on_rare_item(who, id: String) -> void:
	var r: int = ItemDB.rarity(id)
	journal_add_find(id)
	if r >= 1:
		var tag: String = ItemDB.RARITY_NAMES[r].to_upper()
		var name_txt: String = ItemDB.item_name(id)
		var whose: String = "" if (who == null or who.controlled) else " (%s)" % who.char_name
		message("%s find: %s!%s" % [tag, name_txt, whose], ItemDB.rarity_color(id))
		if r >= 2 and who != null:
			_rare_burst(who.position, ItemDB.rarity_color(id))
	elif who != null and who.controlled:
		message("+1 %s" % ItemDB.item_name(id))


func journal_add_find(id: String) -> void:
	var finds: Dictionary = journal["finds"]
	finds[id] = int(finds.get(id, 0)) + 1


func _rare_burst(at: Vector2, color: Color) -> void:
	var sp: CPUParticles2D = FX.make_sparkles()
	sp.position = at + Vector2(0, -20)
	sp.color = color
	sp.one_shot = true
	sp.explosiveness = 0.8
	sp.amount = 16
	sp.z_index = 8
	sp.emitting = true
	add_child(sp)
	get_tree().create_timer(2.0, false).timeout.connect(sp.queue_free)


func ripple_at(at: Vector2) -> void:
	FX.ripple(entities, at, 22.0, 1.0)


## Called the first time the player sees each individual animal.
func on_creature_sighted(a) -> void:
	var creatures: Dictionary = journal["creatures"]
	var first: bool = not creatures.has(a.kind)
	creatures[a.kind] = int(creatures.get(a.kind, 0)) + 1
	# Each colour variant is logged separately for journal completion.
	var variants: Dictionary = journal["variants"]
	var key: String = "%s:%d" % [a.kind, maxi(a.variant, 0)]
	var first_variant: bool = not variants.has(key)
	variants[key] = int(variants.get(key, 0)) + 1
	if a.variant > 0:
		var vcol: Color = ItemDB.VARIANT_COLORS[a.variant]
		if first_variant:
			var bonus: int = ItemDB.VARIANT_REWARD[a.variant]
			coins += bonus
			message("%s spotted! New journal entry (+%d coins)." % [a.display_name(), bonus], vcol)
		else:
			message("A %s!" % a.display_name(), vcol)
		_rare_burst(a.position, vcol)
	if not a.is_rare():
		return
	var col: Color = ItemDB.RARITY_COLORS[3 if bool(a.data.get("boss", false)) or a.kind == "spirit" or a.kind == "white_stag" else 2]
	if first:
		var reward: int = int(a.data.get("reward", 50))
		coins += reward
		message("New journal entry: %s! The naturalists at 100's of Kayaks send %d coins." % [a.display_name(), reward], col)
		_rare_burst(a.position, col)
	else:
		message("You spot a %s!" % a.display_name(), col)


func on_player_tile_changed(t: Vector2i) -> void:
	on_char_tile_changed(player, t)


## Both characters reveal the map around them.
func on_char_tile_changed(c, t: Vector2i) -> void:
	var tt: int = world.get_tile(t.x, t.y)
	var r: int = REVEAL_LAND
	if c.is_paddling() or Tiles.is_water(tt):
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


## Every action the player can take right now, as [input_action, label].
## Drives the on-screen action bar.
func available_actions() -> Array:
	var a: Array = []
	var p = player
	if p == null or p.dead:
		return a
	var near_store: bool = _store_near(p.position) >= 0
	var near_camp: bool = camp != null and p.position.distance_to(camp.fire_position()) < CAMP_REACH
	var can_shoot: bool = p.inventory.has("bow") and p.inventory.has("arrows")
	if p.is_paddling():
		a.append(["move", "Paddle"])
		a.append(["sprint", "Power stroke"])
		if p.can_land():
			a.append(["board", "Get out"])
		if p.fish_state == 1:
			a.append(["fish", "Reel in"])
		elif p.fish_state == 2:
			a.append(["fish", "Hook it!"])
		elif p.inventory.has("fishing_rod") and Tiles.is_water(world.tile_type_at_pos(p.position)):
			a.append(["fish", "Fish"])
		if can_shoot:
			a.append(["shoot", "Shoot"])
	elif p.is_carrying():
		a.append(["move", "Walk"])
		if p.can_launch():
			a.append(["board", "Launch"])
		a.append(["carry", "Put down"])
	else:
		a.append(["move", "Walk"])
		a.append(["sprint", "Run"])
		if p.near_kayak():
			a.append(["board", "Board" if kayak.riders.is_empty() else "Join %s" % kayak.riders[0].char_name])
			if kayak.riders.is_empty():
				a.append(["carry", "Carry kayak"])
		var tgt: Dictionary = p.space_target()
		if not tgt.is_empty():
			a.append(["use_tool", "%s (hold)" % PlayerScript.ACTION_LABEL.get(tgt["action"], "Use")])
		a.append(["attack", "Attack"])
		if near_camp:
			if not camp.lit:
				a.append(["interact", "Light fire"])
			elif p.inventory.has("meat_raw") or p.inventory.has("fish_raw"):
				a.append(["interact", "Cook"])
			elif day_night.is_evening():
				a.append(["interact", "Sleep"])
			a.append(["camp", "Pack camp"])
		elif p.inventory.has("tent") or camp != null:
			var tt: int = world.tile_type_at_pos(p.position)
			if tt != Tiles.SHALLOW and tt != Tiles.MARSH:
				a.append(["camp", "Make camp" if camp == null else "Move camp"])
		if can_shoot:
			a.append(["shoot", "Shoot"])
	if near_store and not p.is_carrying():
		a.append(["interact", "Trade"])
	var other = partner_of(p)
	if other != null:
		a.append(["switch_character", "Play as %s" % other.char_name])
		if not other.downed and not other.is_paddling() and not p.is_paddling() \
				and other.position.distance_to(p.position) > 96.0:
			a.append(["call_partner", "Call %s" % other.char_name])
	if p.hunger < 90.0:
		for id in ItemDB.EAT_ORDER:
			if p.inventory.has(id):
				a.append(["eat", "Eat"])
				break
	a.append(["map", "Map"])
	a.append(["inventory", "Pack"])
	a.append(["journal", "Journal"])
	return a


# ------------------------------------------------------------------ camp
func toggle_camp() -> void:
	if not player.is_paddling() and not player.is_carrying():
		if camp != null and player.position.distance_to(camp.position) < CAMP_REACH + 12.0:
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
	if camp != null and camp.lit and pos.distance_to(camp.fire_position()) < CampScript.SAFE_RADIUS:
		return true
	# The store's lit porch is a safe haven too.
	for st in stores:
		if pos.distance_to(st.position) < 110.0:
			return true
	return false


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
		for c in party:
			var near_fire: bool = camp != null and c.position.distance_to(camp.fire_position()) < CampScript.SAFE_RADIUS * 1.5
			c.health = minf(100.0, c.health + (40.0 if near_fire else 10.0))
			c.stamina = 100.0
			c.hunger = maxf(0.0, c.hunger - 20.0)
			c.exposure = 0.0
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


func treasure_at(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var i: int = world.idx(t.x + dx, t.y + dy)
			if world.in_bounds(t.x + dx, t.y + dy) and treasure_by_idx.has(i) and not dug.has(i):
				return true
	return false


func dig_at(pos: Vector2, digger = null) -> void:
	if digger == null:
		digger = player
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
	edits.set_edit(tile, "dug", game_days())
	hint_layer.queue_redraw()
	FX.splash(entities, world.tile_center(tile), 6)
	var loot: String = treasure_by_idx[found]
	var bonus: int = randi_range(5, 25)
	coins += bonus
	stats["treasures"] = int(stats.get("treasures", 0)) + 1
	if digger.inventory.add(loot, 1) == 0:
		spawn_pickup(loot, 1, pos)
	journal_add_find(loot)
	message("Treasure! You found a %s and %d coins." % [ItemDB.item_name(loot), bonus], ItemDB.rarity_color(loot))
	_chest_effect(world.tile_center(tile))


func _chest_effect(at: Vector2) -> void:
	var s := Sprite2D.new()
	s.texture = Art.prop(Art.CHEST)
	s.position = at + Vector2(0, -12)
	s.z_index = 10
	add_child(s)
	var tw := s.create_tween()
	tw.tween_property(s, "position:y", s.position.y - 28.0, 0.8)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.8).set_delay(0.6)
	tw.tween_callback(s.queue_free)


func _draw_hints() -> void:
	if player == null:
		return
	var pt: Vector2i = world.tile_at_pos(player.position)
	var x_tex: Texture2D = Art.prop(Art.X_MARK)
	var pulse: float = 0.75 + 0.25 * sin(Time.get_ticks_msec() / 250.0)
	# Soft golden glow on the ground under nearby buried treasure.
	for sp in sparkles:
		if sp.emitting:
			var a: float = sp.modulate.a * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 300.0))
			var c: Vector2 = sp.position + Vector2(0, 6)
			hint_layer.draw_circle(c, 22.0, Color(1.0, 0.8, 0.25, 0.18 * a))
			hint_layer.draw_circle(c, 14.0, Color(1.0, 0.87, 0.35, 0.3 * a))
			hint_layer.draw_circle(c, 7.0, Color(1.0, 0.97, 0.7, 0.45 * a))
	for i in revealed_treasures:
		if dug.has(i):
			continue
		var tile := Vector2i(i % world.width, i / world.width)
		if absi(tile.x - pt.x) < 30 and absi(tile.y - pt.y) < 20:
			hint_layer.draw_texture(x_tex, Vector2(tile * 32) - Vector2(16, 16), Color(1, 1, 1, pulse))


## Points the sparkle emitters at the nearest undug treasure sites.
func _update_sparkles() -> void:
	if player == null:
		return
	var pt: Vector2i = world.tile_at_pos(player.position)
	var near: Array = []
	for i in treasure_by_idx:
		if dug.has(i):
			continue
		var tile := Vector2i(i % world.width, i / world.width)
		var d: int = maxi(absi(tile.x - pt.x), absi(tile.y - pt.y))
		if d <= SPARKLE_RANGE or (revealed_treasures.has(i) and d <= 20):
			near.append([d, tile])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in sparkles.size():
		var sp: CPUParticles2D = sparkles[k]
		if k < near.size():
			var tile: Vector2i = near[k][1]
			var d: int = near[k][0]
			sp.position = world.tile_center(tile) + Vector2(0, -4)
			sp.emitting = true
			sp.modulate = Color(1, 1, 1, clampf(1.2 - float(d) / float(SPARKLE_RANGE + 1), 0.6, 1.0))
			if sp.has_meta("motes"):
				(sp.get_meta("motes") as CPUParticles2D).emitting = true
		else:
			sp.emitting = false
			if sp.has_meta("motes"):
				(sp.get_meta("motes") as CPUParticles2D).emitting = false
	hint_layer.queue_redraw()


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
	return kayak.position.distance_to(dock) > 10.0 * 32.0


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
# --------------------------------------------------------------- party
func partner_of(c):
	for o in party:
		if o != c:
			return o
	return null


func game_days() -> float:
	return float(day_night.day) + day_night.time_of_day / 24.0


## Swap control between Juniper and Rowan.
func switch_character() -> void:
	var next = partner_of(player)
	if next == null:
		return
	if next.downed:
		message("%s is knocked out - get to them and hold Space to revive." % next.char_name)
		return
	player.controlled = false
	player._cancel_tool()
	player.velocity = Vector2.ZERO
	player.anchor = player.position
	player.ai.state = "idle"
	player.ai.timer = 1.0
	# A driver who stops controlling becomes a passenger: the kayak waits.
	if player.is_paddling() and not next.is_paddling():
		kayak.set_state(KayakScript.State.PARKED)
	next.controlled = true
	next._cancel_tool()
	player = next
	active_index = party.find(next)
	if next.is_paddling():
		kayak.set_state(KayakScript.State.OCCUPIED)
		next.position = kayak.position
		next.heading = kayak.heading
	message("You are now playing as %s." % next.char_name)


## Ask the partner to come to you (T).
func call_partner() -> void:
	var other = partner_of(player)
	if other == null or other.downed or other.is_paddling():
		return
	var to: Vector2 = _beside(player.position) if player.can_be_at(player.position, false) else player.position
	other.ai.come_to(other, to)
	partner_message(other, "%s is on the way!" % other.char_name, true)


func partner_message(c, text: String, force: bool = false) -> void:
	if c.controlled:
		message(text)
		return
	if not force and _partner_msg_cd > 0.0:
		return
	_partner_msg_cd = 6.0
	message(text if text.begins_with(c.char_name) else "%s: %s" % [c.char_name, text])


func nearest_character(pos: Vector2, on_foot_only: bool = false):
	var best = null
	var best_d: float = 1e20
	for c in party:
		if c.downed:
			continue
		if on_foot_only and c.is_paddling():
			continue
		var d: float = pos.distance_to(c.position)
		if d < best_d:
			best_d = d
			best = c
	return best


func nearest_threat(pos: Vector2, radius: float):
	var best = null
	var best_d: float = radius
	for a in get_tree().get_nodes_in_group("animals"):
		if not a.alive or not a.is_predator() or a.leaving:
			continue
		var d: float = pos.distance_to(a.position)
		if d < best_d and (a.is_threat() or d < radius * 0.5):
			best_d = d
			best = a
	return best


## Where a fleeing partner should run: lit camp, else their anchor.
func safe_point_for(c) -> Vector2:
	if camp != null and camp.lit:
		return camp.fire_position()
	if c.position.distance_to(c.anchor) > 64.0:
		return c.anchor
	return Vector2.INF


func on_character_hurt(c, amount: float) -> void:
	if c.controlled:
		_shake = 0.3
		vignette.color.a = clampf(amount / 40.0, 0.15, 0.45)
	else:
		partner_message(c, "%s is hurt!" % c.char_name)


func on_character_downed(c) -> void:
	var other = partner_of(c)
	if other != null and not other.downed:
		if c.controlled:
			message("%s is knocked out! Switching to %s - hold Space next to them to revive." % [c.char_name, other.char_name])
			switch_character_forced(other)
		else:
			message("%s is knocked out! Go hold Space next to them to revive." % c.char_name)
		return
	player_died()


func switch_character_forced(next) -> void:
	player.controlled = false
	next.controlled = true
	player = next
	active_index = party.find(next)
	if next.is_paddling():
		kayak.set_state(KayakScript.State.OCCUPIED)


func chop_swing_fx(t: Vector2i) -> void:
	var at: Vector2 = world.tile_center(t) + Vector2(0, -20)
	var p := CPUParticles2D.new()
	p.position = at
	p.z_index = 7
	p.texture = Art.dot_texture()
	p.amount = 8
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.6
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.gravity = Vector2(0, 180)
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	p.color = Color(0.45, 0.75, 0.3)
	p.emitting = true
	entities.add_child(p)
	get_tree().create_timer(1.0, false).timeout.connect(p.queue_free)
	tall_decor.modulate = Color(1, 1, 1)


## A tree topples over as it's felled.
func tree_fall_fx(t: Vector2i, tree_id: int) -> void:
	var s := Sprite2D.new()
	var tex := AtlasTexture.new()
	tex.atlas = Art.DECOR
	var c: Vector2i = Decor.atlas_coords(tree_id)
	tex.region = Rect2(c.x * 64, c.y * 64, 64, 64)
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-32, -40)
	s.position = world.tile_center(t) + Vector2(0, 8)
	s.z_index = 2
	add_child(s)
	var dir: float = 1.0 if randf() < 0.5 else -1.0
	var tw := s.create_tween()
	tw.tween_property(s, "rotation", dir * PI * 0.5, 0.55).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(s, "modulate:a", 0.0, 0.35)
	tw.tween_callback(s.queue_free)
	FX.splash(entities, world.tile_center(t), 6)


func _draw_cursor() -> void:
	if player == null or player.downed:
		return
	var tgt: Dictionary = player.space_target()
	if tgt.is_empty():
		return
	var t: Vector2i = tgt["tile"]
	var a: float = 0.55 + 0.3 * sin(Time.get_ticks_msec() / 160.0)
	var r := Rect2(Vector2(t * 32) + Vector2(2, 2), Vector2(28, 28))
	target_cursor.draw_rect(r, Color(1.0, 0.92, 0.5, a), false, 2.0)


# ------------------------------------------------------------ death/respawn
func player_died() -> void:
	get_tree().paused = true
	death_panel.visible = true


func _respawn() -> void:
	death_panel.visible = false
	coins = int(coins * 0.75)
	var pos: Vector2 = respawn_point
	if camp != null:
		pos = camp.position + Vector2(0, 28)
	var first = party[0]
	for c in kayak.riders.duplicate():
		kayak.remove_rider(c)
	if not first.can_be_at(pos, false):
		pos = first._find_spot(pos, false, false)
	if not first.can_be_at(pos, false):
		pos = world.tile_center(world.start)
	for c in party:
		var inv = c.inventory
		var d: Dictionary = inv.to_dict()
		for id in d:
			if not ItemDB.is_key(id):
				d[id] = int(d[id]) / 2
		inv.from_dict(d)
		c.health = 60.0
		c.hunger = maxf(c.hunger, 50.0)
		c.stamina = 100.0
		c.exposure = 0.0
		c.poison = 0.0
		c.velocity = Vector2.ZERO
		c.mode = PlayerScript.Mode.WALKING
		c.downed = false
		c.dead = false
	party[0].position = pos
	party[1].position = _beside(pos)
	for c in party:
		c.anchor = c.position
	switch_character_forced(party[0])
	party[1].controlled = false
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
		"party": [party[0].to_dict(), party[1].to_dict()],
		"active": active_index,
		"coins": coins, "hull": hull_level, "paddle": paddle_level,
		"edits": edits.to_array(),
		"kayak": {"pos": [kayak.position.x, kayak.position.y], "heading": kayak.heading, "state": kayak.state,
			"riders": kayak.riders.map(func(c): return c.who)},
		"camp": null,
		"dug": dug.keys(),
		"revealed": revealed_treasures.keys(),
		"discovered": exploration.to_base64(),
		"respawn": [respawn_point.x, respawn_point.y],
		"stats": stats,
		"journal": journal,
	}
	if camp != null:
		d["camp"] = {"pos": [camp.position.x, camp.position.y], "lit": camp.lit}
	return GameState.write_save(d)


func _apply_save(d: Dictionary) -> void:
	day_night.time_of_day = float(d.get("time", 8.0))
	day_night.day = int(d.get("day", 1))
	day_night._ready()
	coins = int(d.get("coins", coins))
	hull_level = clampi(int(d.get("hull", 0)), 0, ItemDB.HULLS.size() - 1)
	paddle_level = clampi(int(d.get("paddle", 0)), 0, ItemDB.PADDLES.size() - 1)
	if d.has("party"):
		var pd: Array = d["party"]
		for i in mini(2, pd.size()):
			party[i].from_dict(pd[i])
	else:
		# Version 1 save: one character. Rowan joins beside Juniper.
		party[0].from_dict(d.get("player", {}))
		if party[0].is_paddling():
			party[0].mode = PlayerScript.Mode.PADDLING
		party[1].position = _beside(party[0].position)
		party[1].anchor = party[1].position
		party[1].inventory.from_dict({"shovel": 1, "carrot_seeds": 4})
	for c in party:
		c.apply_upgrades()
	var kd: Dictionary = d.get("kayak", {})
	var kp: Array = kd.get("pos", [party[0].position.x, party[0].position.y])
	kayak.position = Vector2(float(kp[0]), float(kp[1]))
	kayak.heading = float(kd.get("heading", 0.0))
	var rider_ids: Array = kd.get("riders", [])
	if not d.has("party") and party[0].is_paddling():
		rider_ids = [0]
	for w in rider_ids:
		var c = party[clampi(int(w), 0, 1)]
		c.mode = PlayerScript.Mode.PADDLING
		kayak.add_rider(c)
	for c in party:
		if c.is_paddling() and not kayak.has_rider(c):
			c.mode = PlayerScript.Mode.WALKING
	var act: int = clampi(int(d.get("active", 0)), 0, 1)
	party[0].controlled = false
	party[1].controlled = false
	party[act].controlled = true
	player = party[act]
	active_index = act
	kayak.set_state(KayakScript.State.OCCUPIED if kayak.has_rider(player) else int(kd.get("state", KayakScript.State.PARKED)))
	if kayak.state == KayakScript.State.OCCUPIED and not kayak.has_rider(player):
		kayak.set_state(KayakScript.State.PARKED)
	if kayak.state == KayakScript.State.CARRIED and not player.is_carrying():
		kayak.set_state(KayakScript.State.PARKED)
	var cd = d.get("camp", null)
	if cd is Dictionary:
		var cp: Array = cd.get("pos", [0, 0])
		_spawn_camp(Vector2(float(cp[0]), float(cp[1])), bool(cd.get("lit", false)))
	for v in d.get("dug", []):
		var idx: int = int(v)
		dug[idx] = true
	for v in d.get("revealed", []):
		revealed_treasures[int(v)] = true
	exploration.from_base64(str(d.get("discovered", "")))
	edits.from_array(d.get("edits", []))
	for idx in dug:
		if edits.get_edit(idx).is_empty():
			edits.set_edit(Vector2i(idx % world.width, idx / world.width), "dug", game_days())
	camera.position = player.position
	camera.reset_smoothing()
	var rp: Array = d.get("respawn", [player.position.x, player.position.y])
	respawn_point = Vector2(float(rp[0]), float(rp[1]))
	var st = d.get("stats", {})
	if st is Dictionary:
		stats = st
	var jr = d.get("journal", {})
	if jr is Dictionary:
		journal = {"creatures": jr.get("creatures", {}), "finds": jr.get("finds", {}),
			"variants": jr.get("variants", {})}
	for i in stores.size():
		store_seen[i] = exploration.is_discovered(world.stores[i])
