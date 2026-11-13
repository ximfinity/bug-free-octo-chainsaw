extends Node2D
## Wildlife.
## Prey (rabbit, deer, duck) wander and flee.
## Predators (wolf, spider, wildcat, bear) notice you, telegraph an attack
## with a red "!" wind-up, lunge, then recover - so you can dodge, run, or
## strike first. They give up when you get far enough away, can't follow you
## into deep water, and won't come near a lit campfire.

const Art = preload("res://scripts/art.gd")
const Tiles = preload("res://scripts/world/tiles.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const FX = preload("res://scripts/fx/fx.gd")
const VariantShader = preload("res://shaders/variant.gdshader")

## aggro: tiles at which a predator notices you (0 = only when hurt).
## swim: 0 land only, 1 shallows too, 2 water animal.
const KINDS := {
	"rabbit": {"hp": 1, "speed": 60.0, "flee_speed": 170.0, "swim": 0,
		"drops": [["meat_raw", 1, 1], ["hide", 0, 1]]},
	"deer": {"hp": 3, "speed": 52.0, "flee_speed": 156.0, "swim": 0,
		"drops": [["meat_raw", 2, 3], ["hide", 1, 2]]},
	"duck": {"hp": 1, "speed": 32.0, "flee_speed": 96.0, "swim": 2,
		"drops": [["meat_raw", 1, 1]]},
	"wolf": {"hp": 3, "speed": 60.0, "chase": 135.0, "lunge": 300.0, "damage": 12.0, "swim": 0,
		"aggro": 9.0, "night_only": true, "drops": [["hide", 1, 2]], "predator": true},
	"spider": {"hp": 2, "speed": 70.0, "chase": 150.0, "lunge": 330.0, "damage": 6.0, "poison": 5.0,
		"swim": 0, "aggro": 6.0, "drops": [["spider_silk", 1, 2]], "predator": true},
	"wildcat": {"hp": 4, "speed": 55.0, "chase": 120.0, "lunge": 420.0, "damage": 15.0, "swim": 0,
		"aggro": 5.0, "stealth": true, "drops": [["wildcat_pelt", 1, 1], ["meat_raw", 1, 1]], "predator": true},
	"bear": {"hp": 10, "speed": 40.0, "chase": 125.0, "lunge": 260.0, "damage": 30.0, "swim": 1,
		"aggro": 3.0, "windup": 0.75, "drops": [["bear_hide", 1, 1], ["bear_meat", 2, 3]], "predator": true},
	# --- rare creatures (logged in the Creature Journal) -----------------
	"white_stag": {"hp": 3, "speed": 60.0, "flee_speed": 205.0, "swim": 0, "rare": true, "flee": 230.0,
		"drops": [["white_antler", 1, 1], ["meat_raw", 2, 3]], "reward": 200},
	"fox": {"hp": 2, "speed": 70.0, "flee_speed": 190.0, "swim": 0, "rare": true, "flee": 180.0,
		"drops": [["fox_pelt", 1, 1]], "reward": 60},
	"moose": {"hp": 8, "speed": 38.0, "chase": 115.0, "lunge": 240.0, "damage": 22.0, "swim": 1,
		"aggro": 2.5, "windup": 0.7, "rare": true, "predator": true,
		"drops": [["moose_antler", 1, 1], ["hide", 2, 2], ["meat_raw", 3, 4]], "reward": 120},
	"elder_bear": {"hp": 25, "speed": 45.0, "chase": 135.0, "lunge": 290.0, "damage": 40.0, "swim": 1,
		"aggro": 4.0, "windup": 0.65, "rare": true, "predator": true, "boss": true,
		"drops": [["elder_claw", 1, 1], ["bear_hide", 2, 2], ["bear_meat", 4, 5]], "reward": 300},
	"otter": {"hp": 1, "speed": 45.0, "flee_speed": 90.0, "swim": 3, "rare": true, "watch_only": true,
		"flee": 70.0, "drops": [], "reward": 80},
	"loon": {"hp": 1, "speed": 22.0, "flee_speed": 60.0, "swim": 2, "rare": true, "watch_only": true,
		"flee": 0.0, "drops": [], "reward": 80},
	"owl": {"hp": 1, "speed": 0.0, "flee_speed": 0.0, "swim": 0, "rare": true, "watch_only": true,
		"flee": 0.0, "drops": [], "reward": 90},
	"spirit": {"hp": 1, "speed": 10.0, "flee_speed": 0.0, "swim": 2, "rare": true, "watch_only": true,
		"flee": 0.0, "drops": [], "reward": 400},
}
const NAMES := {
	"rabbit": "Rabbit", "deer": "Deer", "duck": "Mallard", "wolf": "Grey Wolf", "spider": "Giant Spider",
	"wildcat": "Wildcat", "bear": "Black Bear", "white_stag": "White Stag", "fox": "Red Fox",
	"moose": "Moose", "elder_bear": "Elder Bear", "otter": "River Otter", "loon": "Common Loon",
	"owl": "Great Horned Owl", "spirit": "Lake Spirit",
}
const SIGHT_RANGE := 230.0
const FLEE_RADIUS := 144.0
const LEASH := 32.0 * 16
const GIVE_UP := 32.0 * 13

var kind: String = "rabbit"
## Colour variant: -1 = roll on spawn, 0 normal, 1 shiny, 2 silver, 3 gold.
var variant: int = -1
var main
var hp: int = 1
var max_hp: int = 1
var alive: bool = true
var leaving: bool = false
var dir: Vector2 = Vector2.ZERO
var home: Vector2 = Vector2.ZERO
var data: Dictionary
## Predator states: wander, chase, windup, lunge, recover
var state: String = "wander"
var target = null
var provoked: bool = false
var _timer: float = 0.0
var _state_t: float = 0.0
var _flee_timer: float = 0.0
var _flash: float = 0.0
var _anim: float = 0.0
var _lunge_dir: Vector2 = Vector2.ZERO
var _hit_done: bool = false
var sprite: Sprite2D
var alert: Sprite2D
var hp_bar: Node2D
var _sighted: bool = false
var _special_t: float = 0.0
var _submerged: bool = false
var glow: PointLight2D


func _ready() -> void:
	add_to_group("animals")
	data = KINDS[kind]
	hp = int(data["hp"])
	max_hp = hp
	home = position
	sprite = Sprite2D.new()
	sprite.texture = Art.creature_frame(kind, 0)
	sprite.offset = Vector2(0, -20)
	if kind == "bear" or kind == "moose":
		sprite.scale = Vector2(1.25, 1.25)
		sprite.offset = Vector2(0, -19)
	elif kind == "elder_bear":
		sprite.scale = Vector2(1.7, 1.7)
		sprite.offset = Vector2(0, -19)
	add_child(sprite)
	if kind == "spirit":
		var mat := CanvasItemMaterial.new()
		mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		sprite.material = mat
		glow = PointLight2D.new()
		glow.texture = Art.light_texture()
		glow.texture_scale = 1.2
		glow.color = Color(0.5, 0.95, 1.0)
		glow.energy = 0.9
		glow.position = Vector2(0, -16)
		add_child(glow)
	if is_rare():
		_special_t = randf_range(3.0, 7.0)
	if variant < 0:
		variant = ItemDB.roll_variant(main.luck_mult() if main != null else 1.0)
	_apply_variant()
	alert = Sprite2D.new()
	alert.texture = Art.prop(Art.ALERT)
	alert.position = Vector2(0, -52 if kind != "bear" else -64)
	alert.scale = Vector2(0.6, 0.6)
	alert.visible = false
	add_child(alert)
	hp_bar = Node2D.new()
	hp_bar.position = Vector2(0, -44 if kind != "bear" else -58)
	hp_bar.draw.connect(_draw_hp)
	add_child(hp_bar)
	_timer = randf_range(0.5, 2.0)


func is_predator() -> bool:
	return bool(data.get("predator", false))


func _apply_variant() -> void:
	if variant <= 0:
		return
	var mat := ShaderMaterial.new()
	mat.shader = VariantShader
	mat.set_shader_parameter("mode", variant)
	mat.set_shader_parameter("sheen_offset", randf() * 4.0)
	sprite.material = mat
	var sp: CPUParticles2D = FX.make_sparkles()
	sp.color = ItemDB.VARIANT_COLORS[variant]
	sp.amount = 4 + variant * 2
	sp.position = Vector2(0, -20)
	sp.emission_sphere_radius = 16.0 if kind != "elder_bear" else 30.0
	sp.z_index = 1
	add_child(sp)
	if variant == 3:
		var lt := PointLight2D.new()
		lt.texture = Art.light_texture()
		lt.texture_scale = 0.7
		lt.color = Color(1.0, 0.85, 0.4)
		lt.energy = 0.7
		lt.position = Vector2(0, -16)
		add_child(lt)


func variant_name() -> String:
	return ItemDB.VARIANT_NAMES[clampi(variant, 0, 3)]


func is_rare() -> bool:
	return bool(data.get("rare", false))


## Peaceful rare creatures you can only watch (arrows and swings pass by).
func watch_only() -> bool:
	return bool(data.get("watch_only", false))


func display_name() -> String:
	var base: String = str(NAMES.get(kind, kind.capitalize()))
	if variant > 0:
		return "%s %s" % [variant_name(), base]
	return base


## Can this animal hurt the player right now? (Used by partner AI / HUD.)
func is_threat() -> bool:
	return alive and is_predator() and not leaving and (state == "chase" or state == "windup" or state == "lunge")


## Usable before _ready (data not loaded yet).
func _can_stand_kind(p: Vector2) -> bool:
	data = KINDS[kind]
	return _can_stand(p)


func _can_stand(p: Vector2) -> bool:
	var t: int = main.world.tile_type_at_pos(p)
	match int(data["swim"]):
		3:
			return Tiles.is_water(t)
		2:
			return t == Tiles.DEEP or t == Tiles.SHALLOW
		1:
			return Tiles.walk_ok(t)
		_:
			return Tiles.walk_ok(t) and t != Tiles.SHALLOW and t != Tiles.MARSH


func _process(delta: float) -> void:
	if not alive or main == null:
		return
	_anim += delta
	_timer -= delta
	_flee_timer -= delta
	_state_t += delta
	if _flash > 0.0:
		_flash -= delta
		sprite.modulate = Color(1, 0.4, 0.4) if _flash > 0.0 else Color.WHITE
	_check_sighting()
	var speed: float = float(data["speed"])
	if _special(delta):
		speed = float(data["speed"])
	elif not alive:
		return
	elif is_predator():
		speed = _predator(delta)
	else:
		speed = _prey()
	if dir != Vector2.ZERO and speed > 0.0:
		_step(dir * speed * delta)
	_animate(speed)


## Log the creature in the journal the first time the player sees it.
func _check_sighting() -> void:
	if _sighted or _submerged:
		return
	var c = main.player
	if c != null and c.position.distance_to(position) < SIGHT_RANGE:
		_sighted = true
		main.on_creature_sighted(self)


## Unique behaviours for rare watch-only creatures. Returns true if it
## handled movement this frame.
func _special(delta: float) -> bool:
	match kind:
		"loon":
			_special_t -= delta
			if _special_t <= 0.0:
				if _submerged:
					_submerged = false
					sprite.visible = true
					main.ripple_at(position)
					_special_t = randf_range(4.0, 8.0)
				else:
					# Dive and pop up somewhere nearby.
					main.ripple_at(position)
					if randf() < 0.25:
						main.spawn_pickup("loon_feather", 1, position)
					_submerged = true
					sprite.visible = false
					for i in 10:
						var p: Vector2 = position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(60, 150)
						if _can_stand(p):
							position = p
							break
					_special_t = randf_range(2.0, 3.5)
			if _submerged:
				dir = Vector2.ZERO
			else:
				_wander()
			return true
		"owl":
			dir = Vector2.ZERO
			var c = main.nearest_character(position)
			if c != null and c.position.distance_to(position) < 90.0:
				_fly_away("owl_feather", 0.6)
			return true
		"spirit":
			dir = Vector2.ZERO
			sprite.position.y = sin(_anim * 2.0) * 4.0 - 4.0
			sprite.modulate.a = 0.65 + 0.25 * sin(_anim * 3.0)
			if glow:
				glow.energy = 0.8 + 0.2 * sin(_anim * 3.0)
			if not main.day_night.is_night():
				_fly_away("", 0.0)
				return true
			for ch in main.party:
				if ch.position.distance_to(position) < 70.0:
					main.message("The Lake Spirit smiles and leaves a gift on the water.", Color(0.6, 0.95, 1.0))
					ch.gain("spirit_pearl", 1, position)
					main.on_rare_item(ch, "spirit_pearl")
					_fly_away("", 0.0)
					break
			return true
		"otter":
			var c2 = main.nearest_character(position)
			if c2 != null and c2.position.distance_to(position) < float(data["flee"]):
				dir = (position - c2.position).normalized()
			else:
				_wander()
			return true
	return false


func _fly_away(drop: String, chance: float) -> void:
	if not alive:
		return
	alive = false
	if drop != "" and randf() < chance:
		main.spawn_pickup(drop, 1, position)
	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 60.0, 0.9)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.9)
	tw.tween_callback(queue_free)


