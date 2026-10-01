extends RefCounted
## Maasto: Maanmittauslaitoksen 2 m korkeusmalli ja maastotietokannan pinnat (tools/kartta/bake.py ->
## assets/map/maasto.bin). Kaksi ruudukkoa: tarkka 2 x 2 km (2 m ruutu = korkeusmallin pikselit) ja kauko
## 10 x 10 km (16 m). Korkeudet metreinä Oulujärven pinnasta (122,81 m N2000), järvien pohja arvioitu.
## Kehys: x itään, z etelään, origo aloituspaikalla (Äpätinniemi). h(x, z) kolmioi kuten maastoverkko ja
## törmäysmuoto (HeightMapShape3D), joten maahan nostetut asiat ovat täsmälleen pinnalla.

const BIN := "res://assets/map/maasto.bin"
const COLLISION_LAYER := 16  # maaston törmäyskerros (bitti 5)
## Ruudukon ulkopuolella Oulujärven selkä: pohja tässä syvyydessä.
const OPEN_LAKE_DEPTH := -9.0

enum { FOREST, WATER, SAND, ROCK, BOG, FIELD, YARD, ROAD, PATH, CLEARING, FILL, POND }
const SURFACE_NAMES := ["metsä", "järvi", "hiekka", "kallio", "suo", "pelto", "piha", "tie", "polku", "hakkuuaukea",
	"täyttömaa", "lampi"]


class Grid:
	var n := 0
	var step := 1.0
	var half := 0.0
	var heights := PackedFloat32Array()
	var classes := PackedByteArray()

	func inside(x: float, z: float) -> bool:
		return absf(x) <= half and absf(z) <= half

	func h(x: float, z: float) -> float:
		var fx := clampf((x + half) / step, 0.0, n - 1.0)
		var fz := clampf((z + half) / step, 0.0, n - 1.0)
		var i := mini(int(fx), n - 2)
		var j := mini(int(fz), n - 2)
		var u := fx - i
		var v := fz - j
		var k := j * n + i
		var h00 := heights[k]
		var h10 := heights[k + 1]
		var h01 := heights[k + n]
		var h11 := heights[k + n + 1]
		# HeightMapShape3D:n kolmiointi (Jolt): lävistäjä (1,0)-(0,1).
		if u + v <= 1.0:
			return h00 + (h10 - h00) * u + (h01 - h00) * v
		return h11 + (h01 - h11) * (1.0 - u) + (h10 - h11) * (1.0 - v)

	func cls(x: float, z: float) -> int:
		var i := clampi(int((x + half) / step), 0, n - 2)
		var j := clampi(int((z + half) / step), 0, n - 2)
		return classes[j * (n - 1) + i]


static var near: Grid
static var far: Grid
static var _loaded := false


static func ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(BIN, FileAccess.READ)
	if f == null:
		push_error("Maastodataa ei löydy (%s): aja tools/kartta/bake.py." % BIN)
		return
	if f.get_buffer(4).get_string_from_ascii() != "ONM2":
		push_error("Väärä maasto.bin-versio: aja tools/kartta/bake.py uudelleen.")
		return
	near = _read_grid(f)
	far = _read_grid(f)


static func _read_grid(f: FileAccess) -> Grid:
	var g := Grid.new()
	g.n = f.get_32()
	g.step = f.get_float()
	g.half = f.get_float()
	g.heights = f.get_buffer(g.n * g.n * 4).to_float32_array()
	g.classes = f.get_buffer((g.n - 1) * (g.n - 1))
	return g


static func available() -> bool:
	ensure()
	return near != null


## Maanpinnan (tai järven pohjan) korkeus kohdassa (x, z).
static func h(x: float, z: float) -> float:
	ensure()
	if near == null:
		return 0.0
	if near.inside(x, z):
		return near.h(x, z)
	if far.inside(x, z):
		return far.h(x, z)
	return OPEN_LAKE_DEPTH


## Pintaluokka (FOREST, WATER, ...) kohdassa (x, z).
static func surface(x: float, z: float) -> int:
	ensure()
	if near == null:
		return FOREST
	if near.inside(x, z):
		return near.cls(x, z)
	if far.inside(x, z):
		return far.cls(x, z)
	return WATER


static func is_water(x: float, z: float) -> bool:
	var s := surface(x, z)
	return s == WATER or s == POND


static func normal(x: float, z: float) -> Vector3:
	var e := 1.0
	var dx := h(x + e, z) - h(x - e, z)
	var dz := h(x, z + e) - h(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


## Korkeudet kuvana (FORMAT_RF) maastovarjostimelle.
static func height_image(g: Grid) -> Image:
	return Image.create_from_data(g.n, g.n, false, Image.FORMAT_RF, g.heights.to_byte_array())


## Pintaluokat kuvana (FORMAT_R8, yksi pikseli ruutua kohden).
static func class_image(g: Grid) -> Image:
	return Image.create_from_data(g.n - 1, g.n - 1, false, Image.FORMAT_R8, g.classes)
