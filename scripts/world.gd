extends Node3D
## Maailma oikean kartan mukaan: Äpätti Oulujärven etelärannalla, Vaala (aloituspaikka 64.432089 N,
## 26.886448 E). Kaikki data tools/kartta/bake.py:stä (assets/map/): maasto (MML 2 m korkeusmalli + arvioitu
## järven pohja), pinnat ja kohteet maastotietokannasta (rakennukset tyyppeineen ja laserista mitattuine
## korkeuksineen, tiet, polut, kivet, vesikivet, tervahaudat, linjataulut, veneenlaskupaikat, lammet,
## paikannimet) ja metsä laserkeilauksesta ja VMI:stä (trees.gd).
##
## Tarkka maasto 2 x 2 km (2 m ruutu) on kävelyaluetta; kaukomaasto 10 x 10 km (16 m) ja järvenselkä
## horisonttiin asti näkyvät ympärillä.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Trees := preload("res://scripts/trees.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Ranta := preload("res://scripts/ranta.gd")
const Rantatennis := preload("res://scripts/rantatennis.gd")

const DATA := "res://assets/map/kohteet.json"
const NEAR_CHUNK := 100.0
const NEAR_VIEW := 650.0   # tarkka maastoverkko tähän asti, kauempana kaukoverkko
const FAR_CHUNK := 640.0
const AREA_HALF := 990.0   # kävelyalue (näkymättömät seinät)

var data := {}
var trees: Node3D
var mokki: Node3D
var ranta: Node3D  # hiekkaranta, kätköpolku ja viinakätkö (ranta.gd)
var ponds: Array = []   # [{level, poly: PackedVector2Array}]
var names: Array = []   # [{name, p: Vector2}]
var _near_h_tex: ImageTexture
var _far_h_tex: ImageTexture
var _near_c_tex: ImageTexture
var _far_c_tex: ImageTexture


func _ready() -> void:
	Terrain.ensure()
	Mokki.terraform()
	Ranta.terraform()
	Rantatennis.terraform()
	var f := FileAccess.open(DATA, FileAccess.READ)
	data = JSON.parse_string(f.get_as_text()) if f != null else {}
	if data.is_empty():
		push_error("Kohdedataa ei löydy (%s): aja tools/kartta/bake.py." % DATA)
		return
	data.roads.append(Ranta.trail_road())
	for p in data.ponds:
		ponds.append({"level": float(p.level), "poly": _poly(p.pts)})
	for n in data.names:
		names.append({"name": n.name, "p": Vector2(n.p[0], n.p[1])})
	_build_terrain()
	_build_water()
	_build_roads()
	_build_buildings()
	_build_props()
	_build_walls()
	mokki = Mokki.new()
	add_child(mokki)
	ranta = Ranta.new()
	add_child(ranta)
	trees = Trees.new()
	add_child(trees)


func start_position() -> Vector3:
	var s: Dictionary = data.meta.start
	return Vector3(s.x, Terrain.h(s.x, s.z), s.z)


func sources() -> Array:
	return data.get("meta", {}).get("sources", [])


## Veden pinnan korkeus kohdassa (x, z): Oulujärvi 0, lammet omilla pinnoillaan, kuivalla NAN.
func water_level_at(x: float, z: float) -> float:
	var s := Terrain.surface(x, z)
	if s == Terrain.WATER:
		return 0.0
	if s == Terrain.POND:
		var q := Vector2(x, z)
		for p in ponds:
			if Geometry2D.is_point_in_polygon(q, p.poly):
				return p.level
		return Terrain.h(x, z) + 0.3
	# Rantaviivan maaruuduissa matala vesi, jos maa on järven pinnan alapuolella.
	if Terrain.h(x, z) < 0.0 and (Terrain.is_water(x + 2.0, z) or Terrain.is_water(x - 2.0, z)
			or Terrain.is_water(x, z + 2.0) or Terrain.is_water(x, z - 2.0)):
		return 0.0
	return NAN


## Lähin paikannimi ja etäisyys: {name, dist}.
func nearest_name(p: Vector2) -> Dictionary:
	var best := {"name": "", "dist": INF}
	for n in names:
		var d: float = p.distance_to(n.p)
		if d < best.dist:
			best = {"name": n.name, "dist": d}
	return best


