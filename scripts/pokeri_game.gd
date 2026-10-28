extends CanvasLayer
## Pokeri (Coinline Casino, Veikkauksen/RAYn pokeriautomaatti, ks. Wikipedia "Pokeri (automaatti)") hedelmäpelin ja pajatson
## vieressä. Jokeripokeri: 52 kortin pakka ja jokeri (villi kortti). Viisi korttia jaetaan, pelaaja pitää haluamansa
## (1–5, A/D + välilyönti tai klikkaus) ja loput vaihdetaan kerran uusiin. Pienin voittava käsi on kaksi paria; päävoitto
## (50 × panos) tulee viitosilla (neloset ja jokeri) tai värisuoralla. Panos 1–5 € (W/S).
## Voiton voi tuplata, jos se on korkeintaan puolet päävoitosta: kortti 2–6 PIENI, 8–K SUURI (ässä = 1, pieni), seiska vie
## (vasen = pieni, oikea = suuri), mutta punainen seiska päättää tuplauksen ja voitot saa pitää. E vie talteen.
## E jakaa ja vaihtaa. F / Esc lopettaa (voitto talteen). finished(money): rahat pelin jälkeen.

signal finished(money: float)
signal comment(text: String)

const MG := preload("res://scripts/mg_draw.gd")

const RANKS := ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
const JOKER := 52  # kortti 52 = jokeri (villi)
## [nimi, kerroin]; järjestys on voittotaulukon järjestys.
const HANDS := [["Viitoset", 50], ["Värisuora", 50], ["Neloset", 25], ["Täyskäsi", 10], ["Väri", 6], ["Suora", 4],
	["Kolmoset", 2], ["Kaksi paria", 1]]
const MAIN_WIN := 50  # päävoitto (€ per panos-euro): tuplata saa korkeintaan puolet tästä
const LINES := ["Coinline Casino. Kaksi paria on pienin voittava käsi, ja jokeri on villi.",
	"Jokeri ja pari on jo kolmoset. Pidä jokeri aina.",
	"Neljä samaa ja jokeri on viitoset: päävoitto."]
const CARD_W := 150.0
const CARD_H := 210.0

var money := 10.0
var drunk := 0.0

var _root: Control
var _info: Label
var _keys: Control
var _tip: Label
var _deck: Array[int] = []
var _hand: Array[int] = [-1, -1, -1, -1, -1]  # kortti = maa * 13 + arvo (0 = kakkonen … 12 = ässä)
var _held: Array[bool] = [false, false, false, false, false]
var _cursor := 0
var _bet := 1
## Vaihe: "idle" (panos), "hold" (valitse pidettävät), "draw" (vaihto animaationa), "win" (talteen tai tuplaus), "tupla".
var _phase := "idle"
var _hand_name := ""
var _win := 0.0
var _draw_t := 0.0
var _reveal := [1.0, 1.0, 1.0, 1.0, 1.0]  # kortin kääntymisen edistyminen 0…1
var _card := 0
var _card_red := false
var _card_t := 0.0
var _guess := ""
var _msg := ""
var _t := 0.0
var _done := false
var _flash := 0.0
var _sparks: Array = []
var _k := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("esc_lopettaa")  # Esc lopettaa pelin: taukovalikko ei aukea (menu.gd)
	layer = 6
	_rng.randomize()
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw_root)
	_root.gui_input.connect(_gui_input)
	add_child(_root)
	_info = _label(22, 4.0, false)
	_keys = preload("res://scripts/hint_bar.gd").new()
	_keys.compact = true
	_keys.centered = true
	add_child(_keys)
	_tip = _label(22, -90.0, true)
	_tip.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	comment.connect(func(t: String) -> void: _tip.text = t)
	_msg = "PANOS %d €" % _bet
	comment.emit(LINES.pick_random())


