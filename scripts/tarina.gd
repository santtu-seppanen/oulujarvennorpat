extends Node
## Tarina: mökkiviikonloppu torstaista sunnuntaihin. Porukka on mökillä neljä päivää, ja joka päivä on omat
## tehtävänsä: sauna ja halot, uinti, huussi, pöydän pelit, rantatennis ja mustikat, tutkimusmatka veneellä, jalkapallon
## heittely, aurinkoon ja Happy Beachille autolla – ja joka päivä päikkärit ylämökissä klo 15–18 (Jukka ei nuku
## päikkäreitä vaan keittää kahvit). Tehtävät riippuvat hahmosta (Marko paistaa pyttipannua, Jukka keittää kahvit).
##
## Valikon oletusajankohta "Mökkiviikonloppu" (sun.gd STORY_PRESET) alkaa torstaina klo 18. Päivä vaihtuu
## keskiyöllä: edellisen päivän tulos ilmoitetaan ja uuden päivän tehtävät tulevat näkyviin. Sunnuntaina klo 21
## viikonloppu päättyy: lopputulos näytetään ja peli jatkuu vapaana. J piilottaa ja näyttää tehtävälistan.
##
## Suoritukset tunnistetaan kolmella tavalla: main.gd ilmoittaa tapahtumat (complete), minipelien päättyminen
## (activity_ended) ja pelin tila (poll), joten minipeleihin ei tarvitse koskea.

const Reitti := preload("res://scripts/reitti.gd")
const Porukka := preload("res://scripts/porukka.gd")
const Sun := preload("res://scripts/sun.gd")
const Happybeach := preload("res://scripts/happybeach.gd")

const DAY_NAMES := ["Sunnuntai", "Maanantai", "Tiistai", "Keskiviikko", "Torstai", "Perjantai", "Lauantai"]
const DAY_COUNT := 4
## Happy Beachin tehtävät: kun porukka on rannalla, mökin tehtävät ovat tauolla, ja päinvastoin.
const BEACH_TASKS := ["happy", "baari", "laulu", "tanssi"]
const RECORD_LOSS := 10  # mainepisteet, kun päivän ennätystavoite jää rikkomatta
const END_HOUR := 18  # viimeisenä päivänä viikonloppu päättyy tähän kellonaikaan

## Päivät: nimi, otsikko ja johdanto sekä montako tehtävää arvotaan poolista (picks).
const DAYS := [
	{"title": "Saapuminen", "picks": 5,
		"intro": "Porukka saapuu Äpättiin viikonlopuksi. Mökki herätetään henkiin: sauna, uinti ja ensimmäiset kylmät."},
	{"title": "Mökkiarkea", "picks": 5,
		"intro": "Perjantai: mökkiarkea. Kahvit ja pyttipannu, tehtäviä arvotaan pitkin päivää – ja keskiyöllä oodi."},
	{"title": "Retkipäivä", "picks": 2,
		"intro": "Lauantai: retkipäivä! Veneellä viinakätkölle ja illalla autolla Happy Beachille (baari on auki joka päivä klo 20–02)."},
	{"title": "Lähtöpäivä", "picks": 4,
		"intro": "Sunnuntai: viimeinen päivä. Päikkärit, saunan viimeiset löylyt ja halaukset – klo 18 lähdetään."},
]

