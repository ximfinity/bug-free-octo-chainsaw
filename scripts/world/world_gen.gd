extends RefCounted
## Deterministic world generator: seed -> WorldData.
##
## Steps: elevation/moisture noise -> quantile-based tile classes -> remove
## specks -> give land-locked valleys a lake -> connect every lake with
## A*-carved rivers (MST + a few loops) -> shallows/marsh refinement ->
## stores, start point and treasure placement.

const Tiles = preload("res://scripts/world/tiles.gd")
const Decor = preload("res://scripts/world/decor.gd")
const WorldData = preload("res://scripts/world/world_data.gd")

const LOOT_TABLE := [
	["coin_purse", 40], ["compass", 25], ["gem", 20], ["gold_idol", 15],
]
const STORE_SPACING := 55
const MAX_STORES := 10
const TREASURE_COUNT := 45
const TREASURE_SPACING := 12


static func generate(seed_value: int, w: int = 448, h: int = 448) -> WorldData:
	var wd := WorldData.new()
	wd.width = w
	wd.height = h
	wd.seed_value = seed_value
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var n: int = w * h

	# ---------------------------------------------------------------- noise
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.016
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	var mnoise := FastNoiseLite.new()
	mnoise.seed = seed_value + 7919
	mnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mnoise.frequency = 0.02
	mnoise.fractal_type = FastNoiseLite.FRACTAL_FBM
	mnoise.fractal_octaves = 3
	var tnoise := FastNoiseLite.new()
	tnoise.seed = seed_value + 4242
	tnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	tnoise.frequency = 0.008
	tnoise.fractal_type = FastNoiseLite.FRACTAL_FBM
	tnoise.fractal_octaves = 2

	var elev := PackedFloat32Array()
	elev.resize(n)
	var moist := PackedFloat32Array()
	moist.resize(n)
	var temp := PackedFloat32Array()
	temp.resize(n)
	var border: float = maxf(12.0, w * 0.06)
	var samples := PackedFloat32Array()
	for y in h:
		for x in w:
			var i: int = y * w + x
			var e: float = noise.get_noise_2d(x, y) * 0.5 + 0.5
			var d: float = float(mini(mini(x, y), mini(w - 1 - x, h - 1 - y)))
			if d < border:
				var t: float = d / border
				e = lerpf(1.5, e, t * t * (3.0 - 2.0 * t))
			elif (x + y) % 3 == 0:
				samples.append(e)
			elev[i] = e
			moist[i] = mnoise.get_noise_2d(x, y)
			temp[i] = tnoise.get_noise_2d(x, y)
	samples.sort()
	var deep_q: float = _quantile(samples, 0.19)
	var water_q: float = _quantile(samples, 0.31)
	var sand_q: float = _quantile(samples, 0.36)
	var hill_q: float = _quantile(samples, 0.81)
	var mount_q: float = _quantile(samples, 0.89)
	var snow_q: float = _quantile(samples, 0.975)

	# ------------------------------------------------------------- classify
	var tiles := PackedByteArray()
	tiles.resize(n)
	for i in n:
		var e: float = elev[i]
		var t: int
		if e < deep_q:
			t = Tiles.DEEP
		elif e < water_q:
			t = Tiles.SHALLOW
		elif e < sand_q:
			t = Tiles.SAND
		elif e < hill_q:
			t = _lowland_biome(moist[i], temp[i])
		elif e < mount_q:
			if moist[i] > 0.25:
				t = Tiles.FOREST
			elif moist[i] < -0.15:
				t = Tiles.ROCKY
			else:
				t = Tiles.HILL
		elif e < snow_q:
			t = Tiles.MOUNTAIN
		else:
			t = Tiles.SNOW
		tiles[i] = t

	var lake_mask := Tiles.mask(Tiles.LAKE_WATER)
	var land_mask := Tiles.mask(Tiles.LAND)

	# ------------------------------------------------- remove tiny ponds
	var res: Array = _label(tiles, w, h, lake_mask)
	var labels: PackedInt32Array = res[0]
	var sizes: Array = res[1]
	for i in n:
		var l: int = labels[i]
		if l >= 0 and sizes[l] < 30:
			tiles[i] = Tiles.SAND

	# -------------------------------- land-locked valleys get a lake or rock
	res = _label(tiles, w, h, land_mask)
	labels = res[0]
	sizes = res[1]
	var comp_count: int = sizes.size()
	var touches := PackedByteArray()
	touches.resize(comp_count)
	touches.fill(0)
	var sumx := PackedFloat64Array()
	sumx.resize(comp_count)
	sumx.fill(0.0)
	var sumy := PackedFloat64Array()
	sumy.resize(comp_count)
	sumy.fill(0.0)
	for y in h:
		for x in w:
			var i: int = y * w + x
			var l: int = labels[i]
			if l < 0:
				continue
			sumx[l] += x
			sumy[l] += y
			if touches[l] == 0:
				if (x > 0 and lake_mask[tiles[i - 1]] == 1) or (x < w - 1 and lake_mask[tiles[i + 1]] == 1) \
						or (y > 0 and lake_mask[tiles[i - w]] == 1) or (y < h - 1 and lake_mask[tiles[i + w]] == 1):
					touches[l] = 1
	var reps_land: Array = _representatives(labels, sizes, sumx, sumy, w, h)
	# Small enclosed pockets become rock; big valleys get a lake that the
	# river network will connect.
	var fill_rock := PackedByteArray()
	fill_rock.resize(comp_count)
	fill_rock.fill(0)
	for c in comp_count:
		if touches[c] == 0 and sizes[c] < 160:
			fill_rock[c] = 1
	for i in n:
		var l: int = labels[i]
		if l >= 0 and fill_rock[l] == 1:
			tiles[i] = Tiles.MOUNTAIN
	for c in comp_count:
		if touches[c] == 1 or fill_rock[c] == 1:
			continue
		else:
			var r: Vector2i = reps_land[c]
			var rad: int = clampi(int(sqrt(float(sizes[c])) * 0.18), 3, 7)
			for dy in range(-rad - 1, rad + 2):
				for dx in range(-rad - 1, rad + 2):
					var x: int = r.x + dx
					var y: int = r.y + dy
					if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
						continue
					var dd: float = sqrt(float(dx * dx + dy * dy))
					if dd <= rad and labels[y * w + x] == c:
						tiles[y * w + x] = Tiles.DEEP if dd < rad - 1.5 else Tiles.SHALLOW

	# ------------------------------------------------- connect all lakes
	res = _label(tiles, w, h, lake_mask)
	labels = res[0]
	sizes = res[1]
	comp_count = sizes.size()
	sumx = PackedFloat64Array()
	sumx.resize(comp_count)
	sumx.fill(0.0)
	sumy = PackedFloat64Array()
	sumy.resize(comp_count)
	sumy.fill(0.0)
	for y in h:
		for x in w:
			var l: int = labels[y * w + x]
			if l >= 0:
				sumx[l] += x
				sumy[l] += y
	var reps: Array = _representatives(labels, sizes, sumx, sumy, w, h)
	var edges: Array = _mst_edges(reps, rng)

	var flow := PackedVector2Array()
	flow.resize(n)
	flow.fill(Vector2.ZERO)
	if edges.size() > 0:
		var astar := AStarGrid2D.new()
		astar.region = Rect2i(0, 0, w, h)
		astar.cell_size = Vector2(1, 1)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.update()
		var jnoise := FastNoiseLite.new()
		jnoise.seed = seed_value + 31337
		jnoise.frequency = 0.05
		jnoise.fractal_type = FastNoiseLite.FRACTAL_FBM
		jnoise.fractal_octaves = 2
		var solid_border: int = int(border * 0.5)
		for y in h:
			for x in w:
				var p := Vector2i(x, y)
				var dmin: int = mini(mini(x, y), mini(w - 1 - x, h - 1 - y))
				if dmin < solid_border:
					astar.set_point_solid(p, true)
					continue
				var t: int = tiles[y * w + x]
				var cost: float = 3.0
				match t:
					Tiles.DEEP, Tiles.SHALLOW:
						cost = 1.0
					Tiles.FOREST, Tiles.BIRCH, Tiles.MAPLE:
						cost = 4.0
					Tiles.HILL, Tiles.ROCKY:
						cost = 8.0
					Tiles.MOUNTAIN:
						cost = 30.0
					Tiles.SNOW:
						cost = 45.0
				cost += (jnoise.get_noise_2d(x, y) * 0.5 + 0.5) * 14.0
				astar.set_point_weight_scale(p, cost)
		# Each job: [from, to, width] with width -1 = random.
		var jobs: Array = []
		for e in edges:
			jobs.append([reps[e[0]], reps[e[1]], -1])
		# Spur rivers from the hills down to the nearest lake: dead-end
		# waterways worth exploring upstream.
		var hills: Array = []
		for i in n:
			if tiles[i] == Tiles.HILL:
				hills.append(i)
		if not hills.is_empty() and not reps.is_empty():
			for _s in w / 32:
				var hi: int = hills[rng.randi_range(0, hills.size() - 1)]
				var hp := Vector2i(hi % w, hi / w)
				var best_rep: Vector2i = reps[0]
				var best_d: float = 1e20
				for r in reps:
					var dd: float = Vector2(hp - (r as Vector2i)).length()
					if dd < best_d:
						best_d = dd
						best_rep = r
				if best_d < 120.0 and not astar.is_point_solid(hp):
					jobs.append([hp, best_rep, 0])
		for job in jobs:
			var a: Vector2i = job[0]
			var b: Vector2i = job[1]
			var path: Array = astar.get_id_path(a, b)
			if path.size() < 2:
				continue
			# Rivers flow downhill: orient from the higher endpoint.
			if elev[a.y * w + a.x] < elev[b.y * w + b.x]:
				path.reverse()
			var wide: bool = rng.randf() < 0.5 if int(job[2]) < 0 else int(job[2]) == 1
			_carve_river(tiles, flow, path, w, h, wide)

	# ------------------------------------------ shallows, marsh, cleanup
	var water_mask := Tiles.mask(Tiles.ANY_WATER)
	# Lake tiles near land become shallows, open water stays deep.
	var near := PackedByteArray()
	near.resize(n)
	near.fill(0)
	for pass_i in 2:
		var next := near.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var i: int = y * w + x
				if lake_mask[tiles[i]] == 0 or near[i] == 1:
					continue
				for k in [i - 1, i + 1, i - w, i + w]:
					if (pass_i == 0 and water_mask[tiles[k]] == 0) or (pass_i == 1 and near[k] == 1):
						next[i] = 1
						break
		near = next
	for i in n:
		if lake_mask[tiles[i]] == 1:
			tiles[i] = Tiles.SHALLOW if near[i] == 1 else Tiles.DEEP

	# Marsh on wet grassy shores of lakes.
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i: int = y * w + x
			var t: int = tiles[i]
			if (t == Tiles.GRASS or t == Tiles.SAND or t == Tiles.MEADOW) and moist[i] > 0.35:
				if lake_mask[tiles[i - 1]] == 1 or lake_mask[tiles[i + 1]] == 1 \
						or lake_mask[tiles[i - w]] == 1 or lake_mask[tiles[i + w]] == 1:
					tiles[i] = Tiles.MARSH

	# Keep only the largest navigable water body (everything should already
	# be connected; this removes any stray specks).
	var kayak_mask := Tiles.mask(Tiles.KAYAK_OK)
	res = _label(tiles, w, h, kayak_mask)
	labels = res[0]
	sizes = res[1]
	var main_comp: int = -1
	var best: int = -1
	for c in sizes.size():
		if sizes[c] > best:
			best = sizes[c]
			main_comp = c
	for i in n:
		var l: int = labels[i]
		if l >= 0 and l != main_comp:
			tiles[i] = Tiles.MARSH if tiles[i] == Tiles.MARSH else Tiles.SAND
			flow[i] = Vector2.ZERO
	# Marsh that ended up stranded is just grass.
	res = _label(tiles, w, h, kayak_mask)
	labels = res[0]
	sizes = res[1]
	main_comp = -1
	best = -1
	for c in sizes.size():
		if sizes[c] > best:
			best = sizes[c]
			main_comp = c
	for i in n:
		var l: int = labels[i]
		if l >= 0 and l != main_comp:
			tiles[i] = Tiles.GRASS

	wd.tiles = tiles
	wd.flow = flow
	_place_points_of_interest(wd, rng)
	_place_landmarks(wd, rng)
	_place_decor(wd, moist)
	return wd


