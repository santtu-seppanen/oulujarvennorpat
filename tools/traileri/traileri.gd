extends SceneTree
## Pelin traileri pelikuvasta (Godotin Movie Maker): otokset tools/traileri/leikkaus.gd:stä, sanat alapalkissa ja
## mustat siirtymät. Video on äänetön; kappale liitetään ffmpegillä (tools/traileri/kokoa.sh).
##
##   godot --path . --write-movie /tmp/traileri/traileri.avi --fixed-fps 30 --resolution 1920x1080 \
##     -s tools/traileri/traileri.gd -- --kesto=150
##
## Valinnat (-- jälkeen): --kesto=<s> kappaleen pituus sekunteina (leikkaus venytetään siihen; oletus 72 tahtia 124 bpm:llä),
## --alku=<s> --loppu=<s> kuvaa vain osan (esikatselu), --kuvat=<kansio> tallentaa vain otosten keskikuvat PNG:nä (ei videota).

const Leikkaus := preload("res://tools/traileri/leikkaus.gd")
const FPS := 30.0
const FADE := 0.25

var main: Node3D
var Mokki: GDScript
var Reitti: GDScript
var Satama: GDScript
var Terrain: GDScript
var shots: Array = []
var starts: Array = []  # otosten alkuajat (s)
var ends: Array = []
var total := 0.0
var scale := 1.0
var from_t := 0.0
var to_t := 1e9
var shots_dir := ""
var cam: Camera3D
var layer: CanvasLayer
var fade: ColorRect
var title: Label
var lyric: Label
var _t := 0.0
var _frames := 0
var _idx := -1
var _tree_t := 0.0
var _car_s := 0.0  # auton matka tien keskiviivaa pitkin (m)
var _car_air := -1.0  # lentoaika hyppyrin jälkeen (s), -1 = ei ilmassa
var _car_vy := 0.0
var _car_y := 0.0
var _road_cum: Array = []  # ROAD_LINE-pisteiden kumulatiivinen etäisyys
var _last_lyric := -1
var _game: Node  # ruudulle avattu minipeli
var _call_box: Control
var _call_text: Label


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--kesto="):
			total = float(a.substr(8))
		elif a.begins_with("--alku="):
			from_t = float(a.substr(7))
		elif a.begins_with("--loppu="):
			to_t = float(a.substr(8))
		elif a.begins_with("--kuvat="):
			shots_dir = a.substr(8)
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Mokki = load("res://scripts/mokki.gd")
	Reitti = load("res://scripts/reitti.gd")
	Satama = load("res://scripts/satama.gd")
	Terrain = load("res://scripts/terrain.gd")


func _setup() -> void:
	if total <= 0.0:
		total = Leikkaus.SONG_LEN
	scale = total / Leikkaus.SONG_LEN
	var cum := 0.0
	for k in Satama.ROAD_LINE.size():
		if k > 0:
			cum += (Satama.ROAD_LINE[k] as Vector2).distance_to(Satama.ROAD_LINE[k - 1])
		_road_cum.append(cum)
	shots = Leikkaus.shots(Mokki, Reitti, Satama, main)
	# Osan otokset jakavat osan ajan painojensa (bars) suhteessa.
	var weight := {}
	for s: Dictionary in shots:
		weight[s.sec] = float(weight.get(s.sec, 0.0)) + float(s.bars)
	var used := {}
	for s: Dictionary in shots:
		var span: Array = Leikkaus.SECTIONS[s.sec]
		var len_s: float = (span[1] - span[0]) * scale * float(s.bars) / float(weight[s.sec])
		var t0: float = span[0] * scale + float(used.get(s.sec, 0.0))
		used[s.sec] = float(used.get(s.sec, 0.0)) + len_s
		starts.append(t0)
		ends.append(t0 + len_s)
	cam = Camera3D.new()
	cam.far = 9000.0
	cam.fov = 70.0
	main.add_child(cam)
	cam.current = true
	layer = CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	var vs := Vector2(root.size)
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.anchor_right = 1.0
	fade.anchor_bottom = 1.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	title = _label(vs.y * 0.09, Color(1.0, 0.92, 0.45))
	title.anchor_top = 0.38
	lyric = _label(vs.y * 0.045, Color.WHITE)
	lyric.anchor_top = 0.86
	_make_call_box(vs)
	print("traileri: %.1f s, %d otosta" % [total, shots.size()])


