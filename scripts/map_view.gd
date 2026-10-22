extends Control
## Kartta (M): koko 10 x 10 km alue, lähialue tarkkana. Rulla tai W/S zoomaa, raahaus siirtää, vasen klikkaus
## asettaa kohteen (kompassi ja tutka näyttävät sen), oikea klikkaus poistaa. Peli on pysäytettynä kartan ajan.

const ZOOMS := [0.08, 0.15, 0.3, 0.6, 1.2, 2.4]  # pikseliä metrille

const Kohteet := preload("res://scripts/kohteet.gd")

var player: Node3D
var game: Node3D  # main: kohteet (kohteet.gd) haetaan sen tilasta
var world: Node3D
var has_target := false
var target := Vector2.ZERO
var _near: Texture2D
var _far: Texture2D
var _zoom := 3
var _center := Vector2.ZERO
var _drag := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_near = load("res://assets/map/kartta_lahi.png")
	_far = load("res://assets/map/kartta_koko.png")
	visible = false


func open() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if size.x < 1.0 or size.y < 1.0:
		size = get_viewport_rect().size  # CanvasLayerin alla kokoa ei aina ole asetettu ennen ensimmäistä piirtoa
	visible = true
	_center = Vector2(player.global_position.x, player.global_position.z)
	get_tree().paused = true
	player.controls_enabled = false  # moninpelissä hahmot liikkuvat tauonkin aikana
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false
	player.controls_enabled = get_parent().get_parent().activity == ""


func _to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + (p - _center) * ZOOMS[_zoom]


