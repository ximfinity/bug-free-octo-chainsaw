extends RefCounted
## Tile type ids and their properties.

const DEEP := 0
const SHALLOW := 1
const RIVER := 2
const SAND := 3
const GRASS := 4
const FOREST := 5
const HILL := 6
const MOUNTAIN := 7
const SNOW := 8
const MARSH := 9
const DOCK := 10
const COUNT := 11

const NAMES := ["Deep water", "Shallows", "River", "Sand", "Grass", "Forest", "Hills",
	"Mountain", "Snow", "Marsh", "Dock"]

## Atlas coordinates in assets/tiles.png, two variants per tile type.
const ATLAS := [
	[Vector2i(0, 0), Vector2i(1, 0)],  # DEEP
	[Vector2i(2, 0), Vector2i(3, 0)],  # SHALLOW
	[Vector2i(4, 0), Vector2i(5, 0)],  # RIVER
	[Vector2i(6, 0), Vector2i(7, 0)],  # SAND
	[Vector2i(0, 1), Vector2i(1, 1)],  # GRASS
	[Vector2i(2, 1), Vector2i(3, 1)],  # FOREST
	[Vector2i(4, 1), Vector2i(5, 1)],  # HILL
	[Vector2i(6, 1), Vector2i(7, 1)],  # MOUNTAIN
	[Vector2i(0, 2), Vector2i(1, 2)],  # SNOW
	[Vector2i(4, 2), Vector2i(5, 2)],  # MARSH
	[Vector2i(2, 2), Vector2i(2, 2)],  # DOCK
]
const HOLE_ATLAS := Vector2i(3, 2)

## Colours used for the exploration map.
const MAP_COLORS := [
	Color(0.180, 0.337, 0.549),    # DEEP
	Color(0.306, 0.549, 0.729),   # SHALLOW
	Color(0.275, 0.502, 0.722),   # RIVER
	Color(0.886, 0.808, 0.588),  # SAND
	Color(0.471, 0.659, 0.353),   # GRASS
	Color(0.275, 0.478, 0.259),    # FOREST
	Color(0.588, 0.627, 0.408),  # HILL
	Color(0.471, 0.431, 0.392),  # MOUNTAIN
	Color(0.925, 0.925, 0.925),  # SNOW
	Color(0.376, 0.557, 0.455),   # MARSH
	Color(0.588, 0.416, 0.235),   # DOCK
]
const FOG_COLOR := Color(0.157, 0.133, 0.110)

## Lookup tables indexed by tile id (1 = true).
const KAYAK_OK := [1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0]
const WALK_OK := [0, 1, 0, 1, 1, 1, 1, 0, 0, 1, 1]
const LAKE_WATER := [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
const ANY_WATER := [1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]
const LAND := [0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1]
const WALK_SPEED := [0.0, 0.5, 0.0, 0.95, 1.0, 0.75, 0.8, 0.0, 0.0, 0.6, 1.0]


static func kayak_ok(t: int) -> bool:
	return t >= 0 and t < COUNT and KAYAK_OK[t] == 1


static func walk_ok(t: int) -> bool:
	return t >= 0 and t < COUNT and WALK_OK[t] == 1


static func is_water(t: int) -> bool:
	return t >= 0 and t < COUNT and ANY_WATER[t] == 1


static func mask(table: Array) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(256)
	m.fill(0)
	for i in table.size():
		m[i] = table[i]
	return m
