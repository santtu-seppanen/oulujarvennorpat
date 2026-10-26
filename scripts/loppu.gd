extends Node
## Pelin loppu, kaksi cutsceneä mökin pihalla (auto HOME_SPOT-paikalla):
## - voitto (sunnuntai klo 18): iloiset mutta herkistyneet norpat halaavat pareittain, kyyneleet ja sydämet leijuvat,
##   sitten kaikki nousevat autoon ja lähtevät kotiin tietä pitkin; lopuksi tulos ja peli jatkuu vapaana.
## - häviö (maine 0): sateinen ja synkkä ilta, norpat lerpattavat päätään, auto köhii ja yskii hitaasti pois tietä
##   pitkin ja sammuu; "Hävisit pelin", E / R aloittaa alusta.
## Hahmojen ja auton fysiikka pysäytetään cutscenen ajaksi ja ne asetetaan käsin paikoilleen.

const Reitti := preload("res://scripts/reitti.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Porukka := preload("res://scripts/porukka.gd")
const Mokki := preload("res://scripts/mokki.gd")

const WIN_LINES := ["Tää oli paras viikonloppu. *nuuh*", "Mulla meni jotain silmään... pyttipannusavua.",
	"Ensi kesänä uudestaan. Lupaa se.", "Kahvit on juotu, mutta kaipaus jää."]
const LOSS_LINES := ["Maine meni. Koko Äpätti tietää.", "Michelin-tähdet... pois.", "Ei me tästä puhuta kenellekään.",
	"Kotiin. Hiljaa."]
const HUG_T := 9.0  # halaus kestää näin kauan (s)
const WALK_T := 3.0  # kävely autolle
const DRIVE_T := 11.0
const LOSS_WALK_T := 26.0  # häviön vaellus autolle enintään näin kauan (s)

var game: Node3D
var active := false
var mode := ""  # "voitto" | "tappio"

var _t := 0.0
var _cam: Camera3D
var _layer: CanvasLayer
var _fade: ColorRect
var _tint: ColorRect
var _caption: Label
var _card: Label
var _card_text := ""
var _crew: Array = []
var _start: Array = []  # hahmojen paikat ennen cutsceneä
var _bubbles := {}
var _fx: Array = []  # sydämet ja kyyneleet: [Label3D, nopeus, elinaika]
var _rain: CPUParticles3D
var _car_s := 0.0
var _car_v := 0.0
var _heart_t := 0.0
var _honked := false
var _stalled := false
var _car_state: Array = []
var _text_done := false
var _flash := 0.0
var _flash_t := 3.0
var _inside: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 40
	_layer.visible = false
	add_child(_layer)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tint.color = Color(0.04, 0.05, 0.16, 0.0)
	_layer.add_child(_tint)
	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = Color(0, 0, 0, 0)
	_layer.add_child(_fade)
	_caption = _label(30, 70.0, false)
	_card = Label.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_card.add_theme_font_size_override("font_size", 34)
	_card.add_theme_color_override("font_outline_color", Color.BLACK)
	_card.add_theme_constant_override("outline_size", 8)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_card)


func _label(size: int, y: float, bottom: bool) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.anchor_right = 1.0
	if bottom:
		l.anchor_top = 1.0
		l.anchor_bottom = 1.0
		l.offset_top = -y
	else:
		l.offset_top = y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(l)
	return l


## Voittoleikkaus: summary on lopputulosteksti (tarina.gd).
func start_win(summary: String) -> void:
	_begin("voitto")
	_card_text = summary + "\n\nE: jatka vapaana"
	_caption.text = "Sunnuntai klo 18 – lähtö kotiin"


func start_loss() -> void:
	_begin("tappio")
	_card_text = "HÄVISIT PELIN\n\nMaine laski nollaan. Kotimatka oli hiljainen.\n\nE / R: aloita alusta"
	_caption.text = "Maine nollassa…"
	_fade.color.a = 1.0
	_rain = CPUParticles3D.new()
	_rain.amount = 2200
	_rain.lifetime = 0.9
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(22, 0.5, 22)
	_rain.direction = Vector3(0.15, -1, 0)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 16.0
	_rain.initial_velocity_max = 20.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.9, 0.02)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.75, 0.82, 1.0, 0.8)
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = rm
	_rain.mesh = bm
	game.add_child(_rain)
	Sfx.play("lose", -4.0)


