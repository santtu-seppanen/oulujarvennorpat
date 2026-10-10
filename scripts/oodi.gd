extends Node
## Oodi Oulujärvelle: keskiyöllä koko porukka kokoontuu alamökin etuterassille järven puolelle ja laulaa oodin.
## - Klo 0.00 (kerran yössä, ei tutkimusmatkan aikana) tietokoneen hahmot kävelevät etuterassin kaiteelle
##   rinnakkain kasvot järvelle (ai.gd sing). Korttipöydässä istuvat jäävät pelaamaan.
## - Kun kaikki ovat paikoillaan (tai viimeistään GATHER_MAX:n jälkeen), säestys alkaa
##   (assets/music/oodi_saestys.ogg, lasketaan valmiiksi työkalulla tools/oodimusiikki.gd tämän tiedoston
##   sävelestä ja soinnuista). Säkeistöt laulavat hahmot vuorotellen, kertosäkeen kaikki: rivi näkyy
##   puhekuplana, ja puhesynteesi laulaa sen sana kerrallaan sävelen korkeudella (chat.gd sing).
## - Sanat ja sävel ovat tätä peliä varten tehtyjä. F-duuri, 76 bpm, 4/4: alkusoitto 2 tahtia, säkeistö,
##   kertosäe, säkeistö, kertosäe (kukin 4 riviä x 2 tahtia) ja loppusoitto 2 tahtia, n. 1 min 54 s.
## Moninpeli: host päättää alun ja laulun alun (viesti "oodi"), ja laulu etenee jokaisella koneella omalla
## kellollaan; hostin tietokone ohjaa vapaita hahmoja.

const MUSIC := "res://assets/music/oodi_saestys.ogg"
const BPM := 76.0
const INTRO := 8  # iskuja ennen ensimmäistä riviä
const OUTRO := 8
const LINE := 8  # iskuja riviä kohden (2 tahtia)
const GATHER_MAX := 45.0
const MUSIC_DB := -4.0
## Melodiat riveittäin: [sävelet puolisävelaskelina F4:stä, kestot iskuina] (sana kohden yksi sävel).
const MEL_A := [[[0, 4, 7, 9, 7], [2, 1, 1, 2, 2]], [[9, 7, 5, 4, 2], [2, 2, 1, 1, 2]],
	[[7, 7, 9, 7, 5, 4], [1, 1, 2, 1, 1, 2]], [[4, 5, 7, 5, 4, 2, 0], [1, 1, 1, 1, 1, 1, 2]]]
const MEL_B := [[[7, 9, 7, 4], [2, 2, 2, 2]], [[5, 4, 2, 4, 7], [1, 1, 1, 3, 2]], [[9, 7, 5], [3, 2, 3]],
	[[4, 2, 0], [2, 2, 4]]]
## Soinnut puolitahdeittain (4 riviä kohden).
const CH_A := [["F", "F", "Dm", "C"], ["Dm", "C", "Bb", "C"], ["F", "Dm", "C", "F"], ["F", "Bb", "C", "F"]]
const CH_B := [["F", "Bb", "F", "Dm"], ["Bb", "Gm", "F", "C"], ["Dm", "Dm", "C", "Bb"], ["F", "C", "F", "F"]]
const CH_INTRO := ["F", "Bb", "C", "C"]
const CH_OUTRO := ["Bb", "C", "F", "F"]
## Soinnun sävelet puolisävelaskelina F:stä.
const CHORD := {"F": [0, 4, 7], "Gm": [2, 5, 9], "Bb": [5, 9, 12], "C": [7, 11, 14], "Dm": [9, 12, 16]}
const VERSE_1 := ["Oulujärvi, Kainuun meri, kesäyössä hohtaa",
	"Äpätinniemen männiköissä hiljaa tuuli kulkee",
	"Norpat kiville kokoontuu, aallot rantaan laulaa",
	"Täällä sydän levon löytää, täällä koti kutsuu"]
const REFRAIN := ["Laula, järvi, laula meille",
	"yötön yö ja sininen selkä",
	"Oulujärven norpat täällä",
	"nostaa maljan kotirannalle!"]
const VERSE_2 := ["Sauna lämpiää, löyly pehmeästi suhisee",
	"kumivene laiturilla airoja jo odottaa",
	"Pyttipannu, kahvi, kortit, ystävät ja nauru",
	"aurinko vain hetken painuu, nousee taas aamu"]
## Laulu riveittäin: [melodia, sanat, laulaja (-1 = kaikki)].
const SONG := [[MEL_A, VERSE_1, 0], [MEL_B, REFRAIN, -1], [MEL_A, VERSE_2, 1], [MEL_B, REFRAIN, -1]]
## Paikat etuterassin kaiteella pihan kehyksessä (u, v), kasvot järvelle.
const SPOTS := [Vector2(-1.9, 3.75), Vector2(-1.0, 3.8), Vector2(-0.1, 3.8), Vector2(0.8, 3.75)]

