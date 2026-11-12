extends Node2D
## The kayaker. Three movement modes:
##   WALKING  - on foot over land and shallows
##   PADDLING - in the kayak on any navigable water
##   CARRYING - on foot with the kayak overhead (slow, can't use tools)

const Art = preload("res://scripts/art.gd")
const Tiles = preload("res://scripts/world/tiles.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const Inventory = preload("res://scripts/systems/inventory.gd")
const ArrowScript = preload("res://scripts/entities/arrow.gd")
const KayakScript = preload("res://scripts/entities/kayak.gd")

enum Mode { WALKING, PADDLING, CARRYING }

const WALK_SPEED := 58.0
const CARRY_MULT := 0.55
const SPRINT_MULT := 1.6
const CURRENT_SPEED := 34.0
const KAYAK_REACH := 24.0
const DIG_TIME := 1.6
const CHOP_TIME := 1.3
const SHOOT_COOLDOWN := 0.55
const HUNGER_RATE := 100.0 / 480.0
const EXPOSURE_GRACE := 25.0

var main
var world
var kayak
var mode: int = Mode.WALKING
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN

var health: float = 100.0
var hunger: float = 100.0
var stamina: float = 100.0
var coins: int = 50
var inventory = Inventory.new()
var hull_level: int = 0
var paddle_level: int = 0

var tool_action: String = ""
var tool_progress: float = 0.0
var fish_state: int = 0 # 0 idle, 1 line out, 2 bite!
var fish_timer: float = 0.0
var exposure: float = 0.0
var cold: bool = false
var dead: bool = false

var _shoot_cd: float = 0.0
var _invuln: float = 0.0
var _anim: float = 0.0
var _stroke_t: float = 0.0
var _last_tile: Vector2i = Vector2i(-9999, -9999)

var sprite: Sprite2D
var carry_sprite: Sprite2D
var bite_icon: Sprite2D
var light: PointLight2D
var camera: Camera2D
var progress_bar: Node2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = Art.sprite(Art.PLAYER_DOWN)
	sprite.offset = Vector2(0, -7)
	add_child(sprite)
	carry_sprite = Sprite2D.new()
	carry_sprite.position = Vector2(0, -15)
	carry_sprite.visible = false
	add_child(carry_sprite)
	bite_icon = Sprite2D.new()
	bite_icon.texture = Art.sprite(Art.BITE)
	bite_icon.position = Vector2(0, -24)
	bite_icon.visible = false
	add_child(bite_icon)
	light = PointLight2D.new()
	light.texture = Art.light_texture()
	light.texture_scale = 1.3
	light.color = Color(1.0, 0.95, 0.85)
	light.energy = 0.0
	add_child(light)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)
	camera.make_current()
	progress_bar = Node2D.new()
	progress_bar.position = Vector2(0, -26)
	progress_bar.draw.connect(_draw_progress)
	add_child(progress_bar)


func setup(main_node, world_data, kayak_node) -> void:
	main = main_node
	world = world_data
	kayak = kayak_node
	var px: Vector2 = world.pixel_size()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(px.x)
	camera.limit_bottom = int(px.y)
	apply_upgrades()


func apply_upgrades() -> void:
	inventory.max_slots = int(ItemDB.HULLS[hull_level]["slots"])
	if kayak:
		kayak.set_hull(hull_level)


func is_paddling() -> bool:
	return mode == Mode.PADDLING


func is_carrying() -> bool:
	return mode == Mode.CARRYING


# ------------------------------------------------------------------ process
func _process(delta: float) -> void:
	if main == null or dead:
		return
	_anim += delta
	_shoot_cd -= delta
	_invuln -= delta
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if tool_action != "" and input != Vector2.ZERO:
		_cancel_tool()
	if fish_state != 0 and (input != Vector2.ZERO or mode != Mode.PADDLING):
		_cancel_fishing("You reel in your line.")
	if mode == Mode.PADDLING:
		_process_paddle(delta, input)
	else:
		_process_walk(delta, input)
	_process_tool(delta)
	_process_fishing(delta)
	_update_survival(delta)
	_update_visuals(delta)
	var t: Vector2i = world.tile_at_pos(position)
	if t != _last_tile:
		_last_tile = t
		main.on_player_tile_changed(t)


