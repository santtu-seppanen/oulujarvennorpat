extends Node
## Lautapeli alamökin keittiön pöydässä: ysäritrivia, Trivial Pursuit -tyyliin. Kuusi aihepiiriä, kaikilla 90-luvun
## (ja mökkielämän) kysymyksiä. Vuorossa oleva saa kysymyksen aihepiiristä, josta hänellä ei vielä ole kiilaa:
## oikea vastaus antaa kiilan ja pitää vuoron, väärä siirtää vuoron seuraavalle. Ensimmäinen, jolla on WIN kiilaa,
## voittaa. Pelaaja vastaa kirjoittamalla vastauksen chattiin (Enter, ks. chat.gd), E ohittaa kysymyksen; muiden
## mökkiläisten puolesta vastaa tietokone (hahmon taidon mukaan) ja hahmot tulevat pöytään. Pelaaja istuu
## pöytään Q:lla (kortit ovat E).

const Ui := preload("res://scripts/ui.gd")
const Chat := preload("res://scripts/chat.gd")

const WIN := 4
const ASK_T := 45.0  # pelaajan vastausaika
const RESULT_T := 2.6
const CATS := ["Urheilu", "Musiikki", "Elokuvat ja tv", "Tekniikka ja pelit", "Suomi ja maantieto", "Mökkielämä"]
const CAT_COLORS := [Color(0.35, 0.75, 0.35), Color(0.9, 0.55, 0.15), Color(0.85, 0.35, 0.65), Color(0.4, 0.6, 0.95),
	Color(0.35, 0.8, 0.85), Color(0.95, 0.85, 0.3)]
