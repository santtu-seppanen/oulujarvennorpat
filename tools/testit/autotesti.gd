extends SceneTree
## Autoajon testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/autotesti.gd
## - Reitin pisteet ja kehys: reitti n. 850 m, Happy Beachin kehys (a, b) menee edestakaisin.
## - Auto odottaa mökin pihalla ajouralla; E rattiin, porukka kyytiin (piiloon).
## - Automaattiajo Happy Beachille: perille asti reitin päällä (ei jumia), E ulos, porukka seisoo auton vieressä.
## - Baari: auki lauantaina, kiinni sunnuntaina (oikeat aukioloajat); olut nostaa promilleja.
## - Takaisin mökille automaattiajolla: porukka palaa pihalle omiin puuhiinsa.

var main: Node3D
var Reitti: GDScript
var Happybeach: GDScript
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var arrived := false
var max_off := 0.0
var hit_water := false
var air_frames := 0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Reitti = load("res://scripts/reitti.gd")
	Happybeach = load("res://scripts/happybeach.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = clock


## Etäisyys reittiin (m).
func _off_route(p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var best := INF
	for k in Reitti.ROUTE.size() - 1:
		var a: Vector2 = Reitti.ROUTE[k]
		var b: Vector2 = Reitti.ROUTE[k + 1]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best


func _process(delta: float) -> bool:
	clock += delta
	if main == null or main.get_script() == null:
		print("VIKA peli ei käynnisty")
		return true
	var t := clock - ts
	var p: CharacterBody3D = main.player
	var car: CharacterBody3D = main.car
	match step:
		0:
			if clock > 2.0:
				var route_len: float = Reitti.length()
				check(route_len > 700.0 and route_len < 1000.0, "reitin pituus %.0f m" % route_len)
				var w: Vector2 = Reitti.cw(10.0, 5.0)
				var ab: Vector2 = Reitti.wc(w)
				check(ab.distance_to(Vector2(10.0, 5.0)) < 0.01, "kehys (a, b) menee edestakaisin")
				check(Reitti.on_route(13.0, 36.0) and Reitti.on_route(-586.0, -40.0), "reitti alkaa mökiltä ja päättyy Happy Beachille")
				check(Vector2(car.global_position.x, car.global_position.z).distance_to(Reitti.HOME_SPOT) < 1.0, "auto mökin pihalla")
				var lt := {"weekday": 6, "hour": 20, "minute": 0}
				check(Happybeach.is_open(lt), "baari auki lauantaina klo 20")
				lt.hour = 21
				check(not Happybeach.is_open(lt), "baari kiinni lauantaina klo 21")
				lt = {"weekday": 0, "hour": 12, "minute": 0}
				check(not Happybeach.is_open(lt), "baari kiinni sunnuntaina")
				lt = {"weekday": 2, "hour": 14, "minute": 0}
				check(not Happybeach.is_open(lt), "baari kiinni tiistaina klo 14")
				for c in main.crew:
					if c != p:
						c.brain = null  # testissä porukka ei vaella, ai-tila palautetaan ajon lopussa
				p.global_position = car.global_position + Vector3(-2.0, 0.3, 0.0)
				p.velocity = Vector3.ZERO
				next()
		1:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("nouse autoon"), "kehote: %s" % it.get("text", ""))
				it.cb.call()
				check(car.driver == p and p.hidden_inside, "kuljettaja rattiin")
				check(main._ride_crew.size() == 3, "porukka kyytiin (%d)" % main._ride_crew.size())
				car.arrived.connect(func() -> void: arrived = true)
				car.start_autopilot(true)
				check(car.autopilot, "automaattiajo päällä")
				next()
		2:
			max_off = maxf(max_off, _off_route(car.global_position))
			if car.global_position.y < -0.05:
				hit_water = true
			if car._air:
				air_frames += 1
			if arrived:
				check(max_off < 8.0, "ajettiin reitin päällä (suurin poikkeama %.1f m)" % max_off)
				check(not hit_water, "ei vedessä")
				print("ilmassa %d ruutua matkalla (kumpareet)" % air_frames)
				check(Vector2(car.global_position.x, car.global_position.z).distance_to(Reitti.K) < 6.0,
					"perillä Happy Beachin parkkipaikalla (%.1f m)" % Vector2(car.global_position.x, car.global_position.z).distance_to(Reitti.K))
				next()
			elif t > 200.0:
				check(false, "auto ei päässyt perille 200 s: %s, nopeus %.1f" % [car.global_position, car.speed])
				return true
		3:
			if t > 3.0:
				main._leave_car()
				check(car.driver == null and not p.hidden_inside, "kuljettaja ulos")
				check(main.world.happy.in_camp(p.global_position), "pelaaja leirintäalueella")
				var out := 0
				for j in main._ride_crew:
					if not main.crew[j].hidden_inside:
						out += 1
				check(out == 3, "porukka ulkona auton vieressä (%d)" % out)
				var dw: Vector2 = main.world.happy.cw_door("terassi")
				p.global_position = Vector3(dw.x, main.world.happy.pad_y + 0.2, dw.y)
				p.velocity = Vector3.ZERO
				# Lauantai klo 12 (to-su viikonloppu alkaa torstaista: torstai klo 12 + 2 vrk).
				main.sun.start_preset(main.Sun.STORY_PRESET)
				main.sun.t_utc += 2.0 * 86400.0
				next()
		4:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("sisään"), "ravintola auki lauantaina: %s" % it.get("text", ""))
				it.cb.call()
				check(main.world.happy.in_pocket(p.global_position), "ovesta sisään ravintolaan")
				main.world.happy.leave("terassi")
				main.sun.t_utc += 86400.0  # sunnuntai
				next()
		5:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(not it.has("cb") and str(it.get("text", "")).contains("kiinni"), "ravintola kiinni sunnuntaina: %s" % it.get("text", ""))
				p.global_position = car.global_position + Vector3(-2.0, 0.3, 0.0)
				p.velocity = Vector3.ZERO
				arrived = false
				max_off = 0.0
				next()
		6:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("nouse autoon"), "paluu: %s" % it.get("text", ""))
				it.cb.call()
				check(car.near_beach_end(), "auto Happy Beachin päässä")
				car.start_autopilot(false)
				next()
		7:
			# Happy Beachin pihalla auto kääntyy ympäri (parkkipaikka on tasainen ja raivattu): poikkeamaa mitataan tien päällä.
			if Vector2(car.global_position.x, car.global_position.z).distance_to(Reitti.K) > 35.0:
				max_off = maxf(max_off, _off_route(car.global_position))
			if arrived:
				check(max_off < 8.0, "paluu reitin päällä (suurin poikkeama %.1f m)" % max_off)
				check(Vector2(car.global_position.x, car.global_position.z).distance_to(Reitti.HOME_SPOT) < 6.0, "takaisin mökin pihalla")
				main._leave_car()
				check(main._ride_crew.is_empty(), "porukka palasi pihalle")
				var ai := 0
				for c in main.crew:
					if c != p and c.brain != null and not c.hidden_inside:
						ai += 1
				check(ai == 3, "tietokoneen hahmot taas omissa puuhissaan (%d)" % ai)
				next()
			elif t > 200.0:
				check(false, "paluu ei onnistunut 200 s: %s, nopeus %.1f" % [car.global_position, car.speed])
				return true
		_:
			print("Autotesti valmis, virheitä: %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
