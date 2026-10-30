extends Node3D
## Äpätin venesatama Äpätin niemen länsipuolen lahdessa maavallin (niemen harjanteen) takana (n. 120 m itään ja 25 m pohjoiseen mökiltä, tien vasemmalla puolella): pitkä pääsilta
## järveen, T-pää, sivulaituri pienveneille, rannassa venevaja, nostoramppi ja veneentelakka-alue (kumossa olevat veneet
## telineillä, tynnyreitä, polttoainepumppu, pelastusrengas), lamput ja kyltti "ÄPÄTIN VENESATAMA". Pienveneitä
## (soutuveneitä ja alumiinimoottoriveneitä) on kiinni laiturien kyljissä ja poijuissa. Muskeliveneen paikka (harbor) on
## pääsillan itäkyljessä (muskelivene.gd moorings). Paikallinen kehys: u itään, v pohjoiseen (järvelle) niemen kärjen
## rantaviivasta (ORIGIN). Pääsillan kansi on 0,75 m vedenpinnan yläpuolella (mökkilaituri on muskeliveneelle liian matala).

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")

const ORIGIN := Vector2(116.0, -23.0)  # rantaviivan kohta sataman lahden etelärannalla, tien vasemmalla puolella (x, z)
const DECK := 0.75
const PIER_W := 2.4
const PIER_LEN := 28.0
const HEAD_V := Vector2(27.0, 28.4)  # T-pään v-väli
const HEAD_U := Vector2(-7.0, 7.0)
const SIDE_U := -10.0  # sivulaiturin keskilinja
const SIDE_V := Vector2(10.0, 24.0)
const ROAD_CLEAR := 3.0  # puita ei tien reunassa tätä lähempänä (m)
## Sataman tien keskiviiva (Äpätintie jatkeineen): puut raivataan ja auto pääsee ajamaan täyttä vauhtia perille.
const ROAD_LINE := [Vector2(-26.1, 141.4), Vector2(-8.1, 137.1), Vector2(17.4, 133.4), Vector2(37.0, 130.0),
	Vector2(53.1, 122.5), Vector2(68.4, 112.0), Vector2(83.9, 100.4), Vector2(90.2, 95.3), Vector2(97.0, 81.3),
	Vector2(102.1, 70.5), Vector2(112.5, 61.6), Vector2(121.2, 49.9), Vector2(123.7, 37.2), Vector2(125.4, 26.8),
	Vector2(129.6, 20.7), Vector2(136.8, 9.9), Vector2(145.4, -3.8), Vector2(153.8, -19.4), Vector2(159.7, -31.0),
	Vector2(166.3, -40.4), Vector2(169.9, -48.4), Vector2(168.8, -55.0), Vector2(164.9, -67.7), Vector2(156.2, -83.0),
	Vector2(151.5, -89.6), Vector2(147.1, -97.2)]
## Haara tieltä lahden rantaan sataman luo (tie kääntyy vasemmalle maavallin yli).
const SPUR := [Vector2(153.8, -19.4), Vector2(140.0, -21.5), Vector2(126.0, -20.0), Vector2(116.0, -17.0)]
const ROAD_TREE_R := 5.0  # puita ei tämän lähempänä tien keskiviivaa (m)
const GAP_A := Vector2(-12.0, 137.0)
const GAP_B := Vector2(6.0, 133.0)
const GAP_R := 4.5
const WOOD := Color(0.5, 0.4, 0.3)
const WOOD_D := Color(0.33, 0.25, 0.18)
const STEEL := Color(0.3, 0.32, 0.35)

var harbor := {}  # {name, pos, yaw, deck} (muskelivene.gd moorings)
var lamps: Array[StandardMaterial3D] = []
var _light: OmniLight3D
var _rng := RandomNumberGenerator.new()


static func _near_seg(p: Vector2, a: Vector2, b: Vector2, r: float) -> bool:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < r


