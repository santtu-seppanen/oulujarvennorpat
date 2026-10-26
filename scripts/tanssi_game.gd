extends CanvasLayer
## Tanssilattia Happy Beachillä: eurodance-rytmipeli diskopallon alla. Neljä askelkaistaa (← ↓ ↑ → eli A S W D tai
## nuolet): nuolet laskeutuvat osumalinjalle ja painetaan tahtiin. Biisi (138 bpm, Am–F–C–G) syntetisoidaan
## lennossa: jalkabasari joka tahdilla, klappi tahdeilla 2 ja 4, ylätahdin hattu, pumppaava basso ja kertosäkeessä
## 16-osa-arpeggio. Osuma-ajan mukaan putki (combo) ja kerroin kasvavat, ohi menneet ja väärät askeleet katkaisevat
## putken. Humala nykii painallusten ajoitusta. Tulos 0…1 finished-signaalilla (score, paras putki); pelaaja tanssii
## (dancing()) osumien aikana. Esc / F lopettaa kesken.

signal finished(score: float, best_combo: int)

const W := 1280.0
const H := 720.0
const RATE := 22050.0
const BPM := 138.0
const BEAT := 60.0 / BPM
const BARS := 20
const LEAD := BEAT * 4.0  # sisäänlasku ennen ensimmäistä askelta
const FALL := 1.7  # nuolen näkymisaika yläreunasta osumalinjalle (s)
const TOP_Y := 96.0
const HIT_Y := 470.0
const LANE_GAP := 120.0
const LANES := 4
const LANE_KEYS := [[KEY_A, KEY_LEFT], [KEY_S, KEY_DOWN], [KEY_W, KEY_UP], [KEY_D, KEY_RIGHT]]
const LANE_ANGLE := [PI, PI * 0.5, -PI * 0.5, 0.0]  # ← ↓ ↑ →
const LANE_COLS := [Color(0.95, 0.35, 0.75), Color(0.3, 0.85, 0.95), Color(0.45, 0.9, 0.4), Color(1.0, 0.65, 0.2)]
const WIN_PERFECT := 0.07
const WIN_GOOD := 0.13
const WIN_OK := 0.2
const ROOTS := [110.0, 87.31, 130.81, 98.0]  # A F C G (Hz)
const THIRDS := [3, 4, 4, 4]  # sointujen terssi (puolisävelaskelta)
const CHORUS_FROM := 8  # arpeggio alkaa tästä tahdista

var drunk := 0.0
var score := 0.0
var best_combo := 0

# Askel: {t, lane, state ("odottaa"/"osuma"/"ohi"), q}
var _notes: Array = []
var _t := -LEAD
var _done := false
var _total_w := 0.0
var _end := 0.0
var _sum := 0.0
var _hit := 0
var _miss := 0
var _combo := 0
var _meter := 0.5
var _judge := ""
var _judge_t := 0.0
var _lag := 0.0
var _last_hit := -9.0
var _flash := [0.0, 0.0, 0.0, 0.0]
var _burst: Array = []  # [kaista, aika, laatu]
var _down := [false, false, false, false]
var _draw_node: Control
var _info: Label
var _player: AudioStreamPlayer
var _pb: AudioStreamGeneratorPlayback
var _at := -LEAD
var _ph_kick := 0.0
var _ph_bass := 0.0
var _ph_lead := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("esc_lopettaa")  # Esc lopettaa pelin: taukovalikko ei aukea (menu.gd)
	layer = 20
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.02, 0.1, 0.86)
	bg.position = Vector2(0, 60)
	bg.size = Vector2(W, 470)
	add_child(bg)
	_draw_node = Control.new()
	_draw_node.size = Vector2(W, H)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.draw.connect(_draw_chart)
	add_child(_draw_node)
	_info = Label.new()
	_info.position = Vector2(330, 66)
	_info.add_theme_font_size_override("font_size", 26)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_info.add_theme_constant_override("outline_size", 8)
	add_child(_info)
	_build_chart()
	if DisplayServer.get_name() != "headless":
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = RATE
		gen.buffer_length = 0.3
		_player = AudioStreamPlayer.new()
		_player.stream = gen
		_player.volume_db = -4.0
		add_child(_player)
		_player.play()
		_pb = _player.get_stream_playback()


## Askelkartta: johdanto harvaa, säkeistö joka tahdille, kertosäkeessä myös ylätahtien askelia.
func _build_chart() -> void:
	_rng.seed = 90
	var last := -1
	var prev := -1
	for bar in BARS:
		for k in 4:
			var steps: Array = []
			if bar < 4:
				if k % 2 == 0:
					steps.append(float(k))
			else:
				steps.append(float(k))
				if bar >= 12 and k % 2 == 1:
					steps.append(k + 0.5)
			for s: float in steps:
				var lane := _rng.randi() % LANES
				while lane == last and lane == prev:
					lane = _rng.randi() % LANES
				prev = last
				last = lane
				_notes.append({"t": (bar * 4.0 + s) * BEAT, "lane": lane, "state": "odottaa", "q": 0.0})
	_total_w = _notes.size() * 1.5
	_end = BARS * 4.0 * BEAT + 1.5


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and not event.echo:
		for lane in LANES:
			if event.keycode in LANE_KEYS[lane] or event.physical_keycode in LANE_KEYS[lane]:
				if event.pressed:
					lane_press(lane)
				else:
					_down[lane] = false