func _prey() -> float:
	var c = main.nearest_character(position)
	var to_c: Vector2 = c.position - position if c != null else Vector2(9999, 0)
	if to_c.length() < float(data.get("flee", FLEE_RADIUS)):
		_flee_timer = 1.5
	if _flee_timer > 0.0:
		dir = -to_c.normalized() if to_c.length() > 0.1 else Vector2.RIGHT
		return float(data["flee_speed"])
	_wander()
	return float(data["speed"])


func _predator(delta: float) -> float:
	var night: bool = main.day_night.is_night()
	if leaving or main.is_in_safe_zone(position):
		if main.camp != null:
			dir = (position - main.camp.fire_position()).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		_set_state("wander")
		return float(data["chase"])
	match state:
		"wander":
			_wander()
			if _timer < 0.0 and randf() < 0.02:
				dir = (home - position).normalized() if position.distance_to(home) > 32.0 * 6 else dir
			var aggro: float = float(data.get("aggro", 0.0)) * 32.0
			if bool(data.get("night_only", false)) and not night:
				aggro = 0.0
			var c = main.nearest_character(position, true)
			if c != null and (provoked or position.distance_to(c.position) < aggro):
				target = c
				_set_state("chase")
				if bool(data.get("stealth", false)) and c.controlled:
					main.message("A wildcat leaps out of hiding!")
			return float(data["speed"]) * (0.5 if bool(data.get("stealth", false)) else 1.0)
		"chase":
			if not _target_ok():
				return 0.0
			var to_t: Vector2 = target.position - position
			if to_t.length() > GIVE_UP or position.distance_to(home) > LEASH:
				_give_up()
				return float(data["speed"])
			dir = to_t.normalized()
			if to_t.length() < (64.0 if kind != "bear" else 80.0):
				_set_state("windup")
			return float(data["chase"])
		"windup":
			alert.visible = int(_state_t * 10.0) % 2 == 0
			dir = Vector2.ZERO
			if _target_ok() and target.position.distance_to(position) > 0.1:
				_lunge_dir = (target.position - position).normalized()
				sprite.flip_h = _lunge_dir.x < 0
			if _state_t >= float(data.get("windup", 0.45)):
				alert.visible = false
				_hit_done = false
				_set_state("lunge")
			return 0.0
		"lunge":
			dir = _lunge_dir
			if not _hit_done and _target_ok() and target.position.distance_to(position) < 26.0 + (8.0 if kind == "bear" else 0.0):
				_hit_done = true
				target.take_damage(float(data["damage"]), float(data.get("poison", 0.0)))
			if _state_t >= 0.28:
				_set_state("recover")
			return float(data["lunge"])
		"recover":
			dir = Vector2.ZERO
			if _state_t >= 0.8:
				_set_state("chase" if _target_ok() else "wander")
			return 0.0
	return 0.0


