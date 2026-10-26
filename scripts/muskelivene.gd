extends CharacterBody3D
## Muskelivene: punavalkoinen nopea moottorivene (7 x 2,4 m, perämoottori, huippu n. 60 km/h), toteutus Normipäivä
## Saloisissa -pelin muskeliveneestä. Vene on aina jossain satamassa (moorings): mökin viereisessä Äpätin satamassa
## tai Happy Beachin laiturilla. Pelaaja nousee veneeseen satamassa (E) ja istuu ohjaamon oikealle penkille; W/S kaasu
## ja peruutus, A/D ohjaus, V vaihtaa kuljettajan näkymään. Vene kulkee vain riittävän syvässä vedessä (pohjan korkeus
## alle FREE_H) ja törmää laitureihin ja lohkareisiin (törmäyskerros 1). Veneen voi jättää vain satamaan: E sataman
## lähellä (alle DOCK_R) ja hiljaa kulkiessa liu'uttaa veneen laituriin, ja pelaaja nousee laiturille. Mökkilaituri
## on liian matala muskeliveneelle (kansi 0,42 m, laita 0,9 m), joten sinne ei telakoida.
## build(parent) rakentaa pelkän veneen: keula -Z, vesiraja y = 0.

signal docked(idx: int)

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Chat := preload("res://scripts/chat.gd")

const L := 7.0              # rungon pituus
const W := 2.4              # leveys
const FREEBOARD := 0.9      # laidan korkeus perässä (vesirajasta)
const TRANSOM_H := 0.9      # peräpeilin yläreuna
const DRAFT := 0.35         # kölin syvyys perässä
const FREE_H := -0.40       # pohjan korkeus, jota matalammassa (syvemmässä) vedessä vene kulkee
const MAX_SPEED := 17.0     # n. 60 km/h
const REVERSE_SPEED := 3.0
const ACCEL := 6.0
const DRAG := 2.2
const TURN := 0.75
const DOCK_R := 12.0        # näin lähellä satamapaikkaa telakointi onnistuu
const DOCK_SPEED := 3.0     # telakointi vain tätä hitaammin (m/s)
const SEAT_Z := 0.6
const SEAT_TOP := 0.62
## Kuljettajan paikka veneen avaruudessa: origo ohjaamon lattialla, lantio penkillä.
const SEAT := Vector3(0.45, 0.17, SEAT_Z + 0.1)
## Istumapaikat: 0 kuljettaja, 1 kaverin penkki, 2 ja 3 takapenkki (kasvot keulaan).
const SEATS := [SEAT, Vector3(-0.45, 0.17, SEAT_Z + 0.1), Vector3(-0.5, 0.2, 3.0), Vector3(0.5, 0.2, 3.0)]

static var _hull_mat: StandardMaterial3D

var game: Node3D
var driver: CharacterBody3D = null
## Moninpeli: toinen kone ajaa (remote), ja tämän koneen pelaaja voi istua kyydissä (passenger, paikka passenger_seat).
var passenger: CharacterBody3D = null
var passenger_seat := 1
var remote := false
var speed := 0.0
## Satamapaikat: [{name, pos (veneen origo vedenpinnassa), yaw, deck (laiturin kohta, johon pelaaja nousee)}].
var moorings: Array = []
var at := -1  # satamapaikka, jossa vene on (-1 = vapaana vedessä)
var from_mooring := 0  # satamapaikka, josta ajo alkoi

var _parts := {}
var _body: Node3D
var _cam: Camera3D
var _cam_ready := false
var _engine: AudioStreamPlayer3D
var _yaw := 0.0
var _turn_v := 0.0
var _pitch := 0.0
var _roll := 0.0
var _t := 0.0
var _shake := 0.0
var _bump_cd := 0.0
var _blocked_t := 0.0
var _hist: Array = []
var _splash_t := 0.0
var _docking := false
var _throttle := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _send_t := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 1
	add_child(B.box_shape(Vector3(W * 0.85, 1.0, L * 0.92), Vector3(0, 0.5, 0)))
	_body = Node3D.new()
	add_child(_body)
	_parts = build(_body)
	_cam = Camera3D.new()
	_cam.fov = 68.0
	_cam.far = 9000.0
	_cam.top_level = true
	add_child(_cam)
	_engine = Sfx.loop_on(self, "engine", -14.0)
	_engine.stream_paused = true