## Askelkaistan painallus (myös testit kutsuvat): osuu lähimpään askeleeseen ikkunan sisällä, muuten putki katkeaa.
func lane_press(lane: int, at := -1.0) -> void:
	if _done or _down[lane]:
		return
	_down[lane] = true
	_flash[lane] = 1.0
	var t := (at if at >= 0.0 else _t) + _lag + drunk * randf_range(-0.1, 0.1)
	var best: Dictionary = {}
	var bd := WIN_OK + 0.0001
	for n in _notes:
		if n.lane != lane or n.state != "odottaa":
			continue
		var dt := absf(float(n.t) - t)
		if dt < bd:
			bd = dt
			best = n
	if best.is_empty():
		_break_combo("Ohi!")
		Sfx.play("bike_fall", -22.0, 1.6)
		return
	best.state = "osuma"
	best.q = 1.0 if bd <= WIN_PERFECT else (0.75 if bd <= WIN_GOOD else 0.5)
	_hit += 1
	_combo += 1
	best_combo = maxi(best_combo, _combo)
	_meter = minf(1.0, _meter + 0.035)
	_sum += float(best.q) * multiplier()
	_judge = "TÄYDELLINEN!" if best.q >= 1.0 else ("HYVÄ" if best.q >= 0.75 else "OK")
	_judge_t = 0.6
	_last_hit = _t
	_burst.append([lane, 0.0, best.q])
	Sfx.play("pickup", -20.0, 1.0 + lane * 0.12)


func _break_combo(text: String) -> void:
	_combo = 0
	_meter = maxf(0.0, _meter - 0.06)
	_judge = text
	_judge_t = 0.5


## Putken kerroin: ×1,0 → ×1,6 neljän osuman välein.
func multiplier() -> float:
	return 1.0 + 0.2 * clampi(_combo / 4, 0, 3)


## Pelaajan hahmo tanssii, kun viimeisestä osumasta on alle sekunti.
func dancing() -> bool:
	return _t - _last_hit < 1.0


func current_score() -> float:
	return clampf(_sum / maxf(_total_w, 0.001), 0.0, 1.0)


func _process(delta: float) -> void:
	if _done:
		return
	step(delta)
	if Input.is_action_just_pressed("mount") or Input.is_key_pressed(KEY_ESCAPE):
		_finish()


## Pelin eteneminen delta sekuntia (testit kutsuvat suoraan).
func step(delta: float) -> void:
	_t += delta
	_lag = drunk * 0.06 * (0.5 + 0.5 * sin(_t * 2.1))
	for i in LANES:
		_flash[i] = maxf(_flash[i] - delta * 5.0, 0.0)
	_judge_t = maxf(_judge_t - delta, 0.0)
	for b in _burst:
		b[1] += delta
	_burst = _burst.filter(func(b: Array) -> bool: return b[1] < 0.5)
	for n in _notes:
		if n.state == "odottaa" and _t - float(n.t) > WIN_OK:
			n.state = "ohi"
			_miss += 1
			_break_combo("Huti")
	_info.text = "TANSSILATTIA · EURODANCE    %d %%    Putki %d  ×%.1f" % [roundi(current_score() * 100.0), _combo, multiplier()]
	_fill_audio()
	_draw_node.queue_redraw()
	if _t > _end:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	score = current_score()
	if _player != null:
		_player.stop()
	finished.emit(score, best_combo)


# --- Näyttö ---------------------------------------------------------------------------------------------------

func _lane_x(lane: int) -> float:
	return W * 0.5 + (lane - 1.5) * LANE_GAP


## Nuoli (kärki oikealle) keskipisteessä c kulmaan a käännettynä.
func _arrow(c: Vector2, a: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(r, 0), Vector2(-r * 0.2, -r * 0.9), Vector2(-r * 0.2, -r * 0.4),
		Vector2(-r, -r * 0.4), Vector2(-r, r * 0.4), Vector2(-r * 0.2, r * 0.4), Vector2(-r * 0.2, r * 0.9)])
	for i in pts.size():
		pts[i] = c + pts[i].rotated(a)
	return pts


