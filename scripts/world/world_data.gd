extends RefCounted
## The generated world: a tile grid plus points of interest.

const Tiles = preload("res://scripts/world/tiles.gd")
const TILE_SIZE := 16

var width: int = 0
var height: int = 0
var seed_value: int = 0
var tiles: PackedByteArray = PackedByteArray()
## Per-tile river current direction (zero where there is no current).
var flow: PackedVector2Array = PackedVector2Array()
## Vector2i tile positions of "100's of Kayaks" stores.
var stores: Array = []
## Water tile next to each store where a retrieved kayak is dropped.
var store_docks: Array = []
## Array of {"pos": Vector2i, "loot": String}
var treasures: Array = []
var start: Vector2i = Vector2i.ZERO
var start_water: Vector2i = Vector2i.ZERO


func idx(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_tile(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return Tiles.MOUNTAIN
	return tiles[y * width + x]


func get_tile_v(t: Vector2i) -> int:
	return get_tile(t.x, t.y)


func is_kayak_water(x: int, y: int) -> bool:
	return Tiles.kayak_ok(get_tile(x, y))


func is_walkable(x: int, y: int) -> bool:
	return Tiles.walk_ok(get_tile(x, y))


func tile_at_pos(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE_SIZE), floori(p.y / TILE_SIZE))


func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE_SIZE + TILE_SIZE * 0.5, t.y * TILE_SIZE + TILE_SIZE * 0.5)


func tile_type_at_pos(p: Vector2) -> int:
	var t := tile_at_pos(p)
	return get_tile(t.x, t.y)


func walk_mult_at_pos(p: Vector2) -> float:
	var t: int = tile_type_at_pos(p)
	return Tiles.WALK_SPEED[t]


func flow_at_pos(p: Vector2) -> Vector2:
	var t := tile_at_pos(p)
	if not in_bounds(t.x, t.y):
		return Vector2.ZERO
	return flow[t.y * width + t.x]


func pixel_size() -> Vector2:
	return Vector2(width * TILE_SIZE, height * TILE_SIZE)
