extends Node2D
## A unique map area. One script covers all seven; `id` selects the look,
## the proximity effects and what F does there.
##   cabin      - Old Paddler (quests), bed, safe porch
##   lighthouse - climb to reveal the map, safe at night
##   springs    - soak to heal and stay warm
##   ruins      - dive from the kayak for three relics
##   grove      - ancient trees, golden mushrooms, rare creatures
##   falls      - strong current, hidden cove chest
##   hollow     - the Elder Bear's lair and the Old Paddler's stolen pack

const Art = preload("res://scripts/art.gd")
const FX = preload("res://scripts/fx/fx.gd")
const ItemDB = preload("res://scripts/data/item_db.gd")

const REACH := {"cabin": 90.0, "lighthouse": 80.0, "springs": 60.0, "ruins": 110.0, "grove": 0.0,
	"falls": 70.0, "hollow": 64.0}
const SAFE := {"cabin": 140.0, "lighthouse": 150.0, "springs": 100.0}
const RELICS := ["stone_tablet", "bronze_mask", "jade_ring"]
const GROVE_RADIUS := 32.0 * 4.5

var id: String = ""
var tile: Vector2i
var main
var light: PointLight2D
var anim_sprite: Sprite2D
var extra: Node2D
var npc: Node2D
var _t: float = 0.0
var _fresh: bool = true
var _soak_msg: float = 0.0
var _bear_cd: float = 0.0


func _ready() -> void:
	y_sort_enabled = true
	match id:
		"cabin":
			add_child(Art.landmark_sprite(Art.LM_CABIN))
			npc = _npc(Art.LM_NPC_PADDLER, Vector2(52, 14), "Old Paddler")
			_light(Vector2(-12, -26), 1.8, Color(1.0, 0.72, 0.4))
		"lighthouse":
			add_child(Art.landmark_sprite(Art.LM_LIGHTHOUSE))
			npc = _npc(Art.LM_NPC_KEEPER, Vector2(34, 10), "Keeper")
			_light(Vector2(0, -88), 4.0, Color(1.0, 0.93, 0.7))
		"springs":
			for off in [Vector2(-22, 6), Vector2(30, -14)]:
				var s: Sprite2D = Art.landmark_sprite(Art.LM_SPRING)
				s.position = off
				s.z_index = -8
				s.z_as_relative = false
				add_child(s)
				add_child(_steam(off + Vector2(0, -14)))
		"ruins":
			var layout: Array = [[Art.LM_ARCH, Vector2(0, -20)], [Art.LM_PILLAR, Vector2(-70, 10)],
				[Art.LM_PILLAR_BROKEN, Vector2(62, 30)], [Art.LM_PILLAR, Vector2(84, -40)],
				[Art.LM_PILLAR_BROKEN, Vector2(-48, -58)], [Art.LM_PILLAR_BROKEN, Vector2(-10, 62)]]
			for e in layout:
				var s2: Sprite2D = Art.landmark_sprite(e[0])
				s2.position = e[1]
				add_child(s2)
		"grove":
			for k in 7:
				var ang: float = k * TAU / 7.0 + 0.3
				var s3: Sprite2D = Art.landmark_sprite(Art.LM_ANCIENT_TREE)
				s3.position = Vector2(cos(ang), sin(ang) * 0.8) * 32.0 * 3.3
				add_child(s3)
		"falls":
			anim_sprite = Art.landmark_sprite(Art.LM_FALLS)
			anim_sprite.position = Vector2(0, -16)
			add_child(anim_sprite)
			extra = Art.landmark_sprite(Art.LM_CHEST)
			extra.position = Vector2(0, -26)
			extra.scale = Vector2(0.8, 0.8)
			extra.visible = false
			add_child(extra)
			add_child(_steam(Vector2(0, -20)))
		"hollow":
			var cave: Sprite2D = Art.landmark_sprite(Art.LM_CAVE)
			cave.position = Vector2(0, -14)
			add_child(cave)
			var bones: Sprite2D = Art.landmark_sprite(Art.LM_BONES)
			bones.position = Vector2(-40, 26)
			add_child(bones)
			extra = Art.landmark_sprite(Art.LM_PACK)
			extra.position = Vector2(30, 4)
			add_child(extra)


func _npc(cell: int, off: Vector2, label: String) -> Node2D:
	var n := Node2D.new()
	n.position = off
	n.add_child(Art.landmark_sprite(cell))
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.13))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(120, 18)
	l.position = Vector2(-60, -68)
	n.add_child(l)
	add_child(n)
	return n


func _light(off: Vector2, scale_: float, color: Color) -> void:
	light = PointLight2D.new()
	light.texture = Art.light_texture()
	light.texture_scale = scale_
	light.color = color
	light.position = off
	light.energy = 0.0
	add_child(light)


func _steam(off: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = off
	p.z_index = 4
	p.texture = Art.dot_texture()
	p.amount = 10
	p.lifetime = 2.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 14.0
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 18.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.5))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	return p


func state() -> Dictionary:
	return main.places


func near(c, dist: float) -> bool:
	return c.position.distance_to(position) < dist


