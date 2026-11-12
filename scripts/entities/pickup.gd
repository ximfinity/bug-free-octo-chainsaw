extends Node2D
## An item lying in the world. Collected by walking (or paddling) over it.

const Art = preload("res://scripts/art.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const LIFETIME := 240.0

var item_id: String = "meat_raw"
var amount: int = 1
var main
var _t: float = 0.0
var _full_warned: float = 0.0
var sprite: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = Art.sprite(int(ItemDB.item(item_id).get("icon", Art.CHEST)))
	sprite.scale = Vector2(0.75, 0.75)
	sprite.offset = Vector2(0, -8)
	add_child(sprite)


func _process(delta: float) -> void:
	_t += delta
	_full_warned -= delta
	sprite.position.y = sin(_t * 4.0) * 1.5
	if _t > LIFETIME:
		queue_free()
		return
	if main == null or main.player == null:
		return
	if position.distance_to(main.player.position) < 14.0:
		var added: int = main.player.inventory.add(item_id, amount)
		if added > 0:
			main.message("+%d %s" % [added, ItemDB.item_name(item_id)])
			amount -= added
		if amount <= 0:
			queue_free()
		elif _full_warned <= 0.0:
			main.message("Inventory full! (upgrade your kayak hull for more room)")
			_full_warned = 4.0