static func _poly(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(Vector2(q[0], q[1]))
	return out


# --- Maasto ---------------------------------------------------------------------------------------------------

func _terrain_mat(sink: float) -> ShaderMaterial:
	# Pintojen värit (a, b) ja kohinan mittakaava luokittain: FOREST, WATER(pohja), SAND, ROCK, BOG, FIELD, YARD,
	# ROAD, PATH, CLEARING, FILL, POND(pohja).
	var a := PackedColorArray([Color(0.27, 0.31, 0.16), Color(0.52, 0.47, 0.34), Color(0.74, 0.67, 0.5),
		Color(0.44, 0.43, 0.41), Color(0.5, 0.46, 0.27), Color(0.47, 0.53, 0.25), Color(0.31, 0.47, 0.18),
		Color(0.52, 0.47, 0.39), Color(0.42, 0.35, 0.25), Color(0.42, 0.38, 0.24), Color(0.56, 0.51, 0.42),
		Color(0.24, 0.21, 0.14)])
	var b := PackedColorArray([Color(0.4, 0.38, 0.22), Color(0.6, 0.55, 0.4), Color(0.84, 0.78, 0.6),
		Color(0.58, 0.56, 0.52), Color(0.4, 0.43, 0.23), Color(0.6, 0.6, 0.31), Color(0.4, 0.56, 0.24),
		Color(0.63, 0.58, 0.48), Color(0.52, 0.44, 0.32), Color(0.53, 0.47, 0.3), Color(0.64, 0.6, 0.5),
		Color(0.32, 0.28, 0.19)])
	var sc := PackedFloat32Array([0.035, 0.05, 0.06, 0.08, 0.03, 0.02, 0.04, 0.1, 0.08, 0.03, 0.06, 0.05])
	return B.shader_mat("res://shaders/terrain.gdshader", {
		"near_h": _near_h_tex, "far_h": _far_h_tex, "near_c": _near_c_tex, "far_c": _far_c_tex,
		"near_half": Terrain.near.half, "near_step": Terrain.near.step,
		"far_half": Terrain.far.half, "far_step": Terrain.far.step,
		"open_depth": Terrain.OPEN_LAKE_DEPTH, "sink": sink,
		"col_a": a, "col_b": b, "scale": sc,
	})


func _build_terrain() -> void:
	_near_h_tex = ImageTexture.create_from_image(Terrain.height_image(Terrain.near))
	_far_h_tex = ImageTexture.create_from_image(Terrain.height_image(Terrain.far))
	_near_c_tex = ImageTexture.create_from_image(Terrain.class_image(Terrain.near))
	_far_c_tex = ImageTexture.create_from_image(Terrain.class_image(Terrain.far))
	# Tarkka verkko: 100 m lohkot, pisteet täsmälleen korkeusmallin pikseleissä; näkyy NEAR_VIEW asti.
	var near_mat := _terrain_mat(0.0)
	var nh: float = Terrain.near.half
	var plane := PlaneMesh.new()
	plane.size = Vector2(NEAR_CHUNK, NEAR_CHUNK)
	plane.subdivide_width = int(NEAR_CHUNK / Terrain.near.step) - 1
	plane.subdivide_depth = plane.subdivide_width
	var n := int(nh * 2.0 / NEAR_CHUNK)
	for j in n:
		for i in n:
			var mi := MeshInstance3D.new()
			mi.mesh = plane
			mi.material_override = near_mat
			mi.position = Vector3(-nh + (i + 0.5) * NEAR_CHUNK, 0, -nh + (j + 0.5) * NEAR_CHUNK)
			mi.custom_aabb = AABB(Vector3(-NEAR_CHUNK / 2, -20, -NEAR_CHUNK / 2), Vector3(NEAR_CHUNK, 80, NEAR_CHUNK))
			mi.visibility_range_end = NEAR_VIEW
			mi.visibility_range_end_margin = 30.0
			add_child(mi)
	# Kaukoverkko koko 10 x 10 km alueelle, lähialueella hieman tarkan verkon alla.
	var far_mat := _terrain_mat(0.35)
	var fh: float = Terrain.far.half
	var fplane := PlaneMesh.new()
	fplane.size = Vector2(FAR_CHUNK, FAR_CHUNK)
	fplane.subdivide_width = int(FAR_CHUNK / Terrain.far.step) - 1
	fplane.subdivide_depth = fplane.subdivide_width
	var m := int(fh * 2.0 / FAR_CHUNK)
	for j in m:
		for i in m:
			var mi := MeshInstance3D.new()
			mi.mesh = fplane
			mi.material_override = far_mat
			mi.position = Vector3(-fh + (i + 0.5) * FAR_CHUNK, 0, -fh + (j + 0.5) * FAR_CHUNK)
			mi.custom_aabb = AABB(Vector3(-FAR_CHUNK / 2, -20, -FAR_CHUNK / 2), Vector3(FAR_CHUNK, 80, FAR_CHUNK))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	# Törmäys: tarkan ruudukon korkeuskartta sellaisenaan.
	var body := StaticBody3D.new()
	body.collision_layer = Terrain.COLLISION_LAYER
	body.collision_mask = 0
	var hm := HeightMapShape3D.new()
	hm.map_width = Terrain.near.n
	hm.map_depth = Terrain.near.n
	hm.map_data = Terrain.near.heights
	var cs := CollisionShape3D.new()
	cs.shape = hm
	cs.scale = Vector3(Terrain.near.step, 1.0, Terrain.near.step)
	body.add_child(cs)
	add_child(body)


# --- Vesi -----------------------------------------------------------------------------------------------------

func _build_water() -> void:
	var lake := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000, 40000)
	pm.subdivide_width = 63
	pm.subdivide_depth = 63
	lake.mesh = pm
	lake.material_override = B.shader_mat("res://shaders/lake.gdshader", {
		"clip_land": true, "near_c": _near_c_tex, "far_c": _far_c_tex,
		"near_half": Terrain.near.half, "near_step": Terrain.near.step,
		"far_half": Terrain.far.half, "far_step": Terrain.far.step})
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)
	var pond_mat := B.shader_mat("res://shaders/lake.gdshader", {"deep": Color(0.05, 0.07, 0.05),
		"shallow": Color(0.18, 0.2, 0.12), "clarity": 1.1})
	for p in ponds:
		var poly: PackedVector2Array = p.poly
		var idx := Geometry2D.triangulate_polygon(poly)
		if idx.is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		for i in idx:
			st.add_vertex(Vector3(poly[i].x, p.level, poly[i].y))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = pond_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# Laineiden loiske rannassa aloituspaikalla.
	var s := start_position()
	Sfx.loop_on(self, "water", -12.0).position = Vector3(s.x, 0.0, s.z - 12.0)


