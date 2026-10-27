extends Node
## Pelin loppu, kaksi cutsceneä mökin pihalla (auto HOME_SPOT-paikalla):
## - voitto (sunnuntai klo 18): norpat seisovat ringissä käsi toisen hartioilla ja muistelevat loistavaa viikonloppua
##   (Michelin Markon ruoat, Barista Salosen pannukahvit, ennätykset spartalaisessa ja amerikanpallossa, kätköt löytyivät
##   ja uudet tehtiin), sydämet ja kyyneleet leijuvat; sitten kannetaan matkatavarat autoon ja kaahataan
##   auringonlaskuun (kello kiertää iltaan, kamera katsoo autoa vasten laskevaa aurinkoa); lopuksi tulos ja peli jatkuu vapaana.
## - häviö (maine 0): sateinen ja synkkä ilta, norpat lerpattavat päätään, auto köhii ja yskii hitaasti pois tietä
##   pitkin ja sammuu; "Hävisit pelin", vain E aloittaa uuden pelin.
## Hahmojen ja auton fysiikka pysäytetään cutscenen ajaksi ja ne asetetaan käsin paikoilleen.

const Reitti := preload("res://scripts/reitti.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Porukka := preload("res://scripts/porukka.gd")
const Mokki := preload("res://scripts/mokki.gd")
const B := preload("res://scripts/build.gd")
const Saapuminen := preload("res://scripts/saapuminen.gd")

## Ringin keskustelu: [puhuja, teksti]; puhuja on mökkiläisen nimi, "kaikki" = yhteislause.
const RING_LINES := [
	["Santtu", "No niin... tästä tuli kyllä paras viikonloppu ikinä."],
	["Jaakko", "Michelin Markon ruoat oli ihan tähtiluokkaa. Se pyttipannu!"],
	["Marko", "Kiitos kiitos. Mutta Barista Salosen pannukahvit nosti koko viikonlopun."],
	["Jukka", "*nuuh* Ne keitettiin sydämellä. Kupit pysyi täynnä."],
	["Santtu", "Spartalaisessa ja amerikanpallossa meni ennätykset rikki!"],
	["Jaakko", "Viinakätköt löytyi, ja uudet tehtiin ensi kesää varten."],
	["Marko", "Ensi kesänä uudestaan. Lupaa se."],
	["kaikki", "Ensi kesänä uudestaan!"],
]
const LINE_T := 3.0  # yhden repliikin kesto (s)
const LOSS_LINES := ["Maine meni. Koko Äpätti tietää.", "Michelin-tähdet... pois.", "Ei me tästä puhuta kenellekään.",
	"Kotiin. Hiljaa."]
const LUG_T := 11.0  # matkatavaroiden kanto autoon (s)
const DRIVE_T := 14.0  # kaahaus auringonlaskuun (s)
const SUNSET_HOUR := 22  # kello kiertää iltaan: auringonlasku klo 22.40 -> 23.00
const SUNSET_MIN := 40
const WALK_SPEED := 2.2
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
var _lines: Array = []  # ringin repliikit: [crew-indeksi tai -1, teksti]
var _ring_t := 20.0  # ringin kesto (s)
var _bags: Array = []  # matkatavarat: [Node3D, paikka]
var _lug: Array = []  # hahmon kanto: [vaihe, odotus]
var _centre := Vector3.ZERO  # ringin keskipiste (vapaa paikka auton lähellä)
var _sun_from := 0.0
var _sun_to := 0.0
var _chat_was := true
var _clothed: Array = []  # hahmot, joille on jo puettu vaatteet (t-paita, farkut, kengät)


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
	_caption = _label(30, 90.0, true)  # alalaidassa, pois puhekuplien tieltä
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
	_card_text = "HÄVISIT PELIN\n\nMaine laski nollaan. Kotimatka oli hiljainen.\n\nE: uusi peli"
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
	_said.clear()
	_clothed.clear()
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
	_chat_was = game.chat._ui.visible
	game.chat._ui.visible = false  # viestilista ja kuplat pois kohtauksen ajaksi
	game.chat.bubbles_hidden = true
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
			_dress(i)  # sateessa ei kuljeta paljain rinnoin: vaatteet päällä autolle
	_cam = Camera3D.new()
	_cam.fov = 58.0
	game.add_child(_cam)
	_cam.current = true
	_place_group()
	if mode == "voitto":
		_setup_win()


func _car() -> CharacterBody3D:
	return game.car


## Vaatteet päälle ennen autoon nousua: t-paita, farkut ja kengät (sama asu kuin saapumiskohtauksessa).
func _dress(i: int) -> void:
	if _clothed.has(i):
		return
	_clothed.append(i)
	var body: Node3D = (_crew[i] as CharacterBody3D).body()
	body.restyle(Saapuminen._dressed(i))
	Porukka.decorate(i, body)
	Sfx.play("cloth", -8.0, 1.0 + 0.1 * i)


## Auton oikealla puolella: voitossa kaikki ringissä, häviössä rivissä.
const RING_R := 0.74  # ringin säde (m): tiukka ring, olkapäät melkein koskevat toisiaan


func _place_group() -> void:
	var c := _car()
	var right := c.global_transform.basis.x
	var fwd := -c.global_transform.basis.z
	if mode == "voitto":
		_centre = _free_spot()
	var centre := _centre if mode == "voitto" else c.global_position + right * 3.4
	for i in _crew.size():
		var p: Vector3
		var face: Vector3
		if mode == "voitto":
			# Ringissä keskipisteen ympärillä kasvot sisäänpäin.
			var ang := TAU * float(i) / float(_crew.size()) + 0.4
			p = centre + Vector3(cos(ang), 0, sin(ang)) * RING_R
			face = centre
		else:
			# Häviö: norpat ovat kaukana pihan toisella laidalla (mökin suunnassa) ja vaeltavat jonossa autolle.
			var toward := _toward_cabin()
			p = c.global_position + toward * (13.0 + i * 2.0) + Vector3(-toward.z, 0, toward.x) * sin(float(i) * 2.3) * 1.2
			face = c.global_position
		_set_pos(_crew[i], p)
		var look := face - p
		(_crew[i] as CharacterBody3D).rotation.y = atan2(-look.x, -look.z)


## Vapaa paikka ringille auton lähellä: pingispöytä, puut ja muut esteet eivät saa olla ringin alueella.
func _free_spot() -> Vector3:
	var c := _car()
	var right := c.global_transform.basis.x
	var fwd := -c.global_transform.basis.z
	var cands: Array[Vector3] = []
	for d: Vector3 in [right * 3.4, -right * 3.4, fwd * 5.0, -fwd * 5.0, right * 5.5, -right * 5.5, fwd * 5.0 + right * 3.5,
			-fwd * 5.0 - right * 3.5, fwd * 5.0 - right * 3.5, -fwd * 5.0 + right * 3.5, right * 8.0, -right * 8.0]:
		cands.append(c.global_position + d)
	var space := game.get_world_3d().direct_space_state
	for cand in cands:
		var ok := true
		for ring: Array in [[0.0, 1], [1.6, 8], [2.6, 8]]:
			for k in int(ring[1]):
				var a := TAU * float(k) / float(ring[1])
				var q := cand + Vector3(cos(a), 0, sin(a)) * float(ring[0])
				var g := Terrain.h(q.x, q.z)
				var rq := PhysicsRayQueryParameters3D.create(Vector3(q.x, g + 3.0, q.z), Vector3(q.x, g - 1.0, q.z))
				var hit := space.intersect_ray(rq)
				if not hit.is_empty() and (hit.position as Vector3).y > g + 0.25:
					ok = false
					break
			if not ok:
				break
		if ok:
			return cand
	return cands[0]


## Hahmojen oma törmäysrunko ei saa estää kameran näkyvyyssädettä.
func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var rq := PhysicsRayQueryParameters3D.create(from, to)
	var ex: Array[RID] = []
	for b: CharacterBody3D in _crew:
		ex.append(b.get_rid())
	rq.exclude = ex
	return game.get_world_3d().direct_space_state.intersect_ray(rq)


## Kamera ei saa jäädä esteen (puu, pöytä) sisään tai taakse: jos sädettä kohteesta toivottuun paikkaan estää jokin, kamera tuodaan
## esteen eteen.
func _clear_cam(target: Vector3, want: Vector3) -> Vector3:
	var hit := _ray(target, want)
	if hit.is_empty():
		return want
	var h: Vector3 = hit.position
	return h + (target - h).normalized() * 0.5


## Valitsee ehdokkaista kameran paikan, josta kohteeseen on esteetön näkö (muuten se, jossa este on kaukaisin).
func _clear_pick(target: Vector3, cands: Array) -> Vector3:
	var best: Vector3 = cands[0]
	var best_d := -1.0
	for c: Vector3 in cands:
		var hit := _ray(target, c)
		if hit.is_empty():
			return c
		var d := target.distance_to(hit.position)
		if d > best_d:
			best_d = d
			best = (hit.position as Vector3) + (target - hit.position).normalized() * 0.5
	return best


## Auton ja mökin pihan välinen suunta (xz).
func _toward_cabin() -> Vector3:
	var m := Mokki.yw(-4.9, 0.25)
	var d := Vector3(m.x - _car().global_position.x, 0, m.y - _car().global_position.z)
	return d.normalized()


func _set_pos(b: CharacterBody3D, p: Vector3) -> void:
	b.global_position = Vector3(p.x, Terrain.h(p.x, p.z) + 0.02, p.z)


func _bubble(who: Node3D, text: String, secs: float, chorus := false) -> void:
	# Nauhoitettu repliikki puhujan äänellä (yhteislause: kaikkien neljän äänellä).
	var idx := _crew.find(who)
	if chorus:
		for j in _crew.size():
			game.chat.speak_voice(str(Porukka.CREW[j].name).to_lower(), text, -4.0)
	elif idx >= 0:
		game.chat.speak_voice(str(Porukka.CREW[idx].name).to_lower(), text)
	if _bubbles.has(who):
		_bubbles[who][0].queue_free()
	var l := Label3D.new()
	l.text = text
	l.font_size = 30
	l.pixel_size = 0.005
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1, 1, 0.88)
	l.outline_size = 10
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # pitkä repliikki rivitetään kuplaksi
	l.width = 420.0
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.position = Vector3(0, 2.05, 0)
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