func _begin(m: String) -> void:
	if active:
		return
	active = true
	mode = m
	_t = 0.0
	_car_s = 0.0
	_car_v = 0.0
	_honked = false
	_stalled = false
	_text_done = false
	_inside.clear()
	_flash = 0.0
	_flash_t = 3.0
	_card.text = ""
	_fade.color.a = 0.0
	_tint.color.a = 0.0
	_layer.visible = true
	game.end_activity()
	var p: CharacterBody3D = game.player
	if p.boat != null:
		p.leave_boat()
	if game.car.driver != null:
		game.car.leave()
	game._hud.visible = false
	game.tarina._label.visible = false
	# Hahmot ja auto käsiohjaukseen.
	var c: CharacterBody3D = game.car
	_car_state = [c.global_position, c.rotation]
	c.autopilot = false
	c.place(Reitti.HOME_SPOT, Reitti.ROUTE[1])
	c.set_physics_process(false)
	_crew = game.crew.duplicate()
	_start.clear()
	for i in _crew.size():
		var b: CharacterBody3D = _crew[i]
		_start.append([b.global_position, b.rotation.y, b.visible])
		b.controls_enabled = false
		b.velocity = Vector3.ZERO
		b.set_physics_process(false)
		b.pose = ""
		b.visible = true
		if b.hidden_inside:
			b.set_hidden_inside(false)
		var body: Node3D = b.body()
		body.rotation = Vector3.ZERO
		if mode == "tappio":
			# Kumara asento: selkä köyristyy ja pää painuu alas (luiden ohitukset), vartalo pysyy pystyssä.
			body.set_override("spine_01", Vector3.RIGHT, -0.22)
			body.set_override("spine_03", Vector3.RIGHT, -0.3)
			body.set_override("neck_01", Vector3.RIGHT, -0.35)
	_cam = Camera3D.new()
	_cam.fov = 58.0
	game.add_child(_cam)
	_cam.current = true
	_place_group()


func _car() -> CharacterBody3D:
	return game.car


## Auton oikealla puolella: voitossa pariskunnat (0–1 ja 2–3) kasvokkain halaamassa, häviössä rivissä.
func _place_group() -> void:
	var c := _car()
	var right := c.global_transform.basis.x
	var fwd := -c.global_transform.basis.z
	var centre := c.global_position + right * 3.4
	for i in _crew.size():
		var p: Vector3
		var face: Vector3
		if mode == "voitto":
			var mid := centre + fwd * (1.3 if i / 2 == 0 else -1.3)
			var side := -1.0 if i % 2 == 0 else 1.0
			p = mid + fwd * side * 0.28
			face = mid
		else:
			# Häviö: norpat ovat kaukana pihan toisella laidalla (mökin suunnassa) ja vaeltavat jonossa autolle.
			var toward := _toward_cabin()
			p = c.global_position + toward * (13.0 + i * 2.0) + Vector3(-toward.z, 0, toward.x) * sin(float(i) * 2.3) * 1.2
			face = c.global_position
		_set_pos(_crew[i], p)
		var look := face - p
		(_crew[i] as CharacterBody3D).rotation.y = atan2(-look.x, -look.z)


## Auton ja mökin pihan välinen suunta (xz).
func _toward_cabin() -> Vector3:
	var m := Mokki.yw(-4.9, 0.25)
	var d := Vector3(m.x - _car().global_position.x, 0, m.y - _car().global_position.z)
	return d.normalized()


func _set_pos(b: CharacterBody3D, p: Vector3) -> void:
	b.global_position = Vector3(p.x, Terrain.h(p.x, p.z) + 0.02, p.z)


func _bubble(who: Node3D, text: String, secs: float) -> void:
	if _bubbles.has(who):
		_bubbles[who][0].queue_free()
	var l := Label3D.new()
	l.text = text
	l.font_size = 34
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1, 1, 0.88)
	l.outline_size = 10
	l.position = Vector3(0, 2.25, 0)
	who.add_child(l)
	_bubbles[who] = [l, secs]


