extends Node
## Afrikan tähti alamökin keittiön pöydässä, alkuperäisen lautapelin sääntöjen mukaan. Tavoite: etsiä Afrikan tähti maitse,
## meritse ja ilmateitse ja viedä se Tangeriin tai Kairoon.
## Lauta: 26 punaista ympyrää (kaupunkia), joissa jokaisessa on sinipuolinen kiekko sokkona (tähti, 2 rubiinia, 3 smaragdia,
## 4 topaasia, 3 rosvoa, 5 hevosenkenkää ja 8 tyhjää), sekä Tangeri ja Kairo (lähtö ja maali). Kaupunkeja yhdistävät
## maatiet (ilmaiset, nopan silmäluvun verran pisteitä), meritiet (100 £ lähtiessä satamasta, nopan verran sinisiä pisteitä)
## ja lentoreitit (300 £, ei noppaa). Reitin saa valita vapaasti kaupungeissa, ja kaupunkiin voi pysähtyä ennen kuin silmäluku
## on käytetty. Kaupunkiin saapuessa kiekon voi ostaa 100 £:lla ja kääntää, tai jäädä odottamaan ja yrittää avata se
## nopalla (4–6 avaa ilmaiseksi). Kiekot: tyhjä (pois), topaasi +300 £, smaragdi +600 £, rubiini +1000 £, rosvo vie kaikki
## rahat, hevosenkenkä (turha, ellei tähteä ole löydetty; sen jälkeen löydetty hevosenkenkä käy tähden asemesta voittoon) ja
## Afrikan tähti. Erikoispaikat: Kapkaupunki (ensimmäinen perille saa 500 £), Kultarannikko (Accra: jalokivi kaksinkertaisena),
## Guineanlahti (Lagos: tyhjän kiekon ostaja jää kolmeksi vuoroksi), Pyhä Helena (vankina, kunnes noppa antaa 1 tai 2),
## Saharan autiomaa (mustalla pisteellä sinisen renkaan sisällä vuoronsa päättävä jää vangiksi, kunnes noppa antaa 1 tai 2).
## Aloitusraha 300 £. Pelaaja valitsee ylös/alas-nuolilla (W/S, A/D) valikosta ja vahvistaa E:llä tai klikkaa karttaa;
## tietokoneen mökkiläiset pelaavat itse ja istuvat pöytään. F nousee pöydästä, H avaa ohjeen.

const Ui := preload("res://scripts/ui.gd")
const Chat := preload("res://scripts/chat.gd")

const START_MONEY := 300
const TOKEN_PRICE := 100
const SEA_FEE := 100
const AIR_FEE := 300
const CAPE_BONUS := 500
const HOP_DELAY := 0.55  # askel (s)
const AI_DELAY := 1.1  # tietokoneen päätös (s)
const END_DELAY := 1.0
const GEM_VALUE := {"topaasi": 300, "smaragdi": 600, "rubiini": 1000}
const TOKEN_NAMES := {"tyhja": "tyhjä", "topaasi": "topaasi", "smaragdi": "smaragdi", "rubiini": "rubiini", "rosvo": "rosvo",
	"hevosenkenka": "hevosenkenkä", "tahti": "Afrikan tähti"}
