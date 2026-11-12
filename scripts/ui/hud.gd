extends Control
## In-game HUD: stat bars, clock, coins, context hint, message feed, minimap.

const UI = preload("res://scripts/ui/ui_util.gd")
const Art = preload("res://scripts/art.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")

var main
var bars: Control
var clock_label: Label
var coin_label: Label
var arrow_label: Label
var status_label: Label
var hint_label: Label
var messages: VBoxContainer
var minimap: Control


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = GameState.ui_theme

	bars = Control.new()
	bars.position = Vector2(6, 6)
	bars.custom_minimum_size = Vector2(110, 40)
	bars.size = Vector2(110, 40)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.draw.connect(_draw_bars)
	add_child(bars)

	var top := HBoxContainer.new()
	UI.place(top, 0.5, 0.0, 0.5, 0.0, -110, 4, 110, 20)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	clock_label = UI.outlined("Day 1  08:00", 10)
	top.add_child(clock_label)
	top.add_child(UI.icon(Art.COIN, 12))
	coin_label = UI.outlined("0", 10, Color(1.0, 0.88, 0.4))
	top.add_child(coin_label)
	var ai := UI.icon(22, 12)
	top.add_child(ai)
	arrow_label = UI.outlined("0", 10)
	top.add_child(arrow_label)

	status_label = UI.outlined("", 9, Color(0.7, 0.85, 1.0))
	status_label.position = Vector2(6, 48)
	add_child(status_label)

	hint_label = UI.outlined("", 9, Color(1.0, 0.95, 0.75))
	UI.place(hint_label, 0.0, 1.0, 0.0, 1.0, 6, -18, 420, -4)
	add_child(hint_label)

	messages = VBoxContainer.new()
	UI.place(messages, 0.5, 1.0, 0.5, 1.0, -160, -90, 160, -24)
	messages.alignment = BoxContainer.ALIGNMENT_END
	messages.grow_vertical = Control.GROW_DIRECTION_BEGIN
	messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(messages)

	minimap = Minimap.new()
	UI.place(minimap, 1.0, 0.0, 1.0, 0.0, -110, 6, -6, 110)
	add_child(minimap)

	var help := UI.outlined("M map   Tab bag   Esc menu", 8, Color(0.85, 0.85, 0.85))
	UI.place(help, 1.0, 0.0, 1.0, 0.0, -112, 112, -4, 124)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(help)


func setup(main_node) -> void:
	main = main_node
	minimap.main = main_node


func _process(_delta: float) -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	clock_label.text = main.day_night.clock_text()
	coin_label.text = str(p.coins)
	arrow_label.text = str(p.inventory.count("arrows"))
	var status := ""
	if p.cold:
		status = "Freezing! Light a campfire (C)."
	elif main.day_night.is_night() and not main.is_in_safe_zone(p.position):
		status = "It's dark and cold..."
	elif main.day_night.is_evening() and not main.day_night.is_night():
		status = "Night is coming - make camp."
	if p.hunger < 20.0:
		status += ("  " if status != "" else "") + "Starving!"
	status_label.text = status
	hint_label.text = main.context_hint()
	bars.queue_redraw()
	minimap.queue_redraw()


func _draw_bars() -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	_bar(0, "HP", p.health, Color(0.86, 0.22, 0.2))
	_bar(13, "Food", p.hunger, Color(0.92, 0.58, 0.18))
	_bar(26, "Stam", p.stamina, Color(0.3, 0.75, 0.35))


func _bar(y: float, title: String, value: float, color: Color) -> void:
	var font: Font = get_theme_default_font()
	bars.draw_rect(Rect2(28, y, 80, 9), Color(0, 0, 0, 0.6))
	bars.draw_rect(Rect2(29, y + 1, 78.0 * clampf(value / 100.0, 0.0, 1.0), 7), color)
	bars.draw_string_outline(font, Vector2(0, y + 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, 3, Color.BLACK)
	bars.draw_string(font, Vector2(0, y + 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)


func message(text: String) -> void:
	# Don't repeat the same line back to back.
	if messages.get_child_count() > 0:
		var last := messages.get_child(messages.get_child_count() - 1) as Label
		if last and last.text == text and last.modulate.a > 0.5:
			return
	var l := UI.outlined(text, 9)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages.add_child(l)
	while messages.get_child_count() > 4:
		var old := messages.get_child(0)
		messages.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)
