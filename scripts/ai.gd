extends RefCounted
## Tietokoneen ohjaama mökkiläinen: valitsee tekemisen (pöydän ääressä istuminen, grillaus, saunominen ja
## uinti, ylämökillä käynti, huussi, rantakaiteella jutustelu) ja kulkee mokki.gd:n reittipisteitä pitkin
## ohjaamalla on_foot.gd-hahmoa samoilla syötteillä kuin pelaaja (kaasu, kääntö, juoksu, hyppy).
## Kun aurinko on laskemassa, porukka kerääntyy laiturille ja etuterassille katsomaan sitä.

const ACTIVITIES := {"poyta": 5.0, "grilli": 2.0, "sauna": 2.5, "uinti": 1.5, "ylamokki": 1.2, "huussi": 0.6,
	"kaide": 1.5, "kokkaus": 1.2, "kahvi": 1.2, "kalja": 1.0}
## Tekemiset per hahmo painotettuina (Jukka grillaa, Jaakko ui, Marko istuu).
## Jukka ei nuku päikkäreitä (ylämökki), vaan keittää kahvit.
const LIKES := {"Jukka": {"grilli": 3.0, "kalja": 1.5, "ylamokki": 0.0, "kahvi": 1.5}, "Jaakko": {"uinti": 2.5, "sauna": 1.5}, "Marko": {"poyta": 1.6, "kokkaus": 1.0},
	"Santtu": {"ylamokki": 1.6}}

static var _taken := {}  # istumapaikan indeksi -> hahmo
static var _stove := ""  # kuka on hellalla (Markon pyttipannu tai Jukan kahvit): vain yksi kerrallaan

var body: CharacterBody3D
var mokki: Node3D
var sun: Node
var name := ""
var rng := RandomNumberGenerator.new()

var throttle := 0.0
var steer := 0.0
var fast := false
var jump := false

var activity := ""
var _path: Array = []
var _state := "walk"  # walk | stay | hidden
var _timer := 0.0
var _seat := -1
var _face := Vector3.ZERO
var _stuck := 0.0
var _last := Vector3.ZERO
var _next := ""
var _talk_t := 0.0
var _avoid := 0.0
var _avoid_dir := 1.0
var _loyly_t := 0.0
var _card_seat: Array = []
var _seat_s := -1  # lauteiden paikka, jolle ollaan menossa
var _prev := Vector3.INF  # viimeksi saavutettu reittipiste (jumista sinne takaisin)
var _back_to := Vector3.INF  # piste, jonne jumista palattiin (kerran per reittiväli)


func _init(b: CharacterBody3D, m: Node3D, s: Node, n: String) -> void:
	body = b
	mokki = m
	sun = s
	name = n
	rng.seed = hash(n) + Time.get_ticks_usec()


func reset() -> void:
	_leave_seat()
	activity = ""
	if _stove == name:
		_stove = ""
	_set_path([])
	_state = "walk"
	body.pose = ""
	body.set_hidden_inside(false)


func think(delta: float) -> void:
	throttle = 0.0
	steer = 0.0
	fast = false
	jump = false
	if activity == "":
		_choose()
	# Auringonlasku vetää laiturille (paitsi saunassa, hellalla ja korttipöydässä olevia).
	if _sunset() and not activity in ["aurinko", "kortit", "sauna", "kokkaus", "kahvi"] and _state != "hidden":
		_start("aurinko")
	match _state:
		"walk":
			_walk(delta)
		"stay":
			_stay(delta)
		"hidden":
			_timer -= delta
			if _timer <= 0.0:
				body.set_hidden_inside(false)
				_done()


## Korttipeli alkoi: pöytään omalle paikalle i (mokki.table_seats) pelin ajaksi.
func cards(i: int) -> void:
	if activity == "kortit":
		return
	if body.pose.begins_with("Sitting"):
		body.stand_up()
	_leave_seat()
	body.pose = ""
	body.set_hidden_inside(false)
	_next = ""
	activity = "kortit"
	_state = "walk"
	_card_seat = mokki.table_seats[i]
	_set_path(mokki.route(body.global_position, "keittio"))
	_path.append_array(mokki.table_paths[i])


func cards_end() -> void:
	if activity == "kortit":
		_timer = 0.0
		if _state != "stay":
			_done()


func _sunset() -> bool:
	return sun != null and sun.altitude > -1.0 and sun.altitude < 5.0 and (sun.azimuth > 250.0 or sun.azimuth < 70.0)


func _choose() -> void:
	if _next != "":
		var n := _next
		_next = ""
		_start(n)
		return
	var total := 0.0
	var w := {}
	for a in ACTIVITIES:
		if a == "kokkaus" and name != "Marko":
			continue  # vain Marko osaa kokata
		if a == "kahvi" and name != "Jukka":
			continue  # vain Jukka keittää kahvit
		w[a] = ACTIVITIES[a] * LIKES.get(name, {}).get(a, 1.0)
		total += w[a]
	var r := rng.randf() * total
	for a in w:
		r -= w[a]
		if r <= 0.0:
			_start(a)
			return
	_start("poyta")