const PLAYER_COLORS := [Color(1.0, 0.6, 0.15), Color(0.35, 0.6, 1.0), Color(0.4, 0.85, 0.4), Color(0.9, 0.4, 0.85)]
## Kaupungit: [nimi, paikka kartalla (0..1), erikois]. Kaksi ensimmäistä ovat Tangeri ja Kairo (lähtö ja maali, ei kiekkoa).
const CITIES := [
	["Tangeri", Vector2(0.16, 0.07), "maali"], ["Kairo", Vector2(0.82, 0.10), "maali"],
	["Alger", Vector2(0.35, 0.08), ""], ["Tunis", Vector2(0.52, 0.06), ""], ["Tripoli", Vector2(0.60, 0.17), ""],
	["Bengasi", Vector2(0.71, 0.12), ""], ["Timbuktu", Vector2(0.27, 0.29), ""], ["Agadez", Vector2(0.44, 0.29), ""],
	["Khartum", Vector2(0.77, 0.33), ""], ["Dakar", Vector2(0.04, 0.34), ""], ["Freetown", Vector2(0.06, 0.43), ""],
	["Accra", Vector2(0.20, 0.49), "kulta"], ["Lagos", Vector2(0.31, 0.50), "lagos"], ["Fort Lamy", Vector2(0.52, 0.38), ""],
	["Addis Abeba", Vector2(0.87, 0.45), ""], ["Mogadishu", Vector2(0.95, 0.52), ""], ["Libreville", Vector2(0.38, 0.59), ""],
	["Kinshasa", Vector2(0.50, 0.62), ""], ["Kisangani", Vector2(0.62, 0.51), ""], ["Nairobi", Vector2(0.80, 0.60), ""],
	["Dar es Salaam", Vector2(0.87, 0.69), ""], ["Luanda", Vector2(0.44, 0.75), ""], ["Lubumbashi", Vector2(0.64, 0.70), ""],
	["Beira", Vector2(0.80, 0.80), ""], ["Windhoek", Vector2(0.50, 0.86), ""], ["Johannesburg", Vector2(0.68, 0.88), ""],
	["Kapkaupunki", Vector2(0.56, 0.97), "kapi"], ["Pyhä Helena", Vector2(0.14, 0.76), "helena"],
]
## Maatiet [a, b]; autiomaareitit (pisteet kuolevat sinisen renkaan sisään) ovat omassa listassaan.
const LAND := [[0, 2], [2, 3], [3, 4], [4, 5], [5, 1], [0, 6], [6, 9], [9, 10], [10, 11], [6, 11], [11, 12], [12, 13], [13, 8], [1, 8],
	[8, 14], [14, 15], [14, 19], [13, 18], [18, 17], [17, 16], [16, 12], [17, 21], [18, 19], [19, 20], [20, 22], [17, 22], [21, 22],
	[22, 23], [23, 25], [22, 25], [21, 24], [24, 25], [24, 26], [25, 26], [18, 8]]
const DESERT := [[6, 7], [7, 4], [2, 7], [5, 8], [7, 13]]
const SEA := [[3, 4], [1, 14], [20, 15], [23, 20], [25, 23], [26, 25], [26, 21], [21, 16], [16, 12], [12, 11], [11, 10], [10, 9], [9, 0],
	[27, 21], [27, 26], [3, 5]]
const AIR := [[0, 6], [3, 7], [4, 1], [7, 8], [6, 11], [11, 16], [16, 17], [13, 18], [8, 19], [18, 22], [17, 21], [19, 20], [22, 25],
	[24, 26], [14, 19]]
const KINDS := ["tahti", "rubiini", "rubiini", "smaragdi", "smaragdi", "smaragdi", "topaasi", "topaasi", "topaasi", "topaasi",
	"rosvo", "rosvo", "rosvo", "hevosenkenka", "hevosenkenka", "hevosenkenka", "hevosenkenka", "hevosenkenka",
	"tyhja", "tyhja", "tyhja", "tyhja", "tyhja", "tyhja", "tyhja", "tyhja"]

var game: Node3D
var phase := ""  # "" | "roll" | "choose" | "move" | "pause" | "over"
var turn := 0
var pos: Array = [0, 0, 0, 0]  # nappulan paikka solmuna (kaupungit 0…27, sen jälkeen pisteet)
var money: Array = [300, 300, 300, 300]
var carry: Array = ["", "", "", ""]  # "tahti" | "hevosenkenka" | ""
var held: Array = [false, false, false, false]  # vankina (autiomaa tai Pyhä Helena): vapautuu nopalla 1–2
var skip: Array = [0, 0, 0, 0]  # väliin jäävät vuorot
var tokens: Array = []  # kaupungin kiekko (id) tai "" (pois)
var star_found := false
var cape_taken := false
var dice := 0
var left := 0
var prev := -1
var winner := -1
var wins := {}  # hahmo -> voitot viikonlopun aikana
var opts: Array = []  # valikko: [{id, text, to (solmu tai kaupunki)}]
var sel := 0
var nodes: Array = []  # {p: Vector2, city: int (-1 = piste), kind: "maa" | "meri" | "autio"}
var adj: Array = []  # solmu -> [{to, fee}]
var air: Array = []  # kaupunki -> lentokohteet
var _on := false
var _t := 0.0
var _message := ""
var _rng := RandomNumberGenerator.new()
var _ui: CanvasLayer
var _map: Map
var _score: Label
var _info: Label
var _flow: HFlowContainer
var _human_turns := 0


