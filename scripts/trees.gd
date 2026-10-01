extends Node3D
## Metsä: noin 700 000 puuta oikeilla paikoillaan (tools/kartta/bake.py -> assets/map/puut.bin). Valtapuut MML:n
## laserkeilauksen latvusmallista (paikka, pituus, latvuksen leveys), latvuston aukot täydennetty laserin
## latvustoon ja puulajit Luken VMI 2023 -osuuksista.
##
## Puut piirretään MultiMesheinä, mutta paikat luetaan varjostimessa datatekstuurista (tree.gdshaderinc), joten
## GDScriptissä ei käydä puita läpi yksitellen. Kolme tasoa: lähellä korttilatvukset (foliage.gd), keskimatkalla
## umpimuodot ja kaukana kevyet perusmuodot. Kaukotaso tehdään kerralla 512 m lohkoina, lähi- ja keskitaso
## 128 m lohkoina pelaajan ympärille sitä mukaa kuin hän liikkuu. Rungot törmäävät pelaajan lähilohkoissa.

const Foliage := preload("res://scripts/foliage.gd")
const B := preload("res://scripts/build.gd")
const Mokki := preload("res://scripts/mokki.gd")

const BIN := "res://assets/map/puut.bin"
enum { PINE, SPRUCE, BIRCH, ASPEN, BUSH }
const SPECIES := 5
const NEAR_END := 95.0     # korttilatvukset tähän asti (puukohtaisesti varjostimessa)
const MID_END := 520.0     # umpimuodot
const FAR_END := 4200.0    # perusmuodot (usva peittää kauempana)
const NEAR_HALF_DIAG := 91.0  # 128 m lohkon puolikas lävistäjä: lohkon näkyvyys keskipisteestä
const FAR_HALF_DIAG := 363.0
const MID_RADIUS := 600.0  # lähi- ja keskitason lohkot rakennetaan tämän säteen sisälle
const COLLIDE_RADIUS := 1  # rungot törmäävät pelaajan lohkossa ja sen naapureissa (128 m lohkoja)
const MIN_COLLIDE_H := 2.5  # matalammat (pensaat, taimet) eivät törmää

var count := 0
var far_chunk := 512.0
var near_chunk := 128.0
var nf := 0
var nn := 0
var half := 5120.0
var far_tab := PackedInt32Array()
var near_tab := PackedInt32Array()
var data_a := PackedFloat32Array()  # x, y, z, pituus
var data_b := PackedByteArray()     # säde x40, laji, satunnainen, satunnainen

var _tex_a: ImageTexture
var _tex_b: ImageTexture
var _meshes := {}   # "near"/"mid"/"far" -> [ArrayMesh lajia kohden]
var _built := {}    # Vector2i lähilohko -> [MultiMeshInstance3D]
var _bodies := {}   # Vector2i lähilohko -> StaticBody3D
var _queue: Array[Vector2i] = []
var _last_center := Vector2i(99999, 99999)


func _ready() -> void:
	var f := FileAccess.open(BIN, FileAccess.READ)
	if f == null or f.get_buffer(4).get_string_from_ascii() != "ONP2":
		push_error("Puudataa ei löydy tai versio on väärä (%s): aja tools/kartta/bake.py." % BIN)
		return
	count = f.get_32()
	var w := f.get_32()
	var h := f.get_32()
	far_chunk = f.get_float()
	near_chunk = f.get_float()
	nf = f.get_32()
	nn = f.get_32()
	half = f.get_float()
	far_tab = f.get_buffer(nf * nf * SPECIES * 2 * 4).to_int32_array()
	near_tab = f.get_buffer(nn * nn * SPECIES * 2 * 4).to_int32_array()
	var raw_a := f.get_buffer(w * h * 16)
	var raw_b := f.get_buffer(w * h * 4)
	data_a = raw_a.to_float32_array()
	data_b = raw_b
	# Mökkipihan rakennusten, terassien ja portaiden kohdalta puut pois (matalaksi maan alle).
	for i in count:
		var x := data_a[i * 4]
		var z := data_a[i * 4 + 2]
		if absf(x) < 30.0 and absf(z) < 30.0 and Mokki.clears_tree(x, z):
			data_a[i * 4 + 1] = -50.0
			data_a[i * 4 + 3] = 0.01
	raw_a = data_a.to_byte_array()
	_tex_a = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBAF, raw_a))
	_tex_b = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, raw_b))
	_make_meshes()
	_build_far()


