extends RefCounted
## Autoreitti mökiltä Happy Beachille ja leirintäalueen kehys.
##
## Camping Happy Beach on oikeasti Säräisniemessä (Vankkuritie 1, 64.4535 N, 26.7891 E), noin 5,3 km
## aloituspaikalta länsi-luoteeseen. Pelissä paikka on tiivistetty kävelyalueen sisälle: leirintäalue on
## Siperianrannan hiekkarannan törmällä (n. 700 m mökiltä luoteeseen), ja sinne ajetaan oikeita teitä pitkin:
## mökin ja Äpätintien välinen ajoura (n. 140 m), Äpätintie ja sen jatke länteen, ja siitä pohjoiseen
## polun kohdalle rakennettu Vankkuritie leirintäalueen pihaan. Matkaa n. 850 m, mäet alle 5 %.
##
## Leirintäalueen kehys (a, b): origo K on tien päässä parkkipaikalla, a kulkee hiekkarantaa kaakkoon
## ja b järvelle (luoteeseen). Alueen solmu on kierretty niin, että sen paikallinen +X on a ja -Z on b.

const Terrain := preload("res://scripts/terrain.gd")

const REAL_LATLON := Vector2(64.4535, 26.7891)

## Reittipisteet (maailman x, z) mökin pihan pysäköintipaikalta Happy Beachin parkkipaikalle. Kaikki pisteet
## ovat maastotietokannan teiden ja polun pisteitä, joten ajoura on piirretyllä tiellä.
const ROUTE := [Vector2(13.0, 36.0), Vector2(11.4, 43.4), Vector2(7.4, 51.8), Vector2(0.8, 65.4),
	Vector2(-7.0, 89.3), Vector2(-14.9, 107.3), Vector2(-17.7, 118.5), Vector2(-26.1, 141.4),
	Vector2(-45.4, 149.8), Vector2(-67.4, 156.4), Vector2(-88.0, 160.1), Vector2(-109.2, 162.3),
	Vector2(-136.5, 164.0), Vector2(-156.7, 167.7), Vector2(-171.5, 174.5), Vector2(-195.7, 187.9),
	Vector2(-220.2, 195.6), Vector2(-252.6, 207.9), Vector2(-274.3, 216.1), Vector2(-349.1, 195.5),
	Vector2(-412.3, 176.0), Vector2(-464.6, 161.3), Vector2(-502.8, 149.2), Vector2(-538.0, 137.9),
	Vector2(-563.9, 130.3), Vector2(-568.4, 111.4), Vector2(-576.0, 85.5), Vector2(-579.7, 67.9),
	Vector2(-580.5, 45.9), Vector2(-584.3, 21.4), Vector2(-586.8, 10.9), Vector2(-588.0, -12.0),
	Vector2(-586.0, -40.0)]
## Reitin osa, joka on uutta tietä (Vankkuritie): Äpätien jatkeen päästä leirintäalueelle.
const NEW_ROAD_FROM := 24

## Mökin pihan pysäköintipaikka: auton paikka ja suunta (ajouran suuntaan, etelään).
const HOME_SPOT := Vector2(13.0, 36.0)

## Leirintäalueen kehys.
const K := Vector2(-586.0, -40.0)
const A := Vector2(0.8096, 0.587)
const N := Vector2(0.587, -0.8096)

const MASK_R := 4.2  # tien raivaus ja "tiellä"-alue (m) reitin molemmin puolin
const CELL := 2.0

static var _mask := PackedByteArray()
static var _x0 := 0.0
static var _z0 := 0.0
static var _w := 0
static var _h := 0


## Kehyksestä (a, b) maailmaan (x, z).
static func cw(a: float, b: float) -> Vector2:
	return K + A * a + N * b


## Maailmasta (x, z) kehykseen (a, b).
static func wc(p: Vector2) -> Vector2:
	var d := p - K
	return Vector2(d.dot(A), d.dot(N))


## Leirintäalueen solmun kiertokulma (y): paikallinen +X = A, -Z = N.
static func yaw() -> float:
	return atan2(-A.y, A.x)


## Reitti toiseen suuntaan (paluu mökille).
static func reversed() -> Array:
	var r := ROUTE.duplicate()
	r.reverse()
	return r


