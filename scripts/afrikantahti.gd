extends Node
## Afrikan tähti -tyyppinen lautapeli alamökin keittiön pöydässä. Kartalla on 13 kaupunkia ja niitä yhdistävät reitit.
## Kaikki aloittavat Tunisista ja jokaisen pitää kerätä kolme timanttia (kaupungit arvotaan joka pelissä) ja sen
## jälkeen Afrikan tähti, ja viedä ne takaisin Tunisiin. Vuorolla heitetään noppaa (E) ja liikutaan kaupungista
## naapurikaupunkiin yksi askel kutakin silmälukua kohti (A/D valitsee, E vahvistaa tai klikkaus kartalta, Q lopettaa
## liikkeen). Timantti kerätään kaupunkiin saapuessa; jokaisella on omat timanttinsa. Jos vuoronsa päättää toisen
## pelaajan kaupunkiin, toinen joutuu takaisin Tunisiin (kerätyt säilyvät). Tietokoneen mökkiläiset pelaavat itse
## ja istuvat pöytään. Valinta lautapelin ja trivian välillä tehdään lautapeli.gd:ssä (Q pöydässä).

const Ui := preload("res://scripts/ui.gd")
const Chat := preload("res://scripts/chat.gd")

const START := 1
const GEM_COUNT := 3
const ROLL_DELAY := 1.0  # tietokoneen heitto (s)
const HOP_DELAY := 0.75  # tietokoneen askel (s)
const END_DELAY := 0.9
## Kaupungit: nimi ja paikka kartalla (0..1).
const CITIES := [
	["Casablanca", Vector2(0.15, 0.10)], ["Tunis", Vector2(0.46, 0.07)], ["Kairo", Vector2(0.80, 0.13)],
	["Dakar", Vector2(0.05, 0.36)], ["Timbuktu", Vector2(0.28, 0.30)], ["Khartum", Vector2(0.74, 0.36)],
	["Lagos", Vector2(0.30, 0.54)], ["Addis Abeba", Vector2(0.90, 0.50)], ["Kinshasa", Vector2(0.54, 0.60)],
	["Nairobi", Vector2(0.78, 0.68)], ["Luanda", Vector2(0.38, 0.78)], ["Dar es Salaam", Vector2(0.90, 0.82)],
	["Kapkaupunki", Vector2(0.58, 0.92)],
]
const EDGES := [[0, 1], [0, 3], [0, 4], [1, 2], [1, 4], [2, 5], [3, 4], [3, 6], [4, 5], [4, 6], [5, 7], [5, 8], [6, 8],
	[6, 10], [7, 9], [8, 9], [8, 10], [9, 11], [10, 12], [11, 12], [8, 12]]
const GEM_NAMES := ["sininen", "punainen", "vihreä"]
const GEM_COLORS := [Color(0.35, 0.55, 1.0), Color(0.95, 0.25, 0.25), Color(0.3, 0.85, 0.4)]
const PLAYER_COLORS := [Color(1.0, 0.6, 0.15), Color(0.35, 0.6, 1.0), Color(0.4, 0.85, 0.4), Color(0.9, 0.4, 0.85)]

var game: Node3D
var phase := ""  # "" | "roll" | "move" | "over"
var turn := 0
var pos: Array = [START, START, START, START]
var gems: Array = [[], [], [], []]  # pelaajan keräämät timantit (indeksit 0..GEM_COUNT-1)
var star: Array = [false, false, false, false]
var gem_city: Array = []  # timantin k kaupunki
var star_city := 0
var dice := 0
var left := 0  # liikkeitä jäljellä
var winner := -1
var wins := {}  # hahmo -> voitot viikonlopun aikana
var sel := 0  # valittu naapuri (indeksi neighbors-listassa)
var _on := false
var _t := 0.0
var _message := ""
var _rng := RandomNumberGenerator.new()
var _ui: CanvasLayer
var _map: Map
var _score: Label
var _info: Label
var _human_turns := 0


