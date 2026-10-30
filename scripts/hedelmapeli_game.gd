extends CanvasLayer
## Hedelmäpeli (RAYn vuosina 1995–2001 pelattu kolmirullainen peli, ks. rahapeliopas.fi/nostalgia/hedelmapeli): Siitarin ja Happy Beachin
## baarin vanha kone. Jokaisessa rullassa on 24 symbolia (RAY, apila, meloni, päärynä, rypäle, luumu, appelsiini, tähti, marjat,
## mansikka; määrät rullittain kuten alkuperäisessä), yksi voittolinja keskellä ja panos 1, 2 tai 3 € (W/S). Kolme samaa maksaa
## taulukon mukaan, ja mikä tahansa kolmen hedelmän yhdistelmä (myös marjat ja mansikka) maksaa 2. Hävityn kierroksen jälkeen
## rullia voi lukita (1, 2, 3), mutta ei kahdesti peräkkäin: "lukitse aina kaksi samaa". Tuplausta ei ole.
## E pelaa. Pelaa voi myös hiirellä: alarivin napit LUKKO 1–3, PANOS, PELAA ja LOPETA (mg_napit.gd). Voitot kertyvät koneeseen ja peli jatkuu, kunnes lopetetaan (F / Esc): silloin kone maksaa kertyneet voitot ulos. finished(money): rahat pelin jälkeen.

signal finished(money: float)
signal comment(text: String)

const MG := preload("res://scripts/mg_draw.gd")
const Napit := preload("res://scripts/mg_napit.gd")

const SYMBOLS := ["ray", "apila", "meloni", "paaryna", "rypale", "luumu", "appelsiini", "tahti", "marjat", "mansikka"]
## Symbolien määrä rullilla 1, 2 ja 3 (jokaisella rullalla yhteensä 24).
const COUNTS := {
	"ray": [1, 1, 2], "apila": [2, 1, 1], "meloni": [2, 2, 3], "paaryna": [2, 2, 3], "rypale": [3, 2, 3], "luumu": [3, 3, 3],
	"appelsiini": [4, 3, 3], "tahti": [4, 4, 3], "marjat": [3, 6, 0], "mansikka": [0, 0, 3]}
## Kolme samaa, kerroin × panos.
const PAY := {"ray": 30, "apila": 20, "meloni": 20, "paaryna": 12, "rypale": 12, "luumu": 10, "appelsiini": 10, "tahti": 4}
const RAY_MAX := 100  # kolme RAYta kolmen euron panoksella (30 / 60 / 100)
const ANY_FRUIT := 2  # mikä tahansa kolme hedelmää (ei RAY, apila eikä tähti) × panos
const FRUITS := ["meloni", "paaryna", "rypale", "luumu", "appelsiini", "marjat", "mansikka"]
const NAMES := {"ray": "RAY", "apila": "Apila", "meloni": "Meloni", "paaryna": "Päärynä", "rypale": "Rypäle", "luumu": "Luumu",
	"appelsiini": "Appelsiini", "tahti": "Tähti", "marjat": "Marjat", "mansikka": "Mansikka"}
const SYM_H := 110.0       # yhden symbolin korkeus rullassa
const STOP_AT := [0.9, 1.35, 1.8]
const LINES := ["Vanha kunnon hedelmäpeli. Kolme RAYta ja Päivi saa uuden kahvinkeittimen.",
	"Seurue sano, että tänään se on ollu nuuka. Ehkä sulle se on armollinen.",
	"Lukitse aina kaksi samaa ja toivo kolmatta. Niin ne vanhat konkarit pelaa."]

var money := 10.0
var drunk := 0.0

var _root: Control
var _info: Label
var _keys: Control
var _tip: Label
var _strips: Array = [[], [], []]   # rullanauhat (24 symbolia kullakin rullalla)
var _bet := 1
var _pos: Array[float] = [0.0, 0.0, 0.0]   # rullan asento symboleina (desimaali = välissä)
var _target: Array[int] = [0, 0, 0]
var _spin_from: Array[float] = [0.0, 0.0, 0.0]
var _stopped: Array[bool] = [true, true, true]
var _locked: Array[bool] = [false, false, false]
var _lock_ok := false            # lukitus sallittu (edellinen kierros hävisi eikä ollut lukittu)
var _was_locked := false
## Vaihe: "idle" (odottaa panosta), "spin". _win = koneeseen kertyneet voitot, jotka maksetaan lopettaessa.
var _phase := "idle"
var _spin_t := 0.0
var _win := 0.0
var _t := 0.0
var _done := false
var _flash := 0.0
var _shake := 0.0
var _sparks: Array = []
var _coins: Array = []           # tarjottimelle putoavat kolikot [paikka, nopeus, viive]
var _tray := 0
var _msg := ""
var _btn_flash := ""
var _napit := Napit.new()
var _closing := false            # voitot putoavat tarjottimelle ennen sulkeutumista
var _closing_t := 0.0


