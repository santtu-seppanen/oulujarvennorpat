extends CharacterBody3D
## Kumivene (valokuvan keltainen kahden hengen vene, n. 1,9 x 1,0 m): putki pyöreäkulmaisena renkaana, keltainen
## yläpinta, oranssi-punainen raita, vaalea pohja, kahvanarut ja airot hankaimissa. Kelluu Oulujärven pinnalla
## ja keinuu laineissa; matalikossa ja laituria vasten pysähtyy (törmää maastoon ja rakenteisiin).
##
## Soutaja istuu keskellä selkä keulaan päin ja vetää airoja (W eteen, S taakse, A/D kääntää: toinen airo
## vetää ja toinen työntää). Airojen lavat ja soutajan kädet kulkevat soutuvedon mukana (IK).

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")

const LENGTH := 1.9
const WIDTH := 1.0
const TUBE := 0.17
const MAX_SPEED := 1.5
const STROKE_TIME := 1.5  # yksi soutuveto (s)
const DRIVE := 0.45       # vedon osuus syklistä
## Hankaimet veneen avaruudessa (keula -Z) ja soutajan paikka (istuu pohjalla, kasvot perään).
const OARLOCK := Vector3(0.47, 0.16, 0.12)
const SEAT := Vector3(0.0, -0.5, -0.22)
const OAR_LEN := 1.45
const INBOARD := 0.42  # kädensijasta hankaimeen

var rower: Node3D = null  # on_foot.gd, kun joku soutaa
var speed := 0.0
var yaw_rate := 0.0
var phase := 0.0
var _oars: Array[Node3D] = []
var _hull: Node3D
var _t := 0.0
var _splash_t := 0.0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_mask = 1 | Terrain.COLLISION_LAYER
	var shape := BoxShape3D.new()
	shape.size = Vector3(WIDTH, 0.3, LENGTH)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.06
	add_child(cs)
	_hull = Node3D.new()
	add_child(_hull)
	var mi := MeshInstance3D.new()
	mi.mesh = _hull_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.45
	mat.metallic_specular = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	_hull.add_child(mi)
	for s: float in [-1.0, 1.0]:
		var oar := Node3D.new()
		_hull.add_child(oar)
		# Airo: varsi +Z-suuntaan kädensijasta, lapa päässä.
		B.mesh(oar, B.cyl(0.018, 0.018, OAR_LEN, 6), Vector3(0, 0, OAR_LEN * 0.5), Color(0.95, 0.55, 0.1), Vector3(90, 0, 0))
		B.mesh(oar, B.boxm(Vector3(0.15, 0.012, 0.42)), Vector3(0, 0, OAR_LEN - 0.18), Color(0.08, 0.08, 0.08))
		B.mesh(oar, B.cyl(0.024, 0.024, 0.16, 6), Vector3(0, 0, 0.06), Color(0.08, 0.08, 0.08), Vector3(90, 0, 0))
		oar.set_meta("side", s)
		_oars.append(oar)
		# Hankain.
		B.mesh(_hull, B.boxm(Vector3(0.06, 0.08, 0.1)), Vector3(OARLOCK.x * s, OARLOCK.y - 0.02, OARLOCK.z), Color(0.1, 0.1, 0.1))
	_pose_oars(0.0, 0.0)


## Kelluva keskikohta: veden pinta + keinunta.
func _physics_process(delta: float) -> void:
	_t += delta
	var throttle := 0.0
	var steer := 0.0
	if rower != null and rower.controls_enabled:
		throttle = rower.input_throttle()
		steer = rower.input_steer()
	var rowing := absf(throttle) > 0.05 or absf(steer) > 0.05
	if rowing:
		phase = fmod(phase + delta / STROKE_TIME, 1.0)
	else:
		phase = move_toward(phase, 0.75, delta * 0.5)  # airot lepoasentoon
	var in_drive := rowing and phase < DRIVE
	# Vedon aikana työntö, muuten veden vastus.
	if in_drive:
		var pull := sin(phase / DRIVE * PI)
		speed += throttle * pull * 2.4 * delta
		yaw_rate += steer * pull * 2.6 * delta
	speed -= speed * 0.55 * delta
	yaw_rate -= yaw_rate * 2.2 * delta
	speed = clampf(speed, -MAX_SPEED * 0.6, MAX_SPEED)
	rotation.y += yaw_rate * delta
	var fwd := -global_transform.basis.z
	velocity = Vector3(fwd.x, 0, fwd.z) * speed
	# Matalikko: keula tai perä karilla -> pysähtyy siihen suuntaan.
	var probe := global_position + Vector3(fwd.x, 0, fwd.z) * signf(speed) * (LENGTH * 0.5 + 0.1)
	if Terrain.h(probe.x, probe.z) > -0.06 and absf(speed) > 0.01:
		velocity = Vector3.ZERO
		speed *= 0.3
	move_and_slide()
	if get_slide_collision_count() > 0:
		speed *= 0.8
	# Kelluminen ja keinunta.
	var p := global_position
	var water := 0.0
	var ground := Terrain.h(p.x, p.z)
	var y := maxf(water + 0.02 * sin(_t * 1.7) + 0.015 * sin(_t * 2.9 + 1.0), ground + 0.12)
	global_position.y = y
	_hull.rotation.x = 0.03 * sin(_t * 1.3) + (0.04 * sin(phase * TAU) if rowing else 0.0)
	_hull.rotation.z = 0.035 * sin(_t * 1.1 + 0.5)
	_pose_oars(phase if rowing else -1.0, steer)
	if rowing and phase < DRIVE:
		_splash_t -= delta
		if _splash_t <= 0.0:
			_splash_t = STROKE_TIME
			Sfx.play_on(self, "water", -10.0, randf_range(1.2, 1.5))


## Kädensijojen paikat veneen avaruudessa soutuvaiheen mukaan (-1 = airot lepäävät).
func handle_pos(side: float, ph: float, steer := 0.0) -> Vector3:
	var lock := Vector3(OARLOCK.x * side, OARLOCK.y, OARLOCK.z)
	if ph < 0.0:
		return lock + Vector3(-side * 0.32, 0.12, -0.22)
	# Toinen airo vastavaiheessa käännettäessä paikallaan.
	var p := ph
	if absf(steer) > 0.05 and side * steer > 0.0:
		p = fmod(1.0 - ph + DRIVE, 1.0)
	var t: float
	var lift: float
	if p < DRIVE:
		t = p / DRIVE              # veto: kädet perästä (ojennettu) rintaan
		lift = 0.0
	else:
		t = 1.0 - (p - DRIVE) / (1.0 - DRIVE)  # palautus
		lift = 1.0
	var reach := lerpf(0.42, -0.2, smoothstep(0.0, 1.0, t))
	return Vector3(side * 0.23, OARLOCK.y + 0.18 - lift * 0.1, OARLOCK.z + reach)


func _pose_oars(ph: float, steer: float) -> void:
	for oar in _oars:
		var side: float = oar.get_meta("side")
		var h := handle_pos(side, ph, steer)
		var lock := Vector3(OARLOCK.x * side, OARLOCK.y, OARLOCK.z)
		var dir := (lock - h).normalized()
		oar.position = h
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
		oar.basis = Basis.looking_at(-dir, up)


## Rengasmainen putki, pohja ja kahvanarut yhtenä meshinä.
func _hull_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := WIDTH * 0.5 - TUBE           # putken keskiviivan puolileveys
	var s := LENGTH * 0.5 - WIDTH * 0.5   # suoran osan puolipituus
	var ring := []
	# Keskiviiva: suorat sivut + puoliympyrät keulassa ja perässä (pituussuunta z).
	var n_side := 8
	var n_end := 14
	for i in n_side + 1:
		ring.append(Vector2(a, lerpf(s, -s, float(i) / n_side)))
	for i in range(1, n_end):
		var t := PI * float(i) / n_end
		ring.append(Vector2(cos(t) * a, -s - sin(t) * a * 1.15))
	for i in n_side + 1:
		ring.append(Vector2(-a, lerpf(-s, s, float(i) / n_side)))
	for i in range(1, n_end):
		var t := PI + PI * float(i) / n_end
		ring.append(Vector2(cos(t) * a, s - sin(t) * a))
	var seg := 14
	var yellow := Color(0.98, 0.83, 0.12)
	var orange := Color(0.98, 0.42, 0.12)
	var red := Color(0.9, 0.25, 0.12)
	var white := Color(0.93, 0.91, 0.84)
	var m := ring.size()
	var pts := []
	var cols := []
	var nrms := []
	for i in m:
		var c: Vector2 = ring[i]
		var nx: Vector2 = (ring[(i + 1) % m] - ring[(i - 1 + m) % m]).normalized()
		var outv := Vector2(nx.y, -nx.x)  # ulospäin (kierto vastapäivään ylhäältä)
		if outv.dot(c) < 0.0:
			outv = -outv
		var row := []
		var crow := []
		var nrow := []
		for k in seg:
			var th := TAU * k / seg
			var o3 := Vector3(outv.x, 0, outv.y) * cos(th) * TUBE + Vector3.UP * sin(th) * TUBE
			row.append(Vector3(c.x, 0.06, c.y) + o3)
			nrow.append(o3.normalized())
			var col := yellow
			if sin(th) < -0.35:
				col = white
			elif cos(th) > 0.55 and sin(th) < 0.35 and sin(th) > -0.1:
				# Raita sivulla; keulassa vinoviivat (valokuvan "tiikeriraidat").
				col = orange if absf(c.y) < s + 0.05 or sin(c.y * 40.0) > 0.0 else red
			elif cos(th) > 0.55 and sin(th) >= 0.35 and sin(th) < 0.6:
				col = red
			crow.append(col)
		pts.append(row)
		cols.append(crow)
		nrms.append(nrow)
	for i in m:
		var j := (i + 1) % m
		for k in seg:
			var l := (k + 1) % seg
			for v in [[i, k], [j, k], [j, l], [i, k], [j, l], [i, l]]:
				st.set_color(cols[v[0]][v[1]])
				st.set_normal(nrms[v[0]][v[1]])
				st.add_vertex(pts[v[0]][v[1]])
	# Pohja: tasainen kalvo putken alareunassa.
	var fy := -0.08
	for i in m:
		var c0: Vector2 = ring[i]
		var c1: Vector2 = ring[(i + 1) % m]
		for v in [Vector3.ZERO, Vector3(c1.x, 0, c1.y), Vector3(c0.x, 0, c0.y)]:
			st.set_color(white.darkened(0.1))
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3(0, fy, 0))
	# Kahvanarut (mustat) putken päällä neljässä kohdassa.
	for q in [Vector2(a, 0.4), Vector2(-a, 0.4), Vector2(a, -0.55), Vector2(-a, -0.55)]:
		var base := Vector3(q.x, 0.06 + TUBE, q.y)
		for k in 6:
			var t0 := PI * k / 6.0
			var t1 := PI * (k + 1) / 6.0
			var p0 := base + Vector3(0, sin(t0) * 0.05, cos(t0) * 0.07)
			var p1 := base + Vector3(0, sin(t1) * 0.05, cos(t1) * 0.07)
			for v in [p0, p1, p1 + Vector3(0.02, 0, 0), p0, p1 + Vector3(0.02, 0, 0), p0 + Vector3(0.02, 0, 0)]:
				st.set_color(Color(0.05, 0.05, 0.05))
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	return st.commit()