## Voiton alustus: repliikit, matkatavarat ja kellon siirto iltaan.
func _setup_win() -> void:
	for i in _crew.size():
		_dress(i)  # ringissä jo vaatteet päällä
	_lines.clear()
	for e: Array in RING_LINES:
		var who := -1
		for i in _crew.size():
			if Porukka.CREW[i].name == e[0]:
				who = i
		_lines.append([who, e[1]])
	var extra: String = game.muistelu.win_line()
	if extra != "":
		_lines.insert(_lines.size() - 1, [_name_idx("Jaakko"), extra])  # nuotiotarinat jäivät mieleen
	_ring_t = _lines.size() * LINE_T + 1.5
	# Matkatavarat ringin takana: kullakin oma (reppu, pannu, termos).
	for bag: Array in _bags:
		(bag[0] as Node3D).queue_free()
	_bags.clear()
	_lug.clear()
	var c := _car()
	var right := c.global_transform.basis.x
	var fwd := -c.global_transform.basis.z
	var centre := _centre
	for i in _crew.size():
		var pos := centre + right * 2.3 + fwd * (float(i) - 1.5) * 0.9
		var node := _make_bag(Porukka.CREW[i].name)
		game.add_child(node)
		node.global_position = Vector3(pos.x, Terrain.h(pos.x, pos.z), pos.z)
		_bags.append([node, pos])
		_lug.append([0, float(i) * 0.7])
	var lt: Dictionary = game.sun.local()
	_sun_from = game.sun.t_utc
	_sun_to = game.sun._local_to_utc(int(lt.year), int(lt.month), int(lt.day), SUNSET_HOUR, SUNSET_MIN)
	if _sun_to < _sun_from:
		_sun_to = _sun_from


