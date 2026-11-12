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
	UI.place(info, 0, 1, 1, 1, 8, -30, -8, -4)
	add_child(info)


func open() -> void:
	visible = true
	zoom = 1.0
	center = main.player.position / 16.0
	queue_redraw()


func _fit_scale() -> float:
	var w = main.world
	return minf((size.x - 20.0) / w.width, (size.y - 50.0) / w.height)


func _map_rect_origin() -> Vector2:
	var s: float = _fit_scale() * zoom
	var w = main.world
	if zoom <= 1.0:
		return (size - Vector2(w.width, w.height) * s) * 0.5 + Vector2(0, -10)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.1, 0.08, 0.96))
	if main == null:
		return
	var w = main.world
	var ex = main.exploration
	ex.flush()
	var s: float = _fit_scale() * zoom
	var o: Vector2 = _map_rect_origin()
	var rect := Rect2(o, Vector2(w.width, w.height) * s)
	draw_texture_rect(ex.texture, rect, false)
	draw_rect(rect, Color(0.85, 0.72, 0.42), false, 1.0)
	var font: Font = get_theme_default_font()
	for i in w.stores.size():
		var st: Vector2i = w.stores[i]
		if ex.is_discovered(st):
			var p: Vector2 = o + (Vector2(st) + Vector2(0.5, 0.5)) * s
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(0.2, 0.55, 1.0))
			draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color.BLACK, false, 1.0)
			if zoom >= 2.0:
				draw_string_outline(font, p + Vector2(5, -3), "100's of Kayaks", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color.BLACK)
				draw_string(font, p + Vector2(5, -3), "100's of Kayaks", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.75, 0.9, 1.0))
	for idx in main.revealed_treasures:
		if main.dug.has(idx):
			continue
		var tp: Vector2 = o + (Vector2(idx % w.width, idx / w.width) + Vector2(0.5, 0.5)) * s
		draw_line(tp + Vector2(-4, -4), tp + Vector2(4, 4), Color(0.9, 0.1, 0.1), 2.0)
		draw_line(tp + Vector2(-4, 4), tp + Vector2(4, -4), Color(0.9, 0.1, 0.1), 2.0)
	if main.camp != null:
		var cp: Vector2 = o + main.camp.position / 16.0 * s
		draw_circle(cp, 4.0, Color.BLACK)
		draw_circle(cp, 3.0, Color(1.0, 0.55, 0.15))
	if not main.player.is_paddling() and not main.player.is_carrying():
		var kp: Vector2 = o + main.kayak.position / 16.0 * s
		draw_circle(kp, 3.5, Color.BLACK)
		draw_circle(kp, 2.5, Color(1.0, 0.85, 0.2))
	var pp: Vector2 = o + main.player.position / 16.0 * s
	var blink: bool = int(Time.get_ticks_msec() / 400) % 2 == 0
	draw_circle(pp, 4.0, Color.BLACK)
	draw_circle(pp, 3.0, Color.WHITE if blink else Color(1.0, 0.3, 0.3))
	info.text = "Explored %.1f%%    Blue: 100's of Kayaks   Yellow: kayak   Orange: camp   Red X: treasure    Wheel: zoom   Drag: pan   M: close" % ex.percent()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()
