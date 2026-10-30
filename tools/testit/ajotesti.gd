extends SceneTree
## Käsin ajamisen testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/ajotesti.gd
## Näppäinsyötteet simuloidaan (W, A/D, välilyönti): kaasu, vauhti, kumpareet, käsijarru, peruutus, humala ja ulos.

var main: Node3D
var Reitti: GDScript
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var air := 0
var maxspeed := 0.0
var off := 0.0
var ri := 0
var wobble := 0.0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Reitti = load("res://scripts/reitti.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = clock


func _key(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)


## Pelaaja ohjaa itse reittipisteitä pitkin (pure pursuit näppäimillä).
func _drive_route(car: CharacterBody3D) -> bool:
	var p := Vector2(car.global_position.x, car.global_position.z)
	while ri < Reitti.ROUTE.size() - 1 and p.distance_to(Reitti.ROUTE[ri]) < 6.0:
		ri += 1
	var ti := ri
	while ti < Reitti.ROUTE.size() - 1 and p.distance_to(Reitti.ROUTE[ti]) < 9.0:
		ti += 1
	var tgt: Vector2 = Reitti.ROUTE[ti]
	var d := tgt - p
	var err := wrapf(atan2(-d.x, -d.y) - car.rotation.y, -PI, PI)
	_key("left", err > 0.08)
	_key("right", err < -0.08)
	var rest := p.distance_to(Reitti.K)
	_key("forward", car.speed < (9.0 if absf(err) < 0.5 else 4.0) and rest > 6.0)
	_key("back", rest <= 6.0 and car.speed > 0.5)
	return rest < 6.0 and absf(car.speed) < 1.0


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
		return true
	var t := clock - ts
	var car: CharacterBody3D = main.car
	var p: CharacterBody3D = main.player
	match step:
		0:
			if clock > 2.0:
				p.global_position = car.global_position + Vector3(-2.0, 0.3, 0.0)
				main._interaction().cb.call()
				check(car.driver == p, "rattiin")
				_key("forward", true)
				next()
		1:
			if t > 3.0:
				check(car.speed > 3.0, "kaasu: vauhti %.1f m/s" % car.speed)
				_key("forward", false)
				_key("jump", true)
				next()
		2:
			if t > 2.5:
				_key("jump", false)
				check(absf(car.speed) < 0.5, "käsijarru pysäyttää (%.2f)" % car.speed)
				_key("back", true)
				next()
		3:
			if t > 1.5:
				check(car.speed < -0.5, "peruutus (%.1f)" % car.speed)
				_key("back", false)
				# Reitin seuranta alkaa lähimmästä pisteestä kulkusuuntaan (auto on ajanut jo eteenpäin).
				var q := Vector2(car.global_position.x, car.global_position.z)
				var bd := INF
				for k in Reitti.ROUTE.size():
					if q.distance_to(Reitti.ROUTE[k]) < bd:
						bd = q.distance_to(Reitti.ROUTE[k])
						ri = k
				ri += 1
				next()
		4:
			if _drive_route(car):
				for a in ["left", "right", "forward", "back"]:
					_key(a, false)
				check(t < 160.0, "ajettiin Happy Beachille käsin (%.0f s, ilmassa %d ruutua, suurin vauhti %.1f)" % [t, air, maxspeed])
				check(air > 0, "kumpareet nostivat auton ilmaan")
				next()
			elif t > 220.0:
				for a in ["left", "right", "forward", "back"]:
					_key(a, false)
				check(false, "käsiajo ei päässyt perille: %s nopeus %.1f" % [car.global_position, car.speed])
				return true
			else:
				if car._air:
					air += 1
				maxspeed = maxf(maxspeed, car.speed)
				if _off_route(car.global_position) > 6.0:
					off += delta
		5:
			if t > 1.0:
				check(off < 5.0, "pysyttiin tiellä (poissa %.1f s)" % off)
				p.promille = 2.5
				car.speed = 8.0
				wobble = 0.0
				next()
		6:
			# Humalassa auto vaeltaa: ohjaus pidetään suorassa, mutta suunta ei pysy.
			_key("forward", car.speed < 8.0)
			wobble = maxf(wobble, absf(car.steer_angle))
			if t > 6.0:
				_key("forward", false)
				check(wobble > 0.1, "humalassa ratti heiluu itsestään (suurin kulma %.2f rad)" % wobble)
				car.speed = 0.0
				p.promille = 0.0
				next()
		7:
			if t > 1.0:
				main._leave_car()
				check(car.driver == null and not p.hidden_inside, "ulos autosta")
				next()
		_:
			print("Ajotesti valmis, virheitä: %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
