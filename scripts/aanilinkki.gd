extends Node
## Äänilinkki moninpelissä kuin palaverissa: oma mikki kuuluu kaikille huoneessa, kaikki yhtä kovaa (ei sijaintia).
## - Mikki on auki liityttäessä (asetukset → Ääni → Äänilinkki: mikrofoni), N mykistää ja avaa. Ruudun
##   oikeassa yläkulmassa näkyy, kuka puhuu ja kuka on mykistänyt itsensä.
## - Puhe lähtee vain, kun mikissä on ääntä (GATE, HANG kehystä jälkiääntä), joten hiljaisuus ei kuormita yhteyttä.
## - Pakkaus: 16 kHz mono, IMA ADPCM (4 bittiä näytteelle, n. 8 kt/s puhujaa kohden), 960 näytettä (60 ms)
##   kehyksessä, otsakkeena ennustin (int16 LE) ja askelindeksi. Kehykset kulkevat välityspalvelimen kautta
##   (server/, viesti "v"; mykistys "vm"), joten selain ja työpöytäversio kuulevat toisensa.
## - Työpöytäversio: mikki AudioStreamMicrophonella mykistetylle Mic-väylälle, josta AudioEffectCapture lukee
##   näytteet; toisten puhe AudioStreamGeneratorilla, pieni puskuri puheen alussa (PREBUF). Kaiunpoistoa ei ole,
##   joten kuulokkeet ovat suositeltavat.
## - Selain: mikki ja toisto aanilinkki.js:ssä (getUserMedia kaiunpoistolla, Web Audio), koska säikeettömässä
##   buildissa Godot miksaa pääsäikeessä eikä tue väyläefektejä näytetoistossa.

const Chat := preload("res://scripts/chat.gd")
const RATE := 16000
const FRAME := 960
const GATE := 0.008  # kehyksen RMS, jonka ylittyessä puhe lähtee (sama kuin aanilinkki.js)
const HANG := 8  # kehystä hiljaisuutta ennen kuin lähetys taukoaa
const PREBUF := 0.12  # s: puheen alussa puskuria ennen soittoa
const MAX_LAG := 0.5  # s: tätä enempää viivettä ei kerätä (kehyksiä pudotetaan)
const TALK_SHOW := 0.35  # s: "puhuu" näkyy näin kauan viimeisen kehyksen jälkeen
const JS := "res://scripts/aanilinkki.js"
const IT := [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]
const ST := [7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80,
	88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724,
	796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428,
	4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385,
	24623, 27086, 29794, 32767]

var mp: Node  # moninpeli.gd
var muted := false
var talking := false  # oma puhe lähtee juuri nyt
var mic_on := false
var _web := OS.has_feature("web")
var _js_ok := false
var _online := false
var _cap: AudioEffectCapture
var _mic: AudioStreamPlayer
var _rs_pos := 0.0  # mikin näytteistys 16 kHz:iin
var _rs_acc := 0.0
var _rs_n := 0
var _pcm := PackedFloat32Array()  # 16 kHz näytteitä odottamassa kehystä
var _enc := [0, 0]  # ennustin, askelindeksi
var _hang := 0
var _peers := {}  # tunnus -> {player, queue, playing, wait, talk, muted}
var _hud: CanvasLayer
var _label: Label
var _err_shown := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hud = CanvasLayer.new()
	_hud.layer = 5
	add_child(_hud)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.offset_left = -360
	_label.offset_right = -20
	_label.offset_top = 16
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_size_override("font_size", 17)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_label)
	_hud.visible = false
	mp.on("v", _on_voice)
	mp.on("vm", func(d: Dictionary, from: int) -> void: _peer(from).muted = bool(d.get("m", false)))
	mp.net.peer_joined.connect(func(_id: int) -> void: _send_mute())
	mp.net.peer_left.connect(_drop_peer)
	Settings.changed.connect(_apply_settings)