func _ready() -> void:
	add_to_group("esc_lopettaa")  # Esc lopettaa pelin: taukovalikko ei aukea (menu.gd)
	layer = 6
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.draw.connect(_draw_root)
	_root.gui_input.connect(func(e: InputEvent) -> void:
		if not _done and not _closing:
			_napit.input(e, _k))
	add_child(_root)
	_info = _label(24, 30.0, false)
	_keys = preload("res://scripts/hint_bar.gd").new()  # näppäinohjeet hattuina, näppäimet asetuksista
	_keys.compact = true
	_keys.centered = true
	add_child(_keys)
	_tip = _label(22, -90.0, true)
	_tip.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	comment.connect(func(t: String) -> void: _tip.text = t)
	var rng := RandomNumberGenerator.new()
	for r in 3:
		var strip: Array = _strips[r]
		for sym: String in SYMBOLS:
			for k in int(COUNTS[sym][r]):
				strip.append(sym)
		rng.seed = 77 + r * 13
		for i in range(strip.size() - 1, 0, -1):  # sekoitettu, mutta aina samat nauhat
			var j := rng.randi_range(0, i)
			var tmp: String = strip[i]
			strip[i] = strip[j]
			strip[j] = tmp
		_pos[r] = float(randi() % strip.size())
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


func _sym(r: int, off := 0) -> String:
	var strip: Array = _strips[r]
	var n := strip.size()
	return strip[(int(roundf(_pos[r])) + off + n * 4) % n]


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_root.queue_redraw()
	_flash = maxf(0.0, _flash - delta)
	_shake = maxf(0.0, _shake - delta * 3.0)
	MG.sparks_step(_sparks, delta)
	_coin_step(delta)
	if _closing:
		_closing_t += delta
		# Kolikot ovat tarjottimella (tai kärsivällisyys loppui): peli päättyy.
		if _coins.is_empty() or _closing_t > 8.0:
			_close_now()
		return
	if Input.is_action_just_pressed("mount") or Input.is_key_pressed(KEY_ESCAPE):
		if _phase == "spin":
			return
		_finish()
		return
	match _phase:
		"idle":
			if _lock_ok:
				for r in 3:
					if Input.is_key_pressed(KEY_1 + r) and not _key_held(r):
						_toggle_lock(r)
				_held = [Input.is_key_pressed(KEY_1), Input.is_key_pressed(KEY_2), Input.is_key_pressed(KEY_3)]
			if Input.is_action_just_pressed("forward") and _bet < 3:
				_bet += 1
				_msg = "PANOS %d €" % _bet
				Sfx.play("pickup", -12.0, 1.2)
			elif Input.is_action_just_pressed("back") and _bet > 1:
				_bet -= 1
				_msg = "PANOS %d €" % _bet
				Sfx.play("pickup", -12.0, 1.0)
			if Input.is_action_just_pressed("interact"):
				_play()
		"spin":
			_spin_step(delta)
	_info.text = "HEDELMÄPELI · Rahaa %s €%s" % [_eur(money), "  ·  Voitot %s €" % _eur(_win) if _win > 0.0 else ""]
	match _phase:
		"idle":
			_keys.set_text("%s pelaa (%d €)   %s/%s panos%s   %s lopeta ja ota voitot   J ohje" % [Settings.cap("interact"), _bet, Settings.cap("forward"),
				Settings.cap("back"), "   [1] [2] [3] lukitse rulla" if _lock_ok else "", Settings.cap("mount")])
		_:
			_keys.set_text("")


var _held := [false, false, false]


func _toggle_lock(r: int) -> void:
	if _phase != "idle" or not _lock_ok:
		return
	_locked[r] = not _locked[r]
	_btn_flash = "lukko%d" % r
	Sfx.play("pickup", -12.0, 1.4)


func _press_bet() -> void:
	if _phase != "idle":
		return
	_bet = _bet % 3 + 1
	_msg = "PANOS %d €" % _bet
	Sfx.play("pickup", -12.0, 1.2)


func _press_play() -> void:
	if _phase == "idle":
		_play()


func _press_quit() -> void:
	if _phase != "spin":
		_finish()


func _key_held(r: int) -> bool:
	return _held[r]


func _eur(v: float) -> String:
	return ("%.2f" % v).replace(".", ",").trim_suffix(",00")


func _play() -> void:
	if money < float(_bet):
		if money >= 1.0:
			_bet = int(money)
			_msg = "PANOS %d €" % _bet
			comment.emit("Rahat eivät riitä: panos laski %d euroon." % _bet)
			return
		comment.emit("Rahat loppu. Kone vilkuttaa valojaan, mutta velaksi se ei pelaa.")
		return
	money -= float(_bet)
	_was_locked = _locked.has(true)
	Sfx.play("coin", -10.0, 1.3)
	Sfx.play("rattle", -14.0, 1.2)
	_phase = "spin"
	_spin_t = 0.0
	_msg = ""
	var n: int = _strips[0].size()
	for r in 3:
		_stopped[r] = _locked[r]
		_spin_from[r] = _pos[r]
		# Pysähdyskohta arvotaan, ja rulla pyörii sinne vähintään kolme kierrosta.
		_target[r] = int(roundf(_pos[r])) if _locked[r] else int(_pos[r]) + n * (3 + r) + randi() % n