func _name_idx(n: String) -> int:
	for i in _crew.size():
		if Porukka.CREW[i].name == n:
			return i
	return 0


## Matkatavara: Santtu ja Jaakko kassit, Marko pyttipannu ja Jukka kahvitermos.
func _make_bag(who: String) -> Node3D:
	var n := Node3D.new()
	match who:
		"Marko":
			B.mesh(n, B.cyl(0.24, 0.24, 0.07, 16), Vector3(0, 0.06, 0), Color(0.12, 0.12, 0.13))  # valurautapannu
			B.mesh(n, B.boxm(Vector3(0.32, 0.04, 0.06)), Vector3(0.36, 0.07, 0), Color(0.12, 0.12, 0.13))
			B.mesh(n, B.boxm(Vector3(0.4, 0.3, 0.26)), Vector3(0, 0.25, 0), Color(0.75, 0.6, 0.3))  # kääre
		"Jukka":
			B.mesh(n, B.cyl(0.1, 0.1, 0.5, 12), Vector3(0, 0.25, 0), Color(0.75, 0.1, 0.1))  # termospannu
			B.mesh(n, B.cyl(0.07, 0.07, 0.06, 12), Vector3(0, 0.53, 0), Color(0.2, 0.2, 0.22))
			B.mesh(n, B.boxm(Vector3(0.5, 0.3, 0.3)), Vector3(0.4, 0.15, 0), Color(0.9, 0.9, 0.92))  # kylmälaukku
		"Jaakko":
			B.mesh(n, B.boxm(Vector3(0.7, 0.32, 0.32)), Vector3(0, 0.16, 0), Color(0.2, 0.45, 0.28))
			B.mesh(n, B.boxm(Vector3(0.72, 0.05, 0.12)), Vector3(0, 0.3, 0), Color(0.1, 0.25, 0.15))
		_:
			B.mesh(n, B.boxm(Vector3(0.7, 0.34, 0.34)), Vector3(0, 0.17, 0), Color(0.2, 0.3, 0.6))
			B.mesh(n, B.boxm(Vector3(0.72, 0.05, 0.12)), Vector3(0, 0.32, 0), Color(0.9, 0.8, 0.2))
	return n


