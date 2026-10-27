extends CharacterBody3D
## Mökin farmariauto (tummanvihreä, 4,6 x 1,75 m): ajetaan mökin ajouralta Äpätintietä pitkin Happy Beachille
## ja takaisin (reitti.gd). W/S kaasu ja jarru (taakse peruuttaa), A/D ohjaa, välilyönti käsijarru, H torvi,
## V vaihtaa kuljettajan näkymään, G kytkee automaattiajon (auto ajaa reittiä pitkin lähimpään päähän ja
## pysähtyy) ja E pysäyttää ja nousee pois.
##
## Fysiikka on kevyt: auto seuraa maastoa neljän renkaan korkeuksista (kallistus ja nytkähdykset), kulkee
## tiellä ja reitillä täyttä vauhtia (MAX_SPEED) ja metsässä hitaasti (OFFROAD_SPEED), pysähtyy veteen ja
## liian jyrkkään rinteeseen ja törmää puunrunkoihin ja rakennuksiin (törmäyskerros 1). Humala heiluttaa ohjausta.
## Kamera: kolmas persoona ja kuljettajan silmät CamCtl:n kautta (kuten jalan).

signal arrived  # automaattiajo pääsi perille

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Reitti := preload("res://scripts/reitti.gd")
const Satama := preload("res://scripts/satama.gd")
const Chat := preload("res://scripts/chat.gd")

const LENGTH := 4.6
const WIDTH := 1.75
const WHEELBASE := 2.65
const TRACK := 1.5
const WHEEL_R := 0.33
const MAX_SPEED := 22.2  # tiellä (m/s, 80 km/h)
const OFFROAD_SPEED := 7.0
const REVERSE_SPEED := 3.5
const ACCEL := 5.2  # alkukiihtyvyys (m/s²), pienenee vauhdin kasvaessa (0-80 km/h n. 8 s)
const BRAKE := 11.0
const COAST := 1.6
const MAX_STEER := 0.55  # rad
const AUTO_SPEED := 9.0
const GRAVITY := 9.5
## Kuljettajan silmät ja istuin auton avaruudessa (vasen etupaikka).
const EYE := Vector3(-0.42, 1.28, -0.2)
const BODY_COL := Color(0.1, 0.3, 0.22)

var driver: CharacterBody3D = null
## Moninpeli: toinen kone ajaa (remote), ja tämän koneen pelaaja voi istua kyydissä (passenger).
var passenger: CharacterBody3D = null
var remote := false
var game: Node3D
var speed := 0.0
var steer_angle := 0.0
var autopilot := false
var route: Array = []

var _body: Node3D
var _cam: Camera3D
var _cam_ready := false
var _engine: AudioStreamPlayer3D
var _pivots: Array[Node3D] = []  # etupyörien kääntö
var _spinners: Array[Node3D] = []
var _lights: Array[SpotLight3D] = []
var _ri := 0
var _t := 0.0
var _stuck := 0.0
var _back_t := 0.0
var _pitch := 0.0
var _roll := 0.0
var _throttle := 0.0
var _drunk := 0.0
var _vy := 0.0
var _air := false
var _net_pos := Vector3.ZERO
var _net_rot := 0.0
var _send_t := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_mask = 1
	var cs := B.box_shape(Vector3(WIDTH, 1.0, LENGTH - 0.3), Vector3(0.0, 0.85, 0.0))
	add_child(cs)
	_body = Node3D.new()
	add_child(_body)
	_build_model()
	CamCtl.mark_own_body(_body)  # kuljettajan näkymässä auton oma kori piiloon
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 9000.0
	_cam.top_level = true
	add_child(_cam)
	_engine = Sfx.loop_on(self, "engine", -14.0)
	_engine.stream_paused = true