func _label(size: int, y: float, bottom: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	l.anchor_right = 1.0
	if bottom:
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
	l.offset_top = y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# --- Pelilogiikka ---------------------------------------------------------------------------------------------

static func rank(c: int) -> int:
	return c % 13


static func suit(c: int) -> int:
	return c / 13


static func is_joker(c: int) -> bool:
	return c == JOKER


func _new_deck() -> void:
	_deck.clear()
	for c in 53:
		_deck.append(c)
	for i in range(52, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _deck[i]
		_deck[i] = _deck[j]
		_deck[j] = tmp


## Voiko (uniikit, ilman jokeria olevat) arvot muodostaa suoran jokerin avulla? Ässä on myös alin (pyörä A-2-3-4-5).
static func _fits_straight(rs: Array) -> bool:
	for st in range(-1, 9):
		var ok := true
		for r: int in rs:
			if not ((r >= st and r <= st + 4) or (r == 12 and st == -1)):
				ok = false
		if ok:
			return true
	return false


## Käden arvo: indeksi HANDS-taulukkoon tai -1 (ei voittoa). Jokeri on villi kortti.
static func evaluate(cards: Array) -> int:
	var counts := {}
	var rs: Array = []
	var suits := {}
	var jokers := 0
	for c: int in cards:
		if is_joker(c):
			jokers += 1
			continue
		counts[rank(c)] = int(counts.get(rank(c), 0)) + 1
		rs.append(rank(c))
		suits[suit(c)] = true
	var vals: Array = counts.values()
	vals.sort()
	var top: int = vals[vals.size() - 1]
	var unique := vals.size() == rs.size()
	var flush := suits.size() == 1
	var straight := unique and _fits_straight(rs)
	if top + jokers >= 5:
		return 0
	if straight and flush:
		return 1
	if top + jokers >= 4:
		return 2
	if vals == [2, 3] or (jokers == 1 and vals == [2, 2]):
		return 3
	if flush:
		return 4
	if straight:
		return 5
	if top + jokers >= 3:
		return 6
	if vals == [1, 2, 2]:
		return 7
	return -1


func payout(idx: int, bet: int) -> int:
	if idx < 0:
		return 0
	return int(HANDS[idx][1]) * bet


func _deal() -> void:
	if money < float(_bet):
		if money >= 1.0:
			_bet = int(money)
			_msg = "PANOS %d €" % _bet
			comment.emit("Rahat eivät riitä: panos laski %d euroon." % _bet)
			return
		comment.emit("Rahat loppu. Kone ei anna velaksi.")
		return
	money -= float(_bet)
	_new_deck()
	for i in 5:
		_hand[i] = _deck.pop_back()
		_held[i] = false
		_reveal[i] = 0.0 - i * 0.12
	_cursor = 0
	_win = 0.0
	_hand_name = ""
	_phase = "hold"
	_msg = "PIDÄ KORTIT"
	Sfx.play("cloth", -10.0, 1.2)
	var idx := evaluate(_hand)
	if idx >= 0:
		comment.emit("Valmis käsi: %s. Pidä kaikki ja vaihda (E)." % HANDS[idx][0])


func _draw_cards() -> void:
	for i in 5:
		if not _held[i]:
			_hand[i] = _deck.pop_back()
			_reveal[i] = 0.0 - i * 0.1
	_phase = "draw"
	_draw_t = 0.0
	Sfx.play("cloth", -10.0, 1.4)


func _resolve() -> void:
	var idx := evaluate(_hand)
	_win = float(payout(idx, _bet))
	if _win > 0.0:
		_hand_name = HANDS[idx][0]
		_phase = "win"
		_flash = 1.5
		_msg = "%s  %s €" % [_hand_name.to_upper(), _eur(_win)]
		Sfx.play("win" if idx <= 5 else "win_small", -4.0)
		MG.sparks_burst(_sparks, Vector2(_root.size.x * 0.5, 300.0), Color(1.0, 0.85, 0.2), 40 if idx <= 5 else 18)
		if idx <= 1:
			comment.emit("%s! Päävoitto, nyt on onni mukana." % HANDS[idx][0])
	else:
		_phase = "idle"
		_msg = "EI VOITTOA"
		Sfx.play("lose", -10.0)
		comment.emit(LINES.pick_random())


func _collect() -> void:
	money += _win
	_win = 0.0
	_phase = "idle"
	_msg = "PANOS %d €" % _bet
	Sfx.play("coin", -10.0, 1.2)


func _double(guess: String) -> void:
	_guess = guess
	_card = _rng.randi_range(1, 13)
	_card_red = _rng.randi() % 2 == 0
	_card_t = 0.0
	_phase = "tupla"
	Sfx.play("cloth", -10.0, 1.4)


func _double_result() -> void:
	if _card == 7 and _card_red:
		comment.emit("Punainen seiska! Tuplaus päättyy, ja voitot saa pitää.")
		_collect()
		return
	var ok := (_guess == "pieni" and _card <= 6) or (_guess == "suuri" and _card >= 8)
	if ok:
		_win *= 2.0
		_flash = 1.0
		Sfx.play("win_small", -6.0, 1.1)
		_msg = "TUPLAUS %s €" % _eur(_win)
		if not _can_double():
			comment.emit("Tuplausraja täynnä (puolet päävoitosta). Kone maksaa voiton ulos.")
			_collect()
			return
		_phase = "win"
	else:
		Sfx.play("lose", -6.0)
		comment.emit("Musta seiska vie aina." if _card == 7 else ["Väärin arvattu. Voitto meni.", "Ahneella on paskanen loppu."].pick_random())
		_win = 0.0
		_msg = "PANOS %d €" % _bet
		_phase = "idle"


## Tuplata saa, jos voitto on korkeintaan puolet päävoitosta (50 € × panos / 2).
func _can_double() -> bool:
	return _win <= float(MAIN_WIN * _bet) * 0.5


func _toggle(i: int) -> void:
	if _phase != "hold" or i < 0 or i > 4:
		return
	_held[i] = not _held[i]
	_cursor = i
	Sfx.play("pickup", -12.0, 1.4)


func _finish() -> void:
	if _win > 0.0:
		money += _win
	_done = true
	finished.emit(money)
	queue_free()


func _eur(v: float) -> String:
	return ("%.2f" % v).replace(".", ",").trim_suffix(",00")


# --- Syöte ----------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _done or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var kc: Key = event.physical_keycode
	if _phase == "hold":
		if kc >= KEY_1 and kc <= KEY_5:
			_toggle(kc - KEY_1)
			get_viewport().set_input_as_handled()
		elif kc == KEY_SPACE:
			_toggle(_cursor)
			get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if _done or _phase != "hold":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in 5:
			var br := _card_rect(i)
			br.size.y += 90.0
			if br.has_point(event.position / _k):
				_toggle(i)
				return


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_root.queue_redraw()
	_flash = maxf(0.0, _flash - delta)
	MG.sparks_step(_sparks, delta)
	for i in 5:
		_reveal[i] = minf(1.0, _reveal[i] + delta * 4.0)
	if Input.is_action_just_pressed("mount") or Input.is_key_pressed(KEY_ESCAPE):
		if _phase == "tupla" or _phase == "draw":
			return
		_finish()
		return
	match _phase:
		"idle":
			if Input.is_action_just_pressed("forward") and _bet < 5:
				_bet += 1
				_msg = "PANOS %d €" % _bet
				Sfx.play("pickup", -12.0, 1.2)
			elif Input.is_action_just_pressed("back") and _bet > 1:
				_bet -= 1
				_msg = "PANOS %d €" % _bet
				Sfx.play("pickup", -12.0, 1.0)
			if Input.is_action_just_pressed("interact"):
				_deal()
		"hold":
			if Input.is_action_just_pressed("left"):
				_cursor = (_cursor + 4) % 5
			elif Input.is_action_just_pressed("right"):
				_cursor = (_cursor + 1) % 5
			if Input.is_action_just_pressed("interact"):
				_draw_cards()
		"draw":
			_draw_t += delta
			if _draw_t > 0.9:
				_resolve()
		"win":
			if Input.is_action_just_pressed("interact"):
				_collect()
			elif _can_double() and Input.is_action_just_pressed("left"):
				_double("pieni")
			elif _can_double() and Input.is_action_just_pressed("right"):
				_double("suuri")
		"tupla":
			_card_t += delta
			if _card_t > 1.1:
				_double_result()
	_info.text = "POKERI · Rahaa %s €%s" % [_eur(money), "  ·  Voitto %s €" % _eur(_win) if _win > 0.0 else ""]
	match _phase:
		"idle":
			_keys.set_text("%s jaa (%d €)   %s panos +   %s panos −   %s lopeta   J ohje" % [Settings.cap("interact"), _bet, Settings.cap("forward"),
				Settings.cap("back"), Settings.cap("mount")])
		"hold":
			_keys.set_text("1–5 / klikkaus: PIDÄ   %s vaihda loput   J ohje" % Settings.cap("interact"))
		"win":
			if _can_double():
				_keys.set_text("%s voitto talteen   %s PIENI (A–6)   %s SUURI (8–K)   punainen 7 = voitot talteen" % [
					Settings.cap("interact"), Settings.cap("left"), Settings.cap("right")])
			else:
				_keys.set_text("%s voitto talteen (liian suuri tuplattavaksi)" % Settings.cap("interact"))
		_:
			_keys.set_text("")


# --- Piirto ---------------------------------------------------------------------------------------------------

func _origin() -> Vector2:
	return Vector2(_root.size.x / _k / 2.0 - 450.0, 130.0)


func _card_rect(i: int) -> Rect2:
	var o := _origin()
	return Rect2(o + Vector2(i * 180.0, 232.0), Vector2(CARD_W, CARD_H))


func _draw_root() -> void:
	var sz := _root.size
	var font := ThemeDB.fallback_font
	MG.wood(_root, Rect2(Vector2.ZERO, sz), Color(0.28, 0.17, 0.1), 90.0, 3, false)
	MG.glow(_root, Vector2(sz.x * 0.5, sz.y * 0.45), 560.0, Color(0.2, 0.9, 0.5, 0.3 + 0.1 * sin(_t * 2.0)))
	_root.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.0, 0.05, 0.25))
	_k = minf(1.0, (sz.y - 120.0) / 700.0)
	_root.draw_set_transform_matrix(Transform2D(0.0, Vector2(_k, _k), 0.0, Vector2.ZERO))
	var o := _origin()
	# Kaappi.
	var cab := Rect2(o + Vector2(-50, -90), Vector2(1000, 700))
	MG.box(_root, cab, Color(0.62, 0.1, 0.07), 20, 14, MG.OUTLINE, 3)
	MG.grad_rect(_root, Rect2(cab.position + Vector2(10, 10), Vector2(cab.size.x - 20, 60)), Color(0.08, 0.08, 0.1), Color(0.18, 0.16, 0.14))
	_root.draw_string(font, cab.position + Vector2(0, 54), "♣ POKERI · COINLINE CASINO", HORIZONTAL_ALIGNMENT_CENTER, cab.size.x, 36,
		Color(1.0, 0.8, 0.2))
	_draw_paytable(Rect2(o + Vector2(0, -10), Vector2(900, 208)), font)
	for i in 5:
		_draw_card(i, font)
	# Alapaneeli.
	var pn := Rect2(o + Vector2(0, 548), Vector2(900, 58))
	MG.solid(_root, pn, Color(0.2, 0.2, 0.24))
	var msg := _msg
	if _phase == "win" and int(_t * 3.0) % 2 == 0:
		msg = "TUPLAA?"
	_root.draw_string(font, pn.position + Vector2(14, 38), "RAHAA %s €" % _eur(money), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.3, 0.2))
	_root.draw_string(font, pn.position + Vector2(260, 38), msg, HORIZONTAL_ALIGNMENT_CENTER, 400, 26, Color(0.4, 1.0, 0.35))
	_root.draw_string(font, pn.position + Vector2(690, 38), "PANOS %d €" % _bet, HORIZONTAL_ALIGNMENT_RIGHT, 196, 26, Color(1.0, 0.9, 0.4))
	MG.sparks_draw(_root, _sparks)
	if _phase == "tupla" or (_phase == "win" and _card > 0 and _card_t > 0.0):
		_draw_double_card(o + Vector2(980, 330), font)
	_root.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_paytable(r: Rect2, font: Font) -> void:
	MG.box(_root, r, Color(0.05, 0.07, 0.2), 8, 0, Color(0.7, 0.7, 0.75), 2)
	var cur := evaluate(_hand) if _phase in ["win", "draw", "hold"] and _hand[0] >= 0 else -1
	for i in HANDS.size():
		var y := r.position.y + 22.0 + i * 23.0
		var lit: bool = (_phase == "win" and i == cur and int(_flash * 8.0) % 2 == 0) or (_phase == "win" and i == cur and _flash <= 0.0)
		if lit:
			_root.draw_rect(Rect2(Vector2(r.position.x + 8, y - 17), Vector2(r.size.x - 16, 22)), Color(1.0, 0.85, 0.2, 0.35))
		_root.draw_string(font, Vector2(r.position.x + 20, y), HANDS[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.95, 0.95, 1.0))
		for b in 5:
			var v: int = int(HANDS[i][1]) * (b + 1)
			var col := Color(1.0, 0.9, 0.3) if b + 1 == _bet else Color(0.7, 0.75, 0.9)
			_root.draw_string(font, Vector2(r.position.x + 380 + b * 100, y), str(v), HORIZONTAL_ALIGNMENT_RIGHT, 80, 19, col)

	for b in 5:
		if b + 1 == _bet:
			_root.draw_rect(Rect2(Vector2(r.position.x + 380 + b * 100 - 4, r.position.y + 4), Vector2(88, r.size.y - 8)), Color(1.0, 0.9, 0.3, 0.12))