func _walk_to(i: int, target: Vector3, delta: float) -> bool:
	var b: CharacterBody3D = _crew[i]
	var to := target - b.global_position
	to.y = 0.0
	if to.length() < 0.25:
		_anim(i, "Idle")
		return true
	b.global_position += to.normalized() * WALK_SPEED * delta
	b.global_position.y = Terrain.h(b.global_position.x, b.global_position.z)
	b.rotation.y = atan2(-to.x, -to.z)
	_anim(i, "Walk")
	return false


func _win(delta: float) -> void:
	var c := _car()
	var right := c.global_transform.basis.x
	var back := c.global_transform.basis.z
	var centre := _centre
	# Aurinko: kello kiertää hitaasti iltaan (ei verkkopelissä, jossa aika kulkee yhteisesti).
	if not game.mp.online():
		var k := clampf(_t / (_ring_t + LUG_T), 0.0, 1.0)
		game.sun.t_utc = lerpf(_sun_from, _sun_to, k * k * (3.0 - 2.0 * k))
		if _t > _ring_t + LUG_T:
			game.sun.t_utc = _sun_to + (_t - _ring_t - LUG_T) * 60.0  # kaahatessa ilta etenee hieman
		game.sun._update(true)
	if _t < _ring_t:
		_win_ring(delta, centre, right)
		return
	if _t < _ring_t + LUG_T:
		_win_luggage(delta, centre, right, back)
		return
	_win_drive(delta)