func _draw_chart() -> void:
	var pulse := 1.0 - fposmod(_t, BEAT) / BEAT
	for i in range(-1, 12):
		var y := TOP_Y + fposmod(-_t, BEAT) / FALL * (HIT_Y - TOP_Y) + i * BEAT / FALL * (HIT_Y - TOP_Y)
		if y > TOP_Y and y < HIT_Y + 30:
			_draw_node.draw_line(Vector2(_lane_x(0) - 70, y), Vector2(_lane_x(3) + 70, y), Color(1, 1, 1, 0.06), 1.0)
	for lane in LANES:
		var x := _lane_x(lane)
		_draw_node.draw_rect(Rect2(x - 52, TOP_Y, 104, HIT_Y - TOP_Y + 40), Color(1, 1, 1, 0.04))
		var c: Color = LANE_COLS[lane]
		var s: float = 1.0 + 0.1 * pulse + 0.2 * _flash[lane]
		var target := _arrow(Vector2(x, HIT_Y), LANE_ANGLE[lane], 34.0 * s)
		_draw_node.draw_polyline(target + PackedVector2Array([target[0]]), c.lightened(0.2 + 0.5 * _flash[lane]), 3.0)
	for n in _notes:
		if n.state != "odottaa":
			continue
		var y := HIT_Y - (float(n.t) - _t) / FALL * (HIT_Y - TOP_Y)
		if y < TOP_Y - 30 or y > HIT_Y + 60:
			continue
		var lane: int = n.lane
		var a := clampf((y - TOP_Y) / 60.0, 0.0, 1.0)
		var col: Color = LANE_COLS[lane]
		col.a = a
		_draw_node.draw_colored_polygon(_arrow(Vector2(_lane_x(lane), y), LANE_ANGLE[lane], 30.0), col)
	for b in _burst:
		var rad: float = 36.0 + b[1] * 120.0
		_draw_node.draw_arc(Vector2(_lane_x(b[0]), HIT_Y), rad, 0.0, TAU, 24,
			Color(1, 1, 0.6, 1.0 - b[1] * 2.0) if b[2] >= 1.0 else Color(1, 1, 1, 0.8 - b[1] * 1.6), 3.0)
	if _judge_t > 0.0:
		var font := ThemeDB.fallback_font
		_draw_node.draw_string(font, Vector2(0, HIT_Y + 90), _judge, HORIZONTAL_ALIGNMENT_CENTER, W, 40,
			Color(1, 1, 0.5, minf(1.0, _judge_t * 3.0)))
	# Lattian tunnelma: pystypalkki oikealla.
	_draw_node.draw_rect(Rect2(W - 90, TOP_Y, 26, HIT_Y - TOP_Y), Color(0, 0, 0, 0.5))
	_draw_node.draw_rect(Rect2(W - 90, TOP_Y + (HIT_Y - TOP_Y) * (1.0 - _meter), 26, (HIT_Y - TOP_Y) * _meter),
		Color(0.95, 0.3, 0.8).lerp(Color(1.0, 0.9, 0.3), _meter))
	_draw_node.draw_string(ThemeDB.fallback_font, Vector2(W - 120, TOP_Y - 8), "Lattia", HORIZONTAL_ALIGNMENT_CENTER, 90, 16)


# --- Biisi (syntetisoitu) -------------------------------------------------------------------------------------

func _fill_audio() -> void:
	if _pb == null:
		return
	var n := _pb.get_frames_available()
	for i in n:
		_at += 1.0 / RATE
		var bi := floori(_at / BEAT)
		var bt := _at - bi * BEAT
		var ot := fposmod(_at - BEAT * 0.5, BEAT)  # ylätahti
		var music := bi >= 0
		var bar := (bi / 4) % 4 if music else 0
		var kick := sin(_ph_kick) * exp(-bt * 16.0) * 0.55
		_ph_kick += TAU * (50.0 + 110.0 * exp(-bt * 28.0)) / RATE
		var s := kick
		if music:
			s += (randf() * 2.0 - 1.0) * exp(-ot * 60.0) * 0.11  # hattu ylätahdissa
			if bi % 2 == 1:
				s += (randf() * 2.0 - 1.0) * exp(-bt * 22.0) * 0.18  # klappi tahdeilla 2 ja 4
			_ph_bass = fmod(_ph_bass + ROOTS[bar] / RATE, 1.0)
			s += (_ph_bass * 2.0 - 1.0) * exp(-ot * 7.0) * 0.2  # basso pumppaa ylätahdilla
			if bi >= CHORUS_FROM * 4:
				var six := BEAT * 0.25
				var si := floori(_at / six)
				var st := _at - si * six
				var semis: int = [0, THIRDS[bar], 7, 12][si % 4]
				_ph_lead = fmod(_ph_lead + ROOTS[bar] * 2.0 * pow(2.0, semis / 12.0) / RATE, 1.0)
				s += (1.0 if _ph_lead < 0.5 else -1.0) * exp(-st * 14.0) * 0.07
		_pb.push_frame(Vector2(s, s) * 0.9)
