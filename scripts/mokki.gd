extends Node3D
## Mökki Äpätinniemen kärjessä valokuvien ja maastotietokannan mukaan:
## - alamökki eli rantasauna (MML:n rakennus 5,8 x 3,8 m, pelissä pidennetty törmään päin 8,1 m:iin, jotta
##   sisätiloihin mahtuu koko porukka; pääty kohti järveä NNW): sinharmaa hirsi,
##   valkoiset vuorilaudat ja räystäät, matala harjakatto kuusikulmiopaanuin, piippu, avokuisti järven puolella,
##   lyhdyt pylväissä ja halkovaja itäpäädyssä. Terassin puoleisella pitkällä sivulla katon alla pylväs ja kaksi
##   valkoista ovea (valokuva 20210709_171210): vasemmasta (järven päästä) pieneen keittiöön, jossa keittiö
##   oikealla ja pöytä neljälle järven puoleisen ikkunan edessä; oikeasta saunaan (pelkkä löylyhuone: lauteet
##   neljälle perällä, kiuas ovesta katsoen vasemmalla). Sisätiloihin voi kävellä. Saunan kupeessa törmässä
##   ehtymätön olut- ja viinakätkö.
## - iso terassi saunan länsipuolella: grillikatos (hirsi, matalat seinät, aumakatto, kaappi ja kaasugrilli),
##   valkoinen pop-up-teltta pöytineen ja penkkeineen, kaiteet ja portaat rantaan
## - etuterassi ja portaat kelluvalle laiturille, laiturin päässä tikkaat; huussi omalla terassillaan
## - ylämökki törmän päällä (MML:n rakennus 5,3 x 5,1 m): sinharmaa hirsi, valkoiset ikkunat, harjakatto,
##   aurinkopaneelit ja antenni, valkoinen säleikkö alla, terassi itäsivulla
## - jyrkät portaat (n. 38°, 22 askelmaa) terassilta törmään ylämökin terassille
## Terassin kohdalta maastoa kaivetaan (terraform), ja kaivannon reunat peitetään alkuperäisen maanpinnan
## mukaisella kivi- ja sammalpinnalla, jotta törmä näyttää ja tuntuu samalta kuin ennen.
##
## Kehykset: piha (u itään saunan päätyä pitkin, v järvelle saunan pitkää sivua pitkin), ylämökki (x pitkin
## järven puoleista seinää, v järvelle) ja portaat (v ylös). Kaikissa paikallinen z = -v.

signal loyly  # tietokoneen hahmo heitti löylyä (sauna.gd)
signal cooked(n: int)  # tietokoneen Marko paistoi lettuja (kokkaus.gd)

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")

## Materiaalit (verteksivärin alfa, ks. mokki.gdshader).
const PLAIN := 1.0
const LOG := 0.9
const BOARD_U := 0.8
const BOARD_V := 0.7
const SHINGLE := 0.6
const METAL := 0.5
const GLASS := 0.4
const LATTICE := 0.35
const FABRIC := 0.3
const GROUND := 0.25
const STONE := 0.2
const WINDOW := 0.15
const LAMP := 0.1

## Pihan kehys: origo saunan keskellä, LAKE saunan pitkän sivun suunta järvelle, EAST sen normaali.
const C := Vector2(-1.70, -4.905)
const LAKE := Vector2(-0.4445, -0.8958)
const EAST := Vector2(0.8958, -0.4445)
const DY := 1.3  # terassin ja saunan lattian korkeus järven pinnasta
## Ylämökin kehys (MML:n pohjapiirros): keskipiste ja järven puoleisen seinän suunta.
const CABIN_C := Vector2(-8.15, 9.19)
const CABIN_X := Vector2(0.854, -0.520)
const CABIN_LAKE := Vector2(-0.520, -0.854)
const CABIN_HX := 2.56
const CABIN_HV := 2.64
## Terassit pihan kehyksessä [u0, u1, v0, v1]: pääterassi, etuterassi, huussin terassi, sauna, halkovaja.
const DECKS := [[-10.8, -1.9, -3.2, 2.0], [-3.4, 2.2, 2.0, 4.3], [2.2, 5.4, -0.8, 4.3], [-1.9, 1.9, BACK, 2.9],
	[1.9, 3.2, -2.9, -0.8]]
const STAIR_W := 1.2
## Alamökki: takaseinän ulkopinta ja väliseinä (keittiön takaseinä) v-suunnassa sekä ovet terassin puoleisessa
## seinässä (v-välit): vasen keittiöön, oikea saunaan.
const BACK := -5.2
const KITCHEN_V0 := -1.95
const KIUAS := Vector2(0.3, -2.33)  # kiukaan keskipiste (piippu sen yllä)
const DOOR_KITCHEN := [0.0, 0.8]
const DOOR_SAUNA := [-3.15, -2.35]
const CUT_MARGIN := 2.9  # kaivanto ulottuu näin kauas terassin reunasta (2 m korkeusruudun lävistäjä)

## Sävyt (sRGB valokuvista).
const WALL := Color(0.56, 0.61, 0.69)
const WALL_UP := Color(0.5, 0.56, 0.66)
const TRIM := Color(0.94, 0.94, 0.92)
const ROOF := Color(0.16, 0.16, 0.17)
const DECK := Color(0.66, 0.62, 0.56)
const STAIR := Color(0.8, 0.8, 0.78)
const DARK := Color(0.12, 0.12, 0.13)

static var orig: Terrain.Grid  # maasto ennen kaivamista
static var _floor_y := NAN

## AI:n reittipisteet: nimi -> maailman paikka; linkit nimipareina.
var points := {}
var links := []
## Istumapaikat penkeillä: [paikka, piste jota kohti istutaan].
var seats := []
## Paikat, joista katsellaan auringonlaskua (laituri, etuterassi), maailman pisteinä.
var views := []
## Sisätilat maailman pisteinä: lauteiden istumapaikat ja keittiön pöydän neljä paikkaa [paikka, katse],
## kokin paikka hellan edessä, pannu, pöydän lettulautanen ja kiukaan kivet.
var sauna_seats := []
var table_seats := []
var table_paths := []  # pöydän paikoille kävely keittiön ovelta
var cook_spot := Vector3.ZERO
var cook_face := Vector3.ZERO
var pan_pos := Vector3.ZERO
var plate_pos := Vector3.ZERO
var kiuas_pos := Vector3.ZERO
var card_frame := Transform3D()  # keittiön pöydän keskikohta: x pitkin pöytää (itään), -z järvelle
var stash_pos := Vector3.ZERO  # olut- ja viinakätkö saunan takana
var bodies: Array = []  # mökkiläiset (main.gd): istumapaikan varaus katsotaan heidän paikoistaan


## Vapaa istumapaikka (indeksi) listasta: kukaan muu ei istu tai seiso siinä eikä ole menossa siihen
## (claimed_seat). Jos near on annettu, lähin vapaa paikka, muuten satunnainen. -1 = kaikki varattuja.
func free_seat(list: Array, me: Node3D, near := Vector3.INF) -> int:
	var free := []
	for i in list.size():
		var q: Vector3 = list[i][0]
		var ok := true
		for b in bodies:
			if b == me or b.hidden_inside:
				continue
			if Vector2(b.global_position.x - q.x, b.global_position.z - q.z).length() < 0.35 \
					and absf(b.global_position.y - q.y) < 0.8:
				ok = false
			if b.claimed_seat.distance_to(q) < 0.05:
				ok = false
		if ok:
			free.append(i)
	if free.is_empty():
		return -1
	if near == Vector3.INF:
		return free[randi() % free.size()]
	var best: int = free[0]
	for i: int in free:
		if (list[i][0] as Vector3).distance_to(near) < (list[best][0] as Vector3).distance_to(near):
			best = i
	return best
var lamps: Array[OmniLight3D] = []
var _mat: ShaderMaterial


# --- Kehykset ja maasto ---------------------------------------------------------------------------------------

static func yw(u: float, v: float) -> Vector2:
	return C + EAST * u + LAKE * v


static func wy(p: Vector2) -> Vector2:
	var d := p - C
	return Vector2(d.dot(EAST), d.dot(LAKE))


static func cw(x: float, v: float) -> Vector2:
	return CABIN_C + CABIN_X * x + CABIN_LAKE * v


static func wc(p: Vector2) -> Vector2:
	var d := p - CABIN_C
	return Vector2(d.dot(CABIN_X), d.dot(CABIN_LAKE))


static func oh(p: Vector2) -> float:
	return orig.h(p.x, p.y) if orig != null else Terrain.h(p.x, p.y)


## Ylämökin lattian korkeus: alkuperäisen maan korkein kohta pohjan alla + 0,3 m.
static func floor_y() -> float:
	if is_nan(_floor_y):
		var m := -INF
		for sx: float in [-1.0, 0.0, 1.0]:
			for sv: float in [-1.0, 0.0, 1.0]:
				m = maxf(m, oh(cw(sx * CABIN_HX, sv * CABIN_HV)))
		_floor_y = m + 0.3
	return _floor_y


## Portaiden ala- ja yläpää (maailman xz): pääterassilta ylämökin terassin järven puoleiseen reunaan.
static func stair_ends() -> Array:
	return [yw(-6.0, -2.2), cw(4.1, 2.5)]


static func in_rect(q: Vector2, r: Array, m := 0.0) -> bool:
	return q.x >= r[0] - m and q.x <= r[1] + m and q.y >= r[2] - m and q.y <= r[3] + m


static func in_decks(q: Vector2, m := 0.0) -> bool:
	for r in DECKS:
		if in_rect(q, r, m):
			return true
	return false


## Etäisyys lähimpään terassiin (0 sisällä), pihan kehyksessä.
## Alamökin huone pihan kehyksen pisteessä: keittio, loylyhuone tai "".
static func room_at(p: Vector3) -> String:
	var q := wy(Vector2(p.x, p.z))
	if q.x < -1.72 or q.x > 1.72 or q.y < BACK + 0.18 or q.y > 0.92 or p.y > DY + 2.0 or p.y < DY - 0.6:
		return ""
	return "keittio" if q.y > KITCHEN_V0 - 0.05 else "loylyhuone"


static func deck_dist(q: Vector2) -> float:
	var best := INF
	for r in DECKS:
		var dx := maxf(maxf(r[0] - q.x, q.x - r[1]), 0.0)
		var dv := maxf(maxf(r[2] - q.y, q.y - r[3]), 0.0)
		best = minf(best, Vector2(dx, dv).length())
	return best


## Portaiden paikalliset koordinaatit maailman pisteelle: (sivuttain, matka alapäästä).
static func stair_local(p: Vector2) -> Vector2:
	var e := stair_ends()
	var d: Vector2 = (e[1] - e[0]).normalized()
	var q: Vector2 = p - e[0]
	return Vector2(q.dot(Vector2(-d.y, d.x)), q.dot(d))


static func in_stairs(p: Vector2, m := 0.0) -> bool:
	var e := stair_ends()
	var s := stair_local(p)
	return absf(s.x) <= STAIR_W * 0.5 + 0.1 + m and s.y >= -m and s.y <= (e[1] - e[0]).length() + m


static func stair_y(p: Vector2) -> float:
	var e := stair_ends()
	var t := clampf(stair_local(p).y / (e[1] - e[0]).length(), 0.0, 1.0)
	return lerpf(DY, floor_y(), t)


## Kaivaa terassin ja portaiden kohdat maastosta (ennen kuin world.gd rakentaa maaston ja törmäyksen).
static func terraform() -> void:
	var g := Terrain.near
	if g == null or orig != null:
		return
	orig = Terrain.Grid.new()
	orig.n = g.n
	orig.step = g.step
	orig.half = g.half
	orig.heights = g.heights.duplicate()
	orig.classes = g.classes
	var hs := g.heights
	for j in g.n:
		var z := -g.half + j * g.step
		if z < -24.0 or z > 18.0:
			continue
		for i in g.n:
			var x := -g.half + i * g.step
			if x < -26.0 or x > 16.0:
				continue
			var p := Vector2(x, z)
			var k := j * g.n + i
			var h := hs[k]
			if deck_dist(wy(p)) < CUT_MARGIN:
				h = minf(h, DY - 0.35)
			if in_stairs(p, 1.8):
				h = minf(h, stair_y(p) - 0.45)
			hs[k] = h
	g.heights = hs