func _to_world(s: Vector2) -> Vector2:
	return _center + (s - size / 2.0) / ZOOMS[_zoom]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(1, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(-1, event.position)
			MOUSE_BUTTON_LEFT:
				target = _to_world(event.position)
				has_target = true
				_drag = true
			MOUSE_BUTTON_RIGHT:
				has_target = false
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = false
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		_center -= event.relative / ZOOMS[_zoom]
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_M, KEY_ESCAPE:
				close()
			KEY_W, KEY_UP:
				_zoom_at(1, size / 2.0)
			KEY_S, KEY_DOWN:
				_zoom_at(-1, size / 2.0)
		get_viewport().set_input_as_handled()
		queue_redraw()


func _zoom_at(dz: int, at: Vector2) -> void:
	var w := _to_world(at)
	_zoom = clampi(_zoom + dz, 0, ZOOMS.size() - 1)
	_center = w - (at - size / 2.0) / ZOOMS[_zoom]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.47, 0.67, 0.84))
	var z: float = ZOOMS[_zoom]
	for layer in [[_far, 5120.0], [_near, 1000.0]]:
		var half: float = layer[1]
		draw_texture_rect(layer[0], Rect2(_to_screen(Vector2(-half, -half)), Vector2(half, half) * 2.0 * z), false)
	var font := ThemeDB.fallback_font
	# Paikannimet.
	if world != null:
		for n in world.names:
			var s := _to_screen(n.p)
			var fs := 13 if z < 0.5 else 16
			var tw := font.get_string_size(n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, s - Vector2(tw / 2.0, 0), n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(1, 1, 1, 0.8))
			draw_string(font, s - Vector2(tw / 2.0, 0), n.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.1, 0.1, 0.25))
	_draw_pois(font, z)
	# Kävelyalueen raja.
	var a0 := _to_screen(Vector2(-990, -990))
	draw_rect(Rect2(a0, Vector2(1980, 1980) * z), Color(0.8, 0.1, 0.5, 0.7), false, 2.0)
	if has_target:
		var t := _to_screen(target)
		draw_circle(t, 8.0, Color.BLACK)
		draw_circle(t, 6.0, Color(0.9, 0.15, 0.1))
	if player != null:
		var p := _to_screen(Vector2(player.global_position.x, player.global_position.z))
		draw_circle(p, 8.0, Color.BLACK)
		draw_circle(p, 6.0, Color(1, 0.85, 0.1))
	# Mittakaava ja ohjeet.
	var bar := 100.0 if z >= 0.6 else (500.0 if z >= 0.15 else 1000.0)
	var y := size.y - 30.0
	draw_line(Vector2(30, y), Vector2(30 + bar * z, y), Color.BLACK, 4.0)
	draw_string(font, Vector2(30, y - 8), "%d m" % bar, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	var help := "Rulla / W-S zoomaa · keskinappi siirtää · klikkaus asettaa kohteen · oikea poistaa · M tai Esc sulkee"
	draw_string_outline(font, Vector2(30, 34), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 5, Color.BLACK)
	draw_string(font, Vector2(30, 34), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
	draw_string(font, Vector2(30, size.y - 60), "© Maanmittauslaitos (CC BY 4.0) · © OpenStreetMap-tekijät",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.1, 0.1, 0.1))


## Reitit ja kiinnostavat kohteet kuvan päälle: pääkohteet aina nimineen, muut kun zoomattu lähemmäs; selite alakulmassa.
func _draw_pois(font: Font, z: float) -> void:
	if game == null:
		return
	for r: Array in Kohteet.reitit():
		var pts := PackedVector2Array()
		for p: Vector2 in r[1]:
			pts.append(_to_screen(p))
		if pts.size() > 1:
			draw_polyline(pts, Color(0, 0, 0, 0.5), 5.0)
			draw_polyline(pts, r[2], 3.0)
	for k: Dictionary in Kohteet.list(game):
		var col: Color = Kohteet.KINDS[k.kind][0]
		var s := _to_screen(k.p)
		if s.x < -20 or s.y < -20 or s.x > size.x + 20 or s.y > size.y + 20:
			continue
		var named: bool = k.name != ""
		var show_label: bool = named and (k.major or z >= 1.2 or (k.kind in ["porukka", "kulku"] and z >= 0.6))
		if k.kind == "mustikka":
			if z >= 0.3:
				draw_circle(s, 3.0, Color.BLACK)
				draw_circle(s, 2.2, col)
			continue
		var r := 9.0 if k.major else 6.5
		var d := PackedVector2Array([s + Vector2(0, -r), s + Vector2(r, 0), s + Vector2(0, r), s + Vector2(-r, 0)])
		draw_colored_polygon(d, col)
		draw_polyline(d + PackedVector2Array([d[0]]), Color.BLACK, 1.8)
		if show_label:
			var fs := 15 if k.major else 13
			var tw := font.get_string_size(k.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var tp := s + Vector2(-tw / 2.0, -r - 4.0)
			draw_string_outline(font, tp, k.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(1, 1, 1, 0.9))
			draw_string(font, tp, k.name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.2))
	# Selite.
	var y := size.y - 20.0 * (Kohteet.KINDS.size() + 2) - 36.0
	var x := size.x - 190.0
	draw_rect(Rect2(Vector2(x - 10, y - 20), Vector2(190, 12 + 20.0 * (Kohteet.KINDS.size() + 2))), Color(1, 1, 1, 0.78))
	draw_string(font, Vector2(x, y), "Selite", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
	var i := 1
	for kind: String in Kohteet.KINDS:
		var c: Color = Kohteet.KINDS[kind][0]
		var p := Vector2(x + 8, y + i * 20.0 - 5.0)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), c)
		draw_string(font, Vector2(x + 22, y + i * 20.0), Kohteet.KINDS[kind][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
		i += 1
	draw_line(Vector2(x, y + i * 20.0 - 4.0), Vector2(x + 16, y + i * 20.0 - 4.0), Color(0.85, 0.2, 0.2), 3.0)
	draw_string(font, Vector2(x + 22, y + i * 20.0), "ajoreitti", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
	i += 1
	draw_line(Vector2(x, y + i * 20.0 - 4.0), Vector2(x + 16, y + i * 20.0 - 4.0), Color(0.1, 0.3, 0.8), 3.0)
	draw_string(font, Vector2(x + 22, y + i * 20.0), "soutureitti", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.BLACK)