# --- Tiet ja polut --------------------------------------------------------------------------------------------

const ROAD_STYLE := {
	"highway": [3.7, Color(0.2, 0.2, 0.21)], "main": [3.2, Color(0.22, 0.22, 0.23)],
	"road": [2.6, Color(0.55, 0.5, 0.42)], "drive": [1.9, Color(0.55, 0.5, 0.42)],
	"track": [1.3, Color(0.46, 0.4, 0.3)], "path": [0.55, Color(0.42, 0.34, 0.24)],
	"cycleway": [1.25, Color(0.24, 0.24, 0.25)],
}


func _build_roads() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lim: float = Terrain.far.half
	for r in data.roads:
		var style: Array = ROAD_STYLE.get(r.kind, ROAD_STYLE.drive)
		var w: float = style[0]
		var col: Color = style[1]
		if r.get("paved", false) and r.kind in ["road", "drive"]:
			col = Color(0.22, 0.22, 0.23)
		var pts := _poly(r.pts)
		for k in pts.size() - 1:
			var a := pts[k]
			var b := pts[k + 1]
			if absf(a.x) > lim or absf(a.y) > lim:
				continue
			var segs := maxi(1, int(a.distance_to(b) / 2.0))
			var nrm := (b - a).normalized().orthogonal()
			for s in segs:
				var p0 := a.lerp(b, float(s) / segs)
				var p1 := a.lerp(b, float(s + 1) / segs)
				_road_quad(st, p0, p1, nrm, w, col)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = B.shader_mat("res://shaders/road.gdshader")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Tien pala: reunat (UV.x 0) ja keskiviiva (UV.x 1), jokainen piste maaston pinnasta hieman koholla.
