extends Node3D
## Camping Happy Beach (oikea paikka: Vankkuritie 1, Säräisniemi; pelissä tiivistetty Siperianrannan hiekkarannan
## törmälle n. 700 m mökiltä luoteeseen, ks. reitti.gd). Leirintäalue on ympärivuotinen: ravintola ja baari,
## kioski ja vastaanotto, mökkejä ja asuntovaunujen kausipaikkoja, ja hiekkaranta kävelymatkan päässä.
##
## Pelissä: tasainen alue törmän päällä (terraform), parkkipaikka tien päässä, ravintola- ja baarirakennus terasseineen
## järven puolella, kioski, kolme punamullattua mökkiä, kolme asuntovaunua, lippu, auringonlaskupenkit törmän
## reunalla, pitkospolku rantaan, hiekkarannalla aurinkotuolit ja laituri järveen. Baarissa myydään olutta
## aukioloaikoina (oikeat ajat: ma-to 9-14, pe-la 9-21, su suljettu); E ostaa oluen (main.gd).
##
## Kehys: alueen solmu on kierretty niin, että paikallinen +X on a (hiekkarannan suuntaan kaakkoon) ja -Z on b
## (järvelle), y on alueen tasosta (pad_y) ylöspäin. Ks. Reitti.cw ja Reitti.wc.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Reitti := preload("res://scripts/reitti.gd")

## Tasattava alue (a, b): [a0, a1, b0, b1], ja parkkipaikka sen sisällä.
const PAD := [-30.0, 22.0, -20.0, 24.0]
const LOT := [-8.0, 22.0, -14.0, 4.0]
const BLEND := 5.0
## Pitkospolku törmältä rantaan (a, alku-b, loppu-b).
const PATH_A := 6.5
const PATH_B := [24.0, 47.5]
## Baarin tiski kehyksessä (a, b) ja aukioloajat: [viikonpäivä (0 = su) -> [auki, kiinni]], tunteja.
const BAR := Vector2(-4.0, 18.2)
const HOURS := {1: [9, 14], 2: [9, 14], 3: [9, 14], 4: [9, 14], 5: [9, 21], 6: [9, 21]}
const HOURS_TEXT := "ma–to 9–14\npe–la 9–21\nsu suljettu"
const DECK_H := 0.1

const WALL := Color(0.95, 0.92, 0.82)
const TRIM := Color(0.1, 0.6, 0.65)
const ROOF := Color(0.13, 0.27, 0.3)
const RED := Color(0.55, 0.16, 0.11)
const WOOD := Color(0.62, 0.5, 0.36)
const GLASS := Color(0.45, 0.62, 0.72)

## Alueen tason korkeus (terraform).
static var pad_y := 8.6

var bar_pos := Vector3.ZERO  # asiakkaan paikka tiskin edessä (maailma)
var lamps: Array[StandardMaterial3D] = []
var _lamp_light: OmniLight3D
var _root: Node3D
var _batch: B.Batch


# --- Maasto ---------------------------------------------------------------------------------------------------

static func _in(q: Vector2, r: Array, m := 0.0) -> bool:
	return q.x >= r[0] - m and q.x <= r[1] + m and q.y >= r[2] - m and q.y <= r[3] + m