func _exit_tree() -> void:
	_mic_stop()


# --- Pakkaus (sama kuin aanilinkki.js) ----------------------------------------------------------------------

## Kehys (näytteet -1..1) tavuiksi; st = [ennustin, askelindeksi] jatkuu kehyksestä toiseen.
static func encode(x: PackedFloat32Array, st: Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4 + x.size() / 2)
	var p: int = st[0]
	var i: int = st[1]
	out[0] = p & 0xff
	out[1] = (p >> 8) & 0xff
	out[2] = i
	for k in x.size():
		var s := clampi(roundi(x[k] * 32767.0), -32768, 32767)
		var diff := s - p
		var nib := 0
		if diff < 0:
			nib = 8
			diff = -diff
		var step: int = ST[i]
		var vp := step >> 3
		if diff >= step:
			nib |= 4
			diff -= step
			vp += step
		step >>= 1
		if diff >= step:
			nib |= 2
			diff -= step
			vp += step
		step >>= 1
		if diff >= step:
			nib |= 1
			vp += step
		p = clampi(p - vp if nib & 8 else p + vp, -32768, 32767)
		i = clampi(i + IT[nib], 0, 88)
		if k & 1:
			out[4 + (k >> 1)] |= nib << 4
		else:
			out[4 + (k >> 1)] = nib
	st[0] = p
	st[1] = i
	return out


