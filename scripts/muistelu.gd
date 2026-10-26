extends Node
## "Muistatko kun" -muistelu nuotiolla (nuotio.gd): porukka istuu hirsille ja kertoo vuorotellen ysärimuistoja.
## Illassa on SESSION tarinaa: kolme kertoo joku muu ja pelaaja valitsee, miten reagoi, neljännen kertoo pelaaja itse
## ja valitsee kerrontatavan. Jokainen valinta muuttaa illan tunnelmaa (-2..+2). Päivän tunnelma vaikuttaa seuraavaan
## aamuun (day_ended: mainepisteet) ja pelin loppuun (ending_lines, win_line). Jokaisen illan vaikutus on rajattu,
## joten saman illan toistaminen ei kasvata sitä.

const Ui := preload("res://scripts/ui.gd")
const Chat := preload("res://scripts/chat.gd")

const SESSION := 4
## Reagoidaan toisen kertomaan: [kertojan repliikki (enintään 120 merkkiä), [[valinta, tunnelma, vastaus], ...]].
const STORIES := [
	{"id": "kasetti", "text": "Muistatko kun radiosta nauhoitettiin biisejä kasetille ja juontaja puhui aina päälle?", "opts": [
		["Kynällä kelattiin takaisin!", 2, "Kynä oli kasetin paras ystävä!"],
		["Nykyään kaikki löytyy Spotifysta.", -1, "Joo, mutta siinä ei ole sitä fiilistä."],
		["Mulla meni nauha aina solmuun.", 1, "Mulla kolmesti samana kesänä!"]]},
	{"id": "snake", "text": "Muistatko kun Snake oli bussimatkan paras viihde ja ennätystä piti kehua kaikille?", "opts": [
		["Mun ennätys oli 312!", 2, "Valehtelet, mutta uskotaan."],
		["Yhdellä peukalolla ja näppäinlukko päällä.", 1, "Se oli taitolaji."],
		["Turhaa ajan hukkaa koko juttu.", -2, "No kiitos vaan, nuotion tunnelma-ammattilainen."]]},
	{"id": "pelihalli", "text": "Muistatko kun pelihallissa markat riitti kolmeen peliin ja viimeiseen elämään tuli kiire?", "opts": [
		["Viimeinen kolikko meni aina samaan peliin.", 1, "Ja aina hävisit sen."],
		["Mä sain sitten tuhat pistettä enemmän kuin sä.", -1, "Joo joo, kaikki muistaa vähän eri tavalla."],
		["Ostetaan ne pelit uudestaan!", 2, "Eläköön retro!"]]},
	{"id": "mopo", "text": "Muistatko kun mopolla ajettiin kylälle ja bensa loppui puolimatkassa, ja kaikki työnsi?", "opts": [
		["Ja mä työnsin vielä vastamäkeä.", 2, "Sankari. Oikea sankari."],
		["Olisi pitänyt tankata ajoissa.", -1, "Niinpä. Kiitos neuvosta, isä."],
		["Mä jäin vahtimaan kamoja.", 0, "Tietysti jäit."]]},
	{"id": "ripari", "text": "Muistatko kun rippileirillä kukaan ei nukkunut kolmeen yöhön?", "opts": [
		["Aamulla jaksettiin silti laulaa.", 1, "Jotkut jaksoivat paremmin kuin toiset."],
		["Mä nukuin kyllä koko ajan.", -1, "Siksi sä olitkin ainoa pirteä."],
		["Yöllä käytiin ottamassa tikkarit kirkon takaa!", 2, "Se oli laillista, melkein!"]]},
	{"id": "intti", "text": "Muistatko kun armeijassa kaikki hiukset lähti ensimmäisenä päivänä?", "opts": [
		["Hius ei ollut ikävä, sukat kyllä.", 1, "Ja kotiruoka!"],
		["Kersantti huusi ja mä nauroin ääneen.", -1, "Ja sait lenkin lisää."],
		["Se oli parasta aikaa!", 2, "Kyllä, sieltä sai kavereita elinikäisiksi."]]},
	{"id": "tamagotchi", "text": "Muistatko kun yksi kaveri hoiti Tamagotchia tunnilla ja se kuoli silti?", "opts": [
		["Hautajaiset pidettiin pihalla.", 2, "Muistopuheen piti rehtori."],
		["Kallis lelu, kun ei kestänyt tuntiakaan.", -1, "Eipä ollut sulla parempaa."],
		["Mun elikko eli kolme viikkoa.", 1, "Pitkä ikä. Kunnioitus."]]},
	{"id": "tv", "text": "Muistatko kun lauantai-iltana kaikki katsoi samaa ohjelmaa ja maanantaina siitä puhuttiin?", "opts": [
		["Silloin oli yhteinen tv-maailma.", 2, "Ihan totta. Nykyään jokaisella on omansa."],
		["Netissä on nykyään enemmän valinnanvaraa.", -1, "Niin on, mutta ei meillä silloin ollut."],
		["Mä nauhoitin sen videolle.", 1, "Ja nauha alkoi aina myöhässä."]]},
	{"id": "kioski", "text": "Muistatko kun jäätelökioskilta ostettiin mehujäätä markalla ja kioski oli auki koko kesän?", "opts": [
		["Vadelma oli paras maku.", 1, "Ei, kola oli parempi!"],
		["Mulla oli tapana ottaa aina kaksi.", 1, "Toinen sulaa ranteelle."],
		["Se kioski pitäisi avata uudestaan!", 2, "Joo, mä tulen töihin."]]},
	{"id": "sahko", "text": "Muistatko kun mökillä ei ollut sähköä ja Aku Ankkaa luettiin taskulampulla?", "opts": [
		["Ja paristo loppui parhaassa kohdassa.", 2, "Aina! Ja sitten kuunneltiin hiljaa sadetta."],
		["Sähköt vois vetää tännekin.", -1, "Joo, ja poistaa samalla tunnelma."],
		["Mä pelkäsin pimeää.", 0, "Ei se mitään, ei kerrota kellekään."]]},
	{"id": "bussi", "text": "Muistatko kun koulubussi ajoi ohi ja jouduttiin pyöräilemään pakkasessa kouluun?", "opts": [
		["Mä pakotin sut vielä ottamaan lyhyemmän reitin.", 1, "Ja se oli pidempi."],
		["Se oli sun syytä, kun nukuit pommiin.", -2, "No tässä kiitos, sama sulle."],
		["Hyvä kuntoilu, kyllä se kannatti.", 1, "Niin, ihan vapaaehtoisesti kyllä."]]},
	{"id": "disco", "text": "Muistatko kun nuorisotalon discossa kukaan ei uskaltanut pyytää ketään tanssimaan?", "opts": [
		["Mä uskalsin vasta viimeisen biisin aikaan.", 2, "Ja se oli hidas!"],
		["Tanssittiin porukalla ringissä.", 1, "Se oli turvallisin taktiikka."],
		["Mä olin siellä vain tarjoilemassa limsaa.", 0, "Ja se maistui tuolloin parhaalta."]]},
]
## Pelaaja kertoo itse: [kertomuksen aihe, [[kerrontatapa, tunnelma, muiden vastaus], ...]].
const OWN := [
	{"id": "bandi", "text": "Muistatko kun yritettiin perustaa bändi, eikä kellään ollut rumpuja?", "opts": [
		["Liioittele: kuuluisuus oli ihan nurkan takana.", 2, "Ja se keikka kuudelle serkulle!"],
		["Kerro totuus sellaisena kuin se oli.", 1, "Ihan ok, pidetään tämä."],
		["Kerro, kuka oli huonoin soittaja.", -2, "Hei, ei noin! Tää on ystävien nuotio."]]},
	{"id": "uinti", "text": "Muistatko kun uitiin pimeässä ja huudettiin kaikki yhtä aikaa?", "opts": [
		["Kerro, kuinka kylmää vesi oli.", 2, "Kylmää oli! Ihan viimeinen huuto."],
		["Kerro, kuka pelkäsi eniten.", -1, "Ei kannata kertoa nimiä."],
		["Kerro lyhyesti.", 0, "No, oli se pidempi."]]},
	{"id": "kiuas", "text": "Muistatko kun ensimmäisellä mökkireissulla kiuas ei syttynyt?", "opts": [
		["Liioittele: savu täytti koko saunan.", 2, "Ja naapuri tuli kysymään, palaako."],
		["Syytä toisia sytytyksestä.", -2, "Ei se ihan niin mennyt!"],
		["Kerro, mitä opittiin.", 1, "Pelti auki. Aina pelti auki."]]},
	{"id": "lattia", "text": "Muistatko kun yksi mökkireissu meni niin, että kaikki nukkui lattialla?", "opts": [
		["Kerro, kuka kuorsasi kovaäänisimmin.", -1, "Hei! Mä en kuorsaa."],
		["Kerro, kuinka hauskaa oli aamulla.", 2, "Aamupala oli ikimuistoinen."],
		["Kerro, että sänky oli silti parempi.", 0, "Niin oli, mutta tunnelma ei."]]},
]

