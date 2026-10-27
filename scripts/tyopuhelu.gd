extends Node
## Työpuhelu saunan alla: satunnaistapahtuma, joka tulee aina vain Jaakolle. Kun Jaakko istuu lauteilla (sauna.gd),
## puhelin soi parinkymmenen–viidenkymmenen sekunnin kuluttua, enintään kerran päivässä. E vastaa: työasiat hoituvat
## (mainepisteet +2), mutta löylyt pilaantuvat (löylypisteet -6, kuumuus laskee). Q jättää vastaamatta: löylyt jatkuvat
## (löylypisteet +3), mutta esimies jättää ärtyneen viestin (mainepisteet -2, ei joka kerta). Jos puhelimeen ei vastata
## kymmenessä sekunnissa, se on vastaamatta jättämistä. Jos Jaakkoa ohjaa tietokone, hän vain mutisee saunassa
## työpuhelusta.

const Ui := preload("res://scripts/ui.gd")

const WHO := "Jaakko"
const RING_T := 10.0  # puhelin soi näin kauan
const ANSWER_POINTS := -6.0
const IGNORE_POINTS := 3.0
## [soittaja, repliikki].
const CALLS := [
	["Esimies", "JAAKKO! Missä ne raportit on?! Vastaa nyt heti!"],
	["Esimies", "Moi, onko sulla hetki? Tuotannossa palaa jotain, ja sua tarvittaisiin heti."],
	["Asiakas", "Hei, pieni kysymys vain: voitko katsoa yhtä asiaa nyt, ennen kuin se unohtuu?"],
	["Palaveri", "Muistutus: palaveri alkoi viisi minuuttia sitten. Missä sä olet?"],
	["Tiimin ryhmächatti", "Kaikki odottaa sua, tuliko tuo korjaus jo? Soitellaan nopeasti."],
]
const MUMBLES := ["Työpuhelu... ei vastata. Nyt on löylyt.", "Esimies soittaa taas. Puhelin on takin taskussa.",
	"Ei kai ne nyt saunaan soita..."]

var game: Node3D
var active := false  # puhelin soi
var called_day := -1  # päivä, jolloin puhelu on jo tullut
var answered := 0
var ignored := 0
var _t := -1.0  # jäljellä soittoon (s), < 0 = ei ajastettu
var _ring := 0.0
var _beep := 0.0
var _was_sauna := false
var _call: Array = []
var _ai_day := -1
var _ui: CanvasLayer
var _title: Label
var _text: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_ui = CanvasLayer.new()
	_ui.layer = 25
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "center", 560)
	_title = Ui.label(box, "TYÖPUHELU", 24, Ui.YELLOW)
	_text = Ui.label(box, "", 20)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	Ui.button(row, "Vastaa (E)", func() -> void: answer(true))
	Ui.button(row, "Ei vastata (Q)", func() -> void: answer(false))


## Onko pelaajan hahmo Jaakko (vain hänelle tulee työpuheluita).
func is_jaakko() -> bool:
	return game.Porukka.CREW[game.player_index].name == WHO


func _day() -> int:
	return game.tarina.day


## Puhelu voi tulla: Jaakko saunoo, eikä tälle päivälle ole vielä tullut puhelua.
func can_call() -> bool:
	return is_jaakko() and game.activity == "sauna" and called_day != _day() and not active


func reset() -> void:
	called_day = -1
	answered = 0
	ignored = 0
	_ai_day = -1
	_t = -1.0
	if active:
		_close()


func _process(delta: float) -> void:
	var in_sauna: bool = game.activity == "sauna"
	if in_sauna and not _was_sauna and can_call():
		_t = _rng.randf_range(20.0, 50.0)  # puhelu aikaisintaan 20 s lauteille istumisesta
	if not in_sauna and _was_sauna and not active:
		_t = -1.0
	_was_sauna = in_sauna
	if active:
		_ring -= delta
		_beep -= delta
		if _beep <= 0.0:
			_beep = 1.4
			Sfx.play("alert", -6.0, 1.3)
		if _ring <= 0.0 or not in_sauna:
			answer(false)
		return
	if _t >= 0.0 and in_sauna:
		_t -= delta
		if _t <= 0.0:
			_t = -1.0
			trigger()
	_ai_mumble(delta)


## Puhelin alkaa soida (testit kutsuvat suoraan).
func trigger() -> void:
	if not can_call():
		return
	called_day = _day()
	active = true
	_ring = RING_T
	_beep = 0.0
	_call = CALLS[_rng.randi() % CALLS.size()]
	_title.text = "TYÖPUHELU · %s" % _call[0].to_upper()
	_text.text = "\"%s\"\n\nVastaatko saunassa?" % _call[1]
	_ui.visible = true
	CamCtl.free_mouse = true
	game.toast("Puhelin soi lauteilla...", 3.0)


## Vastaus (yes) tai vastaamatta jättäminen (testit kutsuvat suoraan).
func answer(yes: bool) -> void:
	if not active:
		return
	_close()
	# Soittajan nalkuttava miesääni (nauhoitettu, puhe.gd): vastattaessa puhelimessa, muuten vastaajaviestinä hiljaa.
	game.chat.speak_voice("esimies", str(_call[1]), 0.0 if yes else -9.0)
	var s: Node = game.sauna
	if yes:
		answered += 1
		s.points = maxf(0.0, s.points + ANSWER_POINTS)
		s.heat = maxf(0.0, s.heat - 15.0)
		s.loyly *= 0.3
		game.maine = mini(100, game.maine + 2)
		game.toast("Hoidit työasiat saunasta käsin: mainepisteet +2 (nyt %d/100), mutta löylyt jäähtyivät (löylypisteet %d)."
			% [game.maine, int(s.points)], 6.0)
		Sfx.play("pickup", -8.0)
	else:
		ignored += 1
		s.points += IGNORE_POINTS
		if _rng.randf() < 0.5:
			game.lose_maine(2, "%s jätti ärtyneen viestin" % _call[0])
		else:
			game.toast("Puhelu jäi vastaamatta, eikä kukaan huomannut. Löylyt jatkuvat (+3 pistettä).", 5.0)
		Sfx.play("win_small", -12.0)


func _close() -> void:
	active = false
	_ui.visible = false
	CamCtl.free_mouse = false


func _unhandled_input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.is_action_pressed("interact"):
		answer(true)
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_Q:
		answer(false)
		get_viewport().set_input_as_handled()


## Tietokoneen ohjaama Jaakko mutisee työpuhelusta saunassa (kerran päivässä).
func _ai_mumble(delta: float) -> void:
	if _ai_day == _day():
		return
	for j in game.crew.size():
		if game.Porukka.CREW[j].name != WHO or j == game.player_index or game.crew_modes[j] != "ai":
			continue
		var b: CharacterBody3D = game.crew[j]
		if b.brain != null and "activity" in b.brain and b.brain.activity == "sauna" and b.pose.begins_with("Sitting") and _rng.randf() < delta / 30.0:
			_ai_day = _day()
			game.chat.ai_say(j, MUMBLES[_rng.randi() % MUMBLES.size()])


## Lopputuloksen rivi: saunan työpuhelut (tyhjä, jos puheluita ei tullut).
func ending_lines() -> Array[String]:
	var out: Array[String] = []
	if answered + ignored == 0:
		return out
	out.append("Työpuheluita saunassa: vastattu %d, ei vastattu %d" % [answered, ignored])
	return out