static func decode(b: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if b.size() < 5:
		return out
	var n := (b.size() - 4) * 2
	out.resize(n)
	var p := b[0] | (b[1] << 8)
	if p >= 32768:
		p -= 65536
	var i := mini(88, b[2])
	for k in n:
		var nib := b[4 + (k >> 1)] >> 4 if k & 1 else b[4 + (k >> 1)] & 15
		var step: int = ST[i]
		var vp := step >> 3
		if nib & 4:
			vp += step
		if nib & 2:
			vp += step >> 1
		if nib & 1:
			vp += step >> 2
		p = clampi(p - vp if nib & 8 else p + vp, -32768, 32767)
		i = clampi(i + IT[nib], 0, 88)
		out[k] = p / 32768.0
	return out


static func rms(x: PackedFloat32Array) -> float:
	var e := 0.0
	for v in x:
		e += v * v
	return sqrt(e / maxi(1, x.size()))


# --- Elinkaari ----------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var on: bool = mp.online()
	if on != _online:
		_online = on
		_hud.visible = on
		if on:
			_err_shown = false
			_apply_settings()
			_send_mute()
		else:
			_mic_stop()
			for id in _peers.keys():
				_drop_peer(id)
	if not on:
		return
	if _web:
		_web_poll()
	else:
		_desktop_capture()
	for id in _peers:
		var pr: Dictionary = _peers[id]
		pr.talk = maxf(0.0, pr.talk - delta)
		if not _web:
			_desktop_play(pr, delta)
	_update_label()


func _input(event: InputEvent) -> void:
	if _online and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_N and not Chat.typing:
		set_muted(not muted)
		get_viewport().set_input_as_handled()


func set_muted(m: bool) -> void:
	muted = m
	if _web and _js_ok:
		JavaScriptBridge.eval("NorpatVoice.setMuted(%s)" % ("true" if m else "false"))
	_send_mute()
	if mp.game != null:
		mp.game.toast("Mikki mykistetty (N avaa)" if m else "Mikki auki – muut kuulevat sinut (N mykistää)", 2.5)


func _send_mute() -> void:
	mp.send({"t": "vm", "m": muted or not Settings.get_v("voice_mic")})


func _apply_settings() -> void:
	var vol: float = Settings.get_v("vol_voice") * Settings.get_v("vol_master")
	if _web:
		if _load_js():
			JavaScriptBridge.eval("NorpatVoice.setVolume(%f)" % vol)
	else:
		for id in _peers:
			_peers[id].player.volume_db = linear_to_db(maxf(vol, 0.0001))
	if not _online:
		return
	if Settings.get_v("voice_mic"):
		_mic_start()
	else:
		_mic_stop()
	_send_mute()


func _load_js() -> bool:
	if _js_ok:
		return true
	var src := FileAccess.get_file_as_string(JS)
	if src == "":
		push_warning("Äänilinkki: %s puuttuu" % JS)
		return false
	JavaScriptBridge.eval(src, true)
	_js_ok = true
	return true


func _mic_start() -> void:
	if mic_on:
		return
	mic_on = true
	if _web:
		if _load_js():
			JavaScriptBridge.eval("NorpatVoice.setMuted(%s); NorpatVoice.start()" % ("true" if muted else "false"))
		return
	var i := AudioServer.get_bus_index("Mic")
	if i < 0:
		AudioServer.bus_count += 1
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Mic")
		AudioServer.set_bus_mute(i, true)  # oma ääni ei omiin kaiuttimiin; kaappaus toimii silti
		var cap := AudioEffectCapture.new()
		cap.buffer_length = 0.5
		AudioServer.add_bus_effect(i, cap)
	_cap = AudioServer.get_bus_effect(i, 0)
	_cap.clear_buffer()
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	_mic.play()


func _mic_stop() -> void:
	if not mic_on:
		return
	mic_on = false
	talking = false
	if _web:
		if _js_ok:
			JavaScriptBridge.eval("NorpatVoice.stop()")
		return
	if _mic != null:
		_mic.stop()
		_mic.queue_free()
		_mic = null
	_cap = null
	_pcm.clear()
	_hang = 0


# --- Lähetys ------------------------------------------------------------------------------------------------

## Työpöytä: mikin näytteet 16 kHz:iin (keskiarvo kunkin lähtönäytteen väliltä) ja kehyksiksi.
func _desktop_capture() -> void:
	if _cap == null:
		return
	var n := _cap.get_frames_available()
	if n <= 0:
		return
	var buf := _cap.get_buffer(n)
	var r := AudioServer.get_mix_rate() / RATE
	for f in buf:
		_rs_acc += (f.x + f.y) * 0.5
		_rs_n += 1
		_rs_pos += 1.0
		if _rs_pos >= r:
			_rs_pos -= r
			_pcm.append(_rs_acc / _rs_n)
			_rs_acc = 0.0
			_rs_n = 0
	while _pcm.size() >= FRAME:
		feed(_pcm.slice(0, FRAME))
		_pcm = _pcm.slice(FRAME)


## Yksi 16 kHz:n kehys mikistä: lähtee muille, jos siinä on puhetta (tai jälkiääntä).
func feed(x: PackedFloat32Array) -> void:
	var loud := rms(x) > GATE
	if muted or (not loud and _hang <= 0):
		talking = false
		return
	_hang = HANG if loud else _hang - 1
	talking = true
	mp.send({"t": "v", "d": Marshalls.raw_to_base64(encode(x, _enc))})


## Selain: aanilinkki.js:n kehykset verkkoon ja mikin tila.
func _web_poll() -> void:
	if not _js_ok:
		return
	var d: Variant = JSON.parse_string(str(JavaScriptBridge.eval("NorpatVoice.take()")))
	if not d is Dictionary:
		return
	for f in d.get("f", []):
		mp.send({"t": "v", "d": f})
	talking = bool(d.get("talk", false))
	var e: String = d.get("e", "")
	if e != "" and not _err_shown:
		_err_shown = true
		mic_on = false
		if mp.game != null:
			mp.game.toast("Mikkiin ei saatu lupaa: salli mikrofoni selaimen osoiterivin lukosta." if e == "lupa"
				else "Mikki ei käynnistynyt (%s)." % e, 6.0)


# --- Vastaanotto ----------------------------------------------------------------------------------------------

func _peer(id: int) -> Dictionary:
	if not _peers.has(id):
		var pr := {"player": null, "queue": [], "playing": false, "wait": 0.0, "talk": 0.0, "muted": false}
		if not _web:
			var gen := AudioStreamGenerator.new()
			gen.mix_rate = RATE
			gen.buffer_length = MAX_LAG + 0.2
			var p := AudioStreamPlayer.new()
			p.stream = gen
			var vol: float = Settings.get_v("vol_voice") * Settings.get_v("vol_master")
			p.volume_db = linear_to_db(maxf(vol, 0.0001))
			add_child(p)
			p.play()
			pr.player = p
		_peers[id] = pr
	return _peers[id]


func _drop_peer(id: int) -> void:
	if _peers.has(id):
		var p: AudioStreamPlayer = _peers[id].player
		if p != null:
			p.stop()
			p.queue_free()
		_peers.erase(id)


func _on_voice(d: Dictionary, from: int) -> void:
	var s: String = d.get("d", "")
	if s == "":
		return
	var pr := _peer(from)
	pr.talk = TALK_SHOW
	if _web:
		if _load_js():
			JavaScriptBridge.eval("NorpatVoice.play(%d, \"%s\")" % [from, s.c_escape()])
		return
	pr.queue.append(decode(Marshalls.base64_to_raw(s)))
	# Ruuhka (esim. yhteys tökkäsi): vanhimmat pois, ettei viive kasva.
	while pr.queue.size() * FRAME > MAX_LAG * RATE:
		pr.queue.pop_front()


## Työpöytä: jonossa olevat kehykset generaattoriin. Puheen alussa odotetaan PREBUF verran, jotta verkon
## heittely ei katko puhetta.
func _desktop_play(pr: Dictionary, delta: float) -> void:
	var p: AudioStreamPlayer = pr.player
	var pb := p.get_stream_playback() as AudioStreamGeneratorPlayback
	if pb == null:
		return
	var cap := int((MAX_LAG + 0.2) * RATE)
	var buffered := cap - pb.get_frames_available()
	if not pr.playing:
		if pr.queue.is_empty():
			pr.wait = 0.0
			return
		pr.wait += delta
		if pr.queue.size() * FRAME < PREBUF * RATE and pr.wait < PREBUF * 2.0:
			return
		pr.playing = true
	while not pr.queue.is_empty() and pb.get_frames_available() >= FRAME:
		var x: PackedFloat32Array = pr.queue.pop_front()
		var st := PackedVector2Array()
		st.resize(x.size())
		for k in x.size():
			st[k] = Vector2(x[k], x[k])
		pb.push_buffer(st)
		buffered += x.size()
	if pr.queue.is_empty() and buffered < FRAME / 4:
		pr.playing = false  # puhe tauolla: seuraava alku puskuroidaan taas


# --- Näyttö ---------------------------------------------------------------------------------------------------

## Pelaajan nimi: hänen mökkiläisensä (moninpeli.gd owners).
func _name(id: int) -> String:
	for j in mp.owners:
		if mp.owners[j] == id and mp.game != null and j < mp.game.crew.size():
			return mp.game.crew[j].display_name
	return "Pelaaja %d" % id


func _update_label() -> void:
	var lines := PackedStringArray()
	if not Settings.get_v("voice_mic"):
		lines.append("Äänilinkki: mikki pois asetuksista")
	elif muted:
		lines.append("Mikki mykistetty · N avaa")
	elif not mic_on:
		lines.append("Mikki ei käytössä")
	else:
		lines.append(("Puhut · " if talking else "Mikki auki · ") + "N mykistää")
	for id in mp.net.peers:
		var pr: Dictionary = _peers.get(id, {})
		if pr.get("talk", 0.0) > 0.0:
			lines.append("%s puhuu" % _name(id))
		elif pr.get("muted", false):
			lines.append("%s · mykistetty" % _name(id))
	_label.text = "\n".join(lines)
	_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if talking else Color(1, 1, 1, 0.85))
