extends Node3D
## Tutkimusmatka kumiveneellä viinakätkölle (64.431793 N, 26.884539 E): kätkö on lahden lounaisrannalla,
## n. 100 m mökiltä. Soudetaan: mökin edestä ulos lohkareiden ohi, länteen ja rantaa pitkin lounaaseen
## rantautumispaikalle (LANDING), josta kätkölle on 11 m rantaa ylös.
## - Veneessä Q aloittaa tutkimusmatkan: Vangeliksen Chariots of Fire soi (retkimusiikki.gd), ja koko porukka
##   tulee veneen vanavedessä: tietokoneen hahmot kahlaavat veteen ja uivat jonossa veneen perässä sen
##   kulkemaa reittiä (vanavedessä jaksaa uida, kunto ei kulu). Kompassin kätköosoitin näyttää kätkön.
## - Soutu kestää runsaan minuutin, perillä juhlitaan kappaleen loppuun (PARTY_T).
## - Kun vene on rannassa kätkön kohdalla, porukka nousee kätkölle juhlimaan; kappaleen loputtua musiikki häipyy
##   ja tietokoneen hahmot palaavat omiin puuhiinsa (uiden takaisin mökille). Veneessä Q keskeyttää matkan.
## - Kätkö: lahonnut puulaatikko havujen alla kuten rannan kätkö (ranta.gd), ehtymätön (E olut, Q viina).
## Moninpeli: aloitus ja keskeytys lähtevät kaikille (viesti "retki"), joten musiikki soi kaikilla; hostin
## tietokone ohjaa vapaita hahmoja. Perillepääsyn kukin kone huomaa itse veneen paikasta.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Ranta := preload("res://scripts/ranta.gd")
const Ai := preload("res://scripts/ai.gd")
const Porukka := preload("res://scripts/porukka.gd")
const Musiikki := preload("res://scripts/retkimusiikki.gd")

const LATLON := Vector2(64.431793, 26.884539)
## Kätkö maailman koordinaateissa (main.gd: aloituspaikka 64.432089 N, 26.886448 E; metrit astetta kohden).
const STASH := Vector2((26.884539 - 26.886448) * 48185.5, (64.432089 - 64.431793) * 111483.9)
## Rantautumispaikka lounaisrannalla (vettä n. 0,26 m) ja polku sieltä rantaa ylös kätkölle.
const LANDING := Vector2(-98.0, 24.0)
const SHORE_PATH := [Vector2(-96.0, 27.0), Vector2(-94.0, 30.0)]
## Veneen reitti mökin edestä kätkölle (testi): ensin ulos lohkareiden ohi, länteen ja rantaa pitkin lounaaseen.
## Vettä koko matkalla vähintään 0,22 m, matkaa n. 115 m.
const ROUTE := [Vector2(-15.0, -21.0), Vector2(-60.0, -20.0), Vector2(-90.0, 5.0), LANDING]
const ARRIVE_DIST := 12.0  # vene näin lähellä rantautumispaikkaa: perillä
const PARTY_T := 22.0  # kätköllä juhlitaan ennen paluuta: kappaleen viimeinen fraasi (retkimusiikki.gd FINALE)
const GAP := 2.2  # uimarien väli jonossa
const LINES_START := ["Tutkimusmatka! Kaikki veneen perään!", "Viinakätkö odottaa – uidaan perässä!",
	"Kohti tuntematonta! Ja kätköä.", "Vanavedessä jaksaa uida vaikka Kajaaniin."]
const LINES_ARRIVE := ["Kätkö löytyi! Kippis tutkimusmatkalle!", "Tämä on historiallinen hetki.",
	"Vangelis soi ja viina virtaa.", "Löytöretki onnistui!"]

var game: Node3D
var stash_pos := Vector3.ZERO
var active := false
var state := ""  # matka | perilla
var music: Node  # retkimusiikki.gd
var _trail: Array = []  # veneen kulkema reitti (uusin ensin), uimarit seuraavat sitä
var _brains := {}  # tämän koneen ohjaamat tietokoneen hahmot matkalla: indeksi -> Follow
var _party_t := 0.0