var game: Node3D
var state := ""  # "" | kokoontuu | laulu
var _t := 0.0
var _day := -1  # yö, jona oodi on jo laulettu
var _taken: Array = []  # tämän koneen ohjaamat laulajat (crew-indeksit)
var _player: AudioStreamPlayer
var _req := false
var _next := 0  # seuraava laulettava sana (lines() -lista)
var _lines: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)
	_lines = lines()
	game.mp.on("oodi", func(d: Dictionary, from: int) -> void:
		if from != game.mp.net.host_id:
			return
		if d.get("a", "") == "alku":
			_gather(false)
		elif d.get("a", "") == "laulu":
			_sing(false))


## Laulu sanoittain: [isku, rivi, sana, sävel, laulaja, rivin alku?]. Rivin laulaja: säkeistössä vuorotellen,
## kertosäkeessä kaikki (puhesynteesin ääni vaihtuu riveittäin).
static func lines() -> Array:
	var out := []
	var k := 0
	for part in SONG:
		for r in 4:
			var mel: Array = part[0][r]
			var words: PackedStringArray = (part[1][r] as String).split(" ")
			var who: int = part[2]
			var singer := (who + r) % 4 if who >= 0 else -1
			var beat := INTRO + k * LINE
			for w in words.size():
				out.append([beat, part[1][r], words[w], mel[0][w], singer if singer >= 0 else k % 4, w == 0,
					singer < 0])
				beat += mel[1][w]
			k += 1
	return out


## Laulun kesto iskuina.
static func beats() -> int:
	return INTRO + SONG.size() * 4 * LINE + OUTRO


func _host() -> bool:
	return not game.mp.online() or game.mp.net.is_host()


func singing() -> bool:
	return state == "laulu"


func _process(delta: float) -> void:
	if state == "":
		var lt: Dictionary = game.sun.local()
		if _host() and lt.hour == 0 and lt.minute < 15 and _day != lt.day and not game.retki.active:
			_gather(true)
		return
	_t += delta
	if state == "kokoontuu":
		if _host() and (_t > GATHER_MAX or _all_there()):
			_sing(true)
		return
	var beat := _t * BPM / 60.0
	while _next < _lines.size() and beat >= _lines[_next][0]:
		_word(_lines[_next])
		_next += 1
	if beat > beats() + 3.0:
		_end()


## Keskiyö: porukka etuterassille.
func _gather(send: bool) -> void:
	if state != "":
		return
	state = "kokoontuu"
	_t = 0.0
	_day = game.sun.local().day
	if send:
		game.mp.send({"t": "oodi", "a": "alku"})
	game.toast("Keskiyö! Porukka kokoontuu alamökin etuterassille laulamaan oodin Oulujärvelle.", 6.0)
	if ResourceLoader.exists(MUSIC) and ResourceLoader.load_threaded_request(MUSIC) == OK:
		_req = true
	if not _host():
		return
	_taken.clear()
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if game.crew_modes[j] != "ai" or b.boat != null or not _ai(b) or b.brain.activity == "kortit":
			continue
		b.brain.sing(spot(j))
		_taken.append(j)


## Mökkiläisen j paikka etuterassin kaiteella maailmassa.
func spot(j: int) -> Vector3:
	var m: Node3D = game.world.mokki
	var w: Vector2 = m.yw(SPOTS[j].x, SPOTS[j].y)
	return Vector3(w.x, m.DY, w.y)


## Tavallinen tietokoneen hahmo (ai.gd; ei esim. tutkimusmatkan tai pallopelin ohjauksessa). Ei preloadia,
## jotta työkalu tools/oodimusiikki.gd voi lukea sävelen ilman pelin skriptejä.
static func _ai(b: Node) -> bool:
	return b.brain != null and b.brain.has_method("sing")


func _all_there() -> bool:
	for j in _taken:
		var b: CharacterBody3D = game.crew[j]
		if not _ai(b) or not b.brain.singing_ready():
			return false
	return true


func _sing(send: bool) -> void:
	if state == "laulu":
		return
	if state == "":
		_gather(false)
	state = "laulu"
	_t = 0.0
	_next = 0
	if send:
		game.mp.send({"t": "oodi", "a": "laulu"})
	var st: AudioStream = null
	if _req:
		_req = false
		st = ResourceLoader.load_threaded_get(MUSIC)
	elif ResourceLoader.exists(MUSIC):
		st = load(MUSIC)
	if st is AudioStreamOggVorbis:
		st.loop = false
	_player.stream = st
	_player.volume_db = MUSIC_DB
	if st != null:
		_player.play()


## Sana laulajan äänellä; rivin alussa puhekupla (kertosäkeessä kaikilla).
func _word(e: Array) -> void:
	if e[5]:
		for j in (range(game.crew.size()) if e[6] else [e[4]]):
			game.chat.show_message(j, e[1], false, j == e[4])
	game.chat.sing(e[4], e[2], e[3])


func _end() -> void:
	state = ""
	_player.stop()
	_player.stream = null
	for j in _taken:
		var b: CharacterBody3D = game.crew[j]
		if _ai(b):
			b.brain.sing_end()
	_taken.clear()
	game.toast("Oodi Oulujärvelle laulettu. Hyvää yötä, norpat!", 5.0)
