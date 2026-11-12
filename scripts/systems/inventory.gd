extends RefCounted
## Item counts with a stack-slot limit set by the kayak hull. Key items
## (tools) never use slots.

const ItemDB = preload("res://scripts/data/item_db.gd")

signal changed

var counts: Dictionary = {}
var max_slots: int = 10


func count(id: String) -> int:
	return int(counts.get(id, 0))


func has(id: String, n: int = 1) -> bool:
	return count(id) >= n


func _slots_for(id: String, n: int) -> int:
	if n <= 0 or ItemDB.is_key(id):
		return 0
	var stack: int = maxi(1, int(ItemDB.item(id).get("stack", 10)))
	return int(ceil(float(n) / float(stack)))


func slots_used() -> int:
	var total: int = 0
	for id in counts:
		total += _slots_for(id, int(counts[id]))
	return total


## How many of `id` could be added right now.
func room_for(id: String) -> int:
	if ItemDB.is_key(id):
		return 1 if count(id) == 0 else 0
	var stack: int = maxi(1, int(ItemDB.item(id).get("stack", 10)))
	var cur: int = count(id)
	var used_other: int = slots_used() - _slots_for(id, cur)
	var free_slots: int = max_slots - used_other
	return maxi(0, free_slots * stack - cur)


## Adds up to n items, returns how many were actually added.
func add(id: String, n: int = 1) -> int:
	var added: int = mini(n, room_for(id))
	if added > 0:
		counts[id] = count(id) + added
		changed.emit()
	return added


func remove(id: String, n: int = 1) -> bool:
	if count(id) < n:
		return false
	var left: int = count(id) - n
	if left <= 0:
		counts.erase(id)
	else:
		counts[id] = left
	changed.emit()
	return true


func ids_sorted() -> Array:
	var ids: Array = counts.keys()
	ids.sort_custom(func(a, b): return ItemDB.item_name(a) < ItemDB.item_name(b))
	return ids


func to_dict() -> Dictionary:
	return counts.duplicate()


func from_dict(d: Dictionary) -> void:
	counts.clear()
	for id in d:
		var c: int = int(d[id])
		if c > 0:
			counts[str(id)] = c
	changed.emit()