func _build_model() -> void:
	var dark := Color(0.08, 0.08, 0.09)
	var plastic := Color(0.16, 0.17, 0.18)
	var glass := Color(0.2, 0.28, 0.34)
	var chrome := Color(0.78, 0.8, 0.82)
	var hw := WIDTH * 0.5
	var hl := LENGTH * 0.5
	# Alusta ja alakori: muovinen helmalista, maalattu korin alaosa ja vyölinjan kromilista.
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.25, 0.14, LENGTH - 0.5)), Vector3(0, 0.3, 0), dark)
	B.mesh(_body, B.boxm(Vector3(WIDTH + 0.02, 0.16, LENGTH - 0.3)), Vector3(0, 0.46, 0), plastic)
	B.mesh(_body, B.boxm(Vector3(WIDTH, 0.4, LENGTH)), Vector3(0, 0.74, 0), BODY_COL)
	B.mesh(_body, B.boxm(Vector3(WIDTH + 0.01, 0.025, LENGTH - 0.2)), Vector3(0, 0.95, 0), chrome)
	# Konepelti laskee etuvalojen kohdalle, ja tuulilasi on kallellaan.
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.06, 0.08, 1.35)), Vector3(0, 0.99, -1.5), BODY_COL.lightened(0.05), Vector3(6, 0, 0))
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.2, 0.04, 0.5)), Vector3(0, 1.06, -1.1), BODY_COL.darkened(0.1))  # konepellin kupu
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.12, 0.05, 0.95)), Vector3(0, 1.3, -0.62), glass, Vector3(-42, 0, 0))  # tuulilasi
	for s: float in [-1.0, 1.0]:
		B.mesh(_body, B.boxm(Vector3(0.07, 0.07, 1.0)), Vector3(s * (hw - 0.08), 1.3, -0.62), BODY_COL, Vector3(-42, 0, 0))  # A-pilarit
	# Ohjaamo: sivuikkunat, pilarit, takaluukku ja pitkä farmarikatto.
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.1, 0.55, 2.55)), Vector3(0, 1.28, 0.78), glass)
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.06, 0.07, 2.7)), Vector3(0, 1.6, 0.72), BODY_COL)
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.08, 0.06, 0.12)), Vector3(0, 1.56, -0.18), BODY_COL)  # etureunan palkki
	for s: float in [-1.0, 1.0]:
		for z: float in [-0.12, 0.62, 2.0]:
			B.mesh(_body, B.boxm(Vector3(0.07, 0.6, 0.1 if z < 1.0 else 0.2)), Vector3(s * (hw - 0.07), 1.28, z), BODY_COL)
		B.mesh(_body, B.boxm(Vector3(0.02, 0.4, 0.02)), Vector3(s * (hw + 0.005), 0.78, -0.55), dark)  # ovirako
		B.mesh(_body, B.boxm(Vector3(0.02, 0.4, 0.02)), Vector3(s * (hw + 0.005), 0.78, 0.68), dark)
		B.mesh(_body, B.boxm(Vector3(0.02, 0.4, 0.02)), Vector3(s * (hw + 0.005), 0.78, 1.8), dark)
		for z: float in [-0.05, 0.75]:
			B.mesh(_body, B.boxm(Vector3(0.05, 0.03, 0.18)), Vector3(s * (hw + 0.025), 0.9, z), chrome)  # ovenkahvat
		# Peilit varrella A-pilarin juurella.
		B.mesh(_body, B.boxm(Vector3(0.1, 0.03, 0.03)), Vector3(s * (hw + 0.04), 1.1, -0.82), dark)
		B.mesh(_body, B.boxm(Vector3(0.05, 0.14, 0.22)), Vector3(s * (hw + 0.1), 1.12, -0.82), BODY_COL)
		# Katonkiskot.
		B.mesh(_body, B.boxm(Vector3(0.05, 0.05, 2.5)), Vector3(s * 0.55, 1.67, 0.72), chrome.darkened(0.4))
		for z: float in [-0.35, 1.7]:
			B.mesh(_body, B.boxm(Vector3(0.04, 0.05, 0.05)), Vector3(s * 0.55, 1.64, z), dark)
	# Sisusta: etuistuimet, takapenkki, mittaristo ja rattipyörä lasien läpi.
	for s: float in [-0.42, 0.42]:
		B.mesh(_body, B.boxm(Vector3(0.44, 0.1, 0.5)), Vector3(s, 0.98, 0.0), dark)
		B.mesh(_body, B.boxm(Vector3(0.42, 0.55, 0.1)), Vector3(s, 1.22, 0.28), dark, Vector3(-8, 0, 0))
	B.mesh(_body, B.boxm(Vector3(1.3, 0.1, 0.5)), Vector3(0, 0.98, 1.1), dark)
	B.mesh(_body, B.boxm(Vector3(1.3, 0.5, 0.1)), Vector3(0, 1.2, 1.38), dark)
	B.mesh(_body, B.boxm(Vector3(1.5, 0.2, 0.35)), Vector3(0, 1.08, -0.85), plastic)
	B.mesh(_body, B.cyl(0.17, 0.17, 0.025, 14), Vector3(-0.42, 1.2, -0.6), dark.lightened(0.1), Vector3(-65, 0, 0))
	# Etupää: ritilä, valot, puskuri, sumuvalot ja rekisterikilpi.
	B.mesh(_body, B.boxm(Vector3(WIDTH + 0.04, 0.2, 0.2)), Vector3(0, 0.46, -hl), plastic)
	B.mesh(_body, B.boxm(Vector3(0.9, 0.16, 0.05)), Vector3(0, 0.78, -hl - 0.02), dark)  # ritilä
	B.mesh(_body, B.boxm(Vector3(0.92, 0.025, 0.06)), Vector3(0, 0.8, -hl - 0.025), chrome)
	B.mesh(_body, B.boxm(Vector3(0.7, 0.06, 0.05)), Vector3(0, 0.4, -hl - 0.06), dark)  # alailmanotto
	for s: float in [-1.0, 1.0]:
		B.mesh(_body, B.boxm(Vector3(0.38, 0.14, 0.08)), Vector3(s * 0.66, 0.82, -hl - 0.01), Color(1.0, 0.95, 0.75))
		B.mesh(_body, B.boxm(Vector3(0.14, 0.06, 0.08)), Vector3(s * (hw - 0.12), 0.7, -hl - 0.01), Color(1.0, 0.6, 0.1))
		B.mesh(_body, B.cyl(0.05, 0.05, 0.04, 8), Vector3(s * 0.7, 0.42, -hl - 0.08), Color(1.0, 0.95, 0.75), Vector3(90, 0, 0))
	B.mesh(_body, B.boxm(Vector3(0.5, 0.12, 0.02)), Vector3(0, 0.55, -hl - 0.11), Color(0.95, 0.95, 0.9))
	# Takapää: pystysuora takaluukku, pitkät takavalot, puskuri, pakoputki ja lasinpyyhin.
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.3, 0.5, 0.06)), Vector3(0, 1.28, hl - 0.2), glass)
	B.mesh(_body, B.boxm(Vector3(WIDTH + 0.04, 0.2, 0.22)), Vector3(0, 0.46, hl), plastic)
	B.mesh(_body, B.boxm(Vector3(WIDTH - 0.3, 0.05, 0.1)), Vector3(0, 1.0, hl - 0.05), chrome.darkened(0.2))  # luukun kahva
	for s: float in [-1.0, 1.0]:
		B.mesh(_body, B.boxm(Vector3(0.14, 0.6, 0.07)), Vector3(s * (hw - 0.07), 1.0, hl), Color(0.75, 0.06, 0.05))
		B.mesh(_body, B.cyl(0.035, 0.035, 0.25, 8), Vector3(s * 0.55, 0.25, hl + 0.05), chrome.darkened(0.3), Vector3(90, 0, 0))
	B.mesh(_body, B.boxm(Vector3(0.5, 0.12, 0.02)), Vector3(0, 0.64, hl + 0.12), Color(0.95, 0.95, 0.9))
	B.mesh(_body, B.boxm(Vector3(0.5, 0.02, 0.02)), Vector3(-0.3, 1.04, -1.05), dark, Vector3(0, 0, 8))  # pyyhkimet
	B.mesh(_body, B.boxm(Vector3(0.5, 0.02, 0.02)), Vector3(0.2, 1.04, -1.05), dark, Vector3(0, 0, 8))
	B.mesh(_body, B.cyl(0.008, 0.008, 0.5, 5), Vector3(0.7, 1.84, 1.8), dark, Vector3(0, 0, 0))  # antenni
	# Pyörät: etupyörillä kääntöpivotti, kaikilla pyörimissolmu (spinner): rengas, vanne ja viisi pulttia.
	for wz: float in [-WHEELBASE * 0.5, WHEELBASE * 0.5]:
		for s: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(s * TRACK * 0.5, WHEEL_R, wz)
			_body.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			B.mesh(spin, B.cyl(WHEEL_R, WHEEL_R, 0.22, 16), Vector3.ZERO, dark, Vector3(0, 0, 90))
			B.mesh(spin, B.cyl(WHEEL_R * 0.62, WHEEL_R * 0.62, 0.235, 12), Vector3.ZERO, Color(0.72, 0.73, 0.75), Vector3(0, 0, 90))
			B.mesh(spin, B.cyl(WHEEL_R * 0.18, WHEEL_R * 0.18, 0.25, 8), Vector3.ZERO, Color(0.45, 0.46, 0.48), Vector3(0, 0, 90))
			for k in 5:
				var a := TAU * k / 5.0
				B.mesh(spin, B.boxm(Vector3(0.245, 0.05, 0.05)), Vector3(0.0, sin(a) * WHEEL_R * 0.4, cos(a) * WHEEL_R * 0.4),
					Color(0.35, 0.36, 0.38))
			_spinners.append(spin)
			if wz < 0.0:
				_pivots.append(pivot)
			# Pyöränkaaren tumma reunus korin kyljessä.
			B.mesh(_body, B.cyl(WHEEL_R + 0.07, WHEEL_R + 0.07, 0.03, 16),
				Vector3(s * (hw + 0.004), WHEEL_R + 0.02, wz), Color(0.03, 0.03, 0.035), Vector3(0, 0, 90))
	# Ajovalot: kaksi kaukovaloa, päällä pimeällä (set_night).
	for s: float in [-1.0, 1.0]:
		var sl := SpotLight3D.new()
		sl.position = Vector3(s * 0.62, 0.85, -LENGTH * 0.5 - 0.1)
		sl.spot_range = 45.0
		sl.spot_angle = 32.0
		sl.light_energy = 3.0
		sl.light_color = Color(1.0, 0.95, 0.8)
		sl.shadow_enabled = false
		sl.visible = false
		_body.add_child(sl)
		_lights.append(sl)