## Puut pois rakennusten, terassien, portaiden ja laiturin kohdalta.
static func clears_tree(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	var q := wy(p)
	if in_decks(q, 0.6) or in_stairs(p, 0.6):
		return true
	if in_rect(q, [-3.4, -1.0, 4.0, 14.2]):  # laituri
		return true
	var c := wc(p)
	return in_rect(c, [-CABIN_HX - 0.8, 5.3, -CABIN_HV - 0.8, CABIN_HV + 0.8])


# --- Rakentaminen ---------------------------------------------------------------------------------------------

## Yksi kehys: solmu, yhdistetty mesh (Batch) ja törmäysmuodot. Paikalliset pisteet p(x, v, y) = (x, y, -v).
class Part:
	const B := preload("res://scripts/build.gd")
	var node := Node3D.new()
	var bt := B.Batch.new()
	var body := StaticBody3D.new()
	var o2 := Vector2.ZERO
	var x2 := Vector2.RIGHT
	var f2 := Vector2.UP

	func _init(parent: Node3D, origin: Vector2, front: Vector2) -> void:
		o2 = origin
		f2 = front.normalized()
		var z := Vector3(-f2.x, 0, -f2.y)
		var x := Vector3.UP.cross(z)
		x2 = Vector2(x.x, x.z)
		node.transform = Transform3D(Basis(x, Vector3.UP, z), Vector3(origin.x, 0, origin.y))
		parent.add_child(node)
		body.set_meta("puu", true)
		node.add_child(body)

	func w2(x: float, v: float) -> Vector2:
		return o2 + x2 * x + f2 * v

	static func p(x: float, v: float, y: float) -> Vector3:
		return Vector3(x, y, -v)

	## Laatikko rajojen mukaan (x, v, y); solid = törmää. Täysin läpinäkyvä väri = pelkkä törmäys.
	func bx(x0: float, x1: float, v0: float, v1: float, y0: float, y1: float, col: Color, solid := false) -> void:
		var size := Vector3(absf(x1 - x0), absf(y1 - y0), absf(v1 - v0))
		var c := p((x0 + x1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5)
		if col.a > 0.0:
			bt.add(B.boxm(size), Transform3D(Basis(), c), col)
		if solid:
			body.add_child(B.box_shape(size, c))

	## Laatikko keskipisteen, koon ja kierron mukaan (paikallinen avaruus).
	func box(size: Vector3, center: Vector3, col: Color, basis := Basis(), solid := false) -> void:
		if col.a > 0.0:
			bt.add(B.boxm(size), Transform3D(basis, center), col)
		if solid:
			var cs := B.box_shape(size)
			cs.transform = Transform3D(basis, center)
			body.add_child(cs)

	## Palkki kahden pisteen välille (neliöprofiili w x h, h pystysuunnassa).
	func beam(a: Vector3, b: Vector3, w: float, h: float, col: Color, solid := false) -> void:
		var d := b - a
		var fwd := d.normalized()
		var side := Vector3.UP.cross(fwd)
		if side.length() < 0.01:
			side = Vector3.RIGHT
		side = side.normalized()
		var up := fwd.cross(side)
		box(Vector3(w, h, d.length()), (a + b) * 0.5, col, Basis(side, up, fwd), solid)

	func cyl(a: Vector3, b: Vector3, r: float, col: Color, seg := 8) -> void:
		var d := b - a
		var basis := Basis()
		var dir := d.normalized()
		if absf(dir.dot(Vector3.UP)) < 0.999:
			var axis := Vector3.UP.cross(dir).normalized()
			basis = Basis(axis, Vector3.UP.angle_to(dir))
		elif dir.y < 0.0:
			basis = Basis(Vector3.RIGHT, PI)
		bt.add(B.cyl(r, r, d.length(), seg), Transform3D(basis, (a + b) * 0.5), col)

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
		var nrm := (b - a).cross(c - a).normalized()
		var base := bt.verts.size()
		for v in [a, b, c]:
			bt.verts.append(v)
			bt.norms.append(nrm)
			bt.cols.append(col)
			bt.uvs.append(Vector2.ZERO)
		bt.idx.append_array([base, base + 1, base + 2])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
		tri(a, b, c, col)
		tri(a, c, d, col)

	func faces(f: PackedVector3Array) -> void:
		if f.is_empty():
			return
		var sh := ConcavePolygonShape3D.new()
		sh.set_faces(f)
		sh.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = sh
		body.add_child(cs)

	func finish(mat: Material) -> void:
		if bt.is_empty():
			return
		var mi := MeshInstance3D.new()
		mi.mesh = bt.commit()
		mi.material_override = mat
		node.add_child(mi)


func _ready() -> void:
	_mat = B.shader_mat("res://shaders/mokki.gdshader")
	var yard := Part.new(self, C, LAKE)
	_decks(yard)
	_sauna(yard)
	_woodshed(yard)
	_gazebo(yard)
	_tent(yard)
	_outhouse(yard)
	_dock(yard)
	_bank_cover(yard)
	yard.finish(_mat)
	var e := stair_ends()
	var st := Part.new(self, e[0], (e[1] - e[0]).normalized())
	_stairs(st, (e[1] - e[0]).length())
	st.finish(_mat)
	var cab := Part.new(self, CABIN_C, CABIN_LAKE)
	_cabin(cab)
	cab.finish(_mat)
	var shore := Part.new(self, Vector2.ZERO, Vector2(0, -1))
	_shore(shore)
	shore.finish(_mat)
	_waypoints()


## Iltavalot päälle hämärässä (0..1).
func set_lamp(k: float) -> void:
	_mat.set_shader_parameter("lamp", k)
	for l in lamps:
		l.visible = k > 0.02
		l.light_energy = l.get_meta("energy", 1.0) * k


func _lamp(part: Part, pos: Vector3, energy: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = Color(1.0, 0.72, 0.42)
	l.omni_range = rng
	l.set_meta("energy", energy)
	l.shadow_enabled = false
	l.visible = false
	part.node.add_child(l)
	lamps.append(l)


# --- Ikkunat, ovet ja hirsikulmat -----------------------------------------------------------------------------

## Ikkuna seinään, jonka ulkopinta on tasossa v = v_face (out = +1 ulospäin +v, -1 ulospäin -v),
## leveys x0..x1 ja korkeus y0..y1. lit = sisällä valo illalla.
func _window_v(pt: Part, x0: float, x1: float, v_face: float, out: float, y0: float, y1: float, lit := false) -> void:
	var t := 0.06
	var vf := v_face + out * 0.02
	pt.bx(x0, x1, v_face - out * 0.05, vf, y0, y1, Color(0.1, 0.12, 0.14, WINDOW if lit else GLASS))
	for k in [[x0 - t, x0, y0 - t, y1 + t], [x1, x1 + t, y0 - t, y1 + t], [x0, x1, y0 - t, y0], [x0, x1, y1, y1 + t]]:
		pt.bx(k[0], k[1], v_face, vf + out * 0.03, k[2], k[3], TRIM)
	pt.bx((x0 + x1) * 0.5 - 0.025, (x0 + x1) * 0.5 + 0.025, v_face, vf + out * 0.025, y0, y1, TRIM)
	pt.bx(x0 - 0.1, x1 + 0.1, v_face, vf + out * 0.08, y0 - t - 0.04, y0 - t, TRIM)  # vesipelti


## Ikkuna seinään x = x_face (sivuseinät), leveys v0..v1.
func _window_x(pt: Part, v0: float, v1: float, x_face: float, out: float, y0: float, y1: float, lit := false) -> void:
	var t := 0.06
	var xf := x_face + out * 0.02
	pt.bx(x_face - out * 0.05, xf, v0, v1, y0, y1, Color(0.1, 0.12, 0.14, WINDOW if lit else GLASS))
	for k in [[v0 - t, v0, y0 - t, y1 + t], [v1, v1 + t, y0 - t, y1 + t], [v0, v1, y0 - t, y0], [v0, v1, y1, y1 + t]]:
		pt.bx(x_face, xf + out * 0.03, k[0], k[1], k[2], k[3], TRIM)
	pt.bx(x_face, xf + out * 0.025, (v0 + v1) * 0.5 - 0.025, (v0 + v1) * 0.5 + 0.025, y0, y1, TRIM)


## Hirsiseinä v-suunnassa (seinä tasossa x, paksuus 0.18) aukkoineen: holes = [[v0, v1, y0, y1], ...].
func _log_wall_x(pt: Part, x0: float, x1: float, v0: float, v1: float, y0: float, y1: float, col: Color,
		holes := []) -> void:
	_log_wall(pt, true, x0, x1, v0, v1, y0, y1, col, holes)


func _log_wall_v(pt: Part, x0: float, x1: float, v0: float, v1: float, y0: float, y1: float, col: Color,
		holes := []) -> void:
	_log_wall(pt, false, x0, x1, v0, v1, y0, y1, col, holes)


## Seinä paloiksi aukkojen ympäriltä. along_v: seinä kulkee v-suunnassa (aukot v-väleinä), muuten x-suunnassa.
func _log_wall(pt: Part, along_v: bool, x0: float, x1: float, v0: float, v1: float, y0: float, y1: float,
		col: Color, holes: Array, alpha := LOG, solid := true) -> void:
	var a0 := v0 if along_v else x0
	var a1 := v1 if along_v else x1
	var cuts := [a0]
	var hs := holes.duplicate()
	hs.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var lc := Color(col.r, col.g, col.b, alpha)
	var put := func(s0: float, s1: float, h0: float, h1: float) -> void:
		if s1 - s0 < 0.005 or h1 - h0 < 0.005:
			return
		if along_v:
			pt.bx(x0, x1, s0, s1, h0, h1, lc, solid)
		else:
			pt.bx(s0, s1, v0, v1, h0, h1, lc, solid)
	var s := a0
	for h in hs:
		put.call(s, h[0], y0, y1)
		put.call(h[0], h[1], y0, h[2])
		put.call(h[0], h[1], h[3], y1)
		s = h[1]
	put.call(s, a1, y0, y1)


## Hirsikulmat: ulkonevat hirrenpäät nurkissa.
func _log_corners(pt: Part, x0: float, x1: float, v0: float, v1: float, y0: float, y1: float, col: Color) -> void:
	var lc := Color(col.r * 0.92, col.g * 0.92, col.b * 0.92, LOG)
	for cx: float in [x0, x1]:
		for cv: float in [v0, v1]:
			pt.bx(cx - 0.17, cx + 0.17, cv - 0.17, cv + 0.17, y0, y1, lc)


## Kaide: pylväät ja kaksi johdetta pisteiden a -> b välillä (lattiatasolla y), törmää.
func _railing(pt: Part, a: Vector2, b: Vector2, y: float, col := STAIR) -> void:
	var d := a.distance_to(b)
	var n := maxi(1, int(ceil(d / 1.4)))
	for k in n + 1:
		var q := a.lerp(b, float(k) / n)
		pt.bx(q.x - 0.05, q.x + 0.05, q.y - 0.05, q.y + 0.05, y, y + 1.0, col)
	var pa := Part.p(a.x, a.y, y)
	var pb := Part.p(b.x, b.y, y)
	pt.beam(pa + Vector3.UP * 0.98, pb + Vector3.UP * 0.98, 0.14, 0.04, col)
	pt.beam(pa + Vector3.UP * 0.55, pb + Vector3.UP * 0.55, 0.035, 0.1, col)
	pt.beam(pa + Vector3.UP * 0.2, pb + Vector3.UP * 0.2, 0.035, 0.1, col)
	pt.beam(pa + Vector3.UP * 0.5, pb + Vector3.UP * 0.5, 0.08, 1.0, Color(0, 0, 0, 0), true)


## Portaat (askelmat, umpinaiset nousut, sivupalkit ja ramppi törmäykseen) suunnassa +v kehyksen sisällä:
## alapää (x, v0, y0) -> yläpää (x, v1, y1). Kaiteet sivuille halutessa.
func _steps(pt: Part, xc: float, w: float, v0: float, v1: float, y0: float, y1: float, rails: bool,
		col := STAIR, support := true) -> void:
	var rise := y1 - y0
	var run := v1 - v0
	var n := maxi(1, int(round(absf(rise) / 0.185)))
	var tr := run / n
	var rs := rise / n
	var bc := Color(col.r, col.g, col.b, BOARD_U)
	for k in n:
		var ty := y0 + rs * (k + 1)
		pt.bx(xc - w * 0.5, xc + w * 0.5, v0 + tr * k - 0.02, v0 + tr * (k + 1) + 0.02, ty - 0.045, ty, bc)
		pt.bx(xc - w * 0.5 + 0.03, xc + w * 0.5 - 0.03, v0 + tr * k, v0 + tr * k + 0.03, ty - rs, ty - 0.04,
			col.darkened(0.08))
	for sx: float in [xc - w * 0.5 - 0.03, xc + w * 0.5 + 0.03]:
		pt.beam(Part.p(sx, v0, y0 - 0.1), Part.p(sx, v1, y1 - 0.1), 0.05, 0.3, col)
		if rails:
			var a := Part.p(sx, v0 + tr * 0.5, y0 + rs)
			var b := Part.p(sx, v1 - tr * 0.5, y1)
			var nn := maxi(1, int(ceil(a.distance_to(b) / 1.3)))
			for k in nn + 1:
				var q := a.lerp(b, float(k) / nn)
				pt.box(Vector3(0.07, 0.95, 0.07), q + Vector3.UP * 0.47, col)
			pt.beam(a + Vector3.UP * 0.93, b + Vector3.UP * 0.93, 0.1, 0.04, col)
			pt.beam(a + Vector3.UP * 0.5, b + Vector3.UP * 0.5, 0.03, 0.09, col)
			pt.beam(a + Vector3.UP * 0.5, b + Vector3.UP * 0.5, 0.08, 1.0, Color(0, 0, 0, 0), true)
	if support:
		for k in range(1, int(run / 1.6) + 1):
			var v := v0 + k * 1.6
			var y := y0 + rise * (v - v0) / run - 0.15
			for sx: float in [xc - w * 0.5, xc + w * 0.5]:
				var g := Terrain.h(pt.w2(sx, v).x, pt.w2(sx, v).y)
				if y - g > 0.2:
					pt.bx(sx - 0.05, sx + 0.05, v - 0.05, v + 0.05, g - 0.2, y, col.darkened(0.15))
	# Törmäys: ramppi askelmien etureunojen kautta.
	var a := Part.p(xc, v0, y0)
	var b := Part.p(xc, v1, y1)
	var length := a.distance_to(b)
	var fwd := (b - a).normalized()
	var side := Vector3.RIGHT
	var up := (-fwd).cross(side).normalized()
	var basis := Basis(side, up, -fwd)
	var cs := B.box_shape(Vector3(w, 0.2, length + 0.1))
	cs.transform = Transform3D(basis, (a + b) * 0.5 - up * 0.1)
	pt.body.add_child(cs)


# --- Terassit -------------------------------------------------------------------------------------------------

func _decks(pt: Part) -> void:
	var dc := Color(DECK.r, DECK.g, DECK.b, BOARD_U)
	var dcv := Color(DECK.r, DECK.g, DECK.b, BOARD_V)
	# Lattiapinnat (ei päällekkäin): pääterassi, etuterassi, huussin terassi, halkovaja.
	pt.bx(-10.8, -1.9, -3.2, 2.0, DY - 0.05, DY, dc)
	pt.bx(-3.4, -1.9, 2.0, 2.9, DY - 0.05, DY, dcv)
	pt.bx(-3.4, 2.2, 2.9, 4.3, DY - 0.05, DY, dc)
	pt.bx(2.2, 5.4, -0.8, 4.3, DY - 0.05, DY, dcv)
	pt.bx(1.9, 3.2, -2.9, -0.8, DY - 0.05, DY, dcv)
	for r in DECKS:
		pt.bx(r[0], r[1], r[2], r[3], DY - 0.35, DY - 0.05, Color(0, 0, 0, 0), true)
	# Reunalaudat ja tolpat maahan asti, missä maa on matalammalla.
	for r in DECKS:
		for e in [[r[0], r[2], r[1], r[2]], [r[1], r[2], r[1], r[3]], [r[1], r[3], r[0], r[3]], [r[0], r[3], r[0], r[2]]]:
			var a := Vector2(e[0], e[1])
			var b := Vector2(e[2], e[3])
			var nrm := (b - a).normalized().orthogonal()
			var n := maxi(1, int(a.distance_to(b) / 0.5))
			for k in n:
				var q0 := a.lerp(b, float(k) / n)
				var q1 := a.lerp(b, float(k + 1) / n)
				var mid := (q0 + q1) * 0.5
				if in_decks(mid + nrm * 0.1) and in_decks(mid - nrm * 0.1):
					continue
				var g0 := Terrain.h(yw(q0.x, q0.y).x, yw(q0.x, q0.y).y)
				var g1 := Terrain.h(yw(q1.x, q1.y).x, yw(q1.x, q1.y).y)
				if minf(g0, g1) < DY - 0.12:
					pt.quad(Part.p(q0.x, q0.y, DY - 0.02), Part.p(q1.x, q1.y, DY - 0.02),
						Part.p(q1.x, q1.y, minf(g1, DY) - 0.1), Part.p(q0.x, q0.y, minf(g0, DY) - 0.1),
						Color(DECK.r * 0.8, DECK.g * 0.8, DECK.b * 0.8, BOARD_V if absf(b.x - a.x) > 0.01 else BOARD_U))
	# Kaiteet: pääterassin järven puoli (aukko rantaportaille), etuterassi (aukko laiturin portaille), huussin terassi.
	_railing(pt, Vector2(-10.8, -3.2), Vector2(-10.8, 2.0), DY)
	_railing(pt, Vector2(-10.8, 2.0), Vector2(-8.6, 2.0), DY)
	_railing(pt, Vector2(-7.4, 2.0), Vector2(-3.4, 2.0), DY)
	_railing(pt, Vector2(-3.4, 2.0), Vector2(-3.4, 4.3), DY)
	_railing(pt, Vector2(-3.4, 4.3), Vector2(-2.85, 4.3), DY)
	_railing(pt, Vector2(-1.55, 4.3), Vector2(5.4, 4.3), DY)
	_railing(pt, Vector2(5.4, 4.3), Vector2(5.4, -0.8), DY)
	_railing(pt, Vector2(5.4, -0.8), Vector2(3.2, -0.8), DY)
	# Rantaportaat pääterassilta hiekkarantaan ja portaat etuterassilta laiturille.
	var beach := Terrain.h(yw(-8.0, 3.8).x, yw(-8.0, 3.8).y)
	_steps(pt, -8.0, 1.15, 3.7, 2.0, beach, DY, false)
	_steps(pt, -2.2, 1.2, 5.9, 4.3, 0.42, DY, true)


## Kaivannon peite: alkuperäisen maanpinnan mukainen sammal- ja kivipinta terassin ympärillä sekä kivimuuri
## terassin takareunaan, törmäyksineen.
func _bank_cover(pt: Part) -> void:
	var f := PackedVector3Array()
	var step := 0.25
	var u := -14.5
	while u < 9.0:
		var v := -10.5
		while v < 7.5:
			var c := Vector2(u + step * 0.5, v + step * 0.5)
			var cw2 := yw(c.x, c.y)
			if not in_decks(c) and not in_stairs(cw2, 0.05) and deck_dist(c) < CUT_MARGIN + 3.2:
				var corners := [Vector2(u, v), Vector2(u + step, v), Vector2(u + step, v + step), Vector2(u, v + step)]
				var changed := false
				var ps := []
				for q: Vector2 in corners:
					var w := yw(q.x, q.y)
					var h0 := oh(w)
					if h0 - Terrain.h(w.x, w.y) > 0.01:
						changed = true
					var qq := _snap_out(q)
					var ww := yw(qq.x, qq.y)
					ps.append(Part.p(qq.x, qq.y, oh(ww) + 0.03))
				if changed:
					var col := Color(0.5, 0.48, 0.45, STONE) if deck_dist(c) < 0.9 else Color(1, 1, 1, GROUND)
					pt.quad(ps[0], ps[3], ps[2], ps[1], col)
					f.append_array([ps[0], ps[3], ps[2], ps[0], ps[2], ps[1]])
			v += step
		u += step
	# Kivimuuri terassin reunoihin, joissa alkuperäinen maa on terassia korkeammalla.
	for r in DECKS:
		for e in [[r[0], r[2], r[1], r[2]], [r[1], r[2], r[1], r[3]], [r[1], r[3], r[0], r[3]], [r[0], r[3], r[0], r[2]]]:
			var a := Vector2(e[0], e[1])
			var b := Vector2(e[2], e[3])
			var nrm := -(b - a).normalized().orthogonal()
			var n := maxi(1, int(a.distance_to(b) / 0.25))
			for k in n:
				var q0 := a.lerp(b, float(k) / n)
				var q1 := a.lerp(b, float(k + 1) / n)
				var mid := (q0 + q1) * 0.5
				if in_decks(mid + nrm * 0.08) == in_decks(mid - nrm * 0.08):
					continue
				var h0 := oh(yw(q0.x, q0.y)) + 0.03
				var h1 := oh(yw(q1.x, q1.y)) + 0.03
				if maxf(h0, h1) < DY - 0.05:
					continue
				var t0 := maxf(h0, DY)
				var t1 := maxf(h1, DY)
				var a3 := Part.p(q0.x, q0.y, DY - 0.4)
				var b3 := Part.p(q1.x, q1.y, DY - 0.4)
				var c3 := Part.p(q1.x, q1.y, t1)
				var d3 := Part.p(q0.x, q0.y, t0)
				pt.quad(a3, b3, c3, d3, Color(0.52, 0.5, 0.47, STONE))
				f.append_array([a3, b3, c3, a3, c3, d3])
	pt.faces(f)


## Terassin sisällä oleva piste siirretään lähimmälle terassin reunalle (kaivannon peitteen reuna).
static func _snap_out(q: Vector2) -> Vector2:
	for r in DECKS:
		if in_rect(q, r):
			var opts := [Vector2(r[0], q.y), Vector2(r[1], q.y), Vector2(q.x, r[2]), Vector2(q.x, r[3])]
			var best: Vector2 = opts[0]
			for o: Vector2 in opts:
				if o.distance_to(q) < best.distance_to(q) and not _inside_other(o, r):
					best = o
			return best
	return q


static func _inside_other(q: Vector2, skip: Array) -> bool:
	for r in DECKS:
		if r != skip and in_rect(q, r, -0.01):
			return true
	return false


# --- Alamökki: rantasauna -------------------------------------------------------------------------------------

func _sauna(pt: Part) -> void:
	var y0 := DY
	var eave := DY + 2.25
	var pitch := deg_to_rad(17.0)
	var ridge := eave + 1.9 * tan(pitch)
	# Perustus: kivijalka maasta lattiaan.
	var g := INF
	for q: Vector2 in [Vector2(-1.9, BACK), Vector2(1.9, BACK), Vector2(-1.9, 2.9), Vector2(1.9, 2.9)]:
		g = minf(g, Terrain.h(yw(q.x, q.y).x, yw(q.x, q.y).y))
	pt.bx(-1.85, 1.85, BACK + 0.05, 1.05, g - 0.3, y0 - 0.05, Color(0.45, 0.44, 0.42, STONE))
	pt.bx(-1.9, 2.2, 1.1, 2.9, y0 - 0.05, y0, Color(DECK.r, DECK.g, DECK.b, BOARD_V))  # kuistin lattia
	# Hirsiseinät: takaseinä, itäseinä, terassin puoleinen länsiseinä kahdella ovella (vasen keittiöön, oikea
	# saunaan) ja kuistin seinä, jossa keittiön ikkuna järvelle.
	_log_wall_v(pt, -1.9, 1.9, BACK, BACK + 0.18, y0, eave, WALL)
	_log_wall_x(pt, -1.9, -1.72, BACK + 0.18, 0.92, y0, eave, WALL, [DOOR_KITCHEN + [y0, y0 + 1.95],
		DOOR_SAUNA + [y0, y0 + 1.95]])
	_log_wall_x(pt, 1.72, 1.9, BACK + 0.18, 0.92, y0, eave, WALL)
	_log_wall_v(pt, -1.9, 1.9, 0.92, 1.1, y0, eave, WALL, [[-0.2, 0.8, y0 + 0.85, y0 + 1.55]])
	_log_corners(pt, -1.81, 1.81, BACK + 0.09, 1.01, y0, eave, WALL)
	_window_v(pt, -0.2, 0.8, 1.1, 1.0, y0 + 0.85, y0 + 1.55, true)
	_pane(pt, Part.p(0.3, 1.01, y0 + 1.2), Vector3(1.0, 0.7, 0.02))
	# Ovet auki terassia vasten: valkoiset, keittiön ovessa iso ikkuna, saunan ovessa kapea.
	for d in [[DOOR_KITCHEN, 1.0, 0.55], [DOOR_SAUNA, -1.0, 0.25]]:
		var dv: Array = d[0]
		var v0: float = dv[0]
		var v1: float = dv[1]
		for k in [[v0 - 0.08, v0], [v1, v1 + 0.08]]:
			pt.bx(-1.98, -1.9, k[0], k[1], y0, y0 + 2.03, TRIM)
		pt.bx(-1.98, -1.9, v0 - 0.08, v1 + 0.08, y0 + 1.95, y0 + 2.03, TRIM)
		pt.bx(-1.72, -1.9, v0, v1, y0 - 0.05, y0 + 0.01, Color(DECK.r, DECK.g, DECK.b, BOARD_V))  # kynnys
		# Ovilehti saranoiltaan seinän suuntaisesti auki (hinge = toinen reuna).
		var hinge: float = v0 if d[1] > 0.0 else v1
		var leaf: float = (v1 - v0) * -float(d[1])
		var a := minf(hinge, hinge + leaf)
		var b := maxf(hinge, hinge + leaf)
		var xo := -2.04 if d[1] > 0.0 else -2.0
		pt.bx(xo - 0.04, xo, a, b, y0 + 0.02, y0 + 1.93, Color(0.95, 0.95, 0.93, BOARD_V))
		var gw: float = d[2]
		pt.bx(xo - 0.05, xo + 0.01, (a + b) * 0.5 - gw * 0.5, (a + b) * 0.5 + gw * 0.5, y0 + 0.9, y0 + 1.75,
			Color(0.3, 0.2, 0.1, WINDOW))
		var hv := a + 0.1 if d[1] > 0.0 else b - 0.1  # kahva vapaassa reunassa
		pt.bx(xo - 0.09, xo - 0.04, hv - 0.025, hv + 0.025, y0 + 0.95, y0 + 1.0, Color(0.3, 0.3, 0.32, METAL))
	_interior(pt)
	_stash(pt)
	# Kuistin pylväät (valkoiset, pyöreät) ja otsapalkki.
	for x: float in [-1.75, 1.75]:
		pt.cyl(Part.p(x, 2.75, y0), Part.p(x, 2.75, eave - 0.05), 0.07, TRIM)
		pt.body.add_child(B.box_shape(Vector3(0.14, eave - y0, 0.14), Part.p(x, 2.75, (y0 + eave) * 0.5)))
		# Lyhty pylväässä.
		pt.bx(x - 0.09 * signf(x), x - 0.27 * signf(x), 2.68, 2.82, y0 + 1.55, y0 + 1.85, Color(0.05, 0.05, 0.05, METAL))
		pt.bx(x - 0.11 * signf(x), x - 0.25 * signf(x), 2.7, 2.8, y0 + 1.58, y0 + 1.8, Color(1, 0.9, 0.7, LAMP))
		_lamp(pt, Part.p(x - 0.18 * signf(x), 2.75, y0 + 1.7), 0.8, 6.0)
	pt.bx(-1.9, 1.9, 2.7, 2.85, eave - 0.2, eave, TRIM)
	# Katto: matala harja pitkittäin (v), räystäät 0,45 m, kuistin päällä 0,4 m yli. Terassin puolella katto
	# jatkuu ovien yli 1,25 m ja nojaa palkkiin ja pyöreään pylvääseen.
	var vb := BACK - 0.4
	var vf := 3.3
	var rc := Color(ROOF.r, ROOF.g, ROOF.b, SHINGLE)
	var wx := 3.15
	var wy_ := eave - (wx - 1.9) * tan(pitch)
	pt.beam(Part.p(-3.0, vb + 0.3, wy_ - 0.2), Part.p(-3.0, vf - 0.55, wy_ - 0.2), 0.12, 0.14, TRIM)
	for pv: float in [-0.75, -3.1]:
		pt.cyl(Part.p(-3.0, pv, y0), Part.p(-3.0, pv, wy_ - 0.27), 0.07, TRIM)
		pt.body.add_child(B.box_shape(Vector3(0.14, wy_ - y0, 0.14), Part.p(-3.0, pv, (y0 + wy_) * 0.5)))
	for s: float in [-1.0, 1.0]:
		var ex := wx if s < 0.0 else 2.35
		var ey := eave - (ex - 1.9) * tan(pitch)
		var a := Part.p(s * ex, vb, ey)
		var b := Part.p(0, vb, ridge)
		var c := Part.p(0, vf, ridge)
		var d := Part.p(s * ex, vf, ey)
		pt.quad(a, b, c, d, rc)
		pt.quad(a + Vector3.DOWN * 0.08, b + Vector3.DOWN * 0.08, c + Vector3.DOWN * 0.08, d + Vector3.DOWN * 0.08,
			Color(0.85, 0.85, 0.83, BOARD_U))  # valkoinen räystään alapinta
		# Otsalaudat ja räystäskouru.
		pt.beam(Part.p(s * (ex + 0.02), vb, ey - 0.06), Part.p(s * (ex + 0.02), vf, ey - 0.06), 0.04, 0.18, TRIM)
		pt.beam(Part.p(s * (ex + 0.1), vb, ey - 0.16), Part.p(s * (ex + 0.1), vf, ey - 0.16), 0.13, 0.11, TRIM)
		for vv: float in [vb, vf]:
			pt.beam(Part.p(s * ex, vv, ey - 0.02), Part.p(0, vv, ridge - 0.02), 0.04, 0.2, TRIM)
	# Päätykolmiot: takana hirttä, kuistin päällä valkoista laudoitusta.
	pt.tri(Part.p(-1.9, BACK, eave), Part.p(1.9, BACK, eave), Part.p(0, BACK, ridge - 0.04), Color(WALL.r, WALL.g, WALL.b, LOG))
	pt.tri(Part.p(-1.9, 2.85, eave), Part.p(1.9, 2.85, eave), Part.p(0, 2.85, ridge - 0.04), Color(0.9, 0.9, 0.88, BOARD_V))
	pt.bx(-1.9, 1.9, BACK, 1.1, eave - 0.02, eave, Color(0.8, 0.78, 0.74, BOARD_U), true)  # sisäkatto
	# Piippu (musta) kiukaan yllä, hattu ja kipinäsuoja; tuuletusputki.
	var kq := KIUAS
	var ky := ridge - kq.x * tan(pitch)  # katon pinta piipun kohdalla
	pt.bx(kq.x - 0.2, kq.x + 0.2, kq.y - 0.2, kq.y + 0.2, eave, ky + 0.85, Color(0.1, 0.1, 0.11, PLAIN))
	pt.bx(kq.x - 0.25, kq.x + 0.25, kq.y - 0.25, kq.y + 0.25, ky + 0.85, ky + 0.9, Color(0.2, 0.2, 0.21, METAL))
	for k in 4:
		var x := kq.x - 0.23 + (k % 2) * 0.44
		var v := kq.y - 0.23 + (k / 2) * 0.44
		pt.bx(x, x + 0.03, v, v + 0.03, ky + 0.9, ky + 1.15, Color(0.2, 0.2, 0.21, METAL))
	pt.bx(kq.x - 0.25, kq.x + 0.25, kq.y - 0.25, kq.y + 0.25, ky + 1.13, ky + 1.16, Color(0.2, 0.2, 0.21, METAL))
	pt.cyl(Part.p(-0.7, 0.4, ridge - 0.25), Part.p(-0.7, 0.4, ridge + 0.15), 0.06, Color(0.15, 0.15, 0.16, METAL))
	pt.cyl(Part.p(-0.7, 0.4, ridge + 0.15), Part.p(-0.7, 0.4, ridge + 0.2), 0.09, Color(0.15, 0.15, 0.16, METAL))
	# Keittiön ikkunan valo kuistille illalla.
	_lamp(pt, Part.p(0.3, 1.6, y0 + 1.3), 0.5, 4.0)


## Läpinäkyvä ikkunalasi omana meshinään (koko paikallisessa avaruudessa: leveys x, korkeus y, paksuus).
func _pane(pt: Part, center: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = B.boxm(size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.85, 0.9, 0.12)
	m.roughness = 0.05
	m.metallic_specular = 0.9
	mi.material_override = m
	mi.position = center
	pt.node.add_child(mi)


## Alamökin sisätilat: keittiö järven päässä ja sauna (pelkkä löylyhuone) takana. Lattiat, paneelit, väliseinä,
## kalusteet, valot ja minipelien paikat.
func _interior(pt: Part) -> void:
	var y0 := DY
	var top := DY + 2.23
	var panel := Color(0.86, 0.78, 0.64)
	var sauna := Color(0.62, 0.46, 0.32)
	var white := Color(0.93, 0.93, 0.91)
	var kb := KITCHEN_V0  # keittiön takaseinä (väliseinän keittiön puoli)
	var sv1 := kb - 0.1  # saunan etuseinä (väliseinän saunan puoli)
	var sv0 := BACK + 0.18  # saunan takaseinä
	# Lattiat (törmäys tulee terassin lattiasta).
	pt.bx(-1.72, 1.72, sv1, 0.92, y0 - 0.04, y0, Color(0.72, 0.62, 0.5, BOARD_U))
	pt.bx(-1.72, 1.72, sv0, sv1, y0 - 0.04, y0, Color(0.6, 0.48, 0.36, BOARD_U))
	# Paneelit hirsiseinien sisäpintoihin (aukot samoissa kohdissa).
	_log_wall(pt, true, -1.72, -1.7, kb, 0.92, y0, top, panel, [DOOR_KITCHEN + [y0, y0 + 1.95]], BOARD_V, false)
	_log_wall(pt, true, -1.72, -1.7, sv0, sv1, y0, top, sauna, [DOOR_SAUNA + [y0, y0 + 1.95]], BOARD_V, false)
	_log_wall(pt, true, 1.7, 1.72, kb, 0.92, y0, top, panel, [], BOARD_V, false)
	_log_wall(pt, true, 1.7, 1.72, sv0, sv1, y0, top, sauna, [], BOARD_V, false)
	_log_wall(pt, false, -1.72, 1.72, 0.9, 0.92, y0, top, panel, [[-0.2, 0.8, y0 + 0.85, y0 + 1.55]], BOARD_U, false)
	_log_wall(pt, false, -1.72, 1.72, sv0, sv0 + 0.02, y0, top, sauna, [], BOARD_U, false)
	# Väliseinä keittiön ja saunan välillä (ei ovea).
	pt.bx(-1.72, 1.72, sv1 + 0.02, kb, y0, top, Color(panel.r, panel.g, panel.b, BOARD_V), true)
	pt.bx(-1.72, 1.72, sv1, sv1 + 0.02, y0, top, Color(sauna.r, sauna.g, sauna.b, BOARD_V))

	# --- Keittiö: työtaso oikealla (väliseinää vasten), pöytä neljälle ikkunan edessä ---
	var ct := Color(0.42, 0.43, 0.44)
	# Kapea keittiö (syvyys 45 cm), jotta kokki mahtuu työtason ja pöydän väliin.
	pt.bx(-0.2, 1.72, kb, kb + 0.45, y0, y0 + 0.86, white, true)
	pt.bx(-0.22, 1.72, kb, kb + 0.47, y0 + 0.86, y0 + 0.9, ct)
	for k in 5:
		var x := -0.2 + k * 0.384
		pt.bx(x + 0.01, x + 0.374, kb + 0.45, kb + 0.465, y0 + 0.1, y0 + 0.82, Color(0.97, 0.97, 0.95))
		pt.bx(x + 0.17, x + 0.21, kb + 0.465, kb + 0.48, y0 + 0.72, y0 + 0.74, Color(0.3, 0.3, 0.32, METAL))
	pt.bx(-0.2, 1.72, kb + 0.46, kb + 0.47, y0, y0 + 0.1, Color(0.25, 0.25, 0.26))  # sokkeli
	# Liesi: musta keraaminen taso, kaksi levyä; pannu etulevyllä.
	pt.bx(-0.15, 0.45, kb + 0.05, kb + 0.42, y0 + 0.9, y0 + 0.91, Color(0.05, 0.05, 0.06, GLASS))
	for q: Vector2 in [Vector2(0.05, kb + 0.29), Vector2(0.28, kb + 0.13)]:
		pt.cyl(Part.p(q.x, q.y, y0 + 0.91), Part.p(q.x, q.y, y0 + 0.915), 0.09, Color(0.18, 0.1, 0.08, METAL), 16)
	pt.cyl(Part.p(0.05, kb + 0.29, y0 + 0.915), Part.p(0.05, kb + 0.29, y0 + 0.95), 0.12, Color(0.12, 0.12, 0.13, METAL), 16)
	pt.beam(Part.p(0.05, kb + 0.41, y0 + 0.94), Part.p(0.05, kb + 0.65, y0 + 0.96), 0.03, 0.02, Color(0.1, 0.1, 0.1))
	pan_pos = _world3(pt, 0.05, kb + 0.29, y0 + 0.95)
	cook_spot = _world3(pt, 0.05, kb + 0.78, y0)
	cook_face = _world3(pt, 0.05, kb + 0.15, y0)
	# Tiskiallas ja hana.
	pt.bx(0.95, 1.4, kb + 0.1, kb + 0.39, y0 + 0.78, y0 + 0.905, Color(0.7, 0.72, 0.74, METAL))
	pt.cyl(Part.p(1.18, kb + 0.07, y0 + 0.9), Part.p(1.18, kb + 0.07, y0 + 1.15), 0.015, Color(0.75, 0.77, 0.8, METAL))
	pt.beam(Part.p(1.18, kb + 0.07, y0 + 1.15), Part.p(1.18, kb + 0.25, y0 + 1.12), 0.025, 0.025, Color(0.75, 0.77, 0.8, METAL))
	# Yläkaapit, kahvinkeitin ja leipälaatikko.
	pt.bx(0.55, 1.72, kb, kb + 0.3, y0 + 1.45, y0 + 2.1, white)
	for k in 3:
		pt.bx(0.56 + k * 0.39, 0.93 + k * 0.39, kb + 0.3, kb + 0.31, y0 + 1.47, y0 + 2.08, Color(0.97, 0.97, 0.95))
	pt.bx(0.6, 0.8, kb + 0.05, kb + 0.2, y0 + 0.9, y0 + 1.2, Color(0.1, 0.1, 0.11))
	pt.cyl(Part.p(0.7, kb + 0.27, y0 + 0.9), Part.p(0.7, kb + 0.27, y0 + 1.02), 0.05, Color(0.6, 0.65, 0.7, GLASS))
	pt.bx(1.45, 1.7, kb + 0.05, kb + 0.25, y0 + 0.9, y0 + 1.05, Color(0.75, 0.2, 0.15))
	# Pöytä ja penkit: kaksi paikkaa kummallakin pitkällä sivulla, kasvot pöytään. Pöydän keskellä pelataan
	# kortit (korttipeli.gd: card_spot), lettulautanen ikkunan päässä.
	var tw := Color(0.8, 0.68, 0.5)
	pt.bx(-0.2, 0.8, -0.2, 0.88, y0 + 0.72, y0 + 0.76, tw, true)
	pt.body.add_child(B.box_shape(Vector3(1.0, 0.72, 1.08), Part.p(0.3, 0.34, y0 + 0.36)))
	for q: Vector2 in [Vector2(-0.15, -0.15), Vector2(0.75, -0.15), Vector2(-0.15, 0.83), Vector2(0.75, 0.83)]:
		pt.bx(q.x - 0.03, q.x + 0.03, q.y - 0.03, q.y + 0.03, y0, y0 + 0.72, tw)
	for bx_: float in [-0.52, 1.12]:
		pt.bx(bx_ - 0.17, bx_ + 0.17, -0.18, 0.86, y0 + 0.42, y0 + 0.46, tw)
		for vv: float in [-0.1, 0.78]:
			pt.bx(bx_ - 0.14, bx_ + 0.14, vv - 0.03, vv + 0.03, y0, y0 + 0.42, tw)
	# Paikat kiertävät pöydän ympäri: länsi järven puolelta, länsi, itä, itä järven puolelta.
	# Tekoäly kävelee paikalleen pöydän päädyn ohi: länsipuolelle oven puolelta, itäpuolelle hellan ja pöydän
	# välistä.
	for q: Vector2 in [Vector2(-0.52, 0.66), Vector2(-0.52, 0.0), Vector2(1.12, 0.0), Vector2(1.12, 0.66)]:
		table_seats.append([_world3(pt, q.x, q.y, y0), _world3(pt, 0.3, q.y, y0)])
		if q.x < 0.0:
			table_paths.append([_world3(pt, -1.05, q.y, y0), _world3(pt, q.x, q.y, y0)])
		else:
			table_paths.append([_world3(pt, -1.3, kb + 1.3, y0), _world3(pt, q.x, kb + 1.3, y0), _world3(pt, q.x, q.y, y0)])
	card_frame = Transform3D(pt.node.transform.basis, _world3(pt, 0.3, 0.24, y0 + 0.761))
	plate_pos = _world3(pt, 0.3, 0.78, y0 + 0.76)
	pt.cyl(Part.p(0.3, 0.78, y0 + 0.76), Part.p(0.3, 0.78, y0 + 0.77), 0.09, Color(0.96, 0.96, 0.94), 16)
	pt.bx(0.62, 0.7, 0.76, 0.86, y0 + 0.76, y0 + 0.86, Color(0.75, 0.15, 0.2))  # hillopurkki
	# Kattolamppu.
	pt.cyl(Part.p(0.3, 0.3, top - 0.35), Part.p(0.3, 0.3, top), 0.01, DARK)
	pt.cyl(Part.p(0.3, 0.3, top - 0.45), Part.p(0.3, 0.3, top - 0.35), 0.16, Color(1, 0.9, 0.7, LAMP), 12)
	_room_light(pt, Part.p(0.3, 0.3, top - 0.55), 1.1, 3.5)

	# --- Sauna: lauteet perällä (itäseinällä) neljälle, kiuas ovesta katsoen vasemmalla ---
	var lw := Color(0.85, 0.68, 0.46)
	var lb := Color(lw.r, lw.g, lw.b, BOARD_V)
	var ld := Color(lw.r * 0.7, lw.g * 0.7, lw.b * 0.7, BOARD_U)
	pt.bx(1.12, 1.7, sv0, sv1, y0 + 0.96, y0 + 1.0, lb, true)
	pt.bx(1.12, 1.7, sv0, sv1, y0, y0 + 0.96, ld, true)
	pt.bx(0.67, 1.12, sv0, sv1, y0 + 0.46, y0 + 0.5, lb, true)
	pt.bx(0.67, 1.12, sv0, sv1, y0, y0 + 0.46, ld, true)
	pt.bx(1.66, 1.7, sv0, sv1, y0 + 1.3, y0 + 1.42, lb)  # selkänoja
	for v: float in [-4.6, -3.95, -3.3, -2.65]:
		sauna_seats.append([_world3(pt, 1.19, v, y0 + 0.55), _world3(pt, -1.0, v, y0 + 0.55)])
	var kc := Color(0.1, 0.1, 0.11, METAL)
	var kq := KIUAS
	pt.bx(kq.x - 0.25, kq.x + 0.25, kq.y - 0.25, kq.y + 0.25, y0, y0 + 0.72, kc, true)
	pt.bx(kq.x - 0.26, kq.x + 0.26, kq.y - 0.26, kq.y + 0.26, y0 + 0.62, y0 + 0.65, Color(0.25, 0.25, 0.26, METAL))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 26:
		var q := Vector2(rng.randf_range(kq.x - 0.18, kq.x + 0.18), rng.randf_range(kq.y - 0.18, kq.y + 0.18))
		var r := rng.randf_range(0.05, 0.08)
		var gc := rng.randf_range(0.3, 0.5)
		pt.bt.add(B.sphere(r, 6), Transform3D(Basis().scaled(Vector3(1, 0.7, 1)),
			Part.p(q.x, q.y, y0 + 0.72 + rng.randf() * 0.12)), Color(gc, gc, gc * 0.95, STONE))
	pt.cyl(Part.p(kq.x, kq.y, y0 + 0.9), Part.p(kq.x, kq.y, top), 0.07, kc)
	kiuas_pos = _world3(pt, kq.x, kq.y, y0 + 0.85)
	# Kiulu ja kauha alalauteella kiukaan puoleisessa päässä.
	pt.cyl(Part.p(0.88, sv1 - 0.25, y0 + 0.5), Part.p(0.88, sv1 - 0.25, y0 + 0.72), 0.12, Color(0.6, 0.42, 0.25), 12)
	pt.beam(Part.p(0.88, sv1 - 0.25, y0 + 0.7), Part.p(0.6, sv1 - 0.25, y0 + 0.95), 0.025, 0.025, Color(0.55, 0.38, 0.22))
	# Pyyhkeet naulakossa oven vieressä.
	var towels := [Color(0.85, 0.2, 0.2), Color(0.95, 0.95, 0.9), Color(0.2, 0.4, 0.75), Color(0.95, 0.75, 0.2)]
	for k in 4:
		var v := sv0 + 0.35 + k * 0.32
		pt.bx(-1.7, -1.66, v - 0.12, v + 0.12, y0 + 1.0, y0 + 1.6, towels[k])
	_room_light(pt, Part.p(-1.4, sv0 + 0.3, top - 0.25), 0.6, 3.2, Color(1.0, 0.78, 0.55))


## Kätkö saunan kupeessa törmässä, terassin takakulmasta käden ulottuvilla: kylmälaukku täynnä olutta,
## keltainen olutkori ja kivien ja kuusenhavujen alle piilotettu viinapullo. Ehtymätön.
func _stash(pt: Part) -> void:
	var g := func(u: float, v: float) -> float:
		var w := yw(u, v)
		return oh(w) + 0.02
	# Kylmälaukku (sininen, valkoinen kansi), kansi raollaan ja tölkit näkyvissä.
	var y: float = g.call(-2.5, -3.55)
	pt.bx(-2.75, -2.25, -3.75, -3.4, y - 0.1, y + 0.3, Color(0.15, 0.35, 0.75, PLAIN))
	pt.beam(Part.p(-2.76, -3.75, y + 0.33), Part.p(-2.76, -3.38, y + 0.42), 0.02, 0.05, Color(0.95, 0.95, 0.93))
	pt.bx(-2.76, -2.24, -3.77, -3.38, y + 0.3, y + 0.34, Color(0.95, 0.95, 0.93))
	for k in 6:
		var u := -2.68 + (k % 3) * 0.13
		var v := -3.67 + (k / 3) * 0.12
		pt.cyl(Part.p(u, v, y + 0.18), Part.p(u, v, y + 0.31), 0.033, Color(0.75, 0.78, 0.8, METAL), 8)
	# Olutkori tölkkeineen.
	var y2: float = g.call(-3.3, -3.6)
	pt.bx(-3.5, -3.1, -3.8, -3.45, y2 - 0.05, y2 + 0.22, Color(0.95, 0.75, 0.1))
	for k in 8:
		var u := -3.45 + (k % 4) * 0.1
		var v := -3.72 + (k / 4) * 0.12
		pt.cyl(Part.p(u, v, y2 + 0.1), Part.p(u, v, y2 + 0.25), 0.032, Color(0.15, 0.3, 0.6, METAL), 8)
	# Viinapullo kivien ja havujen alla.
	var bq := Vector2(-4.1, -3.65)
	var y3: float = g.call(bq.x, bq.y)
	pt.cyl(Part.p(bq.x, bq.y, y3 - 0.05), Part.p(bq.x, bq.y, y3 + 0.22), 0.045, Color(0.85, 0.9, 0.92, GLASS), 10)
	pt.cyl(Part.p(bq.x, bq.y, y3 + 0.22), Part.p(bq.x, bq.y, y3 + 0.32), 0.016, Color(0.85, 0.9, 0.92, GLASS), 8)
	pt.cyl(Part.p(bq.x, bq.y, y3 + 0.32), Part.p(bq.x, bq.y, y3 + 0.35), 0.019, Color(0.8, 0.1, 0.1, METAL), 8)
	pt.bx(bq.x - 0.05, bq.x + 0.05, bq.y + 0.04, bq.y + 0.05, y3 + 0.05, y3 + 0.15, Color(0.95, 0.95, 0.9))  # etiketti
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 5:
		var q := Vector2(bq.x + rng.randf_range(-0.25, 0.25), bq.y + rng.randf_range(-0.25, 0.15))
		var r := rng.randf_range(0.08, 0.14)
		var gc := rng.randf_range(0.35, 0.5)
		pt.bt.add(B.sphere(r, 7), Transform3D(Basis().scaled(Vector3(1.2, 0.7, 1)), Part.p(q.x, q.y, oh(yw(q.x, q.y)))),
			Color(gc, gc * 0.98, gc * 0.95, STONE))
	for k in 4:
		var a := Part.p(bq.x - 0.25 + k * 0.12, bq.y + 0.15, y3 + 0.25)
		pt.beam(a, a + Vector3(0.25, -0.2, 0.15), 0.12, 0.02, Color(0.15, 0.3, 0.15))
	stash_pos = _world3(pt, -2.9, -3.55, DY)


## Huoneen valo: aina päällä, himmeä; varjot estävät valoa paistamasta katon ja seinien läpi ulos.
func _room_light(pt: Part, pos: Vector3, energy: float, rng: float, col := Color(1.0, 0.82, 0.6)) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.4
	l.shadow_enabled = true
	pt.node.add_child(l)


func _woodshed(pt: Part) -> void:
	# Halkovaja saunan itäpäädyssä: pulpettikatto, takaseinä laudoista ja halkopino.
	var y0 := DY
	var ytop := DY + 1.95
	var ylow := DY + 1.7
	pt.bx(3.12, 3.2, -2.9, -0.8, y0, ylow, Color(0.6, 0.62, 0.66, BOARD_V), true)
	pt.bx(1.9, 3.2, -2.98, -2.9, y0, ylow, Color(0.6, 0.62, 0.66, BOARD_U), true)
	pt.cyl(Part.p(3.15, -0.85, y0), Part.p(3.15, -0.85, ylow), 0.05, TRIM)
	var a := Part.p(1.9, -3.1, ytop)
	var b := Part.p(3.45, -3.1, ylow - 0.1)
	var c := Part.p(3.45, -0.6, ylow - 0.1)
	var d := Part.p(1.9, -0.6, ytop)
	pt.quad(a, b, c, d, Color(ROOF.r, ROOF.g, ROOF.b, SHINGLE))
	pt.beam(b + Vector3(0.02, -0.06, 0), c + Vector3(0.02, -0.06, 0), 0.04, 0.16, TRIM)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for row in 7:
		for k in 13:
			var v := -2.75 + k * 0.145 + (row % 2) * 0.07
			if v > -0.95:
				continue
			var y := y0 + 0.07 + row * 0.13
			var x := 2.55 + rng.randf_range(-0.03, 0.03)
			var col := Color(0.62, 0.5, 0.36).lerp(Color(0.8, 0.68, 0.5), rng.randf())
			pt.cyl(Part.p(x - 0.33, v, y), Part.p(x + 0.33, v, y), 0.065, col, 6)
	pt.body.add_child(B.box_shape(Vector3(0.7, 0.95, 1.9), Part.p(2.55, -1.85, y0 + 0.48)))


# --- Grillikatos ----------------------------------------------------------------------------------------------

func _gazebo(pt: Part) -> void:
	var x0 := -10.5
	var x1 := -7.5
	var v0 := -3.0
	var v1 := 0.2
	var y0 := DY
	var top := DY + 2.1
	var low := DY + 0.95
	var t := 0.16
	# Takaseinä (törmän puoli) umpinainen, muovi-ikkuna; muut sivut matalat seinät ja nurkkapilarit.
	_log_wall_v(pt, x0, x1, v0, v0 + t, y0, top, WALL, [[-9.6, -8.4, y0 + 1.0, y0 + 1.7]])
	pt.bx(-9.6, -8.4, v0 + 0.06, v0 + 0.08, y0 + 1.0, y0 + 1.7, Color(0.85, 0.87, 0.88, FABRIC))
	_log_wall_v(pt, x0, x1, v1 - t, v1, y0, top, WALL, [[x0 + 0.65, x1 - 0.65, low, top - 0.3]])
	_log_wall_x(pt, x0, x0 + t, v0 + t, v1 - t, y0, top, WALL, [[v0 + 0.75, v1 - 0.75, low, top - 0.3]])
	_log_wall_x(pt, x1 - t, x1, v0 + t, v1 - t, y0, top, WALL, [[v0 + 0.75, v1 - 0.7, y0, top - 0.3]])
	_log_corners(pt, x0 + 0.08, x1 - 0.08, v0 + 0.08, v1 - 0.08, y0, top, WALL)
	# Aumakatto, räystäät 0,4 m; tumma sisäkatto.
	var o := 0.4
	var pitch := deg_to_rad(26.0)
	var hx := (x1 - x0) * 0.5 + o
	var hv := (v1 - v0) * 0.5 + o
	var cx := (x0 + x1) * 0.5
	var cv := (v0 + v1) * 0.5
	var ey := top - o * tan(pitch)
	var ry := ey + hx * tan(pitch)
	var rl := hv - hx  # harjan puolikas v-suunnassa
	var rc := Color(ROOF.r, ROOF.g, ROOF.b, SHINGLE)
	var e00 := Part.p(cx - hx, cv - hv, ey)
	var e10 := Part.p(cx + hx, cv - hv, ey)
	var e11 := Part.p(cx + hx, cv + hv, ey)
	var e01 := Part.p(cx - hx, cv + hv, ey)
	var r0 := Part.p(cx, cv - rl, ry)
	var r1 := Part.p(cx, cv + rl, ry)
	pt.quad(e00, r0, r1, e01, rc)
	pt.quad(e10, e11, r1, r0, rc)
	pt.tri(e00, e10, r0, rc)
	pt.tri(e01, r1, e11, rc)
	for k in [[e00, e10], [e10, e11], [e11, e01], [e01, e00]]:
		pt.beam(k[0] + Vector3.DOWN * 0.08, k[1] + Vector3.DOWN * 0.08, 0.04, 0.17, TRIM)
	pt.bx(x0 - o, x1 + o, v0 - o, v1 + o, ey - 0.05, ey - 0.02, Color(0.18, 0.18, 0.19, BOARD_U))
	# Keittiö: valkoinen kaappi (harmaa työtaso, kaasukeitin) ja musta kaasugrilli; baarijakkarat.
	pt.bx(-10.3, -9.25, -2.82, -2.3, y0, y0 + 0.86, Color(0.93, 0.93, 0.92), true)
	pt.bx(-10.32, -9.23, -2.84, -2.26, y0 + 0.86, y0 + 0.9, Color(0.6, 0.6, 0.62))
	pt.bx(-10.0, -9.6, -2.75, -2.4, y0 + 0.9, y0 + 1.0, Color(0.08, 0.08, 0.08, METAL))
	pt.cyl(Part.p(-9.8, -2.57, y0 + 1.0), Part.p(-9.8, -2.57, y0 + 1.03), 0.16, Color(0.2, 0.2, 0.2, METAL))
	pt.bx(-8.95, -8.0, -2.82, -2.25, y0 + 0.1, y0 + 0.9, Color(0.07, 0.07, 0.08, METAL), true)
	pt.bx(-9.0, -7.95, -2.85, -2.25, y0 + 0.9, y0 + 1.15, Color(0.1, 0.1, 0.11, METAL))
	pt.bx(-8.9, -8.05, -2.27, -2.2, y0 + 1.0, y0 + 1.04, Color(0.7, 0.7, 0.72, METAL))  # kahva
	pt.bx(-7.95, -7.7, -2.8, -2.35, y0 + 0.86, y0 + 0.9, Color(0.6, 0.6, 0.62, METAL))  # sivutaso
	for q: Vector2 in [Vector2(-9.6, -1.6), Vector2(-9.0, -1.2)]:
		pt.cyl(Part.p(q.x, q.y, y0 + 0.62), Part.p(q.x, q.y, y0 + 0.66), 0.17, TRIM)
		for k in 4:
			var a := TAU * k / 4.0 + 0.4
			pt.beam(Part.p(q.x + cos(a) * 0.17, q.y + sin(a) * 0.17, y0), Part.p(q.x + cos(a) * 0.1, q.y + sin(a) * 0.1, y0 + 0.62),
				0.03, 0.03, TRIM)
	# Lamppu katossa.
	pt.bx(-9.1, -8.9, -1.5, -1.3, top - 0.12, top - 0.05, Color(1, 0.9, 0.7, LAMP))
	_lamp(pt, Part.p(-9.0, -1.4, top - 0.3), 0.7, 6.0)
	# Kastelukannu katoksen edessä.
	pt.bx(-7.3, -6.95, -2.6, -2.45, y0, y0 + 0.24, Color(0.15, 0.45, 0.3))
	pt.beam(Part.p(-6.95, -2.53, y0 + 0.08), Part.p(-6.7, -2.53, y0 + 0.3), 0.03, 0.03, Color(0.15, 0.45, 0.3))


# --- Teltta, pöytä ja penkit ----------------------------------------------------------------------------------

func _tent(pt: Part) -> void:
	var x0 := -5.2
	var x1 := -2.2
	var v0 := -1.2
	var v1 := 1.8
	var y0 := DY
	var ey := DY + 2.2
	var ay := DY + 3.0
	var cx := (x0 + x1) * 0.5
	var cv := (v0 + v1) * 0.5
	var leg := Color(0.12, 0.12, 0.13, METAL)
	for q: Vector2 in [Vector2(x0, v0), Vector2(x1, v0), Vector2(x1, v1), Vector2(x0, v1)]:
		pt.bx(q.x - 0.02, q.x + 0.02, q.y - 0.02, q.y + 0.02, y0, ey, leg)
		pt.body.add_child(B.box_shape(Vector3(0.08, 2.2, 0.08), Part.p(q.x, q.y, y0 + 1.1)))
		pt.beam(Part.p(q.x, q.y, ey - 0.02), Part.p(cx, cv, ay - 0.08), 0.025, 0.025, leg)
	var fc := Color(0.97, 0.97, 0.95, FABRIC)
	var apex := Part.p(cx, cv, ay)
	var cs := [Part.p(x0 - 0.05, v0 - 0.05, ey), Part.p(x1 + 0.05, v0 - 0.05, ey), Part.p(x1 + 0.05, v1 + 0.05, ey),
		Part.p(x0 - 0.05, v1 + 0.05, ey)]
	for k in 4:
		pt.tri(cs[k], cs[(k + 1) % 4], apex, fc)
		pt.quad(cs[k], cs[(k + 1) % 4], cs[(k + 1) % 4] + Vector3.DOWN * 0.22, cs[k] + Vector3.DOWN * 0.22, fc)
	# Pöytä: harmaa kansi, valkoiset pukkijalat; penkit molemmin puolin.
	var tc := Color(0.55, 0.57, 0.58)
	var white := Color(0.93, 0.93, 0.92)
	pt.bx(-4.45, -2.95, 0.0, 0.8, y0 + 0.72, y0 + 0.76, tc, true)
	pt.body.add_child(B.box_shape(Vector3(1.5, 0.72, 0.8), Part.p(-3.7, 0.4, y0 + 0.36)))
	for x: float in [-4.3, -3.1]:
		pt.bx(x - 0.04, x + 0.04, 0.1, 0.7, y0, y0 + 0.72, white)
		pt.bx(x - 0.05, x + 0.05, 0.05, 0.75, y0, y0 + 0.06, white)
	pt.bx(-4.3, -3.1, 0.37, 0.43, y0 + 0.2, y0 + 0.3, white)
	for bv: float in [-0.32, 1.12]:
		pt.bx(-4.45, -2.95, bv - 0.15, bv + 0.15, y0 + 0.42, y0 + 0.46, tc)
		for x: float in [-4.3, -3.1]:
			pt.bx(x - 0.03, x + 0.03, bv - 0.12, bv + 0.12, y0, y0 + 0.42, white)
		for x: float in [-4.15, -3.7, -3.25]:
			seats.append([_world3(pt, x, bv, y0), _world3(pt, x, 0.4, y0)])
	# Pöydällä: hanaviinilaatikko, punainen pullo, mukit, lasit ja läppäri.
	pt.bx(-4.35, -4.15, 0.45, 0.6, y0 + 0.76, y0 + 1.0, Color(0.92, 0.95, 0.85))
	pt.bx(-4.35, -4.15, 0.45, 0.52, y0 + 0.8, y0 + 0.92, Color(0.55, 0.78, 0.2))
	pt.cyl(Part.p(-4.0, 0.7, y0 + 0.76), Part.p(-4.0, 0.7, y0 + 1.0), 0.04, Color(0.85, 0.1, 0.1))
	pt.cyl(Part.p(-3.85, 0.35, y0 + 0.76), Part.p(-3.85, 0.35, y0 + 0.86), 0.04, Color(0.85, 0.8, 0.72))
	pt.cyl(Part.p(-3.2, 0.2, y0 + 0.76), Part.p(-3.2, 0.2, y0 + 0.86), 0.035, Color(0.9, 0.92, 0.9, GLASS))
	pt.cyl(Part.p(-3.6, 0.15, y0 + 0.76), Part.p(-3.6, 0.15, y0 + 0.86), 0.035, Color(0.9, 0.92, 0.9, GLASS))
	pt.bx(-3.55, -3.2, 0.35, 0.6, y0 + 0.76, y0 + 0.775, Color(0.72, 0.73, 0.75, METAL))
	pt.beam(Part.p(-3.375, 0.6, y0 + 0.775), Part.p(-3.375, 0.68, y0 + 0.99), 0.35, 0.012, Color(0.2, 0.25, 0.3, GLASS))
	# Jakkara.
	pt.cyl(Part.p(-2.7, -0.9, y0), Part.p(-2.7, -0.9, y0 + 0.45), 0.17, Color(0.55, 0.57, 0.58))


func _world3(pt: Part, x: float, v: float, y: float) -> Vector3:
	var w := pt.w2(x, v)
	return Vector3(w.x, y, w.y)


# --- Huussi ---------------------------------------------------------------------------------------------------

func _outhouse(pt: Part) -> void:
	var x0 := 3.8
	var x1 := 5.1
	var v0 := -0.15
	var v1 := 1.25
	var y0 := DY
	var top := DY + 2.0
	var pitch := deg_to_rad(28.0)
	var ridge := top + (x1 - x0) * 0.5 * tan(pitch)
	_log_wall_v(pt, x0, x1, v0, v0 + 0.12, y0, top, WALL)
	_log_wall_v(pt, x0, x1, v1 - 0.12, v1, y0, top, WALL)
	_log_wall_x(pt, x1 - 0.12, x1, v0 + 0.12, v1 - 0.12, y0, top, WALL)
	_log_wall_x(pt, x0, x0 + 0.12, v0 + 0.12, v1 - 0.12, y0, top, WALL, [[v0 + 0.25, v1 - 0.25, y0, y0 + 1.85]])
	pt.bx(x0 - 0.03, x0, v0 + 0.25, v1 - 0.25, y0, y0 + 1.85, Color(0.96, 0.96, 0.94, BOARD_V))
	pt.bx(x0 - 0.05, x0 - 0.01, v0 + 0.45, v1 - 0.45, y0 + 1.5, y0 + 1.7, Color(0.15, 0.17, 0.2, GLASS))
	for k in [[v0 + 0.17, v0 + 0.25], [v1 - 0.25, v1 - 0.17]]:
		pt.bx(x0 - 0.05, x0, k[0], k[1], y0, y0 + 1.93, TRIM)
	pt.bx(x0 - 0.05, x0, v0 + 0.17, v1 - 0.17, y0 + 1.85, y0 + 1.93, TRIM)
	var cv := (v0 + v1) * 0.5
	var ov := 0.35
	var rc := Color(ROOF.r, ROOF.g, ROOF.b, SHINGLE)
	# Harja x-suunnassa (ovi päätyseinässä? ei: ovi pitkällä sivulla, harja v-suunnassa).
	for s: float in [-1.0, 1.0]:
		var xe := (x0 + x1) * 0.5 + s * ((x1 - x0) * 0.5 + 0.25)
		var ye := top - 0.25 * tan(pitch)
		pt.quad(Part.p(xe, v0 - ov, ye), Part.p((x0 + x1) * 0.5, v0 - ov, ridge), Part.p((x0 + x1) * 0.5, v1 + ov, ridge),
			Part.p(xe, v1 + ov, ye), rc)
		pt.beam(Part.p(xe, v0 - ov, ye - 0.05), Part.p(xe, v1 + ov, ye - 0.05), 0.04, 0.14, TRIM)
		for vv: float in [v0 - ov, v1 + ov]:
			pt.beam(Part.p(xe, vv, ye), Part.p((x0 + x1) * 0.5, vv, ridge), 0.04, 0.15, TRIM)
	for vv: float in [v0, v1]:
		pt.tri(Part.p(x0, vv, top), Part.p(x1, vv, top), Part.p((x0 + x1) * 0.5, vv, ridge - 0.03), Color(WALL.r, WALL.g, WALL.b, LOG))
	pt.cyl(Part.p(4.75, cv, ridge - 0.3), Part.p(4.75, cv, ridge + 0.35), 0.05, Color(0.12, 0.12, 0.12, METAL))
	# Ulkovalo oven yläpuolella ja kukkaruukku.
	pt.bx(x0 - 0.12, x0 - 0.02, cv - 0.06, cv + 0.06, y0 + 2.0, y0 + 2.15, Color(1, 0.9, 0.7, LAMP))
	pt.cyl(Part.p(3.4, -0.5, y0), Part.p(3.4, -0.5, y0 + 0.28), 0.14, Color(0.6, 0.3, 0.2))
	pt.bt.add(B.sphere(0.2, 8), Transform3D(Basis(), Part.p(3.4, -0.5, y0 + 0.4)), Color(0.25, 0.45, 0.15))


# --- Laituri --------------------------------------------------------------------------------------------------

func _dock(pt: Part) -> void:
	var x0 := -3.2
	var x1 := -1.2
	var v0 := 5.9
	var v1 := 13.9
	var top := 0.42
	pt.bx(x0, x1, v0, v1, top - 0.06, top, Color(0.66, 0.6, 0.52, BOARD_U))
	pt.bx(x0, x1, v0, v1, top - 0.36, top - 0.06, Color(0, 0, 0, 0), true)
	for x: float in [x0 + 0.03, x1 - 0.03]:
		pt.bx(x - 0.04, x + 0.04, v0, v1, top - 0.24, top - 0.02, Color(0.5, 0.45, 0.38, BOARD_V))
	for v: float in [v0 + 1.3, v0 + 4.0, v1 - 1.3]:
		pt.bx(x0 + 0.15, x1 - 0.15, v - 0.6, v + 0.6, -0.12, top - 0.24, Color(0.22, 0.23, 0.24))  # ponttonit
	# Portaiden alla tasanne rannassa.
	pt.bx(-2.85, -1.55, 5.5, 5.95, top - 0.06, top, Color(0.66, 0.6, 0.52, BOARD_U))
	# Uimatikkaat laiturin päässä: kaarevat kaiteet ja askelmat veteen.
	var steel := Color(0.78, 0.8, 0.82, METAL)
	for x: float in [-2.55, -1.85]:
		var prev := Part.p(x, v1 - 0.25, top)
		for k in range(1, 7):
			var a := PI * k / 6.0
			var q := Part.p(x, v1 - 0.25 + sin(a) * 0.32, top + 0.75 * sin(a * 0.5) + cos(a) * 0.0 + (0.0 if k < 6 else -0.05))
			if k == 6:
				q = Part.p(x, v1 + 0.08, top + 0.55)
			pt.cyl(prev, q, 0.022, steel, 6)
			prev = q
		pt.cyl(prev, Part.p(x, v1 + 0.1, -1.0), 0.022, steel, 6)
	for k in 3:
		var y := top - 0.3 - k * 0.3
		pt.bx(-2.55, -1.85, v1 + 0.04, v1 + 0.14, y - 0.02, y, steel)
	views.append(_world3(pt, -2.2, v1 - 0.6, top))
	views.append(_world3(pt, -1.6, v1 - 1.4, top))


# --- Portaat törmään ------------------------------------------------------------------------------------------

func _stairs(pt: Part, run: float) -> void:
	_steps(pt, 0.0, STAIR_W, 0.0, run, DY, floor_y(), true, STAIR, true)


# --- Ylämökki -------------------------------------------------------------------------------------------------

func _cabin(pt: Part) -> void:
	var fy := floor_y()
	var hx := CABIN_HX
	var hv := CABIN_HV
	var eave := fy + 2.35
	var pitch := deg_to_rad(20.0)
	var ridge := eave + hv * tan(pitch)
	var g := INF
	for sx: float in [-1.0, 1.0]:
		for sv: float in [-1.0, 1.0]:
			g = minf(g, Terrain.h(pt.w2(sx * hx, sv * hv).x, pt.w2(sx * hx, sv * hv).y))
	# Valkoinen säleikkö lattian alla, lattia.
	var lat := Color(0.93, 0.93, 0.91, LATTICE)
	pt.bx(-hx + 0.05, hx - 0.05, hv - 0.08, hv - 0.05, g - 0.3, fy - 0.1, lat)
	pt.bx(-hx + 0.05, -hx + 0.08, -hv + 0.05, hv - 0.05, g - 0.3, fy - 0.1, lat)
	pt.bx(hx - 0.08, hx - 0.05, -hv + 0.05, hv - 0.05, g - 0.3, fy - 0.1, lat)
	pt.bx(-hx + 0.05, hx - 0.05, -hv + 0.05, -hv + 0.08, g - 0.3, fy - 0.1, Color(0.3, 0.3, 0.3))
	pt.bx(-hx, hx, -hv, hv, fy - 0.12, fy, TRIM)
	# Seinät: järven puolella kaksi ikkunaa, takana yksi, länsipäädyssä yksi, itäpäädyssä ovi ja ikkuna.
	var w0 := fy + 0.85
	var w1 := fy + 1.9
	_log_wall_v(pt, -hx, hx, hv - 0.2, hv, fy, eave, WALL_UP, [[-1.7, -0.5, w0, w1], [0.4, 1.6, w0, w1]])
	_log_wall_v(pt, -hx, hx, -hv, -hv + 0.2, fy, eave, WALL_UP, [[-0.6, 0.6, w0 + 0.2, w1]])
	_log_wall_x(pt, -hx, -hx + 0.2, -hv + 0.2, hv - 0.2, fy, eave, WALL_UP, [[-0.5, 0.5, w0 + 0.2, w1]])
	_log_wall_x(pt, hx - 0.2, hx, -hv + 0.2, hv - 0.2, fy, eave, WALL_UP, [[-0.7, 0.15, fy, fy + 2.0], [0.7, 1.6, w0, w1]])
	_log_corners(pt, -hx + 0.1, hx - 0.1, -hv + 0.1, hv - 0.1, fy, eave, WALL_UP)
	_window_v(pt, -1.7, -0.5, hv, 1.0, w0, w1, true)
	_window_v(pt, 0.4, 1.6, hv, 1.0, w0, w1, true)
	_window_v(pt, -0.6, 0.6, -hv, -1.0, w0 + 0.2, w1)
	_window_x(pt, -0.5, 0.5, -hx, -1.0, w0 + 0.2, w1)
	_window_x(pt, 0.7, 1.6, hx, 1.0, w0, w1, true)
	# Ovi itäpäädyssä terassille.
	pt.bx(hx - 0.05, hx, -0.7, 0.15, fy, fy + 2.0, Color(0.95, 0.95, 0.93, BOARD_U))
	pt.bx(hx, hx + 0.04, -0.6, 0.05, fy + 1.4, fy + 1.85, Color(0.12, 0.14, 0.17, GLASS))
	for k in [[-0.78, -0.7], [0.15, 0.23]]:
		pt.bx(hx, hx + 0.05, k[0], k[1], fy, fy + 2.08, TRIM)
	pt.bx(hx, hx + 0.05, -0.78, 0.23, fy + 2.0, fy + 2.08, TRIM)
	pt.bx(hx + 0.04, hx + 0.08, 0.0, 0.08, fy + 0.95, fy + 1.0, Color(0.3, 0.3, 0.32, METAL))
	# Harjakatto järven suuntaisesti, itäpäädyssä pidempi räystäs terassin päälle.
	var ov := 0.5
	var xw := -hx - 0.5
	var xe := hx + 1.3
	var ey := eave - ov * tan(pitch)
	var rc := Color(ROOF.r, ROOF.g, ROOF.b, SHINGLE)
	for s: float in [-1.0, 1.0]:
		var a := Part.p(xw, s * (hv + ov), ey)
		var b := Part.p(xe, s * (hv + ov), ey)
		var c := Part.p(xe, 0.0, ridge)
		var d := Part.p(xw, 0.0, ridge)
		pt.quad(a, b, c, d, rc)
		pt.quad(a + Vector3.DOWN * 0.09, b + Vector3.DOWN * 0.09, c + Vector3.DOWN * 0.09, d + Vector3.DOWN * 0.09,
			Color(0.9, 0.9, 0.88, BOARD_V))
		pt.beam(Part.p(xw, s * (hv + ov + 0.02), ey - 0.07), Part.p(xe, s * (hv + ov + 0.02), ey - 0.07), 0.04, 0.2, TRIM)
		for xx: float in [xw, xe]:
			pt.beam(Part.p(xx, s * (hv + ov), ey - 0.02), Part.p(xx, 0.0, ridge - 0.02), 0.04, 0.22, TRIM)
	for xx: float in [-hx, hx]:
		pt.tri(Part.p(xx, -hv, eave), Part.p(xx, hv, eave), Part.p(xx, 0.0, ridge - 0.04), Color(WALL_UP.r, WALL_UP.g, WALL_UP.b, LOG))
	# Aurinkopaneelit telineellä järven puoleisella lappeella ja antenni länsipäädyssä.
	for k in 2:
		var x := -1.9 + k * 1.15
		var base := Part.p(x, hv * 0.55, eave + hv * 0.45 * tan(pitch))
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-48.0))
		pt.box(Vector3(1.05, 0.04, 0.7), base + Vector3(0, 0.35, 0), Color(0.08, 0.12, 0.22, GLASS), tilt)
		pt.box(Vector3(1.08, 0.03, 0.73), base + Vector3(0, 0.33, 0), Color(0.75, 0.76, 0.78, METAL), tilt)
		pt.beam(base, base + Vector3(0, 0.3, 0.05), 0.04, 0.04, Color(0.7, 0.7, 0.72, METAL))
	var mast := Part.p(-hx - 0.25, 0.6, fy + 1.0)
	pt.cyl(mast, mast + Vector3.UP * 3.6, 0.03, Color(0.7, 0.7, 0.72, METAL))
	for k in 5:
		var y := 3.0 + k * 0.12
		pt.beam(mast + Vector3(0, y, -0.3 + k * 0.03), mast + Vector3(0, y, 0.3 - k * 0.03), 0.015, 0.015, Color(0.7, 0.7, 0.72, METAL))
	pt.beam(mast + Vector3(0, 3.0, 0), mast + Vector3(0.6, 3.0, 0), 0.02, 0.02, Color(0.7, 0.7, 0.72, METAL))
	pt.bx(-0.2, 0.2, -0.9, -0.5, ridge - 0.4, ridge + 0.55, Color(0.12, 0.12, 0.12))  # piippu
	# Törmäys: runko.
	pt.body.add_child(B.box_shape(Vector3(hx * 2.0, eave - fy, hv * 2.0), Part.p(0, 0, (fy + eave) * 0.5)))
	pt.body.add_child(B.box_shape(Vector3(hx * 2.0, fy - g + 0.3, hv * 2.0), Part.p(0, 0, (fy + g - 0.3) * 0.5)))
	# Terassi itäpäädyssä: lattia, tolpat, kaiteet (aukko portaille järven puolella).
	var tx0 := hx
	var tx1 := 4.9
	var tv0 := -1.8
	var tv1 := hv
	pt.bx(tx0, tx1, tv0, tv1, fy - 0.05, fy, Color(DECK.r, DECK.g, DECK.b, BOARD_V))
	pt.bx(tx0, tx1, tv0, tv1, fy - 0.35, fy - 0.05, Color(0, 0, 0, 0), true)
	for q: Vector2 in [Vector2(tx1 - 0.1, tv1 - 0.1), Vector2(tx1 - 0.1, tv0 + 0.1), Vector2(tx0 + 0.1, tv1 - 0.1), Vector2(3.7, tv1 - 0.1)]:
		var gg := Terrain.h(pt.w2(q.x, q.y).x, pt.w2(q.x, q.y).y)
		pt.bx(q.x - 0.06, q.x + 0.06, q.y - 0.06, q.y + 0.06, gg - 0.2, fy - 0.05, Color(0.55, 0.53, 0.5))
	_railing(pt, Vector2(tx0 + 0.05, tv1), Vector2(3.45, tv1), fy)
	_railing(pt, Vector2(tx1, tv1), Vector2(tx1, tv0), fy)
	# Kuistin valo oven vieressä.
	pt.bx(hx + 0.02, hx + 0.12, 0.35, 0.47, fy + 1.9, fy + 2.1, Color(1, 0.9, 0.7, LAMP))
	_lamp(pt, Part.p(hx + 0.4, 0.4, fy + 2.0), 0.7, 6.0)


# --- Ranta: kivet vedessä ja peitetty vene ---------------------------------------------------------------------

func _shore(pt: Part) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var stone := Color(0.5, 0.49, 0.47)
	# Isot siirtolohkareet vedessä saunan edustalla (valokuvista).
	for q: Vector3 in [Vector3(2.5, -15.5, 0.9), Vector3(4.6, -14.6, 0.6), Vector3(6.8, -15.4, 0.75), Vector3(0.6, -17.6, 0.5),
			Vector3(-14.0, -12.0, 0.7), Vector3(8.6, -12.8, 0.55)]:
		var y := Terrain.h(q.x, q.y)
		var r: float = q.z
		pt.bt.add(B.sphere(r, 10), Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf() * TAU, 0))
			.scaled(Vector3(1.3, 0.7, 1.0)), Vector3(q.x, y + r * 0.35, q.y)), stone)
		var sh := SphereShape3D.new()
		sh.radius = r * 0.85
		var cs := CollisionShape3D.new()
		cs.shape = sh
		cs.position = Vector3(q.x, y + r * 0.3, q.y)
		pt.body.add_child(cs)
	# Pressun alla oleva soutuvene rannalla pääterassin länsipuolella.
	var bp := yw(-11.6, 3.6)
	var by := maxf(Terrain.h(bp.x, bp.y), 0.0)
	var yaw := atan2(-LAKE.x, -LAKE.y) + 0.5
	var basis := Basis(Vector3.UP, yaw)
	var tarp := Color(0.55, 0.57, 0.6)
	pt.bt.add(B.boxm(Vector3(1.4, 0.55, 3.8)), Transform3D(basis, Vector3(bp.x, by + 0.3, bp.y)), tarp)
	pt.bt.add(B.boxm(Vector3(1.1, 0.25, 3.4)), Transform3D(basis, Vector3(bp.x, by + 0.65, bp.y)), tarp.darkened(0.1))
	var bs := B.box_shape(Vector3(1.4, 0.8, 3.8))
	bs.transform = Transform3D(basis, Vector3(bp.x, by + 0.4, bp.y))
	pt.body.add_child(bs)


