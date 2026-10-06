extends SceneTree
## Huussin ja rinteen testi (headless): godot --headless --path . -s tools/testit/huussitesti.gd
## Saunan ovelta kävellen saunan takaa (halkopinon ohi) ja pitkospuita pitkin huussille rinteen reunaan, huussin
## minipeli (ykkönen) sisään ja ulos, sekä virtsaus rinteeseen pitkospuiden alussa: Markon kaari n. 5 m,
## Santun n. 2 m. Lopuksi tarkistetaan, ettei järven puoleiselta itäterassilta pääse huussin pitkospuille.

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
		while path.size() > 1 and Vector2(body.global_position.x - path[0].x, body.global_position.z - path[0].z).length() < 0.35:
			path.pop_front()
		var t: Vector3 = path[0]
		var d := Vector2(t.x - body.global_position.x, t.z - body.global_position.z)
		var want := atan2(-d.x, -d.y)
		var turn := wrapf(want - body.rotation.y, -PI, PI)
		steer = clampf(turn * 3.0, -1.0, 1.0)
		throttle = (1.0 if absf(turn) < 0.5 else 0.0) if d.length() > 0.2 else 0.0  # ensin käännytään


var main: Node3D
var Mokki: GDScript
var fails := 0
var step := 0
var clock := 0.0  # pelin aika (headless --fixed-fps ajaa seinäkelloa nopeammin)
var ts := 0.0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Mokki = load("res://scripts/mokki.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func now() -> float:
	return clock


func next() -> void:
	step += 1
	ts = now()


## Pelaaja pitkospuiden alkuun katse alamäkeen (itään ja järvelle päin).
func _to_pee_spot(p: CharacterBody3D) -> void:
	var q: Vector2 = Mokki.PEE_SPOT
	var w: Vector2 = Mokki.yw(q.x, q.y)
	var y: float = Mokki.duck_y(q, q.distance_to(Mokki.DUCKBOARDS[0]))
	p.global_position = Vector3(w.x, y + 0.1, w.y)
	var d: Vector2 = Mokki.EAST * 0.8 + Mokki.LAKE * 0.6
	p.rotation.y = atan2(-d.x, -d.y)
	p.velocity = Vector3.ZERO


func _process(delta: float) -> bool:
	clock += delta
	if main == null or main.get_script() == null:
		print("VIKA peli ei käynnisty")
		return true
	var t := now() - ts
	var p: CharacterBody3D = main.player
	var m: Node3D = main.world.mokki
	match step:
		0:
			if now() > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 13, 0)
				var route: Array = m.route(m.points.sauna_ovi, "huussi")
				print("reitti saunan ovelta huussille: %d pistettä" % route.size())
				check(route.has(m.points.takana_l) and not route.has(m.points.itaterassi), "reitti kulkee saunan takaa")
				# Muut pois kulkureitiltä (testikävelijä ei väistä): pääterassin länsipäähän paikoilleen.
				for c in main.crew:
					if c != p:
						c.brain = null
						var w: Vector2 = Mokki.yw(-9.5, -2.5 + 1.2 * main.crew.find(c))
						c.global_position = Vector3(w.x, Mokki.DY + 0.1, w.y)
						c.velocity = Vector3.ZERO
				var a: Vector3 = m.points.sauna_ovi
				p.global_position = a + Vector3.UP * 0.1
				p.velocity = Vector3.ZERO
				p.brain = Follow.new()
				p.brain.body = p
				p.brain.path = route.slice(1)
				next()
		1:
			if Mokki.at_outhouse(p.global_position) and (p.brain.path as Array).size() <= 1:
				p.brain = null
				print("huussille %.1f s, korkeus %.2f (lattia %.2f)" % [t, p.global_position.y, Mokki.outhouse_y()])
				check(true, "saunan ovelta kävellen huussille")
				next()
			elif t > 45.0:
				check(false, "jumissa matkalla huussille: %s" % [Mokki.wy(Vector2(p.global_position.x, p.global_position.z))])
				for c in main.crew:
					print("  %s %s %s" % [c.display_name, Mokki.wy(Vector2(c.global_position.x, c.global_position.z)), c.brain.get("activity") if c.brain != null else ""])
				p.brain = null
				next()
		2:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("huussiin"), "huussin kehote: %s" % it.get("text", ""))
				var d: Vector3 = Mokki.outhouse_door()
				p.global_position = d + Vector3.UP * 0.05
				main._start_wc("ykkonen")
				next()
		3:
			if t > 1.0:
				check(main.wc != null and p.hidden_inside and not p.controls_enabled, "huussissa: minipeli käynnissä, hahmo sisällä")
				main.wc._finish()
				next()
		4:
			if t > 0.5:
				check(main.wc == null and not p.hidden_inside and p.controls_enabled, "huussista ulos")
				check(Mokki.at_outhouse(p.global_position), "oven edessä pitkospuilla")
				main.choose_character(1)
				next()
		5:
			if t > 0.5:
				p = main.player
				_to_pee_spot(p)
				next()
		6:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("virtsaa rinteeseen") and str(it.text).contains("5 m"), "Markon kehote: %s" % it.get("text", ""))
				it.cb.call()
				next()
		7:
			if t > 3.0:
				print("Markon kaari %.2f m" % main.pissa._max)
				check(main.pissa._max > 4.2 and main.pissa._max < 6.5, "Markon kaari n. 5 m")
				check(main.pissa._mine._spots.size() > 0, "märät läikät maahan")
				main.pissa.stop()
				check(p.controls_enabled, "ohjaus palaa")
				main.choose_character(0)
				next()
		8:
			if t > 0.5:
				_to_pee_spot(p)
				main._interaction().cb.call()
				next()
		9:
			if t > 3.0:
				print("Santun kaari %.2f m" % main.pissa._max)
				check(main.pissa._max > 1.0 and main.pissa._max < 3.0, "muiden kaari n. 2 m")
				main.pissa.stop()
				# Moninpeli: toisen koneen Marko virtsaa; viestistä suihku näkyy tällä koneella.
				var mk: CharacterBody3D = main.crew[1]
				mk.brain = null  # paikallaan kuin toisen koneen pelaaja
				p.global_position = m.points.itaterassi + Vector3.UP * 0.1
				_to_pee_spot(mk)
				next()
		10:
			main.pissa._on_remote({"t": "pissa", "i": 1, "a": 0.75, "y": 0.0, "v": 6.1, "f": 1.0}, 7)
			if t > 0.5:
				var rs = main.pissa._remote[1].stream
				print("toisen koneen Markon kaari %.2f m" % rs.dist)
				check(rs.active() and rs.dist > 3.5, "moninpelissä toisen suihku näkyy")
				next()
		11:
			if t > 1.0:
				check(not main.pissa._remote[1].stream.active(), "toisen suihku loppuu, kun viestit loppuvat")
				# Itäterassilta suoraan kohti pitkospuita: kaide on tiellä.
				p = main.player
				var a: Vector3 = main.world.mokki.points.itaterassi
				p.global_position = a + Vector3.UP * 0.1
				p.velocity = Vector3.ZERO
				p.brain = Follow.new()
				p.brain.body = p
				p.brain.path = [main.world.mokki.points.pitkos]
				next()
		12:
			if t > 6.0:
				var q: Vector2 = Mokki.wy(Vector2(p.global_position.x, p.global_position.z))
				p.brain = null
				print("itäterassilta pitkospuita kohti: (%.2f, %.2f)" % [q.x, q.y])
				check(q.x < 5.5 and q.y > -0.9, "itäterassilta ei pääse huussille eikä saunan taakse")
				print("vikoja %d" % fails)
				return true
	if now() > 120.0:
		check(false, "aikaraja (vaihe %d)" % step)
		return true
	return false