## Ringissä: käsi toisen hartioilla, vuorotellen puhuja viittoo, muut kallistuvat sisäänpäin ja heiluvat.
func _win_ring(delta: float, centre: Vector3, right: Vector3) -> void:
	var speaker := -1
	var li := int(_t / LINE_T)
	if li < _lines.size() and fmod(_t, LINE_T) > 0.2:
		speaker = int(_lines[li][0])
	for i in _crew.size():
		var b: CharacterBody3D = _crew[i]
		var body: Node3D = b.body()
		var talking := i == speaker or (li < _lines.size() and int(_lines[li][0]) == -1)
		_anim(i, "Idle_Talking" if talking else "Idle")
		body.rotation.x = deg_to_rad(-5.0)
		body.rotation.z = sin(_t * 1.9 + i * 1.6) * 0.05
		# Ringin hidas heilunta: joukko keinuu yhdessä.
		var ang := TAU * float(i) / float(_crew.size()) + 0.4 + sin(_t * 0.4) * 0.06
		var want := centre + Vector3(cos(ang), 0, sin(ang)) * (RING_R - 0.03 * sin(_t * 1.3 + i))
		b.global_position = Vector3(want.x, Terrain.h(want.x, want.z) + 0.02, want.z)
		var look := centre - b.global_position
		b.rotation.y = atan2(-look.x, -look.z)
	_ring_arms(centre)
	# Repliikki alkaa: puhekupla puhujalle (yhteislause kaikille).
	if li < _lines.size() and not _said.has(li) and fmod(_t, LINE_T) > 0.2:
		_said[li] = true
		var who: int = _lines[li][0]
		var txt: String = _lines[li][1]
		if who < 0:
			_bubble(_crew[0], txt, LINE_T - 0.3, true)  # yhteislause yhdessä kuplassa, kaikkien äänellä
			Sfx.play("coin", -10.0, 1.3)
		else:
			_bubble(_crew[who], txt, LINE_T - 0.2)
	_heart_t -= delta
	if _heart_t <= 0.0:
		_heart_t = 0.45
		var who2: CharacterBody3D = _crew[randi() % _crew.size()]
		if randf() < 0.6:
			_fx_spawn(who2.global_position + Vector3(randf_range(-0.3, 0.3), 2.0, 0), "♥", Color(1.0, 0.35, 0.5))
		else:
			_fx_spawn(who2.global_position + Vector3(0.12, 1.65, -0.2), "💧", Color(0.6, 0.85, 1.0))
	# Kamera kiertää ringin ympäri hitaasti auton puolelta alkaen (pihan puu ei peitä).
	var u := _t / _ring_t
	var ang_c := lerpf(0.0, 1.1, u)
	var rad := lerpf(3.6, 2.6, u)
	var dir0 := -right
	var off := dir0.rotated(Vector3.UP, ang_c) * rad
	var tgt := centre + Vector3(0, 1.15, 0)
	_cam.global_position = _clear_cam(tgt, centre + off + Vector3(0, lerpf(1.7, 1.45, u), 0))
	_cam.look_at(tgt, Vector3.UP)
	_caption.text = "Ensi kesänä uudestaan!" if li >= _lines.size() - 1 else "Hyvä viikonloppu…"


var _said := {}
var _ik_on := false


