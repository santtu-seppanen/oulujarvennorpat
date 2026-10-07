extends Node
## Tutkimusmatkan musiikki: Vangeliksen Chariots of Fire (assets/music/chariots_of_fire.ogg, OGG Vorbis q2,
## 2,5 MB, hiljainen häntä leikattu). Kappale sovitetaan matkaan:
## - Matka alkaa intron kanssa, kun porukka kahlaa veteen.
## - Jos soutu venyy, ennen loppuhäivytystä (LOOP_FROM) palataan täyden teeman alkuun (LOOP_TO). Kohdat on haettu
##   iskujen verhokäyrän ristikorrelaatiolla, joten isku jatkuu ristihäivytyksen yli tasaisena.
## - Perillä (arrive) siirrytään viimeiseen teemaan (FINALE), joka soi juhlien ajan kappaleen omaan häivytykseen.
## Kaksi soitinta vuorotellen ristihäivytystä varten. Ilman tiedostoa soi syntetisoitu kappale samassa hengessä
## (Des-duuri, 69 bpm): sykkivä pianon kahdeksasosaostinato, CS-80-tyylinen messinkimatto liukuvine sointuineen
## ja kellot. Syntetisoidaan reaaliajassa (AudioStreamGenerator), joten toimii myös selaimessa ilman säikeitä.

const FILES := ["res://assets/music/chariots_of_fire.ogg", "res://assets/music/chariots_of_fire.mp3",
	"res://assets/music/chariots_of_fire.wav"]
## Kappaleen kohdat (s): tahti 3,52 s (68 bpm), mutta tempo liukuu hieman, joten kohdat on sovitettu iskuihin.
const LOOP_FROM := 196.2   # ennen loppuhäivytystä (3:21) ...
const LOOP_TO := 67.45     # ... takaisin täyden teeman alkuun
const FINALE := 168.93     # viimeinen teema: n. 40 s kappaleen loppuun, juhlien (tutkimusmatka.gd PARTY_T) ajan
const XFADE := 2.5         # silmukan ristihäivytys
const XFADE_FINALE := 1.2  # perillä viimeiseen teemaan
const RATE := 22050.0
const BPM := 69.0
const VOLUME_DB := -3.0
## Soinnut tahdeittain (MIDI): Des, Ges/Des, Des, As/C, b, Ges, Assus4, As.
const CHORDS := [[49, 56, 61, 65], [49, 54, 58, 61], [49, 56, 61, 65], [48, 56, 60, 63], [46, 53, 58, 61],
	[42, 54, 58, 61], [44, 56, 61, 63], [44, 56, 60, 63]]

var synth := false  # soiko syntetisoitu (ei tiedostoa)
var section := ""   # "" | matka | finale (tiedostolla)
var playing: bool:
	get:
		return _cur != null and _cur.playing
var master := 0.0   # kokonaisvoimakkuus 0..1 (häivytykset)
var _cur: AudioStreamPlayer
var _old: AudioStreamPlayer  # ristihäivytyksessä vaimeneva
var _players: Array[AudioStreamPlayer] = []
var _xf_t := 0.0
var _xf_len := 1.0
var _pb: AudioStreamGeneratorPlayback
var _t := 0.0  # syntetisoidun kappaleen aika (s)
var _pad_f := [0.0, 0.0, 0.0, 0.0]
var _pad_ph := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _lp := 0.0
var _pulse_ph := 0.0
var _bell_ph := 0.0
var _bell_f := 0.0
var _comb_l := PackedFloat32Array()
var _comb_r := PackedFloat32Array()
var _ci := 0
var _tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var st: AudioStream = null
	for f in FILES:
		if ResourceLoader.exists(f):
			st = load(f)
			break
	if st is AudioStreamOggVorbis or st is AudioStreamMP3:
		st.loop = false
	if st == null:
		synth = true
		var g := AudioStreamGenerator.new()
		g.mix_rate = RATE
		g.buffer_length = 0.35
		st = g
	for k in (1 if synth else 2):
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.stream = st
		add_child(p)
		_players.append(p)
	_cur = _players[0]


## Alusta, häivyttäen sisään.
func start(fade := 1.0) -> void:
	for p in _players:
		p.stop()
	_old = null
	_xf_t = 0.0
	_cur = _players[0]
	_t = 0.0
	_cur.play()
	if synth:
		_pb = _cur.get_stream_playback()
		_fill()
	else:
		section = "matka"
	_fade_to(1.0, fade)


## Perillä: viimeiseen teemaan, ellei se jo soi.
func arrive() -> void:
	if synth or not playing or section != "matka":
		return
	section = "finale"
	if _cur.get_playback_position() < FINALE - 4.0:
		_cross(FINALE, XFADE_FINALE)


## Häivyttää pois ja pysäyttää.
func fade_out(fade := 4.0) -> void:
	if not playing:
		return
	_fade_to(0.0, fade, func() -> void:
		for p in _players:
			p.stop()
		section = ""
		_pb = null)


func _fade_to(v: float, secs: float, done := Callable()) -> void:
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(self, "master", v, secs)
	if done.is_valid():
		_tw.tween_callback(done)