## Alue tasaiseksi (keskikorkeuteen) ja nurmeksi ennen kuin world.gd rakentaa maaston; parkkipaikka soraa, polku
## polkua, reunoilla BLEND m siirtymä. Kaukoverkko lasketaan tarkan alle, ettei se pilkistä läpi.
static func terraform() -> void:
	var g := Terrain.near
	if g == null:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for ab: Vector2 in [Vector2(PAD[0], PAD[2]), Vector2(PAD[1], PAD[2]), Vector2(PAD[0], PAD[3]), Vector2(PAD[1], PAD[3])]:
		var w := Reitti.cw(ab.x, ab.y)
		lo = lo.min(w)
		hi = hi.max(w)
	lo -= Vector2.ONE * (BLEND + 3.0)
	hi += Vector2.ONE * (BLEND + 3.0)
	var cls := g.classes.duplicate()
	var nodes := []
	var sum := 0.0
	var n := 0
	for j in range(int((lo.y + g.half) / g.step), int((hi.y + g.half) / g.step) + 1):
		for i in range(int((lo.x + g.half) / g.step), int((hi.x + g.half) / g.step) + 1):
			var p := Vector2(-g.half + i * g.step, -g.half + j * g.step)
			var q := Reitti.wc(p)
			var out := maxf(maxf(PAD[0] - q.x, q.x - PAD[1]), maxf(PAD[2] - q.y, q.y - PAD[3]))
			if out < BLEND:
				nodes.append([j * g.n + i, out])
			if out < 0.0:
				sum += g.heights[j * g.n + i]
				n += 1
			if i < g.n - 1 and j < g.n - 1:
				var c := j * (g.n - 1) + i
				if out < 0.8 and cls[c] != Terrain.WATER:
					cls[c] = Terrain.FILL if _in(q, LOT) else Terrain.YARD
				elif absf(q.x - PATH_A) < 1.2 and q.y > PATH_B[0] - 1.0 and q.y < PATH_B[1] and cls[c] == Terrain.FOREST:
					cls[c] = Terrain.PATH
	g.classes = cls
	if n == 0:
		return
	pad_y = sum / n
	var hs := g.heights
	for e in nodes:
		hs[e[0]] = lerpf(pad_y, hs[e[0]], smoothstep(0.0, BLEND, e[1]))
	g.heights = hs
	var f := Terrain.far
	if f == null:
		return
	var fs := f.heights
	for fj in range(int((lo.y - 16.0 + f.half) / f.step), int((hi.y + 16.0 + f.half) / f.step) + 1):
		for fi in range(int((lo.x - 16.0 + f.half) / f.step), int((hi.x + 16.0 + f.half) / f.step) + 1):
			var x := -f.half + fi * f.step
			var z := -f.half + fj * f.step
			var m := INF
			for dz in range(-16, 17, 4):
				for dx in range(-16, 17, 4):
					m = minf(m, g.h(x + dx, z + dz))
			fs[fj * f.n + fi] = minf(fs[fj * f.n + fi], m)
	f.heights = fs


## Puut pois alueelta, sen reunoilta ja rantapolulta (trees.gd).
static func clears_tree(x: float, z: float) -> bool:
	if absf(x - Reitti.K.x) > 70.0 or absf(z - Reitti.K.y) > 70.0:
		return false
	var q := Reitti.wc(Vector2(x, z))
	if _in(q, PAD, 2.5):
		return true
	return absf(q.x - PATH_A) < 1.8 and q.y > PATH_B[0] and q.y < PATH_B[1]


# --- Aukioloajat ja baari -------------------------------------------------------------------------------------

## Onko baari ja kioski auki hetkellä lt (sun.local(): weekday 0 = sunnuntai, hour, minute).
static func is_open(lt: Dictionary) -> bool:
	var wd: int = lt.weekday
	if not HOURS.has(wd):
		return false
	var h: int = lt.hour
	return h >= HOURS[wd][0] and h < HOURS[wd][1]


static func open_text(lt: Dictionary) -> String:
	var wd: int = lt.weekday
	if not HOURS.has(wd):
		return "suljettu sunnuntaisin"
	return "auki %d–%d" % [HOURS[wd][0], HOURS[wd][1]]


## Asiakas tiskin edessä (baarin E).
func at_bar(p: Vector3) -> bool:
	return Vector2(p.x - bar_pos.x, p.z - bar_pos.z).length() < 2.4 and absf(p.y - bar_pos.y) < 1.5


