extends Control
## Corner minimap centred on the player, drawn from the exploration image.

const ZOOM := 4.0
const TILE := 32.0

var main


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.08, 0.06, 0.9))
	if main == null or main.exploration == null or main.player == null:
		return
	var ex = main.exploration
	var w = main.world
	var view_tiles: Vector2 = size / ZOOM
	var pt: Vector2 = main.player.position / TILE
	var origin: Vector2 = pt - view_tiles * 0.5
	origin.x = clampf(origin.x, 0.0, maxf(0.0, w.width - view_tiles.x))
	origin.y = clampf(origin.y, 0.0, maxf(0.0, w.height - view_tiles.y))
	draw_texture_rect_region(ex.texture, Rect2(Vector2.ZERO, size), Rect2(origin, view_tiles))
	# Markers
	for i in w.stores.size():
		var s: Vector2i = w.stores[i]
		if ex.is_discovered(s):
			_marker(Vector2(s) + Vector2(0.5, 0.5), origin, Color(0.2, 0.55, 1.0), 6.0)
	if main.camp != null:
		_marker(main.camp.position / TILE, origin, Color(1.0, 0.55, 0.15), 5.0)
	for idx in main.revealed_treasures:
		if not main.dug.has(idx):
			var tp: Vector2 = Vector2(idx % w.width, idx / w.width) + Vector2(0.5, 0.5)
			_cross(tp, origin, Color(0.9, 0.1, 0.1))
	if main.kayak != null and not main.player.is_paddling() and not main.player.is_carrying():
		_marker(main.kayak.position / TILE, origin, Color(1.0, 0.85, 0.2), 4.5)
	var other = main.partner_of(main.player)
	if other != null and not (other.is_paddling() and main.player.is_paddling()):
		_marker(other.position / TILE, origin, Color(1.0, 0.45, 0.4) if other.downed else Color(0.45, 0.9, 0.45), 4.5)
	for lm in w.landmarks:
		var lt: Vector2 = Vector2(lm["tile"]) + Vector2(0.5, 0.5)
		if bool(main.places.get("found", {}).get(lm["id"], false)):
			_marker(lt, origin, Color(0.37, 0.9, 0.85), 4.0)
		if main.quest_mark == lm["id"]:
			var qp: Vector2 = ((lt - origin) * ZOOM).clamp(Vector2(8, 8), size - Vector2(8, 8))
			var pulse: float = 6.0 + 2.5 * sin(Time.get_ticks_msec() / 200.0)
			draw_arc(qp, pulse, 0.0, TAU, 20, Color(1.0, 0.81, 0.25), 3.0)
	_marker(pt, origin, Color.WHITE, 5.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.8, 0.45), false, 3.0)


func _marker(tile_pos: Vector2, origin: Vector2, color: Color, r: float) -> void:
	var p: Vector2 = (tile_pos - origin) * ZOOM
	if p.x < -8 or p.y < -8 or p.x > size.x + 8 or p.y > size.y + 8:
		return
	draw_circle(p, r + 2.0, Color(0.13, 0.11, 0.17))
	draw_circle(p, r, color)


func _cross(tile_pos: Vector2, origin: Vector2, color: Color) -> void:
	var p: Vector2 = (tile_pos - origin) * ZOOM
	draw_line(p + Vector2(-6, -6), p + Vector2(6, 6), color, 3.0)
	draw_line(p + Vector2(-6, 6), p + Vector2(6, -6), color, 3.0)