## Toinen soitin alkaa kohdasta at, ja nykyinen vaimenee secs sekunnissa (tasatehoinen ristihäivytys).
func _cross(at: float, secs: float) -> void:
	if _old != null:
		_old.stop()
	_old = _cur
	_cur = _players[1] if _cur == _players[0] else _players[0]
	_cur.play(at)
	_xf_len = secs
	_xf_t = secs


func _process(delta: float) -> void:
	if synth:
		if playing and _pb != null:
			_fill()
	elif playing:
		if section == "matka" and _xf_t <= 0.0 and _cur.get_playback_position() >= LOOP_FROM:
			_cross(LOOP_TO, XFADE)
	var k := 1.0
	if _xf_t > 0.0:
		_xf_t = maxf(0.0, _xf_t - delta)
		k = 1.0 - _xf_t / _xf_len
		if _old != null:
			_old.volume_db = linear_to_db(maxf(master * cos(k * PI * 0.5), 1e-4)) + VOLUME_DB
			if _xf_t <= 0.0:
				_old.stop()
				_old = null
	if _cur != null:
		_cur.volume_db = linear_to_db(maxf(master * sin(k * PI * 0.5), 1e-4)) + VOLUME_DB


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _fill() -> void:
	var n := _pb.get_frames_available()
	if n > 0:
		_pb.push_buffer(render(n))


## Seuraavat n stereonäytettä syntetisoitua kappaletta.
func render(n: int) -> PackedVector2Array:
	if _comb_l.is_empty():
		_comb_l.resize(int(RATE * 0.0437))
		_comb_r.resize(int(RATE * 0.0511))
	var beat := 60.0 / BPM
	var bar_len := beat * 4.0
	var dt := 1.0 / RATE
	var glide := 1.0 - exp(-dt / 0.09)  # CS-80:n liuku soinnusta toiseen
	var buf := PackedVector2Array()
	buf.resize(n)
	for s in n:
		var bar := int(_t / bar_len)
		var in_bar := fmod(_t, bar_len)
		var chord: Array = CHORDS[bar % CHORDS.size()]
		# Messinkimatto: neljä ääntä, kaksi hieman epävireistä saha-aaltoa kussakin, alipäästö avautuu tahdin
		# alussa (puhallus) ja hengittää.
		var pad := 0.0
		for v in 4:
			var target := _hz(chord[v])
			if _pad_f[v] == 0.0:
				_pad_f[v] = target
			_pad_f[v] += (target - _pad_f[v]) * glide
			for d in 2:
				var k := v * 2 + d
				_pad_ph[k] = fmod(_pad_ph[k] + _pad_f[v] * (1.0 + (0.004 if d == 0 else -0.004)) * dt, 1.0)
				pad += _pad_ph[k] * 2.0 - 1.0
		pad *= 0.06
		var swell := 0.55 + 0.45 * smoothstep(0.0, 0.6, in_bar) * (1.0 - 0.35 * smoothstep(bar_len * 0.6, bar_len, in_bar))
		var cutoff := 500.0 + 2200.0 * swell
		var a := 1.0 - exp(-TAU * cutoff * dt)
		_lp += (pad * swell - _lp) * a
		# Pianon ostinato: kahdeksasosat soinnun pohjasävelellä, vuorotellen matala ja oktaavia ylempi.
		var eighth := beat * 0.5
		var ei := int(in_bar / eighth)
		var et := fmod(in_bar, eighth)
		var root: float = chord[0] - (12.0 if ei % 2 == 0 else 0.0)
		_pulse_ph = fmod(_pulse_ph + _hz(root) * dt, 1.0)
		var pe := exp(-et * 7.0) * (1.0 if ei % 4 == 0 else 0.7)
		var pulse := (sin(_pulse_ph * TAU) + 0.35 * sin(_pulse_ph * TAU * 2.0) + 0.12 * sin(_pulse_ph * TAU * 3.0)) * pe * 0.2
		if et < dt * 1.5:
			_pulse_ph = 0.0
		# Kello kahden tahdin välein: soinnun ylin sävel kaksi oktaavia ylempänä, hidas sammuminen.
		var bt := fmod(_t, bar_len * 2.0)
		if bt < dt * 1.5:
			_bell_f = _hz(chord[3] + 12.0)
		_bell_ph += _bell_f * dt
		var bell := (sin(_bell_ph * TAU) + 0.4 * sin(_bell_ph * TAU * 2.76)) * exp(-bt * 1.1) * 0.07
		var dry := _lp + pulse + bell
		# Kaiku: kaksi takaisinkytkettyä viivettä, eri pituiset vasemmalla ja oikealla.
		var il := _ci % _comb_l.size()
		var ir := _ci % _comb_r.size()
		var wl := _comb_l[il]
		var wr := _comb_r[ir]
		_comb_l[il] = dry + wl * 0.72
		_comb_r[ir] = dry + wr * 0.72
		_ci += 1
		buf[s] = Vector2(dry + wl * 0.28, dry + wr * 0.28).clampf(-1.0, 1.0)
		_t += dt
	return buf