func _unhandled_input(event: InputEvent) -> void:
	if main == null or dead:
		return
	if event.is_action_pressed("board"):
		try_board()
	elif event.is_action_pressed("carry"):
		try_carry()
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


# ----------------------------------------------------------------- movement
func _process_walk(delta: float, input: Vector2) -> void:
	if tool_action != "":
		velocity = Vector2.ZERO
		return
	var speed: float = WALK_SPEED * world.walk_mult_at_pos(position)
	if mode == Mode.CARRYING:
		speed *= CARRY_MULT
	elif Input.is_action_pressed("sprint") and stamina > 1.0 and input != Vector2.ZERO:
		speed *= SPRINT_MULT
		stamina -= 24.0 * delta
	velocity = input * speed
	if input != Vector2.ZERO:
		facing = input.normalized()
	_move(velocity * delta, false)


func _process_paddle(delta: float, input: Vector2) -> void:
	var hull: Dictionary = ItemDB.HULLS[hull_level]
	var paddle: Dictionary = ItemDB.PADDLES[paddle_level]
	var max_speed: float = float(hull["speed"])
	var accel: float = float(paddle["accel"])
	if input != Vector2.ZERO and Input.is_action_pressed("sprint") and stamina > 1.0:
		max_speed *= 1.45
		accel *= 1.5
		stamina -= 22.0 * float(paddle["stamina"]) * delta
	if world.tile_type_at_pos(position) == Tiles.MARSH:
		max_speed *= 0.5
	if input != Vector2.ZERO:
		velocity += input * accel * delta
		if velocity.length() > max_speed:
			velocity = velocity.normalized() * max_speed
		facing = input.normalized()
		_stroke_t += delta
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 38.0 * delta)
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
	var hw: float = 5.0 if in_kayak else 4.0
	var hh: float = 4.0 if in_kayak else 3.0
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
	for r in [12.0, 18.0, 24.0, 30.0]:
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
	return kayak.state == KayakScript.State.PARKED and position.distance_to(kayak.position) < KAYAK_REACH


func try_board() -> void:
	match mode:
		Mode.WALKING:
			if not near_kayak():
				main.message("Your kayak isn't nearby.")
				return
			var target: Vector2 = kayak.position
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
			kayak.position = position
			kayak.rotation = facing.angle() if velocity.length() < 5.0 else velocity.angle()
			kayak.set_state(KayakScript.State.PARKED)
			position = land
			velocity = Vector2.ZERO
			mode = Mode.WALKING
			main.message("You step ashore.")


func _enter_kayak(spot: Vector2) -> void:
	position = spot
	velocity = Vector2.ZERO
	mode = Mode.PADDLING
	kayak.position = spot
	kayak.set_state(KayakScript.State.OCCUPIED)
	carry_sprite.visible = false
	_cancel_tool()


func try_carry() -> void:
	match mode:
		Mode.WALKING:
			if not near_kayak():
				main.message("Your kayak isn't nearby.")
				return
			mode = Mode.CARRYING
			kayak.set_state(KayakScript.State.CARRIED)
			_cancel_tool()
		Mode.CARRYING:
			var drop: Vector2 = position + facing * 10.0
			if not (can_be_at(drop, false) or can_be_at(drop, true)):
				drop = position
			kayak.position = drop
			kayak.rotation = 0.0 if absf(facing.x) >= absf(facing.y) else PI * 0.5
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
				var q: Vector2 = p + Vector2.RIGHT.rotated(k * TAU / 24.0) * r * 16.0
				if can_be_at(q, true):
					spot = q
					break
			if can_be_at(spot, true):
				break
	kayak.position = spot
	kayak.rotation = 0.0
	kayak.set_state(KayakScript.State.PARKED)