const LANDMARK_NAMES := {
	"cabin": "Old Paddler's Cabin", "lighthouse": "Lighthouse Point", "springs": "Hot Springs",
	"ruins": "Sunken Ruins", "grove": "Whispering Grove", "falls": "Thunder Falls",
	"hollow": "Bear's Hollow",
}
const LANDMARK_ORDER := ["cabin", "lighthouse", "springs", "ruins", "grove", "falls", "hollow"]
const LANDMARK_CLEAR := {"cabin": 3, "lighthouse": 2, "springs": 2, "ruins": 3, "grove": 4, "falls": 1, "hollow": 2}


static func _is_rock(t: int) -> bool:
	return t == Tiles.MOUNTAIN or t == Tiles.SNOW


## Counts tiles within `r` of (x, y) whose type has table[type] == 1.
static func _count_around(wd: WorldData, x: int, y: int, r: int, table: Array) -> int:
	var n: int = 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t: int = wd.get_tile(x + dx, y + dy)
			if t < table.size() and table[t] == 1:
				n += 1
	return n


## Places one of each unique area. Only land-to-land and lake-to-lake tile
## changes are made, so the water network stays connected.
static func _place_landmarks(wd: WorldData, rng: RandomNumberGenerator) -> void:
	var w: int = wd.width
	var h: int = wd.height
	var m: int = 6
	# Candidate lists gathered in one pass.
	var shore: Array = []       # dry shoreline land next to a lake
	var rocky: Array = []       # open highland
	var bay: Array = []         # shallow water surrounded by lake
	var forest: Array = []      # deep forest
	var falls_a: Array = []     # river below a cliff
	var falls_b: Array = []     # any water below a cliff
	var cave: Array = []        # dry land below a cliff
	var full: int = 25
	for y in range(m, h - m):
		for x in range(m, w - m):
			var t: int = wd.tiles[y * w + x]
			var north: int = wd.tiles[(y - 1) * w + x]
			if Tiles.kayak_ok(t) and t != Tiles.MARSH:
				if _is_rock(north):
					if t == Tiles.RIVER:
						falls_a.append(Vector2i(x, y))
					else:
						falls_b.append(Vector2i(x, y))
				if t == Tiles.SHALLOW and (x + y) % 2 == 0 and _count_around(wd, x, y, 2, Tiles.LAKE_WATER) == full:
					bay.append(Vector2i(x, y))
				continue
			if not Tiles.walk_ok(t) or t == Tiles.SHALLOW or t == Tiles.MARSH:
				continue
			if _is_rock(north) and _count_around(wd, x, y + 1, 1, Tiles.DIGGABLE) == 9:
				cave.append(Vector2i(x, y))
			if (x + y) % 2 == 1:
				continue
			if t == Tiles.SAND or t == Tiles.GRASS or t == Tiles.MEADOW or Tiles.is_forest(t):
				if Tiles.LAKE_WATER[wd.tiles[y * w + x - 1]] == 1 or Tiles.LAKE_WATER[wd.tiles[y * w + x + 1]] == 1 \
						or Tiles.LAKE_WATER[wd.tiles[(y - 1) * w + x]] == 1 or Tiles.LAKE_WATER[wd.tiles[(y + 1) * w + x]] == 1:
					shore.append(Vector2i(x, y))
			if (t == Tiles.ROCKY or t == Tiles.HILL) and _count_around(wd, x, y, 2, Tiles.DIGGABLE) == full:
				rocky.append(Vector2i(x, y))
			if Tiles.is_forest(t) and _count_around(wd, x, y, 3, Tiles.FORESTS) >= 45:
				forest.append(Vector2i(x, y))
	var any_land: Array = shore + rocky + forest
	var start := Vector2(wd.start)
	for id in LANDMARK_ORDER:
		var pool: Array = []
		match id:
			"cabin":
				for c in shore:
					var d: float = Vector2(c).distance_to(start)
					if d >= 18.0 and d <= 70.0:
						pool.append(c)
				if pool.is_empty():
					pool = shore
			"lighthouse":
				# Headlands: shoreline with the most open water around.
				var best_n: int = -1
				for k in mini(300, shore.size()):
					var c: Vector2i = shore[rng.randi_range(0, shore.size() - 1)]
					var n: int = _count_around(wd, c.x, c.y, 5, Tiles.LAKE_WATER)
					if n > best_n and _landmark_ok(wd, c, id):
						best_n = n
						pool = [c]
				if pool.is_empty():
					pool = shore
			"springs":
				pool = rocky if not rocky.is_empty() else any_land
			"ruins":
				pool = bay
			"grove":
				pool = forest if not forest.is_empty() else any_land
			"falls":
				pool = falls_a if not falls_a.is_empty() else falls_b
				if pool.is_empty():
					pool = bay
			"hollow":
				pool = cave if not cave.is_empty() else any_land
		var pick := Vector2i(-1, -1)
		for attempt in 200:
			if pool.is_empty():
				break
			var c: Vector2i = pool[rng.randi_range(0, pool.size() - 1)]
			if _landmark_ok(wd, c, id, 22.0 if attempt < 150 else 10.0):
				pick = c
				break
		if pick.x < 0 and not pool.is_empty():
			pick = pool[rng.randi_range(0, pool.size() - 1)]
		if pick.x < 0:
			pick = wd.start + Vector2i(3 + wd.landmarks.size() * 2, 0)
		wd.landmarks.append({"id": id, "tile": pick, "name": LANDMARK_NAMES[id]})
		_stamp_landmark(wd, id, pick)


