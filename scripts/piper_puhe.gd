extends Node
## Piper-puhesynteesi (ilmainen ja paikallinen): suomenkielinen Harri-ääni (CC0), josta chat.gd tekee hahmoille neljä
## miesääntä äänenkorkeuden ja nopeuden avulla. Asennus: tools/piper/asenna.sh (kansio piper/ pelin vieressä).
## Peli käynnistää Piperin HTTP-palvelimen taustalle ja sammuttaa sen lopetettaessa. Jos Piperiä ei ole asennettu
## (tai selain), speak() palauttaa false ja chat.gd käyttää käyttöjärjestelmän puhesynteesiä.

const PORT := 5123
const URL := "http://127.0.0.1:5123/"
const MODEL := "voices/fi_FI-harri-medium.onnx"

var is_up := false
var _pid := -1
var _http: HTTPRequest
var _probe: HTTPRequest
var _player: AudioStreamPlayer
var _queue: Array = []  # [teksti, äänenkorkeus, nopeus, voimakkuus 0..1]
var _busy := false
var _cur: Array = []
var _tries := 0


## Piperin kansio: pelin juuressa (editori) tai suoritettavan tiedoston vieressä (vienti, macOS-paketin vieressä).
static func find_dir() -> String:
	var cands := [ProjectSettings.globalize_path("res://").path_join("piper"), OS.get_executable_path().get_base_dir().path_join("piper"),
		OS.get_executable_path().get_base_dir().path_join("../../../piper").simplify_path()]
	for c: String in cands:
		if FileAccess.file_exists(c.path_join(MODEL)):
			return c
	return ""


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	var dir := find_dir()
	if dir == "":
		return
	_http = HTTPRequest.new()
	_http.request_completed.connect(_on_speech)
	add_child(_http)
	_probe = HTTPRequest.new()
	_probe.request_completed.connect(_on_probe)
	add_child(_probe)
	_player = AudioStreamPlayer.new()
	_player.finished.connect(_pump)
	add_child(_player)
	_check()


func _check() -> void:
	_probe.request(URL + "info")


func _on_probe(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		is_up = true
		return
	if _pid < 0:
		var dir := find_dir()
		var py := dir.path_join("venv/Scripts/python.exe") if OS.get_name() == "Windows" else dir.path_join("venv/bin/python")
		_pid = OS.create_process(py, ["-m", "piper.http_server", "-m", dir.path_join(MODEL), "--host", "127.0.0.1", "--port", str(PORT)])
	_tries += 1
	if _tries < 40 and _pid > 0:
		await get_tree().create_timer(1.0).timeout
		_check()


func _exit_tree() -> void:
	if _pid > 0:
		OS.kill(_pid)


func speaking() -> bool:
	return _busy or not _queue.is_empty() or (_player != null and _player.playing)


## Puhuu tekstin. pitch/rate: 1.0 = Harri sellaisenaan. Palauttaa false, jos Piper ei ole käytössä.
func speak(text: String, pitch: float, rate: float, volume: float) -> bool:
	if not is_up:
		return false
	_queue.append([text, pitch, rate, volume])
	_pump()
	return true


func _pump() -> void:
	if _busy or _queue.is_empty() or _player.playing:
		return
	_cur = _queue.pop_front()
	_busy = true
	# Toisto kiihdytetään äänenkorkeudella (pitch_scale), joten generoitu puhe venytetään vastaavasti.
	var ls := clampf(_cur[1] / _cur[2], 0.4, 2.5)
	_http.request(URL + "synthesize", ["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify({"text": _cur[0], "length_scale": ls}))


func _on_speech(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		var s := _wav(body)
		if s != null:
			_player.stream = s
			_player.pitch_scale = _cur[1]
			_player.volume_db = linear_to_db(maxf(_cur[3], 0.001))
			_player.play()
			return
	_pump()


## Piperin WAV (16-bittinen mono) AudioStreamWAViksi.
static func _wav(b: PackedByteArray) -> AudioStreamWAV:
	if b.size() < 48 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var rate := b.decode_u32(24)
	var i := 12
	while i + 8 <= b.size():
		var id := b.slice(i, i + 4).get_string_from_ascii()
		var n := b.decode_u32(i + 4)
		if id == "data":
			var s := AudioStreamWAV.new()
			s.format = AudioStreamWAV.FORMAT_16_BITS
			s.mix_rate = rate
			s.stereo = false
			s.data = b.slice(i + 8, mini(i + 8 + n, b.size()))
			return s
		i += 8 + n + (n & 1)
	return null