var game: Node3D
var evening := {}  # päivä -> illan tunnelma yhteensä
var told := {}  # päivä -> kerrotut tarinat
var mood_morning := 0  # edellisen illan vaikutus aamuun: -1 | 0 | 1 | 2
var best_story := ""  # tunnetuin tarina (suurin yksittäinen tunnelma)
var _best_val := -9
var _used: Array = []
var _phase := ""  # "" | "intro" | "choose" | "reply" | "done"
var _count := 0
var _sum := 0
var _cur: Dictionary = {}
var _order: Array = []  # valintojen järjestys (sekoitettu)
var _sel := 0
var _teller := -1
var _ui: CanvasLayer
var _head: Label
var _text: Label
var _btns: Array = []
var _info: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "bottom", 640)
	Ui.label(box, "NUOTIO · MUISTATKO KUN", 20, Ui.YELLOW)
	_head = Ui.label(box, "", 16, Color(1.0, 0.85, 0.5))
	_text = Ui.label(box, "", 20)
	for k in 3:
		var b := Ui.button(box, "", func() -> void: choose(k))
		b.custom_minimum_size = Vector2(600, 38)
		_btns.append(b)
	_info = Ui.label(box, "", 16)


## Uusi viikonloppu: tunnelmat nollille.
func reset() -> void:
	evening = {}
	told = {}
	mood_morning = 0
	best_story = ""
	_best_val = -9
	_used = []


