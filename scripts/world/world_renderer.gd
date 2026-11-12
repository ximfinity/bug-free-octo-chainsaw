extends TileMapLayer
## Paints WorldData into a TileMapLayer using assets/tiles.png.

const Tiles = preload("res://scripts/world/tiles.gd")
const Art = preload("res://scripts/art.gd")


static func make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var src := TileSetAtlasSource.new()
	src.texture = Art.TILES
	src.texture_region_size = Vector2i(16, 16)
	for y in 3:
		for x in 8:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	return ts


func _ready() -> void:
	tile_set = make_tileset()


func paint(world) -> void:
	if tile_set == null:
		tile_set = make_tileset()
	clear()
	var w: int = world.width
	var h: int = world.height
	var tiles: PackedByteArray = world.tiles
	for y in h:
		for x in w:
			var t: int = tiles[y * w + x]
			var variant: int = ((x * 73856093) ^ (y * 19349663)) & 1
			var coords: Vector2i = Tiles.ATLAS[t][variant]
			set_cell(Vector2i(x, y), 0, coords)