## Ajovalot päälle pimeällä (main.gd): k 0..1.
func set_night(k: float) -> void:
	for l in _lights:
		l.visible = k > 0.35


## Rattiin: kuljettaja piiloon autoon, kamera auton kameraksi.
func board(p: CharacterBody3D) -> void:
	driver = p
	p.set_hidden_inside(true)
	p.velocity = Vector3.ZERO
	_cam.current = true
	_cam_ready = false
	_engine.stream_paused = false
	Sfx.play("door_close", -4.0)


## Ulos autosta auton vasemmalle puolelle; kamera takaisin kuljettajaan. Palauttaa kuljettajan.
func leave() -> CharacterBody3D:
	var p := driver
	driver = null
	autopilot = false
	if p == null:
		return null
	var out := global_position - global_transform.basis.x * 1.9
	p.global_position = Vector3(out.x, Terrain.h(out.x, out.z) + 0.15, out.z)
	p.rotation.y = rotation.y
	p.velocity = Vector3.ZERO
	p.set_hidden_inside(false)
	p.activate_camera()
	Sfx.play("door", -4.0)
	return p


func set_remote(on: bool) -> void:
	remote = on
	_net_pos = global_position
	_net_rot = rotation.y


## Tila verkkoon: [x, z, suunta, nopeus, ohjauskulma].
func net_state() -> Array:
	return [snappedf(global_position.x, 0.01), snappedf(global_position.z, 0.01), snappedf(rotation.y, 0.01),
		snappedf(speed, 0.01), snappedf(steer_angle, 0.01)]


