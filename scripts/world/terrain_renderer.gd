extends ColorRect
## Draws the whole world's ground and water with shaders/terrain.gdshader.
## Builds two small data textures (one texel per tile) from WorldData.

const Tiles = preload("res://scripts/world/tiles.gd")
const Art = preload("res://scripts/art.gd")
const TerrainShader = preload("res://shaders/terrain.gdshader")

const MAX_DEPTH := 6.0

var data_tex: ImageTexture
var flow_tex: ImageTexture


func build(world) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -20
	var w: int = world.width
	var h: int = world.height
	var n: int = w * h
	position = Vector2.ZERO
	size = world.pixel_size()
	var tiles: PackedByteArray = world.tiles

	# Multi-source BFS from every land tile: gives each water tile its
	# distance to shore and the biome of the nearest land.
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var near := PackedByteArray()
	near.resize(n)
	var queue := PackedInt32Array()
	queue.resize(n)
	var qh: int = 0
	var qt: int = 0
	for i in n:
		var t: int = tiles[i]
		if not Tiles.is_water(t):
			dist[i] = 0
			near[i] = t
			queue[qt] = i
			qt += 1
	while qh < qt:
		var i: int = queue[qh]
		qh += 1
		var x: int = i % w
		var nd: int = dist[i] + 1
		for k in 4:
			var j: int = -1
			if k == 0 and x > 0:
				j = i - 1
			elif k == 1 and x < w - 1:
				j = i + 1
			elif k == 2 and i >= w:
				j = i - w
			elif k == 3 and i < n - w:
				j = i + w
			if j >= 0 and dist[j] == -1:
				dist[j] = nd
				near[j] = near[i]
				queue[qt] = j
				qt += 1

	var data := PackedByteArray()
	data.resize(n * 4)
	var flow := PackedByteArray()
	flow.resize(n * 2)
	for i in n:
		var t: int = tiles[i]
		var water: bool = Tiles.is_water(t)
		var biome: int = near[i] if water else t
		if biome == Tiles.DOCK:
			biome = Tiles.SAND
		data[i * 4] = biome
		data[i * 4 + 1] = 0 if water else 255
		var d: float = clampf(float(maxi(dist[i], 0)) / MAX_DEPTH, 0.0, 1.0)
		data[i * 4 + 2] = int(d * 255.0) if water else 0
		data[i * 4 + 3] = 255 if t == Tiles.RIVER else 0
		var f: Vector2 = world.flow[i]
		flow[i * 2] = int(clampf(f.x * 0.5 + 0.5, 0.0, 1.0) * 255.0)
		flow[i * 2 + 1] = int(clampf(f.y * 0.5 + 0.5, 0.0, 1.0) * 255.0)
	var data_img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var flow_img := Image.create_from_data(w, h, false, Image.FORMAT_RG8, flow)
	data_tex = ImageTexture.create_from_image(data_img)
	flow_tex = ImageTexture.create_from_image(flow_img)

	var mat := ShaderMaterial.new()
	mat.shader = TerrainShader
	mat.set_shader_parameter("data_n", data_tex)
	mat.set_shader_parameter("data_l", data_tex)
	mat.set_shader_parameter("flow_l", flow_tex)
	mat.set_shader_parameter("terrain_atlas", Art.TERRAIN)
	mat.set_shader_parameter("noise_tex", Art.WATER_NOISE)
	mat.set_shader_parameter("world_tiles", Vector2(w, h))
	mat.set_shader_parameter("tile_count", float(Tiles.COUNT))
	material = mat


func set_daylight(v: float) -> void:
	if material:
		(material as ShaderMaterial).set_shader_parameter("daylight", v)