## Vihainen työpuhelu kuvan päällä (kuten Jaakon saunapuhelu): tumma laatikko, otsikko ja puhuttu rivi.
func _make_call_box(vs: Vector2) -> void:
	_call_box = Control.new()
	_call_box.visible = false
	_call_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_call_box.anchor_left = 0.2
	_call_box.anchor_right = 0.8
	_call_box.anchor_top = 0.14
	_call_box.anchor_bottom = 0.42
	layer.add_child(_call_box)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_call_box.add_child(bg)
	var head := Label.new()
	head.text = "TYÖPUHELU · ESIMIES"
	head.add_theme_font_size_override("font_size", int(vs.y * 0.045))
	head.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25))
	head.anchor_left = 0.04
	head.anchor_top = 0.08
	_call_box.add_child(head)
	_call_text = Label.new()
	_call_text.add_theme_font_size_override("font_size", int(vs.y * 0.05))
	_call_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_call_text.anchor_left = 0.04
	_call_text.anchor_right = 0.96
	_call_text.anchor_top = 0.4
	_call_text.anchor_bottom = 0.95
	_call_box.add_child(_call_text)


func _rel(v: Vector3, s: Dictionary) -> Vector3:
	match s.get("rel", ""):
		"boat":
			return main.boat.global_position + v
		"sinikka":  # (a, y, b) Sinikasta Happy Beachin sisätilan kehyksessä
			var hb: Node3D = main.world.happy
			return (hb.sinikka as Node3D).global_position + hb.pocket.global_basis * Vector3(v.x, v.y, -v.z)
	return v


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


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 45:  # maailma ehtii rakentua
		return false
	if shots.is_empty():
		_setup()
		main.nuotio.ignite(4, 1.0, false)  # nuotio palamaan nuotiokuviin
		if shots.is_empty():
			push_error("leikkaus.gd ei antanut otoksia")
			quit(1)
			return true
	var t := from_t + float(_frames - 45) / FPS
	if _frames % 15 == 0 or _frames == 45:
		for c in main.find_children("*", "CanvasLayer", true, false):
			c.visible = false  # pelin oma käyttöliittymä pois
	if root.get_camera_3d() != cam:
		cam.make_current()
	if t >= minf(total, to_t):
		print("valmis, %d ruutua" % (_frames - 45))
		quit()
		return true
	var i := 0
	while i < shots.size() - 1 and t >= ends[i]:
		i += 1
	var s: Dictionary = shots[i]
	if i != _idx or _frames % 10 == 0:
		var tt: Array = s.t  # kellonaika pysyy otoksen arvossa (pelin aika kulkee muuten)
		main.sun.t_utc = main.sun._local_to_utc(2026, tt[0], tt[1], tt[2], tt[3])
		main.sun._update(true)
	var k := clampf((t - starts[i]) / maxf(ends[i] - starts[i], 0.01), 0.0, 1.0)
	if i != _idx:
		_idx = i
		_start_shot(s)
	if s.get("car", false):
		_car_shot(s, k)
	else:
		var e := k * k * (3.0 - 2.0 * k)
		if s.has("a"):
			cam.global_position = _rel(s.a, s).lerp(_rel(s.b, s), e)
			cam.look_at(_rel(s.la, s).lerp(_rel(s.lb, s), e), Vector3.UP)
	if shots_dir != "" and _frames % 15 == 0:
		DirAccess.make_dir_recursive_absolute(shots_dir)
		root.get_texture().get_image().save_png(shots_dir.path_join("f_%04d.png" % _frames))
	_tree_t -= 1.0 / FPS
	if _tree_t <= 0.0:
		_tree_t = 0.5
		main.world.trees.update_around(cam.global_position)
	# Siirtymät mustan kautta, otsikko ja sanat.
	var dt := minf(t - starts[i], ends[i] - t)
	fade.color.a = 1.0 - clampf(dt / FADE, 0.0, 1.0) if (i == 0 or i == shots.size() - 1 or s.has("txt")) else 0.0
	_call_box.visible = s.has("call")
	if s.has("call"):
		_call_text.text = "\"%s\"" % s.call
	title.text = s.get("txt", "") if k < 0.85 else ""
	title.modulate.a = clampf(minf(k * 6.0, (0.85 - k) * 6.0), 0.0, 1.0)
	lyric.text = ""  # sanoitusrivejä ei näytetä: ne eivät ole kappaleen oikeassa ajoituksessa
	if shots_dir != "" and k > 0.5 and i != _last_lyric and _frames > 50:
		_last_lyric = i
		DirAccess.make_dir_recursive_absolute(shots_dir)
		root.get_texture().get_image().save_png(shots_dir.path_join("otos_%02d.png" % i))
	return false