func net_apply(a: Array) -> void:
	_net_pos = Vector3(a[0], 0.0, a[1])
	_net_rot = a[2]
	speed = a[3]
	steer_angle = a[4]


func _follow_net(delta: float) -> void:
	var k := 1.0 - exp(-10.0 * delta)
	var p := global_position
	if Vector2(p.x - _net_pos.x, p.z - _net_pos.z).length() > 8.0:
		k = 1.0
	global_position = Vector3(lerpf(p.x, _net_pos.x, k), p.y, lerpf(p.z, _net_pos.z, k))
	rotation.y = lerp_angle(rotation.y, _net_rot, k)


## Kyytiin toisen koneen ajamaan autoon.
func board_passenger(p: CharacterBody3D) -> void:
	passenger = p
	p.set_hidden_inside(true)
	p.velocity = Vector3.ZERO
	_cam.current = true
	_cam_ready = false
	_engine.stream_paused = false


## Kyydistä pois auton viereen (slot erottaa useamman kyytiläisen).
func leave_passenger(slot := 0) -> void:
	var p := passenger
	passenger = null
	if p == null:
		return
	var out := global_position - global_transform.basis.x * (1.9 + 0.7 * slot)
	p.global_position = Vector3(out.x, Terrain.h(out.x, out.z) + 0.15, out.z)
	p.rotation.y = rotation.y
	p.velocity = Vector3.ZERO
	p.set_hidden_inside(false)
	p.activate_camera()