func _road_quad(st: SurfaceTool, p0: Vector2, p1: Vector2, nrm: Vector2, w: float, col: Color) -> void:
	var lift := 0.06
	var v := func(p: Vector2, u: float) -> void:
		st.set_color(col)
		st.set_uv(Vector2(u, 0))
		st.add_vertex(Vector3(p.x, Terrain.h(p.x, p.y) + lift, p.y))
	for side: float in [-1.0, 1.0]:
		var e0 := p0 + nrm * w * side
		var e1 := p1 + nrm * w * side
		v.call(p0, 1.0)
		v.call(e0, 0.0)
		v.call(e1, 0.0)
		v.call(p0, 1.0)
		v.call(e1, 0.0)
		v.call(p1, 1.0)


# --- Rakennukset ----------------------------------------------------------------------------------------------

const WALL_COLORS := {
	"home": [Color(0.86, 0.74, 0.45), Color(0.82, 0.82, 0.78), Color(0.55, 0.18, 0.12), Color(0.9, 0.88, 0.82)],
	"cottage": [Color(0.55, 0.16, 0.11), Color(0.5, 0.15, 0.1), Color(0.35, 0.28, 0.2)],
	"shed": [Color(0.5, 0.17, 0.12), Color(0.45, 0.42, 0.38), Color(0.4, 0.33, 0.25)],
}
const ROOF_COLORS := [Color(0.18, 0.18, 0.19), Color(0.3, 0.12, 0.1), Color(0.25, 0.25, 0.27), Color(0.32, 0.26, 0.2)]


func _build_buildings() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 64432
	var body := StaticBody3D.new()
	for bd in data.buildings:
		var pts := _poly(bd.pts)
		if pts.size() < 3:
			continue
		var mid := Vector2.ZERO
		for q in pts:
			mid += q / pts.size()
		if Mokki.clears_tree(mid.x, mid.y):
			continue  # mökkipihan sauna ja ylämökki mallinnettu tarkemmin (mokki.gd)
		if Geometry2D.is_polygon_clockwise(pts):
			pts.reverse()
		var base := INF
		for q in pts:
			base = minf(base, Terrain.h(q.x, q.y))
		var ridge: float = float(bd.h)
		var walls_c: Array = WALL_COLORS.get(bd.kind, WALL_COLORS.shed)
		var wall: Color = walls_c[rng.randi() % walls_c.size()]
		var roof: Color = ROOF_COLORS[rng.randi() % ROOF_COLORS.size()]
		var trim := Color(0.92, 0.9, 0.85) if bd.kind != "shed" else wall.darkened(0.2)
		var eave := base + clampf(ridge - 1.6, 2.2, 3.4) if pts.size() == 4 else base + clampf(ridge, 2.2, 6.0)
		# Seinät (sokkeli maan alle asti).
		for k in pts.size():
			var a := pts[k]
			var b := pts[(k + 1) % pts.size()]
			_quad(st, Vector3(a.x, base - 0.5, a.y), Vector3(b.x, base - 0.5, b.y), Vector3(b.x, eave, b.y),
				Vector3(a.x, eave, a.y), wall)
			if bd.kind != "shed":
				_windows(st, a, b, base, eave, trim)
		if pts.size() == 4:
			_gable_roof(st, pts, eave, base + maxf(ridge, eave - base + 0.8), roof, wall)
		else:
			var idx := Geometry2D.triangulate_polygon(pts)
			for i in range(0, idx.size(), 3):
				for t in [0, 2, 1]:
					st.set_color(roof)
					st.add_vertex(Vector3(pts[idx[i + t]].x, eave, pts[idx[i + t]].y))
		var shape := ConvexPolygonShape3D.new()
		var cloud := PackedVector3Array()
		for q in pts:
			cloud.append(Vector3(q.x, base - 0.5, q.y))
			cloud.append(Vector3(q.x, eave, q.y))
		shape.points = cloud
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # seinien kiertosuunta vaihtelee pohjapiirroksen mukaan
	mi.material_override = mat
	add_child(mi)
	add_child(body)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	for v in [a, c, b, a, d, c]:
		st.set_color(col)
		st.add_vertex(v)