func _spin_step(delta: float) -> void:
	_spin_t += delta
	var n: int = _strips[0].size()
	for r in 3:
		if _stopped[r]:
			continue
		var t := clampf(_spin_t / STOP_AT[r], 0.0, 1.0)
		# Nopea pyöritys, joka hidastuu pysähdyskohtaan, ja lopussa pieni nytkähdys (mekaaninen pysäytin).
		var e := 1.0 - pow(1.0 - t, 3.0)
		_pos[r] = lerpf(_spin_from[r], float(_target[r]), e) + (sin(t * PI * 3.0) * 0.06 if t > 0.85 else 0.0)
		if t >= 1.0:
			_stopped[r] = true
			_pos[r] = float(_target[r] % n)
			_shake = 0.25
			Sfx.play("pickup", -8.0, 0.8 + r * 0.1)
	if not _stopped.has(false):
		_resolve()


## Linjan voitto euroina (panos mukana laskettuna).
static func line_win(a: String, b: String, c: String, bet: int) -> int:
	if a == b and b == c and PAY.has(a):
		return RAY_MAX if a == "ray" and bet == 3 else int(PAY[a]) * bet
	if a in FRUITS and b in FRUITS and c in FRUITS:
		return ANY_FRUIT * bet
	return 0


func _resolve() -> void:
	var a := _sym(0)
	var b := _sym(1)
	var c := _sym(2)
	var w := float(line_win(a, b, c, _bet))
	_win += w
	_locked = [false, false, false]
	if w > 0.0:
		_phase = "idle"
		_lock_ok = false
		_flash = 1.5
		_msg = "VOITTO %s €" % _eur(w)
		if w >= 10.0 * _bet:
			Sfx.play("win", -4.0)
			MG.sparks_burst(_sparks, _reel_rect(1).get_center(), Color(1.0, 0.85, 0.2), 50)
			comment.emit("Kolme %s! Koneen valot vilkkuu ja koko baari kuulee." % NAMES[a].to_lower() if a == b and b == c else
				"Hyvä voitto!")
		else:
			Sfx.play("win_small", -6.0)
			MG.sparks_burst(_sparks, _reel_rect(0).get_center(), Color(1.0, 0.4, 0.4), 16)
	else:
		_phase = "idle"
		_lock_ok = not _was_locked
		_msg = "LUKITSE?" if _lock_ok else "PANOS %d €" % _bet
		if _lock_ok and (a == b or b == c or a == c):
			comment.emit("Kaksi samaa! Lukitse ne (1 2 3) ja yritä kolmatta.")


func _pay(amount: float) -> void:
	var n := int(amount)
	for k in n:
		_coins.append([_tray_rect().get_center() + Vector2(randf_range(-40, 40), -150.0), Vector2(randf_range(-60, 60), randf_range(-120, 0)),
			-k * minf(0.07, 2.5 / n)])
	money += amount - n  # sentit suoraan


func _coin_step(delta: float) -> void:
	for c in _coins:
		c[2] += delta
		if c[2] < 0.0:
			continue
		c[1].y += 900.0 * delta
		c[0] += c[1] * delta
	for i in range(_coins.size() - 1, -1, -1):
		var c: Array = _coins[i]
		if c[2] > 0.0 and c[0].y > _tray_rect().end.y - 12.0:
			_coins.remove_at(i)
			_tray += 1
			money += 1.0
			Sfx.play("coin", -12.0, randf_range(0.9, 1.3))


## Lopetus: kertyneet voitot putoavat ensin tarjottimelle, sitten peli sulkeutuu.
func _finish() -> void:
	if _win >= 1.0:
		_pay(_win)
		_win = 0.0
		_closing = true
		_msg = "VOITOT ULOS"
		_phase = "idle"
		return
	_close_now()


func _exit_tree() -> void:
	_napit.release_all()


func _close_now() -> void:
	money += _win + _coins.size()
	_coins.clear()
	_done = true
	finished.emit(money)
	queue_free()


# --- Piirto -------------------------------------------------------------------

## Kaappi piirretään 600 x 800 -kehykseen, joka skaalataan ruudun korkeuteen (ylhäällä otsikko, alhaalla vinkki ja napit).
var _k := 1.0


func _cab() -> Rect2:
	var vs := _root.size / _k
	return Rect2(Vector2(vs.x / 2.0 - 300, 62.0 / _k), Vector2(600, 800))


func _reel_rect(r: int) -> Rect2:
	var c := _cab()
	return Rect2(c.position + Vector2(66 + r * 166, 330), Vector2(136, 230))


func _tray_rect() -> Rect2:
	var c := _cab()
	return Rect2(c.position + Vector2(140, c.size.y - 70), Vector2(320, 46))


