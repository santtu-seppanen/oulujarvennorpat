extends AudioStreamPlayer
## Tutkimusmatkan musiikki: Vangeliksen Chariots of Fire. Äänite ei ole vapaasti levitettävä, joten sitä ei ole
## pelin mukana: oman kopion voi lisätä tiedostoon assets/music/chariots_of_fire.ogg (tai .mp3/.wav), ja se soi
## silmukkana. Ilman tiedostoa soi syntetisoitu kappale samassa hengessä (Des-duuri, 69 bpm): sykkivä
## pianon kahdeksasosaostinato, CS-80-tyylinen messinkimatto liukuvine sointuineen ja kellot. Syntetisoidaan
## reaaliajassa (AudioStreamGenerator), joten toimii myös selaimessa ilman säikeitä.

const FILES := ["res://assets/music/chariots_of_fire.ogg", "res://assets/music/chariots_of_fire.mp3",
	"res://assets/music/chariots_of_fire.wav"]
const RATE := 22050.0
const BPM := 69.0
const VOLUME_DB := -3.0
## Soinnut tahdeittain (MIDI): Des, Ges/Des, Des, As/C, b, Ges, Assus4, As.
const CHORDS := [[49, 56, 61, 65], [49, 54, 58, 61], [49, 56, 61, 65], [48, 56, 60, 63], [46, 53, 58, 61],
	[42, 54, 58, 61], [44, 56, 61, 63], [44, 56, 60, 63]]

var synth := false  # soiko syntetisoitu (ei tiedostoa)
var _pb: AudioStreamGeneratorPlayback
var _t := 0.0  # kappaleen aika (s)
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
	bus = "Music"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for f in FILES:
		if ResourceLoader.exists(f):
			var st: AudioStream = load(f)
			if st is AudioStreamOggVorbis or st is AudioStreamMP3:
				st.loop = true
			elif st is AudioStreamWAV:
				st.loop_mode = AudioStreamWAV.LOOP_FORWARD
				st.loop_end = int(st.get_length() * st.mix_rate)
			stream = st
			return
	synth = true
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.35
	stream = g
	_comb_l.resize(int(RATE * 0.0437))
	_comb_r.resize(int(RATE * 0.0511))


## Alusta, häivyttäen sisään.
func start(fade := 1.0) -> void:
	if _tw != null:
		_tw.kill()
	_t = 0.0
	volume_db = -30.0
	play()
	if synth:
		_pb = get_stream_playback()
		_fill()
	_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(self, "volume_db", VOLUME_DB, fade)


## Häivyttää pois ja pysäyttää.
func fade_out(fade := 4.0) -> void:
	if not playing:
		return
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(self, "volume_db", -40.0, fade)
	_tw.tween_callback(func() -> void:
		stop()
		_pb = null)


func _process(_delta: float) -> void:
	if synth and playing and _pb != null:
		_fill()


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _fill() -> void:
	var n := _pb.get_frames_available()
	if n > 0:
		_pb.push_buffer(render(n))


## Seuraavat n stereonäytettä.
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