## Pelaajan sijainti: rakentaa lähi- ja keskitason lohkot ympärille (muutama ruudussa) ja törmäykset.
func update_around(p: Vector3) -> void:
	var c := Vector2i(floori((p.x + half) / near_chunk), floori((p.z + half) / near_chunk))
	if c != _last_center:
		_last_center = c
		var r := int(ceil(MID_RADIUS / near_chunk))
		var want := {}
		for j in range(c.y - r, c.y + r + 1):
			for i in range(c.x - r, c.x + r + 1):
				if i < 0 or j < 0 or i >= nn or j >= nn:
					continue
				var k := Vector2i(i, j)
				var mid := Vector2((i + 0.5) * near_chunk - half, (j + 0.5) * near_chunk - half)
				if mid.distance_to(Vector2(p.x, p.z)) > MID_RADIUS + near_chunk:
					continue
				want[k] = true
				if not _built.has(k) and not _queue.has(k):
					_queue.append(k)
		for k in _built.keys():
			if not want.has(k):
				for n in _built[k]:
					n.queue_free()
				_built.erase(k)
		_queue = _queue.filter(func(k: Vector2i) -> bool: return want.has(k))
		# Lähimmät ensin.
		_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - c).length_squared() < (b - c).length_squared())
		_update_bodies(c)
	for _i in 6:
		if _queue.is_empty():
			break
		var k: Vector2i = _queue.pop_front()
		_built[k] = _build_near_chunk(k)


## Lähin puu (rungon paikka) ja sen tiedot: {pos, height, species} tai tyhjä.
func tree_info(i: int) -> Dictionary:
	return {"pos": Vector3(data_a[i * 4], data_a[i * 4 + 1], data_a[i * 4 + 2]), "height": data_a[i * 4 + 3],
		"species": data_b[i * 4 + 1]}


func _range(tab: PackedInt32Array, chunk: int, sp: int) -> Vector2i:
	var k := (chunk * SPECIES + sp) * 2
	return Vector2i(tab[k], tab[k + 1])


# --- Lohkot ---------------------------------------------------------------------------------------------------

func _build_far() -> void:
	for j in nf:
		for i in nf:
			var aabb := AABB(Vector3(i * far_chunk - half, -15.0, j * far_chunk - half), Vector3(far_chunk, 60.0, far_chunk))
			for sp in SPECIES:
				var r := _range(far_tab, j * nf + i, sp)
				if r.y == 0:
					continue
				var mmi := _mmi(_meshes.far[sp], r, aabb)
				mmi.visibility_range_begin = maxf(0.0, MID_END - FAR_HALF_DIAG - 20.0)
				mmi.visibility_range_end = FAR_END
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(mmi)


func _build_near_chunk(k: Vector2i) -> Array:
	var out := []
	var aabb := AABB(Vector3(k.x * near_chunk - half, -15.0, k.y * near_chunk - half), Vector3(near_chunk, 60.0, near_chunk))
	for sp in SPECIES:
		var r := _range(near_tab, k.y * nn + k.x, sp)
		if r.y == 0:
			continue
		# Lohkon näkyvyys on karkea rajaus; varsinainen taso valitaan puukohtaisesti (lod_min/lod_max).
		var near := _mmi(_meshes.near[sp], r, aabb)
		near.visibility_range_end = NEAR_END + NEAR_HALF_DIAG + 10.0
		add_child(near)
		var mid := _mmi(_meshes.mid[sp], r, aabb)
		mid.visibility_range_end = MID_END + NEAR_HALF_DIAG + 10.0
		add_child(mid)
		out.append_array([near, mid])
	return out


## MultiMesh, jonka kaikki instanssit ovat identiteettejä ja custom datana lohkon alku: varjostin sijoittaa
## puut (alku + INSTANCE_ID). Custom data eikä instance uniform, koska yhteensopivuustilassa (selain) niitä
## saa olla vain 4096; alku kahtena alle 2048 lukuna, koska siellä custom data on puolitarkkuutta.
func _mmi(mesh: Mesh, r: Vector2i, aabb: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = r.y
	mm.buffer = _buffer(r.y, r.x)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.custom_aabb = aabb
	return mmi


## n kertaa [identiteettimuunnos (12 lukua), custom data (base % 2048, base / 2048, 0, 0)] tuplaamalla: ei
## silmukkaa instanssien yli.
static func _buffer(n: int, base: int) -> PackedFloat32Array:
	var b := PackedFloat32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, base % 2048, base / 2048, 0, 0])
	while b.size() < n * 16:
		b.append_array(b)
	return b.slice(0, n * 16)


