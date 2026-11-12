extends Node2D
## A flying arrow. Hits the first animal it touches, stops at mountains.

const Art = preload("res://scripts/art.gd")
const Tiles = preload("res://scripts/world/tiles.gd")
const SPEED := 560.0
const LIFETIME := 0.85

var direction: Vector2 = Vector2.RIGHT
var main
var shooter = null
var _t: float = 0.0


func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = Art.prop(Art.ARROW)
	s.scale = Vector2(0.6, 0.6)
	add_child(s)
	rotation = direction.angle()


func _process(delta: float) -> void:
	_t += delta
	if _t > LIFETIME:
		queue_free()
		return
	position += direction * SPEED * delta
	var t: int = main.world.tile_type_at_pos(position)
	if t == Tiles.MOUNTAIN or t == Tiles.SNOW:
		queue_free()
		return
	for a in get_tree().get_nodes_in_group("animals"):
		if a.alive and a.position.distance_to(position + Vector2(0, 12)) < 20.0:
			a.hit(2 if a.kind == "bear" else 1, direction, 6.0, shooter)
			queue_free()
			return
