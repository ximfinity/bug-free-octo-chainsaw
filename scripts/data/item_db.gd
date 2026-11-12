extends RefCounted
## Static game data: items, store stock, kayak and paddle upgrades.
## Edit these tables to rebalance the game.

## icon = index into assets/items.png (see scripts/art.gd)
## price = what a store pays you; key items never take inventory slots.
const ITEMS := {
	"meat_raw": {"name": "Raw Meat", "icon": 0, "stack": 10, "price": 4, "food": 10, "cook": "meat_cooked"},
	"meat_cooked": {"name": "Cooked Meat", "icon": 1, "stack": 10, "price": 9, "food": 35},
	"fish_raw": {"name": "Raw Fish", "icon": 2, "stack": 10, "price": 5, "food": 8, "cook": "fish_cooked"},
	"fish_cooked": {"name": "Cooked Fish", "icon": 3, "stack": 10, "price": 10, "food": 25},
	"berries": {"name": "Wild Berries", "icon": 4, "stack": 20, "price": 2, "food": 6},
	"trail_mix": {"name": "Trail Mix", "icon": 5, "stack": 10, "price": 6, "food": 20},
	"hide": {"name": "Animal Hide", "icon": 6, "stack": 10, "price": 8},
	"wood": {"name": "Firewood", "icon": 7, "stack": 20, "price": 1},
	"arrows": {"name": "Arrows", "icon": 8, "stack": 50, "price": 1},
	"coin_purse": {"name": "Old Coin Purse", "icon": 9, "stack": 5, "price": 60, "treasure": true},
	"compass": {"name": "Antique Compass", "icon": 10, "stack": 5, "price": 90, "treasure": true},
	"gem": {"name": "River Gem", "icon": 11, "stack": 5, "price": 130, "treasure": true},
	"gold_idol": {"name": "Golden Idol", "icon": 12, "stack": 5, "price": 200, "treasure": true},
	"bow": {"name": "Hunting Bow", "icon": 15, "stack": 1, "price": 0, "key": true},
	"tent": {"name": "Tent", "icon": 16, "stack": 1, "price": 0, "key": true},
	"shovel": {"name": "Shovel", "icon": 14, "stack": 1, "price": 0, "key": true},
	"fishing_rod": {"name": "Fishing Rod", "icon": 17, "stack": 1, "price": 0, "key": true},
	"knife": {"name": "Hunting Knife", "icon": 29, "stack": 1, "price": 0, "key": true},
	"hatchet": {"name": "Hatchet", "icon": 30, "stack": 1, "price": 0, "key": true},
	"carrot_seeds": {"name": "Carrot Seeds", "icon": 19, "stack": 20, "price": 2, "seed": "carrot"},
	"potato_seeds": {"name": "Seed Potatoes", "icon": 20, "stack": 20, "price": 3, "seed": "potato"},
	"pumpkin_seeds": {"name": "Pumpkin Seeds", "icon": 21, "stack": 20, "price": 4, "seed": "pumpkin"},
	"carrot": {"name": "Carrot", "icon": 22, "stack": 20, "price": 6, "food": 15},
	"potato": {"name": "Potato", "icon": 23, "stack": 20, "price": 5, "food": 8, "cook": "potato_baked"},
	"potato_baked": {"name": "Baked Potato", "icon": 24, "stack": 20, "price": 10, "food": 30},
	"pumpkin": {"name": "Pumpkin", "icon": 25, "stack": 5, "price": 25, "food": 40},
	"mushroom": {"name": "Wild Mushroom", "icon": 33, "stack": 20, "price": 3, "food": 6},
	"spider_silk": {"name": "Spider Silk", "icon": 26, "stack": 20, "price": 12},
	"wildcat_pelt": {"name": "Wildcat Pelt", "icon": 27, "stack": 5, "price": 25},
	"bear_hide": {"name": "Bear Hide", "icon": 28, "stack": 5, "price": 60},
	"bear_meat": {"name": "Bear Meat", "icon": 0, "stack": 10, "price": 8, "food": 12, "cook": "meat_cooked"},
	"worms": {"name": "Worms", "icon": 31, "stack": 30, "price": 1},
	"stone": {"name": "Smooth Stone", "icon": 32, "stack": 20, "price": 1},
}

