extends CanvasLayer
## Alkuvalikko, taukovalikko (Esc) ja asetukset: grafiikka, ääni, ohjaus. Ohjeet ja tekijät.
## Peli on pysäytetty valikon ollessa auki; alkuvalikon taustalla kamera kiertää aloituspaikkaa.

const YELLOW := Color(1.0, 0.8, 0.1)
const CONTROLS := """JALAN
W / S	kävele eteen / taakse
A / D	käänny
Shift	juokse (kuluttaa kuntoa)
Välilyönti	hyppää
VEDESSÄ
W / S, A / D	ui (syvässä vedessä), kahlaa (matalassa)
E	nouse kumiveneeseen / veneestä
W / S, A / D	soutaa veneellä eteen / taakse, kääntää
ALAMÖKKI
E	istu lauteille, heitä löylyä
E	paista pyttipannua (vain Marko), istu pöytään (ristiseiska)
W / S	nouse / lopeta
E / Q	kätkö saunan takana rinteessä: olut / huikka viinaa
YLEISET
T (pohjassa)	kelaa aikaa 20 x (pelivuorokausi on 24 min)
M	kartta (koko 10 x 10 km alue)
V	FPS / kolmas persoona
Hiiri	kamera (Esc vapauttaa hiiren valikkoon)
Esc	taukovalikko
R	takaisin aloituspaikalle"""

var game: Node3D
var _root: Control
var _panel: PanelContainer
var _box: VBoxContainer
var _mode := ""  # main | pause
var _menu_cam: Camera3D
var _cam_t := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if visible:
			if _mode == "pause":
				close()
			elif _mode == "sub_main":
				open_main()
			elif _mode == "sub_pause":
				open_pause()
			get_viewport().set_input_as_handled()
		elif game != null and game.state == "play" and not game.map_open():
			open_pause()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _menu_cam != null and _menu_cam.current:
		_cam_t += delta
		var c: Vector3 = game.start_position()
		var a := _cam_t * 0.05
		_menu_cam.global_position = c + Vector3(cos(a) * 60.0, 22.0, sin(a) * 60.0)
		_menu_cam.look_at(c + Vector3(0, 2.0, 0), Vector3.UP)


# --- Näkymät -------------------------------------------------------------------

func open_main() -> void:
	_mode = "main"
	_show()
	if _menu_cam == null:
		_menu_cam = Camera3D.new()
		_menu_cam.fov = 55.0
		_menu_cam.far = 1500.0
		game.add_child(_menu_cam)
	_menu_cam.current = true
	game._hud.visible = false
	_title("OULUJÄRVEN NORPAT", "Ä P Ä T I N N I E M I  ·  V A A L A")
	_button("Aloita peli", _choose)
	_button("Moninpeli", _multi)
	_button("Asetukset", func() -> void: _settings("sub_main"))
	_button("Ohjaimet", func() -> void: _controls("sub_main"))
	_button("Tekijät", func() -> void: _credits("sub_main"))
	_button("Lopeta", func() -> void: get_tree().quit())


func open_pause() -> void:
	_mode = "pause"
	_show()
	_title("TAUKO", "Oulujärvi, Äpätti")
	_button("Jatka", close)
	_button("Asetukset", func() -> void: _settings("sub_pause"))
	_button("Ohjaimet", func() -> void: _controls("sub_pause"))
	_button("Takaisin aloituspaikalle", func() -> void:
		close()
		game.respawn())
	_button("Päävalikkoon", func() -> void:
		get_tree().paused = false
		get_tree().reload_current_scene())
	_button("Lopeta peli", func() -> void: get_tree().quit())


func close() -> void:
	visible = false
	get_tree().paused = false
	game.player.controls_enabled = game.activity == ""
	if _mode == "main" or _mode == "sub_main" or _mode == "online":
		game._hud.visible = true
		game.player.activate_camera()
	_mode = ""


## Hahmon ja ajankohdan valinta: pelaaja on yksi neljästä, muita ohjaa tietokone.
func _choose() -> void:
	_mode = "sub_main"
	_clear()
	_title("KUKA OLET?", "Muita mökkiläisiä ohjaa tietokone")
	var when := OptionButton.new()
	for p in game.Sun.PRESETS:
		when.add_item(p[0])
	when.selected = 0
	when.add_theme_font_size_override("font_size", 18)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.add_child(_label("Ajankohta", 18, Color.WHITE))
	row.add_child(when)
	for i in game.Porukka.CREW.size():
		var c: Dictionary = game.Porukka.CREW[i]
		_button(c.name, func() -> void:
			game.choose_character(i)
			game.respawn()
			game.sun.start_preset(when.selected)
			close())
		var d := _label(c.desc, 15, Color(0.85, 0.85, 0.8))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(560, 0)
		_box.add_child(d)
	_box.add_child(row)
	_button("Takaisin", open_main)