## Onko piste sataman tiellä (ROAD_LINE ja tien katkoksen ylittävä GAP-osuus): auto ajaa siellä täyttä vauhtia.
static func on_road(x: float, z: float) -> bool:
	var q := Vector2(x, z)
	if _near_seg(q, GAP_A, GAP_B, 3.0):
		return true
	for k in ROAD_LINE.size() - 1:
		if _near_seg(q, ROAD_LINE[k], ROAD_LINE[k + 1], 3.0):
			return true
	for k in SPUR.size() - 1:
		if _near_seg(q, SPUR[k], SPUR[k + 1], 3.0):
			return true
	return false


## Paikallisen (u, v) -suorakulmion vastine maailmassa.
static func _rect(u0: float, u1: float, v0: float, v1: float) -> Rect2:
	var a := w2(u0, v0)
	var b := w2(u1, v1)
	return Rect2(a.min(b), (b - a).abs())


## Paikallinen (u, v) maailmaan (x, z).
static func w2(u: float, v: float) -> Vector2:
	return Vector2(ORIGIN.x + u, ORIGIN.y - v)


static func P(u: float, y: float, v: float) -> Vector3:
	var w := w2(u, v)
	return Vector3(w.x, y, w.y)


## Puut pois sataman alueelta ja satamaan johtavan tien päältä (rungot törmäävät, joten autolla pääsee perille).
static func clears_tree(x: float, z: float) -> bool:
	if x > ORIGIN.x - 22.0 and x < ORIGIN.x + 20.0 and z > ORIGIN.y - 8.0 and z < ORIGIN.y + 26.0:
		return true
	if x > -35.0 and x < 180.0 and z > -105.0 and z < 150.0:
		var q := Vector2(x, z)
		for k in ROAD_LINE.size() - 1:
			if _near_seg(q, ROAD_LINE[k], ROAD_LINE[k + 1], ROAD_TREE_R):
				return true
		for k in SPUR.size() - 1:
			if _near_seg(q, SPUR[k], SPUR[k + 1], ROAD_TREE_R):
				return true
	# Tien katkos Äpätintien ja sataman tien välillä (ei tieluokkaa): auton ajolinja raivataan.
	if _near_seg(Vector2(x, z), GAP_A, GAP_B, GAP_R):
		return true
	if x < ORIGIN.x - 70.0 or x > ORIGIN.x + 20.0 or z < ORIGIN.y - 10.0 or z > 70.0:
		return false
	for d: Vector2 in [Vector2.ZERO, Vector2(ROAD_CLEAR, 0), Vector2(-ROAD_CLEAR, 0), Vector2(0, ROAD_CLEAR), Vector2(0, -ROAD_CLEAR)]:
		if Terrain.surface(x + d.x, z + d.y) == Terrain.ROAD:
			return true
	return false


func _ready() -> void:
	_rng.seed = 2468
	_pier()
	_side_pier()
	_land()
	_boats()
	# avoid: pääsilta sivulaitureineen ja T-pää varoalueineen (muskeliveneen automaattiajo kiertää ne).
	harbor = {"name": "Äpätin venesatama", "pos": P(3.0, 0.0, 19.0), "yaw": 0.0, "deck": P(0.7, DECK, 19.0),
		"avoid": [_rect(-14.0, 2.5, -3.5, 31.0), _rect(2.5, 9.5, 24.5, 31.0)]}
	_light = OmniLight3D.new()
	_light.position = P(0.0, 4.0, HEAD_V.y - 0.4)
	_light.light_color = Color(1.0, 0.75, 0.45)
	_light.omni_range = 18.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	set_lamp(0.0)
	B.street_sign(self, P(-3.2, 1.0, -3.0), "ÄPÄTIN VENESATAMA", PI)


## Illalla lamput päälle (main.gd, kuten mokki.set_lamp): k 0..1.
func set_lamp(k: float) -> void:
	for m in lamps:
		m.emission_energy_multiplier = 3.0 * k
	_light.visible = k > 0.02
	_light.light_energy = 1.2 * k