## Crops: seed item, harvested item, total grow time in in-game days.
const CROPS := {
	"carrot": {"index": 0, "seed": "carrot_seeds", "yield": "carrot", "days": 1.0},
	"potato": {"index": 1, "seed": "potato_seeds", "yield": "potato", "days": 1.5},
	"pumpkin": {"index": 2, "seed": "pumpkin_seeds", "yield": "pumpkin", "days": 2.0},
}
const CROP_ORDER := ["carrot", "potato", "pumpkin"]

## Melee weapons, best first. "paddle" is always available.
const WEAPONS := {
	"hatchet": {"damage": 3, "cooldown": 0.5, "knockback": 18.0, "name": "hatchet"},
	"knife": {"damage": 2, "cooldown": 0.32, "knockback": 10.0, "name": "knife"},
	"paddle": {"damage": 1, "cooldown": 0.45, "knockback": 26.0, "name": "paddle"},
}

## Order in which Q (eat) picks food.
const EAT_ORDER := ["meat_cooked", "potato_baked", "fish_cooked", "pumpkin", "trail_mix", "carrot",
	"berries", "mushroom", "fish_raw", "potato", "bear_meat", "meat_raw"]

## What every "100's of Kayaks" sells.
const STOCK := [
	{"id": "arrows", "qty": 10, "cost": 12},
	{"id": "trail_mix", "qty": 1, "cost": 14},
	{"id": "wood", "qty": 3, "cost": 6},
	{"id": "shovel", "qty": 1, "cost": 40},
	{"id": "fishing_rod", "qty": 1, "cost": 35},
	{"id": "carrot_seeds", "qty": 5, "cost": 8},
	{"id": "potato_seeds", "qty": 5, "cost": 12},
	{"id": "pumpkin_seeds", "qty": 3, "cost": 15},
	{"id": "knife", "qty": 1, "cost": 60},
	{"id": "hatchet", "qty": 1, "cost": 90},
]

const TREASURE_MAP_COST := 60
const KAYAK_RETRIEVE_COST := 20

## Speeds are in pixels/second at 32px tiles. turn_rate in radians/second;
## glide = forward drag (lower glides further); side_drag resists sliding.
const HULLS := [
	{"name": "Rec Kayak", "cost": 0, "speed": 150.0, "slots": 10, "turn_rate": 3.4, "glide": 0.9,
		"side_drag": 5.0, "desc": "Stable, forgiving and quick to turn. Room for 10 stacks."},
	{"name": "Touring Kayak", "cost": 250, "speed": 196.0, "slots": 16, "turn_rate": 2.8, "glide": 0.6,
		"side_drag": 6.0, "desc": "Longer hull that glides and tracks straight. 16 stacks."},
	{"name": "Expedition Kayak", "cost": 700, "speed": 245.0, "slots": 24, "turn_rate": 2.4, "glide": 0.42,
		"side_drag": 7.0, "desc": "Built for long trips: fastest and glides furthest. 24 stacks."},
]

const PADDLES := [
	{"name": "Wooden Paddle", "cost": 0, "accel": 210.0, "stamina": 1.0,
		"desc": "Heavy but honest."},
	{"name": "Aluminum Paddle", "cost": 180, "accel": 320.0, "stamina": 0.8,
		"desc": "Lighter: quicker acceleration, power strokes cost less stamina."},
	{"name": "Carbon Paddle", "cost": 500, "accel": 470.0, "stamina": 0.55,
		"desc": "Feather-light. Punch upstream with ease."},
]


static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id, "icon": 13, "stack": 10, "price": 0})


static func item_name(id: String) -> String:
	return str(item(id).get("name", id))


static func is_key(id: String) -> bool:
	return bool(item(id).get("key", false))