## Veneen paikka satamapaikassa idx.
func place(idx: int) -> void:
	at = idx
	var m: Dictionary = moorings[idx]
	global_position = m.pos
	_yaw = m.yaw
	rotation.y = _yaw
	speed = 0.0
	_turn_v = 0.0
	_hist.clear()


# ---------- Vene ----------

## Rungon poikkileikkaus: [x-kerroin, y, väri] vasemmalta laidalta pohjaan. Oikea puoli peilataan.
static func _ring(t: float) -> Array:
	# t = 0 keula, 1 perä.
	var k := clampf(t / 0.55, 0.0, 1.0)
	var hw := W * 0.5 * (pow(k, 0.65) * 0.97 + 0.03)
	var g := FREEBOARD + 0.4 * pow(1.0 - t, 2.2)           # laita nousee keulassa
	var keel := lerpf(0.08, -DRAFT, clampf(t / 0.6, 0.0, 1.0))
	var white := Color(0.95, 0.95, 0.92)
	var red := Color(0.78, 0.1, 0.1)
	var dark := Color(0.42, 0.06, 0.07)
	var pts: Array = []
	pts.append([Vector3(hw, g, 0), white])
	pts.append([Vector3(hw * 0.985, g - 0.28, 0), white])
	pts.append([Vector3(hw * 0.98, g - 0.3, 0), red])
	pts.append([Vector3(hw * 0.93, minf(0.0, g - 0.31), 0), red])
	pts.append([Vector3(hw * 0.9, 0.0, 0), dark])
	pts.append([Vector3(hw * 0.62, lerpf(keel, 0.0, 0.3), 0), dark])
	pts.append([Vector3(0, keel, 0), dark])
	return pts


static func _hull_material() -> StandardMaterial3D:
	if _hull_mat == null:
		_hull_mat = StandardMaterial3D.new()
		_hull_mat.vertex_color_use_as_albedo = true
		_hull_mat.vertex_color_is_srgb = true
		_hull_mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # kaksipuolinen: kiertosuunnalla ei ole väliä
		_hull_mat.roughness = 0.3
		_hull_mat.metallic_specular = 0.7
	return _hull_mat


## Runko SurfaceToolilla: poikkileikkaukset keulasta perään, kansi keulassa, peräpeili.
static func _hull_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 14
	var rings: Array = []  # jokainen: Array[[Vector3, Color]] vasen laita -> köli -> oikea laita
	for i in n + 1:
		var t := float(i) / n
		var z := -L * 0.5 + L * t
		var half := _ring(t)
		var full: Array = []
		for p in half:
			full.append([Vector3(-p[0].x, p[0].y, z), p[1]])
		for j in range(half.size() - 2, -1, -1):
			full.append([Vector3(half[j][0].x, half[j][0].y, z), half[j][1]])
		rings.append(full)
	for i in n:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		for j in a.size() - 1:
			_quad(st, a[j], a[j + 1], b[j + 1], b[j])
	# Kansi keulassa (laidasta laitaan), ohjaamon etuseinään asti.
	var deck_to := 5
	var deck_col := Color(0.86, 0.86, 0.82)
	for i in deck_to:
		var a: Array = rings[i]
		var b: Array = rings[i + 1]
		var al: Array = a[0]
		var ar: Array = a[a.size() - 1]
		var bl: Array = b[0]
		var br: Array = b[b.size() - 1]
		_quad(st, [al[0], deck_col], [ar[0], deck_col], [br[0], deck_col], [bl[0], deck_col])
	# Peräpeili: viuhka kölistä.
	var last: Array = rings[n]
	var keel_i: int = (last.size() - 1) / 2
	for j in last.size() - 1:
		_tri(st, last[j], last[j + 1], last[keel_i])
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, a: Array, b: Array, c: Array) -> void:
	for p in [a, b, c]:
		st.set_color(p[1])
		st.add_vertex(p[0])


