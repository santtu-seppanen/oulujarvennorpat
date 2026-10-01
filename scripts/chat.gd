extends Node
## Keskustelu: Enter avaa kirjoitusrivin vasempaan alakulmaan, Enter lähettää ja Esc peruu. Viesti näkyy
## puhekuplana hahmon pään yläpuolella ja keskusteluhistoriassa. Moninpelissä viesti lähtee kaikille (viesti
## "chat"), ja sen saa lähettää vain hahmoa ohjaava pelaaja. Kirjoittaessa hahmo ei liiku (typing: on_foot.gd ja
## main.gd lukevat sitä).

const MAX_LEN := 120
const LOG_LINES := 7
const LOG_SECS := 20.0  # historian rivi häipyy näin kauan viestin jälkeen (kirjoittaessa näkyy aina)

static var typing := false

var game: Node3D
var _ui: CanvasLayer
var _log: VBoxContainer
var _edit: LineEdit
var _bubbles := {}  # hahmon indeksi -> [Label3D, jäljellä oleva aika]
var _lines: Array = []  # [Label, aika]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	typing = false
	game.mp.on("chat", func(d: Dictionary, from: int) -> void:
		var i := int(d.get("i", -1))
		if i >= 0 and i < game.crew.size() and game.mp.owners.get(i, -1) == from:
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
	_edit.placeholder_text = "Kirjoita viesti, Enter lähettää, Esc peruu"
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
