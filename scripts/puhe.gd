extends Node
## Valmiiksi nauhoitetut puheet: käsikirjoitetut repliikit (tietokoneen hahmot, kohtaukset, oodi, puhelut) on nauhoitettu
## macOS:n `say`-komennolla (tools/puhe/nauhoita.py) tiedostoihin assets/puhe/<ääni>_<tiiviste>.ogg. Peli ei syntetisoi
## puhetta itse: pelaajien kirjoittamat viestit ja nauhoittamattomat rivit näkyvät vain tekstinä.
## Äänet: santtu, marko, jaakko, jukka (mökkiläiset), esimies (nalkuttava miesääni) ja vaimo (nalkuttava naisääni).
## Editorissa nauhoittamattomat rivit kirjataan tiedostoon user://puhe_puuttuu.txt (ääni <tab> teksti).

const DIR := "res://assets/puhe/"

var _players: Array[AudioStreamPlayer] = []
var _missing := {}


## Tiedoston tunniste: ääni + tekstin MD5 (sama laskenta nauhoita.py:ssä).
static func key(voice: String, text: String) -> String:
	return "%s_%s" % [voice, text.strip_edges().md5_text().left(10)]


static func path(voice: String, text: String) -> String:
	return DIR + key(voice, text) + ".ogg"


static func has(voice: String, text: String) -> bool:
	return ResourceLoader.exists(path(voice, text))


## Soittaa nauhoitteen (vol_db: voimakkuus, pitch: laulussa sävelen mukaan). Palauttaa false, jos riviä ei ole nauhoitettu.
func play(voice: String, text: String, vol_db := 0.0, pitch := 1.0) -> bool:
	var p := path(voice, text)
	if not ResourceLoader.exists(p):
		if OS.has_feature("editor") and not _missing.has(p):
			_missing[p] = true
			var f := FileAccess.open("user://puhe_puuttuu.txt", FileAccess.READ_WRITE if FileAccess.file_exists("user://puhe_puuttuu.txt") else FileAccess.WRITE)
			if f != null:
				f.seek_end()
				f.store_line("%s\t%s" % [voice, text.strip_edges()])
		return false
	var s := load(p) as AudioStream
	if s == null:
		return false
	var pl := AudioStreamPlayer.new()
	pl.stream = s
	pl.volume_db = vol_db
	pl.pitch_scale = clampf(pitch, 0.5, 3.0)
	add_child(pl)
	pl.finished.connect(func() -> void:
		_players.erase(pl)
		pl.queue_free())
	_players.append(pl)
	pl.play()
	return true


func speaking() -> bool:
	return not _players.is_empty()
