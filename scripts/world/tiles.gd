extends RefCounted
## Tile (biome) ids and their properties. Ids must match tools/gen_art.py.

const DEEP := 0
const SHALLOW := 1
const RIVER := 2
const SAND := 3
const GRASS := 4
const FOREST := 5 # pine / spruce forest
const HILL := 6
const MOUNTAIN := 7
const SNOW := 8
const MARSH := 9
const DOCK := 10
const BIRCH := 11
const MAPLE := 12
const MEADOW := 13
const ROCKY := 14
const COUNT := 15

const NAMES := ["Deep water", "Shallows", "River", "Beach", "Grassland", "Pine forest", "Hills",
	"Mountain", "Snow", "Marsh", "Dock", "Birch forest", "Maple forest", "Meadow", "Rocky highland"]

## Colours used for the exploration map (cozy palette).
const MAP_COLORS := [
	Color(0.176, 0.447, 0.722),  # DEEP
	Color(0.361, 0.722, 0.792),  # SHALLOW
	Color(0.302, 0.627, 0.780),  # RIVER
	Color(0.945, 0.835, 0.573),  # SAND
	Color(0.459, 0.749, 0.333),  # GRASS
	Color(0.235, 0.522, 0.318),  # FOREST (pine)
	Color(0.647, 0.733, 0.388),  # HILL
	Color(0.533, 0.506, 0.565),  # MOUNTAIN
	Color(0.937, 0.957, 0.984),  # SNOW
	Color(0.400, 0.620, 0.494),  # MARSH
	Color(0.588, 0.416, 0.235),  # DOCK
	Color(0.553, 0.788, 0.357),  # BIRCH
	Color(0.890, 0.494, 0.231),  # MAPLE
	Color(0.580, 0.835, 0.400),  # MEADOW
	Color(0.663, 0.675, 0.580),  # ROCKY
]
const FOG_COLOR := Color(0.204, 0.176, 0.235)

## Lookup tables indexed by tile id (1 = true).
##                       D  S  R  Sa G  Pi H  Mo Sn Ma Do Bi Mp Me Ro
const KAYAK_OK :=       [1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0]
const WALK_OK :=        [0, 1, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1]
const LAKE_WATER :=     [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
const ANY_WATER :=      [1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
const LAND :=           [0, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 1, 1, 1]
const FORESTS :=        [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 1, 0, 0]
## Where treasure can be buried / stores can stand.
const DIGGABLE :=       [0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1]
const WALK_SPEED := [0.0, 0.5, 0.0, 0.95, 1.0, 0.75, 0.8, 0.0, 0.0, 0.6, 1.0, 0.8, 0.8, 1.0, 0.85]


static func kayak_ok(t: int) -> bool:
	return t >= 0 and t < COUNT and KAYAK_OK[t] == 1


static func walk_ok(t: int) -> bool:
	return t >= 0 and t < COUNT and WALK_OK[t] == 1


static func is_water(t: int) -> bool:
	return t >= 0 and t < COUNT and ANY_WATER[t] == 1


static func is_forest(t: int) -> bool:
	return t >= 0 and t < COUNT and FORESTS[t] == 1


static func is_diggable(t: int) -> bool:
	return t >= 0 and t < COUNT and DIGGABLE[t] == 1


static func mask(table: Array) -> PackedByteArray:
	var m := PackedByteArray()
	m.resize(256)
	m.fill(0)
	for i in table.size():
		m[i] = table[i]
	return m