func _start(a: String) -> void:
	_leave_seat()
	if a in ["kokkaus", "kahvi"]:
		if _stove != "" and _stove != name:
			a = "poyta"  # toinen on jo hellalla
		else:
			_stove = name
	body.pose = ""
	activity = a
	_state = "walk"
	var goal := ""
	match a:
		"poyta":
			# Teltan pöydän takapenkille takaa, etupenkille edestä.
			goal = "poyta"
			_seat = _free_seat()
			if _seat >= 0:
				var s0: Vector3 = mokki.seats[_seat][0]
				if s0.distance_to(mokki.points.poyta_etu) < s0.distance_to(mokki.points.poyta):
					goal = "poyta_etu"
		"grilli":
			goal = "grilli"
		"sauna":
			goal = "loylyhuone"
			_seat_s = mokki.free_seat(mokki.sauna_seats, body)
			if _seat_s >= 0:
				body.claimed_seat = mokki.sauna_seats[_seat_s][0]
		"kokkaus", "kahvi":
			goal = "hella"
		"kalja":
			goal = "katko"
		"uinti":
			goal = "uinti" + str(rng.randi_range(1, 3))
		"ylamokki":
			goal = "ylamokki_ovi"
		"huussi":
			goal = "huussi"
		"kaide":
			goal = "kaide"
		"aurinko":
			goal = "laituri_paa" if rng.randf() < 0.6 else "etuterassi"
	_set_path(mokki.route(body.global_position, goal))
	if a == "aurinko":
		var v: Vector3 = mokki.views[rng.randi() % mokki.views.size()]
		_path.append(v + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))
	elif a == "poyta":
		if _seat >= 0:
			_taken[_seat] = name
			var s: Array = mokki.seats[_seat]
			var from_table: Vector3 = (s[0] - s[1]).normalized()
			_path.append(s[0] + from_table * 0.45)


func _free_seat() -> int:
	var free := []
	for i in mokki.seats.size():
		if not _taken.has(i):
			free.append(i)
	return free[rng.randi() % free.size()] if not free.is_empty() else -1


func _leave_seat() -> void:
	if _seat >= 0 and _taken.get(_seat, "") == name:
		_taken.erase(_seat)
	_seat = -1
	body.claimed_seat = Vector3.INF


func _walk(delta: float) -> void:
	if _path.is_empty():
		_arrive()
		return
	var p := body.global_position
	var t: Vector3 = _path[0]
	var d := Vector2(t.x - p.x, t.z - p.z)
	var radius := 1.2 if body.swimming else 0.45
	# Toinen hahmo tiellä: väistetään sivuun; jos se seisoo itse reittipisteessä, piste on saavutettu.
	var blocker: Node3D = null
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i).get_collider()
		if c is CharacterBody3D:
			blocker = c
	if blocker != null:
		if _avoid <= 0.0:
			_avoid_dir = 1.0 if rng.randf() < 0.5 else -1.0
		_avoid = 0.7
		var bt := blocker.global_position
		if Vector2(bt.x - t.x, bt.z - t.z).length() < 1.0 and d.length() < 1.8:
			_reached()
			return
	if d.length() < radius:
		_reached()
		_stuck = 0.0
		return
	var want := atan2(-d.x, -d.y)
	if _avoid > 0.0:
		_avoid -= delta
		want += _avoid_dir * 1.1
	var diff := wrapf(want - body.rotation.y, -PI, PI)
	steer = clampf(diff * 2.5, -1.0, 1.0)
	throttle = 1.0 if absf(diff) < 0.7 else 0.25
	fast = d.length() > 12.0 and not body.exhausted and not body.swimming and activity == "aurinko"
	if Vector2(p.x - _last.x, p.z - _last.z).length() < 0.25 * delta and throttle > 0.5:
		_stuck += delta
	else:
		_stuck = maxf(0.0, _stuck - delta)
	_last = p
	# Jumissa (esim. tönäisty oven vierestä seinää vasten): ensin takaisin edelliseen reittipisteeseen, sitten
	# hyppy ja lopulta siirto seuraavaan pisteeseen.
	if _stuck > 1.5 and _back_to == Vector3.INF and _prev != Vector3.INF:
		_back_to = _prev
		_path.push_front(_prev)
		_stuck = 0.0
		return
	if _stuck > 2.5:
		jump = true
	if _stuck > 7.0:
		body.global_position = t + Vector3.UP * 0.3
		body.velocity = Vector3.ZERO
		_stuck = 0.0


func _reached() -> void:
	_prev = _path.pop_front()
	if _prev != _back_to:
		_back_to = Vector3.INF