func _draw_card(i: int, font: Font) -> void:
	var r := _card_rect(i)
	var c: int = _hand[i]
	var p := clampf(_reveal[i], 0.0, 1.0)
	var w := CARD_W * absf(cos((1.0 - p) * PI * 0.5)) if p < 1.0 else CARD_W
	var rr := Rect2(r.position + Vector2((CARD_W - w) / 2.0, 0), Vector2(maxf(w, 2.0), CARD_H))
	var face := c >= 0 and p > 0.5
	_root.draw_rect(Rect2(rr.position + Vector2(5, 7), rr.size), Color(0, 0, 0, 0.4))
	MG.box(_root, rr, Color.WHITE if face else Color(0.7, 0.1, 0.14), 10, 0, MG.OUTLINE, 2)
	if _hand[0] < 0:
		return
	if not face:
		for k in 8:
			_root.draw_line(rr.position + Vector2(8, 20 + k * 24), rr.end - Vector2(8, 200 - k * 24), Color(1, 0.8, 0.8, 0.4), 2.0)
		return
	if is_joker(c):
		_root.draw_string(font, rr.position + Vector2(0, 100), "JOKER", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 30, Color(0.7, 0.1, 0.5))
		_root.draw_string(font, rr.position + Vector2(0, 160), "★", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, 60, Color(0.95, 0.7, 0.1))
		_draw_card_marks(i, r, font)
		return
	var red := suit(c) in [1, 2]
	var col := Color(0.85, 0.08, 0.1) if red else Color(0.06, 0.06, 0.1)
	_root.draw_string(font, rr.position + Vector2(12, 40), RANKS[rank(c)], HORIZONTAL_ALIGNMENT_LEFT, -1, 38, col)
	_draw_suit(suit(c), rr.position + Vector2(30, 66), 0.5, col)
	_draw_suit(suit(c), rr.get_center() + Vector2(0, 20), 1.6, col)
	_draw_card_marks(i, r, font)