## Pelaaja alueella (parkkipaikka, rakennukset ja terassi).
static func in_camp(p: Vector3) -> bool:
	return _in(Reitti.wc(Vector2(p.x, p.z)), PAD, 6.0)


# --- Rakentaminen ---------------------------------------------------------------------------------------------

func _ready() -> void:
	_root = Node3D.new()
	_root.position = Vector3(Reitti.K.x, pad_y, Reitti.K.y)
	_root.rotation.y = Reitti.yaw()
	add_child(_root)
	_batch = B.Batch.new()
	var deck_world := Reitti.cw(BAR.x, BAR.y)
	bar_pos = Vector3(deck_world.x, pad_y + DECK_H, deck_world.y)
	_main_building()
	_kiosk()
	for k in 3:
		_cabin(-24.0, -2.0 + k * 9.0)
	_caravan(14.0, 12.0, 0.15)
	_caravan(19.0, 17.0, -0.2)
	_caravan(14.0, 20.5, 0.05)
	_flag(3.5, 7.0)
	_entrance()
	_benches()
	_beach_path()
	_beach_and_jetty()
	var mi := MeshInstance3D.new()
	mi.mesh = _batch.commit()
	mi.material_override = B.vcol_mat()
	_root.add_child(mi)
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = P(-4.0, 3.2, 19.0)
	_lamp_light.light_color = Color(1.0, 0.72, 0.42)
	_lamp_light.omni_range = 16.0
	_lamp_light.shadow_enabled = false
	_lamp_light.visible = false
	_root.add_child(_lamp_light)
	set_lamp(0.0)


## Paikallinen paikka kehyksessä: a, y (alueen tasosta), b.
static func P(a: float, y: float, b: float) -> Vector3:
	return Vector3(a, y, -b)


## Paikallinen korkeus alueen tasosta maailman maaston pintaan kohdassa (a, b).
static func ground(a: float, b: float) -> float:
	var w := Reitti.cw(a, b)
	return Terrain.h(w.x, w.y) - pad_y


## Laatikko paikallisessa kehyksessä; keskipiste (a, y, b), koko (a:n, y:n, b:n suunnassa).
func _box(c: Vector3, size: Vector3, color: Color, collide := true) -> void:
	B.box(_root, Vector3(size.x, size.y, size.z), P(c.x, c.y, c.z), color, collide)


## Harjakatto: pituus ridge harjan suuntaan, leveys span, korkeus rise; harja a-suunnassa (along_a) tai b:n.
func _roof(c: Vector3, span: float, ridge: float, rise: float, color: Color, along_a: bool) -> void:
	var pm := PrismMesh.new()
	pm.size = Vector3(span, rise, ridge)
	var mi := B.mesh(_root, pm, P(c.x, c.y, c.z), color)
	if along_a:
		mi.rotation.y = PI * 0.5


## Ikkuna rakennuksen b-puoleiseen seinään (lasi ja valkoiset pielet), keskikohta (a, y), seinän b.
func _window(a: float, y: float, b: float, w: float, h: float, side: float) -> void:
	_box(Vector3(a, y, b + side * 0.02), Vector3(w, h, 0.06), GLASS, false)
	_box(Vector3(a, y, b + side * 0.04), Vector3(w + 0.16, 0.08, 0.04), Color.WHITE, false)
	_box(Vector3(a, y + h * 0.5 + 0.04, b + side * 0.04), Vector3(w + 0.16, 0.08, 0.04), Color.WHITE, false)
	_box(Vector3(a, y - h * 0.5 - 0.04, b + side * 0.04), Vector3(w + 0.16, 0.08, 0.04), Color.WHITE, false)
	_box(Vector3(a, y, b + side * 0.04), Vector3(0.06, h, 0.04), Color.WHITE, false)


func _lamp_bulb(pos: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.9, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.35)
	m.emission_energy_multiplier = 0.0
	lamps.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = B.sphere(0.09, 8)
	mi.material_override = m
	mi.position = pos
	_root.add_child(mi)


