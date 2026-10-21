extends SceneTree
## Moninpelin autokyydin testi yhdellä koneella (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/automoninpeli.gd
## Toisen koneen kuljettaja (viesti auto/auto_s) imee tämän koneen pelaajan ja tietokoneen hahmot kyytiin ja päästää ulos.

var main: Node3D
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _process(delta: float) -> bool:
	clock += delta
	if main == null or main.get_script() == null:
		return true
	var car: CharacterBody3D = main.car
	var p: CharacterBody3D = main.player
	match step:
		0:
			if clock > 2.0:
				main._remote_ride(true)
				check(car.remote and car.passenger == p and p.hidden_inside, "kyytiin: auto on toisen ajossa, pelaaja kyydissä")
				check(main._ride_crew.size() == 3, "tietokoneen hahmot mukaan (%d)" % main._ride_crew.size())
				check(not main._near_car(), "ajossa olevaan autoon ei nousta")
				step = 1
				ts = clock
		1:
			var t := clock - ts
			car.net_apply([car.global_position.x + t * 5.0, car.global_position.z, car.rotation.y, 5.0, 0.0])
			if t > 2.0:
				check(car.global_position.x > 5.0 and p.global_position.distance_to(car.global_position) < 2.0, "pelaaja seuraa autoa")
				main._remote_ride(false)
				check(not car.remote and car.passenger == null and not p.hidden_inside, "ajon jälkeen pelaaja ulkona")
				check(main._ride_crew.size() == 3 and not main.crew[1].hidden_inside, "porukka ulkona auton vieressä")
				step = 2
		_:
			print("Valmis, virheitä: %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
