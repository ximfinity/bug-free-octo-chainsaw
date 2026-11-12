extends Control
## Bottom-centre bar listing every action available right now, each with its
## key (or gamepad button) glyph. Fed by main.available_actions(), which
## returns an Array of [action_name, label]. Switches between keyboard and
## gamepad glyphs based on the last device used.

const UI = preload("res://scripts/ui/ui_util.gd")

const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_RIGHT: "D-Right",
	JOY_BUTTON_DPAD_LEFT: "D-Left",
}
const PAD_COLORS := {
	"A": Color(0.33, 0.75, 0.35), "B": Color(0.9, 0.32, 0.3),
	"X": Color(0.3, 0.55, 0.95), "Y": Color(0.98, 0.78, 0.2),
}

var main
var row: HBoxContainer
var use_pad: bool = false
var _sig: String = ""
var _timer: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(self, 0.0, 1.0, 1.0, 1.0, 0, -86, 0, -14)
	var center := CenterContainer.new()
	UI.place(center, 0, 0, 1, 1, 0, 0, 0, 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(panel)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)


func _input(event: InputEvent) -> void:
	var pad: bool = use_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != use_pad:
		use_pad = pad
		_sig = ""


func _process(delta: float) -> void:
	if main == null or not main.ready_done:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.12
	var actions: Array = main.available_actions()
	var sig: String = str(use_pad) + str(actions)
	if sig == _sig:
		return
	_sig = sig
	UI.clear_children(row)
	for a in actions:
		row.add_child(_entry(str(a[0]), str(a[1])))


func _entry(action: String, text: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_glyph(action))
	var l := UI.outlined(text, 9, Color(1.0, 0.97, 0.88))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	return hb


func _glyph(action: String) -> Control:
	var text: String = glyph_text(action)
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	var circle: bool = use_pad and PAD_COLORS.has(text)
	if circle:
		sb.bg_color = PAD_COLORS[text]
		sb.set_corner_radius_all(16)
		sb.border_color = PAD_COLORS[text].darkened(0.4)
	else:
		sb.bg_color = Color(0.98, 0.95, 0.86)
		sb.set_corner_radius_all(6)
		sb.border_color = Color(0.55, 0.47, 0.4)
	sb.set_border_width_all(2)
	sb.border_width_bottom = 5
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 2
	sb.content_margin_bottom = 3
	pc.add_theme_stylebox_override("panel", sb)
	var l := UI.label(text, 8, Color.WHITE if circle else Color(0.2, 0.16, 0.24))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc


## Text for an action's first binding on the current device.
func glyph_text(action: String) -> String:
	if action == "move":
		return "L-Stick" if use_pad else "WASD"
	if action == "shoot" and use_pad:
		action = "shoot_key"
	if action == "sprint" and use_pad:
		return "RT"
	if not InputMap.has_action(action):
		return action
	for ev in InputMap.action_get_events(action):
		if use_pad and ev is InputEventJoypadButton:
			return str(PAD_NAMES.get((ev as InputEventJoypadButton).button_index, "Btn"))
		if not use_pad and ev is InputEventKey:
			var k: InputEventKey = ev
			var code: int = k.physical_keycode if k.physical_keycode != 0 else k.keycode
			return OS.get_keycode_string(code)
		if not use_pad and ev is InputEventMouseButton:
			return "L-Click" if (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT else "R-Click"
	return "?"
