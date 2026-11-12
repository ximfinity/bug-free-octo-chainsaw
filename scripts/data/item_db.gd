extends RefCounted
## Static game data: items, store stock, kayak and paddle upgrades.
## Edit these tables to rebalance the game.

## icon = index into assets/sprites.png (see scripts/art.gd)
## price = what a store pays you; key items never take inventory slots.
const ITEMS := {
	"meat_raw": {"name": "Raw Meat", "icon": 16, "stack": 10, "price": 4, "food": 10, "cook": "meat_cooked"},
	"meat_cooked": {"name": "Cooked Meat", "icon": 17, "stack": 10, "price": 9, "food": 35},
	"fish_raw": {"name": "Raw Fish", "icon": 18, "stack": 10, "price": 5, "food": 8, "cook": "fish_cooked"},
	"fish_cooked": {"name": "Cooked Fish", "icon": 19, "stack": 10, "price": 10, "food": 25},
	"berries": {"name": "Wild Berries", "icon": 34, "stack": 20, "price": 2, "food": 6},
	"trail_mix": {"name": "Trail Mix", "icon": 23, "stack": 10, "price": 6, "food": 20},
	"hide": {"name": "Animal Hide", "icon": 20, "stack": 10, "price": 8},
	"wood": {"name": "Firewood", "icon": 21, "stack": 20, "price": 1},
	"arrows": {"name": "Arrows", "icon": 22, "stack": 50, "price": 1},
	"coin_purse": {"name": "Old Coin Purse", "icon": 24, "stack": 5, "price": 60, "treasure": true},
	"compass": {"name": "Antique Compass", "icon": 26, "stack": 5, "price": 90, "treasure": true},
	"gem": {"name": "River Gem", "icon": 27, "stack": 5, "price": 130, "treasure": true},
	"gold_idol": {"name": "Golden Idol", "icon": 25, "stack": 5, "price": 200, "treasure": true},
	"bow": {"name": "Hunting Bow", "icon": 30, "stack": 1, "price": 0, "key": true},
	"tent": {"name": "Tent", "icon": 31, "stack": 1, "price": 0, "key": true},
	"shovel": {"name": "Shovel", "icon": 29, "stack": 1, "price": 0, "key": true},
	"fishing_rod": {"name": "Fishing Rod", "icon": 33, "stack": 1, "price": 0, "key": true},
}

## Order in which Q (eat) picks food.
const EAT_ORDER := ["meat_cooked", "fish_cooked", "trail_mix", "berries", "fish_raw", "meat_raw"]

## What every "100's of Kayaks" sells.
const STOCK := [
	{"id": "arrows", "qty": 10, "cost": 12},
	{"id": "trail_mix", "qty": 1, "cost": 14},
	{"id": "wood", "qty": 3, "cost": 6},
	{"id": "shovel", "qty": 1, "cost": 40},
	{"id": "fishing_rod", "qty": 1, "cost": 35},
]

const TREASURE_MAP_COST := 60
const KAYAK_RETRIEVE_COST := 20

const HULLS := [
	{"name": "Rec Kayak", "cost": 0, "speed": 78.0, "slots": 10,
		"desc": "Stable and forgiving. Room for 10 stacks."},
	{"name": "Touring Kayak", "cost": 250, "speed": 102.0, "slots": 16,
		"desc": "Longer hull, faster cruising, 16 stacks of storage."},
	{"name": "Expedition Kayak", "cost": 700, "speed": 128.0, "slots": 24,
		"desc": "Built for long trips: fastest hull, 24 stacks."},
]

const PADDLES := [
	{"name": "Wooden Paddle", "cost": 0, "accel": 110.0, "stamina": 1.0,
		"desc": "Heavy but honest."},
	{"name": "Aluminum Paddle", "cost": 180, "accel": 170.0, "stamina": 0.8,
		"desc": "Lighter: quicker acceleration, power strokes cost less stamina."},
	{"name": "Carbon Paddle", "cost": 500, "accel": 250.0, "stamina": 0.55,
		"desc": "Feather-light. Punch upstream with ease."},
]


static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id, "icon": 12, "stack": 10, "price": 0})


static func item_name(id: String) -> String:
	return str(item(id).get("name", id))


static func is_key(id: String) -> bool:
	return bool(item(id).get("key", false))
