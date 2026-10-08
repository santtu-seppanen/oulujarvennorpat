extends Node
## Tutkimusmatkan musiikki: alkuun pätkä Vangeliksen Chariots of Firea, sitten peli jatkaa samanhenkisellä
## generoidulla musiikilla perille asti.
## - Pätkä (assets/music/chariots_of_fire_alku.ogg, 24 s, OGG Vorbis q5, normalisoitu -3 dBFS:ään): intron
##   viimeisestä iskusta (0:20) pianoteeman kohdalla ristihäivytyksellä täyden teeman alkuun (1:07) ja neljä
##   tahtia teemaa. Fraasin lopussa (HANDOFF) generoitu musiikki alkaa omalla iskullaan, ja pätkä häipyy pois.
## - Generoitu: Des-duuri, 69 bpm, teeman sointukierto (CHORDS) jatkuu pätkän jälkeen viidennestä tahdista:
##   pianon kahdeksasosaostinato, CS-80-tyylinen messinkimatto liukuvine sointuineen ja kellot.
## - Perillä (arrive) seuraavasta tahdista loppukadenssi (FINALE) ja sointu jää soimaan häipyen.
## Tehokas: soittimien äänet (piano, matto, kello) lasketaan kerran lyhyiksi näytteiksi (AudioStreamWAV, yksi
## soitin ruutua kohden), ja ne soitetaan sävelinä AudioStreamPolyphonicilla sävelkorkeutta skaalaamalla.
## Ruutua kohden vain ajastus ja muutama voimakkuus; kaiku on väylän efekti (BUS -> Music).
## Kun musiikki soi, muut äänet (Ambience- ja SFX-väylät: taustaäänet ja efektit) vaiennetaan (DUCK_DB).

const CLIP := "res://assets/music/chariots_of_fire_alku.ogg"
const HANDOFF := 22.67     # pätkän fraasin loppu: generoitu alkaa tästä (pätkä häipyy 1,6 s)
const CLIP_DB := 0.0       # pätkä on jo normalisoitu
const GEN_DB := -2.0       # generoitu kokonaisuutena (varaa: soittimien huiput yhteensä alle 0 dBFS)
const PAD_DB := -18.0      # maton ääni (4 ääntä)
const PIANO_DB := -7.0
const BELL_DB := -16.0
const DUCK_DB := -80.0     # muut äänet (DUCK_BUSES) kappaleen ajan: hiljaa
const DUCK_BUSES := ["Ambience", "SFX"]
const BUS := "Retkimusiikki"  # generoidun musiikin väylä (kaiku), lähtee Music-väylään
const RATE := 22050
const BPM := 69.0
## Soinnut tahdeittain (MIDI): Des, Ges/Des, Des, As/C, b, Ges, Assus4, As. Pätkässä soi neljä ensimmäistä.
const CHORDS := [[49, 56, 61, 65], [49, 54, 58, 61], [49, 56, 61, 65], [48, 56, 60, 63], [46, 53, 58, 61],
	[42, 54, 58, 61], [44, 56, 61, 63], [44, 56, 60, 63]]
const FIRST_BAR := 4       # generoitu jatkaa pätkän jälkeen tästä tahdista
const FINALE := [5, 6, 7, 0]  # loppukadenssi: Ges, Assus4, As, Des (jää soimaan)
const FINALE_FADE := 8.0   # viimeinen sointu häipyy
## Näytteiden perustaajuudet: matossa kaksi saha-aaltoa 139 ja 140 Hz, joten 1 s silmukka on saumaton.
const PAD_F := 139.5
const PIANO_F := 87.307    # F2
const BELL_F := 659.255    # E5

var synth := false  # pätkä puuttuu: generoitu alusta asti
var section := ""   # "" | alku | matka | finale
var playing: bool:
	get:
		return _on
