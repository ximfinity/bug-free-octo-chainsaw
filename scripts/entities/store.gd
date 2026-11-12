extends Node2D
## A "100's of Kayaks" trading post.

const Art = preload("res://scripts/art.gd")

var store_index: int = 0
var tile: Vector2i
var dock_tile: Vector2i


func _ready() -> void:
	var s := Sprite2D.new()
	s.texture = Art.STORE
	s.offset = Vector2(0, -32)
	add_child(s)
	var lbl := Label.new()
	lbl.text = "100's of Kayaks"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size = Vector2(200, 24)
	lbl.position = Vector2(-100, -112)
	add_child(lbl)
	var light := PointLight2D.new()
	light.texture = Art.light_texture()
	light.texture_scale = 1.6
	light.position = Vector2(0, -20)
	light.color = Color(1.0, 0.85, 0.55)
	light.energy = 0.0
	light.name = "Light"
	add_child(light)


func set_light(darkness: float) -> void:
	var light := get_node_or_null("Light") as PointLight2D
	if light:
		light.energy = clampf(darkness, 0.0, 1.0) * 0.6