## Kädet toisten olkapäillä: kumpikin käsi menee viereisen hahmon olkapäälle (oikea käsi oikealla puolella olevalle).
func _ring_arms(centre: Vector3) -> void:
	_ik_on = true
	for i in _crew.size():
		var b: CharacterBody3D = _crew[i]
		var body: Node3D = b.body()
		var shoulder_me := b.global_position + Vector3(0, 1.4, 0)
		for n in [(i + 1) % _crew.size(), (i + _crew.size() - 1) % _crew.size()]:
			var o: CharacterBody3D = _crew[n]
			var rel := o.global_position - b.global_position
			var right_side := rel.dot(b.global_transform.basis.x) > 0.0
			var side := "r" if right_side else "l"
			var out := (o.global_position - centre).normalized()
			# Naapurin olkapää: hieman ulospäin ja ylhäällä, jotta käsi lepää olan päällä ja selän puolella.
			var target_w := o.global_position + Vector3(0, 1.42, 0) + out * 0.08
			var pole_w := shoulder_me + (shoulder_me - centre).normalized() * 0.5 + Vector3(0, -0.25, 0)
			body.set_ik("arm_" + side, "upperarm_" + side, "lowerarm_" + side, "hand_" + side, body.to_local(target_w), body.to_local(pole_w))


## Matkatavarat autoon: jokainen hakee omansa ringin vierestä ja vie auton takakontille, lopuksi kaikki kävelevät oven luo.
func _win_luggage(delta: float, centre: Vector3, right: Vector3, back: Vector3) -> void:
	var c := _car()
	var rear := c.global_position + back * 2.9
	var door := c.global_position + right * 1.4
	var lt := _t - _ring_t
	if _ik_on:
		_ik_on = false
		for ch: CharacterBody3D in _crew:
			ch.body().clear_ik()  # ringin käsiasennot pois
	for i in _crew.size():
		var b: CharacterBody3D = _crew[i]
		b.body().rotation = Vector3.ZERO
		var st: Array = _lug[i]
		if lt < float(st[1]):
			_anim(i, "Idle")
			continue
		var bag: Node3D = _bags[i][0]
		match int(st[0]):
			0:  # hae oma tavara
				if _walk_to(i, _bags[i][1], delta):
					st[0] = 1
					st[1] = -1.0  # kantaa: tavara seuraa hahmoa käsin (ei reparentia, joka jäädyttää renderin)
			1:  # kanna takakonttiin
				var side_v := b.global_transform.basis.x
				bag.global_position = b.global_position + side_v * 0.32 + Vector3(0, 0.05, 0) - b.global_transform.basis.z * 0.1
				bag.global_position.y = b.global_position.y + 0.05
				bag.rotation.y = b.rotation.y
				if _walk_to(i, rear + right * (float(i) - 1.5) * 0.35, delta):
					st[0] = 2
					st[1] = lt
					bag.visible = false
					Sfx.play("door_close", -8.0, 0.8 + 0.1 * i)
					_dress(i)  # kamat konttiin, vaatteet päälle ennen kaahausta
			2:  # kävele oven luo
				_walk_to(i, door + back * (float(i) - 1.5) * 0.45, delta)
	_win_luggage_cam(centre, right, back)
	_caption.text = "Kamat autoon!"


func _win_luggage_cam(centre: Vector3, _right: Vector3, back: Vector3) -> void:
	var c := _car()
	var rear := c.global_position + back * 2.9
	var along := Vector3(centre.x - c.global_position.x, 0, centre.z - c.global_position.z).normalized()
	# Kamera tielle (tiellä ei kasva puita): auton takaa tai edestä katsoen kohti takakonttia ja ringin paikkaa.
	var tgt := rear + along * 1.5 + Vector3(0, 1.0, 0)
	var want := _clear_pick(tgt, [c.global_position + back * 9.0 + Vector3(0, 1.7, 0), c.global_position - back * 9.0 + Vector3(0, 1.7, 0),
		c.global_position + back * 6.5 + Vector3(0, 2.4, 0)])
	_cam.global_position = _cam.global_position.lerp(want, 1.0 - exp(-2.0 * get_process_delta_time()))
	_cam.look_at(tgt, Vector3.UP)


