extends Control
## A simple conversation panel: speaker portrait, name, pages of text.

const UI = preload("res://scripts/ui/ui_util.gd")
const Art = preload("res://scripts/art.gd")

var main
var pages: Array = []
var page: int = 0
var on_done: Callable
var name_label: Label
var text_label: Label
var portrait: TextureRect
var next_btn: Button


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = GameState.ui_theme
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	UI.place(dim, 0, 0, 1, 1, 0, 0, 0, 0)
	add_child(dim)
	var panel := PanelContainer.new()
	UI.place(panel, 0.5, 1.0, 0.5, 1.0, -430, -250, 430, -100)
	add_child(panel)
	var hb := HBoxContainer.new()
	panel.add_child(hb)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(96, 120)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hb.add_child(portrait)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	name_label = UI.label("", 11, Color(1.0, 0.85, 0.45))
	vb.add_child(name_label)
	text_label = UI.label("", 10)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(680, 70)
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(text_label)
	next_btn = UI.button("Continue (F)", _next)
	next_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	vb.add_child(next_btn)


func start(speaker: String, portrait_cell: int, lines: Array, done: Callable) -> void:
	pages = lines
	page = 0
	on_done = done
	name_label.text = speaker
	var tex := AtlasTexture.new()
	tex.atlas = Art.LANDMARKS
	tex.region = Rect2((portrait_cell % 8) * 128 + 44, (portrait_cell / 8) * 128 + 62, 40, 52)
	portrait.texture = tex
	_show()


func open() -> void:
	visible = true


func _show() -> void:
	text_label.text = str(pages[page]) if page < pages.size() else ""
	next_btn.text = "Continue (F)" if page < pages.size() - 1 else "Farewell (F)"


func _next() -> void:
	page += 1
	if page >= pages.size():
		main.close_screen()
		if on_done.is_valid():
			on_done.call()
		return
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("use_tool") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_next()