## Tietokoneen oikean vastauksen todennäköisyys hahmoittain.
const SKILL := {"Santtu": 0.5, "Marko": 0.55, "Jaakko": 0.5, "Jukka": 0.6}
## [aihepiiri, kysymys, hyväksytyt vastaukset].
const QUESTIONS := [
	[0, "Mikä maa voitti jalkapallon MM-kisat 1998?", ["ranska"]],
	[0, "Kuka suomalainen voitti Formula 1 -maailmanmestaruuden 1998?", ["mika häkkinen", "häkkinen", "hakkinen"]],
	[0, "Missä kaupungissa pidettiin kesäolympialaiset 1996?", ["atlanta"]],
	[0, "Missä maassa pelattiin jääkiekon MM-kisat 1995, joissa Suomi voitti ensimmäisen kultansa?", ["ruotsi", "ruotsissa"]],
	[0, "Minkä seuran paidassa Jari Litmanen voitti Mestarien liigan 1995?", ["ajax"]],
	[0, "Minkä moottorin valmistaja oli Häkkisen McLarenissa 1998?", ["mercedes"]],
	[1, "Mikä yhtye julkaisi 1995 albumin (What's the Story) Morning Glory?", ["oasis"]],
	[1, "Minkä yhtyeen laulaja on Ville Valo?", ["him"]],
	[1, "Mikä tyttöbändi lauloi Wannaben 1996?", ["spice girls", "spicegirls"]],
	[1, "Minkä yhtyeen keulahahmo Kurt Cobain oli?", ["nirvana"]],
	[1, "Missä kaupungissa Euroviisut pidettiin 1997?", ["dublin"]],
	[1, "Kuka lauloi vuonna 1998 kappaleen ...Baby One More Time?", ["britney spears", "britney", "spears"]],
	[2, "Kuka ohjasi Titanicin (1997)?", ["james cameron", "cameron"]],
	[2, "Kuka ohjasi Jurassic Parkin (1993)?", ["steven spielberg", "spielberg"]],
	[2, "Kuka näytteli Forrest Gumpia (1994)?", ["tom hanks", "hanks"]],
	[2, "Minkä niminen Disneyn animaatio kertoo leijonasta nimeltä Simba (1994)?", ["leijonakuningas", "lion king", "the lion king"]],
	[2, "Kuka ohjasi Pulp Fictionin (1994)?", ["quentin tarantino", "tarantino"]],
	[2, "Kuka näytteli Terminaattoria elokuvassa Terminator 2 (1991)?", ["arnold schwarzenegger", "schwarzenegger", "arnold"]],
	[3, "Minkä valmistajan kännykässä Snake oli?", ["nokia"]],
	[3, "Minkä Nintendon kämmenpelikonsolin mukana tuli Tetris 1989?", ["game boy", "gameboy"]],
	[3, "Missä maassa Sega on kotoisin?", ["japani", "japanissa"]],
	[3, "Minkä värinen siili Sonic on?", ["sininen"]],
	[3, "Mikä Windows julkaistiin 1998 Windows 95:n jälkeen?", ["windows 98", "98"]],
	[3, "Kuka suomalainen aloitti Linuxin kehityksen 1991?", ["linus torvalds", "torvalds", "linus"]],
	[3, "Minkä nimisen konsolin Sony julkaisi Japanissa 1994?", ["playstation", "play station", "ps1"]],
	[4, "Minä vuonna Suomi liittyi Euroopan unioniin?", ["1995"]],
	[4, "Mikä oli Suomen rahayksikkö ennen euroa?", ["markka", "mk"]],
	[4, "Kuka oli Suomen presidentti 1994-2000?", ["martti ahtisaari", "ahtisaari"]],
	[4, "Missä kunnassa Äpätti sijaitsee Oulujärven rannalla?", ["vaala", "vaalassa"]],
	[4, "Mikä joki laskee Oulujärvestä mereen?", ["oulujoki"]],
	[4, "Mikä on Suomen korkein tunturi?", ["halti"]],
	[5, "Minä vuonna Nokia 3310 julkaistiin?", ["2000"]],
	[5, "Montako pelaajaa on jääkiekkojoukkueella kentällä maalivahti mukaan lukien?", ["6", "kuusi"]],
	[5, "Mikä on suomalaisilla mökkijärvillä yleinen raidallinen ja punaevinen kala?", ["ahven"]],
	[5, "Kummalla lauteilla on kuumempaa: ala- vai ylälauteilla?", ["ylälauteilla", "ylälauteet", "ylä", "yla", "ylalauteilla"]],
	[5, "Montako korttia kukin saa ristiseiskassa, kun pelaajia on neljä?", ["13", "kolmetoista"]],
	[5, "Mitä korttia ristiseiskassa aloitetaan?", ["ristiseiska", "risti seiska", "risti 7", "ristiseiskalla"]],
	[5, "Mikä on pyttipannun pääraaka-aine perunan lisäksi?", ["makkara", "liha", "nakki", "sipuli"]],
]

var game: Node3D
var phase := ""  # "" | "intro" | "ask" | "result" | "over"
var turn := 0
var wedges: Array = [[], [], [], []]
var wins := {}  # hahmo -> voitot viikonlopun aikana
var cat := 0
var q: Array = []
var winner := -1
var right_count := 0  # pelaajan oikeat vastaukset tässä pelissä
var _on := false
var _t := 0.0
var _result := ""
var _rng := RandomNumberGenerator.new()
var _used: Array = []
var _ui: CanvasLayer
var _score: Label
var _cat_label: Label
var _question: Label
var _meter: Ui.Meter
var _info: Label
var _picks: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "bottom", 680)
	Ui.label(box, "LAUTAPELI · YSÄRITRIVIA", 20, Ui.YELLOW)
	_score = Ui.label(box, "", 15, Color(0.85, 0.85, 0.9))
	_cat_label = Ui.label(box, "", 18)
	_question = Ui.label(box, "", 22)
	_meter = Ui.Meter.new()
	box.add_child(_meter)
	_info = Ui.label(box, "", 16)
	for k in 2:
		var b := Ui.button(box, ["1. Ysäritrivia", "2. Afrikan tähti"][k], func() -> void: choose(k))
		b.custom_minimum_size = Vector2(300, 38)
		_picks.append(b)


func reset() -> void:
	wins = {}


func human() -> int:
	return game.player_index


func _name(i: int) -> String:
	return game.Porukka.CREW[i].name