func _update_bodies(c: Vector2i) -> void:
	var want := {}
	for j in range(c.y - COLLIDE_RADIUS, c.y + COLLIDE_RADIUS + 1):
		for i in range(c.x - COLLIDE_RADIUS, c.x + COLLIDE_RADIUS + 1):
			if i >= 0 and j >= 0 and i < nn and j < nn:
				want[Vector2i(i, j)] = true
	for k in _bodies.keys():
		if not want.has(k):
			_bodies[k].queue_free()
			_bodies.erase(k)
	var shape := CylinderShape3D.new()
	shape.radius = 0.22
	shape.height = 4.0
	for k in want:
		if _bodies.has(k):
			continue
		var body := StaticBody3D.new()
		for sp in SPECIES:
			if sp == BUSH:
				continue
			var r := _range(near_tab, k.y * nn + k.x, sp)
			for i in range(r.x, r.x + r.y):
				if data_a[i * 4 + 3] < MIN_COLLIDE_H:
					continue
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.position = Vector3(data_a[i * 4], data_a[i * 4 + 1] + 2.0, data_a[i * 4 + 2])
				body.add_child(cs)
		add_child(body)
		_bodies[k] = body


# --- Puiden mallit --------------------------------------------------------------------------------------------

func _mat(shader: String, params: Dictionary, ref_h: float, ref_r: float) -> ShaderMaterial:
	var p := params.duplicate()
	p.merge({"tree_a": _tex_a, "tree_b": _tex_b, "ref_h": ref_h, "ref_r": ref_r})
	return B.shader_mat(shader, p)


## Mesh, jonka jokaisen pinnan materiaali piirtää puut vain etäisyysvälillä [lo, hi).
static func _lod(am: ArrayMesh, lo: float, hi: float) -> ArrayMesh:
	for i in am.get_surface_count():
		var m: ShaderMaterial = am.surface_get_material(i).duplicate()
		m.set_shader_parameter("lod_min", lo)
		m.set_shader_parameter("lod_max", hi)
		am.surface_set_material(i, m)
	return am