## Illalla valot päälle (main.gd, kuten mokki.set_lamp): k 0..1.
func set_lamp(k: float) -> void:
	for m in lamps:
		m.emission_energy_multiplier = 3.0 * k
	_lamp_light.visible = k > 0.02
	_lamp_light.light_energy = 1.3 * k


## Ravintola ja baari: vaalea rakennus turkoosein pielin, harjakatto, terassi järven puolella, tiski ja baarimikko,
## pöytiä, päivänvarjoja ja valoköynnös.
func _main_building() -> void:
	# Rakennus a -11..3, b 9..16, seinät 3 m.
	_box(Vector3(-4.0, 1.5, 12.5), Vector3(14.0, 3.0, 7.0), WALL)
	_box(Vector3(-4.0, 3.02, 12.5), Vector3(14.3, 0.08, 7.3), TRIM, false)
	_roof(Vector3(-4.0, 3.9, 12.5), 8.4, 14.8, 1.8, ROOF, true)
	_box(Vector3(5.2, 1.5, 12.5), Vector3(0.1, 3.0, 7.0), WALL, false)
	# Ikkunat ja ovi järven puolen seinässä (b = 16, ulospäin +b) ja tien puolen seinässä (b = 9, ulospäin -b).
	for a: float in [-9.0, 1.0]:
		_window(a, 1.7, 16.0, 1.4, 1.2, 1.0)
	_box(Vector3(-4.0, 1.1, 16.04), Vector3(1.0, 2.2, 0.06), TRIM, false)
	for a: float in [-9.0, -5.5, -2.0, 1.5]:
		_window(a, 1.7, 9.0, 1.2, 1.1, -1.0)
	# Terassi järven puolella.
	_box(Vector3(-4.0, DECK_H * 0.5, 18.6), Vector3(16.0, DECK_H, 5.2), WOOD)
	for a in range(-11, 5, 2):
		_box(Vector3(float(a), DECK_H + 0.4, 21.15), Vector3(0.1, 0.8, 0.1), WOOD, false)
	_box(Vector3(-4.0, DECK_H + 0.8, 21.15), Vector3(16.0, 0.07, 0.1), WOOD, false)
	# Tiski: katettu baaritiski terassilla seinää vasten, baarimikko tiskin takana.
	_box(Vector3(BAR.x, 0.6, BAR.y - 0.6), Vector3(4.6, 1.1, 0.8), TRIM)
	_box(Vector3(BAR.x, 1.17, BAR.y - 0.6), Vector3(4.8, 0.06, 0.95), WOOD, false)
	for sx: float in [-2.2, 2.2]:
		_box(Vector3(BAR.x + sx, 1.45, BAR.y + 1.0), Vector3(0.1, 2.9, 0.1), WOOD, false)
	_box(Vector3(BAR.x, 2.95, 17.65), Vector3(5.4, 0.08, 3.3), TRIM, false)  # markiisi tiskin yllä
	var tender := B.person(_root, Color(0.1, 0.6, 0.65), Color(0.15, 0.15, 0.18), Color(1.0, 0.84, 0.74), Color(0.55, 0.38, 0.2))
	tender.position = P(BAR.x + 0.6, DECK_H, BAR.y - 1.5)
	# Kyltit: iso kyltti seinässä järven puolella ja aukioloajat tiskin vieressä.
	var big := B.sign_plate(_root, "CAMPING\nHAPPY BEACH", TRIM, Color.WHITE, 0.4, 72, Color(0.95, 0.9, 0.5))
	big.position = P(-4.0, 5.5, 12.5)  # katonharjan päällä, teksti molemmin puolin
	for s: float in [-1.0, 1.0]:
		_box(Vector3(-4.0 + s * 1.3, 4.95, 12.5), Vector3(0.1, 0.6, 0.1), WOOD, false)
	var hours := B.sign_plate(_root, "KIOSKI JA BAARI\n" + HOURS_TEXT, Color(0.97, 0.95, 0.88), Color(0.1, 0.1, 0.12), 0.18, 34,
		TRIM)
	hours.position = P(-6.75, 1.9, 16.12)
	# Pöydät ja penkit terassilla, päivänvarjot.
	for pos: Vector2 in [Vector2(-9.5, 19.6), Vector2(0.6, 19.8), Vector2(2.9, 19.0)]:
		_picnic(pos.x, pos.y)
	for pos: Vector2 in [Vector2(-9.5, 19.6), Vector2(0.6, 19.8)]:
		_box(Vector3(pos.x, 1.2, pos.y), Vector3(0.07, 2.4, 0.07), Color(0.4, 0.4, 0.4), false)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.5
		cone.height = 0.55
		cone.radial_segments = 12
		cone.rings = 0
		B.mesh(_root, cone, P(pos.x, 2.5, pos.y), Color(0.95, 0.75, 0.15))
	# Valoköynnös terassin reunalla.
	for k in 9:
		var a := -11.0 + k * 2.0
		_lamp_bulb(P(a, 2.55 - 0.2 * float(k % 2), 21.15))
	_lamp_bulb(P(BAR.x, 2.75, BAR.y + 1.0))