## Joka päivä samat: ruoka ja kahvi, päikkärit, sekä Spartan pinkiponki ja amerikanpallo ennätystavoitteella.
## "not_day": päivät, jolloin tehtävää ei ole: torstaina tullaan mökille vasta klo 18, joten pyttipannu (klo 12–14) ja päikkärit
## (klo 15–18, alkavat vasta perjantaina) jäävät pois.
const COMMON := [
	{"id": "pytti", "text": "Paista aamupalaksi pyttipannu klo 12–14 (Markon erikoisuus)", "only": ["Marko"], "not_day": [0]},
	{"id": "grilli", "text": "Grillaa pihvit klo 20–22 grillikatoksessa (vain Marko grillaa)", "only": ["Marko"]},
	{"id": "aamupala", "text": "Syö Michelin Markon pyttipannua tarjoilupöydältä (Q, klo 12 jälkeen)", "except": ["Marko"], "not_day": [0]},
	{"id": "pihvi", "text": "Syö Michelin Markon grillipihvi tarjoilupöydältä (Q, klo 20 jälkeen)", "except": ["Marko"]},
	{"id": "kahvijuonti", "text": "Juo kuppi Barista Salosen pannukahvia keittiön sivutasolta (E)", "except": ["Jukka"]},
	{"id": "paikkarit", "text": "Päikkärit ylämökissä klo 15–18", "except": ["Jukka"], "not_day": [0]},
	{"id": "kahvi", "text": "Keitä pannukahvit alamökin liedellä (Jukka ei nuku päikkäreitä)", "only": ["Jukka"]},
	{"id": "tennis", "text": "", "record": "tennis"},
	{"id": "heittely", "text": "", "record": "heittely"},
]
## Ennätystavoitteet: aloitusennätys, ja joka päivä tehtävä on rikkoa se (uusi ennätys on seuraava tavoite).
const RECORD_START := {"tennis": 20, "heittely": 8}
const RECORD_NAME := {"tennis": "Spartan pinkiponki: lyöntiä ilmassa", "heittely": "Amerikanpalloa vedessä: heittoa putkeen"}
## Arvottava pooli: jokaiselle päivälle arvotaan picks kappaletta (eri päiville eri tehtäviä).
const POOL := [
	{"id": "halot", "text": "Lämmitä sauna: halot halkovajasta kiukaaseen"},
	{"id": "sauna", "text": "Saunomaan: yli 20 löylypistettä", "min": 20},
	{"id": "katko", "text": "Hae kylmä olut saunan takaa kätköltä"},
	{"id": "uinti", "text": "Pulahda järveen"},
	{"id": "huussi", "text": "Käy huussissa"},
	{"id": "poyta", "text": "Istu alamökin pöytään ja pelaa ristiseiskaa tai tuppea"},
	{"id": "mustikat", "text": "Syö mustikoita metsässä (suihku paranee)"},
	{"id": "rinne", "text": "Virtsaa rinteeseen pitkospuiden alusta"},
	{"id": "kaari", "text": "Komea virtsan kaari: yli 4 m rinteeseen (Marko yltää, muille mustikoista voimaa)"},
	{"id": "aurinko", "text": "Katso auringonlasku laiturilta tai etuterassilta"},
	{"id": "makkara", "text": "Paista täydellinen makkara nuotiolla (hiilloksella, ei liekissä)"},
	{"id": "muistelu", "text": "Nuotiolle kuuntelemaan ja kertomaan vähintään kolme \"Muistatko kun\" -tarinaa"},
	{"id": "trivia", "text": "Ysäritrivia keittiön pöydässä: vastaa oikein vähintään kolmeen kysymykseen"},
	{"id": "afrikka", "text": "Pelaa Afrikan tähteä keittiön pöydässä loppuun asti (vähintään kolme omaa vuoroa)"},
]
## Päiväkohtaiset kiinteät tehtävät (tarinan kulku): lauantain retki ja Happy Beach, sunnuntain kätkö.
const EXTRA := [
	[],
	[],
	[
		{"id": "retki", "text": "Tutkimusmatka: souda kumiveneellä viinakätkölle (veneessä Q)"},
		{"id": "katkohaku", "text": "Hae viinaa tutkimusmatkan kätköltä (E olut, Q viina) – avaa oman kätkön teon"},
		{"id": "uusikatko", "text": "Tee uusi viinakätkö lähimaastoon (E sopivassa paikassa, avautuu kätkön haun jälkeen)"},
		{"id": "happy", "text": "Aja autolla Happy Beachille (G: automaattiajo)"},
		{"id": "baari", "text": "Osta juoma Happy Beachin baarista (tiski sisällä tai terassilla)"},
		{"id": "laulu", "text": "Laula karaokea Happy Beachin lavalla (E baarin sisällä)"},
		{"id": "tanssi", "text": "Tanssi Happy Beachin tanssilattialla eurodancea vähintään 35 % (askeleet tahtiin A S W D)"},
		{"id": "takaisin", "text": "Aja takaisin mökille"},
	],
	[
		{"id": "uusikatko", "text": "Tee uusi viinakätkö lähimaastoon (jos et vielä tehnyt; avautuu tutkimusmatkan kätkön haun jälkeen)"},
		{"id": "halaus", "text": "Lähtöhalaus: koko porukka halaamaan ennen lähtöä (klo 17 jälkeen)"},
	],
]

