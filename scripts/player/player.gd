extends Node2D
## A playable character (Juniper or Rowan). Both characters run this script;
## the one you control reads input, the other is driven by PartnerAI.
## Movement modes:
##   WALKING  - on foot over land and shallows
##   PADDLING - seated in the two-person kayak
##   CARRYING - on foot with the kayak overhead (slow, can't use tools)

const Art = preload("res://scripts/art.gd")
const Tiles = preload("res://scripts/world/tiles.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const Inventory = preload("res://scripts/systems/inventory.gd")
const ArrowScript = preload("res://scripts/entities/arrow.gd")
const KayakScript = preload("res://scripts/entities/kayak.gd")
const Decor = preload("res://scripts/world/decor.gd")
const FX = preload("res://scripts/fx/fx.gd")
const PartnerAI = preload("res://scripts/ai/partner_ai.gd")

enum Mode { WALKING, PADDLING, CARRYING }

const NAMES := ["Juniper", "Rowan"]
const WALK_SPEED := 116.0
const CARRY_MULT := 0.55
const SPRINT_MULT := 1.6
const CURRENT_SPEED := 85.0
const KAYAK_REACH := 48.0
const REVIVE_REACH := 52.0
## Stroke frames per second while paddling (scaled by speed).
const STROKE_RATE := 3.2
const SHOOT_COOLDOWN := 0.55
const HUNGER_RATE := 100.0 / 480.0
const DIGEST_RATE := 6.0
const EXPOSURE_GRACE := 25.0
const ACTION_TIME := {
	"chop": 1.8, "forage": 0.8, "till": 1.2, "dig": 1.4, "dig_treasure": 1.6,
	"plant": 0.6, "harvest": 0.8, "revive": 2.0,
}
const ACTION_LABEL := {
	"chop": "Chop", "forage": "Forage", "till": "Till", "dig": "Dig", "dig_treasure": "Dig treasure",
	"plant": "Plant", "harvest": "Harvest", "revive": "Revive",
}

var main
var world
var kayak
## 0 = Juniper, 1 = Rowan (selects sprites and kayak frames).
var who: int = 0
var char_name: String = "Juniper"
var controlled: bool = true
var mode: int = Mode.WALKING
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN
## Kayak hull direction (radians) while paddling.
var heading: float = 0.0

var health: float = 100.0
var hunger: float = 100.0
var stamina: float = 100.0
## Food eaten but not yet digested; drains into hunger over time.
var digesting: float = 0.0
var poison: float = 0.0
var inventory = Inventory.new()
var downed: bool = false
## Kept for compatibility: true only when the whole party is down.
var dead: bool = false
## Where the partner AI hangs around when idle.
var anchor: Vector2 = Vector2.ZERO
var ai = PartnerAI.new()
## Movement requested by the AI when not controlled.
var ai_input: Vector2 = Vector2.ZERO

var tool_action: String = ""
var tool_tile: Vector2i = Vector2i.ZERO
var tool_progress: float = 0.0
var fish_state: int = 0 # 0 idle, 1 line out, 2 bite!
var fish_timer: float = 0.0
var exposure: float = 0.0
var cold: bool = false

var _shoot_cd: float = 0.0
var _attack_cd: float = 0.0
var _invuln: float = 0.0
var _anim: float = 0.0
var _stroke_t: float = 0.0
var _last_tile: Vector2i = Vector2i(-9999, -9999)
var _swing_count: int = 0

var sprite: Sprite2D
var carry_sprite: Sprite2D
var bite_icon: Sprite2D
var heart_icon: Sprite2D
var light: PointLight2D
var progress_bar: Node2D
var name_label: Label

## Shared party resources live on main.
var coins: int:
	get:
		return main.coins if main else 0
	set(v):
		if main:
			main.coins = v
var hull_level: int:
	get:
		return main.hull_level if main else 0
	set(v):
		if main:
			main.hull_level = v
var paddle_level: int:
	get:
		return main.paddle_level if main else 0
	set(v):
		if main:
			main.paddle_level = v


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = Art.player_frame(Art.VIEW_DOWN, 0, who)
	sprite.offset = Vector2(0, -22)
	add_child(sprite)
	carry_sprite = Sprite2D.new()
	carry_sprite.position = Vector2(0, -38)
	carry_sprite.visible = false
	add_child(carry_sprite)
	bite_icon = Sprite2D.new()
	bite_icon.texture = Art.prop(Art.BITE)
	bite_icon.position = Vector2(0, -52)
	bite_icon.scale = Vector2(0.7, 0.7)
	bite_icon.visible = false
	add_child(bite_icon)
	heart_icon = Sprite2D.new()
	heart_icon.texture = Art.prop(Art.HEART)
	heart_icon.position = Vector2(0, -40)
	heart_icon.scale = Vector2(0.5, 0.5)
	heart_icon.visible = false
	add_child(heart_icon)
	light = PointLight2D.new()
	light.texture = Art.light_texture()
	light.texture_scale = 1.0
	light.color = Color(1.0, 0.82, 0.55)
	light.energy = 0.0
	add_child(light)
	progress_bar = Node2D.new()
	progress_bar.position = Vector2(0, -56)
	progress_bar.draw.connect(_draw_progress)
	add_child(progress_bar)
	name_label = Label.new()
	name_label.text = char_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.13))
	name_label.add_theme_constant_override("outline_size", 5)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size = Vector2(100, 18)
	name_label.position = Vector2(-50, -70)
	name_label.visible = false
	add_child(name_label)


