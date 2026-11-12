extends Control
## In-game HUD: stat bars, clock, coins, status, message feed, minimap and the
## on-screen action bar showing every action available right now.

const UI = preload("res://scripts/ui/ui_util.gd")
const Art = preload("res://scripts/art.gd")
const Minimap = preload("res://scripts/ui/minimap.gd")
const ActionBar = preload("res://scripts/ui/action_bar.gd")

var main
var bars: Control
var clock_label: Label
var coin_label: Label
var arrow_label: Label
var status_label: Label
var messages: VBoxContainer
var minimap: Control
var action_bar


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = GameState.ui_theme

	bars = Control.new()
	bars.position = Vector2(14, 14)
	bars.size = Vector2(260, 96)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.draw.connect(_draw_bars)
	add_child(bars)

	var top_panel := PanelContainer.new()
	UI.place(top_panel, 0.5, 0.0, 0.5, 0.0, -230, 10, 230, 58)
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_panel)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_panel.add_child(top)
	clock_label = UI.outlined("Day 1  08:00", 10)
	top.add_child(clock_label)
	top.add_child(VSeparator.new())
	top.add_child(UI.icon(Art.ICON_COIN, 11))
	coin_label = UI.outlined("0", 10, Color(1.0, 0.88, 0.4))
	top.add_child(coin_label)
	top.add_child(UI.icon(Art.ICON_ARROWS, 11))
	arrow_label = UI.outlined("0", 10)
	top.add_child(arrow_label)

	status_label = UI.outlined("", 9, Color(0.75, 0.88, 1.0))
	status_label.position = Vector2(16, 114)
	add_child(status_label)

	messages = VBoxContainer.new()
	UI.place(messages, 0.5, 1.0, 0.5, 1.0, -360, -260, 360, -110)
	messages.alignment = BoxContainer.ALIGNMENT_END
	messages.grow_vertical = Control.GROW_DIRECTION_BEGIN
	messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(messages)

	minimap = Minimap.new()
	UI.place(minimap, 1.0, 0.0, 1.0, 0.0, -226, 14, -14, 226)
	add_child(minimap)

	action_bar = ActionBar.new()
	add_child(action_bar)


func setup(main_node) -> void:
	main = main_node
	minimap.main = main_node
	action_bar.main = main_node


func _process(_delta: float) -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	clock_label.text = main.day_night.clock_text()
	coin_label.text = str(p.coins)
	arrow_label.text = str(p.inventory.count("arrows"))
	var status := ""
	if p.cold:
		status = "Freezing! Light a campfire."
	elif main.day_night.is_night() and not main.is_in_safe_zone(p.position):
		status = "It's dark and cold..."
	elif main.day_night.is_evening() and not main.day_night.is_night():
		status = "Night is coming - make camp."
	if p.hunger < 20.0:
		status += ("  " if status != "" else "") + "Starving!"
	status_label.text = status
	bars.queue_redraw()
	minimap.queue_redraw()


func _draw_bars() -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	bars.draw_rect(Rect2(0, 0, 260, 96), Color(0.13, 0.11, 0.17, 0.75))
	bars.draw_rect(Rect2(0, 0, 260, 96), Color(1.0, 0.8, 0.45, 0.9), false, 2.0)
	_bar(10, "HP", p.health, Color(0.94, 0.33, 0.33))
	_bar(38, "Food", p.hunger, Color(1.0, 0.65, 0.2))
	_bar(66, "Stam", p.stamina, Color(0.4, 0.84, 0.42))


func _bar(y: float, title: String, value: float, color: Color) -> void:
	var font: Font = get_theme_default_font()
	var x0: float = 74.0
	var w: float = 174.0
	bars.draw_rect(Rect2(x0, y, w, 20), Color(0.1, 0.08, 0.13, 0.9))
	bars.draw_rect(Rect2(x0 + 2, y + 2, (w - 4) * clampf(value / 100.0, 0.0, 1.0), 16), color)
	bars.draw_rect(Rect2(x0 + 2, y + 2, (w - 4) * clampf(value / 100.0, 0.0, 1.0), 5), color.lightened(0.3))
	bars.draw_string_outline(font, Vector2(10, y + 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.1, 0.08, 0.13))
	bars.draw_string(font, Vector2(10, y + 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)


func message(text: String) -> void:
	# Don't repeat the same line back to back.
	if messages.get_child_count() > 0:
		var last := messages.get_child(messages.get_child_count() - 1) as Label
		if last and last.text == text and last.modulate.a > 0.5:
			return
	var l := UI.outlined(text, 10)
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