## Mesh osista: [[PrimitiveMesh tai ArrayMesh, paikka, materiaali], ...] -> yksi monipintainen ArrayMesh.
static func _combine(parts: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	for part in parts:
		var st := SurfaceTool.new()
		st.append_from(part[0], 0, Transform3D(Basis(), part[1]))
		st.commit(am)
		am.surface_set_material(am.get_surface_count() - 1, part[2])
	return am


static func _flat_sphere(r: float, hgt: float, seg := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = hgt * 2.0
	s.radial_segments = seg
	s.rings = maxi(3, seg / 2)
	return s


func _make_meshes() -> void:
	var leaf: Texture2D = Foliage.leaf_texture()
	var pine_tex: Texture2D = Foliage.pine_texture()
	var spruce_tex: Texture2D = Foliage.spruce_texture()
	var solid := "res://shaders/tree_solid.gdshader"
	var card := "res://shaders/tree_card.gdshader"
	# Lajikohtaiset värit ja viitemitat (malli tehty pituudelle ref_h ja latvuksen säteelle ref_r).
	var spec := {
		PINE: {"h": 10.5, "r": 2.0, "crown": Color(0.24, 0.38, 0.18), "trunk": Color(0.4, 0.3, 0.22)},
		SPRUCE: {"h": 8.6, "r": 2.2, "crown": Color(0.16, 0.3, 0.16), "trunk": Color(0.32, 0.24, 0.17)},
		BIRCH: {"h": 8.2, "r": 1.9, "crown": Color(0.42, 0.6, 0.25), "trunk": Color.WHITE},
		ASPEN: {"h": 8.2, "r": 1.9, "crown": Color(0.36, 0.52, 0.22), "trunk": Color(0.55, 0.58, 0.5)},
		BUSH: {"h": 8.2, "r": 1.9, "crown": Color(0.34, 0.48, 0.22), "trunk": Color(0.35, 0.3, 0.22)},
	}
	_meshes = {"near": [], "mid": [], "far": []}
	for sp in SPECIES:
		var s: Dictionary = spec[sp]
		var H: float = s.h
		var R: float = s.r
		var crown_m := _mat(solid, {"color": s.crown}, H, R)
		var crown_far := _mat(solid, {"color": Color(s.crown).darkened(0.1)}, H, R)
		var trunk_m: ShaderMaterial
		if sp == BIRCH:
			trunk_m = _mat(solid, {"bark": true, "foliage": false, "trunk": true}, H, R)
		else:
			trunk_m = _mat(solid, {"color": s.trunk, "foliage": false, "trunk": true}, H, R)
		var near := []
		var mid := []
		var far := []
		match sp:
			PINE:
				var upper := _mat(solid, {"color": Color(0.72, 0.42, 0.24), "foliage": false, "trunk": true}, H, R)
				var trunk := [B.cyl(0.13, 0.22, 5.0, 7), Vector3(0, 2.5, 0), trunk_m]
				var top := [B.cyl(0.07, 0.13, 4.6, 6), Vector3(0, 7.3, 0), upper]
				near = [trunk, top, [Foliage.pine_crown(3), Vector3.ZERO,
					_mat(card, {"leaf_tex": pine_tex, "color": s.crown, "sway": 0.05}, H, R)]]
				mid = [trunk, top,
					[_flat_sphere(1.7, 0.9), Vector3(0.2, 9.1, 0), crown_m],
					[_flat_sphere(1.3, 0.8), Vector3(-0.8, 8.3, 0.4), crown_m],
					[_flat_sphere(1.2, 0.7), Vector3(0.7, 8.0, -0.6), crown_m]]
				far = [[B.cyl(0.1, 0.2, 7.0, 4), Vector3(0, 3.5, 0), trunk_m], [_flat_sphere(1.9, 1.3, 6), Vector3(0, 8.9, 0), crown_far]]
			SPRUCE:
				var trunk := [B.cyl(0.15, 0.24, 2.2, 6), Vector3(0, 1.1, 0), trunk_m]
				var inner := _mat(solid, {"color": Color(0.1, 0.2, 0.1)}, H, R)
				near = [trunk, [Foliage.spruce_crown(5), Vector3.ZERO,
					_mat(card, {"leaf_tex": spruce_tex, "color": s.crown, "sway": 0.04}, H, R)],
					[B.cyl(0.0, 1.3, 7.6, 7), Vector3(0, 4.6, 0), inner]]
				mid = [trunk,
					[B.cyl(0.0, 2.1, 3.4, 8), Vector3(0, 2.9, 0), crown_m],
					[B.cyl(0.0, 1.65, 3.0, 8), Vector3(0, 4.6, 0), crown_m],
					[B.cyl(0.0, 1.15, 2.6, 8), Vector3(0, 6.2, 0), crown_m],
					[B.cyl(0.0, 0.6, 1.8, 7), Vector3(0, 7.6, 0), crown_m]]
				far = [[B.cyl(0.0, 2.1, 8.0, 5), Vector3(0, 4.6, 0), crown_far]]
			_:
				var trunk := [B.cyl(0.11, 0.2, 6.0, 7), Vector3(0, 3.0, 0), trunk_m]
				near = [trunk, [Foliage.birch_crown(1 + sp), Vector3.ZERO,
					_mat(card, {"leaf_tex": leaf, "color": s.crown, "sway": 0.08}, H, R)]]
				mid = [trunk,
					[B.sphere(1.6, 8), Vector3(0, 5.9, 0), crown_m],
					[B.sphere(1.3, 8), Vector3(0.9, 5.1, 0.35), crown_m],
					[B.sphere(1.25, 8), Vector3(-0.75, 6.7, -0.35), crown_m]]
				far = [[B.cyl(0.08, 0.18, 4.5, 4), Vector3(0, 2.25, 0), trunk_m], [_flat_sphere(1.9, 2.2, 6), Vector3(0, 5.9, 0), crown_far]]
		_meshes.near.append(_lod(_combine(near), 0.0, NEAR_END))
		_meshes.mid.append(_lod(_combine(mid), NEAR_END, MID_END))
		_meshes.far.append(_lod(_combine(far), MID_END, FAR_END))
