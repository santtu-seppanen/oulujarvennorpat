extends Control
## Tutka oikeassa alakulmassa: pelaaja keskellä, pohjoinen ylös, karttakuva (tools/kartta/bake.py:
## suunnistuskartan tapaan pinnat, käyrät, tiet ja rakennukset). Lähialueella 1 m/px kuva, muualla koko alueen
## 8 m/px kuva. Kartalta valittu kohde (map_view.gd) näkyy punaisena, reunalla nuolena.

const RANGE := 180.0  # metriä keskeltä reunaan
const SIZE := 220.0

var player: Node3D
var map_view: Control
var _near: Texture2D
var _far: Texture2D
var near_half := 1000.0
var far_half := 5120.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_near = load("res://assets/map/kartta_lahi.png")
	_far = load("res://assets/map/kartta_koko.png")
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -SIZE - 18
	offset_right = -18
	offset_top = -SIZE - 18
	offset_bottom = -18
	clip_contents = true


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var p := Vector2(player.global_position.x, player.global_position.z)
	var s := size
	var c := s / 2.0
	var ppm := c.x / RANGE  # pikseliä metrille
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.47, 0.67, 0.84))
	# Koko alue alle, lähialue päälle.
	for layer in [[_far, far_half], [_near, near_half]]:
		var tex: Texture2D = layer[0]
		var half: float = layer[1]
		var tl := c + (Vector2(-half, -half) - p) * ppm
		draw_texture_rect(tex, Rect2(tl, Vector2(half, half) * 2.0 * ppm), false)
	# Kohde.
	if map_view != null and map_view.has_target:
		var d: Vector2 = (map_view.target - p) * ppm
		var lim := c.x - 8.0
		if d.length() > lim:
			var q := c + d.normalized() * lim
			var a := d.angle()
			draw_colored_polygon(PackedVector2Array([q + Vector2.from_angle(a) * 8.0, q + Vector2.from_angle(a + 2.4) * 7.0,
				q + Vector2.from_angle(a - 2.4) * 7.0]), Color(0.9, 0.15, 0.1))
		else:
			draw_circle(c + d, 6.0, Color.BLACK)
			draw_circle(c + d, 4.5, Color(0.9, 0.15, 0.1))
	# Pelaaja: nuoli katsesuuntaan.
	var cam := get_viewport().get_camera_3d()
	var f := -player.global_transform.basis.z
	if cam != null:
		f = -cam.global_transform.basis.z
	var a := atan2(f.z, f.x)
	var pts := PackedVector2Array([c + Vector2.from_angle(a) * 10.0, c + Vector2.from_angle(a + 2.5) * 7.0,
		c + Vector2.from_angle(a + PI) * 3.0, c + Vector2.from_angle(a - 2.5) * 7.0])
	draw_colored_polygon(pts, Color(1, 0.85, 0.1))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.5)
	draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.8), false, 3.0)
	var font := ThemeDB.fallback_font
	draw_string_outline(font, Vector2(c.x - 5, 16), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 4, Color.BLACK)
	draw_string(font, Vector2(c.x - 5, 16), "P", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.35, 0.3))
