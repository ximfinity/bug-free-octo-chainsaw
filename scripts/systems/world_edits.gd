extends RefCounted
## Changes the player makes to the land, and their slow recovery:
##   stump   -> sapling -> the original tree        (chopping)
##   picked  -> berry bush again                    (foraging)
##   dug     -> grass again                         (digging)
##   plot    -> grass again if left unplanted       (tilling)
##   crop    -> grows through 4 stages              (farming)
## Each edit: tile index -> [kind, start_time_days, extra, stage].
## Times are absolute in-game days (day + hour / 24).

const Decor = preload("res://scripts/world/decor.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const Tiles = preload("res://scripts/world/tiles.gd")

const STUMP_DAYS := 1.5
const SAPLING_DAYS := 1.5
const PICKED_DAYS := 1.0
const DUG_DAYS := 1.0
const PLOT_DAYS := 2.0
const WATER_BONUS := 0.8

var world
var flat_layer
var tall_layer
var edits: Dictionary = {}


func setup(world_data, flat, tall) -> void:
	world = world_data
	flat_layer = flat
	tall_layer = tall


func get_edit(idx: int) -> Array:
	return edits.get(idx, [])


func kind_at(t: Vector2i) -> String:
	var e: Array = get_edit(world.idx(t.x, t.y))
	return "" if e.is_empty() else str(e[0])


## Ripe crop at this tile?
func is_ripe(t: Vector2i) -> bool:
	var e: Array = get_edit(world.idx(t.x, t.y))
	return not e.is_empty() and e[0] == "crop" and int(e[3]) >= 3


func set_edit(t: Vector2i, kind: String, now: float, extra = 0, stage: int = 0) -> void:
	var idx: int = world.idx(t.x, t.y)
	edits[idx] = [kind, now, extra, stage]
	_apply(idx)


func clear_edit(t: Vector2i, decor_id: int) -> void:
	var idx: int = world.idx(t.x, t.y)
	edits.erase(idx)
	_set_decor(idx, decor_id)


## Shows the tile's current state in the decor layers.
func _apply(idx: int) -> void:
	var e: Array = edits.get(idx, [])
	if e.is_empty():
		return
	match str(e[0]):
		"stump":
			_set_decor(idx, Decor.STUMP)
		"sapling":
			_set_decor(idx, Decor.SAPLING)
		"picked":
			_set_decor(idx, Decor.BUSH)
		"dug":
			_set_decor(idx, Decor.DUG)
		"plot":
			_set_decor(idx, Decor.PLOT)
		"crop":
			var ci: int = int(ItemDB.CROPS[str(e[2])]["index"])
			_set_decor(idx, Decor.CROP0 + ci * 4 + clampi(int(e[3]), 0, 3))


func _set_decor(idx: int, decor_id: int) -> void:
	world.decor[idx] = decor_id + 1 if decor_id >= 0 else 0
	var t := Vector2i(idx % world.width, idx / world.width)
	if flat_layer:
		flat_layer.erase_cell(t)
	if tall_layer:
		tall_layer.erase_cell(t)
	if decor_id < 0:
		return
	var layer = tall_layer if Decor.is_tall(decor_id) else flat_layer
	if layer:
		layer.set_cell(t, 0, Decor.atlas_coords(decor_id))


func _near_water(idx: int) -> bool:
	var x: int = idx % world.width
	var y: int = idx / world.width
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if Tiles.is_water(world.get_tile(x + dx, y + dy)):
				return true
	return false


## Advances regrowth and crop growth. Returns true if anything changed.
func tick(now: float) -> bool:
	var changed := false
	for idx in edits.keys():
		var e: Array = edits[idx]
		var age: float = now - float(e[1])
		var t := Vector2i(idx % world.width, idx / world.width)
		match str(e[0]):
			"stump":
				if age >= STUMP_DAYS:
					edits[idx] = ["sapling", now, e[2], 0]
					_apply(idx)
					changed = true
			"sapling":
				if age >= SAPLING_DAYS:
					clear_edit(t, int(e[2]))
					changed = true
			"picked":
				if age >= PICKED_DAYS:
					clear_edit(t, Decor.BERRYBUSH)
					changed = true
			"dug":
				if age >= DUG_DAYS:
					clear_edit(t, -1)
					changed = true
			"plot":
				if age >= PLOT_DAYS:
					clear_edit(t, -1)
					changed = true
			"crop":
				var total: float = float(ItemDB.CROPS[str(e[2])]["days"])
				if _near_water(idx):
					total *= WATER_BONUS
				var stage: int = clampi(int(age / (total / 3.0)), 0, 3)
				if stage != int(e[3]):
					e[3] = stage
					_apply(idx)
					changed = true
	return changed


func to_array() -> Array:
	var out: Array = []
	for idx in edits:
		var e: Array = edits[idx]
		out.append([idx, e[0], e[1], e[2], e[3]])
	return out


func from_array(arr: Array) -> void:
	edits.clear()
	for row in arr:
		if not (row is Array) or (row as Array).size() < 5:
			continue
		var idx: int = int(row[0])
		var extra = row[3]
		if str(row[1]) == "stump" or str(row[1]) == "sapling":
			extra = int(extra)
		edits[idx] = [str(row[1]), float(row[2]), extra, int(row[4])]
		_apply(idx)
