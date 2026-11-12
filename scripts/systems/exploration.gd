extends RefCounted
## Fog-of-war: which tiles the player has seen, and a map image of them.

const Tiles = preload("res://scripts/world/tiles.gd")

var world
var width: int = 0
var height: int = 0
var discovered: PackedByteArray = PackedByteArray()
var discovered_count: int = 0
var image: Image
var texture: ImageTexture
var _dirty: bool = false


func setup(world_data) -> void:
	world = world_data
	width = world.width
	height = world.height
	discovered = PackedByteArray()
	discovered.resize(width * height)
	discovered.fill(0)
	discovered_count = 0
	image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Tiles.FOG_COLOR)
	texture = ImageTexture.create_from_image(image)


func is_discovered(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= width or t.y >= height:
		return false
	return discovered[t.y * width + t.x] == 1


func reveal(center: Vector2i, radius: int) -> void:
	var r2: int = radius * radius
	for dy in range(-radius, radius + 1):
		var y: int = center.y + dy
		if y < 0 or y >= height:
			continue
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var x: int = center.x + dx
			if x < 0 or x >= width:
				continue
			var i: int = y * width + x
			if discovered[i] == 0:
				discovered[i] = 1
				discovered_count += 1
				image.set_pixel(x, y, _color(x, y))
				_dirty = true


func _color(x: int, y: int) -> Color:
	var t: int = world.get_tile(x, y)
	var c: Color = Tiles.MAP_COLORS[t]
	# Subtle grid shading so the map reads like parchment.
	if (x + y) % 2 == 0:
		c = c.darkened(0.04)
	return c


## Push pending pixel changes to the GPU (call at most a few times a second).
func flush() -> void:
	if _dirty:
		texture.update(image)
		_dirty = false


func percent() -> float:
	return 100.0 * float(discovered_count) / float(maxi(1, width * height))


func to_base64() -> String:
	var packed: PackedByteArray = discovered.compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(packed)


func from_base64(s: String) -> void:
	if s.is_empty():
		return
	var packed: PackedByteArray = Marshalls.base64_to_raw(s)
	var raw: PackedByteArray = packed.decompress(width * height, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != width * height:
		push_warning("Exploration data size mismatch; ignoring.")
		return
	discovered = raw
	discovered_count = 0
	image.fill(Tiles.FOG_COLOR)
	for y in height:
		for x in width:
			if discovered[y * width + x] == 1:
				discovered_count += 1
				image.set_pixel(x, y, _color(x, y))
	texture.update(image)
	_dirty = false