static func _quad(st: SurfaceTool, a: Array, b: Array, c: Array, d: Array) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


## Rakentaa veneen parentin alle. Palauttaa {prop, motor, spray_l, spray_r, wake, wheel}.
static func build(parent: Node3D) -> Dictionary:
	var grey := Color(0.3, 0.32, 0.35)
	var black := Color(0.08, 0.08, 0.1)
	var seat_c := Color(0.12, 0.12, 0.16)
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh()
	hull.material_override = _hull_material()
	parent.add_child(hull)
	# Ääriviivat: tumma hankauslista laidan päälle ja vaalea vesirajaviiva.
	for s: float in [-1.0, 1.0]:
		B.mesh(parent, B.boxm(Vector3(0.07, 0.07, L * 0.62)), Vector3(s * (W * 0.5 - 0.02), FREEBOARD + 0.03, L * 0.19), black)
		B.mesh(parent, B.boxm(Vector3(0.04, 0.05, L * 0.55)), Vector3(s * (W * 0.5 * 0.93), 0.02, L * 0.12), Color(0.95, 0.95, 0.95))
	# Ohjaamon lattia ja sisäsivut.
	B.mesh(parent, B.boxm(Vector3(W * 0.78, 0.05, L * 0.52)), Vector3(0, 0.16, L * 0.2), Color(0.55, 0.57, 0.6))
	for s: float in [-1.0, 1.0]:
		B.mesh(parent, B.boxm(Vector3(0.05, 0.5, L * 0.5)), Vector3(s * (W * 0.5 - 0.1), 0.45, L * 0.22), Color(0.9, 0.9, 0.86))
	B.mesh(parent, B.boxm(Vector3(W - 0.2, 0.55, 0.05)), Vector3(0, 0.45, L * 0.5 - 0.06), Color(0.9, 0.9, 0.86))  # peräpeilin sisäpuoli
	# Konsoli keskellä edessä ja tuulilasi.
	var cz := -0.3
	B.mesh(parent, B.boxm(Vector3(1.5, 0.55, 0.7)), Vector3(0, 0.85, cz), Color(0.9, 0.9, 0.86))
	B.mesh(parent, B.boxm(Vector3(1.5, 0.08, 0.72)), Vector3(0, 1.15, cz), grey)
	B.mesh(parent, B.boxm(Vector3(1.0, 0.04, 0.3)), Vector3(0, 1.0, cz + 0.28), Color(0.1, 0.12, 0.15), Vector3(-30, 0, 0))  # mittaristo
	var glass := B.mesh(parent, B.boxm(Vector3(1.9, 0.5, 0.04)), Vector3(0, 1.42, cz - 0.2), Color(0.6, 0.8, 0.9, 0.35), Vector3(-22, 0, 0))
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.65, 0.85, 0.95, 0.35)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.roughness = 0.05
	glass.material_override = gm
	for s: float in [-1.0, 1.0]:
		B.mesh(parent, B.boxm(Vector3(0.05, 0.55, 0.05)), Vector3(s * 0.95, 1.4, cz - 0.2), grey, Vector3(-22, 0, 0))  # kehys
	B.mesh(parent, B.boxm(Vector3(1.95, 0.05, 0.05)), Vector3(0, 1.67, cz - 0.28), grey, Vector3(-22, 0, 0))
	# Ratti (kiertyy ohjauksen mukana) konsolin takasivulla.
	var wheel_pivot := Node3D.new()
	wheel_pivot.position = Vector3(0.0, 1.12, cz + 0.4)
	wheel_pivot.rotation_degrees = Vector3(-55, 0, 0)
	parent.add_child(wheel_pivot)
	var wheel := Node3D.new()
	wheel_pivot.add_child(wheel)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.17
	tm.outer_radius = 0.21
	B.mesh(wheel, tm, Vector3.ZERO, black, Vector3(90, 0, 0))
	for a in [0.0, 120.0, 240.0]:
		var spoke := Node3D.new()
		spoke.rotation_degrees = Vector3(0, a, 0)
		wheel.add_child(spoke)
		B.mesh(spoke, B.boxm(Vector3(0.36, 0.02, 0.025)), Vector3.ZERO, Color(0.7, 0.7, 0.74))
	# Istuimet: kuskin ja kaverin penkki jalustalla sekä takapenkki.
	for s: float in [-1.0, 1.0]:
		var sx := s * 0.45
		B.mesh(parent, B.boxm(Vector3(0.14, SEAT_TOP - 0.15, 0.14)), Vector3(sx, 0.15 + (SEAT_TOP - 0.15) * 0.5, SEAT_Z), grey)
		B.mesh(parent, B.boxm(Vector3(0.62, 0.12, 0.55)), Vector3(sx, SEAT_TOP - 0.06, SEAT_Z), seat_c)
		B.mesh(parent, B.boxm(Vector3(0.62, 0.55, 0.1)), Vector3(sx, SEAT_TOP + 0.3, SEAT_Z + 0.3), seat_c, Vector3(-8, 0, 0))
		B.mesh(parent, B.boxm(Vector3(0.64, 0.05, 0.56)), Vector3(sx, SEAT_TOP - 0.01, SEAT_Z), Color(0.7, 0.1, 0.1))  # punainen reunaommel
	B.mesh(parent, B.boxm(Vector3(W - 0.5, 0.42, 0.5)), Vector3(0, 0.4, L * 0.5 - 0.55), seat_c)  # takapenkki
	B.mesh(parent, B.boxm(Vector3(W - 0.5, 0.08, 0.52)), Vector3(0, 0.63, L * 0.5 - 0.55), Color(0.7, 0.1, 0.1))
	# Keulapollari, köysi ja etulyhty.
	B.mesh(parent, B.cyl(0.05, 0.06, 0.18, 8), Vector3(0, _bow_deck_y(0.15) + 0.09, -L * 0.5 + 0.7), Color(0.75, 0.75, 0.78))
	B.mesh(parent, B.sphere(0.06, 8), Vector3(0, FREEBOARD + 0.62, L * 0.5 - 0.15), Color(0.95, 0.95, 0.8))
	B.mesh(parent, B.cyl(0.015, 0.015, 0.5, 6), Vector3(0, FREEBOARD + 0.35, L * 0.5 - 0.15), grey)
	# Perämoottori peräpeilin yläreunaan.
	var mz := L * 0.5 + 0.22
	var motor := Node3D.new()
	motor.position = Vector3(0, TRANSOM_H, mz)
	parent.add_child(motor)
	B.mesh(motor, B.boxm(Vector3(0.7, 0.08, 0.3)), Vector3(0, -0.08, -0.2), grey)  # kiinnityslevy
	B.mesh(motor, B.boxm(Vector3(0.62, 0.8, 0.62)), Vector3(0, 0.38, 0), black)  # kopa
	B.mesh(motor, B.boxm(Vector3(0.5, 0.14, 0.5)), Vector3(0, 0.83, 0), Color(0.14, 0.14, 0.17))  # kansi
	B.mesh(motor, B.boxm(Vector3(0.66, 0.04, 0.66)), Vector3(0, 0.0, 0), Color(0.75, 0.75, 0.78))  # kiilto
	B.mesh(motor, B.boxm(Vector3(0.48, 0.22, 0.05)), Vector3(0, 0.45, 0.325), Color(0.85, 0.1, 0.1))  # kiilloraita
	B.mesh(motor, B.boxm(Vector3(0.4, TRANSOM_H + 0.85, 0.38)), Vector3(0, -(TRANSOM_H + 0.85) * 0.5, 0.0), Color(0.12, 0.12, 0.15))  # jalka
	B.mesh(motor, B.boxm(Vector3(0.56, 0.05, 0.55)), Vector3(0, -TRANSOM_H * 0.5 - 0.15, 0.0), Color(0.15, 0.15, 0.18))  # vaahtolevy
	for s: float in [-1.0, 1.0]:
		var decal := B.sign_plate(motor, "300", Color(0.9, 0.1, 0.1), Color.WHITE, 0.2, 40, Color.WHITE)
		decal.position = Vector3(s * 0.32, 0.45, 0.0)
		decal.rotation.y = s * PI * 0.5
		decal.scale = Vector3.ONE * 0.8
	# Potkuri kääntyy omassa nivelessään jalan perässä.
	var prop := Node3D.new()
	prop.position = Vector3(0, -TRANSOM_H - 0.7, 0.3)
	motor.add_child(prop)
	B.mesh(prop, B.sphere(0.1, 8), Vector3.ZERO, Color(0.55, 0.55, 0.6))
	for a in [0.0, 120.0, 240.0]:
		var blade := Node3D.new()
		blade.rotation_degrees = Vector3(0, 0, a)
		prop.add_child(blade)
		B.mesh(blade, B.boxm(Vector3(0.07, 0.34, 0.03)), Vector3(0, 0.2, 0), Color(0.78, 0.7, 0.4))
	# Kuohu perän takana ja roiskeet keulan sivuilla.
	var wake := CPUParticles3D.new()
	wake.position = Vector3(0, 0.05, L * 0.5 + 0.7)
	wake.amount = 90
	wake.lifetime = 2.6
	wake.local_coords = false
	wake.emitting = false
	wake.direction = Vector3(0, 0.15, 1)
	wake.spread = 28.0
	wake.initial_velocity_min = 0.8
	wake.initial_velocity_max = 2.4
	wake.gravity = Vector3(0, -0.6, 0)
	wake.scale_amount_min = 0.8
	wake.scale_amount_max = 2.2
	wake.mesh = _foam_mesh(0.28, Color(0.95, 0.98, 1.0, 0.55))
	parent.add_child(wake)
	var sp: Array[CPUParticles3D] = []
	for s: float in [-1.0, 1.0]:
		var p := CPUParticles3D.new()
		p.position = Vector3(s * 0.35, 0.3, -L * 0.5 + 1.2)
		p.amount = 36
		p.lifetime = 0.7
		p.local_coords = false
		p.emitting = false
		p.direction = Vector3(s * 1.0, 1.1, 0.1)
		p.spread = 22.0
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.2
		p.gravity = Vector3(0, -9.0, 0)
		p.mesh = _foam_mesh(0.07, Color(0.92, 0.97, 1.0, 0.85))
		parent.add_child(p)
		sp.append(p)
	return {"prop": prop, "motor": motor, "spray_l": sp[0], "spray_r": sp[1], "wake": wake, "wheel": wheel}