static func _landmark_ok(wd: WorldData, c: Vector2i, id: String, spacing: float = 22.0) -> bool:
	var p := Vector2(c)
	if p.distance_to(Vector2(wd.start)) < 12.0:
		return false
	for s in wd.stores:
		if p.distance_to(Vector2(s as Vector2i)) < 14.0:
			return false
	for lm in wd.landmarks:
		if lm["id"] != id and p.distance_to(Vector2(lm["tile"] as Vector2i)) < spacing:
			return false
	return true


static func _stamp_landmark(wd: WorldData, id: String, c: Vector2i) -> void:
	var w: int = wd.width
	match id:
		"cabin":
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var i: int = (c.y + dy) * w + c.x + dx
					if Tiles.DIGGABLE[wd.tiles[i]] == 1:
						wd.tiles[i] = Tiles.GRASS
		"springs":
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var i: int = (c.y + dy) * w + c.x + dx
					if Tiles.DIGGABLE[wd.tiles[i]] == 1:
						wd.tiles[i] = Tiles.ROCKY
		"ruins":
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var i: int = (c.y + dy) * w + c.x + dx
					if wd.tiles[i] == Tiles.DEEP and dx * dx + dy * dy <= 10:
						wd.tiles[i] = Tiles.SHALLOW
		"grove":
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var i: int = (c.y + dy) * w + c.x + dx
					if Tiles.DIGGABLE[wd.tiles[i]] == 1 and dx * dx + dy * dy <= 5:
						wd.tiles[i] = Tiles.MEADOW
		"falls":
			# A strong current pushes away from the foot of the falls.
			for dy in range(0, 4):
				for dx in range(-1, 2):
					var x: int = c.x + dx
					var y: int = c.y + dy
					if wd.in_bounds(x, y) and Tiles.is_water(wd.tiles[y * w + x]):
						wd.flow[y * w + x] = Vector2(0, 0.9 - dy * 0.15)


