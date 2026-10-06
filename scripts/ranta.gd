extends Node3D
## Hiekkaranta ja viinakätkö Äpätin itärannalla (kätkö 64.431214 N, 26.889959 E, n. 170 m mökiltä itä-kaakkoon).
## - Polku ylämökin terassin maanpuoleiselta sivulta metsän läpi törmän reunalle ja vinosti rinnettä alas
##   rannalle. Polun varrelta puut pois.
## - Viinakätkö rinteessä, kun polkua laskeudutaan rannalle: lahonnut puulaatikko havujen ja kivien alla,
##   viinapulloja ja oluita. Ehtymätön kuten saunan kätkö (main.gd: E olut, Q viina).
## - Hiekkaranta törmän juurella: kuivan rannan pinta hiekaksi, ajopuu ja kiviä. Järven pohja rannan edessä
##   hiekkaa ja syvenee loivasti, joten kahlataan ensin ja n. 18 m rannasta päästään uimaan (on_foot.gd).

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")

## Polku (maailman x, z): ylämökin terassin takaa tenniskentän ohi itä-kaakkoon metsän läpi, Äpätintien yli, törmän reunalta
## vinosti rinnettä alas kätkön ohi rantaan.
const TRAIL := [Vector2(-3.4, 10.6), Vector2(8.0, 14.0), Vector2(19.0, 23.0), Vector2(36.0, 31.5),
	Vector2(54.0, 41.0), Vector2(72.0, 49.5), Vector2(90.0, 58.0), Vector2(106.0, 66.5), Vector2(122.0, 73.5),
	Vector2(136.0, 79.0), Vector2(146.0, 84.0), Vector2(152.0, 88.5), Vector2(156.0, 92.6), Vector2(159.8, 97.6),
	Vector2(163.5, 101.0)]
## Kätkö polun pohjoispuolella rinteessä (koordinaatin kohta on törmän juurella vesirajassa; kätkö on rinteessä).
const STASH := Vector2(158.2, 96.4)
const CACHE_LATLON := Vector2(64.431214, 26.889959)
## Hiekkaranta: rantaviiva etsitään näiltä riveiltä (z), ja pohja muotoillaan rannasta BEACH_OUT metriä ulos.
const BEACH_Z := Vector2(74.0, 132.0)
const BEACH_X := Vector2(140.0, 215.0)
const BEACH_OUT := 44.0
const SAND_TOP := 1.3  # tätä matalampi kuiva maa rannassa on hiekkaa

var stash_pos := Vector3.ZERO


## Pohjan syvyys d metriä rantaviivasta: kahlattavaa n. 15 m, sitten syvenee (1,35 m n. 18 m kohdalla).
static func bottom(d: float) -> float:
	return -(0.05 * d + 0.0015 * d * d) - 0.05


## Rantaviivan x rivillä z (ensimmäinen järven pinnan alla oleva kohta lännestä itään), NAN jos ei löydy.
static func shore_x(z: float) -> float:
	var x := BEACH_X.x
	while x < BEACH_X.y:
		if Terrain.near.h(x, z) < 0.0:
			return x
		x += 0.5
	return NAN


## Rannan muotoilu ennen kuin world.gd rakentaa maaston ja törmäyksen: kuiva ranta hiekaksi ja järven pohja
## rannan edessä loivaksi hiekkapohjaksi; rannan päissä sulautuu alkuperäiseen.
static func terraform() -> void:
	var g := Terrain.near
	if g == null:
		return
	var hs := g.heights
	var cls := g.classes.duplicate()
	var shore := {}
	var j0 := int((BEACH_Z.x + g.half) / g.step)
	var j1 := int((BEACH_Z.y + g.half) / g.step)
	for j in range(j0, j1 + 1):
		var z := -g.half + j * g.step
		shore[j] = shore_x(z)
	for j in range(j0, j1 + 1):
		var z := -g.half + j * g.step
		var sx: float = shore[j]
		if is_nan(sx):
			continue
		# Rannan päissä 10 m siirtymä alkuperäiseen pohjaan.
		var w := minf(smoothstep(BEACH_Z.x, BEACH_Z.x + 10.0, z), 1.0 - smoothstep(BEACH_Z.y - 10.0, BEACH_Z.y, z))
		for i in range(int((sx - 14.0 + g.half) / g.step), int((sx + BEACH_OUT + g.half) / g.step) + 1):
			var x := -g.half + i * g.step
			var k := j * g.n + i
			var d := x - sx
			if d >= 0.0:
				var want := bottom(d)
				# Kauempana ulkona alkuperäinen pohja, jos se on syvempi.
				var fade := smoothstep(BEACH_OUT - 12.0, BEACH_OUT, d)
				hs[k] = lerpf(hs[k], minf(hs[k], lerpf(want, hs[k], fade)), w)
			elif hs[k] < SAND_TOP and j < g.n - 1 and i < g.n - 1:
				var c := j * (g.n - 1) + i
				if cls[c] == Terrain.FOREST or cls[c] == Terrain.ROCK:
					cls[c] = Terrain.SAND
	g.heights = hs
	g.classes = cls
	# Kaukoverkko näkyy hieman tarkan alla: lasketaan rannan edessä uuden pohjan alle, ettei se pilkistä läpi.
	var f := Terrain.far
	if f == null:
		return
	var fs := f.heights
	for fj in f.n:
		var z := -f.half + fj * f.step
		if z < BEACH_Z.x - 16.0 or z > BEACH_Z.y + 16.0:
			continue
		for fi in f.n:
			var x := -f.half + fi * f.step
			if x < BEACH_X.x or x > BEACH_X.y + BEACH_OUT:
				continue
			var m := INF
			for dz in range(-16, 17, 4):
				for dx in range(-16, 17, 4):
					m = minf(m, g.h(x + dx, z + dz))
			fs[fj * f.n + fi] = minf(fs[fj * f.n + fi], m)
	f.heights = fs


