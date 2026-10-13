extends SceneTree
## Äänilinkin testi (headless, ilman palvelinta): godot --headless --path . -s tools/testit/aanilinkkitesti.gd
## Pakkaus ja purku (aanilinkki.gd), bitilleen sama pakkaus kuin selaimessa (aanilinkki.js, vertailu Nodella,
## jos se on asennettu), puhe lähtee vain äänen ylittäessä kynnyksen, mykistys, ja toisen pelaajan puhe päätyy
## soittimeen. Kaksi äänilinkkiä on kytketty toisiinsa valemoninpelillä (Fake), joka välittää viestit suoraan.

## Ladataan vasta käynnistyttyä: skripti käyttää autoloadeja (Settings), jotka eivät ole vielä käännösaikana.
var Aanilinkki: GDScript


class FakeNet:
	extends Node
	signal peer_joined(id: int)
	signal peer_left(id: int)
	var peers: Array[int] = []


class Fake:
	extends Node
	var net := FakeNet.new()
	var game: Node = null
	var owners := {}
	var id := 0
	var other: Fake
	var sent: Array = []
	var _handlers := {}

	func online() -> bool:
		return true

	func on(type: String, cb: Callable) -> void:
		_handlers[type] = cb

	func send(d: Dictionary) -> void:
		sent.append(d)
		if other != null and other._handlers.has(d.t):
			other._handlers[d.t].call(d, id)


var a: Fake
var b: Fake
var va: Node
var vb: Node
var fails := 0
var frames := 0


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


## Sama kokonaisluvuista laskettu signaali kuin aanilinkki_js.mjs:ssä.
func signal_frames(n: int) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	x.resize(n * Aanilinkki.FRAME)
	for k in x.size():
		var p := absi((k * 37) % 4000 - 2000) - 1000
		var q := absi((k * 211) % 600 - 300) - 150
		x[k] = (p * 12 + q * 20) / 32767.0
	return x


func _initialize() -> void:
	Aanilinkki = load("res://scripts/aanilinkki.gd")
	root.get_node("Settings").values.voice_mic = false  # ei oikeaa mikkiä testissä (ei tallenneta)
	a = Fake.new()
	b = Fake.new()
	a.id = 1
	b.id = 2
	a.other = b
	b.other = a
	a.net.peers = [2]
	b.net.peers = [1]
	for f: Fake in [a, b]:
		f.add_child(f.net)
		root.add_child(f)
	va = Aanilinkki.new()
	va.mp = a
	a.add_child(va)
	vb = Aanilinkki.new()
	vb.mp = b
	b.add_child(vb)


func _process(_d: float) -> bool:
	frames += 1
	match frames:
		2:
			_codec()
			_gate()
		10:
			var pr: Dictionary = vb._peers.get(1, {})
			var pb: AudioStreamGeneratorPlayback = pr.player.get_stream_playback() if pr.has("player") else null
			var buffered: int = -1
			if pb != null:
				buffered = int((Aanilinkki.MAX_LAG + 0.2) * Aanilinkki.RATE) - pb.get_frames_available()
			print("  vastaanottaja: jonossa %d, soittimessa %d näytettä" % [pr.get("queue", []).size(), buffered])
			check(pr.get("playing", false) and buffered >= Aanilinkki.FRAME, "toisen puhe soi")
			check("Santtu" in vb._label.text or "Pelaaja 1 puhuu" in vb._label.text, "näkyy kuka puhuu: %s" % vb._label.text.replace("\n", " | "))
			va.set_muted(true)
		12:
			check(vb._peers[1].muted, "mykistys näkyy muille")
			a.sent.clear()
			va.feed(signal_frames(1))
			check(a.sent.is_empty(), "mykistettynä puhe ei lähde")
		40:
			check("mykistetty" in vb._label.text, "näkyy kuka on mykistetty: %s" % vb._label.text.replace("\n", " | "))
			print("vikoja ", fails)
			quit(fails)
			return true
	return false


func _codec() -> void:
	var x := signal_frames(5)
	var st := [0, 0]
	var enc := []
	var e := 0.0
	var n := 0.0
	for f in 5:
		var fr := x.slice(f * Aanilinkki.FRAME, (f + 1) * Aanilinkki.FRAME)
		var bytes: PackedByteArray = Aanilinkki.encode(fr, st)
		enc.append(Marshalls.raw_to_base64(bytes))
		var y: PackedFloat32Array = Aanilinkki.decode(bytes)
		for k in fr.size():
			e += fr[k] * fr[k]
			n += (fr[k] - y[k]) * (fr[k] - y[k])
	var snr := 10.0 * log(e / n) / log(10.0)
	check(snr > 20.0, "pakkaus ja purku: SNR %.1f dB" % snr)
	var out := []
	var code := OS.execute("node", [ProjectSettings.globalize_path("res://tools/testit/aanilinkki_js.mjs"), "--vertailu"], out)
	if code != 0 or out.is_empty():
		print("  (Node puuttuu: selaimen pakkausta ei verrattu)")
		return
	var js: Dictionary = JSON.parse_string(out[0])
	check(js.enc == enc, "selain pakkaa bitilleen samoin kuin työpöytä")
	var dec: PackedFloat32Array = Aanilinkki.decode(Marshalls.base64_to_raw(enc[4]))
	var sum := 0
	for v in dec:
		sum += roundi(v * 32768.0)
	check(int(js.sum) == sum, "selain purkaa samoin kuin työpöytä")


func _gate() -> void:
	var quiet := PackedFloat32Array()
	quiet.resize(Aanilinkki.FRAME)
	var loud := signal_frames(1)
	a.sent.clear()
	va.feed(quiet)
	check(a.sent.is_empty(), "hiljaisuus ei lähde")
	va.feed(loud)
	for k in Aanilinkki.HANG + 3:
		va.feed(quiet)
	var n := 0
	for d in a.sent:
		if d.t == "v":
			n += 1
	check(n == 1 + Aanilinkki.HANG, "puhe ja %d kehystä jälkiääntä lähti (%d)" % [Aanilinkki.HANG, n])
	check(a.sent[0].d.length() < 700, "kehys %d merkkiä (alle palvelimen 8192)" % a.sent[0].d.length())