func _draw_root() -> void:
	var sz := _root.size
	var font := ThemeDB.fallback_font
	_draw_bar_wall(sz)
	_k = minf(1.0, (sz.y - 170.0) / 800.0)
	var cab := _cab()
	var sh := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 4.0
	_root.draw_set_transform_matrix(Transform2D(0.0, Vector2(_k, _k), 0.0, sh))
	_root.draw_rect(Rect2(cab.position + Vector2(20, cab.size.y - 10), Vector2(cab.size.x - 40, sz.y)), Color(0.04, 0.03, 0.03, 0.7))
	# Kaappi: musta lakkapinta, kromireunat ja punaiset sivupaneelit.
	MG.box(_root, cab, Color(0.08, 0.08, 0.1), 22, 16, MG.OUTLINE, 3)
	MG.grad_rect(_root, Rect2(cab.position + Vector2(10, 10), Vector2(30, cab.size.y - 20)), Color(0.85, 0.15, 0.15), Color(0.45, 0.05, 0.05))
	MG.grad_rect(_root, Rect2(Vector2(cab.end.x - 40, cab.position.y + 10), Vector2(30, cab.size.y - 20)), Color(0.85, 0.15, 0.15),
		Color(0.45, 0.05, 0.05))
	_draw_marquee(Rect2(cab.position + Vector2(50, 20), Vector2(cab.size.x - 100, 120)), font)
	_draw_paytable(Rect2(cab.position + Vector2(50, 150), Vector2(cab.size.x - 100, 160)), font)
	# Rullaikkuna.
	var win_r := Rect2(cab.position + Vector2(50, 318), Vector2(cab.size.x - 100, 254))
	MG.box(_root, win_r.grow(6), Color(0.75, 0.76, 0.8), 14, 0, MG.OUTLINE, 3)
	MG.box(_root, win_r, Color(0.05, 0.05, 0.06), 10)
	for r in 3:
		_draw_reel(r, font)
	# Voittolinja.
	var ly := _reel_rect(0).get_center().y
	var lc := Color(1.0, 0.85, 0.2) if _flash > 0.0 and int(_flash * 8.0) % 2 == 0 else Color(0.95, 0.15, 0.1)
	_root.draw_line(Vector2(win_r.position.x - 4, ly), Vector2(win_r.end.x + 4, ly), lc, 4.0)
	for x in [win_r.position.x - 14, win_r.end.x + 14]:
		_root.draw_colored_polygon(PackedVector2Array([Vector2(x, ly - 10), Vector2(x, ly + 10),
			Vector2(x + (12 if x < win_r.position.x else -12), ly)]), lc)
	# Lasin kiilto.
	_root.draw_colored_polygon(PackedVector2Array([win_r.position + Vector2(20, 0), win_r.position + Vector2(90, 0),
		win_r.position + Vector2(30, win_r.size.y), win_r.position + Vector2(-10, win_r.size.y)]), Color(1, 1, 1, 0.06))
	_draw_panel(Rect2(cab.position + Vector2(50, 586), Vector2(cab.size.x - 100, 132)), font)
	_draw_tray(font)
	for c in _coins:
		if c[2] >= 0.0:
			MG.ball(_root, c[0], 10.0, Color(0.92, 0.78, 0.35), 0.6)
	MG.sparks_draw(_root, _sparks)
	_root.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_bar_wall(sz: Vector2) -> void:
	MG.wood(_root, Rect2(Vector2.ZERO, sz), Color(0.3, 0.18, 0.1), 90.0, 5, false)
	MG.grad_rect(_root, Rect2(Vector2(0, sz.y * 0.84), Vector2(sz.x, sz.y * 0.16)), Color(0.22, 0.14, 0.09), Color(0.12, 0.08, 0.05))
	_root.draw_line(Vector2(0, sz.y * 0.84), Vector2(sz.x, sz.y * 0.84), Color(0.1, 0.06, 0.03), 4.0)
	MG.glow(_root, Vector2(sz.x * 0.5, sz.y * 0.4), 520.0, Color(1.0, 0.4, 0.5, 0.35 + 0.15 * sin(_t * 3.0)))
	# Siitari-kyltti seinällä ja pajatson punainen kylki oikealla.
	MG.sign(_root, Rect2(Vector2(sz.x * 0.05, sz.y * 0.12), Vector2(220, 70)), "SIITARI", Color(0.55, 0.05, 0.06), Color(1.0, 0.92, 0.6), 40,
		Color(0.3, 0.02, 0.03))
	var pj := Rect2(Vector2(sz.x * 0.86, sz.y * 0.2), Vector2(sz.x * 0.2, sz.y * 0.66))
	MG.box(_root, pj, Color(0.6, 0.1, 0.1), 14, 8, MG.OUTLINE, 3)
	MG.box(_root, Rect2(pj.position + Vector2(20, 40), Vector2(pj.size.x - 40, pj.size.y * 0.5)), Color(0.95, 0.88, 0.6), 8)
	_root.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.0, 0.0, 0.05, 0.3))