var game: Node3D
var active := false
var day := 0
var finished := false
var done: Array = []  # päivä -> {tehtävän id: true}
var shown := true
var stash_unlocked := false  # oman kätkön teko avautuu, kun tutkimusmatkan kätköltä on haettu viinaa

var _start_no := 0
var _label: Label
var _end_layer: CanvasLayer
var _end_label: Label
var _end_t := 0.0
var _dirty := true
var _intro_day := -1
var _t_table := 0.0
var _t_swim := 0.0
var _t_sun := 0.0
var _prev_berries := 0
var _prev_pissa := false
var _prev_kupit := 0
var _prev_annokset := 0
var _hour_prev := -1


var lost := false  # maine nollassa: peli hävitty (loppu.gd)
var _was_beach := false
var plan: Array = []  # päivä -> tehtävälista (arvotaan begin():ssä)
var records: Dictionary = {}  # ennätystavoitteet (tennis, heittely)
var _best: Dictionary = {}


func _ready() -> void:
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.85))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.position = Vector2(20, 176)
	game._hud.add_child(_label)
	_end_layer = CanvasLayer.new()
	_end_layer.layer = 16
	_end_layer.visible = false
	add_child(_end_layer)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0.02, 0.03, 0.06, 0.78)
	_end_layer.add_child(dim)
	_end_label = Label.new()
	_end_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_end_label.add_theme_font_size_override("font_size", 26)
	_end_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_end_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_end_label.add_theme_constant_override("outline_size", 6)
	_end_layer.add_child(_end_label)
	game.sun.restarted.connect(func() -> void:
		game.kortit.reset_weekend()  # uusi viikonloppu: ristiseiskan pisteet alkavat nollasta
		begin())
	begin()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_J:
		if active and game.state == "play" and not get_tree().paused and game.activity == "":  # minipelissä J on pelin ohje
			shown = not shown
			_dirty = true


## Aloittaa tarinan alusta nykyisestä pelin hetkestä (jos valittu alkuhetki on tarina).
func begin() -> void:
	active = game.sun.story
	stash_unlocked = not game.omat_katkot.spots.is_empty()
	game.maine = 50
	finished = false
	lost = false
	day = 0
	_roll_plan()
	records = RECORD_START.duplicate()
	_best = {"tennis": 0, "heittely": 0}
	done = []
	for i in DAY_COUNT:
		done.append({})
	if game.muistelu != null:
		game.muistelu.reset()  # uusi viikonloppu: nuotion tunnelmat ja trivian voitot nollille
		game.lautapeli.reset()
		game.afrikka.reset()
		game.tyopuhelu.reset()
	_start_no = _day_no()
	_intro_day = -1
	_t_table = 0.0
	_t_swim = 0.0
	_t_sun = 0.0
	_dirty = true
	_end_layer.visible = false
	_end_t = 0.0


## Tutkimusmatkan kätköltä haettu viinaa: oman kätkön tekeminen avautuu.
func unlock_stash() -> void:
	if stash_unlocked:
		return
	stash_unlocked = true
	game.toast("Oman kätkön teko avautui! Etsi sopiva paikka lähimaastosta (metsä, kallio tai aukea) ja paina E.", 7.0)