## Kaahaus: kamera ensin takana, sitten tien sivulta niin, että auto ajaa laskevaa aurinkoa vasten.
func _win_drive(delta: float) -> void:
	var c := _car()
	for b: CharacterBody3D in _crew:
		b.visible = false
	for bag: Array in _bags:
		(bag[0] as Node3D).visible = false
	var drive_t := _t - (_ring_t + LUG_T)
	if not _honked:
		_honked = true
		Sfx.play("horn", -4.0, 1.0)
		_cam.global_position = c.global_position + c.global_transform.basis.z * 8.0 + Vector3(0, 3.0, 0)
	# Piilotettu pelaajan hahmo kulkee auton mukana, jotta puut ja niiden törmäysrungot latautuvat reitin varrelle
	# (kameran esteettömyystarkistus toimii).
	(_crew[game.player_index] as CharacterBody3D).global_position = c.global_position
	_car_v = minf(24.0, _car_v + 4.2 * delta)  # kaahataan
	_car_s += _car_v * delta
	var r := _route_at(_car_s)
	var pos: Vector2 = r[0]
	var dir: Vector2 = r[1]
	c.global_position = Vector3(pos.x, Terrain.h(pos.x, pos.y), pos.y)
	c.rotation.y = atan2(-dir.x, -dir.y)
	c.rotation.z = sin(drive_t * 6.0) * 0.015 * clampf(_car_v / 10.0, 0.0, 1.0)
	c.speed = _car_v
	var behind := Vector3(-dir.x, 0, -dir.y)
	var chase := c.global_position + behind * 9.0 + Vector3(0, 3.0, 0) + Vector3(dir.y, 0, -dir.x) * 2.5
	# Myöhemmin kamera laskeutuu tien tasolle auton taakse: tie on aukea käytävä, joten puut eivät peitä, ja horisontin
	# laskeva aurinko näkyy auton yllä.
	var low := c.global_position + behind * 8.0 + Vector3(0, 1.1, 0) + Vector3(dir.y, 0, -dir.x) * 0.6
	var tgt := c.global_position + Vector3(0, 1.3, 0)
	var k := smoothstep(3.0, 6.5, drive_t)
	var want := _clear_cam(tgt, chase.lerp(low, k))
	_cam.global_position = want  # ei viivettä: auto ajaa 24 m/s eikä saa karata kuvasta
	_cam.look_at(c.global_position + Vector3(0, 1.0, 0), Vector3.UP)
	_caption.text = "Kaahataan auringonlaskuun!" if drive_t < DRIVE_T - 3.0 else "Hyvä viikonloppu. Ensi kesänä uudestaan."
	if drive_t > DRIVE_T - 2.5:
		_fade.color.a = clampf((drive_t - (DRIVE_T - 2.5)) / 2.0, 0.0, 1.0)
	if drive_t > DRIVE_T and not _text_done:
		_text_done = true
		_caption.text = ""
		_card.text = _card_text
	if _text_done and Input.is_action_just_pressed("interact"):
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
		Sfx.play("rattle_hard", -8.0, 0.5)
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
	if _text_done and Input.is_action_just_pressed("interact"):
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
	for ch: CharacterBody3D in _crew:
		ch.body().clear_ik()
	for bag: Array in _bags:
		if is_instance_valid(bag[0]):
			(bag[0] as Node3D).queue_free()
	_bags.clear()
	game.chat._ui.visible = _chat_was
	game.chat.bubbles_hidden = false
	if mode == "voitto" and not game.mp.online():
		game.sun.t_utc = _sun_from  # peli jatkuu vapaana sunnuntai-iltana
		game.sun._update(true)
	var c := _car()
	c.set_physics_process(true)
	c.rotation.z = 0.0
	c.place(Reitti.HOME_SPOT, Reitti.ROUTE[1])
	for i in _crew.size():
		var b: CharacterBody3D = _crew[i]
		if _clothed.has(i):
			b.body().restyle(Porukka.look(i))  # takaisin uikkareihin, peli jatkuu mökkiaikana
			Porukka.decorate(i, b.body())
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