## Moninpeli: uusi huone tai liittyminen kaverin koodilla. Kukin ohjaa omaa mökkiläistään.
func _multi(status := "") -> void:
	_mode = "sub_main"
	_clear()
	_title("MONINPELI", "Kukin ohjaa omaa mökkiläistään, vapaita ohjaa tietokone")
	var when := OptionButton.new()
	for p in game.Sun.PRESETS:
		when.add_item(p[0])
	when.selected = 0
	when.add_theme_font_size_override("font_size", 18)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.add_child(_label("Ajankohta", 18, Color.WHITE))
	row.add_child(when)
	_box.add_child(row)
	var info := _label(status, 17, YELLOW)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(560, 0)
	_button("Luo uusi peli", func() -> void:
		info.text = "Yhdistetään…"
		_listen()
		game.mp.create(when.selected))
	var code := LineEdit.new()
	code.placeholder_text = "Huoneen koodi"
	code.max_length = 12
	code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code.custom_minimum_size = Vector2(320, 46)
	code.add_theme_font_size_override("font_size", 22)
	var go := func() -> void:
		if code.text.strip_edges().length() < 3:
			info.text = "Kirjoita kaverin huoneen koodi"
			return
		info.text = "Yhdistetään…"
		_listen()
		game.mp.join(code.text)
	code.text_submitted.connect(func(_t: String) -> void: go.call())
	_box.add_child(code)
	_button("Liity peliin", go)
	_box.add_child(info)
	_button("Takaisin", func() -> void:
		if game.mp.net.busy():
			get_tree().reload_current_scene()  # irti huoneesta ja hahmot alkutilaan
		else:
			open_main())


func _listen() -> void:
	if not game.mp.roster_changed.is_connected(_online_roster):
		game.mp.roster_changed.connect(_online_roster)
		game.mp.failed.connect(_online_failed)


func _online_roster() -> void:
	if not visible or _mode == "pause" or _mode == "sub_pause":
		return
	if game.mp.mine >= 0:
		_mode = "online"
		close()
		return
	_choose_online()


func _online_failed(why: String) -> void:
	if visible and _mode != "pause" and _mode != "sub_pause":
		_multi(why)


## Hahmon valinta moninpelissä: muiden pelaajien varaamat näkyvät varattuina.
func _choose_online() -> void:
	_mode = "sub_main"
	_clear()
	_title("KUKA OLET?", "Huone %s · kerro koodi kavereille" % game.mp.room())
	for i in game.Porukka.CREW.size():
		var c: Dictionary = game.Porukka.CREW[i]
		var taken: bool = game.mp.taken_by_other(i)
		_button(c.name + (" (pelaaja)" if taken else ""), func() -> void: game.mp.claim(i))
		var b: Button = _box.get_child(_box.get_child_count() - 1)
		b.disabled = taken
		var d := _label(c.desc, 15, Color(0.85, 0.85, 0.8))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(560, 0)
		_box.add_child(d)
	_box.add_child(_label("%d pelaajaa huoneessa" % game.mp.players(), 17, YELLOW))
	_button("Takaisin", func() -> void: get_tree().reload_current_scene())


func _back(from: String) -> void:
	if from == "sub_main":
		open_main()
	else:
		open_pause()


func _controls(from: String) -> void:
	_mode = from
	_clear()
	_title("OHJAIMET", "")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	for line in CONTROLS.split("\n"):
		var parts := line.split("\t")
		var k := _label(parts[0], 17, YELLOW if parts.size() == 1 else Color(0.9, 0.9, 0.85))
		grid.add_child(k)
		grid.add_child(_label(parts[1] if parts.size() > 1 else "", 17, Color.WHITE))
	_box.add_child(grid)
	_button("Takaisin", func() -> void: _back(from))


func _credits(from: String) -> void:
	_mode = from
	_clear()
	_title("TEKIJÄT", "")
	var lines := ["Oulujärven norpat – tehty Godot 4 -pelimoottorilla",
		"Kartta: Äpätti, Vaala (64.432089 N, 26.886448 E)"]
	lines.append_array(game.map_sources())
	lines.append_array(["Hahmot ja animaatiot: Quaternius (CC0)", "Äänet: OpenGameArt ja Kenney (CC0)"])
	for t in lines:
		var l := _label(t, 17, Color.WHITE)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(620, 0)
		_box.add_child(l)
	_button("Takaisin", func() -> void: _back(from))


