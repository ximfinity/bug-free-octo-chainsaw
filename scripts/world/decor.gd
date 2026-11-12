extends RefCounted
## Decor (plants, rocks) ids. Order must match DECOR in tools/gen_art.py
## (see assets/decor_index.txt). WorldData.decor stores id + 1 (0 = none).

const PINE0 := 0
const PINE1 := 1
const BIRCH0 := 2
const BIRCH1 := 3
const MAPLE0 := 4
const MAPLE1 := 5
const OAK0 := 6
const OAK1 := 7
const WILLOW := 8
const SNAG := 9
const SNOWPINE := 10
const BOULDER := 11
const BUSH := 12
const BERRYBUSH := 13
const STUMP := 14
const CATTAIL := 15
const ROCK := 16
const FLOWERS_Y := 17
const FLOWERS_P := 18
const FLOWERS_V := 19
const FLOWERS_W := 20
const FERN := 21
const MUSHROOMS := 22
const REEDS := 23
const LILY := 24
const LILYFLOWER := 25
const DRIFTWOOD := 26
const TUFT := 27
const PEAK0 := 28
const PEAK1 := 29
const PEAK2 := 30
const SNOWPEAK0 := 31
const SNOWPEAK1 := 32
const COUNT := 33
## Ids below FLAT_START are tall; FLAT_START..FLAT_END are flat ground cover;
## ids after FLAT_END (mountain peaks) are tall again.
const FLAT_START := 16
const FLAT_END := 27
const COLUMNS := 8

## Trees you can chop for firewood.
const TREES := [PINE0, PINE1, BIRCH0, BIRCH1, MAPLE0, MAPLE1, OAK0, OAK1, WILLOW, SNAG, SNOWPINE]


static func is_tall(id: int) -> bool:
	return id >= 0 and id < COUNT and (id < FLAT_START or id > FLAT_END)


static func is_tree(id: int) -> bool:
	return TREES.has(id)


static func atlas_coords(id: int) -> Vector2i:
	return Vector2i(id % COLUMNS, id / COLUMNS)