func setup(main_node, world_data, kayak_node, who_index: int = 0) -> void:
	main = main_node
	world = world_data
	kayak = kayak_node
	who = who_index
	char_name = NAMES[who]
	if name_label:
		name_label.text = char_name
	anchor = position
	apply_upgrades()


func apply_upgrades() -> void:
	inventory.max_slots = int(ItemDB.HULLS[hull_level]["slots"])
	if kayak:
		kayak.set_hull(hull_level)


func is_paddling() -> bool:
	return mode == Mode.PADDLING


func is_carrying() -> bool:
	return mode == Mode.CARRYING


func partner():
	return main.partner_of(self) if main else null


# ------------------------------------------------------------------ process
func _process(delta: float) -> void:
	if main == null or dead:
		return
	_anim += delta
	_shoot_cd -= delta
	_attack_cd -= delta
	_invuln -= delta
	if downed:
		velocity = Vector2.ZERO
		_cancel_tool()
		if is_paddling():
			position = kayak.position
		_update_survival(delta)
		_update_visuals(delta)
		return
	var input := Vector2.ZERO
	if controlled:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	else:
		ai.tick(self, delta)
		input = ai_input
	if tool_action != "" and input != Vector2.ZERO:
		_cancel_tool()
	if fish_state != 0 and (input != Vector2.ZERO or mode != Mode.PADDLING):
		_cancel_fishing("You reel in your line.")
	if mode == Mode.PADDLING:
		if controlled:
			_process_paddle(delta, input)
		else:
			# A passenger rides along with the kayak.
			position = kayak.position
			heading = kayak.heading
			velocity = Vector2.ZERO
	else:
		_process_walk(delta, input)
	if controlled:
		_process_tool(delta)
	else:
		_process_ai_tool(delta)
	_process_fishing(delta)
	_update_survival(delta)
	_update_visuals(delta)
	var t: Vector2i = world.tile_at_pos(position)
	if t != _last_tile:
		_last_tile = t
		main.on_char_tile_changed(self, t)


func _unhandled_input(event: InputEvent) -> void:
	if main == null or dead or downed or not controlled:
		return
	if event.is_action_pressed("board"):
		try_board()
	elif event.is_action_pressed("carry"):
		try_carry()
	elif event.is_action_pressed("attack"):
		try_attack(true)
	elif event.is_action_pressed("shoot"):
		try_shoot(true)
	elif event.is_action_pressed("shoot_key"):
		try_shoot(false)
	elif event.is_action_pressed("fish"):
		try_fish()
	elif event.is_action_pressed("eat"):
		eat_best()
	elif event.is_action_pressed("camp"):
		main.toggle_camp()
	elif event.is_action_pressed("interact"):
		main.try_interact()
	elif event.is_action_pressed("call_partner"):
		main.call_partner()


# ----------------------------------------------------------------- movement
func _sprinting(input: Vector2) -> bool:
	return controlled and Input.is_action_pressed("sprint") and stamina > 1.0 and input != Vector2.ZERO


func _process_walk(delta: float, input: Vector2) -> void:
	if tool_action != "":
		velocity = Vector2.ZERO
		return
	var speed: float = WALK_SPEED * world.walk_mult_at_pos(position)
	if mode == Mode.CARRYING:
		speed *= CARRY_MULT
	elif _sprinting(input):
		speed *= SPRINT_MULT
		stamina -= 24.0 * delta
	elif not controlled:
		speed *= ai.speed_mult
	velocity = input * speed
	if input != Vector2.ZERO:
		facing = input.normalized()
	_move(velocity * delta, false)


