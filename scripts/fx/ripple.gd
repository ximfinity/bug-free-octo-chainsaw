extends Node2D
## An expanding, fading ring on the water surface.

var max_radius: float = 18.0
var life: float = 0.9
var _t: float = 0.0


func _ready() -> void:
	z_index = -5


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var f: float = _t / life
	var r: float = 3.0 + (max_radius - 3.0) * f
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, Color(0.95, 1.0, 1.0, 0.7 * (1.0 - f)), 1.5)
	draw_arc(Vector2.ZERO, r * 0.6, 0.0, TAU, 20, Color(0.95, 1.0, 1.0, 0.4 * (1.0 - f)), 1.0)