static func _foam_mesh(r: float, c: Color) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 6
	m.rings = 3
	m.material = B.unshaded(c)
	return m


## Keulakannen korkeus tietyllä etäisyydellä keulasta (peräkkäisten renkaiden kansitaso).
static func _bow_deck_y(dist: float) -> float:
	return FREEBOARD + 0.4 * pow(1.0 - dist / L, 2.2)


# ---------- Ajo ----------

func _fwd() -> Vector3:
	return Vector3(-sin(_yaw), 0, -cos(_yaw))


## Vene vapaassa vedessä: keula, perä, kyljet ja keskipiste riittävän syvässä (pohja alle FREE_H).
func free_at(p: Vector3, yaw: float) -> bool:
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var s := Vector3(f.z, 0, -f.x)
	for q in [f * (L * 0.5), -f * (L * 0.5), s * (W * 0.5), -s * (W * 0.5), Vector3.ZERO]:
		if Terrain.h(p.x + q.x, p.z + q.z) >= FREE_H:
			return false
	return true


## Satamapaikka, jonka luona vene on (alle DOCK_R), tai -1.
func near_mooring() -> int:
	var best := -1
	var bd := DOCK_R
	for i in moorings.size():
		var m: Dictionary = moorings[i]
		var d := Vector2(global_position.x - m.pos.x, global_position.z - m.pos.z).length()
		if d < bd:
			bd = d
			best = i
	return best


