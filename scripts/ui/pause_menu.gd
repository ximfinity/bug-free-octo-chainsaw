extends Control
## Esc menu: resume, save, controls, quit.

const UI = preload("res://scripts/ui/ui_util.gd")

const CONTROLS := """WASD / Arrows / Left stick - move or paddle
Shift - sprint / power strokes (uses stamina)
E - get in / out of the kayak (or launch while carrying)
R - pick up / put down the kayak
Left click - melee attack     Right click or X - shoot bow
Space (hold) - chop, forage, till, plant, harvest, dig, revive
G - fish from the kayak, press again on a bite (!)
V - switch between Juniper and Rowan     T - call your partner over
C - pitch / pack up camp      F - trade, light fire, cook, sleep
Q - eat   Tab - pack & give items   J - creature journal   M - map   Esc - menu"""

var main
var content: VBoxContainer
var controls_label: Label


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Array = UI.modal("Paused", GameState.ui_theme)
	add_child(m[0])
	content = m[1]
	content.add_child(UI.button("Resume", func(): main.close_screen()))
	content.add_child(UI.button("Save Game", func():
		if main.save_game():
			main.message("Game saved.")
		main.close_screen()))
	content.add_child(UI.button("Toggle Fullscreen", func(): GameState.toggle_fullscreen()))
	content.add_child(UI.button("Save & Quit to Title", func():
		main.save_game()
		GameState.quit_to_title()))
	var vol_row := HBoxContainer.new()
	content.add_child(vol_row)
	vol_row.add_child(UI.label("Volume", 9))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	slider.custom_minimum_size = Vector2(300, 24)
	slider.value_changed.connect(func(v: float):
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))
		GameState.save_settings()
		Sfx.play("click"))
	vol_row.add_child(slider)
	content.add_child(HSeparator.new())
	content.add_child(UI.label("Tip: the bar at the bottom of the screen always shows what you can do.", 8, Color(1.0, 0.9, 0.6)))
	controls_label = UI.label(CONTROLS, 8, Color(0.85, 0.85, 0.8))
	content.add_child(controls_label)


func open() -> void:
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		main.close_screen()
