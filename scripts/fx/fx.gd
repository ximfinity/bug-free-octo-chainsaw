extends RefCounted
## One-shot visual effects: ripple rings, splashes, sparkle emitters, wake.

const Art = preload("res://scripts/art.gd")
const RippleScript = preload("res://scripts/fx/ripple.gd")


## Expanding ring on the water.
static func ripple(parent: Node, pos: Vector2, radius: float = 18.0, life: float = 0.9) -> void:
	var r = RippleScript.new()
	r.position = pos
	r.max_radius = radius
	r.life = life
	parent.add_child(r)


## Burst of white droplets.
static func splash(parent: Node, pos: Vector2, amount: int = 8) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.z_index = 1
	p.texture = Art.dot_texture()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 0.45
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 25.0
	p.initial_velocity_max = 55.0
	p.gravity = Vector2(0, 160)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color = Color(0.92, 0.98, 1.0, 0.9)
	p.emitting = true
	parent.add_child(p)
	p.get_tree().create_timer(1.0, false).timeout.connect(p.queue_free)


## Continuous soft wake behind a moving kayak. Add as a child of the world
## (local_coords false) and move it to the stern each frame.
static func make_wake() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Art.dot_texture()
	p.local_coords = false
	p.amount = 40
	p.lifetime = 1.4
	p.emitting = false
	p.z_index = -5
	p.direction = Vector2(-1, 0)
	p.spread = 28.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 18.0
	p.damping_min = 6.0
	p.damping_max = 10.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.75))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	p.color_ramp = ramp
	return p


## Twinkling glints for buried treasure; drawn unshaded so it shows at night.
static func make_sparkles() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Art.prop(Art.SPARKLE)
	p.amount = 5
	p.lifetime = 1.3
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 11.0
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.initial_velocity_min = 4.0
	p.initial_velocity_max = 10.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	p.color = Color(1.0, 0.95, 0.6)
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	return p