## Uusi reitti: vanhat jumitiedot pois.
func _set_path(path: Array) -> void:
	_path = path
	_prev = Vector3.INF
	_back_to = Vector3.INF


func _arrive() -> void:
	match activity:
		"poyta":
			if _seat >= 0:
				var s: Array = mokki.seats[_seat]
				body.sit_at(s[0], s[1])
			_stay_for(rng.randf_range(30.0, 70.0), "Sitting_Idle")
		"grilli":
			_face = body.global_position + _dir_yard(Vector2(0.0, -1.0))
			_stay_for(rng.randf_range(20.0, 40.0), "Idle")
		"kaide":
			_face = body.global_position + _dir_yard(Vector2(rng.randf_range(-0.4, 0.4), 1.0))
			_stay_for(rng.randf_range(15.0, 35.0), "Idle_Talking")
		"aurinko":
			var sd: Vector3 = sun.sun_dir
			_face = body.global_position + Vector3(sd.x, 0, sd.z) * 10.0
			_stay_for(rng.randf_range(40.0, 90.0), "Idle")
		"uinti":
			_stay_for(rng.randf_range(10.0, 25.0), "")
		"sauna":
			body.claimed_seat = Vector3.INF
			var i: int = _seat_s if _seat_s >= 0 else mokki.free_seat(mokki.sauna_seats, body)
			if i >= 0 and mokki.free_seat([mokki.sauna_seats[i]], body) < 0:
				i = mokki.free_seat(mokki.sauna_seats, body, body.global_position)  # joku ehti ensin
			if i >= 0:
				body.sit_at(mokki.sauna_seats[i][0], mokki.sauna_seats[i][1])
			_loyly_t = rng.randf_range(4.0, 10.0)
			_stay_for(rng.randf_range(40.0, 80.0), "Sitting_Idle" if i >= 0 else "Idle")
			_next = "uinti"
		"kokkaus", "kahvi":
			_face = mokki.cook_face
			_stay_for(rng.randf_range(25.0, 45.0), "Idle")
		"kalja":
			_face = mokki.stash_pos
			body.drink(0.0)
			_stay_for(rng.randf_range(8.0, 16.0), "Idle_Talking")
		"kortit":
			body.sit_at(_card_seat[0], _card_seat[1])
			_stay_for(1e9, "Sitting_Idle")
		"ylamokki":
			_hide(rng.randf_range(25.0, 60.0))
		"huussi":
			_hide(rng.randf_range(12.0, 25.0))
		_:
			_done()


func _dir_yard(v: Vector2) -> Vector3:
	var w: Vector2 = mokki.EAST * v.x + mokki.LAKE * v.y
	return Vector3(w.x, 0, w.y) * 5.0


func _stay_for(t: float, pose: String) -> void:
	_state = "stay"
	_timer = t
	body.pose = pose
	_talk_t = rng.randf_range(3.0, 8.0)


func _hide(t: float) -> void:
	_state = "hidden"
	_timer = t
	body.set_hidden_inside(true)


func _stay(delta: float) -> void:
	_timer -= delta
	if activity == "sauna" and body.pose.begins_with("Sitting"):
		_loyly_t -= delta
		if _loyly_t <= 0.0:
			_loyly_t = rng.randf_range(10.0, 22.0)
			mokki.loyly.emit()
	if _face != Vector3.ZERO and body.pose != "Sitting_Idle" and body.pose != "Sitting_Talking":
		var d := _face - body.global_position
		var want := atan2(-d.x, -d.z)
		body.rotation.y = lerp_angle(body.rotation.y, want, 1.0 - exp(-3.0 * delta))
	# Istuessa ja seistessä vuorotellen puhetta.
	_talk_t -= delta
	if _talk_t <= 0.0:
		_talk_t = rng.randf_range(4.0, 10.0)
		if body.pose == "Sitting_Idle":
			body.pose = "Sitting_Talking"
		elif body.pose == "Sitting_Talking":
			body.pose = "Sitting_Idle"
		elif body.pose == "Idle" and activity != "aurinko":
			body.pose = "Idle_Talking"
		elif body.pose == "Idle_Talking":
			body.pose = "Idle"
	if activity == "aurinko" and not _sunset():
		_timer = minf(_timer, 0.0)
	if _timer <= 0.0:
		_done()


func _done() -> void:
	if body.pose.begins_with("Sitting"):
		body.stand_up(activity == "sauna")
	if activity == "kokkaus":
		mokki.cooked.emit(rng.randi_range(2, 4))
	elif activity == "kahvi":
		mokki.coffee.emit(rng.randi_range(3, 4))
	if _stove == name:
		_stove = ""
	body.pose = ""
	_face = Vector3.ZERO
	_leave_seat()
	if activity == "uinti":
		_next = "kaide" if rng.randf() < 0.5 else "poyta"
		activity = "kuivalle"
		_state = "walk"
		_set_path(mokki.route(body.global_position, "rantaportaat"))
		return
	activity = ""
