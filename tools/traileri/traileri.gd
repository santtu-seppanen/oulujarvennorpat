extends SceneTree
## Pelin traileri pelikuvasta (Godotin Movie Maker): ensin pelin oma saapumiskohtaus (scripts/saapuminen.gd), sitten
## kohtaukset tools/traileri/leikkaus.gd:stä ja lopuksi oodi Oulujärvelle. Kuvassa on vain otsikoita ja mustat siirtymät.
## Video on äänetön; vain biisin ääni liitetään ffmpegillä (kokoa.sh), ei puhetta eikä pelin ääniä.
##
##   godot --path . --write-movie ~/traileri/traileri.avi --fixed-fps 30 --resolution 1280x720 \
##     -s tools/traileri/traileri.gd
##
## Valinnat (-- jälkeen): --kuvat=<kansio> tallentaa kuvan sekunnin välein PNG:nä, --loppu=<s> lopettaa tähän aikaan,
## --alku=<n> aloittaa kohtauksesta n (0 = saapuminen; esikatselu). Lopuksi kirjoitetaan aikamerkit (tiedosto
## traileri_ajat.txt kansioon, jossa video on) kokoa.sh:ta varten.

const FPS := 30.0
const FADE := 0.3
const CARD_T := 5.0  # loppuruudun kesto
const CARD_TEXT := "Äpätin Mökkiseikkailu - pelattavissa pian"
const WARMUP := 45  # ruutuja ennen kuvausta: maailma rakentuu (kokoa.sh leikkaa nämä pois)

