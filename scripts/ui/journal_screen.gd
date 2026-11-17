extends Control
## Creature Journal (J): every creature you've seen, and the rare finds
## you've collected. Unseen entries show as silhouettes.

const UI = preload("res://scripts/ui/ui_util.gd")
const Art = preload("res://scripts/art.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")
const AnimalScript = preload("res://scripts/entities/animal.gd")
const VariantShader = preload("res://shaders/variant.gdshader")

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
	"compass", "gem", "gold_idol", "stone_tablet", "bronze_mask", "jade_ring", "shiny_tuft", "silver_pelt", "golden_pelt", "old_boot"]

var main
var content: VBoxContainer
var creature_grid: GridContainer
var finds_grid: GridContainer
var summary: Label
var progress: Control
var _completion: float = 0.0
var pages: Array = []
var tab_buttons: Array = []
var places_box: VBoxContainer
var trail_box: VBoxContainer
var tab: int = 0
const QuestDB = preload("res://scripts/data/quest_db.gd")
const PLACE_HINTS := {
	"cabin": "A lakeshore clearing not far from where you started.",
	"lighthouse": "A headland with open water on every side.",
	"springs": "High rocky ground. Look for steam.",
	"ruins": "A shallow bay with stone in the water.",
	"grove": "Deep forest where the trees grow giant.",
	"falls": "Where water meets a mountain wall.",
	"hollow": "A cave at the foot of the mountains.",
}


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Array = UI.modal("Journal", GameState.ui_theme)
	add_child(m[0])
	content = m[1]
	summary = UI.label("", 9, Color(1.0, 0.9, 0.6))
	content.add_child(summary)
	progress = Control.new()
	progress.custom_minimum_size = Vector2(0, 16)
	progress.draw.connect(_draw_progress)
	content.add_child(progress)
	var tabs := HBoxContainer.new()
	content.add_child(tabs)
	var names: Array = ["Trail", "Creatures", "Places"]
	for i in names.size():
		var idx: int = i
		var b := UI.button(names[i], func(): _set_tab(idx), 90)
		tabs.add_child(b)
		tab_buttons.append(b)
	var trail_scroll := ScrollContainer.new()
	trail_scroll.custom_minimum_size = Vector2(920, 420)
	content.add_child(trail_scroll)
	trail_box = VBoxContainer.new()
	trail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trail_scroll.add_child(trail_box)
	var hb := HBoxContainer.new()
	content.add_child(hb)
	var places_scroll := ScrollContainer.new()
	places_scroll.custom_minimum_size = Vector2(920, 420)
	content.add_child(places_scroll)
	places_box = VBoxContainer.new()
	places_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	places_scroll.add_child(places_box)
	pages = [trail_scroll, hb, places_scroll]
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(600, 420)
	hb.add_child(left)
	creature_grid = GridContainer.new()
	creature_grid.columns = 1
	creature_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(creature_grid)
	hb.add_child(VSeparator.new())
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(300, 0)
	hb.add_child(right)
	right.add_child(UI.label("Rare finds", 11, Color(1.0, 0.85, 0.45)))
	finds_grid = GridContainer.new()
	finds_grid.columns = 5
	right.add_child(finds_grid)
	content.add_child(UI.button("Close (J)", func(): main.close_screen()))


func open() -> void:
	visible = true
	refresh()
	_set_tab(tab)


func _set_tab(i: int) -> void:
	tab = i
	for k in pages.size():
		pages[k].visible = k == i
		tab_buttons[k].modulate = Color(1, 1, 1) if k == i else Color(0.65, 0.65, 0.7)


func _refresh_trail() -> void:
	UI.clear_children(trail_box)
	var q = main.quests
	trail_box.add_child(UI.label("The Old Paddler's Trail", 12, Color(1.0, 0.85, 0.45)))
	for i in QuestDB.STEPS.size():
		var st: Dictionary = QuestDB.STEPS[i]
		if i < q.step:
			trail_box.add_child(UI.label("[done]  %d. %s" % [i + 1, st["title"]], 9, Color(0.55, 0.85, 0.55)))
		elif i == q.step:
			trail_box.add_child(UI.label("%d. %s" % [i + 1, st["title"]], 11, Color(1.0, 0.95, 0.75)))
			var t := UI.label(str(st["text"]), 9, Color(0.9, 0.9, 0.85))
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			t.custom_minimum_size = Vector2(880, 0)
			trail_box.add_child(t)
			for line in q.tracker()[1]:
				trail_box.add_child(UI.label("      " + str(line), 9, Color(0.75, 0.9, 1.0)))
		else:
			trail_box.add_child(UI.label("%d. ???" % (i + 1), 9, Color(0.5, 0.5, 0.55)))
	if q.is_complete():
		trail_box.add_child(UI.label("Trail complete. The Founder's Paddle is yours.", 11, Color(1.0, 0.81, 0.25)))