func _picnic(a: float, b: float) -> void:
	_box(Vector3(a, DECK_H + 0.75, b), Vector3(1.9, 0.06, 0.8), WOOD)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(a, DECK_H + 0.45, b + s * 0.75), Vector3(1.9, 0.05, 0.3), WOOD, false)
	_box(Vector3(a - 0.7, DECK_H + 0.37, b), Vector3(0.08, 0.74, 1.5), WOOD, false)
	_box(Vector3(a + 0.7, DECK_H + 0.37, b), Vector3(0.08, 0.74, 1.5), WOOD, false)


## Kioski ja vastaanotto parkkipaikan vieressä.
func _kiosk() -> void:
	_box(Vector3(-14.0, 1.35, 4.0), Vector3(3.6, 2.7, 3.2), Color(0.1, 0.55, 0.6))
	_roof(Vector3(-14.0, 3.2, 4.0), 3.6, 4.2, 0.9, ROOF, false)
	_box(Vector3(-14.0, 1.5, 2.37), Vector3(1.8, 1.1, 0.06), GLASS, false)  # myyntiluukku parkkipaikalle
	_box(Vector3(-14.0, 0.95, 2.2), Vector3(2.2, 0.06, 0.45), WOOD, false)
	_box(Vector3(-14.0, 2.4, 2.38), Vector3(3.0, 0.05, 0.1), Color.WHITE, false)
	var s := B.sign_plate(_root, "KIOSKI · VASTAANOTTO", Color(0.97, 0.95, 0.88), TRIM.darkened(0.3), 0.2, 40, TRIM)
	s.position = P(-14.0, 2.75, 2.33)


## Punamullattu mökki (4,2 x 3,6) valkoisin nurkin, ovi ja ikkuna a-suuntaan (itään).
func _cabin(a: float, b: float) -> void:
	_box(Vector3(a, 1.2, b), Vector3(4.2, 2.4, 3.6), RED)
	_box(Vector3(a, 2.42, b), Vector3(4.4, 0.08, 3.8), Color.WHITE, false)
	_roof(Vector3(a, 3.1, b), 4.6, 4.4, 1.3, ROOF.darkened(0.2), true)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(a + s * 2.12, 1.2, b - 1.82), Vector3(0.12, 2.4, 0.12), Color.WHITE, false)
		_box(Vector3(a + s * 2.12, 1.2, b + 1.82), Vector3(0.12, 2.4, 0.12), Color.WHITE, false)
	# Ovi ja ikkuna kohti pihaa (+a).
	_box(Vector3(a + 2.12, 1.0, b - 0.7), Vector3(0.06, 2.0, 0.9), Color.WHITE, false)
	_box(Vector3(a + 2.13, 1.4, b + 0.8), Vector3(0.06, 0.9, 0.9), GLASS, false)
	_box(Vector3(a + 2.9, 0.12, b - 0.7), Vector3(1.4, 0.24, 1.3), WOOD)  # rappu
	_box(Vector3(a + 0.1, 0.05, b + 2.3), Vector3(1.0, 0.1, 0.5), WOOD.darkened(0.2), false)  # polttopuupino