## Kartta: reitit, kaupungit, tämän pelaajan keräämättömät timantit, nappulat ja valittavissa olevat kaupungit.
class Map:
	extends Control
	signal picked(city: int)
	var g: Node
	var options: Array = []
	var selected := -1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 330)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func at(i: int) -> Vector2:
		return Vector2(size.x * (0.05 + 0.9 * g.CITIES[i][1].x), size.y * (0.08 + 0.84 * g.CITIES[i][1].y))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for i in options:
				if at(i).distance_to(e.position) < 24.0:
					picked.emit(i)
					return

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.1, 0.07, 0.85))
		for ed: Array in g.EDGES:
			draw_line(at(ed[0]), at(ed[1]), Color(0.7, 0.6, 0.4, 0.8), 3.0)
		var me: int = g.human()
		var font := ThemeDB.fallback_font
		for i in g.CITIES.size():
			var p := at(i)
			var col := Color(0.85, 0.75, 0.5)
			if i == g.START:
				col = Color(1.0, 0.85, 0.2)
			draw_circle(p, 13.0, Color(0.05, 0.04, 0.03))
			draw_circle(p, 11.0, col)
			draw_string(font, p + Vector2(-60, 28), g.CITIES[i][0], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color.WHITE)
			for k in g.GEM_COUNT:
				if g.gem_city[k] == i and not g.gems[me].has(k):
					draw_rect(Rect2(p + Vector2(-5, -5), Vector2(10, 10)), g.GEM_COLORS[k])
			if g.star_city == i and not g.star[me]:
				var pts := PackedVector2Array()
				for k in 10:
					var a := -PI * 0.5 + TAU * k / 10.0
					pts.append(p + Vector2(cos(a), sin(a)) * (9.0 if k % 2 == 0 else 4.0))
				draw_colored_polygon(pts, Color(1.0, 0.95, 0.4))
		for i in options:
			draw_arc(at(i), 18.0, 0.0, TAU, 24, Color(0.4, 1.0, 0.5), 3.0 if i != selected else 6.0)
		for j in 4:
			var q := at(g.pos[j]) + Vector2((j % 2) * 18 - 9, (j / 2) * 14 - 24)
			draw_circle(q, 8.0, Color.BLACK)
			draw_circle(q, 6.5, g.PLAYER_COLORS[j])
			if j == g.turn and g.phase != "over":
				draw_arc(q, 10.5, 0.0, TAU, 16, Color.WHITE, 2.0)
		draw_rect(Rect2(Vector2.ZERO, size), Ui.YELLOW, false, 1.5)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "bottom", 700)
	Ui.label(box, "LAUTAPELI · AFRIKAN TÄHTI", 20, Ui.YELLOW)
	_score = Ui.label(box, "", 15, Color(0.85, 0.85, 0.9))
	_map = Map.new()
	_map.g = self
	_map.picked.connect(hop)
	box.add_child(_map)
	_info = Ui.label(box, "", 17)


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
	CamCtl.free_mouse = true
	_on = true
	_ui.visible = true
	new_game()
	return true


func stop(_why := "") -> void:
	_on = false
	_ui.visible = false
	CamCtl.free_mouse = false
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


## Uusi peli: timanttien ja tähden kaupungit arvotaan (ei aloituskaupunkiin, tähti kauas alusta).
func new_game() -> void:
	pos = [START, START, START, START]
	gems = [[], [], [], []]
	star = [false, false, false, false]
	winner = -1
	_human_turns = 0
	var open: Array = range(CITIES.size())
	open.erase(START)
	open.shuffle()
	gem_city = open.slice(0, GEM_COUNT)
	var far: Array = open.slice(GEM_COUNT).filter(func(c: int) -> bool: return distance(START, c) >= 3)
	star_city = far[_rng.randi() % far.size()] if not far.is_empty() else open[GEM_COUNT]
	turn = _rng.randi() % 4
	_message = "Kerää %d timanttia, sitten Afrikan tähti, ja palaa Tunisiin." % GEM_COUNT
	_begin_turn()


func _begin_turn() -> void:
	phase = "roll"
	_t = ROLL_DELAY
	dice = 0
	left = 0
	_refresh()


func prompt() -> String:
	if phase == "over":
		return "E: uusi peli · W: nouse pöydästä"
	if turn != human():
		return "Vuorossa: %s · W: nouse pöydästä" % _name(turn)
	if phase == "roll":
		return "E: heitä noppaa · W: nouse pöydästä"
	return "A/D: valitse kaupunki, E tai klikkaus: siirry · Q: lopeta liike · W: nouse pöydästä"


func act() -> void:
	if phase == "over":
		new_game()
	elif turn == human():
		if phase == "roll":
			roll()
		elif phase == "move":
			var nb := neighbors(pos[turn])
			if not nb.is_empty():
				hop(nb[sel % nb.size()])
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not _on or Chat.typing or phase != "move" or turn != human():
		return
	var nb := neighbors(pos[turn])
	if event.is_action_pressed("left") and not nb.is_empty():
		sel = (sel + nb.size() - 1) % nb.size()
		_refresh()
	elif event.is_action_pressed("right") and not nb.is_empty():
		sel = (sel + 1) % nb.size()
		_refresh()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_Q:
		end_turn()
		_refresh()


static func neighbors(c: int) -> Array:
	var out: Array = []
	for e: Array in EDGES:
		if e[0] == c:
			out.append(e[1])
		elif e[1] == c:
			out.append(e[0])
	out.sort()
	return out


## Lyhin askelmäärä kaupungista a kaupunkiin b.
static func distance(a: int, b: int) -> int:
	var dist := {a: 0}
	var queue: Array = [a]
	while not queue.is_empty():
		var c: int = queue.pop_front()
		if c == b:
			return dist[c]
		for n: int in neighbors(c):
			if not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return 99