func _refresh_places() -> int:
	UI.clear_children(places_box)
	var found: Dictionary = main.places.get("found", {})
	var n: int = 0
	for lm in main.world.landmarks:
		var id: String = lm["id"]
		var got: bool = bool(found.get(id, false))
		if got:
			n += 1
		places_box.add_child(UI.label(str(lm["name"]) if got else "???", 11,
			Color(0.37, 0.9, 0.85) if got else Color(0.6, 0.6, 0.65)))
		places_box.add_child(UI.label("      " + ("Discovered." if got else str(PLACE_HINTS.get(id, ""))), 9,
			Color(0.75, 0.78, 0.82)))
	return n


func refresh() -> void:
	var creatures: Dictionary = main.journal["creatures"]
	var finds: Dictionary = main.journal["finds"]
	var variants: Dictionary = main.journal.get("variants", {})
	UI.clear_children(creature_grid)
	var seen: int = 0
	var total: int = 0
	var vseen: int = 0
	var vtotal: int = 0
	for sec in SECTIONS:
		creature_grid.add_child(UI.label(sec[0], 11, Color(1.0, 0.85, 0.45)))
		for kind in sec[1]:
			total += 1
			var n: int = int(creatures.get(kind, 0))
			if n > 0:
				seen += 1
			var got: Array = []
			for v in 4:
				var c: int = int(variants.get("%s:%d" % [kind, v], 0))
				# Older saves only counted sightings: treat those as Normal.
				if v == 0 and c == 0 and n > 0:
					c = n
				got.append(c)
				vtotal += 1
				if c > 0:
					vseen += 1
			if n == 0:
				for c2 in got:
					n += int(c2)
				if n > 0:
					seen += 1
			creature_grid.add_child(_creature_row(kind, n, got))
	UI.clear_children(finds_grid)
	var found: int = 0
	for id in FIND_ORDER:
		var n2: int = int(finds.get(id, 0))
		if n2 > 0:
			found += 1
		finds_grid.add_child(_find_cell(id, n2))
	var bottle: int = int(finds.get("bottle", 0))
	_refresh_trail()
	var places_found: int = _refresh_places()
	var places_total: int = main.world.landmarks.size()
	_completion = float(vseen + found + places_found) / float(maxi(1, vtotal + FIND_ORDER.size() + places_total))
	summary.text = "Journal %d%% complete    Creatures %d/%d    Variants %d/%d    Rare finds %d/%d    Places %d/%d%s" % [
		int(round(_completion * 100.0)), seen, total, vseen, vtotal, found, FIND_ORDER.size(),
		places_found, places_total,
		"      Bottles %d" % bottle if bottle > 0 else ""]
	progress.queue_redraw()


func _creature_row(kind: String, n: int, got: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(250, 0)
	row.add_child(info)
	var title: String = str(AnimalScript.NAMES.get(kind, kind)) if n > 0 else "???"
	var rare: bool = bool(AnimalScript.KINDS[kind].get("rare", false))
	var col: Color = ItemDB.RARITY_COLORS[2] if rare else Color(0.95, 0.93, 0.86)
	info.add_child(UI.label(title, 10, col if n > 0 else Color(0.6, 0.6, 0.65)))
	var sub: String = "Seen %d time%s" % [n, "" if n == 1 else "s"] if n > 0 else str(HINTS.get(kind, "Not yet seen."))
	var sl := UI.label(sub, 8, Color(0.75, 0.78, 0.82))
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(sl)
	# One slot per colour variant: tinted thumbnail once seen, silhouette until then.
	for v in 4:
		var slot := VBoxContainer.new()
		slot.add_theme_constant_override("separation", 0)
		var tr := TextureRect.new()
		tr.texture = Art.creature_frame(kind, 0)
		tr.custom_minimum_size = Vector2(56, 56)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var c: int = int(got[v])
		if c == 0:
			tr.modulate = Color(0.08, 0.06, 0.12, 0.8)
		elif v > 0:
			var mat := ShaderMaterial.new()
			mat.shader = VariantShader
			mat.set_shader_parameter("mode", v)
			tr.material = mat
		tr.tooltip_text = "%s - %s" % [ItemDB.VARIANT_NAMES[v], ("seen %d" % c) if c > 0 else "not yet seen"]
		slot.add_child(tr)
		var tag := UI.label(ItemDB.VARIANT_NAMES[v] if c > 0 else "?", 7,
			ItemDB.VARIANT_COLORS[v] if c > 0 else Color(0.45, 0.45, 0.5))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(tag)
		row.add_child(slot)
	return row


func _draw_progress() -> void:
	var w: float = progress.size.x
	progress.draw_rect(Rect2(0, 3, w, 10), Color(0.1, 0.08, 0.13))
	progress.draw_rect(Rect2(1, 4, (w - 2) * _completion, 8), Color(1.0, 0.81, 0.25))


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