# --- Reittipisteet tekoälylle ---------------------------------------------------------------------------------

func _waypoints() -> void:
	var y := func(u: float, v: float, yy: float) -> Vector3:
		var w := yw(u, v)
		return Vector3(w.x, yy, w.y)
	var cab := func(x: float, v: float) -> Vector3:
		var w := cw(x, v)
		return Vector3(w.x, floor_y(), w.y)
	var beach := yw(-8.0, 4.4)
	points = {
		"piha": y.call(-5.6, 0.6, DY), "portaat_ala": y.call(-5.8, -1.3, DY), "poyta": y.call(-3.7, -1.0, DY),
		"grilli_ovi": y.call(-6.7, -1.4, DY), "grilli": y.call(-8.6, -1.8, DY), "etuterassi": y.call(-2.2, 3.6, DY), "kulku": y.call(-2.65, 1.4, DY),
		"kuisti": y.call(0.0, 2.2, DY), "kaide": y.call(0.6, 3.8, DY),
		"keittio_ovi": y.call(-2.55, 0.4, DY), "keittio": y.call(-1.15, 0.4, DY),
		"keittio_kaytava": y.call(-0.85, KITCHEN_V0 + 1.3, DY), "hella": cook_spot,
		"sauna_ovi": y.call(-2.55, -2.75, DY), "loylyhuone": y.call(-0.9, -2.9, DY),
		"katko": y.call(-2.9, -2.9, DY),
		"itaterassi": y.call(2.9, 3.4, DY), "huussi": y.call(3.3, 0.55, DY), "laituri_alku": y.call(-2.2, 6.4, 0.42),
		"laituri_paa": y.call(-2.2, 13.2, 0.42), "rantaportaat": y.call(-8.0, 1.5, DY),
		"ranta": Vector3(beach.x, Terrain.h(beach.x, beach.y), beach.y),
		"ranta_vesi": y.call(-8.0, 9.0, 0.0), "uinti1": y.call(-5.0, 40.0, 0.0), "uinti2": y.call(7.0, 44.0, 0.0),
		"uinti3": y.call(-14.0, 36.0, 0.0),
		"portaat_yla": cab.call(4.1, 1.9), "ylamokki_ovi": cab.call(3.2, -0.25),
	}
	links = [["piha", "portaat_ala"], ["piha", "poyta"], ["piha", "grilli_ovi"], ["grilli_ovi", "grilli"],
		["piha", "kulku"], ["kulku", "etuterassi"], ["etuterassi", "kuisti"], ["kulku", "keittio_ovi"],
		["keittio_ovi", "keittio"], ["keittio", "keittio_kaytava"],
		["keittio_kaytava", "hella"], ["keittio_ovi", "sauna_ovi"], ["sauna_ovi", "loylyhuone"],
		["poyta", "sauna_ovi"],
		["sauna_ovi", "katko"],
		["etuterassi", "kaide"], ["kaide", "itaterassi"], ["itaterassi", "huussi"], ["etuterassi", "laituri_alku"],
		["laituri_alku", "laituri_paa"], ["laituri_paa", "uinti1"], ["uinti1", "uinti2"], ["uinti1", "uinti3"],
		["uinti3", "ranta_vesi"], ["uinti1", "ranta_vesi"], ["ranta_vesi", "ranta"], ["ranta", "rantaportaat"],
		["rantaportaat", "piha"], ["portaat_ala", "portaat_yla"], ["portaat_yla", "ylamokki_ovi"]]
	views.append(points.kaide)
	views.append(y.call(-1.0, 3.9, DY))


## Lyhin reitti (Dijkstra) lähimmästä reittipisteestä kohteeseen: lista maailman paikkoja.
func route(from: Vector3, to: String) -> Array:
	var start := nearest_point(from)
	var dist := {start: 0.0}
	var prev := {}
	var open := [start]
	while not open.is_empty():
		open.sort_custom(func(a: String, b: String) -> bool: return dist[a] < dist[b])
		var cur: String = open.pop_front()
		if cur == to:
			break
		for l in links:
			var nb := ""
			if l[0] == cur:
				nb = l[1]
			elif l[1] == cur:
				nb = l[0]
			else:
				continue
			var d: float = dist[cur] + (points[cur] as Vector3).distance_to(points[nb])
			if not dist.has(nb) or d < dist[nb]:
				dist[nb] = d
				prev[nb] = cur
				open.append(nb)
	var out := []
	var n := to
	if not dist.has(to):
		return [points[to]]
	while n != start:
		out.push_front(points[n])
		n = prev[n]
	out.push_front(points[start])
	return out


func nearest_point(p: Vector3) -> String:
	var best := ""
	var bd := INF
	for k in points:
		var d: float = (points[k] as Vector3).distance_to(p)
		if d < bd:
			bd = d
			best = k
	return best
