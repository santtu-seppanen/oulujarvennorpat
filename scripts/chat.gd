extends Node
## Keskustelu: Enter avaa kirjoitusrivin vasempaan alakulmaan, Enter lähettää ja Esc peruu. Viesti näkyy
## puhekuplana hahmon pään yläpuolella ja keskusteluhistoriassa. Moninpelissä viesti lähtee kaikille (viesti
## "chat"), ja sen saa lähettää vain hahmoa ohjaava pelaaja. Kirjoittaessa hahmo ei liiku (typing: on_foot.gd ja
## main.gd lukevat sitä).
##
## Tietokoneen hahmojen puheet (ai_say) näkyvät hostilla ja lähtevät hostilta kaikille (viesti "chat_ai"); vain
## host ohjaa tietokoneen hahmoja. Puhekuplat luetaan ääneen käyttöjärjestelmän puhesynteesillä (asetus "tts"),
## suomenkielisellä äänellä, jos sellainen on: kullakin hahmolla oma äänenkorkeus ja voimakkuus hiljenee
## etäisyyden mukaan. Tutkimusmatkalla alun huutojen jälkeen ei puhuta ääneen ennen perillä oloa (tutkimusmatka.gd
## allows_speech).

const MAX_LEN := 120
const LOG_LINES := 7
const LOG_SECS := 20.0  # historian rivi häipyy näin kauan viestin jälkeen (kirjoittaessa näkyy aina)
## Puhesynteesi hahmoittain: toivottu ääni (osa äänen tunnusta, macOS:n suomenkieliset äänet), äänenkorkeus ja
## nopeus. Jos ääntä ei ole, käytetään ensimmäistä suomenkielistä (tai englanninkielistä) ääntä.
const VOICE := {"Santtu": ["Eddy", 1.1, 1.05], "Marko": ["Rocko", 0.8, 0.95], "Jaakko": ["Reed", 1.0, 1.1],
	"Jukka": ["Grandpa", 0.9, 1.0]}

static var typing := false

var game: Node3D
var _ui: CanvasLayer
var _log: VBoxContainer
var _edit: LineEdit
var _bubbles := {}  # hahmon indeksi -> [Label3D, jäljellä oleva aika]
var _lines: Array = []  # [Label, aika]
var _voices: Array = []  # käytettävissä olevat äänet (tyhjä = ei puhesynteesiä)
var _voices_read := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	typing = false
	game.mp.on("chat", func(d: Dictionary, from: int) -> void:
		var i := int(d.get("i", -1))
		if i >= 0 and i < game.crew.size() and game.mp.owners.get(i, -1) == from:
			show_message(i, str(d.get("m", ""))))
	game.mp.on("chat_ai", func(d: Dictionary, from: int) -> void:
		var i := int(d.get("i", -1))
		if i >= 0 and i < game.crew.size() and from == game.mp.net.host_id and game.crew_modes[i] != "player":
			show_message(i, str(d.get("m", ""))))
	_build_ui()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 22
	add_child(_ui)
	var box := VBoxContainer.new()
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 20
	box.offset_right = 520
	box.offset_top = -330
	box.offset_bottom = -150
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_ui.add_child(box)
	_log = VBoxContainer.new()
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_constant_override("separation", 0)
	box.add_child(_log)
	_edit = LineEdit.new()
	_edit.max_length = MAX_LEN
	_edit.placeholder_text = "Kirjoita viesti muille, Enter lähettää, Esc peruu"
	_edit.virtual_keyboard_enabled = true  # kosketusnäytöllä näppäimistö aukeaa ("Viesti"-nappi)
	_edit.custom_minimum_size = Vector2(480, 34)
	_edit.add_theme_font_size_override("font_size", 17)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.09, 0.85)
	sb.border_color = Color(1.0, 0.8, 0.1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	_edit.add_theme_stylebox_override("normal", sb)
	_edit.add_theme_stylebox_override("focus", sb)
	_edit.visible = false
	_edit.text_submitted.connect(_submit)
	_edit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
			close()
			_edit.accept_event())
	_edit.focus_exited.connect(close)
	box.add_child(_edit)
	# Kosketusnäytöllä ei ole Enteriä: oma nappi.
	if Touch.active:
		var b := Button.new()
		b.text = "Viesti"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(90, 40)
		b.pressed.connect(open)
		box.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if typing or game.state != "play" or get_tree().paused:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_KP_ENTER):
		open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if game.state != "play" or get_tree().paused:
		return
	typing = true
	_edit.text = ""
	_edit.visible = true
	_edit.grab_focus()
	_show_log()


func close() -> void:
	if not typing:
		return
	typing = false
	_edit.visible = false
	_edit.release_focus()


func _submit(text: String) -> void:
	close()
	say(text)