## Ikkunat seinälle (ulospäin hieman irti seinästä): tumma lasi valkoisissa karmeissa.
func _windows(st: SurfaceTool, a: Vector2, b: Vector2, base: float, eave: float, trim: Color) -> void:
	var length := a.distance_to(b)
	if length < 2.5 or eave - base < 2.0:
		return
	var dir := (b - a) / length
	var out := Vector2(dir.y, -dir.x) * 0.04
	var cnt := int(length / 3.2)
	for k in cnt:
		var c := a + dir * (length * (k + 0.5) / cnt) + out
		var y0 := base + 0.9
		var y1 := minf(base + 2.1, eave - 0.3)
		for frame in [[0.62, trim, 0.0], [0.5, Color(0.12, 0.15, 0.18), 0.01]]:
			var hw: float = frame[0]
			var p0 := c - dir * hw + out * (frame[2] as float) * 25.0
			var p1 := c + dir * hw + out * (frame[2] as float) * 25.0
			var shrink: float = 0.62 - hw
			_quad(st, Vector3(p0.x, y0 + shrink, p0.y), Vector3(p1.x, y0 + shrink, p1.y),
				Vector3(p1.x, y1 - shrink, p1.y), Vector3(p0.x, y1 - shrink, p0.y), frame[1])


## Harjakatto suorakaiteen pitkän sivun suuntaan, räystäät 0,4 m yli, päädyt seinän värisinä.
func _gable_roof(st: SurfaceTool, p: PackedVector2Array, eave: float, ridge: float, roof: Color, gable: Color) -> void:
	var long_first := p[0].distance_to(p[1]) >= p[1].distance_to(p[2])
	var q := p if long_first else PackedVector2Array([p[1], p[2], p[3], p[0]])
	# q0-q1 ja q2-q3 pitkät sivut; harja niiden keskeltä.
	var m0 := (q[0] + q[3]) / 2.0
	var m1 := (q[1] + q[2]) / 2.0
	var along := (m1 - m0).normalized() * 0.4
	var r0 := Vector3(m0.x - along.x, ridge, m0.y - along.y)
	var r1 := Vector3(m1.x + along.x, ridge, m1.y + along.y)
	var e := func(v: Vector2, toward_ridge: Vector2, ext: Vector2) -> Vector3:
		var o := (v - toward_ridge).normalized() * 0.4
		return Vector3(v.x + o.x + ext.x, eave - 0.25, v.y + o.y + ext.y)
	var a0: Vector3 = e.call(q[0], m0, -along)
	var a1: Vector3 = e.call(q[1], m1, along)
	var b0: Vector3 = e.call(q[3], m0, -along)
	var b1: Vector3 = e.call(q[2], m1, along)
	for tri in [[a0, a1, r1], [a0, r1, r0], [b1, b0, r0], [b1, r0, r1]]:
		for v in tri:
			st.set_color(roof)
			st.add_vertex(v)
		for v in [tri[0], tri[2], tri[1]]:  # alapinta
			st.set_color(roof.darkened(0.3))
			st.add_vertex(v)
	# Päätykolmiot.
	for tri in [[q[0], q[3], m0], [q[2], q[1], m1]]:
		var t0 := Vector3(tri[0].x, eave, tri[0].y)
		var t1 := Vector3(tri[1].x, eave, tri[1].y)
		var t2 := Vector3(tri[2].x, ridge - 0.05, tri[2].y)
		for v in [t0, t1, t2, t0, t2, t1]:
			st.set_color(gable)
			st.add_vertex(v)


# --- Pienet kohteet -------------------------------------------------------------------------------------------