## Tietokoneen hahmo tutkimusmatkalla: ensin mökin reittipisteitä veteen, sitten oma paikka jonossa veneen
## perässä (slot), perillä rinnettä ylös kätkölle. Samat syötteet kuin pelaajalla.
class Follow:
	extends RefCounted
	var body: CharacterBody3D
	var retki: Node3D
	var k := 0  # paikka jonossa
	var path: Array = []
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump := false
	var spot := Vector3.INF  # paikka kätköllä perillä
	var at_stash := false
	var _stuck := 0.0
	var _last := Vector3.ZERO

	func reset() -> void:
		pass

	func think(delta: float) -> void:
		throttle = 0.0
		steer = 0.0
		fast = false
		jump = false
		# Vanavedessä jaksaa: kunto ei kulu.
		body.stamina = 100.0
		body.exhausted = false
		var p := body.global_position
		var t: Vector3 = retki.slot(k)
		if not path.is_empty():
			t = path[0]
		elif spot != Vector3.INF:
			t = spot
		var d := Vector2(t.x - p.x, t.z - p.z)
		var r := 1.2 if body.swimming else 0.5
		if d.length() < r:
			_stuck = 0.0
			if not path.is_empty():
				path.pop_front()
				return
			if spot != Vector3.INF:
				# Kätköllä: kasvot kätköä kohti.
				at_stash = true
				var f := Vector2(retki.stash_pos.x - p.x, retki.stash_pos.z - p.z)
				steer = clampf(wrapf(atan2(-f.x, -f.y) - body.rotation.y, -PI, PI) * 2.5, -1.0, 1.0)
			return
		if at_stash and d.length() < 1.5:
			return  # tönäisty vähän sivuun kätköllä: ei lähdetä kävelemään
		var diff := wrapf(atan2(-d.x, -d.y) - body.rotation.y, -PI, PI)
		steer = clampf(diff * 2.5, -1.0, 1.0)
		throttle = 1.0 if absf(diff) < 0.8 else 0.25
		fast = d.length() > (1.5 if body.swimming else 6.0)
		if Vector2(p.x - _last.x, p.z - _last.z).length() < 0.2 * delta and throttle > 0.5:
			_stuck += delta
		else:
			_stuck = maxf(0.0, _stuck - delta)
		_last = p
		if _stuck > 2.0:
			jump = true
		# Jumissa tai jäänyt kauas jälkeen (esim. kiven taakse tai vielä rannalle, kun vene on jo kaukana):
		# suoraan omalle paikalle.
		var s: Vector3 = retki.slot(k)
		if not path.is_empty() and spot == Vector3.INF and Vector2(s.x - p.x, s.z - p.z).length() > 50.0:
			path.clear()
			t = s
		if _stuck > 5.0 or (path.is_empty() and Vector2(t.x - p.x, t.z - p.z).length() > 40.0):
			body.global_position = t + Vector3.UP * 0.3
			body.velocity = Vector3.ZERO
			_stuck = 0.0


