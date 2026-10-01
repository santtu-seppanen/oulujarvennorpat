extends RefCounted
## Minipelien käyttöliittymän palikat valikon tyyliin: tumma paneeli keltaisella reunalla, tekstit ja palkki.

const YELLOW := Color(1.0, 0.8, 0.1)


## Paneeli ruudun reunaan (anchor: "bottom", "top" tai "center"); palauttaa sisällön VBoxin.
static func panel(parent: Node, anchor := "bottom", width := 520.0) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.09, 0.85)
	sb.border_color = YELLOW
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 14)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(width, 0)
	match anchor:
		"bottom":
			pc.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			pc.grow_vertical = Control.GROW_DIRECTION_BEGIN
			pc.offset_bottom = -130
		"top":
			pc.set_anchors_preset(Control.PRESET_CENTER_TOP)
			pc.offset_top = 16
		_:
			pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.offset_left = -width * 0.5
	pc.offset_right = width * 0.5
	parent.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	pc.add_child(box)
	return box


static func label(parent: Node, text: String, size := 18, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	parent.add_child(l)
	return l


static func button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 38)
	b.add_theme_font_size_override("font_size", 18)
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.18, 0.16, 0.2), "hover": Color(0.85, 0.35, 0.05),
			"pressed": Color(1.0, 0.45, 0.1), "disabled": Color(0.12, 0.11, 0.13)}[st]
		sb.border_color = Color(0.4, 0.35, 0.3)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Vaakapalkki vyöhykkeineen: zones = [[alku, loppu, väri], ...] välillä 0..1, osoitin kohdassa value.
class Meter:
	extends Control
	var value := 0.0
	var zones: Array = []
	var marker := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(0, 26)

	func set_value(v: float) -> void:
		value = v
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.6))
		for z in zones:
			draw_rect(Rect2(Vector2(size.x * z[0], 2), Vector2(size.x * (z[1] - z[0]), size.y - 4)), z[2])
		var x := size.x * clampf(value, 0.0, 1.0)
		draw_rect(Rect2(Vector2(x - 3, -3), Vector2(6, size.y + 6)), Color.BLACK)
		draw_rect(Rect2(Vector2(x - 2, -2), Vector2(4, size.y + 4)), marker)
		draw_rect(r, YELLOW, false, 1.5)