## Kartta: Afrikan ääriviiva, reitit pisteineen, kaupungit kiekkoineen, nappulat ja valitun valinnan kohde.
class Map:
	extends Control
	signal clicked(city: int)
	var g: Node
	const OUTLINE := [Vector2(0.14, 0.09), Vector2(0.30, 0.04), Vector2(0.50, 0.03), Vector2(0.60, 0.10), Vector2(0.70, 0.07),
		Vector2(0.82, 0.04), Vector2(0.86, 0.14), Vector2(0.90, 0.30), Vector2(0.99, 0.46), Vector2(0.96, 0.58),
		Vector2(0.92, 0.72), Vector2(0.84, 0.84), Vector2(0.72, 0.94), Vector2(0.62, 1.0), Vector2(0.52, 1.0),
		Vector2(0.45, 0.88), Vector2(0.44, 0.72), Vector2(0.40, 0.60), Vector2(0.33, 0.55), Vector2(0.20, 0.55),
		Vector2(0.08, 0.50), Vector2(0.02, 0.40), Vector2(0.0, 0.30), Vector2(0.05, 0.20), Vector2(0.10, 0.12)]

	func _init() -> void:
		custom_minimum_size = Vector2(0, 340)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func at(p: Vector2) -> Vector2:
		return Vector2(size.x * (0.03 + 0.94 * p.x), size.y * (0.03 + 0.94 * p.y))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for i in g.CITIES.size():
				if at(g.nodes[i].p).distance_to(e.position) < 20.0:
					clicked.emit(i)
					return

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.3, 0.45, 0.95))
		var pts := PackedVector2Array()
		for p: Vector2 in OUTLINE:
			pts.append(at(p))
		draw_colored_polygon(pts, Color(0.78, 0.68, 0.45))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.35, 0.28, 0.15), 2.0)
		var font := ThemeDB.fallback_font
		# Lentoreitit punaisina viivoina.
		for a: Array in g.AIR:
			draw_dashed_line(at(g.nodes[a[0]].p), at(g.nodes[a[1]].p), Color(0.9, 0.15, 0.15, 0.75), 2.0, 7.0)
		# Pisteet maa-, meri- ja autiomaareiteillä.
		for i in range(g.CITIES.size(), g.nodes.size()):
			var n: Dictionary = g.nodes[i]
			var q := at(n.p)
			match n.kind:
				"meri":
					draw_circle(q, 4.5, Color(0.1, 0.25, 0.6))
				"autio":
					draw_circle(q, 6.0, Color(0.2, 0.4, 0.8))
					draw_circle(q, 4.0, Color(0.05, 0.05, 0.05))
				_:
					draw_circle(q, 3.5, Color(0.08, 0.06, 0.04))
		var dest := -1
		if not g.opts.is_empty() and g.turn == g.human():
			var o: Dictionary = g.opts[g.sel % g.opts.size()]
			if o.has("city"):
				dest = o.city
		for i in g.CITIES.size():
			var q := at(g.nodes[i].p)
			var goal: bool = g.CITIES[i][2] == "maali"
			draw_circle(q, 14.0, Color(0.05, 0.04, 0.03))
			draw_circle(q, 12.0, Color(1.0, 0.85, 0.2) if goal else Color(0.85, 0.12, 0.1))
			if not goal and g.tokens[i] != "":
				draw_circle(q, 6.5, Color(0.25, 0.5, 0.95))  # sinipuolinen kiekko
				draw_arc(q, 6.5, 0.0, TAU, 16, Color.WHITE, 1.5)
			draw_string(font, q + Vector2(-60, 28), g.CITIES[i][0], HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0.08, 0.05, 0.02))
			if i == dest:
				draw_arc(q, 19.0, 0.0, TAU, 24, Color(0.3, 1.0, 0.4), 4.0)
		for j in 4:
			var node: int = g.pos[j]
			var q: Vector2 = at(g.nodes[node].p) + Vector2((j % 2) * 14 - 7, (j / 2) * 12 - 20)
			draw_circle(q, 8.0, Color.BLACK)
			draw_circle(q, 6.5, g.PLAYER_COLORS[j])
			if j == g.turn and g.phase != "over":
				draw_arc(q, 10.5, 0.0, TAU, 16, Color.WHITE, 2.0)
			if g.carry[j] != "":
				draw_circle(q + Vector2(9, -9), 4.0, Color(1.0, 0.95, 0.4) if g.carry[j] == "tahti" else Color(0.7, 0.7, 0.75))
		draw_rect(Rect2(Vector2.ZERO, size), Ui.YELLOW, false, 1.5)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build_graph()
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "bottom", 860)
	Ui.label(box, "LAUTAPELI · AFRIKAN TÄHTI", 20, Ui.YELLOW)
	_score = Ui.label(box, "", 15, Color(0.85, 0.85, 0.9))
	_map = Map.new()
	_map.g = self
	_map.clicked.connect(_click_city)
	box.add_child(_map)
	_info = Ui.label(box, "", 17)
	_flow = HFlowContainer.new()
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	_flow.add_theme_constant_override("h_separation", 8)
	_flow.add_theme_constant_override("v_separation", 6)
	box.add_child(_flow)