func _process_paddle(delta: float, input: Vector2) -> void:
	# Heading-based kayak physics: input steers the hull, thrust pushes along
	# it, low forward drag lets you glide, high side drag makes turns carve.
	var hull: Dictionary = ItemDB.HULLS[hull_level]
	var paddle: Dictionary = ItemDB.PADDLES[paddle_level]
	var max_speed: float = float(hull["speed"])
	var accel: float = float(paddle["accel"])
	var turn: float = float(hull["turn_rate"])
	if kayak.riders.size() >= 2:
		accel *= 1.2  # two paddlers
		max_speed *= 1.1
	var power: bool = input != Vector2.ZERO and Input.is_action_pressed("sprint") and stamina > 1.0
	if power:
		max_speed *= 1.4
		accel *= 1.5
		stamina -= 22.0 * float(paddle["stamina"]) * delta
	if world.tile_type_at_pos(position) == Tiles.MARSH:
		max_speed *= 0.5
	var fwd := Vector2.from_angle(heading)
	var side := fwd.orthogonal()
	var vf: float = velocity.dot(fwd)
	var vs: float = velocity.dot(side)
	if input != Vector2.ZERO:
		var target: float = input.angle()
		var diff: float = absf(angle_difference(heading, target))
		if diff > 2.4 and vf > 15.0:
			# Pulling back on the stick: back-paddle to brake.
			vf = move_toward(vf, 0.0, accel * 1.2 * delta)
		else:
			heading = rotate_toward(heading, target, turn * delta * (1.0 if diff > 0.05 else 0.5))
			fwd = Vector2.from_angle(heading)
			side = fwd.orthogonal()
			# Keep momentum through the turn, then add thrust when roughly aligned.
			var spd: float = velocity.length()
			vf = maxf(vf, 0.0)
			vf = lerpf(vf, spd, clampf(turn * delta, 0.0, 1.0))
			vs = velocity.dot(side)
			vf += accel * delta * clampf(cos(diff), 0.15, 1.0)
		_stroke_t += delta * STROKE_RATE * (1.25 if power else 1.0)
		facing = fwd
	vf *= exp(-float(hull["glide"]) * delta)
	vs *= exp(-float(hull["side_drag"]) * delta)
	vf = clampf(vf, -max_speed * 0.3, max_speed)
	velocity = fwd * vf + side * vs
	var current: Vector2 = world.flow_at_pos(position) * CURRENT_SPEED
	_move((velocity + current) * delta, true)


func _move(motion: Vector2, in_kayak: bool) -> void:
	var nx: Vector2 = position + Vector2(motion.x, 0)
	if can_be_at(nx, in_kayak):
		position = nx
	elif in_kayak:
		velocity.x *= -0.25
	var ny: Vector2 = position + Vector2(0, motion.y)
	if can_be_at(ny, in_kayak):
		position = ny
	elif in_kayak:
		velocity.y *= -0.25


func can_be_at(p: Vector2, in_kayak: bool) -> bool:
	var hw: float = 10.0 if in_kayak else 8.0
	var hh: float = 8.0 if in_kayak else 6.0
	for c in [Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(-hw, hh), Vector2(hw, hh)]:
		var t: Vector2i = world.tile_at_pos(p + c)
		if in_kayak:
			if not world.is_kayak_water(t.x, t.y):
				return false
		elif not world.is_walkable(t.x, t.y):
			return false
	return true


## Searches rings around `origin` (facing direction first) for a spot that
## satisfies can_be_at(spot, in_kayak). Returns origin if nothing is found.
func _find_spot(origin: Vector2, in_kayak: bool, prefer_dry: bool) -> Vector2:
	var base_ang: float = facing.angle()
	for r in [24.0, 36.0, 48.0, 60.0]:
		for k in 16:
			var off: float = (k + 1) / 2 * (TAU / 16.0) * (1 if k % 2 == 0 else -1)
			var p: Vector2 = origin + Vector2.RIGHT.rotated(base_ang + off) * r
			if not can_be_at(p, in_kayak):
				continue
			if prefer_dry and world.tile_type_at_pos(p) == Tiles.SHALLOW:
				continue
			return p
	if prefer_dry:
		return _find_spot(origin, in_kayak, false)
	return origin


# -------------------------------------------------------------- kayak moves
func near_kayak() -> bool:
	return kayak.state != KayakScript.State.CARRIED and not kayak.has_rider(self) \
			and position.distance_to(kayak.position) < KAYAK_REACH and kayak.riders.size() < 2


## Is there somewhere to step ashore from the kayak right now?
func can_land() -> bool:
	return can_be_at(_find_spot(position, false, true), false)


## Is there water close enough to launch the carried kayak?
func can_launch() -> bool:
	return can_be_at(_find_spot(position, true, false), true)


func try_board() -> void:
	match mode:
		Mode.WALKING:
			if not near_kayak():
				main.message("The kayak isn't nearby." if kayak.riders.size() < 2 else "The kayak is full.")
				return
			var target: Vector2 = kayak.position
			if not kayak.riders.is_empty():
				_enter_kayak(target)
				return
			if not can_be_at(target, true):
				target = _find_spot(kayak.position, true, false)
				if not can_be_at(target, true):
					main.message("Carry the kayak (R) to the water's edge first.")
					return
			_enter_kayak(target)
		Mode.CARRYING:
			var spot: Vector2 = _find_spot(position, true, false)
			if not can_be_at(spot, true):
				main.message("Get to the water's edge to launch.")
				return
			_enter_kayak(spot)
		Mode.PADDLING:
			var land: Vector2 = _find_spot(position, false, true)
			if not can_be_at(land, false):
				main.message("Nowhere to land here.")
				return
			exit_kayak(land)
			if not kayak.riders.is_empty():
				main.message("%s stays with the kayak." % kayak.riders[0].char_name)
			else:
				main.message("%s steps ashore." % char_name)


