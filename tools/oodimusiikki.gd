extends SceneTree
## Keskiyön oodin säestys tiedostoon (kerran, ei pelin aikana):
##   godot --headless --path . -s tools/oodimusiikki.gd
## Kirjoittaa assets/music/oodi_saestys.ogg (oggenc, Homebrew: brew install vorbis-tools) ja tuo sen
## (godot --headless --path . --import).
## Sävel, soinnut ja tempo luetaan scripts/oodi.gd:stä, joten laulu ja säestys pysyvät tahdissa: urkumatto
## (soinnut puolitahdeittain), basso iskuittain ja hiljainen huilu soittaa laulun sävelen. Lopuksi kevyt kaiku
## (kaksi kampasuodinta), mono 22 kHz, normalisoitu -1 dBFS:ään.

const Oodi := preload("res://scripts/oodi.gd")
const OUT := "res://assets/music/oodi_saestys.ogg"
const RATE := 22050
const F3 := 53  # MIDI: urkujen alin sävel
const F4 := 65  # melodian perussävel (0 = F4)
const TAB := 2048
const ORGAN_DB := -12.0
const BASS_DB := -9.0
const FLUTE_DB := -11.0
const TAIL := 3.0  # loppusoinnun häntä

var _beat := 0.0  # näytteitä iskua kohden
var _buf := PackedFloat32Array()


func _initialize() -> void:
	_beat = RATE * 60.0 / Oodi.BPM
	var total: int = Oodi.beats()
	_buf.resize(roundi((total * _beat) + TAIL * RATE))
	var organ := _table([1.0, 0.5, 0.25, 0.12, 0.06])
	var flute := _table([1.0, 0.15, 0.04])
	# Soinnut puolitahdeittain: alkusoitto, laulun osat ja loppusoitto.
	var chords: Array = Oodi.CH_INTRO.duplicate()
	for part in Oodi.SONG:
		for r in 4:
			chords.append_array((Oodi.CH_A if part[0] == Oodi.MEL_A else Oodi.CH_B)[r])
	chords.append_array(Oodi.CH_OUTRO)
	for h in chords.size():
		var at := h * 2.0
		var len := 2.0 if h < chords.size() - 1 else 2.0 + TAIL * Oodi.BPM / 60.0
		var pcs: Array = Oodi.CHORD[chords[h]]
		for pc: int in pcs:
			_note(organ, F3 + posmod(pc, 12), at, len, db_to_linear(ORGAN_DB), 0.03)
		_note(organ, F3 + posmod(pcs[0], 12) + 12, at, len, db_to_linear(ORGAN_DB - 4.0), 0.03)
		# Basso: soinnun pohjasävel kahdesti puolitahdissa.
		var root: int = F3 - 12 + posmod(pcs[0], 12)
		for k in 2:
			_note(organ, root, at + k, 0.9 if h < chords.size() - 1 or k == 0 else len - 1.0,
				db_to_linear(BASS_DB), 0.01)
	# Melodia huilulla.
	var song: Array = Oodi.lines()
	for i in song.size():
		var e: Array = song[i]
		var end: float = song[i + 1][0] if i + 1 < song.size() else total - Oodi.OUTRO
		_note(flute, F4 + e[3], e[0], end - e[0] - 0.08, db_to_linear(FLUTE_DB), 0.04, true)
	_reverb()
	var peak := 0.0
	for x in _buf:
		peak = maxf(peak, absf(x))
	var sc := db_to_linear(-1.0) * 32767.0 / peak
	var pcm := PackedByteArray()
	pcm.resize(_buf.size() * 2)
	for i in _buf.size():
		pcm.encode_s16(i * 2, clampi(roundi(_buf[i] * sc), -32768, 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = pcm
	var wav := OS.get_cache_dir().path_join("oodi_saestys.wav")
	w.save_to_wav(wav)
	var out := ProjectSettings.globalize_path(OUT)
	var log := []
	var code := OS.execute("oggenc", ["-Q", "-q", "2", "-o", out, wav], log, true)
	DirAccess.remove_absolute(wav)
	print("kesto %.1f s, %d puolitahtia, %d sanaa, huippu %.3f, oggenc %d %s -> %s" % [_buf.size() / float(RATE),
		chords.size(), song.size(), peak, code, "".join(log), out])
	quit(code)


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Yksi aaltojakso osasävelineen (kertoimet 1., 2., 3. .. osasävelelle).
static func _table(h: Array) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(TAB + 1)
	for i in TAB + 1:
		var s := 0.0
		for k in h.size():
			s += h[k] * sin(TAU * (k + 1) * i / TAB)
		t[i] = s
	return t


## Sävel iskusta at, kesto iskuina; pehmeä alku ja loppu (fade s), huilulla hidas vibrato.
func _note(tab: PackedFloat32Array, midi: float, at: float, len: float, vol: float, fade: float, vib := false) -> void:
	var i0 := roundi(at * _beat)
	var n := roundi(len * _beat)
	var f := _hz(midi) * TAB / RATE
	var fa := maxi(1, roundi(fade * RATE))
	var ph := 0.0
	for i in n:
		var k := i0 + i
		if k >= _buf.size():
			break
		var env := minf(1.0, minf(float(i) / fa, float(n - i) / fa))
		var p := f
		if vib:
			p *= 1.0 + 0.004 * sin(TAU * 5.0 * i / RATE) * smoothstep(0.0, 0.4 * RATE, float(i))
		var ix := int(ph)
		_buf[k] += (tab[ix] + (tab[ix + 1] - tab[ix]) * (ph - ix)) * env * vol
		ph += p
		if ph >= TAB:
			ph -= TAB


## Kevyt kaiku: kaksi takaisinkytkettyä viivettä sekoitetaan alkuperäiseen.
func _reverb() -> void:
	var out := _buf.duplicate()
	for d: float in [0.0297, 0.0371]:
		var n := roundi(d * RATE)
		var y := PackedFloat32Array()
		y.resize(_buf.size())
		for i in _buf.size():
			y[i] = _buf[i] + (y[i - n] * 0.72 if i >= n else 0.0)
		for i in _buf.size():
			out[i] += y[i] * 0.12
	_buf = out