## Reittiverkko: kaupungit solmuina 0…27 ja jokaisen reitin pituuden mukaan pisteitä (solmuja) niiden välissä.
func _build_graph() -> void:
	nodes.clear()
	adj.clear()
	air.clear()
	for c: Array in CITIES:
		nodes.append({"p": c[1], "city": nodes.size(), "kind": ""})
		adj.append([])
		air.append([])
	for k in 3:
		var list: Array = [LAND, DESERT, SEA][k]
		var kind: String = ["maa", "autio", "meri"][k]
		for e: Array in list:
			_link(e[0], e[1], kind)
	for a: Array in AIR:
		air[a[0]].append(a[1])
		air[a[1]].append(a[0])


func _link(a: int, b: int, kind: String) -> void:
	for e: Dictionary in adj[a]:  # sama yhteys vain kerran (tien ja meren välillä)
		if _chain_ends(a, e.to) == b:
			return
	var pa: Vector2 = nodes[a].p
	var pb: Vector2 = nodes[b].p
	var dist := Vector2((pb.x - pa.x) * 1.7, pb.y - pa.y).length()
	var n := maxi(1, int(roundf(dist / 0.075)))
	var prev_n := a
	for k in n:
		var t := (k + 1.0) / (n + 1.0)
		var idx := nodes.size()
		var dot_kind := kind
		if kind == "autio" and (k == 0 or k == n - 1):
			dot_kind = "maa"  # autiomaareitin reunat ovat tavallista maatietä
		nodes.append({"p": pa.lerp(pb, t), "city": -1, "kind": dot_kind})
		adj.append([])
		_edge(prev_n, idx)
		prev_n = idx
	_edge(prev_n, b)


func _edge(a: int, b: int) -> void:
	adj[a].append({"to": b})
	adj[b].append({"to": a})


## Reitin toinen pää kaupungista a ensimmäisen pisteen first kautta.
func _chain_ends(a: int, first: int) -> int:
	var p := a
	var cur := first
	while nodes[cur].city < 0:
		var nxt := -1
		for e: Dictionary in adj[cur]:
			if e.to != p:
				nxt = e.to
		p = cur
		cur = nxt
	return cur


## Maksu askeleesta from -> to: merelle lähtö satamasta maksaa.
func _fee(from: int, to: int) -> int:
	return SEA_FEE if nodes[from].city >= 0 and nodes[to].kind == "meri" else 0


func human() -> int:
	return game.player_index


func _name(i: int) -> String:
	return game.Porukka.CREW[i].name


func reset() -> void:
	wins = {}


func start() -> bool:
	var seat: Array = game.world.mokki.table_seats[human()]
	game.player.sit_at(seat[0], seat[1])
	_gather(true)
	CamCtl.free_mouse = true
	_on = true
	_ui.visible = true
	new_game()
	game.ohje.open_first("afrikka")
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


## Uusi peli: kiekot sekoitetaan sokkona kaupunkeihin, jokaisella 300 £ ja lähtö Tangerista tai Kairosta.
func new_game() -> void:
	var kinds: Array = KINDS.duplicate()
	kinds.shuffle()
	tokens = []
	var k := 0
	for i in CITIES.size():
		if CITIES[i][2] == "maali":
			tokens.append("")
		else:
			tokens.append(kinds[k])
			k += 1
	for j in 4:
		pos[j] = 0 if j == human() else _rng.randi() % 2
		money[j] = START_MONEY
		carry[j] = ""
		held[j] = false
		skip[j] = 0
	star_found = false
	cape_taken = false
	winner = -1
	_human_turns = 0
	turn = _rng.randi() % 4
	_message = "Etsi Afrikan tähti ja vie se Tangeriin tai Kairoon."
	_begin_turn()


