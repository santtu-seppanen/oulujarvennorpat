extends Node
## Tutkimusmatkan musiikki: alkuun pätkä Vangeliksen Chariots of Firea, sitten samanhenkinen generoitu jatko
## perille asti, jolloin musiikki häivytetään (fade_out).
## - Pätkä (assets/music/chariots_of_fire_alku.ogg, 24 s, OGG Vorbis q5, normalisoitu -3 dBFS:ään): intron
##   viimeisestä iskusta (0:20) pianoteeman kohdalla ristihäivytyksellä täyden teeman alkuun (1:07) ja neljä
##   tahtia teemaa. Fraasin lopussa (HANDOFF) generoitu musiikki alkaa omalla iskullaan, ja pätkä häipyy pois.
## - Generoitu (assets/music/retkimusiikki_silmukka.ogg, 28 s saumaton silmukka, 22 kHz mono, 145 kt): teeman
##   sointukierto jatkuu pätkän jälkeen, ilman kaikua. Lasketaan valmiiksi työkalulla tools/retkimusiikki.gd,
##   joten pelin aikana ei lasketa mitään eikä väylällä ole kaikuefektiä: selaimessa ääni miksataan pääsäikeessä,
##   ja raskas laskenta tai efekti rikkoi äänen.
## Molemmat ladataan taustalla (prepare) huutojen aikana ja vapautetaan muistista heti, kun ne ovat soineet.
## Musiikin aikana vain puhesynteesi on hiljaa (tutkimusmatka.gd allows_speech); taustaäänet ja efektit soivat.

const CLIP := "res://assets/music/chariots_of_fire_alku.ogg"
const LOOP := "res://assets/music/retkimusiikki_silmukka.ogg"
const HANDOFF := 22.67     # pätkän fraasin loppu: generoitu alkaa tästä (pätkä häipyy 1,6 s)
const CLIP_DB := 0.0       # pätkä on jo normalisoitu
const GEN_DB := -2.0       # generoitu (normalisoitu -1 dBFS:ään)

var synth := false  # pätkä puuttuu: generoitu alusta asti
var section := ""   # "" | alku | matka
var playing: bool:
	get:
		return _on
var master := 0.0   # kokonaisvoimakkuus 0..1 (häivytykset)
var _on := false
var _clip: AudioStreamPlayer
var _gen: AudioStreamPlayer
var _req := {}        # taustalataukset: polku -> true
var _clip_len := 0.0
var _clip_t := 0.0    # aikaa pätkän alusta (oma kello: soittokohta ei etene ilman äänilaitetta)
var _g := -1.0        # generoidun aika (s), < 0: ei vielä alkanut
var _tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	synth = not ResourceLoader.exists(CLIP)
	_clip = AudioStreamPlayer.new()
	_clip.bus = "Music"
	add_child(_clip)
	_gen = AudioStreamPlayer.new()
	_gen.bus = "Music"
	add_child(_gen)


func _exit_tree() -> void:
	_drop_requests()


## Valmistelu ennen soittoa (esim. huutojen aikana): pätkä ja silmukka latautuvat taustalla.
func prepare() -> void:
	for path: String in ([LOOP] if synth else [CLIP, LOOP]):
		if not _req.has(path) and ResourceLoader.exists(path):
			if ResourceLoader.load_threaded_request(path) == OK:
				_req[path] = true


## Valmisteltu tai heti ladattu tiedosto.
func _take(path: String) -> AudioStream:
	if _req.erase(path):
		return ResourceLoader.load_threaded_get(path)
	return load(path) if ResourceLoader.exists(path) else null


## Valmistellut lataukset pois välimuistista (ei ehditty soittaa).
func _drop_requests() -> void:
	for path: String in _req:
		ResourceLoader.load_threaded_get(path)
	_req.clear()


## Pätkän alusta (intron viimeinen isku), häivyttäen sisään.
func start(fade := 0.15) -> void:
	_stop_all()
	prepare()
	_on = true
	if synth:
		_start_gen(0.0)
	else:
		section = "alku"
		var st := _take(CLIP)
		if st is AudioStreamOggVorbis:
			st.loop = false
		_clip.stream = st
		_clip_len = st.get_length() if st != null else 0.0
		_clip_t = 0.0
		_clip.play(0.0)
	_fade_to(1.0, fade)


## Häivyttää pois ja pysäyttää (muut äänet palaavat samassa tahdissa).
func fade_out(fade := 4.0) -> void:
	if not _on:
		_drop_requests()
		return
	_fade_to(0.0, fade, _stop_all)


func _stop_all() -> void:
	_free(_clip)
	_free(_gen)
	_drop_requests()
	_g = -1.0
	_on = false
	section = ""


## Soinut: pois muistista (seuraavalla matkalla ladataan uudelleen).
func _free(p: AudioStreamPlayer) -> void:
	if p.stream != null:
		p.stop()
		p.stream = null


func _fade_to(v: float, secs: float, done := Callable()) -> void:
	if _tw != null:
		_tw.kill()
	_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tw.tween_property(self, "master", v, secs)
	if done.is_valid():
		_tw.tween_callback(done)


## Generoitu alkaa kohdasta g (myöhästyminen ruudun rajalta).
func _start_gen(g: float) -> void:
	_gen.stream = _take(LOOP)
	_gen.play(g)
	_g = g
	section = "matka"


func _process(delta: float) -> void:
	if _on and _g < 0.0:
		_clip_t += delta
		if _clip_t >= HANDOFF:
			_start_gen(minf(_clip_t - HANDOFF, 0.25))
	elif _on:
		_g += delta
		if _clip.stream != null and _clip_t + _g >= _clip_len:
			_free(_clip)
	var lin := maxf(master, 1e-4)
	_clip.volume_db = linear_to_db(lin) + CLIP_DB
	_gen.volume_db = linear_to_db(lin) + GEN_DB
