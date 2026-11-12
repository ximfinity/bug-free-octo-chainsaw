extends Control
## Title screen: new game (seed + world size), continue, fullscreen, quit.

const UI = preload("res://scripts/ui/ui_util.gd")
const Art = preload("res://scripts/art.gd")

var seed_edit: LineEdit
var size_option: OptionButton
var continue_btn: Button
var _t: float = 0.0
var kayak_sprite: TextureRect


func _ready() -> void:
	theme = GameState.ui_theme
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.27, 0.45)
	UI.place(bg, 0, 0, 1, 1, 0, 0, 0, 0)
	add_child(bg)
	kayak_sprite = TextureRect.new()
	kayak_sprite.texture = Art.kayak_frame(1, 1)
	kayak_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	kayak_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kayak_sprite.size = Vector2(96, 48)
	add_child(kayak_sprite)

	var center := CenterContainer.new()
	UI.place(center, 0, 0, 1, 1, 0, 0, 0, 0)
	add_child(center)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vb)
	var title := UI.outlined("Paddle & Pine", 32, Color(1.0, 0.88, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := UI.outlined("an open-water survival adventure", 10, Color(0.85, 0.92, 1.0))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(Control.new())

	var panel := PanelContainer.new()
	vb.add_child(panel)
	var inner := VBoxContainer.new()
	panel.add_child(inner)
	var row := HBoxContainer.new()
	inner.add_child(row)
	row.add_child(UI.label("Seed", 10))
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "random"
	seed_edit.custom_minimum_size = Vector2(120, 0)
	row.add_child(seed_edit)
	row.add_child(UI.label("World", 10))
	size_option = OptionButton.new()
	for k in GameState.WORLD_SIZES:
		size_option.add_item(k)
	size_option.select(1)
	row.add_child(size_option)
	inner.add_child(UI.button("New Game", _on_new_game, 200))
	continue_btn = UI.button("Continue", func(): GameState.continue_game(), 200)
	continue_btn.disabled = not GameState.has_save()
	inner.add_child(continue_btn)
	inner.add_child(UI.button("Toggle Fullscreen", func(): GameState.toggle_fullscreen(), 200))
	if OS.get_name() != "Web":
		inner.add_child(UI.button("Quit", func(): get_tree().quit(), 200))
	var tip := UI.outlined("Explore lakes and rivers by kayak. Hunt, camp before dark, trade at 100's of Kayaks,\nupgrade your boat and dig up buried treasure.", 9, Color(0.9, 0.9, 0.85))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)


func _on_new_game() -> void:
	var txt: String = seed_edit.text.strip_edges()
	var seed_value: int
	if txt == "":
		seed_value = randi() % 2000000000
	elif txt.is_valid_int():
		seed_value = absi(txt.to_int()) % 2000000000
	else:
		seed_value = absi(txt.hash()) % 2000000000
	var key: String = size_option.get_item_text(size_option.selected)
	var world_size: int = int(GameState.WORLD_SIZES[key])
	if GameState.has_save():
		_confirm_overwrite(seed_value, world_size)
	else:
		GameState.start_new_game(seed_value, world_size)


func _confirm_overwrite(seed_value: int, world_size: int) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Starting a new game will replace your saved game when you next save. Continue?"
	dlg.confirmed.connect(func(): GameState.start_new_game(seed_value, world_size))
	add_child(dlg)
	dlg.popup_centered()


func _process(delta: float) -> void:
	_t += delta
	var w: float = size.x
	kayak_sprite.position = Vector2(fmod(_t * 40.0, w + 200.0) - 100.0, size.y * 0.78 + sin(_t * 2.0) * 3.0)
	kayak_sprite.texture = Art.kayak_frame(1, 1 + int(_t * 3.0) % 2)