func _enter_kayak(spot: Vector2) -> void:
	var was_carried: bool = kayak.state == KayakScript.State.CARRIED
	var first: bool = kayak.riders.is_empty()
	mode = Mode.PADDLING
	velocity = Vector2.ZERO
	if first:
		heading = facing.angle() if was_carried else kayak.heading
		kayak.position = spot
		kayak.heading = heading
	else:
		heading = kayak.heading
		spot = kayak.position
	position = spot
	kayak.add_rider(self)
	if controlled:
		kayak.set_state(KayakScript.State.OCCUPIED)
	elif kayak.state == KayakScript.State.CARRIED:
		kayak.set_state(KayakScript.State.PARKED)
	kayak.ripple()
	FX.splash(get_parent(), spot, 10)
	carry_sprite.visible = false
	_cancel_tool()
	anchor = spot


## Leaves the kayak onto `land`; any other rider stays aboard.
func exit_kayak(land: Vector2) -> void:
	kayak.position = position
	kayak.heading = heading
	kayak.remove_rider(self)
	kayak.set_state(KayakScript.State.PARKED)
	kayak.ripple()
	position = land
	velocity = Vector2.ZERO
	mode = Mode.WALKING
	anchor = land


func try_carry() -> void:
	match mode:
		Mode.WALKING:
			if not near_kayak():
				main.message("The kayak isn't nearby.")
				return
			if not kayak.riders.is_empty():
				main.message("Someone is sitting in it!")
				return
			mode = Mode.CARRYING
			kayak.set_state(KayakScript.State.CARRIED)
			_cancel_tool()
		Mode.CARRYING:
			var drop: Vector2 = position + facing * 20.0
			if not (can_be_at(drop, false) or can_be_at(drop, true)):
				drop = position
			kayak.position = drop
			kayak.heading = 0.0 if absf(facing.x) >= absf(facing.y) else PI * 0.5
			kayak.set_state(KayakScript.State.PARKED)
			mode = Mode.WALKING
		Mode.PADDLING:
			main.message("Get out first (E).")


## Used by respawn / store retrieval.
func place_kayak_near(p: Vector2) -> void:
	var spot: Vector2 = _find_spot(p, true, false)
	if not can_be_at(spot, true):
		for r in range(1, 12):
			for k in 24:
				var q: Vector2 = p + Vector2.RIGHT.rotated(k * TAU / 24.0) * r * 32.0
				if can_be_at(q, true):
					spot = q
					break
			if can_be_at(spot, true):
				break
	for c in kayak.riders.duplicate():
		c.mode = Mode.WALKING
		kayak.remove_rider(c)
	kayak.position = spot
	kayak.heading = 0.0
	kayak.set_state(KayakScript.State.PARKED)


# ------------------------------------------------------------------ fighting
func weapon() -> Dictionary:
	for id in ["hatchet", "knife"]:
		if inventory.has(id):
			return ItemDB.WEAPONS[id]
	return ItemDB.WEAPONS["paddle"]


## Melee swing toward the mouse (controlled) or facing direction.
func try_attack(use_mouse: bool, toward: Vector2 = Vector2.INF) -> bool:
	if mode != Mode.WALKING or tool_action != "" or _attack_cd > 0.0 or downed:
		return false
	var w: Dictionary = weapon()
	var dir: Vector2 = facing
	if toward != Vector2.INF:
		dir = (toward - position).normalized()
	elif use_mouse and controlled:
		var to_mouse: Vector2 = get_global_mouse_position() - (position + Vector2(0, -12))
		if to_mouse.length() > 2.0:
			dir = to_mouse.normalized()
	facing = dir
	_attack_cd = float(w["cooldown"])
	var arc := Sprite2D.new()
	arc.texture = Art.prop(Art.SWING)
	arc.position = position + Vector2(0, -14) + dir * 18.0
	arc.rotation = dir.angle()
	arc.scale = Vector2(0.8, 0.8)
	arc.z_index = 6
	main.entities.add_child(arc)
	var tw := arc.create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, 0.18)
	tw.tween_callback(arc.queue_free)
	var hit := false
	for a in get_tree().get_nodes_in_group("animals"):
		if not a.alive:
			continue
		var to_a: Vector2 = a.position - position
		if to_a.length() < 44.0 and (to_a.length() < 14.0 or to_a.normalized().dot(dir) > 0.25):
			a.hit(int(w["damage"]), dir, float(w["knockback"]), self)
			hit = true
	return hit