## Asuntovaunu kausipaikalla: valkoinen runko, kaarevat päädyt, ikkunat, tukijalat ja markiisi.
func _caravan(a: float, b: float, yaw: float) -> void:
	var node := Node3D.new()
	node.position = P(a, 0.0, b)
	node.rotation.y = yaw
	_root.add_child(node)
	B.box(node, Vector3(2.3, 2.0, 6.6), Vector3(0.0, 1.35, 0.0), Color(0.95, 0.95, 0.93))
	B.mesh(node, B.boxm(Vector3(2.35, 0.25, 6.7)), Vector3(0.0, 0.5, 0.0), Color(0.5, 0.52, 0.55))
	B.mesh(node, B.boxm(Vector3(2.32, 0.12, 6.62)), Vector3(0.0, 1.3, 0.0), Color(0.35, 0.55, 0.7))
	for z: float in [-1.8, 0.2, 2.0]:
		for s: float in [-1.0, 1.0]:
			B.mesh(node, B.boxm(Vector3(0.06, 0.7, 1.0)), Vector3(s * 1.16, 1.6, z), GLASS)
	for s: float in [-1.0, 1.0]:
		B.mesh(node, B.cyl(0.38, 0.38, 0.22, 14), Vector3(s * 1.2, 0.38, 0.4), Color(0.08, 0.08, 0.09), Vector3(0, 0, 90))
	B.mesh(node, B.boxm(Vector3(0.1, 0.1, 1.8)), Vector3(0.0, 0.7, -4.0), Color(0.3, 0.3, 0.32))  # vetokanki
	B.mesh(node, B.boxm(Vector3(2.0, 0.06, 2.0)), Vector3(1.9, 2.0, 0.2), Color(0.1, 0.6, 0.65)).rotation.z = -0.25  # markiisi
	B.mesh(node, B.boxm(Vector3(1.8, 0.04, 1.8)), Vector3(1.9, 0.02, 0.2), Color(0.35, 0.45, 0.3))  # matto


func _flag(a: float, b: float) -> void:
	_box(Vector3(a, 4.0, b), Vector3(0.1, 8.0, 0.1), Color(0.85, 0.85, 0.85))
	_box(Vector3(a, 7.2, b - 0.8), Vector3(0.02, 1.0, 1.6), Color.WHITE, false)
	_box(Vector3(a, 7.2, b - 0.8), Vector3(0.03, 1.0, 0.24), Color(0.0, 0.21, 0.56), false)
	_box(Vector3(a, 7.2, b - 0.8), Vector3(0.03, 0.24, 1.6), Color(0.0, 0.21, 0.56), false)


## Sisäänkäynti: iso kyltti tien varrella ("Camping Happy Beach · Vankkuritie 1") ja kaksi valopylvästä.
func _entrance() -> void:
	var s := B.sign_plate(_root, "CAMPING HAPPY BEACH\nVankkuritie 1 · ympärivuotinen", TRIM, Color.WHITE, 0.3, 54,
		Color(0.95, 0.9, 0.5))
	var w: float = s.get_meta("width")
	s.position = P(18.0, 2.3, -17.0)  # tien (a ≈ 11 kohdassa b = -17) vieressä, teksti tulijaa kohti
	_box(Vector3(18.0 - w * 0.5 + 0.1, 1.15, -17.0), Vector3(0.12, 2.3, 0.12), WOOD, false)
	_box(Vector3(18.0 + w * 0.5 - 0.1, 1.15, -17.0), Vector3(0.12, 2.3, 0.12), WOOD, false)
	for sa: float in [3.0, 10.6]:
		_box(Vector3(sa, 1.4, -11.0), Vector3(0.1, 2.8, 0.1), WOOD, false)
		_lamp_bulb(P(sa, 2.9, -11.0))


