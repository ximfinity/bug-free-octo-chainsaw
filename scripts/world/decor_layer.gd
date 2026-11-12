extends TileMapLayer
## Plants, trees and rocks from WorldData.decor. Two instances are used:
## a flat ground layer (flowers, lily pads, reeds) under everything and a tall
## y-sorted layer (trees, bushes, boulders) inside the entities node so the
## player walks behind them. Decor sprites are 64x64, drawn centred on the
## 32px cell with their foot 8px below the centre (see tools/gen_art.py).

const Art = preload("res://scripts/art.gd")
const Decor = preload("res://scripts/world/decor.gd")

var tall: bool = false


static func make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	var src := TileSetAtlasSource.new()
	src.texture = Art.DECOR
	src.texture_region_size = Vector2i(64, 64)
	for id in Decor.COUNT:
		var c: Vector2i = Decor.atlas_coords(id)
		src.create_tile(c)
		var td: TileData = src.get_tile_data(c, 0)
		td.y_sort_origin = 8
	ts.add_source(src, 0)
	return ts


func paint(world, tall_layer: bool, tileset: TileSet) -> void:
	tall = tall_layer
	tile_set = tileset
	y_sort_enabled = tall
	if not tall:
		z_index = -10
	clear()
	var w: int = world.width
	var h: int = world.height
	var decor: PackedByteArray = world.decor
	for y in h:
		for x in w:
			var v: int = decor[y * w + x]
			if v == 0:
				continue
			var id: int = v - 1
			if Decor.is_tall(id) != tall:
				continue
			set_cell(Vector2i(x, y), 0, Decor.atlas_coords(id))


func remove_at(t: Vector2i) -> void:
	erase_cell(t)
