extends Node
## Global state: input map, UI theme, settings, new-game options, save files.

const SAVE_PATH := "user://savegame.json"
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_VERSION := 1

const WORLD_SIZES := {"Small": 320, "Medium": 448, "Large": 576}

## Keyboard / mouse / gamepad bindings, created at startup so the project
## file stays readable. Key = action, value = list of events.
const KEYS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"board": [KEY_E],
	"carry": [KEY_R],
	"interact": [KEY_F],
	"use_tool": [KEY_SPACE],
	"fish": [KEY_G],
	"camp": [KEY_C],
	"eat": [KEY_Q],
	"map": [KEY_M],
	"inventory": [KEY_TAB, KEY_I],
	"pause": [KEY_ESCAPE],
	"shoot_key": [KEY_X],
	"switch_character": [KEY_V],
	"call_partner": [KEY_T],
}
const PAD_BUTTONS := {
	"board": [JOY_BUTTON_X],
	"carry": [JOY_BUTTON_Y],
	"interact": [JOY_BUTTON_A],
	"use_tool": [JOY_BUTTON_B],
	"fish": [JOY_BUTTON_LEFT_SHOULDER],
	"shoot_key": [JOY_BUTTON_LEFT_STICK],
	"attack": [JOY_BUTTON_RIGHT_SHOULDER],
	"switch_character": [JOY_BUTTON_DPAD_LEFT],
	"call_partner": [JOY_BUTTON_RIGHT_STICK],
	"camp": [JOY_BUTTON_DPAD_DOWN],
	"eat": [JOY_BUTTON_DPAD_UP],
	"map": [JOY_BUTTON_BACK],
	"inventory": [JOY_BUTTON_DPAD_RIGHT],
	"pause": [JOY_BUTTON_START],
}

var new_game_seed: int = 0
var new_game_size: int = 448
var pending_load: Dictionary = {}
var fullscreen: bool = false
var ui_theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	ui_theme = _make_theme()
	_load_settings()


func _setup_input() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in PAD_BUTTONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)
	# Left click = melee, right click = bow (aims at the mouse).
	for pair in [["attack", MOUSE_BUTTON_LEFT], ["shoot", MOUSE_BUTTON_RIGHT]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)
	# Sprint on the gamepad: right trigger.
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("sprint", rt)
	var axes := {
		"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
	}
	for action in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = axes[action][0]
		jm.axis_value = axes[action][1]
		InputMap.action_add_event(action, jm)
		InputMap.action_set_deadzone(action, 0.25)


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.09, 0.13, 0.92)
	panel.border_color = Color(0.85, 0.72, 0.42)
	panel.bg_color = Color(0.13, 0.11, 0.17, 0.93)
	panel.border_color = Color(1.0, 0.8, 0.45)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(8)
	panel.set_content_margin_all(14)
	panel.shadow_color = Color(0, 0, 0, 0.35)
	panel.shadow_size = 6
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "TabContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.17, 0.56, 0.6)
	normal.border_color = Color(0.09, 0.33, 0.37)
	normal.set_border_width_all(2)
	normal.border_width_bottom = 4
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 4
	normal.content_margin_bottom = 6
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.25, 0.68, 0.72)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.12, 0.42, 0.46)
	pressed.border_width_bottom = 2
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.2, 0.2, 0.22)
	var focus := normal.duplicate() as StyleBoxFlat
	focus.bg_color = Color(0, 0, 0, 0)
	focus.border_color = Color(1.0, 0.85, 0.4)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", Color(0.95, 0.95, 0.9))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.55, 0.55))
	t.set_color("font_color", "Label", Color(0.95, 0.93, 0.86))
	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_font_size("font_size", "TabContainer", 20)
	return t


# ------------------------------------------------------------------ settings
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		fullscreen = bool(cfg.get_value("display", "fullscreen", false))
		var vol: float = float(cfg.get_value("audio", "master", 1.0))
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	apply_fullscreen()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("audio", "master", db_to_linear(AudioServer.get_bus_volume_db(0)))
	cfg.save(SETTINGS_PATH)


func apply_fullscreen() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply_fullscreen()
	save_settings()


# --------------------------------------------------------------------- saves
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func write_save(data: Dictionary) -> bool:
	data["version"] = SAVE_VERSION
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write save: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


func read_save() -> Dictionary:
	if not has_save():
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func start_new_game(seed_value: int, size: int) -> void:
	new_game_seed = seed_value
	new_game_size = size
	pending_load = {}
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func continue_game() -> void:
	var data := read_save()
	if data.is_empty():
		return
	pending_load = data
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func quit_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/title.tscn")