## Puut pois kätkön kohdalta (trees.gd).
static func clears_tree(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(STASH) < 1.6


func _ready() -> void:
	var batch := B.Batch.new()
	stash_pos = Ranta.build_stash(batch, STASH, LANDING - STASH, 57)  # rinne laskee rantautumispaikalle
	var mi := MeshInstance3D.new()
	mi.mesh = batch.commit()
	mi.material_override = B.vcol_mat()
	add_child(mi)
	music = Musiikki.new()
	add_child(music)
	game.mp.on("retki", func(d: Dictionary, _from: int) -> void:
		if bool(d.on):
			_begin(false)
		else:
			_end(false))


func near_stash(p: Vector3) -> bool:
	return Vector2(p.x - stash_pos.x, p.z - stash_pos.z).length() < 1.6 and absf(p.y - stash_pos.y) < 1.5


## Veneessä Q: aloittaa tai keskeyttää tutkimusmatkan (kaikilla koneilla).
func toggle() -> void:
	if active:
		_end(true)
		game.toast("Tutkimusmatka keskeytettiin.", 3.0)
	else:
		_begin(true)


func _host() -> bool:
	return not game.mp.online() or game.mp.net.is_host()


func _begin(send: bool) -> void:
	if active:
		return
	active = true
	state = "matka"
	_party_t = 0.0
	var b: Node3D = game.boat
	_trail = [Vector2(b.global_position.x, b.global_position.z)]
	music.start()
	if send:
		game.mp.send({"t": "retki", "on": true})
	game.toast("Tutkimusmatka viinakätkölle! Souda länteen ja rantaa pitkin lounaaseen – porukka uimassa vanavedessä. "
		+ "Kompassi näyttää kätkön.", 6.0)
	if _host():
		_take_crew()


func _end(send: bool) -> void:
	if not active:
		return
	active = false
	state = ""
	music.fade_out(4.0)
	if send:
		game.mp.send({"t": "retki", "on": false})
	_release_crew()


## Host: vapaat tietokoneen hahmot (ei pallopelissä olevia) jonoon veneen perään.
func _take_crew() -> void:
	var k := 0
	var said := false
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if game.crew_modes[j] != "ai" or b.boat != null or not (b.brain is Ai):
			continue
		b.brain.reset()
		if b.pose.begins_with("Sitting"):
			b.stand_up()
		b.pose = ""
		var f := Follow.new()
		f.body = b
		f.retki = self
		f.k = k
		k += 1
		# Mökin pihalta reittipisteitä rantaan, sitten veteen.
		if b.global_position.distance_to(game.world.mokki.points.ranta_vesi) < 60.0:
			f.path = game.world.mokki.route(b.global_position, "ranta_vesi")
		b.brain = f
		_brains[j] = f
		if not said or randf() < 0.5:
			said = true
			game.chat.ai_say(j, LINES_START.pick_random())


func _release_crew() -> void:
	for j in _brains:
		var b: CharacterBody3D = game.crew[j]
		if b.brain == _brains[j] and game.crew_modes[j] == "ai":
			b.brain = Ai.new(b, game.world.mokki, game.sun, Porukka.CREW[j].name)
	_brains.clear()


## Jonon paikka k: veneen kulkemaa reittiä pitkin GAP-välein taaksepäin, vuorotellen sivuille.
func slot(k: int) -> Vector3:
	var want := 2.6 + GAP * k
	var b: Node3D = game.boat
	var prev := Vector2(b.global_position.x, b.global_position.z)
	var dir := Vector2(b.global_transform.basis.z.x, b.global_transform.basis.z.z).normalized()  # perän suuntaan
	var p := prev + dir * want
	var walked := 0.0
	for q: Vector2 in _trail:
		var seg := prev.distance_to(q)
		if seg > 0.01:
			dir = (q - prev) / seg
			if walked + seg >= want:
				p = prev + dir * (want - walked)
				break
			walked += seg
			prev = q
			p = q + dir * (want - walked)
	var side := Vector2(-dir.y, dir.x) * (0.7 if k % 2 == 0 else -0.7)
	p += side
	return Vector3(p.x, 0.0, p.y)


func _physics_process(delta: float) -> void:
	if not active:
		return
	var b: Node3D = game.boat
	var bp := Vector2(b.global_position.x, b.global_position.z)
	if bp.distance_to(_trail[0]) > 1.0:
		_trail.push_front(bp)
		if _trail.size() > 80:
			_trail.pop_back()
	# Hahmo vaihtui pelaajalle tai toiselle koneelle kesken matkan: jätetään jonosta.
	for j in _brains.keys():
		if (game.crew[j] as CharacterBody3D).brain != _brains[j]:
			_brains.erase(j)
	if state == "matka" and bp.distance_to(LANDING) < ARRIVE_DIST:
		_arrive()
	elif state == "perilla":
		_party_t += delta
		if _party_t >= PARTY_T:
			_end(false)
			game.toast("Tutkimusmatka päättyi. Porukka ui takaisin mökille.", 4.0)


## Perillä: porukka rinnettä ylös kätkölle juhlimaan.
func _arrive() -> void:
	state = "perilla"
	_party_t = 0.0
	game.toast("Perillä! Viinakätkö rinteessä rannan yläpuolella. E: olut · Q: huikka viinaa.", 6.0)
	music.arrive()  # viimeinen teema juhlien ajaksi
	var said := false
	for j in _brains:
		var f: Follow = _brains[j]
		var a := TAU * f.k / maxf(1.0, _brains.size()) + 0.6
		var at := STASH + (LANDING - STASH).normalized().rotated(a * 0.5 - 0.5) * 1.8
		f.path = []
		for q: Vector2 in SHORE_PATH:
			f.path.append(Vector3(q.x, Terrain.h(q.x, q.y), q.y))
		f.spot = Vector3(at.x, Terrain.h(at.x, at.y), at.y)
		f.at_stash = false
		if not said:
			said = true
			game.chat.ai_say(j, LINES_ARRIVE.pick_random())
	# Kätköllä huikat (tietokoneen hahmot, kun ehtivät perille).
	get_tree().create_timer(14.0).timeout.connect(func() -> void:
		for j in _brains:
			var f: Follow = _brains[j]
			if f.at_stash:
				f.body.drink(0.45)
				f.body.pose = "Idle_Talking")


## Kehote veneessä.
func prompt() -> String:
	if active:
		return "kätkölle %d m · Q keskeyttää" % roundi(Vector2(game.boat.global_position.x,
			game.boat.global_position.z).distance_to(STASH))
	return "Q: tutkimusmatka viinakätkölle"
