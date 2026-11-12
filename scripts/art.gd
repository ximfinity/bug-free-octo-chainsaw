extends RefCounted
## Texture atlas helpers. Layouts match tools/gen_art.py.

const ITEMS := preload("res://assets/items.png")
const PROPS := preload("res://assets/props.png")
const KAYAK := preload("res://assets/kayak.png")
const PLAYER := preload("res://assets/player.png")
const CREATURES := preload("res://assets/creatures.png")
const DECOR := preload("res://assets/decor.png")
const STORE := preload("res://assets/store.png")
const TERRAIN := preload("res://assets/terrain.png")
const WATER_NOISE := preload("res://assets/water_noise.png")

# props.png (64x64 cells)
const TENT := 0
const FIRE_A := 1
const FIRE_B := 2
const FIRE_OUT := 3
const CHEST := 4
const X_MARK := 5
const HOLE := 6
const BITE := 7
const ARROW := 8
const SPARKLE := 9
const SWING := 10
const ALERT := 11
const HEART := 12

# items.png (32x32 icons)
const ICON_ARROWS := 8
const ICON_COIN := 18

# player.png rows
const VIEW_DOWN := 0
const VIEW_UP := 1
const VIEW_SIDE := 2

const CREATURE_ROWS := {"rabbit": 0, "deer": 1, "duck": 2, "wolf": 3, "spider": 4, "wildcat": 5, "bear": 6}
const KAYAK_HEADINGS := 16

static var _cache: Dictionary = {}
static var _light_tex: Texture2D = null
static var _dot_tex: Texture2D = null


static func _region(atlas: Texture2D, key: String, rect: Rect2) -> AtlasTexture:
	if _cache.has(key):
		return _cache[key]
	var a := AtlasTexture.new()
	a.atlas = atlas
	a.region = rect
	_cache[key] = a
	return a


static func item(index: int) -> AtlasTexture:
	return _region(ITEMS, "i%d" % index, Rect2((index % 8) * 32, (index / 8) * 32, 32, 32))


static func prop(index: int) -> AtlasTexture:
	return _region(PROPS, "p%d" % index, Rect2((index % 8) * 64, (index / 8) * 64, 64, 64))


## Kayak column for who is aboard: riders = [juniper_aboard, rowan_aboard],
## stroke 0..3. 0 = empty, 1-4 Juniper solo, 5-8 Rowan solo, 9-12 both.
static func kayak_col(juniper: bool, rowan: bool, stroke: int) -> int:
	if juniper and rowan:
		return 9 + stroke
	if juniper:
		return 1 + stroke
	if rowan:
		return 5 + stroke
	return 0


## hull 0..2, heading_index 0..15 (0 = east, clockwise), col 0..12
static func kayak_frame(hull: int, heading_index: int, col: int) -> AtlasTexture:
	var row: int = hull * KAYAK_HEADINGS + posmod(heading_index, KAYAK_HEADINGS)
	return _region(KAYAK, "k%d_%d" % [row, col], Rect2(col * 64, row * 64, 64, 64))


static func heading_index(angle: float) -> int:
	return posmod(int(round(angle / (TAU / KAYAK_HEADINGS))), KAYAK_HEADINGS)


## who 0 Juniper / 1 Rowan; view 0 down / 1 up / 2 side(right);
## col 0..3 walk, 4..5 carry
static func player_frame(view: int, col: int, who: int = 0) -> AtlasTexture:
	var row: int = who * 3 + view
	return _region(PLAYER, "pl%d_%d" % [row, col], Rect2(col * 32, row * 48, 32, 48))


static func creature_frame(kind: String, frame: int) -> AtlasTexture:
	var row: int = int(CREATURE_ROWS.get(kind, 0))
	return _region(CREATURES, "c%d_%d" % [row, frame], Rect2(frame * 48, row * 48, 48, 48))


static func light_texture() -> Texture2D:
	if _light_tex != null:
		return _light_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.55, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_light_tex = t
	return t


## Small soft white dot used for wakes, splashes and sparkles.
static func dot_texture() -> Texture2D:
	if _dot_tex != null:
		return _dot_tex
	var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 6:
		for x in 6:
			var d: float = Vector2(x - 2.5, y - 2.5).length()
			if d < 2.6:
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if d < 1.6 else 0.6))
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex
