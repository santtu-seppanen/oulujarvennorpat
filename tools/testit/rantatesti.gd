extends SceneTree
## Hiekkarannan ja viinakätkön testi (headless): godot --headless --path . -s tools/testit/rantatesti.gd
## Ylämökin ovelta kävellen kätköpolkua metsän läpi ja rinnettä alas viinakätkölle, kätkön kehote ja huikka,
## kuiva ranta hiekkaa, ja rannasta kävellen järveen: ensin kahlataan, n. 18 m päässä uidaan.

## Kävelee reittipisteitä pitkin samoilla syötteillä kuin tekoäly.
class Follow:
	extends RefCounted
	var body: CharacterBody3D
	var path: Array
	var throttle := 1.0
	var steer := 0.0
	var fast := false
	var jump := false

	func think(_d: float) -> void:
		while path.size() > 1 and Vector2(body.global_position.x - path[0].x, body.global_position.z - path[0].z).length() < 0.6:
			path.pop_front()
		var t: Vector3 = path[0]
		var d := Vector2(t.x - body.global_position.x, t.z - body.global_position.z)
		throttle = 1.0 if d.length() > 0.3 else 0.0
		var want := atan2(-d.x, -d.y)
		steer = clampf(wrapf(want - body.rotation.y, -PI, PI) * 3.0, -1.0, 1.0)


var main: Node3D
var Ranta: GDScript
var Terrain: GDScript
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var waded := false
var swim_at := -1.0
var shore := 0.0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Ranta = load("res://scripts/ranta.gd")
	Terrain = load("res://scripts/terrain.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = clock


func _path(pts: Array) -> Array:
	var out := []
	for q: Vector2 in pts:
		out.append(Vector3(q.x, 0.0, q.y))
	return out


func _process(delta: float) -> bool:
	clock += delta
	if main == null or main.get_script() == null:
		print("VIKA peli ei käynnisty")
		return true
	var t := clock - ts
	var p: CharacterBody3D = main.player
	var r: Node3D = main.world.ranta
	match step:
		0:
			if clock > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 14, 0)
				var s: Vector2 = Ranta.STASH
				print("kätkö (%.1f, %.1f), korkeus %.2f m, rantaviiva x %.1f" % [s.x, s.y, r.stash_pos.y, Ranta.shore_x(s.y)])
				check(r.stash_pos.y > 1.2 and r.stash_pos.y < 4.5, "kätkö rinteessä rannan yläpuolella")
				check(main._compass.has_cache, "kätkö kompassissa")
				var a: Vector3 = main.world.mokki.points.ylamokki_ovi
				p.global_position = a + Vector3.UP * 0.1
				p.velocity = Vector3.ZERO
				p.brain = Follow.new()
				p.brain.body = p
				var path := _path(Ranta.TRAIL)
				# Kätkön kohdalla polulta sivuun kätkölle.
				var i := 13
				path.insert(i, Vector3(s.x + 0.6, 0.0, s.y + 0.4))
				p.brain.path = path.slice(0, i + 1)
				next()
		1:
			if main._near_beach_stash():
				p.brain = null
				print("ylämökiltä kätkölle %.1f s" % t)
				check(true, "kävellen ylämökiltä polkua kätkölle")
				next()
			elif t > 120.0:
				check(false, "jumissa polulla: %s" % [p.global_position])
				p.brain = null
				next()
		2:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("Viinakätkö"), "kätkön kehote: %s" % it.get("text", ""))
				var d0: int = p.drinks
				main._booze()
				check(p.drinks == d0 + 1, "huikka viinaa kätköstä")
				p.promille = 0.0
				# Rinnettä alas rantaan.
				p.brain = Follow.new()
				p.brain.body = p
				p.brain.path = _path(Ranta.TRAIL.slice(13))
				next()
		3:
			if (p.brain.path as Array).size() <= 1 and p.brain.throttle == 0.0:
				var q := p.global_position
				print("rannassa (%.1f, %.1f) pinta %s" % [q.x, q.z, Terrain.SURFACE_NAMES[Terrain.surface(q.x, q.z)]])
				check(Terrain.surface(q.x, q.z) == Terrain.SAND, "polku päättyy hiekkarannalle")
				shore = Ranta.shore_x(q.z)
				# Suoraan ulos järvelle.
				p.brain.path = [Vector3(shore + 40.0, 0.0, q.z)]
				next()
			elif t > 30.0:
				check(false, "ei päästy rantaan: %s" % [p.global_position])
				next()
		4:
			if p.water_depth > 0.3 and not p.swimming:
				waded = true
			if p.swimming:
				swim_at = p.global_position.x - shore
				p.brain = null
				check(waded, "ensin kahlataan")
				print("uimaan %.1f m rannasta, syvyys %.2f m" % [swim_at, p.water_depth])
				check(swim_at > 10.0 and swim_at < 26.0, "uimasyvyys n. 18 m rannasta")
				next()
			elif t > 60.0:
				check(false, "ei päästy uimaan: %s syvyys %.2f" % [p.global_position, p.water_depth])
				next()
		5:
			if t > 2.0:
				check(p.swimming, "uidaan")
				print("vikoja %d" % fails)
				return true
	if clock > 240.0:
		check(false, "aikaraja (vaihe %d)" % step)
		return true
	return false