func _begin_turn() -> void:
	left = 0
	dice = 0
	prev = -1
	if skip[turn] > 0:
		skip[turn] -= 1
		_message = "%s joutuu jäämään pois tästä vuorosta." % _name(turn)
		_pause()
		return
	phase = "roll"
	_t = AI_DELAY
	_build_opts()
	_refresh()


func _pause() -> void:
	phase = "pause"
	opts = []
	_t = END_DELAY
	_refresh()


func _city_here() -> int:
	return pos[turn] if nodes[pos[turn]].city >= 0 else -1


func _token_here() -> bool:
	var c := _city_here()
	return c >= 0 and CITIES[c][2] != "maali" and tokens[c] != ""


## Valikon vaihtoehdot nykyiselle pelaajalle ja vaiheelle.
func _build_opts() -> void:
	opts = []
	sel = 0
	var who := turn
	var c := _city_here()
	if phase == "roll":
		if _token_here():
			if money[who] >= TOKEN_PRICE:
				opts.append({"id": "buy", "text": "Osta kiekko (%d £)" % TOKEN_PRICE})
			opts.append({"id": "wait", "text": "Odota ja yritä avata kiekko nopalla (4–6)"})
		opts.append({"id": "roll", "text": "Heitä noppa" + (" (1–2 vapauttaa)" if held[who] else "")})
		if c >= 0 and not held[who] and money[who] >= AIR_FEE:
			for d: int in air[c]:
				opts.append({"id": "fly", "text": "Lennä: %s (%d £)" % [CITIES[d][0], AIR_FEE], "to": d, "city": d})
	elif phase == "choose":
		if left > 0:
			for e: Dictionary in _cands():
				var r := _route(pos[who], e.to)
				var txt := "%s %s" % [{"maa": "Maatie", "autio": "Autiomaa", "meri": "Meritie"}[r.kind], CITIES[r.city][0]]
				txt = "→ %s (%d askelta%s)" % [txt, r.steps, ", %d £" % e.fee if e.fee > 0 else ""]
				opts.append({"id": "go", "text": txt, "to": e.to, "city": r.city})
		if c >= 0 and _token_here() and money[who] >= TOKEN_PRICE:
			opts.append({"id": "buy", "text": "Osta kiekko (%d £)" % TOKEN_PRICE})
		if c >= 0:
			opts.append({"id": "stop", "text": "Pysähdy tähän" if left > 0 else "Lopeta vuoro"})


## Askeleet nykyisestä solmusta: ei takaisin tulosuuntaan (ellei muuta ole) eikä merelle ilman rahaa.
func _cands() -> Array:
	var out: Array = []
	var p: int = pos[turn]
	for e: Dictionary in adj[p]:
		if e.to == prev:
			continue
		var fee := _fee(p, e.to)
		if fee <= money[turn]:
			out.append({"to": e.to, "fee": fee})
	if out.is_empty():
		for e: Dictionary in adj[p]:
			var fee := _fee(p, e.to)
			if fee <= money[turn]:
				out.append({"to": e.to, "fee": fee})
	return out


## Reitti kaupungista (tai pisteestä) from ensimmäisen pisteen first kautta seuraavaan kaupunkiin.
func _route(from: int, first: int) -> Dictionary:
	var p := from
	var cur := first
	var steps := 1
	while nodes[cur].city < 0:
		var nxt := -1
		for e: Dictionary in adj[cur]:
			if e.to != p:
				nxt = e.to
		p = cur
		cur = nxt
		steps += 1
	return {"city": cur, "kind": nodes[first].kind, "steps": steps}


# --- Toiminnot ------------------------------------------------------------------------------------------------

## Valikon vaihtoehto i (pelaaja vahvistaa tai tietokone valitsee).
func confirm(i: int) -> void:
	if i < 0 or i >= opts.size() or not (phase == "roll" or phase == "choose"):
		return
	var o: Dictionary = opts[i]
	match o.id:
		"roll":
			roll()
		"wait":
			wait_roll()
		"fly":
			_fly(o.to)
		"buy":
			_buy()
		"go":
			_step(o.to)
		"stop":
			end_turn()
	_refresh()