func try_shoot(use_mouse: bool) -> void:
	if mode == Mode.CARRYING or tool_action != "" or _shoot_cd > 0.0 or downed:
		return
	if not inventory.has("bow"):
		return
	if not inventory.has("arrows"):
		main.message("Out of arrows! Craft some from wood (Tab) or buy them.")
		_shoot_cd = 0.5
		return
	var dir: Vector2 = facing
	if use_mouse:
		var to_mouse: Vector2 = get_global_mouse_position() - (position + Vector2(0, -12))
		if to_mouse.length() > 2.0:
			dir = to_mouse.normalized()
	inventory.remove("arrows", 1)
	_shoot_cd = SHOOT_COOLDOWN
	var a = ArrowScript.new()
	a.main = main
	a.direction = dir
	a.shooter = self
	a.position = position + Vector2(0, -12) + dir * 12.0
	main.entities.add_child(a)
	facing = dir


# ------------------------------------------------------------------ fishing
func try_fish() -> void:
	if fish_state == 2:
		_catch_fish()
		return
	if fish_state == 1:
		_cancel_fishing("You reel in your line.")
		return
	if mode != Mode.PADDLING:
		main.message("You fish from your kayak.")
		return
	if not inventory.has("fishing_rod"):
		main.message("You need a fishing rod (sold at 100's of Kayaks).")
		return
	var t: int = world.tile_type_at_pos(position)
	if t != Tiles.DEEP and t != Tiles.SHALLOW and t != Tiles.RIVER:
		main.message("Find open water to fish.")
		return
	velocity = Vector2.ZERO
	fish_state = 1
	var bait: float = 0.6 if inventory.has("worms") else 1.0
	fish_timer = randf_range(2.5, 7.0) * (0.8 if t == Tiles.DEEP else 1.0) * bait
	main.message("You cast your line..." + (" (baited with a worm)" if bait < 1.0 else ""))


func _process_fishing(delta: float) -> void:
	if fish_state == 0:
		bite_icon.visible = false
		return
	fish_timer -= delta
	if fish_state == 1 and fish_timer <= 0.0:
		fish_state = 2
		fish_timer = 0.9
		bite_icon.visible = true
	elif fish_state == 2:
		bite_icon.visible = int(_anim * 10.0) % 2 == 0
		if fish_timer <= 0.0:
			_cancel_fishing("It got away...")


func _catch_fish() -> void:
	if inventory.has("worms"):
		inventory.remove("worms", 1)
	fish_state = 0
	bite_icon.visible = false
	# Rare catches first.
	var luck: float = main.luck_mult()
	for entry in ItemDB.FISH_RARES:
		if randf() < float(entry[1]) * luck:
			var rid: String = entry[0]
			if rid == "bottle":
				main.message("You fish up a message in a bottle!", ItemDB.RARITY_COLORS[2])
				if main.reveal_treasure_near(world.tile_at_pos(position)):
					main.message("It's a treasure map! An X appears on your map (M).", ItemDB.RARITY_COLORS[2])
				main.journal_add_find("bottle")
			else:
				gain(rid, 1, position)
				main.on_rare_item(self, rid)
			return
	var n: int = 2 if randf() < 0.2 else 1
	var added: int = inventory.add("fish_raw", n)
	if added > 0:
		main.message("Caught %d fish!" % added)
	else:
		main.message("Pack full - you let the fish go.")


func _cancel_fishing(msg: String) -> void:
	if fish_state != 0 and controlled:
		main.message(msg)
	fish_state = 0
	bite_icon.visible = false


# ------------------------------------------- Space actions (hold to repeat)
## What holding Space would do right now: {"action": String, "tile": Vector2i}
func space_target() -> Dictionary:
	if mode != Mode.WALKING or downed:
		return {}
	var other = partner()
	if other != null and other.downed and not other.is_paddling() \
			and position.distance_to(other.position) < REVIVE_REACH:
		return {"action": "revive", "tile": world.tile_at_pos(other.position)}
	var here: Vector2i = world.tile_at_pos(position)
	var ahead: Vector2i = world.tile_at_pos(position + facing * 22.0)
	for t in [ahead, here]:
		var a: String = action_for_tile(t)
		if a != "":
			return {"action": a, "tile": t}
	return {}


