extends Node
## Saapumiskohtaus: neljä norppaa ajaa mökin pihaan, nostaa kaljakorit takakontista, kantaa ne ylämökin kautta
## terassille, Jukka panee saunan lämpiämään ja kaikki heittävät vaatteet pois uikkareilleen. Näytetään uuden pelin
## alussa (menu.gd) ja trailerin alkuna (tools/traileri). Kohtaus käyttää omia hahmoja (looks.gd) ja piilottaa
## pelin hahmot siksi aikaa; lopuksi oikeat hahmot ilmestyvät terassille samoille paikoille uikkareissa.
##
## game on main.gd. Peli ajaa kohtausta itse (_process); traileri asettaa manual = true ja kutsuu step(delta) omalla
## kellollaan, antaa oman kameran (cam) ja piirtää häivytyksen (fade) itse.

const B := preload("res://scripts/build.gd")
const Looks := preload("res://scripts/looks.gd")
const Porukka := preload("res://scripts/porukka.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Reitti := preload("res://scripts/reitti.gd")

signal finished

const WALK := 2.0
const CARRY := 2.6
const START_AT := 3  # ajon aloituspiste Reitti.ROUTE:ssa (n. 30 m päässä pysäköintipaikasta)
const SHIRTS := [Color(0.93, 0.93, 0.9), Color(0.5, 0.52, 0.56), Color(0.18, 0.28, 0.5), Color(0.55, 0.5, 0.32)]
const JEANS := [Color(0.2, 0.28, 0.45), Color(0.18, 0.2, 0.28), Color(0.3, 0.34, 0.45), Color(0.26, 0.24, 0.2)]
## Kaljakorit pinoon terassille (pihan kehys u, v) ja loppuasennot (main.gd SPAWNS).
const CRATES_AT := Vector2(-3.4, 2.6)

var game: Node3D
var cam: Camera3D
var manual := false
var active := false
var fade := 1.0  # mustan peitto 0..1
var phase := ""
var sun_time := {}  # {"m", "d", "h", "min"}: kohtauksen kellonaika (tyhjä = pelin kello pysäytetään)

var _t := 0.0
var _pt := 0.0
var _actors: Array = []  # {node, i, path, speed, crate, shirt, trousers, idle, state}
var _crates: Array[Node3D] = []
var _props: Array = []  # lentävät vaatteet {node, v, spin, landed}
var _driver: CharacterBody3D
var _saved_t := 0.0
var _cut_t := 0.0  # kohtauksen kellonaika (pelin päivän klo 18), kun sun_time on tyhjä
var _own_layer: CanvasLayer
var _own_fade: ColorRect
var _own_cam := false
var _smoke_done := false
var _skip_t := 0.0
var _shown := false


static func y(u: float, v: float, h: float) -> Vector3:
	var w := Mokki.yw(u, v)
	return Vector3(w.x, h, w.y)


static func ground(u: float, v: float) -> Vector3:
	var w := Mokki.yw(u, v)
	return Vector3(w.x, maxf(Terrain.h(w.x, w.y), 0.0), w.y)


func start() -> void:
	active = true
	_t = 0.0
	_saved_t = game.sun.t_utc
	# Mökille tullaan torstai-iltana (klo 18), ja sauna on kylmä; Jukka panee sen lämpiämään.
	var lt: Dictionary = game.sun.local()
	_cut_t = _saved_t + float((18 * 60) - (int(lt.hour) * 60 + int(lt.minute))) * 60.0
	game.sauna.fire = 0.0
	game.sauna.temp = game.sauna.COLD_AIR
	_shown = false
	if not manual:
		_own_layer = CanvasLayer.new()
		_own_layer.layer = 90
		add_child(_own_layer)
		_own_fade = ColorRect.new()
		_own_fade.color = Color.BLACK
		_own_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_own_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_own_layer.add_child(_own_fade)
		cam = Camera3D.new()
		cam.far = 3000.0
		cam.fov = 65.0
		game.add_child(cam)
		_own_cam = true
		cam.make_current()
		game._hud.visible = false
	if not sun_time.is_empty():
		_set_sun()
	else:
		game.sun.t_utc = _cut_t
		game.sun._update(true)
	# Pelin hahmot piiloon ja jäähdytykselle; kohtauksen omat hahmot tilalle.
	for b: CharacterBody3D in game.crew:
		b.set_hidden_inside(true)
		b.process_mode = Node.PROCESS_MODE_DISABLED
	game.end_activity()
	_driver = game.crew[0]
	_driver.controls_enabled = false
	_drive_start()
	phase = "ajo"
	_pt = 0.0


func _set_sun() -> void:
	game.sun.t_utc = game.sun._local_to_utc(2026, sun_time.m, sun_time.d, sun_time.h, sun_time.min)
	game.sun._update(true)


func _drive_start() -> void:
	var car: CharacterBody3D = game.car
	car.place(Reitti.ROUTE[START_AT], Reitti.ROUTE[START_AT - 1])
	car.driver = _driver
	car.start_autopilot(false)
	car.speed = 8.0


func _process(delta: float) -> void:
	if active and not manual:
		step(delta)
		if _skip_t > 0.0:
			_skip_t -= delta


func _unhandled_input(event: InputEvent) -> void:
	if not active or manual:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("jump") or event.is_action_pressed("ui_cancel"):
		if _skip_t <= 0.0:
			_skip_t = 0.0
			_end()


## Kohtauksen kello eteenpäin delta sekuntia.
func step(delta: float) -> void:
	if not active:
		return
	_t += delta
	_pt += delta
	if sun_time.is_empty():
		game.sun.t_utc = _cut_t
	else:
		_set_sun()
	_step_phase(delta)
	if not active:
		return
	_move_actors(delta)
	_move_props(delta)
	_camera()
	var car: CharacterBody3D = game.car
	if phase != "ajo" and car.autopilot:
		car.autopilot = false
	# Häivytys sisään alussa ja ulos lopussa.
	if phase == "loppu":
		fade = clampf(_pt / 1.2, 0.0, 1.0)
	else:
		fade = clampf(1.0 - _t / 1.2, 0.0, 1.0)
	if _own_cam:
		_own_fade.color.a = fade
		if not cam.current:
			cam.make_current()


func _go(p: String) -> void:
	phase = p
	_pt = 0.0


func _step_phase(delta: float) -> void:
	var car: CharacterBody3D = game.car
	match phase:
		"ajo":
			var rest := Vector2(car.global_position.x - Reitti.HOME_SPOT.x, car.global_position.z - Reitti.HOME_SPOT.y).length()
			if rest < 5.0 or _pt > 25.0:
				car.autopilot = false
				car.driver = _driver
			if rest < 5.0 and absf(car.speed) < 0.5:
				_go("ulos")
		"ulos":
			if not _shown and _pt > 0.5:
				_shown = true
				_spawn_actors()
				Sfx.play("door", -4.0)
			if _shown and _pt > 1.8:
				for a in _actors:
					_walk_to(a, [_rear()], WALK)
				_go("takakontti")
		"takakontti":
			if _all_idle():
				for a in _actors:
					_take_crate(a)
				Sfx.play("door_close", -3.0)
				_go("nosto")
		"nosto":
			if _pt > 1.4:
				var k := 0
				for a in _actors:
					a.delay = 0.5 * k
					_walk_to(a, _carry_path(k), CARRY)
					k += 1
				_go("kanto")
		"kanto":
			# Leikkaus: metsäosuus näytetään vain hetki, sitten kantajat ovat jo ylämökin portailla.
			if _pt > 6.0:
				var m: Node3D = game.world.mokki
				var route: Array = m.route(m.points["ylamokki_kulma"], "kulku")
				var k := 0
				for a in _actors:
					var start: Vector3 = route[0] + Vector3((k - 1.5) * 0.5, 0, 0.0)
					(a.node as Node3D).global_position = start
					(a.node as Node3D).rotation.y = atan2(-Mokki.LAKE.x, -Mokki.LAKE.y)
					a.delay = 0.45 * k
					_walk_to(a, route + [y(CRATES_AT.x + (k - 1.5) * 0.5, CRATES_AT.y + 0.8, Mokki.DY)], CARRY)
					k += 1
				_go("kanto2")
		"kanto2":
			if _all_idle():
				_put_crates()
				_go("lasku")
		"lasku":
			if _pt > 1.6:
				# Jukka saunalle, muut odottavat terassin reunalla.
				var sauna_door: Vector3 = game.world.mokki.points["sauna_ovi"]
				_walk_to(_actors[3], game.world.mokki.route(_actors[3].node.global_position, "sauna_ovi"), WALK)
				for k in 3:
					_walk_to(_actors[k], [_lineup(k)], WALK)
				_actors[3].state = "sauna"
				_sauna_door = sauna_door
				_go("sauna")
		"sauna":
			var j: Dictionary = _actors[3]
			if j.state == "sauna" and _is_idle(j):
				j.state = "sisalla"
				j.node.visible = false
				Sfx.play("door", -6.0)
				_pt = 0.0
			elif j.state == "sisalla" and _pt > 1.8:
				game.sauna.ignite(3, 4, 1.0, false)
				Sfx.play("door_close", -6.0)
				j.state = "ulos"
				j.node.visible = true
				_walk_to(j, game.world.mokki.route(_sauna_door, "kulku") + [_lineup(3)], WALK)
			elif j.state == "ulos" and _is_idle(j):
				j.state = "valmis"
				for a in _actors:
					_face_lake(a)
				_go("riisu")
		"riisu":
			var k := int(_pt / 0.9)
			if k < 4 and not _actors[k].undressed and _pt - 0.9 * k > 0.35:
				_undress(_actors[k])
			if _pt > 0.9 * 4 + 2.2:
				_go("loppu")
		"loppu":
			if _pt > 1.4:
				_end()


var _sauna_door := Vector3.ZERO


func _rear() -> Vector3:
	var car: CharacterBody3D = game.car
	var p: Vector3 = car.global_position + car.global_transform.basis.z * (float(car.LENGTH) * 0.5 + 0.9)
	return Vector3(p.x, Terrain.h(p.x, p.z), p.z)


## Kantoreitti auton takaa ylämökin portaiden kautta terassille: maastoa pitkin ylämökin kulmalle ja sieltä
## mökin reittiverkkoa.
func _carry_path(k: int) -> Array:
	var out: Array = []
	var off := (k - 1.5) * 0.6
	for q: Vector2 in [Vector2(-5.0 + off, -34.0), Vector2(-7.0 + off, -24.0), Vector2(-8.0 + off, -15.0)]:
		out.append(ground(q.x, q.y))
	out.append(ground(-8.0 + off, -10.0))
	return out


func _lineup(k: int) -> Vector3:
	var s: Vector2 = game.SPAWNS[k]
	return y(s.x, s.y, Mokki.DY)


func _spawn_actors() -> void:
	var car: CharacterBody3D = game.car
	var b := car.global_transform.basis
	var doors := [car.global_position - b.x * 1.6 + b.z * 0.3, car.global_position + b.x * 1.6 + b.z * 0.3,
		car.global_position - b.x * 1.6 - b.z * 0.9, car.global_position + b.x * 1.6 - b.z * 0.9]
	for i in 4:
		var c: Node3D = Looks.make(game, _dressed(i))
		Porukka.decorate(i, c)
		var d: Vector3 = doors[i]
		c.global_position = Vector3(d.x, Terrain.h(d.x, d.z), d.z)
		c.rotation.y = car.rotation.y
		c.play("Idle", 0.0)
		_actors.append({"node": c, "i": i, "path": [], "speed": WALK, "crate": null, "idle": true, "delay": 0.0,
			"state": "", "undressed": false, "swap_at": -1.0})


## Päällepuettu ulkonäkö: t-paita, farkut ja kengät (uikkarit ja paljas yläruumis tulevat Porukka.look:sta).
static func _dressed(i: int) -> Dictionary:
	var l := Porukka.look(i)
	l["sleeve_x"] = 0.3
	l["shorts_y"] = -1.0
	l["shirt"] = SHIRTS[i]
	l["pants"] = JEANS[i]
	l["shoes"] = Color(0.12, 0.1, 0.09)
	return l


func _walk_to(a: Dictionary, path: Array, speed: float) -> void:
	a.path = path.duplicate()
	a.speed = speed
	a.idle = false


func _is_idle(a: Dictionary) -> bool:
	return a.path.is_empty() and a.delay <= 0.0


func _all_idle() -> bool:
	for a in _actors:
		if not _is_idle(a):
			return false
	return true


func _face_lake(a: Dictionary) -> void:
	a.node.rotation.y = atan2(-Mokki.LAKE.x, -Mokki.LAKE.y)


func _take_crate(a: Dictionary) -> void:
	var c := Looks.beer_crate()
	var node: Node3D = a.node
	node.add_child(c)
	c.position = Vector3(0, 1.02, -0.42)
	a.crate = c
	node.set_ik("arm_l", "upperarm_l", "lowerarm_l", "hand_l", Vector3(-0.22, 1.08, -0.4), Vector3(-0.7, 0.9, 0.1))
	node.set_ik("arm_r", "upperarm_r", "lowerarm_r", "hand_r", Vector3(0.22, 1.08, -0.4), Vector3(0.7, 0.9, 0.1))
	Sfx.play("pickup", -6.0)


func _put_crates() -> void:
	var k := 0
	for a in _actors:
		var c: Node3D = a.crate
		if c != null:
			a.node.remove_child(c)
			game.add_child(c)
			var p := y(CRATES_AT.x + (k % 2) * 0.46, CRATES_AT.y, Mokki.DY + 0.02 + 0.28 * (k / 2))
			c.global_transform = Transform3D(Basis(Vector3.UP, a.node.rotation.y), p)
			_crates.append(c)
			a.crate = null
			a.node.clear_ik()
			k += 1
	Sfx.play("rattle", -4.0)


func _move_actors(delta: float) -> void:
	for a in _actors:
		var n: Node3D = a.node
		if a.swap_at >= 0.0 and _t >= a.swap_at:
			a.swap_at = -1.0
			_swap_look(a)
			a.idle = true  # tanssi jatkuu, kunnes reitti annetaan
		if a.delay > 0.0:
			a.delay -= delta
			continue
		if a.path.is_empty():
			if not a.idle:
				a.idle = true
				n.play("Idle", 0.25)
			continue
		var target: Vector3 = a.path[0]
		var d := target - n.global_position
		var flat := Vector3(d.x, 0.0, d.z)
		if flat.length() < 0.15:
			a.path.remove_at(0)
			continue
		var step_len := minf(a.speed * delta, flat.length())
		var np := n.global_position + flat.normalized() * step_len
		np.y += d.y * step_len / maxf(flat.length(), 0.01)  # korkeus kulkee reittipisteestä toiseen tasaisesti
		n.global_position = np
		n.rotation.y = lerp_angle(n.rotation.y, atan2(-flat.x, -flat.z), clampf(8.0 * delta, 0.0, 1.0))
		n.play("Walk", 0.2, a.speed / 2.0)


## Vaatteet pois: paita ja housut lentävät kaaressa lattialle, hahmo vaihtuu uikkareihin.
func _undress(a: Dictionary) -> void:
	a.undressed = true
	var n: Node3D = a.node
	var i: int = a.i
	n.play("Interact", 0.1)
	var out := Vector3(Mokki.LAKE.x, 0.0, Mokki.LAKE.y)
	var side := Vector3(-out.z, 0.0, out.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + i
	for kind in ["shirt", "pants"]:
		var cloth := Node3D.new()
		game.add_child(cloth)
		var col: Color = SHIRTS[i] if kind == "shirt" else JEANS[i]
		if kind == "shirt":
			B.mesh(cloth, B.boxm(Vector3(0.5, 0.05, 0.6)), Vector3.ZERO, col)
			B.mesh(cloth, B.boxm(Vector3(0.22, 0.05, 0.3)), Vector3(0.34, 0, -0.1), col)
			B.mesh(cloth, B.boxm(Vector3(0.22, 0.05, 0.3)), Vector3(-0.34, 0, -0.1), col)
		else:
			B.mesh(cloth, B.boxm(Vector3(0.2, 0.05, 0.75)), Vector3(0.12, 0, 0), col)
			B.mesh(cloth, B.boxm(Vector3(0.2, 0.05, 0.75)), Vector3(-0.12, 0, 0), col)
		cloth.global_position = n.global_position + Vector3(0, 1.4 if kind == "shirt" else 0.9, 0)
		var v := Vector3(0, 3.6, 0) + out * rng.randf_range(0.2, 1.6) + side * rng.randf_range(-2.0, 2.0)
		_props.append({"node": cloth, "v": v, "spin": Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6)),
			"floor": Mokki.DY + 0.04, "landed": false})
	Sfx.play("cloth", -4.0)
	a.swap_at = _t + 0.35  # uikkarit näkyviin hetken päästä