func _fx_spawn(at: Vector3, text: String, col: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 40
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = col
	l.outline_size = 8
	game.add_child(l)
	l.global_position = at
	_fx.append([l, randf_range(0.5, 0.9), 2.2])


## Polun (maailman x, z) piste ja suunta matkalla s alusta.
func _route_at(s: float) -> Array:
	var r: Array = Reitti.ROUTE
	var left := s
	for k in r.size() - 1:
		var a: Vector2 = r[k]
		var b: Vector2 = r[k + 1]
		var l := a.distance_to(b)
		if left <= l:
			return [a.lerp(b, left / l), (b - a).normalized()]
		left -= l
	var last: Vector2 = r[r.size() - 1]
	return [last, ((r[r.size() - 1] as Vector2) - (r[r.size() - 2] as Vector2)).normalized()]


func _process(delta: float) -> void:
	if not active:
		return
	_t += delta
	for who: Node3D in _bubbles.keys():
		_bubbles[who][1] -= delta
		if _bubbles[who][1] <= 0.0:
			_bubbles[who][0].queue_free()
			_bubbles.erase(who)
	for i in range(_fx.size() - 1, -1, -1):
		var e: Array = _fx[i]
		e[2] -= delta
		(e[0] as Label3D).global_position.y += e[1] * delta
		(e[0] as Label3D).modulate.a = clampf(e[2], 0.0, 1.0)
		if e[2] <= 0.0:
			(e[0] as Label3D).queue_free()
			_fx.remove_at(i)
	if mode == "voitto":
		_win(delta)
	else:
		_loss(delta)
	if _rain != null:
		_rain.global_position = _cam.global_position + Vector3(0, 9, 0)


func _anim(i: int, a: String) -> void:
	(_crew[i] as CharacterBody3D).body().play(a, 0.25)


func _win(delta: float) -> void:
	var c := _car()
	var right := c.global_transform.basis.x
	var centre := c.global_position + right * 3.4
	if _t < HUG_T + WALK_T:
		# Halaus: pariskunnat nojaavat toisiinsa ja heiluvat, sydämiä ja kyyneleitä leijuu.
		var hug := _t < HUG_T
		for i in _crew.size():
			var b: CharacterBody3D = _crew[i]
			var body: Node3D = b.body()
			if hug:
				_anim(i, "Interact" if int(_t / 2.5) % 2 == 0 else "Idle_Talking")
				body.rotation.x = deg_to_rad(-9.0)
				body.rotation.z = sin(_t * 2.2 + i) * 0.07
				if _bubbles.is_empty() and _t > 0.8 + i * 2.0 and _t < HUG_T - 1.0 and int((_t - 0.8) / 2.0) == i:
					var wl: String = WIN_LINES[i % WIN_LINES.size()]
					if i == 1 and game.muistelu.win_line() != "":
						wl = game.muistelu.win_line()  # nuotiotarinat jäivät mieleen
					_bubble(b, wl, 1.9)
			else:
				body.rotation = Vector3.ZERO
				var to := c.global_position + right * 1.0 - b.global_position
				to.y = 0.0
				if to.length() > 0.6:
					b.global_position += to.normalized() * 2.1 * delta
					b.global_position.y = Terrain.h(b.global_position.x, b.global_position.z)
					b.rotation.y = atan2(-to.x, -to.z)
					_anim(i, "Walk")
		_heart_t -= delta
		if hug and _heart_t <= 0.0:
			_heart_t = 0.35
			var who: CharacterBody3D = _crew[randi() % _crew.size()]
			if randf() < 0.6:
				_fx_spawn(who.global_position + Vector3(randf_range(-0.3, 0.3), 2.0, 0), "♥", Color(1.0, 0.35, 0.5))
			else:
				_fx_spawn(who.global_position + Vector3(0.12, 1.65, -0.2), "💧", Color(0.6, 0.85, 1.0))
		# Kamera: halaajien sivulta, hitaasti lähemmäs.
		_cam.global_position = centre - right * (2.6 - _t * 0.05) + Vector3(0, 1.8, 0)  # auton puolelta (pihan puu ei peitä)
		_cam.look_at(centre + Vector3(0, 1.0, 0), Vector3.UP)
		_caption.text = "Halauksia ja herkkiä hetkiä…" if hug else "Kamat autoon!"
		return
	# Autoon ja pois.
	for b: CharacterBody3D in _crew:
		b.visible = false
	var drive_t := _t - (HUG_T + WALK_T)
	if not _honked:
		_honked = true
		Sfx.play("horn", -4.0, 1.0)
	_car_v = minf(11.5, _car_v + 2.0 * delta)
	_car_s += _car_v * delta
	var r := _route_at(_car_s)
	var pos: Vector2 = r[0]
	var dir: Vector2 = r[1]
	c.global_position = Vector3(pos.x, Terrain.h(pos.x, pos.y), pos.y)
	c.rotation.y = atan2(-dir.x, -dir.y)
	c.speed = _car_v
	var behind := Vector3(-dir.x, 0, -dir.y)
	var want := c.global_position + behind * 9.0 + Vector3(0, 3.6, 0) + Vector3(dir.y, 0, -dir.x) * 3.0
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-3.0 * delta))
	_cam.look_at(c.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	_caption.text = "Hyvä viikonloppu! Norpat lähtevät kotiin."
	if drive_t > DRIVE_T - 2.5:
		_fade.color.a = clampf((drive_t - (DRIVE_T - 2.5)) / 2.0, 0.0, 1.0)
	if drive_t > DRIVE_T and not _text_done:
		_text_done = true
		_caption.text = ""
		_card.text = _card_text
	if _text_done and (Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_ENTER)):
		_finish()


