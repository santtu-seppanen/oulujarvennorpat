extends Control
## Kartta (M): koko 10 x 10 km alue, lähialue tarkkana. Rulla tai W/S zoomaa, raahaus siirtää, vasen klikkaus
## asettaa kohteen (kompassi ja tutka näyttävät sen), oikea klikkaus poistaa. Peli on pysäytettynä kartan ajan.

const ZOOMS := [0.08, 0.15, 0.3, 0.6, 1.2, 2.4]  # pikseliä metrille

var player: Node3D
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
	visible = true
	_center = Vector2(player.global_position.x, player.global_position.z)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


func close() -> void:
	visible = false
	get_tree().paused = false


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
