extends Node
## Konttauskunto: kun joku mökkiläinen juo itsensä kahden promillen humalaan (on_foot.gd promille), alkaa välianimaatio,
## jossa koko porukka heiluu kännissä terassilla ja konttaa sitten portaita alas rannalle. Näytetään enintään kerran
## pelipäivässä. Kohtaus ohjaa pelin hahmoja omalla ohjaajallaan (Walker) ja omalla kamerallaan; E tai välilyönti ohittaa.
## Traileri ajaa kohtausta itse (manual = true, step(delta), oma kamera cam, häivytys fade).

const Porukka := preload("res://scripts/porukka.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Terrain := preload("res://scripts/terrain.gd")

const TRIGGER := 2.0  # promillea
const SWAY_T := 5.0  # heiluminen terassilla
const CRAWL_T := 13.0  # konttaus rannalle
const CRAWL_PROMILLE := 3.1  # konttausasento (on_foot.gd CRAWL on 3,0)


## Hahmon ohjaaja: kulkee reittipisteitä pitkin ja heiluu humalassa (on_foot.gd lukee throttle, steer, fast, jump).
class Walker:
	extends RefCounted
	var body: CharacterBody3D
	var path: Array = []
	var wobble := 0.0
	var phase := 0.0
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump := false
	var _t := 0.0

	func think(delta: float) -> void:
		_t += delta
		throttle = 0.0
		steer = 0.0
		if path.is_empty():
			return
		var t: Vector3 = path[0]
		var p := body.global_position
		var d := Vector2(t.x - p.x, t.z - p.z)
		if d.length() < 0.7:
			path.remove_at(0)
			return
		var diff := wrapf(atan2(-d.x, -d.y) - body.rotation.y, -PI, PI)
		steer = clampf(diff * 2.0 + sin(_t * 1.7 + phase) * wobble, -1.0, 1.0)
		throttle = (0.35 + 0.35 * absf(sin(_t * 0.9 + phase))) if body.pose != "Ryomii" else 1.0

	func reset() -> void:
		pass


var game: Node3D
var cam: Camera3D
var manual := false
var active := false
var fade := 1.0

var _t := 0.0
var _day := -1
var _walkers: Array = []
var _layer: CanvasLayer
var _fade: ColorRect
var _own_cam := false
var _crawling := false
var _prev: Array = []


func _process(delta: float) -> void:
	if active:
		if not manual:
			step(delta)
		return
	if game.state != "play" or game.saapuminen.active or game.activity != "" or game.get_tree().paused:
		return
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		var was: float = _prev[j] if j < _prev.size() else 0.0
		if _prev.size() <= j:
			_prev.append(b.promille)
		_prev[j] = b.promille
		if was < TRIGGER and b.promille >= TRIGGER and _day != int(game.sun.local().day) and b.boat == null:
			start()
			return


func _unhandled_input(event: InputEvent) -> void:
	if active and not manual and (event.is_action_pressed("interact") or event.is_action_pressed("jump")):
		_end()


func start() -> void:
	active = true
	_t = 0.0
	_crawling = false
	_day = int(game.sun.local().day)
	game.end_activity()
	if not manual:
		_layer = CanvasLayer.new()
		_layer.layer = 90
		add_child(_layer)
		_fade = ColorRect.new()
		_fade.color = Color.BLACK
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(_fade)
		cam = Camera3D.new()
		cam.far = 3000.0
		cam.fov = 70.0
		game.add_child(cam)
		_own_cam = true
		cam.make_current()
		game._hud.visible = false
	var m: Node3D = game.world.mokki
	_walkers.clear()
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if b.boat != null:
			b.leave_boat()
		if b.brain != null:
			b.brain.reset()
		b.set_hidden_inside(false)
		b.controls_enabled = true
		b.is_player = false
		var s: Vector2 = game.SPAWNS[j]
		var w := Mokki.yw(s.x + (j - 1.5) * 0.3, s.y)
		b.global_position = Vector3(w.x, Mokki.DY + 0.1, w.y)
		b.velocity = Vector3.ZERO
		b.pose = ""
		b.promille = maxf(b.promille, TRIGGER)
		var wk := Walker.new()
		wk.body = b
		wk.wobble = 0.9
		wk.phase = j * 1.9
		wk.path = _sway_path(m, j)
		b.brain = wk
		_walkers.append(wk)


## Heiluminen terassilla: edestakaisin etuterassin ja pöydän välillä.
func _sway_path(m: Node3D, j: int) -> Array:
	var pts: Array = []
	var names := ["etuterassi", "kulku", "poyta_etu", "kaide", "etuterassi", "kulku"]
	for k in names.size():
		var n: String = names[(k + j) % names.size()]
		pts.append((m.points[n] as Vector3) + Vector3((j - 1.5) * 0.25, 0, 0))
	return pts


func step(delta: float) -> void:
	if not active:
		return
	_t += delta
	if not _crawling and _t >= SWAY_T:
		_crawling = true
		var m: Node3D = game.world.mokki
		for j in _walkers.size():
			var wk: Walker = _walkers[j]
			var b: CharacterBody3D = wk.body
			b.promille = maxf(b.promille, CRAWL_PROMILLE)
			b.pose = "Ryomii"
			wk.wobble = 0.5
			var r: Array = m.route(b.global_position, "ranta")
			wk.path = r
	_camera()
	if _t < 1.0:
		fade = 1.0 - _t
	elif _t > SWAY_T + CRAWL_T - 1.0:
		fade = clampf(_t - (SWAY_T + CRAWL_T - 1.0), 0.0, 1.0)
	else:
		fade = 0.0
	if _own_cam:
		_fade.color.a = fade
		if not cam.current:
			cam.make_current()
	if _t >= SWAY_T + CRAWL_T:
		_end()


func _centroid() -> Vector3:
	var c := Vector3.ZERO
	for wk: Walker in _walkers:
		c += wk.body.global_position
	return c / maxf(_walkers.size(), 1.0)


func _camera() -> void:
	var c := _centroid()
	var lake := Vector3(Mokki.LAKE.x, 0.0, Mokki.LAKE.y)
	var side := Vector3(Mokki.EAST.x, 0.0, Mokki.EAST.y)
	var from: Vector3
	var at: Vector3
	if not _crawling:
		# Terassi järven puolelta: porukka heiluu kaiteen edessä.
		var k := _t / SWAY_T
		from = c + lake * 2.6 + side * lerpf(-1.4, 1.4, k) + Vector3(0, 2.4, 0)
		at = c + Vector3(0, 1.0, 0)
	else:
		# Konttaajat rannalla matalalta kuvattuna.
		var k := clampf((_t - SWAY_T) / CRAWL_T, 0.0, 1.0)
		from = c + lake * lerpf(3.0, 3.6, k) - side * 1.2 + Vector3(0, lerpf(2.8, 1.5, k), 0)
		at = c + Vector3(0, 0.4, 0)
	cam.global_position = from
	if from.distance_to(at) > 0.01:
		cam.look_at(at, Vector3.UP)


func _end() -> void:
	if not active:
		return
	active = false
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		b.brain = null
		game.set_crew_mode(j, "")
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if b.promille >= 2.9:
			b.promille = 2.6  # nousevat konttauksesta pystyyn, humala jää
		b.pose = ""
	if _own_cam:
		cam.queue_free()
		_layer.queue_free()
		_own_cam = false
		game._hud.visible = true
	game.choose_character(game.player_index)
