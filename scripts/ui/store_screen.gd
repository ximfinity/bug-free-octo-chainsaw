extends Control
## "100's of Kayaks" trading screen: sell, buy, upgrade, services.

const UI = preload("res://scripts/ui/ui_util.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")

var main
var store_index: int = 0
var content: VBoxContainer
var coins_label: Label
var tabs: TabContainer
var sell_list: VBoxContainer
var buy_list: VBoxContainer
var upgrade_list: VBoxContainer
var service_list: VBoxContainer


func _ready() -> void:
	UI.place(self, 0, 0, 1, 1, 0, 0, 0, 0)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Array = UI.modal("100's of Kayaks", GameState.ui_theme)
	add_child(m[0])
	content = m[1]
	var greet := UI.label("\"Welcome, paddler! Hundreds of kayaks, and everything to go with 'em.\"", 9, Color(0.8, 0.9, 1.0))
	content.add_child(greet)
	coins_label = UI.label("", 10, Color(1.0, 0.88, 0.4))
	content.add_child(coins_label)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(880, 400)
	content.add_child(tabs)
	sell_list = _tab("Sell")
	buy_list = _tab("Buy")
	upgrade_list = _tab("Upgrades")
	service_list = _tab("Services")
	content.add_child(UI.button("Leave (Esc)", func(): main.close_screen()))


func _tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	tabs.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	return vb


func open(index: int) -> void:
	store_index = index
	visible = true
	refresh()


func refresh() -> void:
	var p = main.player
	coins_label.text = "Your coins: %d      Pack: %d/%d slots" % [p.coins, p.inventory.slots_used(), p.inventory.max_slots]
	_build_sell(p)
	_build_buy(p)
	_build_upgrades(p)
	_build_services(p)


