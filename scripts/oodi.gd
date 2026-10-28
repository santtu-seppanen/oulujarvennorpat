extends Node
## Oodi Oulujärvelle: keskiyöllä koko porukka kokoontuu alamökin etuterassille järven puolelle ja laulaa oodin.
## - Klo 0.00 (kerran yössä, ei tutkimusmatkan aikana) tietokoneen hahmot kävelevät etuterassin kaiteelle
##   rinnakkain kasvot järvelle (ai.gd sing). Korttipöydässä istuvat jäävät pelaamaan.
## - Kun kaikki ovat paikoillaan (tai viimeistään GATHER_MAX:n jälkeen), säestys alkaa
##   (assets/music/oodi_saestys.ogg, lasketaan valmiiksi työkalulla tools/oodimusiikki.gd tämän tiedoston
##   sävelestä ja soinnuista). Säkeistöt laulavat hahmot vuorotellen, kertosäkeen kaikki: rivi näkyy
##   puhekuplana, ja puhesynteesi laulaa sen sana kerrallaan sävelen korkeudella (chat.gd sing).
## - Sävel on tätä peliä varten tehty. F-duuri, 104 bpm, 4/4: alkusoitto 2 tahtia, säkeistö ja kertosäe
##   (kumpikin 4 riviä x 2 tahtia) ja loppusoitto 2 tahtia, n. 49 s.
## Moninpeli: host päättää alun ja laulun alun (viesti "oodi"), ja laulu etenee jokaisella koneella omalla
## kellollaan; hostin tietokone ohjaa vapaita hahmoja.

const MUSIC := "res://assets/music/oodi_saestys.ogg"
const BPM := 104.0
const INTRO := 8  # iskuja ennen ensimmäistä riviä
const OUTRO := 8
const LINE := 8  # iskuja riviä kohden (2 tahtia)
const GATHER_MAX := 45.0
const MUSIC_DB := -4.0
const MAINE_GAIN := 20  # laulamaan osallistuvan mainepisteet joka kerta
const MAINE_LOSS := 10  # oodin ohittavan mökkiläisen mainepisteet
const SING_REACH := 3.0  # näin lähellä omaa paikkaa kaiteella lasketaan laulavan
## Melodiat riveittäin: [sävelet puolisävelaskelina F4:stä, kestot iskuina] (sana kohden yksi sävel).
const MEL_A := [[[0, 4, 7, 9, 7], [2, 1, 2, 1, 2]], [[9, 7, 5, 4, 2], [2, 1, 2, 1, 2]], [[7, 9, 7], [3, 2, 3]],
	[[5, 2, 0], [3, 1, 4]]]
const MEL_B := [[[9, 7, 9, 12], [2, 2, 1, 3]], [[12, 9, 7], [3, 2, 3]], [[7, 9, 7, 5, 7], [2, 1, 2, 1, 2]],
	[[9, 7, 5, 4, 2, 0], [2, 1, 1, 1, 1, 2]]]
## Soinnut puolitahdeittain (4 riviä kohden).
const CH_A := [["F", "F", "Dm", "C"], ["Dm", "C", "Bb", "C"], ["F", "Dm", "C", "C"], ["Bb", "C", "F", "F"]]
const CH_B := [["Dm", "C", "Bb", "F"], ["F", "Dm", "C", "C"], ["F", "Bb", "F", "C"], ["Bb", "C", "F", "F"]]
const CH_INTRO := ["F", "Bb", "C", "C"]
const CH_OUTRO := ["Bb", "C", "F", "F"]
## Soinnun sävelet puolisävelaskelina F:stä.
const CHORD := {"F": [0, 4, 7], "Gm": [2, 5, 9], "Bb": [5, 9, 12], "C": [7, 11, 14], "Dm": [9, 12, 16]}
const VERSE := ["Taival lie hankala – olkoon vaan!",
	"Luonto lie kitsas – siis kilpaillaan!",
	"Kolkassa synkeän syntymämaan",
	"pirttimme piilköhöt paikoillaan!"]
const REFRAIN := ["Vainojen virmat, oi vaietkaa!",
	"Rapparit, ryöstäjät, kaijotkaa!",
	"Miekkaa ei tarvis – tarmoa vaan",
	"puolesta hengen ja heimon ja maan."]