func _day_no() -> int:
	var t: float = game.sun.t_utc
	return floori((t + Sun.utc_offset(t) * 3600.0) / 86400.0)


## Pelaajan hahmon nimi.
func _who() -> String:
	return Porukka.CREW[game.player_index].name


## Päivän tehtävät pelaajan hahmolle.
func tasks_for(d: int) -> Array:
	if plan.is_empty():
		_roll_plan()
	var out: Array = []
	var who := _who()
	for t: Dictionary in plan[d]:
		if t.has("only") and not who in t.only:
			continue
		if t.has("except") and who in t["except"]:
			continue
		if t.has("not_day") and d in t["not_day"]:
			continue
		var tt: Dictionary = t.duplicate()
		if t.has("record"):
			tt.text = "%s – rikota ennätys (nyt %d)" % [RECORD_NAME[t.record], int(records.get(t.record, RECORD_START[t.record]))]
		out.append(tt)
	return out


## Arpoo päivien tehtävät: kiinteät, päiväkohtaiset ja poolista picks kappaletta (sauna on viimeisenä päivänä 30 pisteen).
func _roll_plan() -> void:
	plan = []
	for d in DAY_COUNT:
		var tasks: Array = COMMON.duplicate()
		tasks.append_array(EXTRA[d])
		var pool: Array = POOL.duplicate()
		pool.shuffle()
		for k in mini(int(DAYS[d].picks), pool.size()):
			var t: Dictionary = (pool[k] as Dictionary).duplicate()
			if t.id == "sauna" and d == DAY_COUNT - 1:
				t.min = 30
				t.text = "Viimeiset löylyt: yli 30 löylypistettä"
			tasks.append(t)
		plan.append(tasks)


func _find(id: String) -> Dictionary:
	for t: Dictionary in tasks_for(day):
		if t.id == id:
			return t
	return {}


func is_done(id: String, d := -1) -> bool:
	var k := day if d < 0 else d
	return k >= 0 and k < done.size() and done[k].has(id)


func count_done(d: int) -> int:
	var n := 0
	for t: Dictionary in tasks_for(d):
		if done[d].has(t.id):
			n += 1
	return n


## Tehtävä suoritettu (main.gd ja minipelien seuranta): vain nykyisen päivän tehtävät lasketaan.
func complete(id: String) -> void:
	if not active or finished or game.state != "play":
		return
	var t := _find(id)
	if t.is_empty() or done[day].has(id) or _paused(id):
		return
	done[day][id] = true
	_dirty = true
	var n := count_done(day)
	var total := tasks_for(day).size()
	game.toast("Tehtävä suoritettu: %s (%d/%d)" % [t.text, n, total], 4.0)
	Sfx.play("win_small", -8.0)
	if n == total:
		game.toast("Päivän kaikki tehtävät tehty! Hyvää työtä, %s." % _who(), 6.0)


## Pelaaja on Happy Beachin leirintäalueella tai baarissa.
func at_beach() -> bool:
	var p: Vector3 = game.player.global_position
	return game.world.happy.in_pocket(p) or Happybeach.in_camp(p)


## Tehtävä on tauolla, kun ollaan toisessa paikassa: rannalla vain rannan tehtävät, mökillä vain mökin.
func _paused(id: String) -> bool:
	return (id in BEACH_TASKS) != at_beach() and id != "happy" and id != "takaisin"


## Alamökin minipeli päättyi (main.end_activity): sauna, pyttipannu, kahvi ja korttipöytä.
func activity_ended(a: String) -> void:
	match a:
		"sauna":
			var need := 20.0
			var t := _find("sauna")
			if not t.is_empty():
				need = float(t.get("min", 20.0))
			if game.sauna.points >= need:
				complete("sauna")
		"kokkaus":
			var h: int = game.sun.local().hour
			if game.kokkaus._made > 0 and h >= 12 and h < 14:
				complete("pytti")
		"kahvi":
			if game.kahvi._made > 0:
				complete("kahvi")