var main: Node3D
var scenes: Array = []
var arrival: Node
var cam: Camera3D
var layer: CanvasLayer
var fade: ColorRect
var title: Label
var card: Label  # loppuruudun teksti
var shots_dir := ""
var stop_at := 1e9
var first_scene := 0
var _frames := 0
var _t := 0.0  # sekuntia kuvauksen alusta
var _i := -1  # -1 = saapuminen
var _scene_t := 0.0
var _scene_start := 0.0
var _marks := {}
var _tree_t := 0.0
var _ready_done := false
var _finished := false
var _last_shot := -1
var _keep: Array = []  # minipelin ruudut, jotka jäävät näkyviin (kohtauksen keep)


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--kuvat="):
			shots_dir = a.substr(8)
		elif a.begins_with("--loppu="):
			stop_at = float(a.substr(8))
		elif a.begins_with("--alku="):
			first_scene = int(a.substr(7))
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _label(size: float, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", int(size))
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", int(size * 0.18))
	l.anchor_right = 1.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	return l


func _setup() -> void:
	cam = Camera3D.new()
	cam.far = 9000.0
	cam.fov = 70.0
	main.add_child(cam)
	cam.make_current()
	main.set_meta("trailer_cam", cam)
	layer = CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	title = _label(float(root.size.y) * 0.09, Color(1.0, 0.92, 0.45))
	title.anchor_top = 0.38
	card = _label(float(root.size.y) * 0.055, Color(1.0, 0.92, 0.45))
	card.anchor_top = 0.45
	card.text = CARD_TEXT
	card.modulate.a = 0.0
	_hide_ui()
	scenes = load("res://tools/traileri/leikkaus.gd").scenes(main)
	# Kuvausta varten hahmot ovat tietokoneen ohjauksessa (kaikki paitsi 0, jota ohjaa kohtaus tarvittaessa).
	for j in range(1, 4):
		main.set_crew_mode(j, "ai")
	arrival = main.saapuminen
	arrival.cam = cam
	arrival.manual = true
	arrival.sun_time = {"m": 7, "d": 9, "h": 18, "min": 0}  # torstai-ilta
	main._hud.visible = false
	# Tarina ja pelin lopun cutscenet pois: ne ottaisivat kameran ja mustan ruudun, kun kello hyppii päivästä toiseen.
	main.tarina.set_process(false)
	main.loppu.set_process(false)
	if first_scene == 0:
		arrival.start()
		_i = -1
		_marks["saapuminen_alku"] = 0.0
	else:
		_begin_scene(first_scene - 1)
	_ready_done = true
	print("traileri: %d kohtausta saapumisen jälkeen" % scenes.size())


## Pelin oma käyttöliittymä pois; minipelien ruudut (root:n alla) ja baarin canvas jäävät.
func _hide_ui() -> void:
	for c in main.find_children("*", "CanvasLayer", true, false):
		if c in _keep:
			continue
		c.visible = false


func _begin_scene(i: int) -> void:
	if _i >= 0:
		_end_scene()
	_i = i
	_scene_t = 0.0
	_scene_start = _t
	var s: Dictionary = scenes[i]
	_keep = (s.keep as Callable).call() if s.has("keep") else []
	_marks["kohtaus_%d" % i] = _t
	_set_sun(s.t)
	if s.has("setup"):
		(s.setup as Callable).call()
	_hide_ui()
	var pos: Vector3 = Vector3.ZERO
	if s.has("a"):
		pos = s.a
		main.world.trees.update_around(pos)
	print("kohtaus %d alkaa %.1f s %s" % [i, _t, s.get("txt", "")])


func _end_scene() -> void:
	var s: Dictionary = scenes[_i]
	if s.has("done"):
		(s.done as Callable).call()


func _set_sun(t: Array) -> void:
	main.sun.t_utc = main.sun._local_to_utc(2026, t[0], t[1], t[2], t[3])
	main.sun._update(true)


func _process(delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP:
		return false
	if not _ready_done:
		_setup()
		return false
	if _frames % 15 == 0:
		_hide_ui()
	var dt := 1.0 / FPS
	_t += dt
	if _t >= stop_at:
		quit()
		return true
	if _card_t >= 0.0:
		_card_t += dt
		fade.color.a = 1.0
		card.modulate.a = clampf(minf(_card_t / 1.0, (CARD_T - _card_t) / 1.0), 0.0, 1.0)
		if _card_t >= CARD_T:
			_finish()
			return true
	elif _i < 0:
		_arrival_frame(dt)
	else:
		if _scene_frame(dt):
			return true
	if shots_dir != "" and _frames % int(FPS) == 0:
		print("t=%.0f kohtaus %d korkeus=%.1f peitto=%.2f oma_kamera=%s paikka=%s" % [_t, _i, main.sun.altitude, fade.color.a, root.get_camera_3d() == cam, cam.global_position])
		DirAccess.make_dir_recursive_absolute(shots_dir)
		root.get_texture().get_image().save_png(shots_dir.path_join("t_%04d.png" % int(_t)))
	_tree_t -= dt
	if _tree_t <= 0.0:
		_tree_t = 0.5
		main.world.trees.update_around(cam.global_position)
	return false


func _arrival_frame(dt: float) -> void:
	if arrival.active:
		arrival.step(dt)
		cam.make_current()
		fade.color.a = arrival.fade
		var a: float = clampf(minf(_t / 0.6, 2.2 - _t) * 2.0, 0.0, 1.0) if _t < 2.2 else 0.0
		title.text = "TORSTAI" if _t < 2.8 else ""
		title.modulate.a = a
		return
	_marks["saapuminen_loppu"] = _t
	title.text = ""
	print("saapuminen päättyi %.1f s" % _t)
	_begin_scene(0)


## Palauttaa true, kun traileri on valmis.
func _scene_frame(dt: float) -> bool:
	var s: Dictionary = scenes[_i]
	_scene_t += dt
	var dur: float = s.dur
	var k := clampf(_scene_t / dur, 0.0, 1.0)
	if s.has("t2"):
		var a: Array = s.t
		var b: Array = s.t2
		var m0: float = a[2] * 60.0 + a[3]
		var m1: float = b[2] * 60.0 + b[3]
		var m := lerpf(m0, m1, k)
		_set_sun([a[0], a[1], int(m / 60.0), int(fmod(m, 60.0))])
	if s.has("tick"):
		(s.tick as Callable).call(k, dt)
	var over: bool = _scene_t >= dur
	if s.has("until") and _scene_t > 3.0 and (s.until as Callable).call():
		over = true
	if s.has("cam"):
		var c: Array = (s.cam as Callable).call(k)
		cam.global_position = c[0]
		if (c[1] as Vector3).distance_to(c[0]) > 0.01:
			cam.look_at(c[1], Vector3.UP)
		cam.fov = float(s.get("fov", 70.0)) if float(s.get("fov", 70.0)) > 0.0 else cam.fov
	if root.get_camera_3d() != cam:
		cam.make_current()
	# Siirtymät mustan kautta. Viimeinen kohtaus (oodi) häipyy hitaasti mustaan vasta, kun laulu on loppunut.
	var last := _i == scenes.size() - 1
	if last and s.has("until") and over and _ode_end < 0.0:
		_ode_end = _scene_t + 2.5
		over = false
	var end_t := dur if _ode_end < 0.0 else _ode_end
	var out_len := 2.5 if last else FADE
	fade.color.a = maxf(1.0 - clampf(_scene_t / FADE, 0.0, 1.0), 1.0 - clampf((end_t - _scene_t) / out_len, 0.0, 1.0) if (last and _ode_end > 0.0) or not last else 0.0)
	if s.has("fade"):
		fade.color.a = maxf(fade.color.a, (s.fade as Callable).call())
	var txt: String = s.get("txt", "")
	title.text = txt if k < 0.4 else ""
	title.modulate.a = clampf(minf(_scene_t * 3.0, (0.4 * dur - _scene_t) * 3.0), 0.0, 1.0)
	if _ode_end > 0.0 and _scene_t >= _ode_end:
		over = true
	if over:
		if _i == scenes.size() - 1:
			_end_scene()
			_card_t = 0.0  # oodin jälkeen musta ruutu ja nimiteksti
			title.text = ""
			return false
		_begin_scene(_i + 1)
	return false


var _ode_end := -1.0
var _card_t := -1.0


func _finish() -> void:
	_marks["loppu"] = _t
	var out := ""
	for k in _marks:
		out += "%s=%.2f\n" % [k, _marks[k]]
	var path := "user://traileri_ajat.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("valmis %.1f s, aikamerkit: %s" % [_t, ProjectSettings.globalize_path(path)])
	print(out)
	quit()