func action_for_tile(t: Vector2i) -> String:
	if not world.in_bounds(t.x, t.y):
		return ""
	var edits = main.edits
	var kind: String = edits.kind_at(t)
	if kind == "crop":
		return "harvest" if edits.is_ripe(t) else ""
	if kind == "plot":
		return "plant" if first_seed() != "" else ""
	if inventory.has("shovel") and main.treasure_at(t):
		return "dig_treasure"
	var d: int = world.get_decor(t.x, t.y)
	if Decor.is_tree(d):
		return "chop"
	if d == Decor.BERRYBUSH or d == Decor.MUSHROOMS:
		return "forage"
	if kind != "":
		return ""
	if d >= 0 and Decor.is_tall(d):
		return ""
	var tt: int = world.get_tile(t.x, t.y)
	if not Tiles.is_diggable(tt) or not inventory.has("shovel"):
		return ""
	if tt == Tiles.SAND:
		return "dig"
	return "till"


func first_seed() -> String:
	for crop in ItemDB.CROP_ORDER:
		var seed_id: String = ItemDB.CROPS[crop]["seed"]
		if inventory.has(seed_id):
			return seed_id
	return ""


func action_time(action: String) -> float:
	var t: float = float(ACTION_TIME.get(action, 1.0))
	if action == "chop" and inventory.has("hatchet"):
		t *= 0.6
	return t


func _process_tool(delta: float) -> void:
	var holding: bool = Input.is_action_pressed("use_tool")
	if tool_action == "":
		if holding and mode == Mode.WALKING:
			var tgt: Dictionary = space_target()
			if not tgt.is_empty():
				tool_action = tgt["action"]
				tool_tile = tgt["tile"]
				tool_progress = 0.0
				_swing_count = 0
			elif Input.is_action_just_pressed("use_tool"):
				main.message("Nothing to do here. Face a tree, bush or open ground (shovel needed to dig).")
		progress_bar.queue_redraw()
		return
	if not holding or mode != Mode.WALKING:
		_cancel_tool()
		return
	_advance_tool(delta)


## AI-driven actions use the same timing without Space being held.
func _process_ai_tool(delta: float) -> void:
	if tool_action == "":
		progress_bar.queue_redraw()
		return
	if mode != Mode.WALKING:
		_cancel_tool()
		return
	_advance_tool(delta)


func start_action(action: String, t: Vector2i) -> void:
	tool_action = action
	tool_tile = t
	tool_progress = 0.0
	_swing_count = 0


func _advance_tool(delta: float) -> void:
	tool_progress += delta
	var total: float = action_time(tool_action)
	if tool_action == "chop":
		var swings: int = int(tool_progress / (total / 3.0))
		if swings > _swing_count:
			_swing_count = swings
			main.chop_swing_fx(tool_tile)
	if tool_progress >= total:
		var act: String = tool_action
		var t: Vector2i = tool_tile
		tool_action = ""
		tool_progress = 0.0
		perform_action(act, t)
	progress_bar.queue_redraw()


## Gives items, dropping what doesn't fit on the ground. Returns amount kept.
func gain(id: String, n: int, at: Vector2) -> int:
	var added: int = inventory.add(id, n)
	if added < n:
		main.spawn_pickup(id, n - added, at)
	return added


func perform_action(act: String, t: Vector2i) -> void:
	_perform(act, t)
	if act in ["chop", "forage", "till", "dig", "harvest"]:
		main.roll_rare_drops(act, world.tile_center(t), self)


func _perform(act: String, t: Vector2i) -> void:
	var now: float = main.game_days()
	var at: Vector2 = world.tile_center(t)
	var edits = main.edits
	match act:
		"chop":
			var tree: int = world.get_decor(t.x, t.y)
			if not Decor.is_tree(tree):
				return
			main.tree_fall_fx(t, tree)
			edits.set_edit(t, "stump", now, tree)
			var wood: int = randi_range(3, 4)
			gain("wood", wood, at)
			var msg := "+%d Firewood" % wood
			if randf() < 0.25:
				gain("berries", 1, at)
				msg += ", +1 Berries"
			if randf() < 0.15:
				var seed_id: String = ItemDB.CROPS[ItemDB.CROP_ORDER[randi() % 3]]["seed"]
				gain(seed_id, 1, at)
				msg += ", +1 " + ItemDB.item_name(seed_id)
			_say(msg)
		"forage":
			var d: int = world.get_decor(t.x, t.y)
			if d == Decor.BERRYBUSH:
				var n: int = randi_range(2, 3)
				gain("berries", n, at)
				edits.set_edit(t, "picked", now, Decor.BERRYBUSH)
				var msg2 := "+%d Wild Berries" % n
				if randf() < 0.2:
					var sid: String = "carrot_seeds" if randf() < 0.5 else "potato_seeds"
					gain(sid, 1, at)
					msg2 += ", +1 " + ItemDB.item_name(sid)
				_say(msg2)
			elif d == Decor.MUSHROOMS:
				var m: int = randi_range(1, 2)
				gain("mushroom", m, at)
				edits.clear_edit(t, -1)
				_say("+%d Wild Mushroom" % m)
		"till":
			edits.set_edit(t, "plot", now)
			FX.splash(main.entities, at, 4)
			if controlled and first_seed() == "":
				main.message("Plot ready. Buy seeds at 100's of Kayaks, or find them foraging.")
		"dig":
			edits.set_edit(t, "dug", now)
			var r: float = randf()
			if r < 0.12:
				gain("worms", randi_range(1, 3), at)
				_say("You dig up some worms (fishing bait).")
			elif r < 0.2:
				gain("stone", 1, at)
				_say("+1 Smooth Stone")
		"dig_treasure":
			main.dig_at(at, self)
		"plant":
			var seed_id2: String = first_seed()
			if seed_id2 == "":
				return
			inventory.remove(seed_id2, 1)
			var crop: String = ItemDB.ITEMS[seed_id2]["seed"]
			edits.set_edit(t, "crop", now, crop, 0)
			_say("Planted %s." % crop)
		"harvest":
			var e: Array = edits.get_edit(world.idx(t.x, t.y))
			if e.is_empty():
				return
			var crop2: String = str(e[2])
			var yid: String = ItemDB.CROPS[crop2]["yield"]
			var n2: int = randi_range(2, 3)
			gain(yid, n2, at)
			edits.set_edit(t, "plot", now)
			_say("Harvested %d %s!" % [n2, ItemDB.item_name(yid)])
		"revive":
			var other = partner()
			if other != null and other.downed:
				other.revive()
				main.message("%s helps %s back up." % [char_name, other.char_name])


