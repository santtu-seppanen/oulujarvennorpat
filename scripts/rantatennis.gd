extends "res://scripts/pallopeli.gd"
## Spartan-rantatennis ylämökin edessä ruohokentällä: koko porukka pelaa yhdessä isoilla puumailoilla, eikä
## vastakkain. Pallo pidetään ilmassa ja lyönnit lasketaan, kunnes pallo osuu maahan (pallopeli.gd).
## Kenttä tasataan ja raivataan (terraform, clears_tree), valkoiset rajat ja ennätystaulu kentän laidalla.

## Kenttä ylämökin kehyksessä (x pitkin järven puoleista seinää, v järvelle): mökin maanpuoleinen sivu.
const FIELD_C := Vector2(-2.5, -11.0)
const FIELD_H := Vector2(7.0, 4.5)  # puolikkaat leveydet
## Pelipaikat kentän kehyksessä (x, v): salmiakki, naapuriin n. 4,6 m.
const SPOTS := [Vector2(-3.8, 0.0), Vector2(0.0, 2.6), Vector2(3.8, 0.0), Vector2(0.0, -2.6)]

var _sign: Label3D


func _init() -> void:
	title = "Rantatennis"
	msg = "tn"
	section = "rantatennis"
	save_path = "user://rantatennis.cfg"


# --- Kenttä ---------------------------------------------------------------------------------------------------

## Kentän kehyksestä (x, v) maailmaan (x, z).
static func fw(x: float, v: float) -> Vector2:
	return Mokki.cw(FIELD_C.x + x, FIELD_C.y + v)


static func local(p: Vector2) -> Vector2:
	return Mokki.wc(p) - FIELD_C


static func in_field(p: Vector3, m := 0.0) -> bool:
	var q := local(Vector2(p.x, p.z))
	return absf(q.x) <= FIELD_H.x + m and absf(q.y) <= FIELD_H.y + m


## Kenttä tasaiseksi (keskikorkeuteen) ja ruohoksi ennen kuin world.gd rakentaa maaston; reunoilla 2 m siirtymä.
static func terraform() -> void:
	var g := Terrain.near
	if g == null:
		return
	var c := fw(0.0, 0.0)
	var r := FIELD_H.length() + 4.0
	var sum := 0.0
	var n := 0
	var nodes := []
	var cls := g.classes.duplicate()
	for j in range(int((c.y - r + g.half) / g.step), int((c.y + r + g.half) / g.step) + 1):
		for i in range(int((c.x - r + g.half) / g.step), int((c.x + r + g.half) / g.step) + 1):
			var p := Vector2(-g.half + i * g.step, -g.half + j * g.step)
			var q := local(p)
			var out := maxf(absf(q.x) - FIELD_H.x, absf(q.y) - FIELD_H.y)
			if out < 3.0:
				nodes.append([j * g.n + i, out])
			if out < 0.0:
				sum += g.heights[j * g.n + i]
				n += 1
			if out < 0.8 and i < g.n - 1 and j < g.n - 1:
				cls[j * (g.n - 1) + i] = Terrain.YARD
	g.classes = cls
	if n == 0:
		return
	var flat := sum / n
	var hs := g.heights
	for e in nodes:
		hs[e[0]] = lerpf(flat, hs[e[0]], smoothstep(1.0, 3.0, e[1]))
	g.heights = hs


## Puut pois kentältä ja sen reunoilta.
static func clears_tree(x: float, z: float) -> bool:
	var c := fw(0.0, 0.0)
	if absf(x - c.x) > 14.0 or absf(z - c.y) > 14.0:
		return false
	return in_field(Vector3(x, 0.0, z), 2.0)


func _ready() -> void:
	super._ready()
	_build_field()


func _spot_pos(k: int) -> Vector3:
	var q: Vector2 = SPOTS[k] if k >= 0 else Vector2.ZERO
	var w := fw(q.x, q.y)
	return Vector3(w.x, Terrain.h(w.x, w.y), w.y)


func in_area(p: Vector3, m := 0.0) -> bool:
	return in_field(p, m)


func can_start(p: Vector3) -> bool:
	return not active and in_field(p, 0.5) and absf(p.y - Terrain.h(p.x, p.z)) < 0.6


func _on_record() -> void:
	_update_sign()


