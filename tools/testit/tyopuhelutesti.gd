extends SceneTree
## Jaakon työpuhelun testi saunassa (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/tyopuhelutesti.gd
## - Puhelu tulee vain Jaakolle, vain kun hän saunoo ja enintään kerran päivässä.
## - Vastaaminen: mainepisteet +2, löylypisteet -6. Vastaamatta jättäminen: löylypisteet +3. Soitto päättyy itsestään.

var main: Node3D
var fails := 0
var frames := 0
var step := 0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _sauna() -> void:
	main.end_activity()
	var m: Node3D = main.world.mokki
	main.player.global_position = m.sauna_seats[0][0] + Vector3(0.3, 0.05, 0.0)
	main.player.velocity = Vector3.ZERO
	main.start_activity("sauna")


func _process(_d: float) -> bool:
	frames += 1
	if frames < 60:
		return false
	var tp: Node = main.tyopuhelu
	match step:
		0:
			main.choose_character(0)
			_sauna()
			check(main.activity == "sauna" and not tp.is_jaakko() and not tp.can_call(), "Santtulle ei tule työpuhelua")
			tp.trigger()
			check(not tp.active, "puhelin ei soi muille kuin Jaakolle")
			main.choose_character(2)
			check(tp.is_jaakko(), "pelaaja on Jaakko")
			step = 1
		1:
			_sauna()
			check(main.activity == "sauna" and tp.can_call(), "Jaakko saunoo: puhelu mahdollinen")
			main.end_activity()
			check(not tp.can_call(), "ei puhelua saunan ulkopuolella")
			_sauna()
			main.sauna.points = 10.0
			var maine0: int = main.maine
			tp.trigger()
			check(tp.active, "puhelin soi")
			tp.answer(true)
			check(not tp.active and is_equal_approx(main.sauna.points, 4.0) and main.maine == mini(100, maine0 + 2),
				"vastaus: löylypisteet 10 -> %.0f, maine %d -> %d" % [main.sauna.points, maine0, main.maine])
			tp.trigger()
			check(not tp.active, "saman päivän toista puhelua ei tule")
			step = 2
		2:
			main.tarina.day = 1
			main.sauna.points = 10.0
			tp.trigger()
			check(tp.active, "seuraavana päivänä puhelin soi taas")
			tp.answer(false)
			check(is_equal_approx(main.sauna.points, 13.0) and tp.ignored == 1, "vastaamatta: löylypisteet +3")
			main.tarina.day = 2
			tp.trigger()
			tp._ring = 0.0
			tp._process(0.1)
			check(not tp.active and tp.ignored == 2, "soitto päättyy itsestään vastaamattomana")
			check(not tp.ending_lines().is_empty(), "lopputuloksessa työpuheluiden määrä")
			main.tarina.day = 0
			tp.reset()
			check(tp.answered == 0 and tp.ignored == 0 and tp.ending_lines().is_empty(), "uusi viikonloppu nollaa")
			step = 3
		3:
			print("Valmis, vikoja: %d" % fails)
			quit(1 if fails > 0 else 0)
	return false
