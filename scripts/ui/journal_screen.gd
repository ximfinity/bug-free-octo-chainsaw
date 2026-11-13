extends Control
## Creature Journal (J): every creature you've seen, and the rare finds
## you've collected. Unseen entries show as silhouettes.

const UI = preload("res://scripts/ui/ui_util.gd")
const Art = preload("res://scripts/art.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const AnimalScript = preload("res://scripts/entities/animal.gd")

const SECTIONS := [
	["Wildlife", ["rabbit", "deer", "duck"]],
	["Dangerous", ["wolf", "spider", "wildcat", "bear"]],
	["Rare", ["fox", "otter", "loon", "owl", "white_stag", "moose", "spirit", "elder_bear"]],
]
const HINTS := {
	"fox": "Grassland and meadows, at dawn and dusk.",
	"otter": "Playing in rivers on sunny days.",
	"loon": "Deep lakes. Dives and pops up elsewhere.",
	"owl": "Forests at night. Shy - flies off if you get close.",
	"white_stag": "Deep in birch and maple woods. Very rare.",
	"moose": "Marshes and lakeshores. Don't crowd it.",
	"spirit": "Deep water on dark nights. Paddle close...",
	"elder_bear": "An ancient giant of the old forests.",
}
const FIND_ORDER := ["rabbit_foot", "antler", "wolf_fang", "wildcat_claw", "bear_claw", "amber",
	"bird_egg", "golden_mushroom", "arrowhead", "old_coin", "fox_pelt", "loon_feather", "owl_feather",
	"moose_antler", "white_antler", "golden_trout", "elder_claw", "spirit_pearl", "coin_purse",
	"compass", "gem", "gold_idol", "old_boot"]

var main
var content: VBoxContainer
var creature_grid: GridContainer
var finds_grid: GridContainer
var summary: Label


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Array = UI.modal("Creature Journal", GameState.ui_theme)
	add_child(m[0])
	content = m[1]
	summary = UI.label("", 9, Color(1.0, 0.9, 0.6))
	content.add_child(summary)
	var hb := HBoxContainer.new()
	content.add_child(hb)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(520, 420)
	hb.add_child(left)
	creature_grid = GridContainer.new()
	creature_grid.columns = 1
	creature_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(creature_grid)
	hb.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(320, 0)
	hb.add_child(right)
	right.add_child(UI.label("Rare finds", 11, Color(1.0, 0.85, 0.45)))
	finds_grid = GridContainer.new()
	finds_grid.columns = 6
	right.add_child(finds_grid)
	content.add_child(UI.button("Close (J)", func(): main.close_screen()))


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	var creatures: Dictionary = main.journal["creatures"]
	var finds: Dictionary = main.journal["finds"]
	UI.clear_children(creature_grid)
	var seen: int = 0
	var total: int = 0
	for sec in SECTIONS:
		creature_grid.add_child(UI.label(sec[0], 11, Color(1.0, 0.85, 0.45)))
		for kind in sec[1]:
			total += 1
			var n: int = int(creatures.get(kind, 0))
			if n > 0:
				seen += 1
			creature_grid.add_child(_creature_row(kind, n))
	UI.clear_children(finds_grid)
	var found: int = 0
	for id in FIND_ORDER:
		var n2: int = int(finds.get(id, 0))
		if n2 > 0:
			found += 1
		finds_grid.add_child(_find_cell(id, n2))
	var bottle: int = int(finds.get("bottle", 0))
	summary.text = "Creatures seen: %d / %d      Rare finds: %d / %d%s" % [
		seen, total, found, FIND_ORDER.size(),
		"      Bottles found: %d" % bottle if bottle > 0 else ""]


func _creature_row(kind: String, n: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var tr := TextureRect.new()
	tr.texture = Art.creature_frame(kind, 0)
	tr.custom_minimum_size = Vector2(56, 56)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if n == 0:
		tr.modulate = Color(0.08, 0.06, 0.12, 0.85)  # silhouette
	row.add_child(tr)
	var vb := VBoxContainer.new()
	row.add_child(vb)
	var title: String = str(AnimalScript.NAMES.get(kind, kind)) if n > 0 else "???"
	var rare: bool = bool(AnimalScript.KINDS[kind].get("rare", false))
	var col: Color = ItemDB.RARITY_COLORS[2] if rare else Color(0.95, 0.93, 0.86)
	vb.add_child(UI.label(title, 10, col if n > 0 else Color(0.6, 0.6, 0.65)))
	var sub: String = "Seen %d time%s" % [n, "" if n == 1 else "s"] if n > 0 else str(HINTS.get(kind, "Not yet seen."))
	vb.add_child(UI.label(sub, 8, Color(0.75, 0.78, 0.82)))
	return row


func _find_cell(id: String, n: int) -> Control:
	var tr := TextureRect.new()
	tr.texture = Art.item(int(ItemDB.item(id).get("icon", 13)))
	tr.custom_minimum_size = Vector2(48, 48)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if n == 0:
		tr.modulate = Color(0.08, 0.06, 0.12, 0.8)
		tr.tooltip_text = "???"
	else:
		tr.tooltip_text = "%s (%s) x%d" % [ItemDB.item_name(id), ItemDB.RARITY_NAMES[ItemDB.rarity(id)], n]
	return tr


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("journal") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		main.close_screen()