func _box(u0: float, u1: float, v0: float, v1: float, y0: float, y1: float, color: Color, collide := true) -> void:
	B.box(self, Vector3(u1 - u0, y1 - y0, v1 - v0), P((u0 + u1) * 0.5, (y0 + y1) * 0.5, (v0 + v1) * 0.5), color, collide)


func _post(u: float, v: float, top: float) -> void:
	var w := w2(u, v)
	var gy := minf(Terrain.h(w.x, w.y), 0.0) - 0.5
	B.mesh(self, B.cyl(0.11, 0.11, top - gy, 8), P(u, (top + gy) * 0.5, v), WOOD_D)


func _lamp(u: float, v: float) -> void:
	B.mesh(self, B.cyl(0.04, 0.05, 2.8, 6), P(u, DECK + 1.4, v), STEEL)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.92, 0.65)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.35)
	m.emission_energy_multiplier = 0.0
	lamps.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = B.sphere(0.14, 8)
	mi.material_override = m
	mi.position = P(u, DECK + 2.9, v)
	add_child(mi)


func _bollard(u: float, v: float) -> void:
	B.mesh(self, B.cyl(0.09, 0.09, 0.32, 8), P(u, DECK + 0.16, v), STEEL)
	B.mesh(self, B.cyl(0.13, 0.13, 0.06, 8), P(u, DECK + 0.34, v), STEEL)


## Pääsilta rannasta järveen, T-pää ja pukit pohjaan, pollarit, fenderit ja lamput.
func _pier() -> void:
	var hu := PIER_W * 0.5
	_box(-hu, hu, -1.0, PIER_LEN, DECK - 0.1, DECK, WOOD)
	_box(-hu, hu, -1.0, PIER_LEN, DECK - 0.45, DECK - 0.1, Color(0, 0, 0, 0), false)
	for s: float in [-hu, hu - 0.1]:
		_box(s, s + 0.1, -1.0, PIER_LEN, DECK - 0.3, DECK + 0.12, WOOD_D, false)
	# T-pää.
	_box(HEAD_U.x, HEAD_U.y, HEAD_V.x, HEAD_V.y, DECK - 0.1, DECK, WOOD)
	_box(HEAD_U.x, HEAD_U.y, HEAD_V.y - 0.1, HEAD_V.y, DECK - 0.3, DECK + 0.12, WOOD_D, false)
	var v := 1.0
	while v < PIER_LEN:
		_post(-hu + 0.12, v, DECK + 0.1)
		_post(hu - 0.12, v, DECK + 0.1)
		v += 3.5
	for u: float in [HEAD_U.x + 0.2, -3.0, 0.0, 3.0, HEAD_U.y - 0.2]:
		_post(u, HEAD_V.y - 0.2, DECK + 0.1)
		_post(u, HEAD_V.x + 0.2, DECK + 0.1)
	# Pollarit itäkyljessä veneen kohdalla ja T-päässä, fenderit.
	for q: Vector2 in [Vector2(hu - 0.3, 16.0), Vector2(hu - 0.3, 22.0), Vector2(-hu + 0.3, 16.0), Vector2(-hu + 0.3, 22.0),
			Vector2(HEAD_U.y - 0.4, 27.6), Vector2(HEAD_U.x + 0.4, 27.6)]:
		_bollard(q.x, q.y)
	for k in 4:
		var fv := 16.0 + 2.2 * k
		_box(hu, hu + 0.12, fv - 0.3, fv + 0.3, DECK - 0.5, DECK - 0.05, Color(0.08, 0.08, 0.09), false)
	_lamp(0.0, 8.0)
	_lamp(0.0, HEAD_V.y - 0.6)
	# Pelastusrengas ja tikkaat.
	B.mesh(self, B.cyl(0.35, 0.35, 0.08, 14), P(hu - 0.15, DECK + 1.0, 10.0), Color(0.95, 0.4, 0.1), Vector3(0, 0, 90))
	_box(hu - 0.05, hu, 9.9, 10.1, DECK, DECK + 1.5, WOOD_D, false)
	for k in 3:
		B.mesh(self, B.cyl(0.02, 0.02, 0.5, 6), P(-hu - 0.02, DECK - 0.25 - k * 0.3, 12.0), STEEL, Vector3(0, 0, 90))