func _settings(from: String) -> void:
	_mode = from
	_clear()
	_title("ASETUKSET", "")
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(560, 380)
	_box.add_child(tabs)
	var g := _tab(tabs, "Grafiikka")
	_option(g, "Laatu", Settings.QUALITY, Settings.get_v("quality"), func(i: int) -> void: Settings.set_v("quality", i))
	_check(g, "Koko näyttö", "fullscreen")
	_check(g, "Pystytahdistus (V-Sync)", "vsync")
	_slider(g, "Renderöintiskaala", "render_scale", 0.5, 1.0, 0.05, "%d %%", 100.0)
	_slider(g, "Näkökenttä (FOV)", "fov", 55.0, 95.0, 1.0, "%d°", 1.0)
	_check(g, "Näytä FPS", "show_fps")
	_check(g, "Näytä opasteet (paikkojen ja hahmojen nimet)", "show_guides")
	var note := _label("", 14, Color(0.8, 0.8, 0.8))
	var note_text := func() -> String:
		return "Käytössä nyt: %s. Vaihtuu, kun peli käynnistetään uudelleen." % Settings.RENDERERS[Settings.renderer_current()]
	_option(g, "Grafiikkamoottori", Settings.RENDERERS, Settings.renderer_saved(), func(i: int) -> void:
		Settings.set_renderer(i)
		note.text = note_text.call() if i != Settings.renderer_current() else "")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g.add_child(note)
	var a := _tab(tabs, "Ääni")
	_slider(a, "Kokonaisvoimakkuus", "vol_master", 0.0, 1.0, 0.05, "%d %%", 100.0)
	_slider(a, "Tehosteet", "vol_sfx", 0.0, 1.0, 0.05, "%d %%", 100.0)
	_slider(a, "Ympäristö", "vol_ambience", 0.0, 1.0, 0.05, "%d %%", 100.0)
	_slider(a, "Musiikki", "vol_music", 0.0, 1.0, 0.05, "%d %%", 100.0)
	var c := _tab(tabs, "Ohjaus")
	_slider(c, "Hiiren herkkyys", "mouse_sens", 0.3, 3.0, 0.1, "%.1f", 1.0)
	_check(c, "Käänteinen pystyakseli", "invert_y")
	_check(c, "Hiiri kääntää kameraa", "mouse_look")
	_check(c, "Kamera palaa itsestään taakse", "auto_recenter")
	_button("Takaisin", func() -> void: _back(from))


# --- Rakennuspalikat ------------------------------------------------------------

func _show() -> void:
	visible = true
	get_tree().paused = true
	game.player.controls_enabled = false  # moninpelissä hahmot liikkuvat valikonkin aikana
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear()


func _clear() -> void:
	for ch in _root.get_children():
		ch.queue_free()
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.35 if _mode.begins_with("main") or _mode == "sub_main" else 0.55)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.09, 0.88)
	sb.border_color = YELLOW
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	_panel.add_theme_stylebox_override("panel", sb)
	center.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_box)


func _title(text: String, sub: String) -> void:
	var t := _label(text, 64, YELLOW)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Impact", "Arial Black", "Helvetica Neue"])
	f.font_weight = 900
	t.add_theme_font_override("font", f)
	t.add_theme_constant_override("outline_size", 12)
	_box.add_child(t)
	if sub != "":
		_box.add_child(_label(sub, 20, Color.WHITE))


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	return l


func _button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 46)
	b.add_theme_font_size_override("font_size", 22)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color(0.18, 0.16, 0.2), "hover": Color(0.85, 0.35, 0.05), "pressed": Color(1.0, 0.45, 0.1),
			"focus": Color(0.18, 0.16, 0.2)}[st]
		sb.border_color = YELLOW if st == "focus" else Color(0.4, 0.35, 0.3)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	_box.add_child(b)
	if _box.get_child_count() <= 3:
		b.call_deferred("grab_focus")


func _tab(tabs: TabContainer, name: String) -> VBoxContainer:
	var m := MarginContainer.new()
	m.name = name
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 16)
	tabs.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return v


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := _label(text, 18, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(250, 0)
	h.add_child(l)
	parent.add_child(h)
	return h


func _check(parent: Control, text: String, key: String) -> void:
	var h := _row(parent, text)
	var c := CheckButton.new()
	c.button_pressed = Settings.get_v(key)
	c.toggled.connect(func(on: bool) -> void: Settings.set_v(key, on))
	h.add_child(c)


func _option(parent: Control, text: String, items: Array, sel: int, cb: Callable) -> void:
	var h := _row(parent, text)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.selected = sel
	o.item_selected.connect(cb)
	o.custom_minimum_size = Vector2(200, 0)
	h.add_child(o)


func _slider(parent: Control, text: String, key: String, lo: float, hi: float, step: float, fmt: String, mul: float) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Settings.get_v(key)
	s.custom_minimum_size = Vector2(200, 24)
	h.add_child(s)
	var v := _label(fmt % (s.value * mul), 18, YELLOW)
	v.custom_minimum_size = Vector2(70, 0)
	h.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt % (x * mul)
		Settings.set_v(key, x))