func roll() -> void:
	dice = _rng.randi_range(1, 6)
	left = dice
	if turn == human():
		_human_turns += 1
	Sfx.play("pickup", -10.0)
	if held[turn]:
		if dice <= 2:
			held[turn] = false
			_message = "%s heitti %d ja pääsi vapaaksi." % [_name(turn), dice]
		else:
			_message = "%s heitti %d: yhä vankina (vapaaksi 1 tai 2)." % [_name(turn), dice]
			_next_turn()
			return
	else:
		_message = "%s heitti %d." % [_name(turn), dice]
	_continue()


## Kaupungissa odottaja heittää: 4–6 avaa kiekon ilmaiseksi.
func wait_roll() -> void:
	dice = _rng.randi_range(1, 6)
	Sfx.play("pickup", -10.0)
	if dice >= 4:
		_message = "%s heitti %d ja sai kiekon auki ilmaiseksi." % [_name(turn), dice]
		_open_token(true)
	else:
		_message = "%s heitti %d: ei vielä auki (tarvitaan 4–6)." % [_name(turn), dice]
	if phase != "over":
		_next_turn()


func _fly(to: int) -> void:
	money[turn] -= AIR_FEE
	prev = -1
	pos[turn] = to
	left = 0
	_message = "%s lensi kaupunkiin %s." % [_name(turn), CITIES[to][0]]
	Sfx.play("pickup", -8.0, 1.4)
	_arrive()


func _buy() -> void:
	money[turn] -= TOKEN_PRICE
	_open_token(false)
	if phase == "over":
		return
	# Ostettu kiekko: valikko päivittyy (noppa tai matkan jatko); jos ei ole enää mitään tehtävää, vuoro päättyy.
	_build_opts()
	_t = AI_DELAY
	if phase == "choose" and left <= 0 and opts.size() <= 1:
		end_turn()


func _step(to: int) -> void:
	var from: int = pos[turn]
	money[turn] -= _fee(from, to)
	prev = from
	pos[turn] = to
	left -= 1
	if nodes[to].city >= 0:
		_arrive()
	else:
		_continue()


## Saapuminen kaupunkiin: maali tähden tai hevosenkengän kanssa voittaa, Kapkaupunki antaa bonuksen.
func _arrive() -> void:
	var c := _city_here()
	if CITIES[c][2] == "maali" and carry[turn] != "":
		_win(turn)
		return
	if CITIES[c][2] == "kapi" and not cape_taken:
		cape_taken = true
		money[turn] += CAPE_BONUS
		_message += " Ensimmäisenä Kapkaupunkiin: %d £ pankista!" % CAPE_BONUS
		Sfx.play("coin", -8.0)
	phase = "choose"
	_t = AI_DELAY
	_build_opts()
	if opts.is_empty() or (opts.size() == 1 and opts[0].id == "stop" and left <= 0):
		end_turn()


## Pisteen tai kaupungin jälkeen: jatka matkaa, valikko tai vuoron loppu.
func _continue() -> void:
	if left <= 0:
		if nodes[pos[turn]].city >= 0:
			phase = "choose"
			_t = AI_DELAY
			_build_opts()
			if opts.size() <= 1:
				end_turn()
		else:
			end_turn()
		return
	if nodes[pos[turn]].city >= 0:
		phase = "choose"
		_t = AI_DELAY
		_build_opts()
		return
	var c := _cands()
	if c.size() >= 2:
		phase = "choose"
		_t = AI_DELAY
		opts = []
		sel = 0
		for e: Dictionary in c:
			var r := _route(pos[turn], e.to)
			opts.append({"id": "go", "text": "→ %s (%d askelta)" % [CITIES[r.city][0], r.steps], "to": e.to, "city": r.city})
	else:
		phase = "move"
		_t = HOP_DELAY
		opts = []