func _day() -> int:
	return game.tarina.day


func start() -> bool:
	game.nuotio.sit_player()
	CamCtl.free_mouse = true
	_ui.visible = true
	_count = 0
	_sum = 0
	_phase = "intro"
	_refresh()
	return true


func stop(_why := "") -> void:
	_ui.visible = false
	CamCtl.free_mouse = false
	_phase = ""
	game.nuotio.stand_player()


func prompt() -> String:
	match _phase:
		"choose":
			return "1/2/3 tai A/D + E: valitse · W: poistu nuotiolta"
		"done":
			return "E: poistu nuotiolta"
		_:
			return "E: jatka · W: poistu nuotiolta"


func act() -> void:
	match _phase:
		"intro", "reply":
			_next()
		"choose":
			choose(_sel)
		"done":
			game.end_activity()
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if _phase != "choose" or Chat.typing or not _ui.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode - KEY_1
		if k >= 0 and k < 3:
			choose(k)
			return
	if event.is_action_pressed("left"):
		_sel = (_sel + 2) % 3
		_refresh()
	elif event.is_action_pressed("right"):
		_sel = (_sel + 1) % 3
		_refresh()


## Seuraava tarina (tai illan päätös).
func _next() -> void:
	if _count >= SESSION:
		_finish()
		return
	var own := _count == SESSION - 1
	var pool: Array = OWN if own else STORIES
	var fresh: Array = pool.filter(func(s: Dictionary) -> bool: return not _used.has(s.id))
	if fresh.is_empty():
		_used = _used.filter(func(id: String) -> bool: return not pool.any(func(s: Dictionary) -> bool: return s.id == id))
		fresh = pool
	_cur = fresh[_rng.randi() % fresh.size()]
	_used.append(_cur.id)
	_order = [0, 1, 2]
	_order.shuffle()
	_sel = 0
	var others: Array = game.nuotio.others()
	_teller = -1 if own else others[_count % others.size()]
	if _teller >= 0:
		game.chat.ai_say(_teller, _cur.text)
	_phase = "choose"


func choose(k: int) -> void:
	if _phase != "choose" or k < 0 or k >= 3:
		return
	var opt: Array = _cur.opts[_order[k]]
	var d: int = opt[1]
	_sum += d
	_count += 1
	var day := _day()
	evening[day] = int(evening.get(day, 0)) + d
	told[day] = int(told.get(day, 0)) + 1
	if d > _best_val:
		_best_val = d
		best_story = _cur.text.replace("Muistatko kun ", "").trim_suffix("?")
	var talkers: Array = game.nuotio.others()
	var replier: int = _teller if _teller >= 0 else talkers[_rng.randi() % talkers.size()]
	game.chat.ai_say(replier, opt[2])
	Sfx.play("win_small" if d > 0 else ("lose" if d < 0 else "pickup"), -10.0)
	if int(told[day]) >= 3:
		game.tarina.complete("muistelu")
	_phase = "reply"
	_info.text = "%s (%s)" % [opt[2], _mood_word(d)]