## Pelaaja veneen luona (alle 3,4 m veneen keskilinjasta): voi nousta kyytiin.
func can_board(p: Vector3) -> bool:
	if driver != null or passenger != null or remote or _docking:
		return false
	var f := _fwd()
	var a := global_position + f * (L * 0.5 - 0.5)
	var b := global_position - f * (L * 0.5 - 0.5)
	var q := Geometry3D.get_closest_point_to_segment(Vector3(p.x, 0, p.z), a, b)
	return Vector2(p.x - q.x, p.z - q.z).length() < 3.4 and absf(p.y - 0.7) < 1.6


func board(p: CharacterBody3D) -> void:
	driver = p
	from_mooring = maxi(at, 0)
	at = -1
	p.controls_enabled = false
	p._seated(true)
	p.vehicle = self
	p.vehicle_seat = 0
	p.pose = "Sitting_Idle"
	_cam.current = true
	_cam_ready = false
	_engine.stream_paused = false
	_hist.clear()
	Sfx.play("cloth", -8.0)


## Telakoi satamapaikkaan idx: vene liukuu paikalleen, ja pelaaja nousee laiturille.
func dock(idx: int) -> void:
	if _docking or driver == null:
		return
	_docking = true
	speed = 0.0
	_turn_v = 0.0
	var m: Dictionary = moorings[idx]
	var from_pos := global_position
	var from_yaw := _yaw
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		global_position = from_pos.lerp(m.pos, k)
		_yaw = lerp_angle(from_yaw, m.yaw, k)
		rotation.y = _yaw, 0.0, 1.0, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(func() -> void:
		at = idx
		_docking = false
		release(m.deck)
		docked.emit(idx))