## Sivulaituri pienveneille: kapea laituri pääsillan länsipuolella, yhdistetty poikkisillalla.
func _side_pier() -> void:
	var w := 1.8
	_box(SIDE_U - w * 0.5, SIDE_U + w * 0.5, SIDE_V.x, SIDE_V.y, DECK - 0.1, DECK, WOOD)
	_box(-PIER_W * 0.5 - 8.2, -PIER_W * 0.5, SIDE_V.x, SIDE_V.x + 1.4, DECK - 0.1, DECK, WOOD)
	var v := SIDE_V.x + 0.3
	while v < SIDE_V.y:
		_post(SIDE_U - w * 0.5 + 0.12, v, DECK + 0.1)
		_post(SIDE_U + w * 0.5 - 0.12, v, DECK + 0.1)
		v += 3.5
	_bollard(SIDE_U, SIDE_V.y - 0.4)
	_bollard(SIDE_U + 0.5, 14.0)
	_bollard(SIDE_U - 0.5, 18.5)
	_lamp(SIDE_U, SIDE_V.y - 0.6)


## Rantaosa: venevaja, nostoramppi, telineet ja kumoon käännetyt veneet, tynnyrit, pumppu.
func _land() -> void:
	# Venevaja tien länsipuolella (punamullattu, harjakatto).
	var bu := -14.0
	var bv := -7.0
	var wb := w2(bu, bv)
	var gy := Terrain.h(wb.x, wb.y)
	B.box(self, Vector3(6.0, 2.6, 4.2), Vector3(wb.x, gy + 1.3, wb.y), Color(0.55, 0.14, 0.1))
	var roof := PrismMesh.new()
	roof.size = Vector3(6.6, 1.1, 4.8)
	B.mesh(self, roof, Vector3(wb.x, gy + 3.15, wb.y), Color(0.15, 0.15, 0.17))
	B.box(self, Vector3(1.8, 2.0, 0.08), Vector3(wb.x, gy + 1.0, wb.y + 2.14), Color(0.94, 0.94, 0.9), false)  # portti järvelle päin
	B.box(self, Vector3(0.7, 0.7, 0.06), Vector3(wb.x + 2.2, gy + 1.6, wb.y + 2.13), Color(0.7, 0.85, 0.95), false)
	# Nostoramppi: betonilaatta rannasta veteen.
	for k in 6:
		var wr := w2(8.0 + k * 1.8, -1.0 + k * 0.8)
		var ry := Terrain.h(wr.x, wr.y)
		B.box(self, Vector3(3.4, 0.14, 2.6), Vector3(wr.x, ry + 0.05, wr.y), Color(0.62, 0.62, 0.6), false)
	# Veneteline ja kumossa olevat soutuveneet.
	for k in 2:
		var wt := w2(-10.0 + k * 5.0, 4.0 - k * 1.5)
		var ty := Terrain.h(wt.x, wt.y)
		for s: float in [-1.2, 1.2]:
			B.box(self, Vector3(0.12, 0.7, 0.12), Vector3(wt.x + s, ty + 0.35, wt.y), WOOD_D, false)
		B.box(self, Vector3(2.8, 0.1, 0.12), Vector3(wt.x, ty + 0.7, wt.y), WOOD_D, false)
		var hull := B.mesh(self, B.boxm(Vector3(3.6, 0.5, 1.3)), Vector3(wt.x, ty + 1.0, wt.y), Color(0.2, 0.35, 0.55) if k == 0 else Color(0.7, 0.65, 0.5))
		hull.rotation.y = 0.2 * k
	# Tynnyrit, polttoainepumppu, laatikot, verkkoseipäät.
	for q: Vector2 in [Vector2(-8.0, -3.0), Vector2(-7.4, -2.5), Vector2(-7.9, -2.0)]:
		var wq := w2(q.x, q.y)
		B.mesh(self, B.cyl(0.3, 0.3, 0.9, 10), Vector3(wq.x, Terrain.h(wq.x, wq.y) + 0.45, wq.y), Color(0.15, 0.3, 0.55) if q.x > -7.7 else Color(0.7, 0.15, 0.1))
	var wp := w2(5.0, -4.0)
	var py := Terrain.h(wp.x, wp.y)
	B.box(self, Vector3(0.7, 1.5, 0.5), Vector3(wp.x, py + 0.75, wp.y), Color(0.8, 0.1, 0.08))
	B.box(self, Vector3(0.5, 0.35, 0.04), Vector3(wp.x, py + 1.2, wp.y + 0.27), Color(0.95, 0.9, 0.5), false)
	for k in 3:
		var wn := w2(-5.0 + k * 1.5, -6.0)
		B.mesh(self, B.cyl(0.04, 0.05, 2.2, 6), Vector3(wn.x, Terrain.h(wn.x, wn.y) + 1.1, wn.y), WOOD_D)
	# Ohut pengerrys polulle rannasta laiturille.
	for k in 4:
		var wg := w2(0.0, -1.0 + k * 0.5)
		B.box(self, Vector3(PIER_W, 0.06, 0.5), Vector3(wg.x, Terrain.h(wg.x, wg.y) + 0.04, wg.y), WOOD, false)


