extends RefCounted
## Small helpers for building UI in code.

const Art = preload("res://scripts/art.gd")
## UI scale factor: sizes passed to these helpers are in "design" units
## (from the original 640x360 layout) and multiplied by K for 1280x720.
const K := 2


static func label(text: String, size: int = 10, color: Color = Color(0.95, 0.93, 0.86)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size * K)
	l.add_theme_color_override("font_color", color)
	return l


static func outlined(text: String, size: int = 10, color: Color = Color.WHITE) -> Label:
	var l := label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3 * K)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, cb: Callable, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	if min_w > 0.0:
		b.custom_minimum_size = Vector2(min_w * K, 0)
	return b


## Item icon from assets/items.png.
static func icon(index: int, size: float = 16.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Art.item(index)
	r.custom_minimum_size = Vector2(size * K, size * K)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return r


## A centred panel filling most of the screen, returned as [root, content_vbox].
static func modal(title: String, theme: Theme) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420 * K, 250 * K)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var t := label(title, 14, Color(1.0, 0.85, 0.45))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(HSeparator.new())
	return [root, vb]


## Sets anchors (0..1) and pixel offsets explicitly.
static func place(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, o_r: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = o_r
	c.offset_bottom = ob


static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