## Soratien kumpareet: Äpätintien suoralle osuudelle (reitin pisteet MOUND_FROM..NEW_ROAD_FROM) tehdään maastoon
## pehmeitä poikkipoikkeisia kumpuja (n. 0,45-0,85 m, 6 m pitkiä) 38 m välein; kovaa ajettaessa auto lentää
## niiden yli (auto.gd). Ennen maaston rakentamista (world.gd).
const MOUND_FROM := 8
const MOUND_GAP := 38.0
const MOUND_HALF := 3.5


static func terraform() -> void:
	var g := Terrain.near
	if g == null:
		return
	var hs := g.heights
	var next := 20.0
	var travelled := 0.0
	var n := 0
	for k in range(MOUND_FROM, NEW_ROAD_FROM):
		var a: Vector2 = ROUTE[k]
		var b: Vector2 = ROUTE[k + 1]
		var seg := a.distance_to(b)
		var t := (b - a) / seg
		while next <= travelled + seg:
			var c := a + t * (next - travelled)
			var height := 0.45 + 0.4 * fposmod(float(n) * 0.618, 1.0)
			n += 1
			next += MOUND_GAP
			var r := MOUND_HALF + 7.0
			for j in range(int((c.y - r + g.half) / g.step), int((c.y + r + g.half) / g.step) + 1):
				for i in range(int((c.x - r + g.half) / g.step), int((c.x + r + g.half) / g.step) + 1):
					var d := Vector2(-g.half + i * g.step, -g.half + j * g.step) - c
					var along := d.dot(t)
					var across := absf(d.dot(t.orthogonal()))
					if absf(along) >= MOUND_HALF or across >= 7.0:
						continue
					var w := cos(along / MOUND_HALF * PI * 0.5)
					hs[j * g.n + i] += height * w * w * (1.0 - smoothstep(3.0, 7.0, across))
		travelled += seg
	g.heights = hs


## Lisää Vankkuritien tiedoston teihin ennen kuin world.gd piirtää tiet.
static func add_road(data: Dictionary) -> void:
	var pts := []
	for i in range(NEW_ROAD_FROM, ROUTE.size()):
		var p: Vector2 = ROUTE[i]
		pts.append([p.x, p.y])
	data.roads.append({"kind": "drive", "name": "Vankkuritie", "paved": false, "pts": pts})


static func _ensure_mask() -> void:
	if not _mask.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector2 in ROUTE:
		lo = lo.min(p)
		hi = hi.max(p)
	lo -= Vector2.ONE * (MASK_R + 2.0)
	hi += Vector2.ONE * (MASK_R + 2.0)
	_x0 = lo.x
	_z0 = lo.y
	_w = int((hi.x - lo.x) / CELL) + 1
	_h = int((hi.y - lo.y) / CELL) + 1
	_mask.resize(_w * _h)
	_mask.fill(0)
	var reach := int(ceil(MASK_R / CELL))
	for k in ROUTE.size() - 1:
		var a: Vector2 = ROUTE[k]
		var b: Vector2 = ROUTE[k + 1]
		var steps := maxi(1, int(a.distance_to(b)))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			var ci := int((p.x - _x0) / CELL)
			var cj := int((p.y - _z0) / CELL)
			for dj in range(-reach, reach + 1):
				for di in range(-reach, reach + 1):
					var i := ci + di
					var j := cj + dj
					if i < 0 or j < 0 or i >= _w or j >= _h:
						continue
					var c := Vector2(_x0 + (i + 0.5) * CELL, _z0 + (j + 0.5) * CELL)
					if c.distance_to(p) <= MASK_R:
						_mask[j * _w + i] = 1


## Onko paikka ajouran, tien tai Vankkuritien päällä (reitin MASK_R sisällä).
static func on_route(x: float, z: float) -> bool:
	_ensure_mask()
	var i := int((x - _x0) / CELL)
	var j := int((z - _z0) / CELL)
	if x < _x0 or z < _z0 or i >= _w or j >= _h:
		return false
	return _mask[j * _w + i] == 1


## Puut pois ajourilta ja tieltä (trees.gd): metsässä rungot törmäävät, joten tie raivataan.
static func clears_tree(x: float, z: float) -> bool:
	return on_route(x, z)


## Reitin pituus metreinä.
static func length() -> float:
	var l := 0.0
	for k in ROUTE.size() - 1:
		l += (ROUTE[k] as Vector2).distance_to(ROUTE[k + 1])
	return l