## Valaistu yläpaneeli: HEDELMÄPELI-teksti ja maalatut hedelmät, reunoilla juoksevat lamput.
func _draw_marquee(r: Rect2, font: Font) -> void:
	MG.box(_root, r, Color(0.15, 0.05, 0.3), 12, 0, Color(0.95, 0.8, 0.3), 4)
	MG.grad_rect(_root, r.grow(-8), Color(0.95, 0.35, 0.15), Color(0.6, 0.08, 0.2))
	MG.glow(_root, r.get_center(), r.size.x * 0.45, Color(1.0, 0.95, 0.6, 0.5))
	for k in 20:
		var x := r.position.x + 14.0 + k * (r.size.x - 28.0) / 19.0
		var on := int(_t * 6.0 + k) % 4 < 2 or _flash > 0.0
		_root.draw_circle(Vector2(x, r.position.y + 8), 5.0, Color(1.0, 0.95, 0.5) if on else Color(0.45, 0.3, 0.1))
		_root.draw_circle(Vector2(x, r.end.y - 8), 5.0, Color(1.0, 0.95, 0.5) if not on else Color(0.45, 0.3, 0.1))
	_draw_symbol("mansikka", Vector2(r.position.x + 52, r.get_center().y), 0.6)
	_draw_symbol("ray", Vector2(r.end.x - 52, r.get_center().y), 0.6)
	var tp := Vector2(r.position.x, r.get_center().y + 22)
	_root.draw_string_outline(font, tp, "HEDELMÄPELI", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 54, 12, Color(0.3, 0.02, 0.05))
	_root.draw_string(font, tp, "HEDELMÄPELI", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 54, Color(1.0, 0.92, 0.3))


## Voittotaulukko: kolme samaa = voitto panoksella 1 / 2 / 3 €, lisäksi mikä tahansa kolme hedelmää.
func _draw_paytable(r: Rect2, font: Font) -> void:
	MG.box(_root, r, Color(0.06, 0.08, 0.2), 8, 0, Color(0.7, 0.7, 0.75), 2)
	var order := ["ray", "apila", "meloni", "paaryna", "rypale", "luumu", "appelsiini", "tahti"]
	for i in order.size():
		var col := i % 2
		var row := i / 2
		var p := r.position + Vector2(12 + col * 250, 10 + row * 34)
		var lit: bool = _flash > 0.0 and _sym(0) == order[i] and _sym(1) == order[i] and _sym(2) == order[i] and int(_flash * 8.0) % 2 == 0
		if lit:
			MG.box(_root, Rect2(p - Vector2(4, 2), Vector2(240, 32)), Color(1.0, 0.85, 0.2, 0.5), 6)
		for k in 3:
			_draw_symbol(order[i], p + Vector2(14 + k * 26, 14), 0.2)
		var v: int = int(PAY[order[i]])
		_root.draw_string(font, p + Vector2(92, 22), "%d / %d / %d €" % [v, v * 2, RAY_MAX if i == 0 else v * 3], HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
			Color(1.0, 0.9, 0.4) if _bet > 0 else Color.WHITE)
	_root.draw_string(font, r.position + Vector2(0, r.size.y - 6), "Mikä tahansa kolme hedelmää %d / %d / %d €" % [ANY_FRUIT, ANY_FRUIT * 2, ANY_FRUIT * 3],
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, Color(0.9, 0.9, 0.95))


## Rulla: valkoinen kaareva nauha (tumma ylä- ja alareuna = lieriö), kolme symbolia näkyvissä.
func _draw_reel(r: int, _font: Font) -> void:
	var rr := _reel_rect(r)
	_root.draw_rect(rr, Color(0.97, 0.96, 0.92))
	var strip: Array = _strips[r]
	var n := strip.size()
	var base := floorf(_pos[r])
	var frac := _pos[r] - base
	var blur: bool = not _stopped[r] and _spin_t > 0.1 and _spin_t < STOP_AT[r] - 0.25
	for k in range(-2, 3):
		var y := rr.get_center().y - (k - frac) * SYM_H
		if absf(y - rr.get_center().y) > rr.size.y * 0.5 - 20.0:  # ei rullan reunan yli
			continue
		var sym: String = strip[(int(base) + k + n * 8) % n]
		var squash := 1.0 - absf(y - rr.get_center().y) / (rr.size.y * 0.9)
		if blur:
			_draw_symbol(sym, Vector2(rr.get_center().x, y), 0.5 * squash, 0.35)
			_draw_symbol(sym, Vector2(rr.get_center().x, y + 18), 0.5 * squash, 0.25)
		else:
			_draw_symbol(sym, Vector2(rr.get_center().x, y), 0.5 * maxf(squash, 0.3))
	# Lieriön varjostus ylhäältä ja alhaalta.
	MG.grad_rect(_root, Rect2(rr.position, Vector2(rr.size.x, 70)), Color(0.05, 0.05, 0.06, 0.95), Color(0.05, 0.05, 0.06, 0.0))
	MG.grad_rect(_root, Rect2(rr.position + Vector2(0, rr.size.y - 70), Vector2(rr.size.x, 70)), Color(0.05, 0.05, 0.06, 0.0),
		Color(0.05, 0.05, 0.06, 0.95))
	_root.draw_rect(Rect2(rr.position + Vector2(rr.size.x - 14, 0), Vector2(14, rr.size.y)), Color(0, 0, 0, 0.18))
	_root.draw_rect(rr, MG.OUTLINE, false, 2.0)
	# Lukituslamppu rullan alla.
	var lp := Vector2(rr.get_center().x, rr.end.y + 4)
	if _locked[r]:
		MG.glow(_root, lp, 40.0, Color(1.0, 0.3, 0.2, 0.9))
		MG.sign(_root, Rect2(lp + Vector2(-46, -22), Vector2(92, 24)), "LUKITTU", Color(0.75, 0.08, 0.06), Color(1, 0.95, 0.8), 15,
			Color(0.95, 0.8, 0.3))