## Istumapaikan slot paikka maailmassa (keinunta mukana): on_foot.gd _sit_in.
func seat_global(slot := 0) -> Vector3:
	return to_global(SEATS[slot] + Vector3(0, _body.position.y, 0))


func set_remote(on: bool) -> void:
	remote = on
	_net_pos = global_position
	_net_yaw = rotation.y
	_engine.stream_paused = not on and driver == null and passenger == null


## Tila verkkoon: [x, z, suunta, nopeus, kääntönopeus].
func net_state() -> Array:
	return [snappedf(global_position.x, 0.01), snappedf(global_position.z, 0.01), snappedf(_yaw, 0.01),
		snappedf(speed, 0.01), snappedf(_turn_v, 0.01)]


func net_apply(a: Array) -> void:
	_net_pos = Vector3(a[0], 0.0, a[1])
	_net_yaw = a[2]
	speed = a[3]
	_turn_v = a[4]


func _follow_net(delta: float) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	var p := global_position
	if Vector2(p.x - _net_pos.x, p.z - _net_pos.z).length() > 8.0:
		k = 1.0
	global_position = Vector3(lerpf(p.x, _net_pos.x, k), 0.0, lerpf(p.z, _net_pos.z, k))
	_yaw = lerp_angle(_yaw, _net_yaw, k)
	rotation.y = _yaw
	_pitch = lerpf(_pitch, clampf(absf(speed) / MAX_SPEED, 0.0, 1.0) * 0.08, 1.0 - exp(-4.0 * delta))
	_roll = lerpf(_roll, clampf(_turn_v * speed * 0.045, -0.35, 0.35), 1.0 - exp(-4.0 * delta))


## Kyytiin toisen koneen ajamaan veneeseen paikalle slot.
func board_passenger(p: CharacterBody3D, slot: int) -> void:
	passenger = p
	passenger_seat = slot
	p.controls_enabled = false
	p._seated(true)
	p.vehicle = self
	p.vehicle_seat = slot
	p.pose = "Sitting_Idle"
	_cam.current = true
	_cam_ready = false
	_engine.stream_paused = false