func _finish() -> void:
	_phase = "done"


static func _mood_word(d: int) -> String:
	if d >= 2:
		return "nauru raikuu, tunnelma +2"
	if d == 1:
		return "hyvä fiilis, tunnelma +1"
	if d == 0:
		return "ei sen suurempaa vaikutusta"
	return "hiljaista hetken, tunnelma %d" % d


static func evening_word(m: int) -> String:
	if m >= 5:
		return "upea"
	if m >= 2:
		return "hyvä"
	if m <= -3:
		return "kiusallinen"
	return "tavallinen"


func _refresh() -> void:
	_head.text = ""
	for b: Button in _btns:
		b.visible = false
	match _phase:
		"intro":
			_text.text = "Nuotio rätisee ja porukka kerääntyy hirsille. Illan tarinoita on %d." % SESSION
			_info.text = "E aloittaa. Valinnat vaikuttavat illan tunnelmaan, ja tunnelma seuraavaan päivään."
		"choose":
			var own := _teller < 0
			_head.text = "Sinun vuorosi kertoa" if own else "%s kertoo" % game.Porukka.CREW[_teller].name
			_text.text = _cur.text
			for k in 3:
				var b: Button = _btns[k]
				b.visible = true
				b.text = "%s%d. %s" % ["> " if k == _sel else "   ", k + 1, _cur.opts[_order[k]][0]]
			_info.text = "Tarina %d/%d" % [_count + 1, SESSION]
		"reply":
			_text.text = _cur.text
			_head.text = "Tarina %d/%d" % [_count, SESSION]
		"done":
			_text.text = "Iltatunnelma nuotiolla: %s (%+d)." % [evening_word(_sum), _sum]
			_info.text = "Illan tunnelma vaikuttaa huomiseen aamuun."


## Päivä d päättyi: illan tunnelma vaikuttaa aamuun (mainepisteet, kerran päivässä).
func day_ended(d: int) -> void:
	mood_morning = 0
	if int(told.get(d, 0)) == 0:
		return
	var m: int = evening.get(d, 0)
	if m >= 5:
		mood_morning = 2
		game.maine = mini(100, game.maine + 4)
		game.toast("Eilisen nuotiotarinat naurattavat vieläkin: upea tunnelma (maine +4, nyt %d/100)" % game.maine, 6.0)
	elif m >= 2:
		mood_morning = 1
		game.maine = mini(100, game.maine + 2)
		game.toast("Eilisen nuotioilta jäi hyvä fiilis (maine +2, nyt %d/100)" % game.maine, 5.0)
	elif m <= -3:
		mood_morning = -1
		game.lose_maine(3, "Eilisen nuotiolla jäi kiusallinen tunnelma")
	game.tarina._dirty = true


## Tarinatehtävälistan rivi: aamun tunnelma (tyhjä, jos ei nuotioiltaa).
func mood_line() -> String:
	match mood_morning:
		2:
			return "Tunnelma: upea (eilisen nuotiotarinat)"
		1:
			return "Tunnelma: hyvä (eilinen nuotioilta)"
		-1:
			return "Tunnelma: nuokkuva (eilisen nuotion hiljaisuus)"
	return ""


func total() -> int:
	var t := 0
	for d in evening:
		t += int(evening[d])
	return t


func tales() -> int:
	var t := 0
	for d in told:
		t += int(told[d])
	return t


## Lopputuloksen rivit: nuotiotarinat ja tunnelma (tyhjä, jos nuotiolla ei kerrottu mitään).
func ending_lines() -> Array[String]:
	var out: Array[String] = []
	if tales() == 0:
		return out
	var t := total()
	out.append("Nuotiotarinoita kerrottu: %d · tunnelma %+d" % [tales(), t])
	if t >= 8 and best_story != "":
		out.append("Tunnetuin tarina: \"Muistatko kun %s\"" % best_story)
	elif t <= -3:
		out.append("Nuotiolla oli välillä aika hiljaista.")
	return out


## Poislähtöpuhe pelin lopussa nuotion tunnelman mukaan (tyhjä = ei muutosta).
func win_line() -> String:
	var t := total()
	if tales() == 0:
		return ""
	if t >= 8 and best_story != "":
		return "Muistatko kun %s" % best_story.left(80)
	if t <= -3:
		return "Ensi kerralla nuotiolla vähän vähemmän piikittelyä."
	return "Nuotiolla oli kivaa."