## Käynnistää automaattiajon reitin päähän: to_beach = Happy Beachille, muuten mökille.
func start_autopilot(to_beach: bool) -> void:
	route = Reitti.ROUTE.duplicate() if to_beach else Reitti.reversed()
	var p := Vector2(global_position.x, global_position.z)
	var best := 0
	var bd := INF
	for i in route.size():
		var d := p.distance_to(route[i])
		if d < bd:
			bd = d
			best = i
	_ri = best
	_stuck = 0.0
	_back_t = 0.0
	autopilot = true


func stop_autopilot() -> void:
	autopilot = false


## Lähempänä kumpaa päätä auto on: true = Happy Beachin pää.
func near_beach_end() -> bool:
	var p := Vector2(global_position.x, global_position.z)
	return p.distance_to(Reitti.K) < p.distance_to(Reitti.HOME_SPOT)


## Asettaa auton paikalleen ja suuntaan (ajon alku, testit).
func place(p: Vector2, heading_to: Vector2) -> void:
	global_position = Vector3(p.x, Terrain.h(p.x, p.y), p.y)
	var d := heading_to - p
	rotation.y = atan2(-d.x, -d.y)
	speed = 0.0
	steer_angle = 0.0
	_throttle = 0.0
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if driver == null or not (event is InputEventKey) or not event.pressed or event.echo or Chat.typing:
		return
	if event.physical_keycode == KEY_H:
		Sfx.play_on(self, "horn", -2.0, randf_range(0.97, 1.03))


