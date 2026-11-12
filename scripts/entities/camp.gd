extends Node2D
## A pitched tent and campfire. A lit fire keeps the player warm and wolves
## away within SAFE_RADIUS.

const Art = preload("res://scripts/art.gd")
const SAFE_RADIUS := 176.0
const WOOD_TO_LIGHT := 3

var lit: bool = false
var fire_sprite: Sprite2D
var light: PointLight2D
var _anim: float = 0.0


func _ready() -> void:
	var tent := Sprite2D.new()
	tent.texture = Art.prop(Art.TENT)
	tent.position = Vector2(-22, 0)
	tent.offset = Vector2(0, -14)
	add_child(tent)
	fire_sprite = Sprite2D.new()
	fire_sprite.position = Vector2(20, 6)
	fire_sprite.offset = Vector2(0, -10)
	add_child(fire_sprite)
	light = PointLight2D.new()
	light.texture = Art.light_texture()
	light.texture_scale = 2.6
	light.color = Color(1.0, 0.68, 0.38)
	light.position = Vector2(20, -6)
	add_child(light)
	set_lit(lit)


func set_lit(v: bool) -> void:
	lit = v
	if fire_sprite == null:
		return
	fire_sprite.texture = Art.prop(Art.FIRE_A if lit else Art.FIRE_OUT)
	light.enabled = lit


func fire_position() -> Vector2:
	return position + Vector2(20, 0)


func _process(delta: float) -> void:
	if not lit:
		return
	_anim += delta
	fire_sprite.texture = Art.prop(Art.FIRE_A if int(_anim * 6.0) % 2 == 0 else Art.FIRE_B)
	light.energy = 1.0 + sin(_anim * 9.0) * 0.08 + sin(_anim * 23.0) * 0.05
