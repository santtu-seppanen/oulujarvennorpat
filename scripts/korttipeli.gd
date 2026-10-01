extends Node
## Ristiseiska alamökin keittiön pöydässä (säännöt ristiseiska.gd). Pöytään istuva pelaaja näkee pelin ja
## kätensä; kortteja pelataan klikkaamalla. Mukana ovat aina kaikki neljä mökkiläistä: pöydässä istuvat
## ihmiset pelaavat itse, muiden puolesta pelaa tietokone, ja tietokoneen ohjaamat hahmot kävelevät pöytään.
##
## Moninpelissä pelitilaa pitää host: muut lähettävät siirtonsa ("rs") ja host jakaa tilan ("rs_tila").

const R := preload("res://scripts/ristiseiska.gd")
const Ui := preload("res://scripts/ui.gd")

var bot_delay := 1.2  # tietokoneen siirron viive (testissä pienempi)
const RED := Color(0.8, 0.08, 0.1)

var game: Node3D
var logic := R.new()
var humans := {}  # mökkiläisen indeksi -> pöydässä istuva ihminen (hostin tieto)
var _rng := RandomNumberGenerator.new()
var _bot_t := 0.0
var _ai_at_table := false
var _seen_moves := -1
var _seen_phase := ""

var _ui: CanvasLayer
var _rows: Array = []  # maa -> HBoxContainer
var _hand: HBoxContainer
var _status: Label
var _players: Label
var _deal_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	game.mp.on("rs", func(d: Dictionary, from: int) -> void:
		if game.mp.net.is_host():
			_handle(d, from))
	game.mp.on("rs_tila", func(d: Dictionary, from: int) -> void:
		if from == game.mp.net.host_id:
			logic.from_dict(d.s)
			humans.clear()
			for i in d.hu:
				humans[int(i)] = true
			_changed())
	game.mp.net.peer_joined.connect(func(_id: int) -> void:
		if game.mp.net.is_host():
			_broadcast())
	_build_ui()


func _authority() -> bool:
	return not game.mp.online() or game.mp.net.is_host()


# --- Toiminta (main.gd kutsuu) --------------------------------------------------------------------------------

func start() -> bool:
	var m: Node3D = game.world.mokki
	var seat: Array = m.table_seats[game.player_index]
	game.player.sit_at(seat[0], seat[1])
	_ui.visible = true
	CamCtl.free_mouse = true
	_request("istu")
	game.kokkaus.eat()
	_refresh()
	return true


func act() -> void:
	if logic.phase == "idle" or logic.phase == "over":
		_request("jaa")


func stop(_why := "") -> void:
	_ui.visible = false
	CamCtl.free_mouse = false
	game.player.stand_up()
	_request("nouse")


func prompt() -> String:
	if logic.phase == "idle" or logic.phase == "over":
		return "E: jaa kortit (ristiseiska) · W: nouse pöydästä"
	return "Ristiseiska: klikkaa korttia · W: nouse pöydästä"


# --- Pelitila (host) ------------------------------------------------------------------------------------------

func _request(a: String, c := -1) -> void:
	var d := {"t": "rs", "a": a, "i": game.player_index, "c": c}
	if _authority():
		_handle(d, game.mp.net.my_id)
	else:
		d["to"] = game.mp.net.host_id
		game.mp.send(d)


func _handle(d: Dictionary, from: int) -> void:
	var i := int(d.get("i", -1))
	if i < 0 or i >= 4:
		return
	# Siirron saa tehdä vain hahmoa ohjaava pelaaja.
	if game.mp.online():
		if game.mp.owners.get(i, -1) != from:
			return
	elif i != game.player_index:
		return
	var c := int(d.get("c", -1))
	match d.get("a", ""):
		"istu":
			humans[i] = true
		"nouse":
			humans.erase(i)
		"jaa":
			if logic.phase == "idle" or logic.phase == "over":
				logic.deal(_rng.randi())
				_bot_t = 0.0
		"pelaa":
			logic.play(i, c)
		"anna":
			logic.give(i, c)
	_broadcast()


func _broadcast() -> void:
	game.mp.send({"t": "rs_tila", "s": logic.to_dict(), "hu": humans.keys()})
	_changed()