func _physics_process(delta: float) -> void:
	_t += delta
	if remote:
		_follow_net(delta)
		_finish(delta)
		return
	var throttle := 0.0
	var steer := 0.0
	var brake := false
	if driver != null:
		if autopilot:
			var a := _autopilot_inputs(delta)
			throttle = a.x
			steer = a.y
		elif driver.controls_enabled and not Chat.typing:
			throttle = Input.get_axis("back", "forward")
			steer = Input.get_axis("right", "left")
			brake = Input.is_action_pressed("jump")
	# Humalassa saa ajaa, mutta ajaminen vaikeutuu koko ajan: auto vaeltaa kaistalta toiselle, ohjaus yli- ja
	# alikorjaa, kaasu nytkähtelee, ja kovassa humalassa ohjaus kääntyy välillä väärin päin. Automaattiajokin heiluu.
	if driver != null:
		var dr: float = driver.drunk()
		_drunk = dr
		if dr > 0.05:
			var k := 0.6 if autopilot else 1.0
			steer += (sin(_t * 0.7) * 0.7 + sin(_t * 1.9 + 1.0) * 0.5 + sin(_t * 4.3) * 0.25) * dr * 1.3 * k
			steer *= 1.0 + 0.8 * dr * sin(_t * 1.1 + 2.0)
			if dr > 0.6 and sin(_t * 0.41) > 0.75:
				steer = -steer
			throttle *= 1.0 - 0.5 * dr * absf(sin(_t * 0.9))
	else:
		_drunk = 0.0
	_throttle = throttle
	var p := global_position
	var fwd := -global_transform.basis.z
	var on_road := Reitti.on_route(p.x, p.z) or Terrain.surface(p.x, p.z) in [Terrain.ROAD, Terrain.FILL, Terrain.YARD] or Satama.on_road(p.x, p.z)
	var vmax := MAX_SPEED if on_road else OFFROAD_SPEED
	if driver == null:
		speed = move_toward(speed, 0.0, 6.0 * delta)
	elif brake:
		speed = move_toward(speed, 0.0, BRAKE * 1.3 * delta)
	elif throttle > 0.01:
		if speed < 0.0:
			speed += BRAKE * delta
		else:
			speed += ACCEL * (1.0 - 0.7 * clampf(speed / MAX_SPEED, 0.0, 1.0)) * throttle * delta  # moottorin teho hiipuu vauhdissa
	elif throttle < -0.01:
		if speed > 0.2:
			speed -= BRAKE * -throttle * delta
		else:
			speed -= ACCEL * 0.6 * -throttle * delta
	else:
		speed = move_toward(speed, 0.0, COAST * delta)
	if speed > vmax:
		speed = move_toward(speed, vmax, 7.0 * delta)
	speed = maxf(speed, -REVERSE_SPEED)
	# Ohjaus: kulma pienenee nopeuden mukaan, ja auto kääntyy pyöräkulman ja akselivälin mukaan.
	var want_steer := clampf(steer, -1.0, 1.0) * MAX_STEER * (1.0 - 0.8 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
	steer_angle = move_toward(steer_angle, want_steer, 2.4 * (1.0 - 0.55 * _drunk) * delta)
	if not _air:
		rotation.y += speed / WHEELBASE * tan(steer_angle) * delta
	fwd = -global_transform.basis.z
	# Vesi ja liian jyrkkä rinne edessä pysäyttävät.
	if absf(speed) > 0.05:
		var reach := LENGTH * 0.5 + 0.4
		var probe := p + fwd * signf(speed) * reach
		var ph := Terrain.h(probe.x, probe.z)
		if ph < -0.1 or Terrain.is_water(probe.x, probe.z) or (ph - Terrain.h(p.x, p.z)) * signf(speed) / reach > 0.75:
			speed = 0.0
	velocity = Vector3(fwd.x, 0.0, fwd.z) * speed
	move_and_slide()
	if get_slide_collision_count() > 0:
		var along := Vector2(velocity.x, velocity.z).dot(Vector2(fwd.x, fwd.z))
		if absf(along) < absf(speed) * 0.6:
			speed = along * 0.5
		if absf(speed) > 3.0:
			Sfx.play_on(self, "rattle_hard", -6.0)
	if driver != null and game != null and game.mp.online():
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / 12.0
			game.mp.send({"t": "auto_s", "s": net_state()})
	_finish(delta)


## Korkeus, kuljettajan ja kyytiläisen paikka, pyörät, ääni ja kamera (paikallinen ja verkon auto).
func _finish(delta: float) -> void:
	_follow_ground(delta)
	for r: CharacterBody3D in [driver, passenger]:
		if r != null:
			r.global_position = global_position + Vector3.UP * 0.6
			r.rotation.y = rotation.y
	_wheels(delta)
	_sound()
	var rider: CharacterBody3D = driver if driver != null else passenger
	if rider != null and rider.is_player:
		var eye := global_transform * EYE
		_cam.fov = lerpf(_cam.fov, 70.0 + 14.0 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0), 1.0 - exp(-3.0 * delta))  # vauhdin tuntu
		CamCtl.update_camera(_cam, self, eye, 7.5, 3.2, absf(speed) > 1.0, delta, not _cam_ready)
		_cam_ready = true


