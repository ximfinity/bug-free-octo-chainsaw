extends Control
## Inventory, eating and simple crafting (Tab).

const UI = preload("res://scripts/ui/ui_util.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")

var main
var content: VBoxContainer
var list: GridContainer
var header: Label
var craft_box: VBoxContainer


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Array = UI.modal("Pack", GameState.ui_theme)
	m[1].get_child(0).name = "Title"
	add_child(m[0])
	content = m[1]
	header = UI.label("", 9, Color(0.8, 0.85, 0.9))
	content.add_child(header)
	var hb := HBoxContainer.new()
	content.add_child(hb)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 380)
	hb.add_child(scroll)
	list = GridContainer.new()
	list.columns = 1
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	hb.add_child(VSeparator.new())
	craft_box = VBoxContainer.new()
	craft_box.custom_minimum_size = Vector2(280, 0)
	hb.add_child(craft_box)
	content.add_child(UI.button("Close (Tab)", func(): main.close_screen()))


func open() -> void:
	visible = true
	refresh()


func refresh() -> void:
	var p = main.player
	var title := content.get_node_or_null("Title") as Label
	if title:
		title.text = "%s's Pack" % p.char_name
	var hull: Dictionary = ItemDB.HULLS[p.hull_level]
	var paddle: Dictionary = ItemDB.PADDLES[p.paddle_level]
	header.text = "%s + %s    Slots %d/%d    Coins %d    Explored %.1f%%    Animals hunted %d    Treasure found %d" % [
		hull["name"], paddle["name"], p.inventory.slots_used(), p.inventory.max_slots, p.coins,
		main.exploration.percent(), int(main.stats.get("kills", 0)), int(main.stats.get("treasures", 0))]
	UI.clear_children(list)
	var ids: Array = p.inventory.ids_sorted()
	if ids.is_empty():
		list.add_child(UI.label("Your pack is empty.", 10))
	for id in ids:
		var info: Dictionary = ItemDB.item(id)
		var row := HBoxContainer.new()
		row.add_child(UI.icon(int(info.get("icon", 12)), 16))
		var name_l := UI.label("%s x%d" % [info.get("name", id), p.inventory.count(id)], 10)
		name_l.custom_minimum_size = Vector2(260, 0)
		row.add_child(name_l)
		if float(info.get("food", 0)) > 0.0:
			var eat_id: String = id
			row.add_child(UI.button("Eat (+%d)" % int(info["food"]), func():
				p.eat(eat_id)
				refresh()))
		elif bool(info.get("key", false)):
			row.add_child(UI.label("tool", 8, Color(0.6, 0.7, 0.8)))
		var other = main.partner_of(p)
		if other != null and not other.downed and other.position.distance_to(p.position) < 80.0:
			var give_id: String = id
			row.add_child(UI.button("Give", func():
				var n: int = 1 if ItemDB.is_key(give_id) else p.inventory.count(give_id)
				var moved: int = other.inventory.add(give_id, n)
				if moved > 0:
					p.inventory.remove(give_id, moved)
					main.message("Gave %d %s to %s." % [moved, ItemDB.item_name(give_id), other.char_name])
				else:
					main.message("%s has no room." % other.char_name)
				refresh()))
		list.add_child(row)

	UI.clear_children(craft_box)
	craft_box.add_child(UI.label("Crafting", 11, Color(1.0, 0.85, 0.45)))
	var b := UI.button("5 Arrows (1 wood)", func():
		if p.inventory.has("wood") and p.inventory.room_for("arrows") >= 5:
			p.inventory.remove("wood", 1)
			p.inventory.add("arrows", 5)
			main.message("Crafted 5 arrows.")
		else:
			main.message("Need 1 firewood and room for arrows.")
		refresh())
	craft_box.add_child(b)
	craft_box.add_child(UI.label("Camp: press C with a tent.\nFire needs %d wood.\nCook raw food at a lit fire (F).\nSleep by the fire at night (F)." % 3, 8, Color(0.8, 0.8, 0.75)))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("inventory") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		main.close_screen()