## Kortin alla: PIDÄ-painike (palaa pidetylle kortille) ja valintakehys.
func _draw_card_marks(i: int, r: Rect2, font: Font) -> void:
	if _phase == "hold" and i == _cursor:
		_root.draw_rect(r.grow(6), Color(0.4, 1.0, 0.5, 0.9), false, 4.0)
	# Oikean pokeriautomaatin suorakulmainen painike tummassa upotuksessa: palaa kirkkaana pidetylle kortille.
	var c := r.position + Vector2(CARD_W / 2.0, CARD_H + 56.0)
	var lit := _held[i] and _phase != "idle"
	var col := Color(0.95, 0.2, 0.12) if lit else Color(0.5, 0.09, 0.07)
	if lit:
		MG.glow(_root, c, 70.0, Color(1.0, 0.3, 0.15, 0.5))
	MG.box(_root, Rect2(c - Vector2(64, 30), Vector2(128, 60)), Color(0.1, 0.09, 0.09), 8, 0, Color(0.38, 0.36, 0.34), 2)
	var bt := Rect2(c - Vector2(56, 22), Vector2(112, 44))
	MG.box(_root, bt, col.darkened(0.4), 6, 0, MG.OUTLINE, 2)
	MG.box(_root, Rect2(bt.position, Vector2(bt.size.x, bt.size.y - 6)), col, 6)
	_root.draw_rect(Rect2(bt.position + Vector2(6, 4), Vector2(bt.size.x - 12, 5)), Color(1, 1, 1, 0.28 if lit else 0.12))
	_root.draw_string(font, bt.position + Vector2(0, 28), "PIDÄ", HORIZONTAL_ALIGNMENT_CENTER, bt.size.x, 20,
		Color(1.0, 0.95, 0.8) if lit else Color(0.9, 0.7, 0.6))