func _start_shot(s: Dictionary) -> void:
	print("otos %d alkaa %.1f s%s %s" % [_idx, starts[_idx], " (%s)" % s.txt if s.has("txt") else "", s.keys()])
	var tt: Array = s.t
	main.sun.t_utc = main.sun._local_to_utc(2026, tt[0], tt[1], tt[2], tt[3])
	main.sun._update(true)
	if is_instance_valid(_game):
		_game.queue_free()
	_game = null
	if not s.get("car", false):
		main.car.global_position = Vector3(Reitti.HOME_SPOT.x, Terrain.h(Reitti.HOME_SPOT.x, Reitti.HOME_SPOT.y), Reitti.HOME_SPOT.y)
	main.world.happy._in_light.visible = s.get("rel", "") == "sinikka"  # sisätilan valo vain baarikuvissa
	if s.has("game"):
		_game = load(s.game).new()
		root.add_child(_game)
		root.move_child(_game, 0)  # otsikot ja sanat päälle
		if s.has("play"):
			_game.call(s.play)
		return
	if s.get("car", false):
		# Auto sijoitetaan käsin (ei fysiikkaa): ajo täyttä vauhtia, hyppyri lennättää.
		main.car.set_physics_process(false)
		_car_s = _road_cum[15] - 30.0 if s.get("jump", false) else _road_cum[4]
		_car_air = -1.0
		_car_y = 0.0
	elif s.has("a"):
		main.world.trees.update_around(_rel(s.a, s))


## Auto ajaa täyttä vauhtia sataman tietä (hyppyri); kamera seuraa takaa ja sivulta.
func _car_shot(s: Dictionary, k: float) -> void:
	var car: CharacterBody3D = main.car
	var line: Array = Satama.ROAD_LINE
	_car_s = minf(_car_s + 22.2 / FPS, _road_cum[line.size() - 1] - 0.1)
	var seg := 0
	while seg < line.size() - 2 and _car_s > _road_cum[seg + 1]:
		seg += 1
	var f: float = (_car_s - _road_cum[seg]) / maxf(_road_cum[seg + 1] - _road_cum[seg], 0.01)
	var p: Vector2 = (line[seg] as Vector2).lerp(line[seg + 1], f)
	var dir: Vector2 = ((line[seg + 1] as Vector2) - line[seg]).normalized()
	var ground: float = Terrain.h(p.x, p.y) + Satama.ramp_h(p.x, p.y)
	# Hyppyri: kun auto ohittaa rampin huipun, se lentää ballistisesti kunnes osuu maahan.
	var a_ramp: float = (p - Satama.RAMP_START).dot(Satama.RAMP_DIR)
	if _car_air < 0.0 and absf(a_ramp - Satama.RAMP_RISE) < 0.4 and absf((p - Satama.RAMP_START).dot(Satama.RAMP_DIR.orthogonal())) < Satama.RAMP_HW:
		_car_air = 0.0
		_car_vy = 22.2 * Satama.RAMP_H / Satama.RAMP_RISE
		_car_y = ground
	if _car_air >= 0.0:
		_car_air += 1.0 / FPS
		_car_vy -= 9.5 / FPS
		_car_y += _car_vy / FPS
		if _car_y <= ground and _car_air > 0.2:
			_car_air = -1.0
		else:
			ground = _car_y
	car.global_position = Vector3(p.x, ground + 0.02, p.y)
	car.rotation = Vector3(clampf(-_car_vy * 0.03, -0.2, 0.2) if _car_air >= 0.0 else 0.0, atan2(-dir.x, -dir.y), 0.0)
	var back := Vector3(dir.x, 0.0, dir.y) * -1.0
	var side := Vector3(back.z, 0.0, -back.x)
	var off := back * lerpf(9.0, 6.0, k) + side * lerpf(4.0, -3.0, k) + Vector3.UP * (2.4 if s.get("jump", false) else 2.0)
	cam.global_position = car.global_position + off
	cam.look_at(car.global_position + Vector3.UP * 0.8, Vector3.UP)