## Oma viesti: kupla oman hahmon yläpuolelle ja kaikille muille.
func say(text: String) -> void:
	text = text.strip_edges().left(MAX_LEN)
	if text == "":
		return
	var i: int = game.player_index
	show_message(i, text)
	game.mp.send({"t": "chat", "i": i, "m": text})


## Tietokoneen hahmon i puhe: kupla tällä koneella, ja hostilta kaikille muillekin.
func ai_say(i: int, text: String) -> void:
	show_message(i, text)
	if game.mp.online() and game.mp.net.is_host():
		game.mp.send({"t": "chat_ai", "i": i, "m": text.strip_edges().left(MAX_LEN)})


## Puhesynteesi: viesti ääneen hahmon omalla äänellä, hiljempaa kauempana kamerasta.
func _speak(i: int, text: String) -> void:
	if not Settings.get_v("tts") or DisplayServer.get_name() == "headless" or not game.retki.allows_speech(text):
		return
	if not _voices_read:
		_voices_read = true
		_voices = Array(DisplayServer.tts_get_voices_for_language("fi"))
		if _voices.is_empty():
			_voices = Array(DisplayServer.tts_get_voices_for_language("en"))
	if _voices.is_empty():
		return
	var b: CharacterBody3D = game.crew[i]
	var cam := get_viewport().get_camera_3d()
	var dist: float = b.global_position.distance_to(cam.global_position) if cam != null else 0.0
	var vol: float = Settings.get_v("vol_speech") * Settings.get_v("vol_master") * clampf(1.0 - dist / 60.0, 0.2, 1.0)
	var vp: Array = VOICE.get(game.Porukka.CREW[i].name, ["", 1.0, 1.0])
	var voice: String = _voices[0]
	for v: String in _voices:
		if vp[0] != "" and v.contains(vp[0]):
			voice = v
	DisplayServer.tts_speak(text, voice, int(vol * 100.0), vp[1], vp[2])


## Viesti hahmolta i: puhekupla pään yläpuolelle ja rivi historiaan.
func show_message(i: int, text: String) -> void:
	text = text.strip_edges().left(MAX_LEN)
	if text == "":
		return
	var b: CharacterBody3D = game.crew[i]
	var l: Label3D
	if _bubbles.has(i):
		l = _bubbles[i][0]
	else:
		l = Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 40
		l.pixel_size = 0.0035
		l.outline_size = 16
		l.outline_modulate = Color(0.02, 0.02, 0.03, 0.95)
		l.modulate = Color(1.6, 1.6, 1.5)  # sävykartoitus himmentää valkoisen harmaaksi
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = 520
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		l.no_depth_test = true  # näkyy myös seinän ja katon takaa
		b.add_child(l)
	l.text = text
	_bubbles[i] = [l, clampf(4.0 + text.length() * 0.08, 5.0, 12.0)]
	_speak(i, text)
	if i == game.player_index:
		Sfx.play("pickup", -18.0, 1.6)
	else:
		Sfx.play_on(b, "pickup", -14.0, 1.6)
	var line := Label.new()
	line.text = "%s: %s" % [game.Porukka.CREW[i].name, text]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(480, 0)
	line.add_theme_font_size_override("font_size", 16)
	line.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55) if i == game.player_index else Color.WHITE)
	line.add_theme_color_override("font_outline_color", Color.BLACK)
	line.add_theme_constant_override("outline_size", 5)
	_log.add_child(line)
	_lines.append([line, LOG_SECS])
	while _lines.size() > LOG_LINES:
		_lines.pop_front()[0].queue_free()


func _show_log() -> void:
	for e in _lines:
		e[0].modulate.a = 1.0


func _process(delta: float) -> void:
	for i in _bubbles.keys():
		var e: Array = _bubbles[i]
		e[1] -= delta
		var l: Label3D = e[0]
		var b: CharacterBody3D = game.crew[i]
		# Oma kupla ei näy silmien kohdalla FPS-kuvakulmassa; sisällä olevan kupla ei näy seinien läpi.
		l.visible = not (b.is_player and CamCtl.fps) and not b.hidden_inside
		l.position = Vector3(0, 1.75 if b.pose.begins_with("Sitting") else 2.45, 0)
		l.modulate.a = clampf(e[1], 0.0, 1.0)
		# Kauempaa kupla kasvaa, jotta sen erottaa vielä pihan toiselta laidalta.
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			l.scale = Vector3.ONE * clampf(l.global_position.distance_to(cam.global_position) / 6.0, 1.0, 4.0)
		l.outline_modulate.a = l.modulate.a * 0.95
		if e[1] <= 0.0:
			l.queue_free()
			_bubbles.erase(i)
	for e in _lines:
		e[1] -= delta
		e[0].modulate.a = 1.0 if typing else clampf(e[1], 0.0, 1.0)