## Maa piirretään käsin: 0 pata, 1 hertta, 2 ruutu, 3 risti. s = mittakaava (1 = 30 px).
func _draw_suit(sv: int, c: Vector2, s: float, col: Color) -> void:
	var u := 14.0 * s
	match sv:
		1, 0:
			var dir := 1.0 if sv == 1 else -1.0
			_root.draw_circle(c + Vector2(-u * 0.55, -u * 0.35 * dir), u * 0.62, col)
			_root.draw_circle(c + Vector2(u * 0.55, -u * 0.35 * dir), u * 0.62, col)
			_root.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 1.12, -u * 0.1 * dir), c + Vector2(u * 1.12, -u * 0.1 * dir),
				c + Vector2(0, u * 1.2 * dir)]), col)
			if sv == 0:
				_root.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.35, u * 1.3), c + Vector2(u * 0.35, u * 1.3),
					c + Vector2(0, u * 0.3)]), col)
		2:
			_root.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -u * 1.2), c + Vector2(u * 0.9, 0), c + Vector2(0, u * 1.2),
				c + Vector2(-u * 0.9, 0)]), col)
		3:
			for off: Vector2 in [Vector2(0, -0.7), Vector2(-0.7, 0.2), Vector2(0.7, 0.2)]:
				_root.draw_circle(c + off * u, u * 0.58, col)
			_root.draw_colored_polygon(PackedVector2Array([c + Vector2(-u * 0.3, u * 1.3), c + Vector2(u * 0.3, u * 1.3), c + Vector2(0, 0)]), col)


## Tuplauskortti: selkä kääntyy, sitten kortin arvo.
func _draw_double_card(c: Vector2, font: Font) -> void:
	var t := clampf(_card_t / 0.6, 0.0, 1.0)
	var w := 120.0 * absf(cos(t * PI))
	var r := Rect2(c - Vector2(w / 2.0, 85), Vector2(maxf(w, 2.0), 170))
	MG.box(_root, r, Color.WHITE if t > 0.5 else Color(0.7, 0.1, 0.12), 10, 6, MG.OUTLINE, 2)
	if t <= 0.5:
		for k in 6:
			_root.draw_line(r.position + Vector2(6, 14 + k * 26), r.end - Vector2(6, 156 - k * 26), Color(1, 0.8, 0.8, 0.5), 2.0)
	elif w > 60.0:
		var names := {1: "A", 11: "J", 12: "Q", 13: "K"}
		var v: String = names.get(_card, str(_card))
		var col := Color(0.8, 0.1, 0.1) if _card_red else Color(0.08, 0.08, 0.1)
		_root.draw_string(font, r.position + Vector2(0, 108), v, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 64, col)
	_root.draw_string(font, c + Vector2(-80, 120), "Arvaus: %s" % _guess.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 160, 20, Color.WHITE)
