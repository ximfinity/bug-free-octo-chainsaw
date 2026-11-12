extends Node2D
## The player's kayak. Lives in the world when parked; follows the player
## while paddled or carried. Uses 16 pre-rendered headings x 4 paddle strokes.

const Art = preload("res://scripts/art.gd")
const FX = preload("res://scripts/fx/fx.gd")

enum State { PARKED, OCCUPIED, CARRIED }

var state: int = State.PARKED
var hull_level: int = 0
## Facing angle in radians (0 = east, clockwise because screen y points down).
var heading: float = 0.0
## 0 = resting, otherwise 1..4 paddle stroke frame.
var stroke_frame: int = 0
var speed: float = 0.0
var sprite: Sprite2D
var wake: CPUParticles2D
var _t: float = 0.0


func _ready() -> void:
	sprite = Sprite2D.new()
	add_child(sprite)
	refresh()


func _enter_tree() -> void:
	# The wake lives in world space beside the kayak.
	if wake == null:
		wake = FX.make_wake()
		call_deferred("_attach_wake")


func _attach_wake() -> void:
	if wake and wake.get_parent() == null and get_parent():
		get_parent().add_child(wake)


func set_hull(level: int) -> void:
	hull_level = level
	refresh()


func set_state(s: int) -> void:
	state = s
	if state != State.OCCUPIED:
		stroke_frame = 0
		speed = 0.0
	refresh()


func refresh() -> void:
	if sprite == null:
		return
	visible = state != State.CARRIED
	var col: int = 0 if state == State.PARKED else maxi(1, stroke_frame)
	sprite.texture = Art.kayak_frame(hull_level, Art.heading_index(heading), col)


func _process(delta: float) -> void:
	_t += delta
	if sprite == null:
		return
	# Gentle bob on the water; a touch more when moving.
	var bob: float = sin(_t * 2.3) * (0.8 + minf(speed, 120.0) / 120.0 * 0.6)
	sprite.position = Vector2(0, roundf(bob))
	if wake:
		var moving: bool = state == State.OCCUPIED and speed > 25.0
		wake.emitting = moving
		var back := Vector2.from_angle(heading) * -20.0
		wake.global_position = global_position + back
		wake.rotation = heading
		wake.initial_velocity_max = 10.0 + minf(speed, 200.0) * 0.08


func ripple() -> void:
	if get_parent():
		FX.ripple(get_parent(), global_position, 26.0, 1.0)
