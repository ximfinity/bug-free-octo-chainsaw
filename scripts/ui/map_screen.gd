extends Control
## Full-screen exploration map (M). Mouse wheel zooms, drag pans.

const UI = preload("res://scripts/ui/ui_util.gd")

var main
var zoom: float = 1.0
var center: Vector2 = Vector2.ZERO # in tiles
var _dragging: bool = false
var info: Label


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	theme = GameState.ui_theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	info = UI.outlined("", 9)
	UI.place(info, 0, 1, 1, 1, 16, -60, -16, -8)
	add_child(info)


func open() -> void:
	visible = true
	zoom = 1.0
	center = main.player.position / 32.0
	queue_redraw()


func _fit_scale() -> float:
	var w = main.world
	return minf((size.x - 40.0) / w.width, (size.y - 100.0) / w.height)


func _map_rect_origin() -> Vector2:
	var s: float = _fit_scale() * zoom
	var w = main.world
	if zoom <= 1.0:
		return (size - Vector2(w.width, w.height) * s) * 0.5 + Vector2(0, -20)
	return size * 0.5 - center * s


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.5, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1.0 / 1.5, mb.position)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging and zoom > 1.0:
		var mm := event as InputEventMouseMotion
		center -= mm.relative / (_fit_scale() * zoom)
		queue_redraw()


func _zoom_at(factor: float, at: Vector2) -> void:
	var s: float = _fit_scale() * zoom
	var tile_under: Vector2 = (at - _map_rect_origin()) / s
	zoom = clampf(zoom * factor, 1.0, 8.0)
	if zoom > 1.0:
		center = tile_under
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("map") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		main.close_screen()
	elif event.is_action_pressed("ui_page_up"):
		_zoom_at(1.5, size * 0.5)
	elif event.is_action_pressed("ui_page_down"):
		_zoom_at(1.0 / 1.5, size * 0.5)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.11, 0.17, 0.97))
	if main == null:
		return
	var w = main.world
	var ex = main.exploration
	ex.flush()
	var s: float = _fit_scale() * zoom
	var o: Vector2 = _map_rect_origin()
	var rect := Rect2(o, Vector2(w.width, w.height) * s)
	draw_texture_rect(ex.texture, rect, false)
	draw_rect(rect, Color(1.0, 0.8, 0.45), false, 3.0)
	var font: Font = get_theme_default_font()
	for i in w.stores.size():
		var st: Vector2i = w.stores[i]
		if ex.is_discovered(st):
			var p: Vector2 = o + (Vector2(st) + Vector2(0.5, 0.5)) * s
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color(0.2, 0.55, 1.0))
			draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color.BLACK, false, 1.0)
			if zoom >= 2.0:
				draw_string_outline(font, p + Vector2(10, -6), "100's of Kayaks", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color.BLACK)
				draw_string(font, p + Vector2(10, -6), "100's of Kayaks", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.9, 1.0))
	for idx in main.revealed_treasures:
		if main.dug.has(idx):
			continue
		var tp: Vector2 = o + (Vector2(idx % w.width, idx / w.width) + Vector2(0.5, 0.5)) * s
		draw_line(tp + Vector2(-8, -8), tp + Vector2(8, 8), Color(0.9, 0.1, 0.1), 4.0)
		draw_line(tp + Vector2(-8, 8), tp + Vector2(8, -8), Color(0.9, 0.1, 0.1), 4.0)
	if main.camp != null:
		var cp: Vector2 = o + main.camp.position / 32.0 * s
		draw_circle(cp, 8.0, Color.BLACK)
		draw_circle(cp, 6.0, Color(1.0, 0.55, 0.15))
	if not main.player.is_paddling() and not main.player.is_carrying():
		var kp: Vector2 = o + main.kayak.position / 32.0 * s
		draw_circle(kp, 7.0, Color.BLACK)
		draw_circle(kp, 5.0, Color(1.0, 0.85, 0.2))
	for lm in w.landmarks:
		var lp: Vector2 = o + (Vector2(lm["tile"]) + Vector2(0.5, 0.5)) * s
		var known: bool = bool(main.places.get("found", {}).get(lm["id"], false))
		if known:
			draw_circle(lp, 7.0, Color.BLACK)
			draw_circle(lp, 5.0, Color(0.37, 0.9, 0.85))
			draw_string_outline(font, lp + Vector2(10, 5), str(lm["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color.BLACK)
			draw_string(font, lp + Vector2(10, 5), str(lm["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.7, 1.0, 0.95))
		if main.quest_mark == lm["id"]:
			var pr: float = 12.0 + 4.0 * sin(Time.get_ticks_msec() / 200.0)
			draw_arc(lp, pr, 0.0, TAU, 28, Color(1.0, 0.81, 0.25), 3.0)
			if not known:
				draw_string_outline(font, lp + Vector2(16, 5), "Trail: look here", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 5, Color.BLACK)
				draw_string(font, lp + Vector2(16, 5), "Trail: look here", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.9, 0.5))
	var other = main.partner_of(main.player)
	if other != null and not (other.is_paddling() and main.player.is_paddling()):
		var op: Vector2 = o + other.position / 32.0 * s
		draw_circle(op, 7.0, Color.BLACK)
		draw_circle(op, 5.0, Color(0.45, 0.9, 0.45))
	var pp: Vector2 = o + main.player.position / 32.0 * s
	var blink: bool = int(Time.get_ticks_msec() / 400) % 2 == 0
	draw_circle(pp, 8.0, Color.BLACK)
	draw_circle(pp, 6.0, Color.WHITE if blink else Color(1.0, 0.3, 0.3))
	info.text = "Explored %.1f%%    Blue: 100's of Kayaks   Yellow: kayak   Orange: camp   Red X: treasure    Wheel: zoom   Drag: pan   M: close" % ex.percent()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
