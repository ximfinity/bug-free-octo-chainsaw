extends RefCounted
## Tracks progress along the story trail (scripts/data/quest_db.gd).

const QuestDB = preload("res://scripts/data/quest_db.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")

var main
var step: int = 0
var progress: Array = []
var _poll: float = 0.0


func setup(main_node) -> void:
	main = main_node
	_begin_step()


func is_complete() -> bool:
	return step >= QuestDB.STEPS.size()


func current() -> Dictionary:
	if is_complete():
		return {}
	return QuestDB.STEPS[step]


func current_id() -> String:
	return str(current().get("id", ""))


## Landmark id the current step points at ("" if none).
func target_landmark() -> String:
	return str(current().get("mark", ""))


func wants_talk(who: String) -> bool:
	for g in current().get("goals", []):
		if g["kind"] == "talk" and str(g.get("id", "")).begins_with(who):
			return true
	return false


func _begin_step() -> void:
	progress = []
	if is_complete():
		return
	var st: Dictionary = current()
	for g in st["goals"]:
		progress.append(0)
	# Credit things that were already done before the step began.
	var places: Dictionary = main.places
	for i in st["goals"].size():
		var g: Dictionary = st["goals"][i]
		var gid: String = str(g.get("id", ""))
		match str(g["kind"]):
			"discover_place":
				if bool(places.get("found", {}).get(gid, false)):
					progress[i] = 1
			"use_place":
				var done := false
				match gid:
					"lighthouse": done = bool(places.get("lighthouse_climbed", false))
					"ruins": done = int(places.get("ruins_left", 3)) < 3
					"falls": done = bool(places.get("falls_open", false))
					"hollow_pack": done = bool(places.get("pack_taken", false))
				if done:
					progress[i] = 1
			"defeat":
				if gid == "elder_bear" and bool(places.get("bear_defeated", false)):
					progress[i] = 1
	var mark: String = str(st.get("mark", ""))
	if mark != "":
		main.mark_landmark(mark)
	# A step whose goals were all done beforehand completes straight away
	# (e.g. the lighthouse was climbed before "The Light" came up).
	_check()


## Game events feed the goals. Returns true if the step completed.
func event(kind: String, id: String = "", n: int = 1) -> bool:
	if is_complete():
		return false
	var st: Dictionary = current()
	for i in st["goals"].size():
		var g: Dictionary = st["goals"][i]
		if g["kind"] != kind:
			continue
		var gid: String = str(g.get("id", ""))
		if gid != "" and gid != id:
			continue
		if progress[i] < int(g["n"]):
			progress[i] = mini(int(g["n"]), progress[i] + n)
	return _check()


## Polls "have item" goals.
func tick(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0 or is_complete():
		return
	_poll = 0.5
	var st: Dictionary = current()
	var changed := false
	for i in st["goals"].size():
		var g: Dictionary = st["goals"][i]
		if g["kind"] == "have":
			var have: int = 0
			for c in main.party:
				have += c.inventory.count(str(g["id"]))
			have = mini(have, int(g["n"]))
			if have > progress[i]:
				progress[i] = have
				changed = true
	if changed:
		_check()


func _check() -> bool:
	if is_complete():
		return false
	var st: Dictionary = current()
	var met: int = 0
	for i in st["goals"].size():
		if progress[i] >= int(st["goals"][i]["n"]):
			met += 1
	var done: bool = met >= 1 if bool(st.get("any", false)) else met == st["goals"].size()
	if not done:
		return false
	_complete()
	return true


func _complete() -> void:
	var st: Dictionary = current()
	var reward: Dictionary = st.get("reward", {})
	var parts := PackedStringArray()
	var c: int = int(reward.get("coins", 0))
	if c > 0:
		main.coins += c
		parts.append("%d coins" % c)
	for id in reward.get("items", {}):
		var n: int = int(reward["items"][id])
		main.player.gain(id, n, main.player.position)
		parts.append("%s x%d" % [ItemDB.item_name(id), n] if n > 1 else ItemDB.item_name(id))
	if bool(reward.get("founders_paddle", false)):
		main.paddle_level = ItemDB.FOUNDERS_PADDLE
		for ch in main.party:
			ch.apply_upgrades()
		parts.append("the Founder's Paddle")
	step += 1
	main.on_quest_step_done(st, ", ".join(parts))
	_begin_step()


## Lines for the HUD tracker: [title, [goal lines...]]
func tracker() -> Array:
	if is_complete():
		return ["Trail complete", ["Explore freely. Fill your journal!"]]
	var st: Dictionary = current()
	var lines: Array = []
	for i in st["goals"].size():
		var g: Dictionary = st["goals"][i]
		var need: int = int(g["n"])
		var tick_s: String = "[x] " if progress[i] >= need else "[ ] "
		var count: String = " %d/%d" % [progress[i], need] if need > 1 else ""
		lines.append(tick_s + str(g["label"]) + count)
	return [str(st["title"]), lines]


func to_dict() -> Dictionary:
	return {"step": step, "progress": progress}


func from_dict(d: Dictionary) -> void:
	step = clampi(int(d.get("step", 0)), 0, QuestDB.STEPS.size())
	_begin_step()
	var saved: Array = d.get("progress", [])
	for i in mini(saved.size(), progress.size()):
		progress[i] = maxi(progress[i], int(saved[i]))
