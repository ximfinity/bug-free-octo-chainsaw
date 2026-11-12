extends Node2D
## The player's kayak. Lives in the world when parked; follows the player
## while paddled or carried.

const Art = preload("res://scripts/art.gd")

enum State { PARKED, OCCUPIED, CARRIED }

var state: int = State.PARKED
var hull_level: int = 0
var paddle_frame: int = 1
var sprite: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	refresh()


func set_hull(level: int) -> void:
	hull_level = level
	refresh()


func set_state(s: int) -> void:
	state = s
	refresh()


func refresh() -> void:
	if sprite == null:
		return
	visible = state != State.CARRIED
	var col: int = 0 if state == State.PARKED else paddle_frame
	sprite.texture = Art.kayak_frame(hull_level, col)