## Polku tieaineiston muodossa (world.gd piirtää sen muiden polkujen tapaan).
static func trail_road() -> Dictionary:
	var pts := []
	for q: Vector2 in TRAIL:
		pts.append([q.x, q.y])
	return {"kind": "path", "name": "Kätköpolku", "paved": false, "pts": pts}


static func trail_dist(p: Vector2) -> float:
	var best := INF
	for k in TRAIL.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, TRAIL[k], TRAIL[k + 1])))
	return best


## Puut pois polun, kätkön ja kuivan hiekkarannan kohdalta.
static func clears_tree(x: float, z: float) -> bool:
	if x < -10.0 or x > BEACH_X.y or z < 5.0 or z > BEACH_Z.y + 4.0:
		return false
	var p := Vector2(x, z)
	if trail_dist(p) < 1.3 or p.distance_to(STASH) < 2.0:
		return true
	return z > BEACH_Z.x and x > 150.0 and Terrain.h(x, z) < SAND_TOP + 0.3


func _ready() -> void:
	var batch := B.Batch.new()
	var body := StaticBody3D.new()
	_build_stash(batch)
	_build_beach(batch, body)
	var mi := MeshInstance3D.new()
	mi.mesh = batch.commit()
	mi.material_override = B.vcol_mat()
	add_child(mi)
	add_child(body)
	# Polun alkuun viitta ylämökin taakse.
	var a: Vector2 = TRAIL[1]
	var d: Vector2 = (TRAIL[2] as Vector2) - a
	B.trail_sign(self, Vector3(a.x - 1.0, Terrain.h(a.x - 1.0, a.y + 0.8), a.y + 0.8), "Ranta", atan2(-d.x, -d.y))