func _build_props() -> void:
	var batch := B.Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var body := StaticBody3D.new()
	# Siirtolohkareet ja vesikivet (maastotietokanta).
	for list in [data.stones, data.water_rocks]:
		for q in list:
			var x: float = q[0]
			var z: float = q[1]
			var r := rng.randf_range(0.9, 1.6)
			var y := Terrain.h(x, z)
			if list == data.water_rocks:
				y = minf(y, -0.3)
				r = maxf(r, 0.4 - y)
			batch.add(B.sphere(r, 7), Transform3D(Basis.from_euler(Vector3(rng.randf(), rng.randf() * TAU, 0))
				.scaled(Vector3(1.2, 0.75, 1.0)), Vector3(x, y + r * 0.3, z)), Color(0.45, 0.44, 0.42))
			var cs := CollisionShape3D.new()
			var sph := SphereShape3D.new()
			sph.radius = r * 0.9
			cs.shape = sph
			cs.position = Vector3(x, y + r * 0.3, z)
			body.add_child(cs)
	# Tervahaudat: maavalli renkaana ja kuoppa (näkyvät maastossa matalina kumpareina).
	for q in data.tar_pits:
		var x: float = q[0]
		var z: float = q[1]
		var y := Terrain.h(x, z)
		for k in 14:
			var a := TAU * k / 14.0
			var p := Vector3(x + cos(a) * 4.5, y - 0.1, z + sin(a) * 4.5)
			batch.add(B.sphere(1.3, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.45, 1.0)).rotated(Vector3.UP, -a), p),
				Color(0.3, 0.27, 0.17))
		batch.add(B.cyl(3.6, 3.2, 0.1, 12), Transform3D(Basis(), Vector3(x, y - 0.02, z)), Color(0.12, 0.1, 0.08))
	# Linjataulut (väylän johtoloistot): pylväs ja oranssi-musta taulu.
	for q in data.beacons:
		var x: float = q[0]
		var z: float = q[1]
		var y := maxf(Terrain.h(x, z), 0.0)
		batch.add(B.cyl(0.12, 0.15, 7.0, 6), Transform3D(Basis(), Vector3(x, y + 3.5, z)), Color(0.35, 0.3, 0.25))
		batch.add(B.boxm(Vector3(1.4, 2.2, 0.08)), Transform3D(Basis(), Vector3(x, y + 6.0, z)), Color(0.95, 0.45, 0.05))
		batch.add(B.boxm(Vector3(0.3, 2.2, 0.1)), Transform3D(Basis(), Vector3(x, y + 6.0, z)), Color(0.08, 0.08, 0.08))
	# Veneenlaskupaikat: betoniramppi rannasta veteen.
	for q in data.slipways:
		var x: float = q[0]
		var z: float = q[1]
		var to_water := _towards_water(Vector2(x, z))
		var mid := Vector2(x, z) + to_water * 3.0
		var yaw := atan2(to_water.x, to_water.y)
		var y := Terrain.h(mid.x, mid.y)
		batch.add(B.boxm(Vector3(3.5, 0.25, 10.0)), Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.09),
			Vector3(mid.x, y, mid.y)), Color(0.62, 0.6, 0.56))
	# Puomit.
	for q in data.barriers:
		var x: float = q[0]
		var z: float = q[1]
		var y := Terrain.h(x, z)
		batch.add(B.cyl(0.08, 0.08, 1.0, 6), Transform3D(Basis(), Vector3(x - 2.0, y + 0.5, z)), Color(0.9, 0.9, 0.85))
		batch.add(B.boxm(Vector3(4.2, 0.1, 0.1)), Transform3D(Basis(), Vector3(x, y + 0.95, z)), Color(0.85, 0.15, 0.1))
	if not batch.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = batch.commit()
		mi.material_override = B.vcol_mat()
		add_child(mi)
	add_child(body)
	# Paikannimet opasteina (asetus "Näytä opasteet").
	for n in names:
		var p: Vector2 = n.p
		B.guide(self, n.name, Vector3(p.x, maxf(Terrain.h(p.x, p.y), 0.0) + 12.0, p.y), 160, Color(1, 0.95, 0.8))


## Suunta lähimpään veteen (8 suuntaa, 30 m säteellä).
func _towards_water(p: Vector2) -> Vector2:
	for dist in [4.0, 8.0, 15.0, 30.0]:
		for k in 8:
			var d := Vector2.from_angle(TAU * k / 8.0)
			if Terrain.is_water(p.x + d.x * dist, p.y + d.y * dist):
				return d
	return Vector2(0, -1)


func _build_walls() -> void:
	for k in 4:
		var wall := StaticBody3D.new()
		var d := Vector2.from_angle(PI * 0.5 * k)
		wall.position = Vector3(d.x * AREA_HALF, 0, d.y * AREA_HALF)
		wall.rotation.y = -PI * 0.5 * k
		wall.add_child(B.box_shape(Vector3(1.0, 200.0, AREA_HALF * 2.0)))
		add_child(wall)