## Auringonlaskupenkit törmän reunalla, katse järvelle.
func _benches() -> void:
	for a: float in [-14.0, -8.0, 14.0]:
		var b := 26.5
		var gy := ground(a, b)
		_box(Vector3(a, gy + 0.45, b), Vector3(1.8, 0.07, 0.45), WOOD)
		_box(Vector3(a, gy + 0.75, b - 0.25), Vector3(1.8, 0.4, 0.06), WOOD, false)
		for s: float in [-0.8, 0.8]:
			_box(Vector3(a + s, gy + 0.22, b), Vector3(0.08, 0.44, 0.4), WOOD, false)


## Pitkospolku törmältä hiekkarannalle: lankut maaston pinnalla ja kaide yhdellä sivulla.
func _beach_path() -> void:
	var b: float = PATH_B[0]
	while b < PATH_B[1]:
		var y0 := ground(PATH_A, b - 0.5)
		var y1 := ground(PATH_A, b + 0.5)
		var xf := Transform3D(Basis(Vector3.RIGHT, atan2(y1 - y0, 1.0)), P(PATH_A, (y0 + y1) * 0.5 + 0.05, b))
		_batch.add(B.boxm(Vector3(1.3, 0.05, 0.38)), xf, WOOD)
		b += 0.5
	b = PATH_B[0]
	while b < PATH_B[1]:
		_batch.add(B.boxm(Vector3(0.07, 0.9, 0.07)), Transform3D(Basis(), P(PATH_A + 0.7, ground(PATH_A + 0.7, b) + 0.45, b)),
			WOOD.darkened(0.2))
		b += 3.0


## Hiekkarannalla aurinkotuolit ja rantapallo, laituri järveen.
func _beach_and_jetty() -> void:
	for a: float in [-4.0, 0.0, 3.5]:
		var b := 45.6
		var gy := ground(a, b)
		_batch.add(B.boxm(Vector3(0.7, 0.07, 1.8)), Transform3D(Basis(Vector3.RIGHT, 0.2), P(a, gy + 0.3, b)), Color(0.1, 0.6, 0.65))
		for s: float in [-0.3, 0.3]:
			_batch.add(B.boxm(Vector3(0.05, 0.3, 0.05)), Transform3D(Basis(), P(a + s, gy + 0.12, b - 0.7)), WOOD)
	_batch.add(B.sphere(0.22, 10), Transform3D(Basis(), P(-1.8, ground(-1.8, 46.2) + 0.22, 46.2)), Color(0.95, 0.35, 0.2))
	# Laituri: kansi n. 1 m järven pinnan yläpuolella rannasta 14 m ulos, tolpat pohjaan.
	var ja := 14.0
	var b0 := 46.0
	var deck_y := maxf(0.7, ground(ja, b0) + pad_y + 0.05)
	var reach := 14.0
	_box(Vector3(ja, deck_y - pad_y, b0 + reach * 0.5), Vector3(1.5, 0.1, reach), WOOD)
	var k := 0.0
	while k <= reach:
		for s: float in [-0.7, 0.7]:
			_box(Vector3(ja + s, deck_y - pad_y - 1.0, b0 + k), Vector3(0.12, 2.0, 0.12), WOOD.darkened(0.3), false)
		k += 3.5
	_box(Vector3(ja, deck_y - pad_y + 0.2, b0 + reach), Vector3(1.5, 0.4, 0.08), WOOD.darkened(0.2), false)  # päätyreunus