func _swap_look(a: Dictionary) -> void:
	var n: Node3D = a.node
	n.restyle(Porukka.look(a.i))
	Porukka.decorate(a.i, n)
	n.play("Dance", 0.2)


func _move_props(delta: float) -> void:
	for p in _props:
		if p.landed:
			continue
		var n: Node3D = p.node
		p.v.y -= 9.8 * delta
		n.global_position += p.v * delta
		n.rotation += p.spin * delta
		if n.global_position.y <= p.floor and p.v.y < 0.0:
			n.global_position.y = p.floor
			n.rotation.x = 0.0
			n.rotation.z = 0.0
			p.landed = true


## Kamera vaiheen mukaan.
func _camera() -> void:
	var car: CharacterBody3D = game.car
	var at := Vector3.ZERO
	var from := Vector3.ZERO
	var fov := 65.0
	match phase:
		"ajo":
			if _pt < 4.5:
				# Tienvarsi: matala kuva pysäköintipaikan vierestä, auto ajaa kohti.
				var hp := Vector3(Reitti.HOME_SPOT.x, Terrain.h(Reitti.HOME_SPOT.x, Reitti.HOME_SPOT.y), Reitti.HOME_SPOT.y)
				from = hp + Vector3(-3.5, 0.9, -6.0)
				at = car.global_position + Vector3(0, 0.8, 0)
			else:
				var back := car.global_transform.basis.z
				from = car.global_position + back * -7.0 + car.global_transform.basis.x * 4.5 + Vector3(0, 1.6, 0)
				at = car.global_position + Vector3(0, 0.7, 0)
		"ulos", "takakontti", "nosto":
			var rear := _rear()
			var b := car.global_transform.basis
			from = rear + b.z * 3.4 + b.x * 3.0 + Vector3(0, 1.5, 0)
			at = rear + Vector3(0, 1.0, 0) - b.z * 1.4
		"kanto2":
			from = y(-9.5, 9.0, Mokki.DY + 1.5)
			at = y(-6.8, -3.5, Mokki.DY + 2.6)
		"kanto":
			# Seuranta edestä: kamera kulkee kantajien edellä ylämökin suuntaan.
			var c := _centroid()
			from = c + Vector3(0, 1.4, 0) + _lead_dir() * 5.5
			at = c + Vector3(0, 1.1, 0)
		"lasku", "sauna":
			from = y(-9.5, 8.5, Mokki.DY + 1.6)
			at = y(-3.5, 2.4, Mokki.DY + 0.9)
			if phase == "sauna" and not _actors.is_empty() and _actors[3].state in ["sisalla", "ulos"]:
				from = y(3.5, 9.0, Mokki.DY + 1.8)
				at = y(-0.5, -4.2, Mokki.DY + 3.4)
		"riisu", "loppu":
			var k := clampf(_pt / 8.0, 0.0, 1.0)
			from = y(-5.4, 10.5 - 2.0 * k, Mokki.DY + 1.5)
			at = y(-5.4, 1.2, Mokki.DY + 1.25)
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.fov = fov