func _loss(delta: float) -> void:
	var c := _car()
	var toward := _toward_cabin()
	var side := Vector3(-toward.z, 0, toward.x)
	# Pimeä sateinen ilta: pimennys tulee hitaasti, ja salama välähtää silloin tällöin.
	_flash = maxf(0.0, _flash - delta * 2.2)
	_flash_t -= delta
	if _flash_t <= 0.0 and _t > 2.0:
		_flash_t = randf_range(4.0, 8.0)
		_flash = 0.55
		Sfx.play("rattle_hard_0", -8.0, 0.5)
	if _t < 1.6:
		_fade.color.a = 1.0 - _t / 1.6
	_tint.color = Color(0.03, 0.04, 0.14, minf(0.55, _t * 0.3)).lerp(Color(0.9, 0.93, 1.0, 0.6), _flash)
	if _t < LOSS_WALK_T:
		# Norpat vaeltavat sateessa autolle: hitaasti, päät painuksissa, märkinä. Kamera auton vierestä, ja he tulevat päin.
		var arrived := 0
		for i in _crew.size():
			var b: CharacterBody3D = _crew[i]
			var body: Node3D = b.body()
			var to := c.global_position + side * 1.4 - b.global_position
			to.y = 0.0
			if to.length() > 1.5:
				var sp := 1.15 + 0.12 * float(i % 2) + sin(_t * 0.7 + i) * 0.1
				b.global_position += to.normalized() * sp * delta
				b.global_position.y = Terrain.h(b.global_position.x, b.global_position.z) + 0.02
				b.rotation.y = lerp_angle(b.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-3.0 * delta))
				body.play("Walk", 0.3, 0.55)
				body.rotation.z = sin(_t * 2.4 + i * 1.7) * 0.05  # lerpattava kävely
			else:
				arrived += 1
				b.visible = false  # autoon
				if not _inside.has(i):
					_inside.append(i)
					Sfx.play("door_close", -4.0)
		var cen := Vector3.ZERO
		var n := 0
		for b: CharacterBody3D in _crew:
			if b.visible:
				cen += b.global_position
				n += 1
		cen = (cen / float(n)) if n > 0 else c.global_position
		# Seurantakuva: kamera kulkee jonon mukana sivulla, matalalla ja lähellä.
		var focus := (cen + Vector3(0, 1.1, 0)) if n > 0 else c.global_position + Vector3(0, 1.0, 0)
		var want_cam := ((cen if n > 0 else c.global_position) + side * 4.2 + Vector3(0, 1.3, 0))
		_cam.global_position = _cam.global_position.lerp(want_cam, 1.0 - exp(-2.5 * delta)) if _t > 0.2 else want_cam
		_cam.look_at(focus, Vector3.UP)
		if _bubbles.is_empty() and _t > 1.5 and int((_t - 1.5) / 2.6) < LOSS_LINES.size() and fmod(_t - 1.5, 2.6) < 0.05 and _crew[int((_t - 1.5) / 2.6) % _crew.size()].visible:
			_bubble(_crew[int((_t - 1.5) / 2.6) % _crew.size()], LOSS_LINES[int((_t - 1.5) / 2.6) % LOSS_LINES.size()], 2.2)
		_caption.text = "Maine nollassa. Norpat vaeltavat sateessa autolle…"
		if arrived == _crew.size():
			_t = maxf(_t, LOSS_WALK_T)
		return
	for b: CharacterBody3D in _crew:
		b.visible = false
	var drive_t := _t - LOSS_WALK_T
	# Auto köhii: nytkähtelee eteenpäin ja sammuu lopulta.
	if not _honked:
		_honked = true
		Sfx.play("horn", -6.0, 0.55)  # surkea törähdys
	var chug := maxf(0.0, sin(drive_t * 5.0)) * 2.4
	if drive_t < 6.5:
		_car_v = 0.6 + chug
	else:
		_car_v = move_toward(_car_v, 0.0, 3.0 * delta)
		if not _stalled:
			_stalled = true
			Sfx.play("lose", -2.0, 0.8)
			Sfx.play("horn", -8.0, 0.4)
	_car_s += _car_v * delta
	var r := _route_at(_car_s)
	var pos: Vector2 = r[0]
	var dir: Vector2 = r[1]
	c.global_position = Vector3(pos.x, Terrain.h(pos.x, pos.y), pos.y)
	c.rotation.y = atan2(-dir.x, -dir.y)
	c.rotation.z = sin(drive_t * 5.0) * 0.02 * clampf(_car_v, 0.0, 1.0)
	c.speed = _car_v
	var behind := Vector3(-dir.x, 0, -dir.y)
	var want := c.global_position + behind * 7.5 + Vector3(0, 2.6, 0) + Vector3(dir.y, 0, -dir.x) * 2.2
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-2.0 * delta))
	_cam.look_at(c.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	_caption.text = "Auto köhii kotimatkalla…" if drive_t < 6.5 else "…ja sammuu."
	if drive_t > 8.0:
		_fade.color.a = clampf((drive_t - 8.0) / 2.0, 0.0, 0.85)
	if drive_t > 10.5 and not _text_done:
		_text_done = true
		_caption.text = ""
		_card.text = _card_text
	if _text_done and (Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_R) or Input.is_key_pressed(KEY_ENTER)):
		active = false
		get_tree().reload_current_scene()


## Voiton jälkeen: auto ja hahmot takaisin pihaan, peli jatkuu vapaana.
func _finish() -> void:
	active = false
	_layer.visible = false
	_card.text = ""
	if _cam != null:
		_cam.queue_free()
	for e in _fx:
		(e[0] as Label3D).queue_free()
	_fx.clear()
	for who: Node3D in _bubbles.keys():
		_bubbles[who][0].queue_free()
	_bubbles.clear()
	var c := _car()
	c.set_physics_process(true)
	c.rotation.z = 0.0
	c.place(Reitti.HOME_SPOT, Reitti.ROUTE[1])
	for i in _crew.size():
		var b: CharacterBody3D = _crew[i]
		b.set_physics_process(true)
		b.body().rotation = Vector3.ZERO
		b.visible = true
		b.controls_enabled = true
		var q: Vector3 = _start[i][0]
		b.global_position = Vector3(q.x, Terrain.h(q.x, q.z) + 0.1, q.z)
		b.rotation.y = _start[i][1]
		b.pose = ""
	game.player.activate_camera()
	game._hud.visible = true