func _say(msg: String) -> void:
	if controlled:
		main.message(msg)
	else:
		main.partner_message(self, msg)


func _cancel_tool() -> void:
	tool_action = ""
	tool_progress = 0.0
	if progress_bar:
		progress_bar.queue_redraw()


func _draw_progress() -> void:
	if tool_action == "":
		return
	var total: float = action_time(tool_action)
	var f: float = clampf(tool_progress / total, 0.0, 1.0)
	progress_bar.draw_rect(Rect2(-19, 0, 38, 6), Color(0.17, 0.13, 0.2, 0.8))
	progress_bar.draw_rect(Rect2(-18, 1, 36 * f, 4), Color(1.0, 0.82, 0.25))


## Kept for compatibility with older code paths.
func _forest_nearby() -> bool:
	var tgt: Dictionary = space_target()
	return not tgt.is_empty() and tgt["action"] == "chop"


# ---------------------------------------------------------------- survival
func _update_survival(delta: float) -> void:
	var sprint: bool = controlled and Input.is_action_pressed("sprint")
	var rate: float = HUNGER_RATE
	if mode == Mode.PADDLING and velocity.length() > 20.0:
		rate *= 1.15
	if sprint:
		rate *= 1.3
	hunger = maxf(0.0, hunger - rate * delta)
	if digesting > 0.0:
		var d: float = minf(digesting, DIGEST_RATE * delta)
		digesting -= d
		hunger = minf(100.0, hunger + d)
	if not sprint:
		var regen: float = 15.0 if hunger > 20.0 else 6.0
		stamina = minf(100.0, stamina + regen * delta)
	stamina = maxf(stamina, 0.0)
	if downed:
		return
	if poison > 0.0:
		poison -= delta
		health -= 1.0 * delta
	if hunger <= 0.0:
		health -= 1.0 * delta
	elif hunger > 50.0 and health < 100.0 and poison <= 0.0:
		health = minf(100.0, health + 0.5 * delta)
	# Cold nights: you need a lit camp (or the store's porch).
	if main.day_night.is_night() and not main.is_in_safe_zone(position):
		exposure += delta
		cold = exposure > EXPOSURE_GRACE
		if cold:
			health -= 0.3 * delta
	else:
		exposure = 0.0
		cold = false
	if health <= 0.0:
		health = 0.0
		_go_down()


func _go_down() -> void:
	if downed:
		return
	downed = true
	_cancel_tool()
	_cancel_fishing("")
	if mode == Mode.CARRYING:
		try_carry()
	main.on_character_downed(self)


func revive() -> void:
	downed = false
	dead = false
	health = 30.0
	poison = 0.0
	exposure = 0.0
	_invuln = 1.5