## Kyydistä pois pisteeseen where (laiturille tai veneen viereen).
func leave_passenger(where: Vector3) -> void:
	var p := passenger
	passenger = null
	if p == null:
		return
	p.vehicle = null
	p._seated(false)
	p.pose = ""
	p.controls_enabled = true
	p.global_position = where + Vector3.UP * 0.2
	p.velocity = Vector3.ZERO
	p.rotation.y = _yaw
	p.activate_camera()
	_engine.stream_paused = driver == null


## Kuljettaja pois veneestä pisteeseen where (laiturille tai nollauksessa).
func release(where: Vector3) -> CharacterBody3D:
	var p := driver
	driver = null
	speed = 0.0
	_engine.stream_paused = true
	if p == null:
		return null
	p.vehicle = null
	p._seated(false)
	p.pose = ""
	p.controls_enabled = true
	p.global_position = where + Vector3.UP * 0.2
	p.velocity = Vector3.ZERO
	p.rotation.y = _yaw
	p.activate_camera()
	return p


## Ajo keskeytyy (R, hahmon vaihto): vene takaisin Äpätin satamaan ja kuljettaja laiturille.
func send_home() -> void:
	place(0)
	release(moorings[0].deck)


func _physics_process(delta: float) -> void:
	_t += delta
	_bump_cd -= delta
	if remote:
		_follow_net(delta)
		_finish(delta)
		return
	if driver == null or _docking:
		speed = move_toward(speed, 0.0, DRAG * 2.0 * delta)
		velocity = Vector3.ZERO
		_finish(delta)
		return
	var fwd_in := 0.0
	var turn_in := 0.0
	if driver.controls_enabled == false and not Chat.typing:
		fwd_in = Input.get_axis("back", "forward")
		turn_in = Input.get_axis("right", "left")
	var drunk: float = driver.drunk()
	var wob := sin(_t * 0.8) * 0.4 * drunk
	_throttle = fwd_in
	var target := fwd_in * (MAX_SPEED if fwd_in > 0.0 else REVERSE_SPEED)
	var rate := ACCEL if absf(fwd_in) > 0.1 else DRAG
	if fwd_in > 0.1 and speed > MAX_SPEED * 0.75:
		rate = ACCEL * 0.5  # huippuvauhdissa kiihtyvyys hiipuu
	var prev := speed
	speed = move_toward(speed, target, rate * delta)
	var accel := (speed - prev) / maxf(delta, 0.0001)
	# Ohjaus vähenee vauhdin kasvaessa vain hiukan, mutta paikallaan ei käännytä.
	var steer_k := clampf(absf(speed) / 3.0, 0.0, 1.0) * (1.0 - 0.35 * clampf(speed / MAX_SPEED, 0.0, 1.0))
	var sgn := 1.0 if speed >= -0.1 else -1.0
	_turn_v = lerpf(_turn_v, (turn_in + wob) * TURN * steer_k * sgn, 1.0 - exp(-3.5 * delta))
	var new_yaw := _yaw + _turn_v * delta
	var f := Vector3(-sin(new_yaw), 0, -cos(new_yaw))
	var new_pos := global_position + f * speed * delta
	if free_at(new_pos, new_yaw):
		_yaw = new_yaw
		rotation.y = _yaw
		velocity = f * speed
		move_and_slide()
		if get_slide_collision_count() > 0 and absf(speed) > 1.5:
			_bump("Kolahti laituriin.")
			speed *= 0.4
		_blocked_t = 0.0
		_hist.append([global_position, _yaw])
		if _hist.size() > 10:
			_hist.pop_front()
	else:
		velocity = Vector3.ZERO
		if absf(speed) > 1.5:
			_bump("Liian matalaa. Vene pysyy syvässä vedessä.")
		speed = -speed * 0.25
		_turn_v = 0.0
		_blocked_t += delta
		if _blocked_t > 1.5 and not _hist.is_empty():  # jumi: takaisin vanhaan vapaaseen asentoon
			var h: Array = _hist[0]
			global_position = h[0]
			_yaw = h[1]
			rotation.y = _yaw
			speed = 0.0
			_blocked_t = 0.0
	global_position.y = 0.0
	# Pitch: kiihdytyksessä keula nousee, liukutasolle päästessä laskee.
	var frac := clampf(absf(speed) / MAX_SPEED, 0.0, 1.0)
	var plane := clampf((absf(speed) - 4.0) / 9.0, 0.0, 1.0)
	var tp := clampf(accel * 0.012, -0.06, 0.12) + sin(plane * PI) * 0.1 + frac * 0.03
	_pitch = lerpf(_pitch, tp, 1.0 - exp(-4.0 * delta))
	var troll := clampf(_turn_v * speed * 0.045, -0.35, 0.35) + sin(_t * 1.3) * 0.015 * drunk
	_roll = lerpf(_roll, troll, 1.0 - exp(-4.0 * delta))
	_finish(delta)