var master := 0.0   # kokonaisvoimakkuus 0..1 (häivytykset)
var _on := false
var _clip: AudioStreamPlayer
var _gen: AudioStreamPlayer
var _pb: AudioStreamPlaybackPolyphonic
var _pad: AudioStreamWAV
var _piano: AudioStreamWAV
var _bell: AudioStreamWAV
var _build_step := 0  # näytteet lasketaan ruutu kerrallaan (0..3)
var _clip_t := 0.0    # aikaa pätkän alusta (oma kello: soittokohta ei etene ilman äänilaitetta)
var _g := -1.0        # generoidun aika (s), < 0: ei vielä alkanut
var _next_e := 0      # seuraava kahdeksasosa
var _voices: Array[int] = []  # maton äänet
var _bar := -1
var _finale_at := -1  # tahti, josta loppukadenssi alkaa
var _tw: Tween
var _ducks: Array[AudioEffectAmplify] = []  # DUCK_BUSES-väylillä


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists(CLIP):
		var st: AudioStream = load(CLIP)
		if st is AudioStreamOggVorbis:
			st.loop = false
		_clip = AudioStreamPlayer.new()
		_clip.bus = "Music"
		_clip.stream = st
		add_child(_clip)
	synth = _clip == null
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Music" if AudioServer.get_bus_index("Music") >= 0 else "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.6
		rv.damping = 0.4
		rv.wet = 0.22
		rv.dry = 0.9
		AudioServer.add_bus_effect(i, rv)
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 16
	_gen = AudioStreamPlayer.new()
	_gen.bus = BUS
	_gen.stream = poly
	add_child(_gen)
	for name: String in DUCK_BUSES:
		var bus := AudioServer.get_bus_index(name)
		if bus >= 0:
			var fx := AudioEffectAmplify.new()
			AudioServer.add_bus_effect(bus, fx)
			_ducks.append(fx)


func _exit_tree() -> void:
	for name: String in DUCK_BUSES:
		var bus := AudioServer.get_bus_index(name)
		for i in range((AudioServer.get_bus_effect_count(bus) if bus >= 0 else 0) - 1, -1, -1):
			if AudioServer.get_bus_effect(bus, i) in _ducks:
				AudioServer.remove_bus_effect(bus, i)


## Pätkän alusta (intron viimeinen isku), häivyttäen sisään.
func start(fade := 0.15) -> void:
	_stop_all()
	_on = true
	_finale_at = -1
	if synth:
		section = "matka"
		_build_all()
		_start_gen(0.0)
	else:
		section = "alku"
		_clip_t = 0.0
		_clip.play(0.0)
	_fade_to(1.0, fade)


## Perillä: seuraavasta tahdista loppukadenssi (pätkän aikana heti generoidun alkaessa).
func arrive() -> void:
	if not _on or section == "finale":
		return
	section = "finale"
	_finale_at = _bar + 1 if _g >= 0.0 else 0


## Häivyttää pois ja pysäyttää.
func fade_out(fade := 4.0) -> void:
	if not _on:
		return
	_fade_to(0.0, fade, _stop_all)


func _stop_all() -> void:
	if _clip != null:
		_clip.stop()
	_gen.stop()
	_pb = null
	_voices.clear()
	_g = -1.0
	_bar = -1
	_on = false
	section = ""


func _fade_to(v: float, secs: float, done := Callable()) -> void:
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(self, "master", v, secs)
	if done.is_valid():
		_tw.tween_callback(done)


## Generoitu alkaa: aika g (myöhästyminen ruudun rajalta) kahdeksasosien ajastusta varten.
func _start_gen(g: float) -> void:
	_gen.play()
	_pb = _gen.get_stream_playback()
	_g = g
	_next_e = 0
	_bar = -1
	if section == "alku":
		section = "matka"


func _process(delta: float) -> void:
	if _on and _build_step < 3:
		_build_next()
	if _on and _g < 0.0 and _clip != null:
		_clip_t += delta
		if _clip_t >= HANDOFF and _build_step >= 3:
			_start_gen(minf(_clip_t - HANDOFF, 0.25))
	if _g >= 0.0 and _pb != null:
		_g += delta
		_sequence()
	var lin := maxf(master, 1e-4)
	if _clip != null:
		_clip.volume_db = linear_to_db(lin) + CLIP_DB
	_gen.volume_db = linear_to_db(lin) + GEN_DB
	var duck := linear_to_db(lerpf(1.0, db_to_linear(DUCK_DB), master if _on else 0.0))
	for fx in _ducks:
		fx.volume_db = duck


