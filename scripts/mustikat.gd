extends Node3D
## Mustikkamättäät metsässä mökin ympärillä. Mättään vieressä E syö kourallisen mustikoita, ja suihku paranee
## (rinnepissa.gd): jokainen kourallinen lisää lähtönopeutta, enintään MAX kourallista. Muiden kaari pitenee
## mustikoilla, mutta Markon suureen kaareen ei ilman erikoiskykyä yllä. Vaikutus hiipuu hiljalleen, ja syöty
## mätäs kasvaa marjat takaisin muutamassa minuutissa.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Rantatennis := preload("res://scripts/rantatennis.gd")

const PATCHES := 10  # mustikkapaikkoja metsässä
const PER_PATCH := 5
const RING := Vector2(18.0, 200.0)  # etäisyys mökkipihasta
const REACH := 1.3
const REGROW := 240.0  # sekuntia, kunnes syöty mätäs on taas sininen
const BOOST := 0.14  # lähtönopeus (m/s) kourallista kohden
const MAX := 10
const FADE := 150.0  # sekuntia per kourallinen, kun vaikutus hiipuu

var game: Node3D
var bushes: Array = []  # [{p: Vector3, berries: Node3D, t: float (0 = marjoja)}]
var eaten := {}  # hahmon indeksi -> kourallisia
var _fade := {}


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	var leaves := B.Batch.new()
	var centre := Mokki.yw(-3.0, -2.0)
	var tries := 0
	var patches := 0
	while patches < PATCHES and tries < 400:
		tries += 1
		var a := rng.randf() * TAU
		var r := lerpf(RING.x, RING.y, sqrt(rng.randf()))
		var c := centre + Vector2(cos(a), sin(a)) * r
		if not _ok(c):
			continue
		patches += 1
		for k in PER_PATCH:
			var q := c + Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
			if not _ok(q):
				continue
			_bush(leaves, q, rng)
	var mi := MeshInstance3D.new()
	mi.mesh = leaves.commit()
	mi.material_override = B.vcol_mat()
	add_child(mi)


## Mättään paikka: kuivaa metsämaata, ei pihalla, kentällä, teillä eikä vedessä.
func _ok(q: Vector2) -> bool:
	if Terrain.surface(q.x, q.y) != Terrain.FOREST or Terrain.h(q.x, q.y) < 1.2:
		return false
	if Mokki.clears_tree(q.x, q.y) or Rantatennis.in_field(Vector3(q.x, 0, q.y), 3.0):
		return false
	return Mokki.wy(q).length() > 16.0


## Matala varpu: muutama litteä vihreä pallo ja niiden päällä sinisiä marjoja.
func _bush(leaves: B.Batch, q: Vector2, rng: RandomNumberGenerator) -> void:
	var g := Terrain.h(q.x, q.y)
	var berries := B.Batch.new()
	# Varvikko: paljon pieniä tummanvihreitä lehtipalloja eri korkeuksilla (mustikanvarpu n. 30 cm).
	for k in 14:
		var o := Vector3(rng.randf_range(-0.45, 0.45), rng.randf_range(0.06, 0.24), rng.randf_range(-0.45, 0.45))
		var r := rng.randf_range(0.07, 0.13)
		var col := Color(0.07, 0.16, 0.04).lerp(Color(0.14, 0.24, 0.06), rng.randf())
		leaves.add(B.sphere(r, 6), Transform3D(Basis().scaled(Vector3(1.3, 0.7, 1.3)), Vector3(q.x, g, q.y) + o), col)
		leaves.add(B.cyl(0.006, 0.008, o.y, 4), Transform3D(Basis(), Vector3(q.x, g + o.y * 0.5, q.y) + Vector3(o.x, 0, o.z)),
			Color(0.25, 0.3, 0.12))
		# Mustikat lehtien reunoilla: tummansiniset, huurteiset.
		for j in 3:
			var b := o + Vector3(rng.randf_range(-r, r), rng.randf_range(-0.03, r * 0.6), rng.randf_range(-r, r)) * 1.1
			berries.add(B.sphere(0.022, 6), Transform3D(Basis(), Vector3(q.x, g, q.y) + b),
				Color(0.07, 0.09, 0.28).lerp(Color(0.2, 0.24, 0.45), rng.randf() * 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = berries.commit()
	mi.material_override = B.vcol_mat()
	add_child(mi)
	bushes.append({"p": Vector3(q.x, g, q.y), "berries": mi, "t": 0.0})


## Lähin marjainen mätäs käden ulottuvilla (indeksi) tai -1.
func near(p: Vector3) -> int:
	for i in bushes.size():
		var b: Dictionary = bushes[i]
		var q: Vector3 = b.p
		if b.t <= 0.0 and Vector2(p.x - q.x, p.z - q.z).length() < REACH and absf(p.y - q.y) < 1.5:
			return i
	return -1


## Hahmo i syö kourallisen mättäästä k.
func eat(k: int, i: int) -> void:
	var b: Dictionary = bushes[k]
	b.t = REGROW
	(b.berries as Node3D).visible = false
	eaten[i] = mini(MAX, eaten.get(i, 0) + 1)
	_fade[i] = FADE
	Sfx.play("pickup", -10.0, 1.3)


## Lähtönopeuden lisä suihkuun (m/s) hahmolle i.
func boost(i: int) -> float:
	return eaten.get(i, 0) * BOOST


func _process(delta: float) -> void:
	for b in bushes:
		if b.t > 0.0:
			b.t -= delta
			if b.t <= 0.0:
				(b.berries as Node3D).visible = true
	for i in eaten.keys():
		_fade[i] -= delta
		if _fade[i] <= 0.0:
			_fade[i] = FADE
			eaten[i] -= 1
			if eaten[i] <= 0:
				eaten.erase(i)