func roll() -> void:
	if phase != "roll":
		return
	dice = _rng.randi_range(1, 6)
	left = dice
	phase = "move"
	sel = 0
	if turn == human():
		_human_turns += 1
	_message = "%s heitti %d." % [_name(turn), dice]
	Sfx.play("pickup", -10.0)
	_t = HOP_DELAY
	_refresh()


## Askel kaupunkiin c (naapuri). Timantti kerätään saapuessa, tähti vasta kun kaikki timantit on kerätty.
func hop(c: int) -> void:
	if phase != "move" or not neighbors(pos[turn]).has(c):
		return
	var who := turn
	pos[who] = c
	left -= 1
	_t = HOP_DELAY
	sel = 0
	for k in GEM_COUNT:
		if gem_city[k] == c and not gems[who].has(k):
			gems[who].append(k)
			_message = "%s keräsi timantin (%s) kaupungissa %s." % [_name(who), GEM_NAMES[k], CITIES[c][0]]
			Sfx.play("win_small", -10.0)
	if star_city == c and not star[who] and gems[who].size() == GEM_COUNT:
		star[who] = true
		_message = "%s sai Afrikan tähden kaupungista %s!" % [_name(who), CITIES[c][0]]
		Sfx.play("win_small", -8.0)
	if c == START and star[who]:
		_win(who)
		return
	if left <= 0:
		end_turn()
	_refresh()


func end_turn() -> void:
	if phase != "move":
		return
	var who := turn
	var c: int = pos[who]
	if c != START:
		for j in 4:
			if j != who and pos[j] == c:
				pos[j] = START
				_message = "%s joutui takaisin Tunisiin: %s tuli samaan kaupunkiin." % [_name(j), _name(who)]
	turn = (turn + 1) % 4
	phase = "roll"
	_t = END_DELAY
	dice = 0
	left = 0


func _win(who: int) -> void:
	phase = "over"
	winner = who
	wins[who] = int(wins.get(who, 0)) + 1
	_message = "%s toi Afrikan tähden Tunisiin ja voitti pelin!" % _name(who)
	if who == human():
		game.maine = mini(100, game.maine + 3)
		_message += " Maine +3."
		Sfx.play("win", -8.0)
	else:
		game.chat.ai_say(who, "Afrikan tähti on minun!")
	if _human_turns >= 3:
		game.tarina.complete("afrikka")
	_refresh()


func _process(delta: float) -> void:
	step(delta)


## Tietokoneen vuoro: heitto ja askeleet viiveellä.
func step(delta: float) -> void:
	if not _on or phase == "over":
		return
	_t -= delta
	if _t > 0.0:
		return
	if phase == "roll":
		if turn != human():
			roll()
		elif _t < -30.0:
			roll()  # ei jäädä odottamaan ikuisesti
	elif phase == "move" and turn != human():
		hop(_ai_pick())
		_refresh()


## Tietokoneen seuraava kaupunki: lähin vielä tarvittava kohde (timantti, tähti, sitten Tunis).
func _ai_pick() -> int:
	var target := _target(turn)
	var best := -1
	var best_d := 99.0
	for n: int in neighbors(pos[turn]):
		var d := distance(n, target) + (_rng.randf() * 0.4)
		if d < best_d:
			best_d = d
			best = n
	return best


func _target(who: int) -> int:
	var here: int = pos[who]
	var best := -1
	var best_d := 99
	for k in GEM_COUNT:
		if not gems[who].has(k) and distance(here, gem_city[k]) < best_d:
			best_d = distance(here, gem_city[k])
			best = gem_city[k]
	if best >= 0:
		return best
	return START if star[who] else star_city


func _refresh() -> void:
	if not _on:
		return
	var parts: Array[String] = []
	for i in 4:
		parts.append("%s%s %d/%d%s" % ["> " if i == turn and phase != "over" else "", _name(i), gems[i].size(), GEM_COUNT,
			" +tähti" if star[i] else ""])
	_score.text = "   ·   ".join(parts)
	_map.options = neighbors(pos[turn]) if phase == "move" and turn == human() else []
	_map.selected = _map.options[sel % _map.options.size()] if not _map.options.is_empty() else -1
	_map.queue_redraw()
	match phase:
		"roll":
			_info.text = "%s Vuorossa %s%s" % [_message, _name(turn), ": heitä noppaa (E)." if turn == human() else "."]
		"move":
			_info.text = "%s Liikkeitä jäljellä %d%s." % [_message, left, ": valitse kaupunki" if turn == human() else ""]
		"over":
			_info.text = _message


## Lopputuloksen rivit: Afrikan tähden voittajat (tyhjä, jos ei pelattu).
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
	out.append("Afrikan tähden voittaja: %s (%d voittoa)" % [", ".join(names), best])
	return out