func _process(delta: float) -> void:
	if _end_t > 0.0:
		_end_t -= delta
		if _end_t <= 0.0:
			_end_layer.visible = false
	if not active or game.state != "play":
		_label.visible = false
		return
	if game.maine <= 0 and not finished and not lost:
		lost = true
		finished = true
		game.loppu.start_loss()
	if not finished:
		_advance_day()
		_poll(delta)
	var here := at_beach()
	if here != _was_beach:
		_was_beach = here
		_dirty = true
		game.toast("Porukka on %s: %s tehtävät ovat tauolla." % ["Happy Beachillä" if here else "mökillä", "mökin" if here else "Happy Beachin"], 4.0)
	if _dirty:
		_dirty = false
		_refresh()
	_label.visible = shown or finished


## Päivän vaihtuminen keskiyöllä ja viikonlopun loppu.
func _advance_day() -> void:
	var idx := _day_no() - _start_no
	var lt: Dictionary = game.sun.local()
	if idx >= DAY_COUNT or (idx == DAY_COUNT - 1 and lt.hour >= END_HOUR):
		_finish()
		return
	if idx > day:
		_day_summary(day)
		game.muistelu.day_ended(day)
		day = idx
		_dirty = true
	if _intro_day != day:
		_intro_day = day
		var weekday: String = DAY_NAMES[lt.weekday]
		game.toast("%s – %s. %s" % [weekday, DAYS[day].title, DAYS[day].intro], 9.0)


## Ennätystavoite (Spartan pinkiponki, amerikanpallo) jäi rikkomatta: 10 mainepistettä per tavoite.
func _record_penalties(d: int) -> void:
	for t: Dictionary in tasks_for(d):
		if t.has("record") and not done[d].has(t.id):
			game.lose_maine(RECORD_LOSS, "Ennätystavoite jäi rikkomatta (%s)" % RECORD_NAME[t.record].split(" (")[0].split(":")[0])


func _day_summary(d: int) -> void:
	_record_penalties(d)
	var n := count_done(d)
	var total := tasks_for(d).size()
	var t := "%s päättyi: %d/%d tehtävää." % [DAYS[d].title, n, total]
	if n == total:
		t += " Täydellinen päivä!"
	elif n * 2 < total:
		t += " Paljon jäi tekemättä – huomenna uusi yritys."
	game.toast(t, 6.0)


func _finish() -> void:
	finished = true
	if not lost and day == DAY_COUNT - 1:
		_record_penalties(day)
	var n := 0
	var total := 0
	for d in DAY_COUNT:
		n += count_done(d)
		total += tasks_for(d).size()
	var ratio := float(n) / maxf(1.0, float(total))
	var title := "Mökkimestari!" if ratio >= 0.9 else ("Hyvä viikonloppu." if ratio >= 0.6 else "Vähän jäi tekemättä – ensi kerralla.")
	var lines: Array[String] = ["VIIKONLOPPU PÄÄTTYI", "", "Torstaista sunnuntaihin Äpätissä.", "%s: %d/%d tehtävää tehty."
		% [_who(), n, total], title, ""]
	lines.append("Maine: %d/100" % game.maine)
	var leaders: Array = game.kortit.leaders()
	if not leaders.is_empty():
		var names := ", ".join(leaders.map(func(p: int) -> String: return Porukka.CREW[p].name))
		var pts := ", ".join(range(4).map(func(p: int) -> String:
			return "%s %d" % [Porukka.CREW[p].name, game.kortit.logic.totals[p]]))
		lines.append("Ristiseiskan voittaja: %s (vähiten pisteitä)" % names)
		lines.append("Pisteet: " + pts)
		lines.append("")
	lines.append_array(game.muistelu.ending_lines())
	lines.append_array(game.lautapeli.ending_lines())
	lines.append_array(game.afrikka.ending_lines())
	lines.append_array(game.tyopuhelu.ending_lines())
	if not game.muistelu.ending_lines().is_empty() or not game.lautapeli.ending_lines().is_empty() \
			or not game.afrikka.ending_lines().is_empty() or not game.tyopuhelu.ending_lines().is_empty():
		lines.append("")
	lines.append("Kamat autoon, mutta peli jatkuu vapaana.")
	_end_label.text = "\n".join(lines)
	lines.pop_front()
	game.loppu.start_win("VIIKONLOPPU PÄÄTTYI\n" + "\n".join(lines).strip_edges())
	Sfx.play("win", -6.0)
	_dirty = true