## Korkeus ja kallistus renkaiden alla olevasta maastosta.
func _follow_ground(delta: float) -> void:
	var fwd := -global_transform.basis.z
	var right := global_transform.basis.x
	var p := global_position
	var hs := {}
	for fz: float in [1.0, -1.0]:
		for rx: float in [-1.0, 1.0]:
			var q := p + fwd * fz * WHEELBASE * 0.5 + right * rx * TRACK * 0.5
			hs[Vector2(fz, rx)] = Terrain.h(q.x, q.z)
	var front: float = (hs[Vector2(1.0, -1.0)] + hs[Vector2(1.0, 1.0)]) * 0.5
	var rear: float = (hs[Vector2(-1.0, -1.0)] + hs[Vector2(-1.0, 1.0)]) * 0.5
	var left: float = (hs[Vector2(1.0, -1.0)] + hs[Vector2(-1.0, -1.0)]) * 0.5
	var rgt: float = (hs[Vector2(1.0, 1.0)] + hs[Vector2(-1.0, 1.0)]) * 0.5
	# Kumpareet: auto seuraa maastoa, mutta jos maa putoaa nopeammin kuin vapaassa pudotuksessa (harjanteen yli
	# kovaa), auto lentää ja laskeutuu iskulla.
	var g := (front + rear) * 0.5 + 0.02
	if _air:
		_vy -= GRAVITY * delta
		var ny := p.y + _vy * delta
		if ny <= g:
			ny = g
			_air = false
			if _vy < -3.0:
				Sfx.play_on(self, "rattle_hard", -2.0)
				speed *= clampf(1.0 + _vy * 0.02, 0.6, 1.0)
			_vy = 0.0
		global_position.y = ny
	else:
		var gv := (g - p.y) / maxf(delta, 0.001)
		var up := _vy  # nousunopeus ennen tätä ruutua
		_vy = lerpf(_vy, gv, 0.6)
		if up > 0.8 and absf(speed) > 3.0 and g < p.y + up * delta - 0.5 * GRAVITY * delta * delta - 0.01:
			_air = true
			_vy = up
		else:
			global_position.y = g
	var k := 1.0 - exp(-8.0 * delta)
	_pitch = lerpf(_pitch, atan2(front - rear, WHEELBASE), k)
	_roll = lerpf(_roll, atan2(rgt - left, TRACK), k)
	# Pieni keinunta kiihdytettäessä ja jarruttaessa.
	_body.rotation = Vector3(_pitch - _throttle * 0.012, 0.0, _roll)


func _wheels(delta: float) -> void:
	for s in _spinners:
		s.rotation.x -= speed / WHEEL_R * delta
	for pv in _pivots:
		pv.rotation.y = steer_angle


func _sound() -> void:
	var active := driver != null or passenger != null or absf(speed) > 0.3
	_engine.stream_paused = not active
	if active:
		var k := clampf(absf(speed) / MAX_SPEED, 0.0, 1.0)
		_engine.pitch_scale = 0.55 + 1.0 * k + (0.12 if _throttle > 0.1 else 0.0)
		_engine.volume_db = -16.0 + 7.0 * k


## Automaattiajo: mihin suuntaan ja kuinka lujaa (x = kaasu, y = ohjaus). Seuraa reittiä tähtäyspisteellä, hidastaa
## käännöksissä ja perillä, ja peruuttaa pätkän, jos jää jumiin.
func _autopilot_inputs(delta: float) -> Vector2:
	var p := Vector2(global_position.x, global_position.z)
	var last: Vector2 = route[route.size() - 1]
	var rest := p.distance_to(last)
	# Jumi: ei liikuta, vaikka kaasua: peruutetaan hetki vastakkaiseen suuntaan.
	if _back_t > 0.0:
		_back_t -= delta
		return Vector2(-1.0, -signf(steer_angle))
	_stuck = _stuck + delta if absf(speed) < 0.4 and rest > 4.0 else 0.0
	if _stuck > 2.5:
		_stuck = 0.0
		_back_t = 1.4
	while _ri < route.size() - 1 and p.distance_to(route[_ri]) < 5.0:
		_ri += 1
	var ti := _ri
	while ti < route.size() - 1 and p.distance_to(route[ti]) < 7.0:
		ti += 1
	var target: Vector2 = route[ti]
	var d := target - p
	var err := wrapf(atan2(-d.x, -d.y) - rotation.y, -PI, PI)
	var v := AUTO_SPEED * (1.0 - 0.65 * minf(absf(err), 1.0))
	if rest < 40.0:
		v = minf(v, maxf(1.6, rest * 0.25))
	if rest < 3.0:
		autopilot = false
		arrived.emit()
		return Vector2(-1.0, 0.0)
	var th := 0.0
	if speed < v - 0.3:
		th = 1.0
	elif speed > v + 0.8:
		th = -0.6
	return Vector2(th, clampf(err * 1.6, -1.0, 1.0))