func _process(delta: float) -> void:
	if not _authority():
		return
	# Pöydästä poistuneet ihmiset (yhteys katkesi tai hahmo vaihtui) korvautuvat tietokoneella.
	for i in humans.keys():
		var here: bool = (i == game.player_index and game.activity == "kortit") or \
			(game.mp.online() and game.mp.owners.has(i) and game.mp.owners[i] != game.mp.net.my_id)
		if not here:
			humans.erase(i)
			_broadcast()
	var playing := logic.phase == "play" or logic.phase == "give"
	if playing != _ai_at_table:
		_ai_at_table = playing
		_gather_ai(playing)
	if not playing:
		return
	var a := logic.actor()
	if humans.has(a):
		return
	_bot_t += delta
	if _bot_t < bot_delay:
		return
	_bot_t = 0.0
	if logic.phase == "play":
		logic.play(a, logic.bot_play(a, _rng))
	else:
		logic.give(a, logic.bot_give(a, _rng))
	_broadcast()


## Tietokoneen ohjaamat mökkiläiset pöytään pelin ajaksi.
func _gather_ai(on: bool) -> void:
	var m: Node3D = game.world.mokki
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if game.crew_modes[j] != "ai" or b.brain == null:
			continue
		if on:
			b.brain.cards(m.table_seats[j])
		else:
			b.brain.cards_end()


# --- Näyttö ---------------------------------------------------------------------------------------------------

func _name(i: int) -> String:
	return game.Porukka.CREW[i].name


## Tilan muutos: äänet ja tapahtumat, sitten näkymä.
func _changed() -> void:
	if logic.moves != _seen_moves and not logic.last.is_empty() and game.activity == "kortit":
		var l: Dictionary = logic.last
		Sfx.play("cloth" if l.a == "pelasi" else "pickup", -10.0, randf_range(0.9, 1.2))
	if logic.phase == "over" and _seen_phase != "over" and _seen_phase != "":
		var w: int = logic.finished[0]
		var loser: int = logic.finished[-1]
		var me: int = game.player_index
		if game.activity == "kortit":
			game.toast("%s voitti ristiseiskan! %s jäi viimeiseksi." % [_name(w), _name(loser)], 6.0)
			Sfx.play("win" if w == me else ("lose" if loser == me else "win_small"), -6.0)
	_seen_moves = logic.moves
	_seen_phase = logic.phase
	_refresh()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var top := Ui.panel(_ui, "top", 840)
	Ui.label(top, "RISTISEISKA", 24, Ui.YELLOW)
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 18)
	top.add_child(mid)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	mid.add_child(rows)
	for s in 4:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 3)
		rows.add_child(h)
		_rows.append(h)
	_players = Ui.label(mid, "", 16)
	_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_players.autowrap_mode = TextServer.AUTOWRAP_OFF
	_players.custom_minimum_size = Vector2(250, 0)
	_status = Ui.label(top, "", 17)
	var bottom := Control.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = -560
	bottom.offset_right = 560
	bottom.offset_top = -190
	bottom.offset_bottom = -100
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bottom)
	_hand = HBoxContainer.new()
	_hand.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_hand)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	top.add_child(btns)
	_deal_btn = Ui.button(btns, "Jaa kortit (E)", func() -> void: _request("jaa"))
	Ui.button(btns, "Nouse pöydästä (W)", func() -> void: game.end_activity())


func _refresh() -> void:
	if not _ui.visible:
		return
	var me: int = game.player_index
	var playing := logic.phase == "play" or logic.phase == "give"
	_deal_btn.visible = not playing
	# Pöydän rivit: A..K, pelatut kortit näkyvissä, muut himmeinä paikkoina.
	for s in 4:
		var h: HBoxContainer = _rows[s]
		for ch in h.get_children():
			ch.queue_free()
		for r in range(1, 14):
			var cv := CardView.new()
			cv.card = s * 13 + r - 1
			cv.custom_minimum_size = Vector2(38, 52)
			cv.ghost = logic.low[s] == 0 or r < logic.low[s] or r > logic.high[s]
			h.add_child(cv)
	# Pelaajat: korttien määrä, vuoro ja sijoitus.
	var lines := []
	for p in 4:
		var mark := "▶ " if playing and logic.actor() == p else "   "
		var who := _name(p) + (" (sinä)" if p == me else ("" if humans.has(p) else " (tietokone)"))
		var info := ""
		if logic.finished.has(p):
			info = "%d." % (logic.finished.find(p) + 1)
		elif logic.hands.size() == 4:
			info = "%d korttia" % logic.hands[p].size()
		lines.append("%s%s  %s" % [mark, who, info])
	_players.text = "\n".join(lines)
	# Tilanne.
	var st := ""
	match logic.phase:
		"idle":
			st = "Jaa kortit aloittaaksesi. Ristiseiskan saanut aloittaa."
		"over":
			st = "Peli päättyi: " + ", ".join(logic.finished.map(func(p: int) -> String:
				return "%d. %s" % [logic.finished.find(p) + 1, _name(p)])) + ". Jaa uudet kortit (E)."
		"play":
			st = "Sinun vuorosi: pelaa korostettu kortti" if logic.turn == me else "Vuorossa: %s" % _name(logic.turn)
		"give":
			if logic.giver == me:
				st = "%s ei voi pelata: anna hänelle kortti (klikkaa)" % _name(logic.turn)
			else:
				st = "%s ei voi pelata, %s antaa kortin" % [_name(logic.turn), _name(logic.giver)]
	if not logic.last.is_empty() and playing:
		var l: Dictionary = logic.last
		if l.a == "pelasi":
			st = "%s pelasi %s. %s" % [_name(l.p), R.card_name(l.c), st]
		else:
			st = "%s antoi kortin %s:lle. %s" % [_name(l.p), _name(l.to), st]
	_status.text = st
	# Oma käsi.
	for ch in _hand.get_children():
		ch.queue_free()
	if logic.hands.size() == 4:
		var hand: Array = logic.hands[me]
		_hand.add_theme_constant_override("separation", 4 if hand.size() <= 14 else -14)
		for c in hand:
			var cv := CardView.new()
			cv.card = c
			cv.custom_minimum_size = Vector2(60, 86)
			if logic.phase == "play" and logic.turn == me:
				cv.active = logic.can_play(c)
			elif logic.phase == "give" and logic.giver == me:
				cv.active = true
			cv.dim = playing and not cv.active
			cv.clicked.connect(_on_card)
			_hand.add_child(cv)