## Pelin tilasta tunnistettavat suoritukset.
func _poll(delta: float) -> void:
	var p: Vector3 = game.player.global_position
	var pi: int = game.player_index
	# Uinti: kuusi sekuntia uimassa.
	if game.player.swimming:
		_t_swim += delta
		if _t_swim > 6.0:
			complete("uinti")
	# Pöytä: istutaan pelaamaan.
	if game.activity == "kortit":
		_t_table += delta
		if _t_table > 40.0:
			complete("poyta")
	else:
		_t_table = 0.0
	# Mustikat ja rinteeseen virtsaaminen.
	var berries: int = game.mustikat.eaten.get(pi, 0)
	if berries > _prev_berries:
		complete("mustikat")
	_prev_berries = berries
	if game.pissa.active and not _prev_pissa:
		complete("rinne")
	_prev_pissa = game.pissa.active
	# Rantatennis ja heittely: ennätystavoite (rikotaan joka päivä; uusi ennätys on seuraava tavoite).
	for id: String in ["tennis", "heittely"]:
		var g: Node3D = game.tennis if id == "tennis" else game.heittely
		if g.active:
			_best[id] = maxi(int(_best.get(id, 0)), int(g.hits))
			if int(g.hits) > int(records.get(id, 0)) and not _find(id).is_empty():
				complete(id)
		elif int(_best.get(id, 0)) > int(records.get(id, 0)):
			records[id] = _best[id]
			_best[id] = 0
			_dirty = true
			game.toast("Uusi ennätys: %s %d!" % [RECORD_NAME[id].split(":")[0], int(records[id])], 4.0)
		else:
			_best[id] = 0
	# Tutkimusmatka: perillä kätkön rannassa.
	if game.retki.active and game.retki.state in ["perilla", "paluu"]:
		complete("retki")
	# Auringonlasku laiturilta tai etuterassilta.
	if game.sun.altitude < 5.0 and game.sun.altitude > -3.0:
		for v: Vector3 in game.world.mokki.views:
			if Vector2(p.x - v.x, p.z - v.z).length() < 6.0:
				_t_sun += delta
				break
		if _t_sun > 6.0:
			complete("aurinko")
	# Happy Beach: perillä leirintäalueella, ja takaisin mökille.
	var pp := Vector2(p.x, p.z)
	if pp.distance_to(Reitti.K) < 30.0:
		complete("happy")
	if is_done("happy") and pp.distance_to(Reitti.HOME_SPOT) < 45.0:
		complete("takaisin")


func _refresh() -> void:
	if finished:
		_label.text = "Viikonloppu päättyi (J: piilota)"
		return
	if not shown:
		_label.text = "J: tehtävät"
		return
	var lt: Dictionary = game.sun.local()
	var tasks := tasks_for(day)
	var lines: Array[String] = ["%s · %s (%d/%d)" % [DAY_NAMES[lt.weekday].to_upper(), DAYS[day].title, count_done(day), tasks.size()]]
	for t: Dictionary in tasks:
		var mark := "[x] " if done[day].has(t.id) else ("[~] " if _paused(t.id) else "[ ] ")
		lines.append(mark + t.text + (" (tauolla)" if mark == "[~] " else ""))
	lines.append("Maine: %d/100" % game.maine)
	if game.muistelu.mood_line() != "":
		lines.append(game.muistelu.mood_line())
	lines.append("J: piilota")
	_label.text = "\n".join(lines)