# ------------------------------------------------------------------ hunting
func try_shoot(use_mouse: bool) -> void:
	if mode == Mode.CARRYING or tool_action != "" or _shoot_cd > 0.0:
		return
	if not inventory.has("bow"):
		return
	if not inventory.has("arrows"):
		main.message("Out of arrows! Craft some from wood (Tab) or buy them.")
		_shoot_cd = 0.5
		return
	var dir: Vector2 = facing
	if use_mouse:
		var to_mouse: Vector2 = get_global_mouse_position() - (position + Vector2(0, -6))
		if to_mouse.length() > 2.0:
			dir = to_mouse.normalized()
	inventory.remove("arrows", 1)
	_shoot_cd = SHOOT_COOLDOWN
	var a = ArrowScript.new()
	a.main = main
	a.direction = dir
	a.position = position + Vector2(0, -6) + dir * 6.0
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
	fish_timer = randf_range(2.5, 7.0) * (0.8 if t == Tiles.DEEP else 1.0)
	main.message("You cast your line... (G to reel in)")


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
	var n: int = 2 if randf() < 0.2 else 1
	var added: int = inventory.add("fish_raw", n)
	if added > 0:
		main.message("Caught %d fish!" % added)
	else:
		main.message("Inventory full - you let the fish go.")
	fish_state = 0
	bite_icon.visible = false


func _cancel_fishing(msg: String) -> void:
	if fish_state != 0:
		main.message(msg)
	fish_state = 0
	bite_icon.visible = false


# ---------------------------------------------------- digging and chopping
func _process_tool(delta: float) -> void:
	var holding: bool = Input.is_action_pressed("use_tool")
	if tool_action == "":
		if Input.is_action_just_pressed("use_tool") and mode == Mode.WALKING:
			tool_action = _choose_tool_action()
			tool_progress = 0.0
		progress_bar.queue_redraw()
		return
	if not holding or mode != Mode.WALKING:
		_cancel_tool()
		return
	tool_progress += delta
	var total: float = DIG_TIME if tool_action == "dig" else CHOP_TIME
	if tool_progress >= total:
		var act: String = tool_action
		tool_action = ""
		tool_progress = 0.0
		if act == "dig":
			main.dig_at(position)
		elif act == "chop":
			_chop()
	progress_bar.queue_redraw()


func _choose_tool_action() -> String:
	var near_forest: bool = _forest_nearby()
	var has_shovel: bool = inventory.has("shovel")
	if has_shovel and main.treasure_hint_near(position):
		return "dig"
	if near_forest:
		return "chop"
	if has_shovel:
		return "dig"
	main.message("Nothing to do here. (Space: chop near trees, dig with a shovel)")
	return ""


func _forest_nearby() -> bool:
	var here: Vector2i = world.tile_at_pos(position)
	for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if world.get_tile(here.x + d.x, here.y + d.y) == Tiles.FOREST:
			return true
	return false


func _chop() -> void:
	var added: int = inventory.add("wood", 1)
	if added == 0:
		main.message("Inventory full.")
		return
	var msg := "+1 Firewood"
	if randf() < 0.25 and inventory.add("berries", 1) > 0:
		msg += ", +1 Wild Berries"
	main.message(msg)


func _cancel_tool() -> void:
	tool_action = ""
	tool_progress = 0.0
	if progress_bar:
		progress_bar.queue_redraw()


func _draw_progress() -> void:
	if tool_action == "":
		return
	var total: float = DIG_TIME if tool_action == "dig" else CHOP_TIME
	var f: float = clampf(tool_progress / total, 0.0, 1.0)
	progress_bar.draw_rect(Rect2(-9, 0, 18, 3), Color(0, 0, 0, 0.7))
	progress_bar.draw_rect(Rect2(-9, 0, 18 * f, 3), Color(0.95, 0.8, 0.3))


# ---------------------------------------------------------------- survival
func _update_survival(delta: float) -> void:
	var rate: float = HUNGER_RATE
	if mode == Mode.PADDLING and velocity.length() > 20.0:
		rate *= 1.15
	if Input.is_action_pressed("sprint"):
		rate *= 1.3
	hunger = maxf(0.0, hunger - rate * delta)
	if not Input.is_action_pressed("sprint"):
		var regen: float = 15.0 if hunger > 20.0 else 6.0
		stamina = minf(100.0, stamina + regen * delta)
	stamina = maxf(stamina, 0.0)
	if hunger <= 0.0:
		health -= 1.0 * delta
	elif hunger > 50.0 and health < 100.0:
		health = minf(100.0, health + 0.5 * delta)
	# Cold nights: you need a lit camp.
	if main.day_night.is_night() and not main.is_in_safe_zone(position):
		exposure += delta
		cold = exposure > EXPOSURE_GRACE
		if cold:
			health -= 0.3 * delta
	else:
		exposure = 0.0
		cold = false
	if health <= 0.0 and not dead:
		health = 0.0
		dead = true
		main.player_died()