## Pieni vene: runko (laatikko + keula), sisäosa, penkki ja halutessa perämoottori. Keula kohti +v (pohjoista).
func _small_boat(u: float, v: float, yaw: float, blen: float, wid: float, color: Color, motor: bool) -> void:
	var root := Node3D.new()
	root.position = P(u, 0.0, v)
	root.rotation.y = yaw
	add_child(root)
	var body := blen - wid * 0.5
	B.mesh(root, B.boxm(Vector3(wid, 0.45, body)), Vector3(0, 0.02, 0), color)
	B.mesh(root, B.boxm(Vector3(wid * 0.707, 0.45, wid * 0.707)), Vector3(0, 0.02, -body * 0.5), color, Vector3(0, 45, 0))
	B.mesh(root, B.boxm(Vector3(wid - 0.2, 0.06, body - 0.2)), Vector3(0, 0.26, 0), color.lightened(0.5))
	B.mesh(root, B.boxm(Vector3(wid - 0.2, 0.05, 0.28)), Vector3(0, 0.38, 0), WOOD)
	if motor:
		B.mesh(root, B.boxm(Vector3(0.28, 0.5, 0.3)), Vector3(0, 0.5, body * 0.5 + 0.1), Color(0.15, 0.15, 0.17))


## Pienveneitä: sivulaiturin kyljissä, pääsillan länsikyljessä ja poijuissa.
func _boats() -> void:
	_small_boat(SIDE_U + 2.3, 15.0, 0.05, 4.2, 1.5, Color(0.8, 0.8, 0.82), true)
	_small_boat(SIDE_U - 2.2, 17.0, -0.04, 3.4, 1.3, Color(0.2, 0.4, 0.6), false)
	_small_boat(-5.2, 20.0, 0.08, 4.8, 1.7, Color(0.9, 0.9, 0.85), true)
	_small_boat(SIDE_U + 2.3, 21.0, -0.02, 3.6, 1.4, Color(0.7, 0.2, 0.15), false)
	_small_boat(-3.4, 12.0, 0.0, 3.2, 1.3, Color(0.3, 0.55, 0.3), false)
	# Poijuvene ja poijut.
	_small_boat(-14.0, 30.0, 0.5, 4.0, 1.5, Color(0.9, 0.9, 0.9), true)
	for q: Vector2 in [Vector2(-14.0, 26.0), Vector2(10.0, 30.0)]:
		B.mesh(self, B.sphere(0.28, 8), P(q.x, 0.0, q.y), Color(0.95, 0.3, 0.1))