## Laulu riveittäin: [melodia, sanat, laulaja (-1 = kaikki)].
const SONG := [[MEL_A, VERSE, 0], [MEL_B, REFRAIN, -1]]
## Paikat etuterassin kaiteella pihan kehyksessä (u, v), kasvot järvelle.
const SPOTS := [Vector2(-1.9, 3.75), Vector2(-1.0, 3.8), Vector2(-0.1, 3.8), Vector2(0.8, 3.75)]

var game: Node3D
var state := ""  # "" | kokoontuu | laulu
var _t := 0.0
var _day := -1  # yö, jona oodi on jo laulettu
var _taken: Array = []  # tämän koneen ohjaamat laulajat (crew-indeksit)
var _player: AudioStreamPlayer
var _away := false  # pelaaja oli oodin alkaessa Happy Beachillä tai matkalla: ei ääntä eikä kuplia, maine vähenee
var _away_text := ""  # missä pelaaja oli poissa (ilmoitukseen)
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
			var ws := words(part[1][r])
			var who: int = part[2]
			var singer := (who + r) % 4 if who >= 0 else -1
			var beat := INTRO + k * LINE
			for w in ws.size():
				out.append([beat, part[1][r], ws[w], mel[0][w], singer if singer >= 0 else k % 4, w == 0,
					singer < 0])
				beat += mel[1][w]
			k += 1
	return out


## Rivin laulettavat sanat (yksi sävel kutakin): ajatusviiva ei ole sana.
static func words(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	for w in line.split(" ", false):
		if w != "–":
			out.append(w)
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
		if _host() and lt.hour == 0 and _day != lt.day and not game.retki.active:
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
	# Happy Beachillä tai autolla/veneellä oleville oodi ei kuulu: he eivät kuule sitä, ja mainepisteet vähenevät
	_away = game.at_beach() or game.travelling()
	_away_text = "Happy Beachillä" if game.at_beach() else "matkalla"
	_t = 0.0
	_day = game.sun.local().day
	if send:
		game.mp.send({"t": "oodi", "a": "alku"})
	if not _away:
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


## Oma pelaaja on omalla paikallaan etuterassilla (oikea ihminen ei kävele itse, joten odotetaan häntä).
func _player_there() -> bool:
	var j: int = game.player_index
	if game.crew_modes[j] == "ai" or game.player.boat != null or _away:
		return true  # rannalla olevaa ei odoteta
	var q: Vector3 = spot(j)
	var p: Vector3 = game.player.global_position
	return Vector2(p.x - q.x, p.z - q.z).length() < SING_REACH and absf(p.y - q.y) < 2.5


func _all_there() -> bool:
	if not _player_there():
		return false
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
	_settle_fame()
	_player.stream = st
	_player.volume_db = MUSIC_DB
	if st != null and not _away:
		_player.play()


## Laulun alkaessa: mökillä laulamassa +20 mainepistettä, muualla (esim. Happy Beachillä) -10.
func _settle_fame() -> void:
	var j: int = game.player_index
	var sang: bool = not _away and ((game.crew_modes[j] == "ai" and j in _taken) or (game.crew_modes[j] != "ai" and _player_there()))
	if _away:
		game.maine = maxi(0, game.maine - MAINE_LOSS)
		game.toast("Keskiyö %s: oodi Oulujärvelle jäi laulamatta, mainepisteet -%d (nyt %d/100)" % [_away_text, MAINE_LOSS, game.maine], 5.0)
	elif sang:
		game.maine = mini(100, game.maine + MAINE_GAIN)
		game.toast("Lauloit oodin Oulujärvelle: mainepisteet +%d (nyt %d/100)" % [MAINE_GAIN, game.maine], 5.0)
	else:
		game.maine = maxi(0, game.maine - MAINE_LOSS)
		game.toast("Et ollut laulamassa oodia mökillä: mainepisteet -%d (nyt %d/100)" % [MAINE_LOSS, game.maine], 5.0)
	game.tarina._dirty = true


## Sana laulajan äänellä; rivin alussa puhekupla (kertosäkeessä kaikilla).
func _word(e: Array) -> void:
	if _away:
		return
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
	if not _away:
		game.toast("Oodi Oulujärvelle laulettu. Hyvää yötä, norpat!", 5.0)
	_away = false
	# Yön yli juomattomat kahvit ja syömättömät ruoat menevät hukkaan (jokainen kone nollaa omansa).
	game.kahvi._set_count(0)
	game.kokkaus._set_count(0)
	game.tarjoilu._set_steaks(0)
	game.go_to_bed()