## Biome for the fertile lowland band, from moisture and temperature.
static func _lowland_biome(m: float, t: float) -> int:
	if m > 0.05:
		if t < -0.18:
			return Tiles.FOREST
		if t > 0.22:
			return Tiles.MAPLE
		return Tiles.BIRCH
	if m < -0.3 and t > -0.1:
		return Tiles.MEADOW
	return Tiles.GRASS


## Cheap deterministic per-tile random in [0, 1).
static func hash01(x: int, y: int, s: int) -> float:
	var hsh: int = (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	hsh = (hsh ^ (hsh >> 13)) * 1274126177
	hsh = hsh ^ (hsh >> 16)
	return float(hsh & 0xFFFF) / 65536.0


## Plants, trees and rocks per biome, stored as id + 1 in wd.decor.
static func _place_decor(wd: WorldData, moist: PackedFloat32Array) -> void:
	var w: int = wd.width
	var h: int = wd.height
	var tiles: PackedByteArray = wd.tiles
	var decor := PackedByteArray()
	decor.resize(w * h)
	decor.fill(0)
	var s: int = wd.seed_value
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i: int = y * w + x
			var r: float = hash01(x, y, s)
			var v: int = 0 if hash01(x, y, s + 1) < 0.5 else 1
			var d: int = -1
			match tiles[i]:
				Tiles.FOREST:
					if r < 0.5: d = Decor.PINE0 + v
					elif r < 0.54: d = Decor.STUMP
					elif r < 0.60: d = Decor.FERN
					elif r < 0.63: d = Decor.MUSHROOMS
				Tiles.BIRCH:
					if r < 0.40: d = Decor.BIRCH0 + v
					elif r < 0.47: d = Decor.OAK0 + v
					elif r < 0.53: d = Decor.FERN
					elif r < 0.56: d = Decor.MUSHROOMS
					elif r < 0.59: d = Decor.BERRYBUSH
				Tiles.MAPLE:
					if r < 0.42: d = Decor.MAPLE0 + v
					elif r < 0.48: d = Decor.OAK0 + v
					elif r < 0.52: d = Decor.MUSHROOMS
					elif r < 0.56: d = Decor.BUSH
				Tiles.GRASS:
					if r < 0.05: d = Decor.OAK0 + v
					elif r < 0.08: d = Decor.BUSH
					elif r < 0.10: d = Decor.BERRYBUSH
					elif r < 0.16: d = Decor.TUFT
					elif r < 0.20: d = Decor.FLOWERS_Y + int(hash01(x, y, s + 2) * 4.0)
					elif r < 0.21: d = Decor.ROCK
				Tiles.MEADOW:
					if r < 0.24: d = Decor.FLOWERS_Y + int(hash01(x, y, s + 2) * 4.0)
					elif r < 0.30: d = Decor.TUFT
					elif r < 0.31: d = Decor.OAK0 + v
					elif r < 0.33: d = Decor.BERRYBUSH
				Tiles.HILL:
					if r < 0.04: d = Decor.PINE0 + v
					elif r < 0.07: d = Decor.ROCK
					elif r < 0.11: d = Decor.TUFT
					elif r < 0.13: d = Decor.BOULDER
				Tiles.ROCKY:
					if r < 0.10: d = Decor.ROCK
					elif r < 0.16: d = Decor.BOULDER
					elif r < 0.18: d = Decor.SNAG
					elif r < 0.21: d = Decor.TUFT
					elif r < 0.23: d = Decor.SNOWPINE
				Tiles.MOUNTAIN:
					if r < 0.72: d = Decor.PEAK0 + int(hash01(x, y, s + 3) * 3.0)
				Tiles.SNOW:
					if r < 0.72: d = Decor.SNOWPEAK0 + v
				Tiles.SAND:
					if r < 0.03: d = Decor.DRIFTWOOD
					elif r < 0.04: d = Decor.ROCK
				Tiles.MARSH:
					if r < 0.25: d = Decor.CATTAIL
					elif r < 0.40: d = Decor.REEDS
					elif r < 0.43: d = Decor.WILLOW
				Tiles.SHALLOW:
					var near_land: bool = Tiles.LAND[tiles[i - 1]] == 1 or Tiles.LAND[tiles[i + 1]] == 1 \
							or Tiles.LAND[tiles[i - w]] == 1 or Tiles.LAND[tiles[i + w]] == 1
					if near_land and r < 0.07: d = Decor.REEDS
					elif moist[i] > 0.0 and r < 0.13: d = Decor.LILY
					elif moist[i] > 0.0 and r < 0.15: d = Decor.LILYFLOWER
			if d >= 0:
				decor[i] = d + 1
	# Keep points of interest clear.
	var clear: Array = [wd.start, wd.start_water]
	for st in wd.stores:
		var sp: Vector2i = st
		for dy in range(-2, 2):
			for dx in range(-2, 3):
				clear.append(sp + Vector2i(dx, dy))
	for dk in wd.store_docks:
		clear.append(dk)
	for tr in wd.treasures:
		clear.append(tr["pos"])
	for lm in wd.landmarks:
		var lt: Vector2i = lm["tile"]
		var lr: int = int(LANDMARK_CLEAR.get(lm["id"], 2))
		for dy in range(-lr, lr + 1):
			for dx in range(-lr, lr + 1):
				clear.append(lt + Vector2i(dx, dy))
	for c in clear:
		var cp: Vector2i = c
		if cp.x >= 0 and cp.y >= 0 and cp.x < w and cp.y < h:
			decor[cp.y * w + cp.x] = 0
	wd.decor = decor


# --------------------------------------------------------------------------
static func _quantile(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return q
	var i: int = clampi(int(q * (sorted.size() - 1)), 0, sorted.size() - 1)
	return sorted[i]


## Flood-fill labelling of 4-connected components where mask[tile] == 1.
## Returns [labels: PackedInt32Array (-1 = not in mask), sizes: Array[int]].
static func _label(tiles: PackedByteArray, w: int, h: int, mask: PackedByteArray) -> Array:
	var n: int = w * h
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(-1)
	var sizes: Array = []
	var stack := PackedInt32Array()
	var cur: int = 0
	for i in n:
		if labels[i] != -1 or mask[tiles[i]] == 0:
			continue
		var size: int = 0
		stack.resize(0)
		stack.append(i)
		labels[i] = cur
		while stack.size() > 0:
			var j: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			size += 1
			var x: int = j % w
			if x > 0:
				var k: int = j - 1
				if labels[k] == -1 and mask[tiles[k]] == 1:
					labels[k] = cur
					stack.append(k)
			if x < w - 1:
				var k: int = j + 1
				if labels[k] == -1 and mask[tiles[k]] == 1:
					labels[k] = cur
					stack.append(k)
			if j >= w:
				var k: int = j - w
				if labels[k] == -1 and mask[tiles[k]] == 1:
					labels[k] = cur
					stack.append(k)
			if j < n - w:
				var k: int = j + w
				if labels[k] == -1 and mask[tiles[k]] == 1:
					labels[k] = cur
					stack.append(k)
		sizes.append(size)
		cur += 1
	return [labels, sizes]


## For each component, the member tile closest to the component centroid.
static func _representatives(labels: PackedInt32Array, sizes: Array, sumx: PackedFloat64Array,
		sumy: PackedFloat64Array, w: int, h: int) -> Array:
	var count: int = sizes.size()
	var reps: Array = []
	var best := PackedFloat32Array()
	reps.resize(count)
	best.resize(count)
	best.fill(1e20)
	var cx := PackedFloat32Array()
	var cy := PackedFloat32Array()
	cx.resize(count)
	cy.resize(count)
	for c in count:
		cx[c] = sumx[c] / maxf(1.0, float(sizes[c]))
		cy[c] = sumy[c] / maxf(1.0, float(sizes[c]))
		reps[c] = Vector2i(int(cx[c]), int(cy[c]))
	for y in h:
		for x in w:
			var l: int = labels[y * w + x]
			if l < 0:
				continue
			var dx: float = x - cx[l]
			var dy: float = y - cy[l]
			var d: float = dx * dx + dy * dy
			if d < best[l]:
				best[l] = d
				reps[l] = Vector2i(x, y)
	return reps


## Minimum spanning tree (Prim) over representative points plus a few extra
## edges to create loops. Returns Array of [a, b] index pairs.
static func _mst_edges(reps: Array, rng: RandomNumberGenerator) -> Array:
	var count: int = reps.size()
	var edges: Array = []
	if count < 2:
		return edges
	var in_tree := PackedByteArray()
	in_tree.resize(count)
	in_tree.fill(0)
	var dist := PackedFloat32Array()
	dist.resize(count)
	dist.fill(1e20)
	var parent := PackedInt32Array()
	parent.resize(count)
	parent.fill(-1)
	dist[0] = 0.0
	var existing := {}
	for _iter in count:
		var u: int = -1
		var bd: float = 1e21
		for i in count:
			if in_tree[i] == 0 and dist[i] < bd:
				bd = dist[i]
				u = i
		if u == -1:
			break
		in_tree[u] = 1
		if parent[u] >= 0:
			edges.append([parent[u], u])
			existing[_edge_key(parent[u], u)] = true
		var pu: Vector2i = reps[u]
		for v in count:
			if in_tree[v] == 1:
				continue
			var pv: Vector2i = reps[v]
			var d: float = Vector2(pu - pv).length()
			if d < dist[v]:
				dist[v] = d
				parent[v] = u
	# Extra loop edges: connect some lakes to their nearest non-tree neighbour.
	for i in count:
		if rng.randf() > 0.3:
			continue
		var pi: Vector2i = reps[i]
		var best_j: int = -1
		var best_d: float = 1e20
		for j in count:
			if j == i or existing.has(_edge_key(i, j)):
				continue
			var d: float = Vector2(pi - (reps[j] as Vector2i)).length()
			if d < best_d:
				best_d = d
				best_j = j
		if best_j >= 0 and best_d < 140.0:
			edges.append([i, best_j])
			existing[_edge_key(i, best_j)] = true
	return edges


static func _edge_key(a: int, b: int) -> int:
	return mini(a, b) * 100000 + maxi(a, b)


static func _carve_river(tiles: PackedByteArray, flow: PackedVector2Array, path: Array, w: int, h: int,
		wide: bool) -> void:
	var count: int = path.size()
	for k in count:
		var p: Vector2i = path[k]
		# Smoothed direction of travel for the current.
		var a: Vector2i = path[maxi(0, k - 3)]
		var b: Vector2i = path[mini(count - 1, k + 3)]
		var dir := Vector2(b - a)
		if dir.length() > 0.0:
			dir = dir.normalized()
		var r_lo: int = -1
		var r_hi: int = 1 if wide else 0
		for dy in range(r_lo, r_hi + 1):
			for dx in range(r_lo, r_hi + 1):
				var x: int = p.x + dx
				var y: int = p.y + dy
				if x < 1 or y < 1 or x >= w - 1 or y >= h - 1:
					continue
				var i: int = y * w + x
				var t: int = tiles[i]
				if t == Tiles.DEEP or t == Tiles.SHALLOW:
					continue
				tiles[i] = Tiles.RIVER
				flow[i] = dir


static func _place_points_of_interest(wd: WorldData, rng: RandomNumberGenerator) -> void:
	var w: int = wd.width
	var h: int = wd.height
	var tiles: PackedByteArray = wd.tiles
	var center := Vector2(w * 0.5, h * 0.5)

	# Shoreline candidates: dry land tile with navigable water next to it.
	var shore: Array = []
	var shore_water: Array = []
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var t: int = tiles[y * w + x]
			if t != Tiles.SAND and t != Tiles.GRASS and t != Tiles.MEADOW and not Tiles.is_forest(t):
				continue
			for d in dirs:
				var nt: int = tiles[(y + d.y) * w + (x + d.x)]
				if nt == Tiles.DEEP or nt == Tiles.SHALLOW:
					shore.append(Vector2i(x, y))
					shore_water.append(Vector2i(x + d.x, y + d.y))
					break
	if shore.is_empty():
		# Degenerate world; fall back to the centre.
		wd.start = Vector2i(w / 2, h / 2)
		wd.start_water = wd.start
		return

	var best_i: int = 0
	var best_d: float = 1e20
	for i in shore.size():
		var d: float = Vector2(shore[i]).distance_squared_to(center)
		if d < best_d:
			best_d = d
			best_i = i
	wd.start = shore[best_i]
	wd.start_water = shore_water[best_i]

	# First store close to the start, the rest spread out (Poisson-ish).
	var order: Array = range(shore.size())
	_shuffle(order, rng)
	var first_i: int = -1
	var first_d: float = 1e20
	for i in shore.size():
		var d: float = Vector2(shore[i]).distance_to(Vector2(wd.start))
		if d >= 4.0 and d < first_d:
			first_d = d
			first_i = i
	if first_i >= 0:
		wd.stores.append(shore[first_i])
		wd.store_docks.append(shore_water[first_i])
	for i in order:
		if wd.stores.size() >= MAX_STORES:
			break
		var p: Vector2i = shore[i]
		var ok := true
		for s in wd.stores:
			if Vector2(p).distance_to(Vector2(s as Vector2i)) < STORE_SPACING:
				ok = false
				break
		if ok:
			wd.stores.append(p)
			wd.store_docks.append(shore_water[i])

	# Treasure on dry land, away from stores and the start.
	var tries: int = 0
	while wd.treasures.size() < TREASURE_COUNT and tries < 30000:
		tries += 1
		var x: int = rng.randi_range(4, w - 5)
		var y: int = rng.randi_range(4, h - 5)
		var t: int = tiles[y * w + x]
		if not Tiles.is_diggable(t):
			continue
		var p := Vector2i(x, y)
		if Vector2(p).distance_to(Vector2(wd.start)) < 12.0:
			continue
		var ok := true
		for s in wd.stores:
			if Vector2(p).distance_to(Vector2(s as Vector2i)) < 8.0:
				ok = false
				break
		if ok:
			for tr in wd.treasures:
				if Vector2(p).distance_to(Vector2(tr["pos"] as Vector2i)) < TREASURE_SPACING:
					ok = false
					break
		if ok:
			wd.treasures.append({"pos": p, "loot": _roll_loot(rng)})


static func _roll_loot(rng: RandomNumberGenerator) -> String:
	var total: int = 0
	for e in LOOT_TABLE:
		total += int(e[1])
	var r: int = rng.randi_range(1, total)
	for e in LOOT_TABLE:
		r -= int(e[1])
		if r <= 0:
			return e[0]
	return "coin_purse"


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