## Kiekon kääntäminen kaupungissa: vaikutus ja kiekko pois pelistä.
func _open_token(free: bool) -> void:
	var c := _city_here()
	var tk: String = tokens[c]
	var who := turn
	var nm := _name(who)
	var how := "" if free else " 100 £:lla"
	tokens[c] = ""
	if GEM_VALUE.has(tk):
		var v: int = GEM_VALUE[tk] * (2 if CITIES[c][2] == "kulta" else 1)
		money[who] += v
		_message = "%s osti%s kiekon: %s! Pankki maksaa %d £%s." % [nm, how, TOKEN_NAMES[tk], v, " (Kultarannikko: kaksinkertainen)" if CITIES[c][2] == "kulta" else ""]
		Sfx.play("win_small", -8.0)
	elif tk == "rosvo":
		_message = "%s avasi kiekon%s: ROSVO! Kaikki rahat (%d £) menivät." % [nm, how, money[who]]
		money[who] = 0
		Sfx.play("lose", -8.0)
	elif tk == "tahti":
		carry[who] = "tahti"
		star_found = true
		_message = "%s löysi AFRIKAN TÄHDEN! Nyt Tangeriin tai Kairoon!" % nm
		Sfx.play("win", -6.0)
	elif tk == "hevosenkenka":
		if star_found:
			carry[who] = "hevosenkenka"
			_message = "%s sai hevosenkengän, ja tähti on jo löydetty: se käy voittoon Tangerissa tai Kairossa!" % nm
			Sfx.play("win_small", -8.0)
		else:
			_message = "%s avasi kiekon%s: hevosenkenkä, mutta tähteä ei ole vielä löydetty. Kiekko pois." % [nm, how]
	else:
		_message = "%s avasi kiekon%s: tyhjä." % [nm, how]
		if CITIES[c][2] == "lagos" and not free:
			skip[who] = 3
			_message += " Guineanlahdella myrsky: kolme vuoroa väliin."
		Sfx.play("lose", -14.0)
	if tk == "tahti" and who != human():
		game.chat.ai_say(who, "Tähti löytyi!")


func end_turn() -> void:
	if phase == "over":
		return
	var who := turn
	var p: int = pos[who]
	if nodes[p].kind == "autio" and nodes[p].city < 0:
		held[who] = true
		_message += " %s jäi Saharaan: beduiinit pidättävät (vapaaksi 1 tai 2)." % _name(who)
	elif nodes[p].city >= 0 and CITIES[nodes[p].city][2] == "helena" and not held[who]:
		held[who] = true
		_message += " Pyhän Helenan merirosvot pidättävät (vapaaksi 1 tai 2)."
	_next_turn()


func _next_turn() -> void:
	turn = (turn + 1) % 4
	_pause()


func _win(who: int) -> void:
	phase = "over"
	winner = who
	opts = []
	wins[who] = int(wins.get(who, 0)) + 1
	_message = "%s toi %s %s ja voitti pelin!" % [_name(who), "Afrikan tähden" if carry[who] == "tahti" else "hevosenkengän",
		CITIES[pos[who]][0]]
	if who == human():
		game.maine = mini(100, game.maine + 3)
		_message += " Maine +3."
		Sfx.play("win", -8.0)
	else:
		game.chat.ai_say(who, "Afrikan tähti on minun!")
	if _human_turns >= 3:
		game.tarina.complete("afrikka")
	_refresh()


# --- Tietokone ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if not _on or phase == "over" or game.ohje.is_open():
		return
	_t -= delta
	if _t > 0.0:
		return
	match phase:
		"pause":
			_begin_turn()
		"move":
			var c := _cands()
			if c.is_empty():
				end_turn()
			else:
				_step(c[0].to)
			_refresh()
		"roll", "choose":
			if turn != human():
				confirm(_ai_pick())
			elif _t < -60.0:
				confirm(_ai_pick())  # ei jäädä odottamaan ikuisesti


## Etäisyys (askelta) lähimpään kohteeseen kaikista solmuista: kohteena Tangeri ja Kairo kun nappulalla on tähti tai
## hevosenkenkä, muuten kaupungit, joissa on vielä kiekko. Merelle ei lähdetä ilman rahaa.
func _dist_map(who: int) -> Array:
	var d: Array = []
	d.resize(nodes.size())
	d.fill(999)
	var q: Array = []
	for i in CITIES.size():
		var goal: bool = CITIES[i][2] == "maali"
		if (carry[who] != "" and goal) or (carry[who] == "" and not goal and tokens[i] != ""):
			d[i] = 0
			q.append(i)
	var qi := 0
	while qi < q.size():
		var n: int = q[qi]
		qi += 1
		for e: Dictionary in adj[n]:
			var to: int = e.to
			var sea: bool = (nodes[n].kind == "meri" or nodes[to].kind == "meri") and (nodes[n].city >= 0 or nodes[to].city >= 0)
			var nd: int = d[n] + 1 + (2 if sea else 0)
			if nd < d[to]:
				d[to] = nd
				q.append(to)
	return d