func take_damage(amount: float, poisoned: float = 0.0) -> void:
	if _invuln > 0.0 or dead or downed:
		return
	health -= amount
	if poisoned > 0.0:
		poison = maxf(poison, poisoned)
	_invuln = 0.6
	sprite.modulate = Color(1, 0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	main.on_character_hurt(self, amount)
	if health <= 0.0:
		health = 0.0
		_go_down()


func eat(id: String) -> bool:
	var food: float = float(ItemDB.item(id).get("food", 0))
	if food <= 0.0 or not inventory.has(id):
		return false
	if hunger + digesting >= 98.0:
		if controlled:
			main.message("You're not hungry.")
		return false
	inventory.remove(id, 1)
	digesting += food
	var heal: float = float(ItemDB.item(id).get("heal", 0))
	if heal > 0.0:
		health = minf(100.0, health + heal)
		poison = 0.0
	if controlled:
		main.message("You eat the %s." % ItemDB.item_name(id).to_lower())
	return true


func eat_best() -> void:
	for id in ItemDB.EAT_ORDER:
		if inventory.has(id):
			eat(id)
			return
	if controlled:
		main.message("You have nothing to eat! Hunt, fish, farm or forage.")


# ----------------------------------------------------------------- visuals
func _update_visuals(delta: float) -> void:
	light.energy = main.day_night.darkness() * (0.5 if controlled else 0.3)
	name_label.visible = not controlled and not is_paddling()
	heart_icon.visible = downed and int(_anim * 3.0) % 2 == 0
	if downed:
		sprite.visible = not is_paddling()
		sprite.rotation = PI * 0.5
		sprite.modulate = Color(0.7, 0.7, 0.75)
		carry_sprite.visible = false
		return
	sprite.rotation = 0.0
	match mode:
		Mode.PADDLING:
			sprite.visible = false
			carry_sprite.visible = false
			if controlled:
				kayak.position = position
				kayak.heading = heading
				kayak.speed = velocity.length()
				var paddling: bool = Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO
				var frame: int = 1
				if paddling:
					frame = 1 + int(_stroke_t) % 4
				if frame != kayak.stroke_frame:
					var dip: bool = paddling and (frame == 1 or frame == 3)
					kayak.stroke_frame = frame
					if dip:
						var side: float = 1.0 if frame == 1 else -1.0
						var blade: Vector2 = position + Vector2.from_angle(heading + PI * 0.5 * side) * 17.0
						FX.splash(get_parent(), blade, 4)
						FX.ripple(get_parent(), blade, 10.0, 0.6)
				kayak.refresh()
		_:
			sprite.visible = true
			carry_sprite.visible = mode == Mode.CARRYING
			var view: int = Art.VIEW_DOWN
			if absf(facing.x) > absf(facing.y):
				view = Art.VIEW_SIDE
				sprite.flip_h = facing.x < 0
			else:
				view = Art.VIEW_DOWN if facing.y >= 0 else Art.VIEW_UP
				sprite.flip_h = false
			var moving: bool = velocity.length() > 1.0
			var col: int = 0
			if mode == Mode.CARRYING:
				col = 4 + (int(_anim * 5.0) % 2 if moving else 0)
				var east: bool = not (view == Art.VIEW_SIDE and facing.x < 0)
				carry_sprite.texture = Art.kayak_frame(hull_level, 0 if east else 8, 0)
			elif moving:
				col = int(_anim * (9.0 if velocity.length() > WALK_SPEED * 1.2 else 7.0)) % 4
			elif tool_action != "":
				col = 1 + int(_anim * 6.0) % 2
			sprite.texture = Art.player_frame(view, col, who)
	if _invuln <= 0.0 and sprite.modulate != Color.WHITE and not cold and poison <= 0.0:
		sprite.modulate = Color.WHITE
	if poison > 0.0:
		sprite.modulate = Color(0.75, 1.0, 0.7)
	elif cold:
		sprite.modulate = Color(0.8, 0.88, 1.1)


# -------------------------------------------------------------- save/load
func to_dict() -> Dictionary:
	return {
		"who": who,
		"pos": [position.x, position.y],
		"mode": mode,
		"facing": [facing.x, facing.y],
		"heading": heading,
		"health": health, "hunger": hunger, "stamina": stamina,
		"digesting": digesting, "poison": poison, "downed": downed,
		"anchor": [anchor.x, anchor.y],
		"inventory": inventory.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [position.x, position.y])
	position = Vector2(float(p[0]), float(p[1]))
	var f: Array = d.get("facing", [0, 1])
	facing = Vector2(float(f[0]), float(f[1]))
	mode = int(d.get("mode", Mode.WALKING))
	heading = float(d.get("heading", 0.0))
	health = float(d.get("health", 100))
	hunger = float(d.get("hunger", 100))
	stamina = float(d.get("stamina", 100))
	digesting = float(d.get("digesting", 0))
	poison = float(d.get("poison", 0))
	downed = bool(d.get("downed", false))
	var an: Array = d.get("anchor", [position.x, position.y])
	anchor = Vector2(float(an[0]), float(an[1]))
	# v1 saves kept coins/upgrades on the player.
	if d.has("coins"):
		coins = int(d["coins"])
	if d.has("hull"):
		hull_level = clampi(int(d["hull"]), 0, ItemDB.HULLS.size() - 1)
	if d.has("paddle"):
		paddle_level = clampi(int(d["paddle"]), 0, ItemDB.PADDLES.size() - 1)
	apply_upgrades()
	inventory.from_dict(d.get("inventory", {}))