func _target_ok() -> bool:
	if target == null or not is_instance_valid(target) or target.downed or target.is_paddling():
		_give_up()
		return false
	if main.is_in_safe_zone(target.position):
		_give_up()
		return false
	return true


func _give_up() -> void:
	target = null
	provoked = false
	alert.visible = false
	_set_state("wander")
	dir = (home - position).normalized()


func _set_state(s: String) -> void:
	state = s
	_state_t = 0.0


func _step(step: Vector2) -> void:
	var moved := false
	var nx: Vector2 = position + Vector2(step.x, 0)
	if _can_stand(nx):
		position = nx
		moved = true
	var ny: Vector2 = position + Vector2(0, step.y)
	if _can_stand(ny):
		position = ny
		moved = true
	if not moved and state == "wander":
		_timer = 0.0
		dir = dir.rotated(randf_range(1.5, 4.7))


func _animate(speed: float) -> void:
	if absf(dir.x) > 0.1:
		sprite.flip_h = dir.x < 0
	var fast: bool = speed > 80.0
	sprite.position.y = -roundf(absf(sin(_anim * 12.0)) * 3.0) if fast else 0.0
	if dir != Vector2.ZERO:
		sprite.texture = Art.creature_frame(kind, int(_anim * (10.0 if fast else 5.0)) % 2)
	if state == "windup":
		sprite.position.x = sin(_anim * 60.0) * 1.5
	else:
		sprite.position.x = 0.0
	if bool(data.get("stealth", false)) and state == "wander" and _flash <= 0.0:
		sprite.modulate.a = 0.45
	elif _flash <= 0.0:
		sprite.modulate.a = 1.0