## Ohjauspaneeli: rahanäyttö (LED), viestinäyttö ja isot valaistut napit.
func _draw_panel(r: Rect2, font: Font) -> void:
	MG.solid(_root, r, Color(0.2, 0.2, 0.22))
	var led := Rect2(r.position + Vector2(14, 12), Vector2(150, 44))
	MG.box(_root, led, Color(0.08, 0.02, 0.02), 4, 0, Color(0.4, 0.4, 0.42), 2)
	_root.draw_string(font, led.position + Vector2(0, -2), "RAHAA", HORIZONTAL_ALIGNMENT_CENTER, led.size.x, 12, Color(0.8, 0.8, 0.8))
	_root.draw_string(font, led.position + Vector2(0, 34), "%s €" % _eur(money), HORIZONTAL_ALIGNMENT_CENTER, led.size.x, 28, Color(1.0, 0.25, 0.15))
	var msg := Rect2(r.position + Vector2(180, 12), Vector2(r.size.x - 194, 44))
	MG.box(_root, msg, Color(0.02, 0.06, 0.02), 4, 0, Color(0.4, 0.4, 0.42), 2)
	var mtxt := _msg
	_root.draw_string(font, msg.position + Vector2(0, 32), mtxt, HORIZONTAL_ALIGNMENT_CENTER, msg.size.x, 26, Color(0.4, 1.0, 0.35))
	# Napit (hiirellä painettavat, pokerin tyyliin neliskanttiset): lukot, panos, PELAA ja LOPETA.
	_layout_buttons(r)
	_napit.draw(_root, font, _t)


func _layout_buttons(r: Rect2) -> void:
	var y := r.position.y + 66.0
	var idle := _phase == "idle" and not _closing
	_napit.list.clear()
	var x := r.position.x + 18.0
	for k in 3:
		var b := {"r": Rect2(Vector2(x, y), Vector2(54, 48)), "label": "%d" % (k + 1), "sub": "LUKKO", "col": Color(0.95, 0.93, 0.8),
			"lit": _locked[k] or (_lock_ok and idle and int(_t * 2.0) % 2 == 0)}
		if idle:
			b["call"] = _toggle_lock.bind(k)
		_napit.list.append(b)
		x += 60.0
	x += 8.0
	var pb := {"r": Rect2(Vector2(x, y), Vector2(90, 48)), "label": "PANOS", "sub": "%d €" % _bet, "col": Color(0.25, 0.6, 1.0), "lit": idle}
	var gb := {"r": Rect2(Vector2(x + 102.0, y), Vector2(100, 48)), "label": "PELAA", "col": Color(0.25, 0.85, 0.3), "lit": idle, "blink": idle}
	var qb := {"r": Rect2(Vector2(x + 214.0, y), Vector2(72, 48)), "label": "LOPETA", "col": Color(0.9, 0.2, 0.15),
		"lit": _phase != "spin" and not _closing}
	if idle:
		pb["call"] = _press_bet
		gb["call"] = _press_play
	if _phase != "spin" and not _closing:
		qb["call"] = _press_quit
	_napit.list.append_array([pb, gb, qb])


func _draw_tray(font: Font) -> void:
	var r := _tray_rect()
	MG.box(_root, r.grow(5), Color(0.25, 0.25, 0.28), 10, 0, MG.OUTLINE, 2)
	MG.grad_rect(_root, r, Color(0.7, 0.72, 0.76), Color(0.4, 0.42, 0.46))
	_root.draw_rect(Rect2(r.position + Vector2(r.size.x / 2.0 - 40, -14), Vector2(80, 14)), Color(0.05, 0.05, 0.05))
	for k in mini(_tray, 40):
		var p := r.position + Vector2(r.size.x / 2.0 + ((k * 37) % 120 - 60) * 2.0, r.size.y - 9 - (k / 8) * 4)
		var pts := PackedVector2Array()
		for j in 14:
			pts.append(p + Vector2(cos(TAU * j / 14.0) * 10.0, sin(TAU * j / 14.0) * 3.5))
		_root.draw_colored_polygon(pts, Color(0.88, 0.74, 0.32))
	if _tray > 0:
		_root.draw_string(font, r.position + Vector2(0, r.size.y + 24), "Tarjottimella %d €" % _tray, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18,
			Color(1, 0.92, 0.6))


