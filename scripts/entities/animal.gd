extends Node2D
## Wildlife.
## Prey (rabbit, deer, duck) wander and flee.
## Predators (wolf, spider, wildcat, bear) notice you, telegraph an attack
## with a red "!" wind-up, lunge, then recover - so you can dodge, run, or
## strike first. They give up when you get far enough away, can't follow you
## into deep water, and won't come near a lit campfire.

const Art = preload("res://scripts/art.gd")
const Tiles = preload("res://scripts/world/tiles.gd")

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
}
const FLEE_RADIUS := 144.0
const LEASH := 32.0 * 16
const GIVE_UP := 32.0 * 13

var kind: String = "rabbit"
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


func _ready() -> void:
	add_to_group("animals")
	data = KINDS[kind]
	hp = int(data["hp"])
	max_hp = hp
	home = position
	sprite = Sprite2D.new()
	sprite.texture = Art.creature_frame(kind, 0)
	sprite.offset = Vector2(0, -20)
	if kind == "bear":
		sprite.scale = Vector2(1.25, 1.25)
		sprite.offset = Vector2(0, -19)
	add_child(sprite)
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


## Can this animal hurt the player right now? (Used by partner AI / HUD.)
func is_threat() -> bool:
	return alive and is_predator() and not leaving and (state == "chase" or state == "windup" or state == "lunge")


func _can_stand(p: Vector2) -> bool:
	var t: int = main.world.tile_type_at_pos(p)
	match int(data["swim"]):
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
	var speed: float = float(data["speed"])
	if is_predator():
		speed = _predator(delta)
	else:
		speed = _prey()
	if dir != Vector2.ZERO and speed > 0.0:
		_step(dir * speed * delta)
	_animate(speed)


func _prey() -> float:
	var c = main.nearest_character(position)
	var to_c: Vector2 = c.position - position if c != null else Vector2(9999, 0)
	if to_c.length() < FLEE_RADIUS:
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
	var w: float = 30.0 if kind != "bear" else 44.0
	hp_bar.draw_rect(Rect2(-w / 2, 0, w, 5), Color(0.13, 0.1, 0.16, 0.85))
	hp_bar.draw_rect(Rect2(-w / 2 + 1, 1, (w - 2) * float(hp) / float(max_hp), 3), Color(0.95, 0.3, 0.3))


func hit(damage: int, from_dir: Vector2, knockback: float = 6.0, attacker = null) -> void:
	if not alive:
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
	main.stats["kills"] = int(main.stats.get("kills", 0)) + 1
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