func start() -> bool:
	var seat: Array = game.world.mokki.table_seats[human()]
	game.player.sit_at(seat[0], seat[1])
	_gather(true)
	_on = true
	_ui.visible = true
	phase = "valinta"
	_refresh()
	return true


func stop(_why := "") -> void:
	_on = false
	_ui.visible = false
	phase = ""
	game.player.stand_up()
	_gather(false)


func _gather(on: bool) -> void:
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if game.crew_modes[j] != "ai" or b.brain == null:
			continue
		if on:
			b.brain.cards(j)
		else:
			b.brain.cards_end()


func _new_game() -> void:
	wedges = [[], [], [], []]
	right_count = 0
	winner = -1
	turn = _rng.randi() % 4
	phase = "intro"
	_refresh()


## Pelin valinta pöydässä: 0 = ysäritrivia, 1 = Afrikan tähti (afrikantahti.gd).
func choose(k: int) -> void:
	if phase != "valinta":
		return
	if k == 0:
		_new_game()
	else:
		game.call_deferred("start_activity", "afrikka")


func _unhandled_input(event: InputEvent) -> void:
	if not _on or phase != "valinta" or Chat.typing:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_1:
			choose(0)
		elif event.physical_keycode == KEY_2:
			choose(1)


func prompt() -> String:
	match phase:
		"valinta":
			return "1: ysäritrivia · 2: Afrikan tähti · W: nouse pöydästä"
		"ask":
			if turn == human():
				return "Enter: kirjoita vastaus chattiin · E: ohita · W: nouse pöydästä"
			return "Vastaamassa: %s · W: nouse pöydästä" % _name(turn)
		"over":
			return "E: uusi peli · W: nouse pöydästä"
		_:
			return "E: jatka · W: nouse pöydästä"


func act() -> void:
	match phase:
		"intro":
			_begin_turn()
		"ask":
			if turn == human():
				_resolve(false, "")
		"result":
			_t = 0.0
		"over":
			_new_game()
	_refresh()


## Pelaajan vastaus chatista (chat.gd say).
func wants_answer() -> bool:
	return _on and phase == "ask" and turn == human()


func submit(text: String) -> void:
	if wants_answer():
		_resolve(matches(text, q[2]), text)
		_refresh()


## Vastaus oikein: sama merkkijono pienillä kirjaimilla ilman ääkkösiä ja välimerkkejä, tai (yli 4 merkin
## vastauksilla) vastaus sisältyy kirjoitettuun, esim. "Ranskan" vastaa "ranska".
static func matches(given: String, answers: Array) -> bool:
	var g := _norm(given)
	if g == "":
		return false
	for a: String in answers:
		var n := _norm(a)
		if g == n or (n.length() > 4 and g.contains(n)):
			return true
	return false


static func _norm(s: String) -> String:
	var t := s.to_lower().strip_edges()
	for pair in [["ä", "a"], ["ö", "o"], ["å", "a"], [".", ""], [",", ""], ["!", ""], ["?", ""], ["-", ""], [" ", ""]]:
		t = t.replace(pair[0], pair[1])
	return t


func _begin_turn() -> void:
	var open: Array = range(CATS.size()).filter(func(c: int) -> bool: return not wedges[turn].has(c))
	cat = open[_rng.randi() % open.size()]
	var pool: Array = QUESTIONS.filter(func(x: Array) -> bool: return x[0] == cat and not _used.has(x[1]))
	if pool.is_empty():
		_used = _used.filter(func(t: String) -> bool: return not QUESTIONS.any(func(x: Array) -> bool: return x[1] == t and x[0] == cat))
		pool = QUESTIONS.filter(func(x: Array) -> bool: return x[0] == cat)
	q = pool[_rng.randi() % pool.size()]
	_used.append(q[1])
	phase = "ask"
	_t = ASK_T if turn == human() else _rng.randf_range(2.5, 4.5)