## Valkoiset rajat ruohossa ja ennätystaulu kentän laidalla mökin puolella.
func _build_field() -> void:
	var batch := B.Batch.new()
	var white := Color(0.92, 0.92, 0.88)
	var line := func(a: Vector2, b: Vector2) -> void:
		var segs := maxi(1, int(a.distance_to(b) / 1.0))
		for s in segs:
			var p0 := a.lerp(b, float(s) / segs)
			var p1 := a.lerp(b, float(s + 1) / segs)
			var w0 := fw(p0.x, p0.y)
			var w1 := fw(p1.x, p1.y)
			var m := (w0 + w1) * 0.5
			var d := w1 - w0
			batch.add(B.boxm(Vector3(0.06, 0.02, d.length() + 0.06)), Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)),
				Vector3(m.x, Terrain.h(m.x, m.y) + 0.005, m.y)), white)
	var hx := FIELD_H.x - 0.5
	var hv := FIELD_H.y - 0.5
	line.call(Vector2(-hx, -hv), Vector2(hx, -hv))
	line.call(Vector2(hx, -hv), Vector2(hx, hv))
	line.call(Vector2(hx, hv), Vector2(-hx, hv))
	line.call(Vector2(-hx, hv), Vector2(-hx, -hv))
	# Taulu kahdella tolpalla kentän mökin puoleisella laidalla, teksti kentälle päin.
	var bp := fw(-FIELD_H.x + 1.2, FIELD_H.y + 0.4)
	var by := Terrain.h(bp.x, bp.y)
	var bx := Vector3(Mokki.CABIN_X.x, 0, Mokki.CABIN_X.y)
	for s: float in [-0.55, 0.55]:
		batch.add(B.boxm(Vector3(0.07, 1.6, 0.07)), Transform3D(Basis(), Vector3(bp.x, by + 0.8, bp.y) + bx * s),
			Color(0.45, 0.33, 0.2))
	var face := Basis.looking_at(Vector3(Mokki.CABIN_LAKE.x, 0, Mokki.CABIN_LAKE.y))  # teksti kentälle päin
	batch.add(B.boxm(Vector3(1.3, 0.55, 0.04)), Transform3D(face, Vector3(bp.x, by + 1.35, bp.y)), Color(0.18, 0.3, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = batch.commit()
	mi.material_override = B.vcol_mat()
	add_child(mi)
	_sign = B.label(self, "", Vector3(bp.x, by + 1.35, bp.y) + face * Vector3(0, 0, 0.03), 30, Color(1, 0.97, 0.85))
	_sign.basis = face
	_update_sign()


func _update_sign() -> void:
	_sign.text = "RANTATENNIS\nEnnätys %d lyöntiä" % record


## Alhaalta pihasta ja saunalta portaita ylös ylämökin terassille, oven edustan tasanteelta portaat alas kentälle.
func _route_to(b: CharacterBody3D) -> Array:
	var p := b.global_position
	var q := local(Vector2(p.x, p.z))
	if p.y > Mokki.floor_y() - 1.5 and q.length() < 30.0:
		return []
	var m: Node3D = game.world.mokki
	var path: Array = m.route(p, "ylamokki_ovi")
	path.append(Mokki.cabin_steps_foot())
	return path


## Iso puinen Spartan-maila oikeaan käteen: varsi kämmenestä käsivarren suuntaan, lapa kasvot eteenpäin.
func _give_item(b: CharacterBody3D) -> Node3D:
	var r := Node3D.new()
	var wood := B.mat(Color(0.74, 0.56, 0.34))
	var face := MeshInstance3D.new()
	face.mesh = B.cyl(0.15, 0.15, 0.014, 20)
	face.material_override = wood
	face.basis = Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.15, 1.0))
	face.position = Vector3(0, 0.29, 0)
	r.add_child(face)
	var paint := MeshInstance3D.new()
	paint.mesh = B.cyl(0.1, 0.1, 0.016, 20)
	paint.material_override = B.mat(Color(0.1, 0.35, 0.7) if b.get_index() % 2 == 0 else Color(0.75, 0.15, 0.1))
	paint.basis = face.basis
	paint.position = face.position
	r.add_child(paint)
	var grip := MeshInstance3D.new()
	grip.mesh = B.boxm(Vector3(0.035, 0.18, 0.028))
	grip.material_override = B.mat(Color(0.25, 0.18, 0.12))
	grip.position = Vector3(0, 0.06, 0)
	r.add_child(grip)
	var holder := Node3D.new()
	holder.add_child(r)
	r.basis = Basis(Vector3.BACK, -PI * 0.5)
	b.body().attach("hand_r", holder, Vector3(0.06, 0.0, 0.0))
	return holder