## Symbolit piirretään käsin: sävytys, ääriviivat ja kiilto. s = mittakaava (1 = 100 px), a = läpinäkyvyys.
func _draw_symbol(sym: String, c: Vector2, s: float, a := 1.0) -> void:
	var o := Color(MG.OUTLINE.r, MG.OUTLINE.g, MG.OUTLINE.b, a)
	var ac := func(col: Color) -> Color: return Color(col.r, col.g, col.b, col.a * a)
	match sym:
		"ray":
			var rr := Rect2(c - Vector2(46, 24) * s, Vector2(92, 48) * s)
			MG.box(_root, rr.grow(3.0 * s), ac.call(Color(0.95, 0.85, 0.3)), int(8 * s))
			MG.box(_root, rr, ac.call(Color(0.75, 0.05, 0.08)), int(6 * s))
			_root.draw_string(ThemeDB.fallback_font, rr.position + Vector2(0, rr.size.y * 0.76), "RAY", HORIZONTAL_ALIGNMENT_CENTER, rr.size.x,
				int(38 * s), ac.call(Color(1, 1, 1)))
		"apila":
			for off: Vector2 in [Vector2(0, -20), Vector2(-20, 0), Vector2(20, 0), Vector2(0, 20)]:
				_root.draw_circle(c + off * s, 19.0 * s, ac.call(Color(0.1, 0.45, 0.12)))
				_root.draw_circle(c + (off - Vector2(2, 2)) * s, 16.0 * s, ac.call(Color(0.25, 0.75, 0.25)))
			_root.draw_line(c + Vector2(0, 6) * s, c + Vector2(10, 44) * s, ac.call(Color(0.1, 0.4, 0.1)), 5.0 * s)
		"paaryna":
			_root.draw_circle(c + Vector2(0, 16) * s, 28.0 * s, ac.call(Color(0.6, 0.65, 0.1)))
			_root.draw_circle(c + Vector2(-2, 14) * s, 25.0 * s, ac.call(Color(0.85, 0.9, 0.25)))
			_root.draw_circle(c + Vector2(0, -14) * s, 17.0 * s, ac.call(Color(0.6, 0.65, 0.1)))
			_root.draw_circle(c + Vector2(-1, -15) * s, 14.5 * s, ac.call(Color(0.85, 0.9, 0.25)))
			_root.draw_circle(c + Vector2(-10, 8) * s, 7.0 * s, ac.call(Color(1, 1, 0.8)))
			_root.draw_line(c + Vector2(0, -30) * s, c + Vector2(5, -46) * s, ac.call(Color(0.35, 0.25, 0.1)), 4.0 * s)
			_leaf(c + Vector2(14, -42) * s, s, ac.call(Color(0.3, 0.65, 0.2)), o)
		"tahti":
			var sp := PackedVector2Array()
			for k in 10:
				var rad := 42.0 if k % 2 == 0 else 18.0
				var ang := -PI / 2.0 + k * PI / 5.0
				sp.append(c + Vector2(cos(ang), sin(ang)) * rad * s)
			_root.draw_colored_polygon(sp, ac.call(Color(1.0, 0.85, 0.15)))
			sp.append(sp[0])
			_root.draw_polyline(sp, o, 2.5, true)
			_root.draw_circle(c + Vector2(-8, -10) * s, 6.0 * s, ac.call(Color(1, 1, 0.8)))
		"marjat":
			for p: Vector2 in [Vector2(-20, 14), Vector2(18, 16), Vector2(0, -8), Vector2(-4, 34), Vector2(24, -10)]:
				_root.draw_circle(c + p * s, 16.0 * s, ac.call(Color(0.12, 0.12, 0.4)))
				_root.draw_circle(c + (p - Vector2(2, 2)) * s, 13.5 * s, ac.call(Color(0.25, 0.3, 0.75)))
				_root.draw_circle(c + (p - Vector2(6, 6)) * s, 4.0 * s, ac.call(Color(0.8, 0.85, 1.0)))
			_leaf(c + Vector2(-2, -30) * s, s * 1.3, ac.call(Color(0.3, 0.65, 0.2)), o)
		"mansikka":
			var bp := PackedVector2Array([c + Vector2(-34, -22) * s, c + Vector2(34, -22) * s, c + Vector2(24, 18) * s, c + Vector2(0, 44) * s,
				c + Vector2(-24, 18) * s])
			_root.draw_colored_polygon(bp, ac.call(Color(0.85, 0.08, 0.14)))
			_root.draw_circle(c + Vector2(-20, -16) * s, 14.0 * s, ac.call(Color(0.85, 0.08, 0.14)))
			_root.draw_circle(c + Vector2(20, -16) * s, 14.0 * s, ac.call(Color(0.85, 0.08, 0.14)))
			for k in 7:
				var q := c + Vector2(-18 + (k % 3) * 18, -8 + (k / 3) * 16) * s
				_root.draw_circle(q, 2.0 * s, ac.call(Color(1.0, 0.9, 0.5)))
			_leaf(c + Vector2(-12, -32) * s, s * 1.2, ac.call(Color(0.25, 0.6, 0.2)), o)
			_leaf(c + Vector2(12, -32) * s, s * 1.2, ac.call(Color(0.3, 0.65, 0.2)), o)
		"appelsiini":
			_root.draw_circle(c, 38.0 * s, ac.call(Color(0.8, 0.35, 0.02)))
			_root.draw_circle(c - Vector2(3, 3) * s, 34.0 * s, ac.call(Color(1.0, 0.55, 0.08)))
			for k in 8:
				var p := c + Vector2(cos(k * 2.3), sin(k * 1.7)) * 20.0 * s
				_root.draw_circle(p, 1.8 * s, ac.call(Color(0.85, 0.4, 0.02)))
			_root.draw_circle(c + Vector2(-12, -14) * s, 8.0 * s, ac.call(Color(1, 0.85, 0.55)))
			_leaf(c + Vector2(8, -38) * s, s, ac.call(Color(0.3, 0.65, 0.2)), o)
			_root.draw_arc(c, 38.0 * s, 0, TAU, 28, o, 2.0, true)
		"luumu":
			_ellipse(c, Vector2(32, 38) * s, ac.call(Color(0.3, 0.08, 0.35)), o)
			_ellipse(c - Vector2(3, 3) * s, Vector2(28, 34) * s, ac.call(Color(0.5, 0.15, 0.55)), Color.TRANSPARENT)
			_root.draw_arc(c + Vector2(6, 0) * s, 26.0 * s, -1.4, 1.2, 12, ac.call(Color(0.32, 0.08, 0.36)), 3.0 * s)
			_root.draw_circle(c + Vector2(-12, -16) * s, 6.0 * s, ac.call(Color(0.85, 0.65, 0.9)))
			_root.draw_line(c + Vector2(0, -36) * s, c + Vector2(4, -46) * s, ac.call(Color(0.35, 0.25, 0.1)), 4.0 * s)
		"rypale":
			_root.draw_line(c + Vector2(0, -34) * s, c + Vector2(4, -48) * s, ac.call(Color(0.35, 0.25, 0.1)), 4.0 * s)
			_leaf(c + Vector2(-14, -40) * s, s, ac.call(Color(0.3, 0.65, 0.2)), o)
			for row in 4:
				for k in 4 - row:
					var p := c + Vector2((k - (3 - row) / 2.0) * 20.0, -22.0 + row * 17.0) * s
					_root.draw_circle(p, 11.0 * s, ac.call(Color(0.22, 0.08, 0.3)))
					_root.draw_circle(p - Vector2(1, 1) * s, 9.5 * s, ac.call(Color(0.45, 0.2, 0.6)))
					_root.draw_circle(p - Vector2(4, 4) * s, 3.0 * s, ac.call(Color(0.85, 0.75, 0.95)))
		"meloni":
			# Vesimelonin viipale: vihreä kuori, vaalea raja, punainen malto ja siemenet.
			_wedge(c + Vector2(0, -16) * s, 46.0 * s, ac.call(Color(0.15, 0.5, 0.15)))
			_wedge(c + Vector2(0, -16) * s, 40.0 * s, ac.call(Color(0.9, 0.95, 0.75)))
			_wedge(c + Vector2(0, -16) * s, 35.0 * s, ac.call(Color(0.92, 0.18, 0.22)))
			for k in 5:
				var a2 := 0.4 + k * 0.58
				_ellipse(c + Vector2(0, -16) * s + Vector2(cos(a2), sin(a2)) * 20.0 * s, Vector2(2.5, 4.0) * s, ac.call(Color(0.1, 0.05, 0.05)),
					Color.TRANSPARENT)
			_root.draw_line(c + Vector2(-46, -16) * s, c + Vector2(46, -16) * s, o, 2.0)


func _leaf(c: Vector2, s: float, col: Color, o: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-10, 0) * s, c + Vector2(0, -8) * s, c + Vector2(14, -4) * s, c + Vector2(4, 6) * s])
	_root.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	_root.draw_polyline(pts, o, 1.5, true)


func _ellipse(c: Vector2, r: Vector2, col: Color, o: Color) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	_root.draw_colored_polygon(pts, col)
	if o.a > 0.0:
		pts.append(pts[0])
		_root.draw_polyline(pts, o, 2.0, true)


## Puoliympyrä alaspäin (melonin viipale).
func _wedge(c: Vector2, rad: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 17:
		var a := PI * k / 16.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	_root.draw_colored_polygon(pts, col)