## Soittaa erääntyneet kahdeksasosat. Ruudun rajalta myöhästynyt sävel aloitetaan näytteen kohdasta, jossa se
## olisi nyt, joten rytmi pysyy tasaisena ruutunopeudesta riippumatta.
func _sequence() -> void:
	var eighth := 30.0 / BPM
	while _g >= _next_e * eighth:
		var late := _g - _next_e * eighth
		var e := _next_e
		_next_e += 1
		if late > 0.25:
			continue  # pitkä katko (esim. tauko): ei kasata säveliä
		var bar := e / 8
		var ei := e % 8
		var chord := _chord(bar)
		if chord.is_empty():
			continue  # kadenssin jälkeen vain viimeinen sointu soi
		if ei == 0:
			_bar = bar
			_set_pad(chord, late)
			if bar % 2 == 0 or _finale_at >= 0 and bar >= _finale_at + FINALE.size() - 1:
				var p := _hz(chord[3] + 12.0) / BELL_F
				_pb.play_stream(_bell, late * p, BELL_DB, p, 0, BUS)
		if _finale_at >= 0 and bar >= _finale_at + FINALE.size() - 1:
			continue  # viimeinen sointu: ei ostinatoa
		var root: float = chord[0] - (12.0 if ei % 2 == 0 else 0.0)
		var pp := _hz(root) / PIANO_F
		_pb.play_stream(_piano, late * pp, PIANO_DB - (0.0 if ei % 4 == 0 else 3.0), pp, 0, BUS)
	# Matto hengittää tahdin mukana: puhallus tahdin alussa, hiipuu loppua kohti.
	var bar_len := eighth * 8.0
	var in_bar := fmod(_g, bar_len)
	var swell := 0.55 + 0.45 * smoothstep(0.0, 0.6, in_bar) * (1.0 - 0.35 * smoothstep(bar_len * 0.6, bar_len, in_bar))
	var last := _finale_at >= 0 and _bar >= _finale_at + FINALE.size() - 1
	if last:
		swell *= 1.0 - clampf((_g - (_finale_at + FINALE.size() - 1) * bar_len) / FINALE_FADE, 0.0, 1.0)
		if swell <= 0.0:
			_stop_all()
			master = 0.0
			return
	for id in _voices:
		_pb.set_stream_volume(id, PAD_DB + linear_to_db(maxf(swell, 1e-4)))


## Tahdin sointu: teeman kierto FIRST_BAR:sta, perillä loppukadenssi, sen jälkeen tyhjä (viimeinen jää soimaan).
func _chord(bar: int) -> Array:
	if _finale_at >= 0 and bar >= _finale_at:
		var k := bar - _finale_at
		return CHORDS[FINALE[k]] if k < FINALE.size() else []
	return CHORDS[(FIRST_BAR + bar) % CHORDS.size()]


## Maton neljä ääntä: ensimmäisellä kerralla alkavat, sitten liukuvat uuteen sointuun.
func _set_pad(chord: Array, late: float) -> void:
	for v in 4:
		var p := _hz(chord[v]) / PAD_F
		if _voices.size() <= v:
			_voices.append(_pb.play_stream(_pad, late * p, PAD_DB, p, 0, BUS))
		else:
			_pb.set_stream_pitch_scale(_voices[v], p)


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _build_all() -> void:
	while _build_step < 3:
		_build_next()


## Seuraava näyte (yksi ruutua kohden, ettei aloitus nyki).
func _build_next() -> void:
	match _build_step:
		0:
			_pad = _render_pad()
		1:
			_piano = _render_piano()
		2:
			_bell = _render_bell()
	_build_step += 1


static func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


## Messinkimatto: kaksi hieman epävireistä saha-aaltoa (139 ja 140 Hz), alipäästö; 1 s saumaton silmukka
## (suodin lämmitetään kierroksella, jotta silmukan alku ja loppu täsmäävät).
static func _render_pad() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	s.resize(RATE)
	var a := 1.0 - exp(-TAU * 1600.0 / RATE)
	var lp := 0.0
	var lp2 := 0.0
	for _pass in 2:
		for i in RATE:
			var x := fmod(i * 139.0 / RATE, 1.0) + fmod(i * 140.0 / RATE, 1.0) - 1.0
			lp += (x - lp) * a
			lp2 += (lp - lp2) * a
			s[i] = lp2 * 0.8
	return _wav(s, true)


## Pianon isku: perussävel ja kaksi yläsäveltä, nopea sammuminen (kahdeksasosan mittainen).
static func _render_piano() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * PIANO_F * t
		s[i] = (sin(ph) + 0.35 * sin(ph * 2.0) + 0.12 * sin(ph * 3.0)) * exp(-t * 7.0) * minf(1.0, t * 300.0) * 0.6
	return _wav(s)


## Kello: perussävel ja epäharmoninen yläsävel, hidas sammuminen.
static func _render_bell() -> AudioStreamWAV:
	var n := int(RATE * 1.8)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * BELL_F * t
		s[i] = (sin(ph) + 0.4 * sin(ph * 2.76)) * exp(-t * 1.6) * minf(1.0, t * 500.0) * 0.6
	return _wav(s)