## Vastaus annettu (said = pelaajan kirjoittama): oikein/väärin, tulos näkyviin.
func _resolve(ok: bool, said: String) -> void:
	var who := turn
	var answer: String = (q[2] as Array)[0]
	if ok:
		wedges[who].append(cat)
		if who == human():
			right_count += 1
		_result = "%s vastasi oikein (%s) ja saa kiilan: %s." % [_name(who), answer, CATS[cat]]
		Sfx.play("win_small", -10.0)
		if wedges[who].size() >= WIN:
			phase = "over"
			winner = who
			wins[who] = int(wins.get(who, 0)) + 1
			_result += " %s voitti pelin!" % _name(who)
			if who == human():
				game.maine = mini(100, game.maine + 3)
				_result += " Kunnia kasvaa (maine +3)."
				Sfx.play("win", -8.0)
			if right_count >= 3:
				game.tarina.complete("trivia")
			return
	else:
		_result = "%s ei osunut. Oikea vastaus: %s." % [_name(who), answer]
		if said == "" and who == human():
			_result = "Ohitettu. Oikea vastaus: %s." % answer
		Sfx.play("lose", -12.0)
		turn = (turn + 1) % 4
	if right_count >= 3 and who == human():
		game.tarina.complete("trivia")
	phase = "result"
	_t = RESULT_T


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not _on:
		return
	match phase:
		"ask":
			_t -= delta
			if turn == human():
				if _t <= 0.0:
					_resolve(false, "")
			elif _t <= 0.0:
				_ai_answer()
		"result":
			_t -= delta
			if _t <= 0.0:
				_begin_turn()
	_refresh()


func _ai_answer() -> void:
	var skill: float = SKILL.get(_name(turn), 0.5)
	var ok := _rng.randf() < skill
	if ok:
		game.chat.ai_say(turn, "%s!" % (q[2] as Array)[0].capitalize())
	else:
		game.chat.ai_say(turn, ["Hmm... en muista.", "Ööö... pas.", "Kyllä mä tiesin, mutta..."][_rng.randi() % 3])
	_resolve(ok, "x")


func _refresh() -> void:
	if not _on:
		return
	var parts: Array[String] = []
	for i in 4:
		parts.append("%s%s %d/%d" % ["> " if i == turn and phase != "intro" and phase != "over" else "", _name(i), wedges[i].size(), WIN])
	_score.text = "   ·   ".join(parts)
	for b: Button in _picks:
		b.visible = phase == "valinta"
	_meter.visible = phase == "ask" and turn == human()
	if _meter.visible:
		_meter.zones = [[0.0, 1.0, Color(0.25, 0.5, 0.3, 0.6)]]
		_meter.set_value(1.0 - _t / ASK_T)
	match phase:
		"valinta":
			_cat_label.text = "Lautapelit"
			_question.text = "Mitä pelataan?"
			_info.text = "Ysäritrivia: 90-luvun kysymyksiä, vastaukset chattiin. Afrikan tähti: noppaa ja matkaa kartalla."
		"intro":
			_cat_label.text = ""
			_question.text = "Ysäritrivia: kerää %d kiilaa eri aihepiireistä. Oikea vastaus pitää vuoron." % WIN
			_info.text = "Vastaukset kirjoitetaan chattiin (Enter). E aloittaa."
		"ask":
			_cat_label.text = "%s · %s" % [_name(turn), CATS[cat]]
			_cat_label.add_theme_color_override("font_color", CAT_COLORS[cat])
			_question.text = q[1]
			_info.text = "Kirjoita vastaus chattiin (Enter), E ohittaa." if turn == human() else "%s miettii..." % _name(turn)
		"result", "over":
			_info.text = _result
			if phase == "over":
				_cat_label.text = "Peli ohi"
				_question.text = "%s voitti." % _name(winner)
				_info.text = _result


## Lopputuloksen rivit: trivian voittajat (tyhjä, jos ei pelattu).
func ending_lines() -> Array[String]:
	var out: Array[String] = []
	if wins.is_empty():
		return out
	var best := 0
	for k in wins:
		best = maxi(best, int(wins[k]))
	var names: Array[String] = []
	for k in wins:
		if int(wins[k]) == best:
			names.append(_name(k))
	out.append("Ysäritrivian voittaja: %s (%d voittoa)" % [", ".join(names), best])
	return out
