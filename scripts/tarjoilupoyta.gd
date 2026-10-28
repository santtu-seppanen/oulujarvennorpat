extends Node3D
## Tarjoilu teltan pöydällä (ei omaa pöytää): Markon ruoka tarjoillaan ulos: aamupalaksi klo 12 pyttipannua (lautaset, kokkaus.gd)
## ja klo 20 grillistä pihvit (grilli.gd). Q syö annoksen ulkona (pihvi ensin). Tietokoneen Marko tekee ruoat itse
## klo 12 ja klo 20; pelaaja-Marko paistaa ja grillaa ne. Kahvi tarjoillaan sisällä keittiön sivutasolta (kahvi.gd).
## Kahvista kiitellään Barista Saloselle ja ruoasta Michelin Markolle.

const B := preload("res://scripts/build.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Porukka := preload("res://scripts/porukka.gd")

const SPOT := Vector2(-4.9, 0.25)  # pihan kehyksessä (u, v): teltan pöydän keskikohta (mokki.gd _tent)
const REACH := 1.5
const BREAKFAST_LINE := "Aamupala on valmis! Pyttipannua tarjoilupöydällä."  # nauhoitetut (puhe.gd)
const STEAK_LINE := "Pihvit grillistä! Ruoka on pöydässä."
const PRAISE_COFFEE := ["Barista Salonen, tää on kahvia!", "Kiitos Barista Salonen – pannukahvi on parasta.", "Barista Salosen pannukahvi, ei voita mikään!",
	"Barista Salonen on taas tehnyt täydellisen pannullisen."]
const PRAISE_FOOD := ["Michelin Marko, tää on tähtiruokaa!", "Kiitos Michelin Marko – pyttipannu on huikeaa.", "Michelin Markon pyttipannu, kolme tähteä!",
	"Michelin Marko on taas ylittänyt itsensä."]
const PRAISE_STEAK := ["Michelin Marko, tää pihvi on täydellisen kypsä!", "Kiitos Michelin Marko – grillipihvi on huikea.",
	"Michelin Markon pihvit, kolme tähteä!", "Michelin Marko osaa grillata, vaikka kaikki muu menisi pieleen."]

var game: Node3D
var pos := Vector3.ZERO
var plates: Node3D  # pyttipannuannokset (kokkaus.gd täyttää)
var steaks: Node3D  # pihvit
var pihvit := 0
var _day12 := -1
var _day20 := -1


func _ready() -> void:
	var w := Mokki.yw(SPOT.x, SPOT.y)
	pos = Vector3(w.x, Mokki.DY, w.y)
	position = pos
	rotation.y = atan2(-Mokki.EAST.y, Mokki.EAST.x)  # paikallinen x = pihan u-akseli, z = v-akseli
	var top := 0.76 + 0.005  # teltan pöydän kansi
	plates = Node3D.new()
	plates.position = Vector3(0.3, top, 0.25)
	add_child(plates)
	steaks = Node3D.new()
	steaks.position = Vector3(-0.3, top, 0.25)
	add_child(steaks)
	game.mp.on("pihvi", func(d: Dictionary, _from: int) -> void: _set_steaks(int(d.n)))


func pos_xz() -> Vector2:
	return Vector2(pos.x, pos.z)


func near(p: Vector3) -> bool:
	return Vector2(p.x - pos.x, p.z - pos.z).length() < REACH and absf(p.y - pos.y) < 1.5


## Kehut: joku muista kiittää tarjoilijaa puhekuplalla (kahvista Barista Salonen, ruoasta Michelin Marko).
func praise(coffee: bool, steak := false) -> void:
	var who: Array = []
	for i in Porukka.CREW.size():
		if i != game.player_index and Porukka.CREW[i].name != ("Jukka" if coffee else "Marko"):
			who.append(i)
	if who.is_empty():
		return
	game.chat.ai_say(who.pick_random(), (PRAISE_COFFEE if coffee else (PRAISE_STEAK if steak else PRAISE_FOOD)).pick_random())


## Marko-hahmon indeksi ja ohjaako tietokone häntä (silloin ruoka tulee pöytään itsestään).
func _marko_ai() -> bool:
	for i in Porukka.CREW.size():
		if Porukka.CREW[i].name == "Marko":
			return game.crew_modes[i] == "ai"
	return false


func _marko_index() -> int:
	for i in Porukka.CREW.size():
		if Porukka.CREW[i].name == "Marko":
			return i
	return -1


func _process(_delta: float) -> void:
	if game.state != "play" or (game.mp.online() and not game.mp.net.is_host()) or not _marko_ai():
		return
	var lt: Dictionary = game.sun.local()
	var day: int = lt.day
	if lt.hour == 12 and _day12 != day:
		_day12 = day
		game.kokkaus.add(4)
		if not game.at_beach(): game.chat.ai_say(_marko_index(), BREAKFAST_LINE)
		if not game.at_beach(): game.toast("Marko on paistanut aamupalaksi pyttipannua: tarjoilupöydällä (Q syö).", 5.0)
	elif lt.hour == 20 and _day20 != day:
		_day20 = day
		add_steaks(4)
		if not game.at_beach(): game.chat.ai_say(_marko_index(), STEAK_LINE)
		if not game.at_beach(): game.toast("Marko grillasi pihvit grillikatoksessa: tarjoilupöydällä (Q syö).", 5.0)


## Pihvejä pöydälle (Markon grillaama tai tietokoneen Markon tekemä).
func add_steaks(n: int) -> void:
	_set_steaks(mini(8, pihvit + n))
	game.mp.send({"t": "pihvi", "n": pihvit})


func eat_steak() -> void:
	if pihvit <= 0:
		return
	_set_steaks(pihvit - 1)
	game.mp.send({"t": "pihvi", "n": pihvit})
	var p: CharacterBody3D = game.player
	p.stamina = 100.0
	p.exhausted = false
	game.toast("Söit Michelin Markon grillipihvin: täydellisen kypsä! Kunto täynnä.", 4.0)
	Sfx.play("pickup", -8.0)
	game.tarina.complete("pihvi")
	if randf() < 0.6:
		praise(false, true)


func _set_steaks(n: int) -> void:
	pihvit = n
	for ch in steaks.get_children():
		ch.queue_free()
	for k in n:
		var o := Vector3((k % 4) * 0.11 - 0.15, 0.0, (k / 4) * 0.12 - 0.06)
		B.mesh(steaks, B.cyl(0.05, 0.05, 0.006, 12), o, Color(0.96, 0.96, 0.94))  # lautanen
		var st := B.mesh(steaks, B.sphere(0.045, 8), o + Vector3(0, 0.012, 0), Color(0.42, 0.2, 0.12))
		st.scale = Vector3(1.3, 0.35, 1.0)
		B.mesh(steaks, B.boxm(Vector3(0.07, 0.003, 0.008)), o + Vector3(0, 0.03, 0.0), Color(0.15, 0.08, 0.05), Vector3(0, 30, 0))