## Lahonnut puulaatikko rinteessä polun vieressä, kansi raollaan ja osin havujen peitossa: viinapulloja,
## oluttölkkejä ja kiviä painona havujen päällä.
func _build_stash(batch: B.Batch) -> void:
	var down := Vector2(1.0, 0.25).normalized()  # rinne laskee itään
	var yaw := atan2(down.x, down.y)
	var basis := Basis(Vector3.UP, yaw)
	var y := Terrain.h(STASH.x, STASH.y)
	var o := Vector3(STASH.x, y, STASH.y)
	var at := func(lx: float, ly: float, lz: float) -> Vector3:
		return o + basis * Vector3(lx, ly, lz)
	var wood := Color(0.36, 0.27, 0.18)
	# Laatikko kaivettu rinteeseen: yläreuna rinteen puolella maan tasalla.
	batch.add(B.boxm(Vector3(0.7, 0.04, 0.5)), Transform3D(basis, at.call(0, 0.02, 0)), wood.darkened(0.3))
	for s: float in [-1.0, 1.0]:
		batch.add(B.boxm(Vector3(0.7, 0.36, 0.04)), Transform3D(basis, at.call(0, 0.18, s * 0.25)), wood)
		batch.add(B.boxm(Vector3(0.04, 0.36, 0.5)), Transform3D(basis, at.call(s * 0.35, 0.18, 0)), wood)
	# Kansi raollaan, nojaa rinteeseen.
	batch.add(B.boxm(Vector3(0.74, 0.03, 0.54)),
		Transform3D(basis * Basis(Vector3.RIGHT, -0.5), at.call(0, 0.45, -0.32)), wood.darkened(0.15))
	# Pullot ja tölkit laatikossa.
	var glass := Color(0.85, 0.9, 0.92)
	for k in 3:
		var p: Vector3 = at.call(-0.2 + k * 0.14, 0.04, -0.06)
		batch.add(B.cyl(0.045, 0.045, 0.24, 10), Transform3D(Basis(), p + Vector3(0, 0.12, 0)), glass)
		batch.add(B.cyl(0.016, 0.02, 0.1, 8), Transform3D(Basis(), p + Vector3(0, 0.29, 0)), glass)
		batch.add(B.cyl(0.019, 0.019, 0.03, 8), Transform3D(Basis(), p + Vector3(0, 0.355, 0)),
			Color(0.8, 0.1, 0.1) if k != 1 else Color(0.1, 0.25, 0.7))
		batch.add(B.boxm(Vector3(0.07, 0.08, 0.002)), Transform3D(basis, p + Vector3(0, 0.12, 0) + basis * Vector3(0, 0, 0.046)),
			Color(0.95, 0.95, 0.9))
	for k in 4:
		var p: Vector3 = at.call(0.12 + (k % 2) * 0.09, 0.1, 0.06 + (k / 2) * 0.09)
		batch.add(B.cyl(0.032, 0.032, 0.15, 8), Transform3D(Basis(), p), Color(0.15, 0.3, 0.6))
	# Havut laatikon päällä ja kivet painona.
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	for k in 6:
		var a: Vector3 = at.call(-0.4 + k * 0.15, 0.4, rng.randf_range(-0.1, 0.25))
		batch.add(B.boxm(Vector3(0.5, 0.02, 0.14)), Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3),
			yaw + rng.randf_range(-0.8, 0.8), rng.randf_range(-0.2, 0.2))), a), Color(0.13, 0.27, 0.13))
	for k in 4:
		var q := STASH + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
		var r := rng.randf_range(0.1, 0.18)
		var gc := rng.randf_range(0.35, 0.5)
		batch.add(B.sphere(r, 7), Transform3D(Basis().scaled(Vector3(1.2, 0.7, 1)), Vector3(q.x, Terrain.h(q.x, q.y), q.y)),
			Color(gc, gc * 0.98, gc * 0.95))
	stash_pos = o + Vector3(0, 0.1, 0)


## Ajopuu hiekalla ja kiviä rannassa ja matalassa vedessä.
func _build_beach(batch: B.Batch, body: StaticBody3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	# Ajopuu (kuorittu, harmaantunut runko) rantaviivan suuntaisesti.
	var lz := 104.0
	var lx := shore_x(lz) - 3.2
	var a := Vector3(lx - 0.6, Terrain.h(lx - 0.6, lz - 2.2) + 0.12, lz - 2.2)
	var b := Vector3(lx + 0.4, Terrain.h(lx + 0.4, lz + 2.0) + 0.12, lz + 2.0)
	var d := b - a
	var basis := Basis(Quaternion(Vector3.UP, d.normalized()))
	batch.add(B.cyl(0.13, 0.16, d.length(), 10), Transform3D(basis, (a + b) * 0.5), Color(0.62, 0.6, 0.55))
	batch.add(B.cyl(0.04, 0.06, 0.8, 6), Transform3D(Basis(Vector3(0, 0, 1), 1.1).rotated(Vector3.UP, 0.4),
		a + d * 0.3 + Vector3(0.25, 0.15, 0)), Color(0.58, 0.56, 0.5))
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.15
	cap.height = d.length()
	cs.shape = cap
	cs.transform = Transform3D(basis, (a + b) * 0.5)
	body.add_child(cs)
	# Kiviä: muutama rannassa, muutama matalassa vedessä.
	for k in 7:
		var z := rng.randf_range(BEACH_Z.x + 8.0, BEACH_Z.y - 8.0)
		var sx := shore_x(z)
		if is_nan(sx):
			continue
		var x := sx + (rng.randf_range(-4.0, -1.0) if k < 3 else rng.randf_range(3.0, 12.0))
		var r := rng.randf_range(0.25, 0.6)
		var y := Terrain.h(x, z)
		var gc := rng.randf_range(0.38, 0.52)
		batch.add(B.sphere(r, 8), Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf() * TAU, 0))
			.scaled(Vector3(1.3, 0.7, 1.0)), Vector3(x, y + r * 0.2, z)), Color(gc, gc * 0.97, gc * 0.93))
