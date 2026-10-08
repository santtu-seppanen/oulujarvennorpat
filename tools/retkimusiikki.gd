extends SceneTree
## Tutkimusmatkan generoidun musiikin silmukka tiedostoon (kerran, ei pelin aikana):
##   godot --headless --path . -s tools/retkimusiikki.gd
## Kirjoittaa assets/music/retkimusiikki_silmukka.ogg (oggenc, Homebrew: brew install vorbis-tools) ja tuo sen
## (godot --headless --path . --import; silmukka päälle .import-tiedostossa).
## Des-duuri, 69 bpm, Chariots of Firen teeman sointukierto (CHORDS) viidennestä tahdista: pianon
## kahdeksasosaostinato, CS-80-tyylinen messinkimatto ja kellot joka toisella tahdilla. 8 tahtia, n. 28 s,
## saumaton silmukka. Soittimet lasketaan ensin lyhyiksi näytteiksi (matto, piano, kello), joista sävelet
## luetaan sävelkorkeuden mukaan. Mono, ei kaikua. Normalisoitu -1 dBFS:ään.

const OUT := "res://assets/music/retkimusiikki_silmukka.ogg"
const RATE := 22050
const BPM := 69.0
## Soinnut tahdeittain (MIDI): Des, Ges/Des, Des, As/C, b, Ges, Assus4, As. Pätkässä soi neljä ensimmäistä.
const CHORDS := [[49, 56, 61, 65], [49, 54, 58, 61], [49, 56, 61, 65], [48, 56, 60, 63], [46, 53, 58, 61],
	[42, 54, 58, 61], [44, 56, 61, 63], [44, 56, 60, 63]]
const FIRST_BAR := 4       # jatkaa Vangelis-pätkän jälkeen tästä tahdista
const PAD_DB := -18.0      # maton ääni (4 ääntä)
const PIANO_DB := -7.0
const BELL_DB := -16.0
## Näytteiden perustaajuudet: matossa kaksi saha-aaltoa 139 ja 140 Hz, joten 1 s silmukka on saumaton.
const PAD_F := 139.5
const PIANO_F := 87.307    # F2
const BELL_F := 659.255    # E5
const SEAM := 2048         # silmukan sauma: maton ristihäivytys (näytteitä)

var _n := 0
var _eighth := 0.0
var _buf := PackedFloat32Array()


