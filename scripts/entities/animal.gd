extends Node2D
## Wildlife. Prey wander and flee; wolves hunt the player at night.

const Art = preload("res://scripts/art.gd")
const Tiles = preload("res://scripts/world/tiles.gd")

const KINDS := {
	"rabbit": {"hp": 1, "speed": 60.0, "flee_speed": 170.0, "water": false,
		"drops": [["meat_raw", 1, 1], ["hide", 0, 1]]},
	"deer": {"hp": 3, "speed": 52.0, "flee_speed": 156.0, "water": false,
		"drops": [["meat_raw", 2, 3], ["hide", 1, 2]]},
	"duck": {"hp": 1, "speed": 32.0, "flee_speed": 96.0, "water": true,
		"drops": [["meat_raw", 1, 1]]},
	"wolf": {"hp": 3, "speed": 60.0, "flee_speed": 150.0, "water": false,
		"drops": [["hide", 1, 2]], "predator": true},
}
const FLEE_RADIUS := 144.0
const CHASE_RADIUS := 300.0
const BITE_DAMAGE := 12.0

var kind: String = "rabbit"
var main
var hp: int = 1
var alive: bool = true
var leaving: bool = false
var dir: Vector2 = Vector2.ZERO
var _timer: float = 0.0
var _flee_timer: float = 0.0
var _attack_cd: float = 0.0
var _flash: float = 0.0
var _anim: float = 0.0
var sprite: Sprite2D
var data: Dictionary


func _ready() -> void:
	add_to_group("animals")
	data = KINDS[kind]
	hp = int(data["hp"])
	sprite = Sprite2D.new()
	sprite.texture = Art.creature_frame(kind, 0)
	sprite.offset = Vector2(0, -20)
	add_child(sprite)
	_timer = randf_range(0.5, 2.0)


func is_predator() -> bool:
	return bool(data.get("predator", false))


func _can_stand(p: Vector2) -> bool:
	var t: int = main.world.tile_type_at_pos(p)
	if bool(data["water"]):
		return t == Tiles.DEEP or t == Tiles.SHALLOW
	return Tiles.walk_ok(t) and t != Tiles.SHALLOW


func _process(delta: float) -> void:
	if not alive or main == null:
		return
	_anim += delta
	_attack_cd -= delta
	_timer -= delta
	_flee_timer -= delta
	if _flash > 0.0:
		_flash -= delta
		sprite.modulate = Color(1, 0.4, 0.4) if _flash > 0.0 else Color.WHITE
	var player = main.player
	var to_player: Vector2 = player.position - position
	var dist: float = to_player.length()
	var speed: float = float(data["speed"])

	if is_predator():
		var player_on_land: bool = not player.is_paddling()
		var safe: bool = main.is_in_safe_zone(player.position)
		if leaving or main.is_in_safe_zone(position):
			dir = -to_player.normalized() if dist > 0.1 else Vector2.RIGHT
			speed = float(data["flee_speed"])
		elif dist < CHASE_RADIUS and player_on_land and not safe:
			dir = to_player.normalized()
			speed = float(data["flee_speed"]) * 0.85
			if dist < 24.0 and _attack_cd <= 0.0:
				player.take_damage(BITE_DAMAGE)
				_attack_cd = 1.1
		else:
			_wander()
	else:
		if dist < FLEE_RADIUS:
			_flee_timer = 1.5
		if _flee_timer > 0.0:
			dir = -to_player.normalized() if dist > 0.1 else Vector2.RIGHT
			speed = float(data["flee_speed"])
		else:
			_wander()

	if dir != Vector2.ZERO:
		var step: Vector2 = dir * speed * delta
		var moved := false
		var nx: Vector2 = position + Vector2(step.x, 0)
		if _can_stand(nx):
			position = nx
			moved = true
		var ny: Vector2 = position + Vector2(0, step.y)
		if _can_stand(ny):
			position = ny
			moved = true
		if not moved:
			_timer = 0.0
			dir = dir.rotated(randf_range(1.5, 4.7))
		if absf(dir.x) > 0.1:
			sprite.flip_h = dir.x < 0
		sprite.position.y = -roundf(absf(sin(_anim * 12.0)) * 3.0) if speed > 80.0 else 0.0
		sprite.texture = Art.creature_frame(kind, int(_anim * (10.0 if speed > 80.0 else 5.0)) % 2)


func _wander() -> void:
	if _timer <= 0.0:
		_timer = randf_range(1.0, 3.5)
		if randf() < 0.4:
			dir = Vector2.ZERO
		else:
			dir = Vector2.RIGHT.rotated(randf() * TAU)


func hit(damage: int, from_dir: Vector2) -> void:
	if not alive:
		return
	hp -= damage
	_flash = 0.15
	_flee_timer = 3.0
	position += from_dir * 6.0
	if hp <= 0:
		_die()


func _die() -> void:
	alive = false
	for d in data["drops"]:
		var amount: int = randi_range(int(d[1]), int(d[2]))
		if amount > 0:
			main.spawn_pickup(d[0], amount, position + Vector2(randf_range(-12, 12), randf_range(-8, 8)))
	main.stats["kills"] = int(main.stats.get("kills", 0)) + 1
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.4)
	tw.tween_callback(queue_free)