func is_safe(pos: Vector2) -> bool:
	return SAFE.has(id) and pos.distance_to(position) < float(SAFE[id])


## Label for the F prompt, or "" when there's nothing to do here.
func prompt(c) -> String:
	var st: Dictionary = state()
	if not near(c, float(REACH[id])):
		return ""
	match id:
		"cabin":
			if not c.is_paddling():
				if main.quests.wants_talk("paddler"):
					return "Talk"
				return "Sleep" if main.day_night.is_evening() else "Talk"
		"lighthouse":
			if not c.is_paddling():
				return "Climb lighthouse"
		"ruins":
			if c.is_paddling() and int(st.get("ruins_left", 3)) > 0:
				return "Dive for relics"
		"falls":
			if c.is_paddling() and not bool(st.get("falls_open", false)):
				return "Open cove chest"
		"hollow":
			if not c.is_paddling() and not bool(st.get("pack_taken", false)) \
					and c.position.distance_to(position + Vector2(30, 4)) < 44.0:
				return "Take the old pack"
	return ""


func interact(c) -> void:
	var st: Dictionary = state()
	match id:
		"cabin":
			if not main.quests.wants_talk("paddler") and main.day_night.is_evening():
				main.sleep_now(true)
			else:
				main.talk_to("paddler")
		"lighthouse":
			main.exploration.reveal(tile, 35)
			main.exploration.flush()
			Sfx.play("chime", position)
			if not bool(st.get("lighthouse_climbed", false)):
				st["lighthouse_climbed"] = true
				main.talk_to("keeper")
			else:
				main.message("From the lamp room you can see for miles. Your map fills in.")
			main.quest_event("use_place", "lighthouse")
		"ruins":
			var left: int = int(st.get("ruins_left", 3))
			if left <= 0:
				return
			var relic: String = RELICS[3 - left]
			st["ruins_left"] = left - 1
			FX.splash(main.entities, c.position, 14)
			FX.ripple(main.entities, c.position, 40.0, 1.2)
			Sfx.play("splash", c.position)
			c.gain(relic, 1, c.position)
			main.on_rare_item(c, relic)
			main.message("You dive among the drowned pillars and surface with a %s." % ItemDB.item_name(relic))
			main.quest_event("use_place", "ruins")
		"falls":
			st["falls_open"] = true
			(extra as Sprite2D).texture = Art.landmark(Art.LM_CHEST_OPEN)
			main.coins += 150
			c.gain("gem", 1, c.position)
			main.on_rare_item(c, "gem")
			Sfx.play("coin", position)
			main.message("Behind the falls: a chest! 150 coins and a River Gem.", ItemDB.RARITY_COLORS[3])
			main.quest_event("use_place", "falls")
		"hollow":
			st["pack_taken"] = true
			extra.visible = false
			c.inventory.add("old_pack", 1)
			Sfx.play("pickup", position)
			main.message("You grab the Old Paddler's pack. Now get out of here!", ItemDB.RARITY_COLORS[2])
			main.quest_event("use_place", "hollow_pack")


func _process(delta: float) -> void:
	if main == null or not main.ready_done:
		return
	_t += delta
	var p = main.player
	if light:
		var dark: float = main.day_night.darkness()
		light.energy = dark * (1.1 if id == "lighthouse" else 0.8)
		if id == "lighthouse":
			light.texture_scale = 3.6 + sin(_t * 1.3) * 0.6
	match id:
		"springs":
			_soak_msg -= delta
			for c in main.party:
				if c.downed or c.is_paddling():
					continue
				if c.position.distance_to(position + Vector2(-22, -8)) < 34.0 \
						or c.position.distance_to(position + Vector2(30, -28)) < 34.0:
					c.health = minf(100.0, c.health + 2.0 * delta)
					c.exposure = 0.0
					c.poison = 0.0
					if c.controlled and _soak_msg <= 0.0:
						_soak_msg = 30.0
						main.message("The hot water soaks the ache out of your arms.", Color(0.6, 0.95, 1.0))
						main.quest_event("use_place", "springs")
		"falls":
			anim_sprite.texture = Art.landmark(Art.LM_FALLS + int(_t * 8.0) % 4)
			var close: bool = near(p, 100.0)
			anim_sprite.modulate.a = move_toward(anim_sprite.modulate.a, 0.45 if close else 1.0, delta * 2.0)
			extra.visible = close or bool(state().get("falls_open", false))
		"hollow":
			extra.visible = not bool(state().get("pack_taken", false))
			_bear_cd -= delta
			if _bear_cd <= 0.0 and near(p, 32.0 * 13) and not bool(state().get("bear_defeated", false)):
				_bear_cd = 4.0
				main.ensure_elder_bear(position + Vector2(0, 44))
		"grove":
			if near(p, GROVE_RADIUS):
				if _fresh:
					_fresh = false
					for k in 2:
						main.spawn_pickup("golden_mushroom", 1, position + Vector2(randf_range(-50, 50), randf_range(-40, 40)))
				main.on_enter_grove(self)


func on_morning() -> void:
	_fresh = true