func _wander() -> void:
	if _timer <= 0.0:
		_timer = randf_range(1.0, 3.5)
		if randf() < 0.4:
			dir = Vector2.ZERO
		else:
			dir = Vector2.RIGHT.rotated(randf() * TAU)


func _draw_hp() -> void:
	if hp >= max_hp or not alive:
		return
	var w: float = 30.0
	if kind == "bear" or kind == "moose":
		w = 44.0
	elif kind == "elder_bear":
		w = 64.0
	hp_bar.draw_rect(Rect2(-w / 2, 0, w, 5), Color(0.13, 0.1, 0.16, 0.85))
	hp_bar.draw_rect(Rect2(-w / 2 + 1, 1, (w - 2) * float(hp) / float(max_hp), 3), Color(0.95, 0.3, 0.3))


func hit(damage: int, from_dir: Vector2, knockback: float = 6.0, attacker = null) -> void:
	if not alive or watch_only():
		return
	hp -= damage
	_flash = 0.15
	_flee_timer = 3.0
	_step(from_dir * knockback)
	hp_bar.queue_redraw()
	if is_predator():
		provoked = true
		if attacker != null and state == "wander":
			target = attacker
			_set_state("chase")
		elif state == "windup":
			_set_state("recover")  # a hit interrupts the wind-up
	if hp <= 0:
		_die()


func _die() -> void:
	alive = false
	alert.visible = false
	for d in data["drops"]:
		var amount: int = randi_range(int(d[1]), int(d[2]))
		if amount > 0:
			main.spawn_pickup(d[0], amount, position + Vector2(randf_range(-12, 12), randf_range(-8, 8)))
	main.roll_rare_drops(kind, position)
	if variant > 0:
		main.spawn_pickup(ItemDB.VARIANT_TROPHY[variant], 1, position + Vector2(0, -6))

	main.stats["kills"] = int(main.stats.get("kills", 0)) + 1
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
