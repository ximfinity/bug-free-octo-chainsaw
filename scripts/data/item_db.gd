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
	"coin_purse": {"name": "Old Coin Purse", "icon": 9, "stack": 5, "price": 60, "treasure": true, "rarity": 1},
	"compass": {"name": "Antique Compass", "icon": 10, "stack": 5, "price": 90, "treasure": true, "rarity": 2},
	"gem": {"name": "River Gem", "icon": 11, "stack": 5, "price": 130, "treasure": true, "rarity": 2},
	"gold_idol": {"name": "Golden Idol", "icon": 12, "stack": 5, "price": 200, "treasure": true, "rarity": 3},
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
	"spider_silk": {"name": "Spider Silk", "icon": 26, "stack": 20, "price": 12, "rarity": 1},
	"wildcat_pelt": {"name": "Wildcat Pelt", "icon": 27, "stack": 5, "price": 25, "rarity": 1},
	"bear_hide": {"name": "Bear Hide", "icon": 28, "stack": 5, "price": 60, "rarity": 2},
	"bear_meat": {"name": "Bear Meat", "icon": 0, "stack": 10, "price": 8, "food": 12, "cook": "meat_cooked"},
	"worms": {"name": "Worms", "icon": 31, "stack": 30, "price": 1},
	"stone": {"name": "Smooth Stone", "icon": 32, "stack": 20, "price": 1},
	# --- rare finds -------------------------------------------------------
	"white_antler": {"name": "White Stag Antler", "icon": 34, "stack": 5, "price": 250, "rarity": 3},
	"moose_antler": {"name": "Moose Antler", "icon": 35, "stack": 5, "price": 150, "rarity": 2},
	"fox_pelt": {"name": "Red Fox Pelt", "icon": 36, "stack": 5, "price": 80, "rarity": 2},
	"loon_feather": {"name": "Loon Feather", "icon": 37, "stack": 10, "price": 60, "rarity": 2},
	"owl_feather": {"name": "Owl Feather", "icon": 38, "stack": 10, "price": 60, "rarity": 2},
	"golden_trout": {"name": "Golden Trout", "icon": 39, "stack": 5, "price": 150, "food": 50, "rarity": 3},
	"spirit_pearl": {"name": "Spirit Pearl", "icon": 40, "stack": 5, "price": 500, "rarity": 4},
	"elder_claw": {"name": "Elder Bear Claw", "icon": 41, "stack": 5, "price": 400, "rarity": 4},
	"rabbit_foot": {"name": "Lucky Rabbit's Foot", "icon": 42, "stack": 1, "price": 60, "rarity": 2,
		"desc": "Carrying one doubles your chance of rare drops."},
	"antler": {"name": "Deer Antler", "icon": 43, "stack": 10, "price": 25, "rarity": 1},
	"wolf_fang": {"name": "Wolf Fang", "icon": 44, "stack": 10, "price": 20, "rarity": 1},
	"amber": {"name": "Ancient Amber", "icon": 45, "stack": 10, "price": 90, "rarity": 2},
	"wildcat_claw": {"name": "Wildcat Claw", "icon": 46, "stack": 10, "price": 30, "rarity": 1},
	"bear_claw": {"name": "Bear Claw", "icon": 47, "stack": 10, "price": 45, "rarity": 1},
	"bird_egg": {"name": "Bird Egg", "icon": 48, "stack": 10, "price": 8, "food": 15, "rarity": 1},
	"golden_mushroom": {"name": "Golden Mushroom", "icon": 49, "stack": 10, "price": 70, "food": 25,
		"heal": 35, "rarity": 2},
	"arrowhead": {"name": "Ancient Arrowhead", "icon": 50, "stack": 10, "price": 40, "rarity": 1},
	"old_coin": {"name": "Old Silver Coin", "icon": 51, "stack": 10, "price": 75, "rarity": 2},
	"old_boot": {"name": "Soggy Old Boot", "icon": 52, "stack": 5, "price": 1, "rarity": 0},
	"shiny_tuft": {"name": "Shiny Tuft", "icon": 54, "stack": 10, "price": 80, "rarity": 2},
	"silver_pelt": {"name": "Silver Pelt", "icon": 55, "stack": 5, "price": 220, "rarity": 3},
	"golden_pelt": {"name": "Golden Pelt", "icon": 56, "stack": 5, "price": 550, "rarity": 4},
}

## Creature colour variants: 0 normal, 1 shiny, 2 silver, 3 gold.
const VARIANT_NAMES := ["Normal", "Shiny", "Silver", "Golden"]
const VARIANT_COLORS := [Color(0.95, 0.93, 0.86), Color(1.0, 0.48, 0.85), Color(0.82, 0.86, 0.93),
	Color(1.0, 0.81, 0.25)]
## Base odds (1 in N) before luck; checked rarest first.
const VARIANT_ODDS := [0, 20, 60, 150]
## Trophy dropped by a variant creature, and first-sighting bonus coins.
const VARIANT_TROPHY := ["", "shiny_tuft", "silver_pelt", "golden_pelt"]
const VARIANT_REWARD := [0, 40, 120, 300]


## Rolls a colour variant. luck multiplies the odds (2.0 = twice as likely).
static func roll_variant(luck: float = 1.0) -> int:
	for v in [3, 2, 1]:
		if randf() < luck / float(VARIANT_ODDS[v]):
			return v
	return 0

## Rarity tiers: name and colour (used for item names, pickup sparkles).
const RARITY_NAMES := ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const RARITY_COLORS := [Color(0.95, 0.93, 0.86), Color(0.48, 0.89, 0.42), Color(0.37, 0.71, 1.0),
	Color(0.78, 0.49, 1.0), Color(1.0, 0.81, 0.25)]

## Chance-based extra drops, by source (animal kind or activity).
## [item, chance]. A Lucky Rabbit's Foot in the party doubles every chance.
const RARE_DROPS := {
	"rabbit": [["rabbit_foot", 0.03]],
	"deer": [["antler", 0.18]],
	"wolf": [["wolf_fang", 0.25]],
	"spider": [["amber", 0.06]],
	"wildcat": [["wildcat_claw", 0.2]],
	"bear": [["bear_claw", 0.35]],
	"fox": [["rabbit_foot", 0.08]],
	"chop": [["bird_egg", 0.05], ["amber", 0.012]],
	"dig": [["arrowhead", 0.04], ["old_coin", 0.015]],
	"forage": [["golden_mushroom", 0.035]],
	"till": [["arrowhead", 0.02]],
	"harvest": [["golden_mushroom", 0.01]],
}

## Fishing outcomes beyond a normal fish (rolled in order).
const FISH_RARES := [["golden_trout", 0.035], ["bottle", 0.02], ["old_boot", 0.04]]

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


static func rarity(id: String) -> int:
	return int(item(id).get("rarity", 0))


static func rarity_color(id: String) -> Color:
	return RARITY_COLORS[clampi(rarity(id), 0, RARITY_COLORS.size() - 1)]


static func is_key(id: String) -> bool:
	return bool(item(id).get("key", false))
