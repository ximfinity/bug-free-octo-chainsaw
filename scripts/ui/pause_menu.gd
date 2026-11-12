extends Control
## Esc menu: resume, save, controls, quit.

const UI = preload("res://scripts/ui/ui_util.gd")

const CONTROLS := """WASD / Arrows / Left stick - move or paddle
Shift - sprint / power strokes (uses stamina)
E - get in / out of the kayak (or launch while carrying)
R - pick up / put down the kayak
Left click or X - shoot bow (needs arrows)
Space (hold) - chop trees / dig with a shovel
G - fish from the kayak, press again on a bite (!)
C - pitch / pack up camp      F - trade, light fire, cook, sleep
Q - eat      Tab - pack & crafting      M - map      Esc - menu"""

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
	content.add_child(HSeparator.new())
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