func _on_card(c: int) -> void:
	var me: int = game.player_index
	if logic.phase == "play" and logic.turn == me and logic.can_play(c):
		_request("pelaa", c)
	elif logic.phase == "give" and logic.giver == me:
		_request("anna", c)


## Pelikortti piirrettynä: arvo kulmissa ja maa keskellä. Maat piirretään kuvioina (fontista riippumatta).
class CardView:
	extends Control
	signal clicked(card: int)
	var card := 0
	var ghost := false  # tyhjä paikka pöydän rivissä
	var active := false  # voi pelata / antaa
	var dim := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if not ghost else Control.MOUSE_FILTER_IGNORE
		if active:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(card)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var s := card / 13
		var red := s == 1 or s == 2
		var ink := Color(0.8, 0.08, 0.1) if red else Color(0.08, 0.08, 0.1)
		if ghost:
			draw_rect(r, Color(1, 1, 1, 0.06))
			draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)
			return
		var up := Vector2(0, -8) if active else Vector2.ZERO
		r.position += up
		draw_rect(r, Color(0.98, 0.97, 0.94) if not dim else Color(0.7, 0.69, 0.67))
		draw_rect(r, Color(1.0, 0.8, 0.1) if active else Color(0.3, 0.3, 0.3), false, 3.0 if active else 1.0)
		var font := ThemeDB.fallback_font
		var fs := int(size.y * 0.26)
		var txt: String = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][card % 13]
		draw_string(font, r.position + Vector2(3, fs), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		suit_shape(self, s, r.position + Vector2(size.x * 0.5, size.y * 0.6), size.x * 0.42, ink)

	## Maa kuviona keskipisteeseen c, koko w.
	static func suit_shape(ci: CanvasItem, s: int, c: Vector2, w: float, col: Color) -> void:
		var h := w * 0.5
		match s:
			0:  # risti: kolme palloa ja jalka
				for o in [Vector2(0, -0.32), Vector2(-0.3, 0.08), Vector2(0.3, 0.08)]:
					ci.draw_circle(c + o * w, h * 0.5, col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.0) * w, c + Vector2(-0.2, 0.5) * w,
					c + Vector2(0.2, 0.5) * w]), col)
			1:  # ruutu
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.55) * w, c + Vector2(0.4, 0) * w,
					c + Vector2(0, 0.55) * w, c + Vector2(-0.4, 0) * w]), col)
			2:  # hertta
				ci.draw_circle(c + Vector2(-0.24, -0.15) * w, h * 0.52, col)
				ci.draw_circle(c + Vector2(0.24, -0.15) * w, h * 0.52, col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.5, -0.06) * w, c + Vector2(0.5, -0.06) * w,
					c + Vector2(0, 0.52) * w]), col)
			3:  # pata: ylösalainen hertta ja jalka
				ci.draw_circle(c + Vector2(-0.24, 0.12) * w, h * 0.52, col)
				ci.draw_circle(c + Vector2(0.24, 0.12) * w, h * 0.52, col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.5, 0.03) * w, c + Vector2(0.5, 0.03) * w,
					c + Vector2(0, -0.55) * w]), col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.1) * w, c + Vector2(-0.18, 0.55) * w,
					c + Vector2(0.18, 0.55) * w]), col)