func _ai_pick() -> int:
	var who := turn
	var d := _dist_map(who)
	var here: int = pos[who]
	var best := -1
	var best_v := 1.0e9
	for i in opts.size():
		var o: Dictionary = opts[i]
		var v := 1.0e8
		match o.id:
			"buy":
				v = -1000.0
			"wait":
				v = -500.0 if money[who] < TOKEN_PRICE else 1000.0
			"roll":
				v = 100.0
			"fly":
				var gain: int = d[here] - d[o.to]
				v = 0.0 if gain >= 6 and money[who] >= AIR_FEE + TOKEN_PRICE else 5000.0
			"go":
				v = float(d[o.to]) + _rng.randf() * 0.3
			"stop":
				v = -400.0 if (_token_here() and money[who] < TOKEN_PRICE) else 5000.0
		if v < best_v:
			best_v = v
			best = i
	return maxi(best, 0)


# --- Syöte ja näkymä ------------------------------------------------------------------------------------------

## Valikko käyttää ylös/alas-näppäimiä: main.gd ei nosta pelaajaa pöydästä niistä (F nostaa).
func keeps_arrows() -> bool:
	return true


func prompt() -> String:
	if phase == "over":
		return "E: uusi peli · H: ohje · F: nouse pöydästä"
	if turn != human():
		return "Vuorossa: %s · H: ohje · F: nouse pöydästä" % _name(turn)
	return "↑/↓: valitse · E: vahvista (tai klikkaa karttaa) · H: ohje · F: nouse pöydästä"


func act() -> void:
	if phase == "over":
		new_game()
	elif turn == human() and (phase == "roll" or phase == "choose"):
		confirm(sel)


func _click_city(c: int) -> void:
	if turn != human() or not (phase == "roll" or phase == "choose"):
		return
	for i in opts.size():
		if opts[i].has("city") and opts[i].city == c:
			sel = i
			confirm(i)
			return


func _unhandled_input(event: InputEvent) -> void:
	if not _on or Chat.typing or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_H:
		game.ohje.open("afrikka")
		get_viewport().set_input_as_handled()
		return
	if turn != human() or not (phase == "roll" or phase == "choose") or opts.is_empty():
		return
	var k: int = event.physical_keycode - KEY_1
	if k >= 0 and k < opts.size():
		sel = k
		confirm(k)
	elif event.is_action_pressed("forward") or event.is_action_pressed("left"):
		sel = (sel + opts.size() - 1) % opts.size()
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("back") or event.is_action_pressed("right"):
		sel = (sel + 1) % opts.size()
		_refresh()
		get_viewport().set_input_as_handled()


func _status(i: int) -> String:
	var s := "%s%s %d £" % ["> " if i == turn and phase != "over" else "", _name(i), money[i]]
	if carry[i] == "tahti":
		s += " ★"
	elif carry[i] == "hevosenkenka":
		s += " (hevosenkenkä)"
	if held[i]:
		s += " [vankina]"
	if skip[i] > 0:
		s += " [%d vuoroa väliin]" % skip[i]
	return s


func _refresh() -> void:
	if not _on:
		return
	var parts: Array[String] = []
	for i in 4:
		parts.append(_status(i))
	_score.text = "   ·   ".join(parts)
	for c in _flow.get_children():
		c.queue_free()
	if turn == human() and (phase == "roll" or phase == "choose"):
		for i in opts.size():
			var b := Ui.button(_flow, "%s%d. %s" % ["> " if i == sel else "", i + 1, opts[i].text], func() -> void:
				sel = i
				confirm(i))
			b.custom_minimum_size = Vector2(250, 36)
			b.add_theme_font_size_override("font_size", 15)
	_map.queue_redraw()
	match phase:
		"roll", "choose":
			if turn == human():
				_info.text = "%s Sinun vuorosi%s." % [_message, " (noppa %d, askelia jäljellä %d)" % [dice, left] if left > 0 else ""]
			else:
				_info.text = "%s Vuorossa %s." % [_message, _name(turn)]
		"over":
			_info.text = _message
		_:
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