func _centroid() -> Vector3:
	var c := Vector3.ZERO
	for a in _actors:
		c += (a.node as Node3D).global_position
	return c / maxf(_actors.size(), 1.0)


## Suunta, josta kamera kuvaa kantajia: kulkusuunnan vastakkaisesta päästä edestä.
func _lead_dir() -> Vector3:
	var a: Dictionary = _actors[0]
	if a.path.is_empty():
		return Vector3(0, 0, 1)
	var d: Vector3 = (a.path[0] as Vector3) - (a.node as Node3D).global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.1 else Vector3(0, 0, 1)


func _end() -> void:
	if not active:
		return
	active = false
	phase = ""
	for a in _actors:
		(a.node as Node3D).queue_free()
	_actors.clear()
	for c in _crates:
		c.queue_free()
	_crates.clear()
	for p in _props:
		(p.node as Node3D).queue_free()
	_props.clear()
	game.car.autopilot = false
	game.car.driver = null
	for i in game.crew.size():
		var b: CharacterBody3D = game.crew[i]
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.set_hidden_inside(false)
		var s: Vector2 = game.SPAWNS[i]
		var w := Mokki.yw(s.x, s.y)
		b.global_position = Vector3(w.x, Mokki.DY + 0.1, w.y)
		b.rotation.y = atan2(-Mokki.LAKE.x, -Mokki.LAKE.y)
		b.velocity = Vector3.ZERO
	_driver.controls_enabled = true
	if _own_cam:
		cam.queue_free()
		_own_layer.queue_free()
		_own_cam = false
		game._hud.visible = true
		game.player.activate_camera()
	if sun_time.is_empty():
		game.sun.t_utc = _saved_t
		game.sun._update(true)
	finished.emit()