func take_damage(amount: float) -> void:
	if _invuln > 0.0 or dead:
		return
	health -= amount
	_invuln = 0.6
	sprite.modulate = Color(1, 0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	main.message("Ouch!")


func eat(id: String) -> bool:
	var food: float = float(ItemDB.item(id).get("food", 0))
	if food <= 0.0 or not inventory.has(id):
		return false
	if hunger >= 98.0:
		main.message("You're not hungry.")
		return false
	inventory.remove(id, 1)
	hunger = minf(100.0, hunger + food)
	main.message("You eat the %s." % ItemDB.item_name(id).to_lower())
	return true


func eat_best() -> void:
	for id in ItemDB.EAT_ORDER:
		if inventory.has(id):
			eat(id)
			return
	main.message("You have nothing to eat! Hunt, fish or forage.")


# ----------------------------------------------------------------- visuals
func _update_visuals(delta: float) -> void:
	light.energy = main.day_night.darkness() * 0.85
	match mode:
		Mode.PADDLING:
			sprite.visible = false
			carry_sprite.visible = false
			kayak.position = position
			var moving: bool = velocity.length() > 6.0
			if moving:
				kayak.rotation = lerp_angle(kayak.rotation, velocity.angle(), clampf(8.0 * delta, 0.0, 1.0))
			var frame: int = 1
			if Input.get_vector("move_left", "move_right", "move_up", "move_down") != Vector2.ZERO:
				frame = 1 + int(_stroke_t * 3.0) % 2
			if frame != kayak.paddle_frame:
				kayak.paddle_frame = frame
				kayak.refresh()
		_:
			sprite.visible = true
			carry_sprite.visible = mode == Mode.CARRYING
			if mode == Mode.CARRYING:
				carry_sprite.texture = Art.kayak_frame(hull_level, 0)
				carry_sprite.flip_h = facing.x < 0
			if absf(facing.x) > absf(facing.y):
				sprite.texture = Art.sprite(Art.PLAYER_SIDE)
				sprite.flip_h = facing.x < 0
			else:
				sprite.texture = Art.sprite(Art.PLAYER_DOWN if facing.y >= 0 else Art.PLAYER_UP)
				sprite.flip_h = false
			if velocity.length() > 1.0:
				sprite.position.y = -absf(sin(_anim * 14.0)) * 1.5
			else:
				sprite.position.y = 0.0
	if _invuln <= 0.0 and sprite.modulate != Color.WHITE and not cold:
		sprite.modulate = Color.WHITE
	if cold:
		sprite.modulate = Color(0.75, 0.85, 1.1)


# -------------------------------------------------------------- save/load
func to_dict() -> Dictionary:
	return {
		"pos": [position.x, position.y],
		"mode": mode,
		"facing": [facing.x, facing.y],
		"health": health, "hunger": hunger, "stamina": stamina,
		"coins": coins,
		"inventory": inventory.to_dict(),
		"hull": hull_level, "paddle": paddle_level,
	}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [position.x, position.y])
	position = Vector2(float(p[0]), float(p[1]))
	var f: Array = d.get("facing", [0, 1])
	facing = Vector2(float(f[0]), float(f[1]))
	mode = int(d.get("mode", Mode.WALKING))
	health = float(d.get("health", 100))
	hunger = float(d.get("hunger", 100))
	stamina = float(d.get("stamina", 100))
	coins = int(d.get("coins", 0))
	hull_level = clampi(int(d.get("hull", 0)), 0, ItemDB.HULLS.size() - 1)
	paddle_level = clampi(int(d.get("paddle", 0)), 0, ItemDB.PADDLES.size() - 1)
	apply_upgrades()
	inventory.from_dict(d.get("inventory", {}))