func _row(icon_index: int, text: String, color: Color = Color(0.95, 0.93, 0.86)) -> HBoxContainer:
	var row := HBoxContainer.new()
	if icon_index >= 0:
		row.add_child(UI.icon(icon_index, 16))
	var l := UI.label(text, 10, color)
	l.custom_minimum_size = Vector2(500, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	return row


func _build_sell(p) -> void:
	UI.clear_children(sell_list)
	var any := false
	for id in p.inventory.ids_sorted():
		if ItemDB.is_key(id):
			continue
		var info: Dictionary = ItemDB.item(id)
		var price: int = int(info.get("price", 0))
		if price <= 0:
			continue
		any = true
		var count: int = p.inventory.count(id)
		var row := _row(int(info.get("icon", 12)), "%s x%d  -  %d each" % [info["name"], count, price], ItemDB.rarity_color(id))
		var sid: String = id
		row.add_child(UI.button("Sell 1", func(): _sell(sid, 1)))
		row.add_child(UI.button("All", func(): _sell(sid, p.inventory.count(sid))))
		sell_list.add_child(row)
	if not any:
		sell_list.add_child(UI.label("Nothing to sell. Hides, meat, fish and treasure fetch good prices.", 9))


func _sell(id: String, n: int) -> void:
	var p = main.player
	if n <= 0 or not p.inventory.remove(id, n):
		return
	var earned: int = int(ItemDB.item(id).get("price", 0)) * n
	p.coins += earned
	main.message("Sold %d %s for %d coins." % [n, ItemDB.item_name(id), earned])
	refresh()


func _build_buy(p) -> void:
	UI.clear_children(buy_list)
	for entry in ItemDB.STOCK:
		var id: String = entry["id"]
		var qty: int = int(entry["qty"])
		var cost: int = int(entry["cost"])
		var info: Dictionary = ItemDB.item(id)
		var owned_tool: bool = ItemDB.is_key(id) and p.inventory.has(id)
		var row := _row(int(info.get("icon", 12)), "%s%s  -  %d coins%s" % [
			info["name"], (" x%d" % qty) if qty > 1 else "", cost, "  (owned)" if owned_tool else ""])
		var b := UI.button("Buy", func(): _buy(id, qty, cost))
		b.disabled = owned_tool or p.coins < cost
		row.add_child(b)
		buy_list.add_child(row)


func _buy(id: String, qty: int, cost: int) -> void:
	var p = main.player
	if p.coins < cost:
		main.message("Not enough coins.")
		return
	if p.inventory.room_for(id) < qty:
		main.message("No room in your pack.")
		return
	p.coins -= cost
	p.inventory.add(id, qty)
	main.message("Bought %s." % ItemDB.item_name(id))
	refresh()


func _build_upgrades(p) -> void:
	UI.clear_children(upgrade_list)
	upgrade_list.add_child(UI.label("Hull (speed and storage)", 11, Color(1.0, 0.85, 0.45)))
	for i in ItemDB.HULLS.size():
		var h: Dictionary = ItemDB.HULLS[i]
		var row := _row(-1, "%s - %s" % [h["name"], h["desc"]])
		if i <= p.hull_level:
			row.add_child(UI.label("owned" if i == p.hull_level else "-", 9, Color(0.6, 0.9, 0.6)))
		else:
			var lvl: int = i
			var b := UI.button("%d coins" % int(h["cost"]), func(): _upgrade("hull", lvl))
			b.disabled = p.coins < int(h["cost"]) or i != p.hull_level + 1
			row.add_child(b)
		upgrade_list.add_child(row)
	upgrade_list.add_child(UI.label("Paddle (acceleration and stamina)", 11, Color(1.0, 0.85, 0.45)))
	for i in ItemDB.PADDLES.size():
		var pd: Dictionary = ItemDB.PADDLES[i]
		var row := _row(-1, "%s - %s" % [pd["name"], pd["desc"]])
		if i <= p.paddle_level:
			row.add_child(UI.label("owned" if i == p.paddle_level else "-", 9, Color(0.6, 0.9, 0.6)))
		else:
			var lvl: int = i
			var b := UI.button("%d coins" % int(pd["cost"]), func(): _upgrade("paddle", lvl))
			b.disabled = p.coins < int(pd["cost"]) or i != p.paddle_level + 1
			row.add_child(b)
		upgrade_list.add_child(row)


func _upgrade(kind: String, level: int) -> void:
	var p = main.player
	var table: Array = ItemDB.HULLS if kind == "hull" else ItemDB.PADDLES
	var cost: int = int(table[level]["cost"])
	if p.coins < cost:
		return
	p.coins -= cost
	if kind == "hull":
		p.hull_level = level
	else:
		p.paddle_level = level
	for c in main.party:
		c.apply_upgrades()
	main.message("Upgraded to the %s!" % table[level]["name"])
	refresh()


func _build_services(p) -> void:
	UI.clear_children(service_list)
	var row := _row(13, "Treasure map - marks an undiscovered dig site on your map. %d coins" % ItemDB.TREASURE_MAP_COST)
	var b := UI.button("Buy", _buy_map)
	b.disabled = p.coins < ItemDB.TREASURE_MAP_COST or main.unrevealed_treasure_count() == 0
	row.add_child(b)
	service_list.add_child(row)
	var far: bool = main.kayak_far_from_store(store_index)
	var cost: int = ItemDB.KAYAK_RETRIEVE_COST if p.coins >= ItemDB.KAYAK_RETRIEVE_COST else 0
	var row2 := _row(-1, "Kayak shuttle - we'll fetch your kayak to our dock. %s" % ("%d coins" % cost if cost > 0 else "Free for broke paddlers!"))
	var b2 := UI.button("Fetch", func(): _retrieve(cost))
	b2.disabled = not far
	row2.add_child(b2)
	service_list.add_child(row2)
	service_list.add_child(UI.label("Tip: sleeping at camp saves your game.", 9, Color(0.75, 0.75, 0.7)))


func _buy_map() -> void:
	var p = main.player
	if p.coins < ItemDB.TREASURE_MAP_COST:
		return
	if main.reveal_treasure_near(main.world.stores[store_index]):
		p.coins -= ItemDB.TREASURE_MAP_COST
		main.message("The map shows an X! Check your map (M).")
	refresh()


func _retrieve(cost: int) -> void:
	var p = main.player
	p.coins -= cost
	main.retrieve_kayak_to_store(store_index)
	main.message("Your kayak is waiting at the dock.")
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		main.close_screen()
