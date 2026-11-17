extends Node2D
## An item lying in the world. Collected by walking (or paddling) over it.

const Art = preload("res://scripts/art.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const FX = preload("res://scripts/fx/fx.gd")
const LIFETIME := 240.0

var item_id: String = "meat_raw"
var amount: int = 1
var main
var _t: float = 0.0
var _full_warned: float = 0.0
var sprite: Sprite2D


func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture = Art.item(int(ItemDB.item(item_id).get("icon", 13)))
	sprite.offset = Vector2(0, -16)
	add_child(sprite)
	# Rare items glitter in their rarity colour so you notice them.
	var r: int = ItemDB.rarity(item_id)
	if r >= 2:
		var sp: CPUParticles2D = FX.make_sparkles()
		sp.color = ItemDB.rarity_color(item_id)
		sp.position = Vector2(0, -16)
		sp.z_index = 1
		add_child(sp)
		var lt := PointLight2D.new()
		lt.texture = Art.light_texture()
		lt.texture_scale = 0.5
		lt.color = ItemDB.rarity_color(item_id)
		lt.energy = 0.8
		add_child(lt)


func _process(delta: float) -> void:
	_t += delta
	_full_warned -= delta
	sprite.position.y = roundf(sin(_t * 4.0) * 3.0)
	if _t > LIFETIME:
		queue_free()
		return
	if main == null or main.player == null or _t < 0.4:
		return
	var who = null
	var best: float = 56.0
	for c in main.party:
		if c.downed or c.is_paddling():
			continue
		var d: float = position.distance_to(c.position)
		if d < best:
			best = d
			who = c
	if who == null:
		return
	if best > 22.0:
		# Magnet: drift toward whoever is close.
		if who.inventory.room_for(item_id) > 0:
			position = position.move_toward(who.position, 200.0 * delta)
		return
	if true:
		var added: int = who.inventory.add(item_id, amount)
		if added > 0:
			if ItemDB.rarity(item_id) >= 1:
				main.on_rare_item(who, item_id)
			elif who.controlled:
				main.item_toast(item_id, added)
			Sfx.play("pickup", position, -6.0)
			amount -= added
		if amount <= 0:
			queue_free()
		elif _full_warned <= 0.0 and who.controlled:
			main.message("Inventory full! (upgrade your kayak hull for more room)")
			_full_warned = 4.0
