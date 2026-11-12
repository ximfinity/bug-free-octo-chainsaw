extends RefCounted
## Texture atlas helpers. Index constants match tools/gen_art.py.

const SPRITES := preload("res://assets/sprites.png")
const KAYAK := preload("res://assets/kayak.png")
const STORE := preload("res://assets/store.png")
const TILES := preload("res://assets/tiles.png")

const PLAYER_DOWN := 0
const PLAYER_UP := 1
const PLAYER_SIDE := 2
const RABBIT := 3
const DEER := 4
const DUCK := 5
const WOLF := 6
const TENT := 7
const FIRE_A := 8
const FIRE_B := 9
const FIRE_OUT := 10
const ARROW := 11
const CHEST := 12
const DIG_HINT := 13
const X_MARK := 14
const FISH := 15
const COIN := 32
const BITE := 35

static var _cache: Dictionary = {}
static var _light_tex: Texture2D = null


static func sprite(index: int) -> AtlasTexture:
	if _cache.has(index):
		return _cache[index]
	var a := AtlasTexture.new()
	a.atlas = SPRITES
	a.region = Rect2((index % 8) * 16, (index / 8) * 16, 16, 16)
	_cache[index] = a
	return a


## row = hull level (0..2), col = 0 empty, 1/2 paddle strokes
static func kayak_frame(row: int, col: int) -> AtlasTexture:
	var key: int = 10000 + row * 10 + col
	if _cache.has(key):
		return _cache[key]
	var a := AtlasTexture.new()
	a.atlas = KAYAK
	a.region = Rect2(col * 32, row * 16, 32, 16)
	_cache[key] = a
	return a


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
	t.width = 128
	t.height = 128
	_light_tex = t
	return t