func _initialize() -> void:
	_eighth = RATE * 30.0 / BPM
	_n = roundi(_eighth * 8.0 * CHORDS.size())
	_buf.resize(_n + SEAM)
	_pad()
	var piano := _render_piano()
	var bell := _render_bell()
	for e in 8 * CHORDS.size():
		var bar := e / 8
		var ei := e % 8
		var chord := _chord(bar)
		var at := roundi(e * _eighth)
		if ei == 0 and bar % 2 == 0:
			_add_note(at, bell, _hz(chord[3] + 12.0) / BELL_F, db_to_linear(BELL_DB))
		var root: float = chord[0] - (12.0 if ei % 2 == 0 else 0.0)
		_add_note(at, piano, _hz(root) / PIANO_F, db_to_linear(PIANO_DB - (0.0 if ei % 4 == 0 else 3.0)))
	var st := _buf
	var peak := 0.0
	for x in st:
		peak = maxf(peak, absf(x))
	var sc := db_to_linear(-1.0) * 32767.0 / peak
	var pcm := PackedByteArray()
	pcm.resize(st.size() * 2)
	for i in st.size():
		pcm.encode_s16(i * 2, clampi(roundi(st[i] * sc), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = pcm
	var wav := OS.get_cache_dir().path_join("retkimusiikki_silmukka.wav")
	w.save_to_wav(wav)
	var out := ProjectSettings.globalize_path(OUT)
	var log := []
	var code := OS.execute("oggenc", ["-Q", "-q", "3", "-o", out, wav], log, true)
	DirAccess.remove_absolute(wav)
	print("kierto %.2f s (%d näytettä), huippu %.3f, oggenc %d %s -> %s" % [_n / float(RATE), _n, peak, code, "".join(log), out])
	quit(code)


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Tahdin sointu: teeman kierto FIRST_BAR:sta.
static func _chord(bar: int) -> Array:
	return CHORDS[(FIRST_BAR + bar) % CHORDS.size()]


## Matto: neljä ääntä luetaan maton näytteestä soinnun sävelkorkeuksilla (sointu vaihtuu tahdin alussa), ja matto
## hengittää tahdin mukana: puhallus tahdin alussa, hiipuu loppua kohti. Kierron jatko häivytetään alkuun (sauma).
func _pad() -> void:
	var pad := _render_pad()
	var bar_n := _eighth * 8.0
	var bar_len := bar_n / RATE
	var vol := db_to_linear(PAD_DB)
	var x := [0.0, 0.0, 0.0, 0.0]
	var m := float(RATE)
	var bar := -1
	var p := []
	for i in _n + SEAM:
		if bar < 0 or i >= roundi((bar + 1) * bar_n):
			bar += 1
			p = _chord(bar).map(func(v: int) -> float: return _hz(v) / PAD_F)
		var s := 0.0
		for v in 4:
			var xv: float = x[v]
			var iv := int(xv)
			s += pad[iv] + (pad[iv + 1] - pad[iv]) * (xv - iv)
			xv += p[v]
			x[v] = xv - m if xv >= m else xv
		_buf[i] = s * vol * _swell((i - roundi(bar * bar_n)) / float(RATE), bar_len)
	for i in SEAM:
		var k := float(i) / SEAM
		_buf[i] = _buf[i] * k + _buf[_n + i] * (1.0 - k)
	_buf.resize(_n)


static func _swell(t: float, bar_len: float) -> float:
	return 0.55 + 0.45 * smoothstep(0.0, 0.6, t) * (1.0 - 0.35 * smoothstep(bar_len * 0.6, bar_len, t))


## Sävel kohdasta at: näyte luetaan sävelkorkeudella p (lineaarinen tulkinta); kierron yli menevä häntä jatkuu
## alusta.
func _add_note(at: int, src: PackedFloat32Array, p: float, vol: float) -> void:
	var x := 0.0
	var k := at
	for i in int((src.size() - 1) / p):
		if k >= _n:
			k -= _n
		var ix := int(x)
		_buf[k] += (src[ix] + (src[ix + 1] - src[ix]) * (x - ix)) * vol
		x += p
		k += 1


## Messinkimatto: kaksi hieman epävireistä saha-aaltoa (139 ja 140 Hz), alipäästö; 1 s saumaton silmukka
## (suodin lämmitetään kierroksella, jotta silmukan alku ja loppu täsmäävät). Viimeinen näyte = ensimmäinen.
static func _render_pad() -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(RATE + 1)
	var a := 1.0 - exp(-TAU * 1600.0 / RATE)
	var lp := 0.0
	var lp2 := 0.0
	for _pass in 2:
		for i in RATE:
			var x := fmod(i * 139.0 / RATE, 1.0) + fmod(i * 140.0 / RATE, 1.0) - 1.0
			lp += (x - lp) * a
			lp2 += (lp - lp2) * a
			s[i] = lp2 * 0.8
	s[RATE] = s[0]
	return s


## Pianon isku: perussävel ja kaksi yläsäveltä, nopea sammuminen (kahdeksasosan mittainen).
static func _render_piano() -> PackedFloat32Array:
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * PIANO_F * t
		s[i] = (sin(ph) + 0.35 * sin(ph * 2.0) + 0.12 * sin(ph * 3.0)) * exp(-t * 7.0) * minf(1.0, t * 300.0) * 0.6
	return s


## Kello: perussävel ja epäharmoninen yläsävel, hidas sammuminen.
static func _render_bell() -> PackedFloat32Array:
	var n := int(RATE * 1.8)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * BELL_F * t
		s[i] = (sin(ph) + 0.4 * sin(ph * 2.76)) * exp(-t * 1.6) * minf(1.0, t * 500.0) * 0.6
	return s