func _bump(text: String) -> void:
	if _bump_cd > 0.0:
		return
	_bump_cd = 0.8
	_shake = clampf(absf(speed) / 10.0, 0.2, 1.0)
	Sfx.play_on(self, "body_fall", -6.0, 0.8)
	if game != null:
		game.toast(text, 2.0)


## Kuljettaja paikalleen, vene keinuu, potkuri ja ratti pyörivät, ääni ja kamera.
func _finish(delta: float) -> void:
	var bob := sin(_t * 1.6) * 0.025 * (1.0 - clampf(speed / 8.0, 0.0, 0.8))
	var lift := clampf((absf(speed) - 4.0) / 9.0, 0.0, 1.0) * 0.18
	_body.position = Vector3(0, 0.05 + bob + lift, 0)
	_body.rotation = Vector3(_pitch + sin(_t * 1.1) * 0.01, 0, _roll + sin(_t * 0.9) * 0.012)
	(_parts.prop as Node3D).rotation.z += (6.0 + absf(speed) * 3.0) * delta * 3.0
	var wheel: Node3D = _parts.wheel
	wheel.rotation.y = lerpf(wheel.rotation.y, _turn_v * 2.5, 1.0 - exp(-8.0 * maxf(delta, 0.001)))
	var rider: CharacterBody3D = driver if driver != null else passenger
	if rider != null:
		if rider.is_player:
			_shake = maxf(0.0, _shake - delta * 2.5)
			var rs: Vector3 = SEATS[0] if rider == driver else SEATS[passenger_seat]
			var eye := to_global(Vector3(rs.x, 1.5, SEAT_Z - 0.05))
			_cam.fov = lerpf(_cam.fov, 66.0 + 12.0 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0), 1.0 - exp(-3.0 * delta))
			CamCtl.update_camera(_cam, self, eye, 9.5, 4.0, absf(speed) > 1.0, delta, not _cam_ready,
				Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.25)
			_cam_ready = true
	var sp := absf(speed)
	(_parts.wake as CPUParticles3D).emitting = sp > 1.0
	(_parts.wake as CPUParticles3D).initial_velocity_max = 1.0 + sp * 0.2
	for k in ["spray_l", "spray_r"]:
		var p: CPUParticles3D = _parts[k]
		p.emitting = sp > 5.0
		p.initial_velocity_min = 1.0 + sp * 0.12
		p.initial_velocity_max = 2.0 + sp * 0.2
	_splash_t -= delta
	if sp > 6.0 and _splash_t <= 0.0:
		_splash_t = lerpf(0.9, 0.35, clampf(sp / MAX_SPEED, 0.0, 1.0))
		Sfx.play_on(self, "water", -14.0, randf_range(1.0, 1.4))
	if driver != null and game != null and game.mp.online() and not remote:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / 12.0
			game.mp.send({"t": "vene_s", "s": net_state()})
	if rider != null or remote:
		var k := clampf(sp / MAX_SPEED, 0.0, 1.0)
		_engine.pitch_scale = lerpf(_engine.pitch_scale, 0.5 + 0.9 * k + 0.15 * absf(_throttle), 1.0 - exp(-5.0 * delta))
		_engine.volume_db = -14.0 + 6.0 * k
