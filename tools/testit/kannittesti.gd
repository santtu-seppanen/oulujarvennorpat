extends SceneTree
## Konttauskunnon testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/kannittesti.gd
## Kun joku nousee kahden promillen humalaan, välianimaatio alkaa, porukka heiluu ja konttaa, ja lopuksi peli palaa normaaliksi.

var main: Node3D
var frames := 0
var started := false
var fails := 0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _process(_d: float) -> bool:
	frames += 1
	var k: Node = main.kannit
	if frames == 120:
		main.crew[1].promille = 0.5
	elif frames == 130:
		main.crew[1].promille = 2.1
	elif frames == 140:
		check(k.active, "kahden promillen humala käynnistää välianimaation")
		started = k.active
	elif frames == 140 + 60 * 8:
		check(k.active and k._crawling and main.crew[2].pose == "Ryomii", "porukka konttaa")
	elif frames == 140 + 60 * 20:
		print(k.active, " ", main.crew[2].pose, " ", main.crew[2].promille, " ", k._t)
		check(not k.active and main.crew[2].pose == "", "välianimaatio päättyy ja hahmot nousevat")
		check(main.crew[0].brain == null or main.crew_modes[0] == "player", "pelaaja saa ohjauksen takaisin")
		print("Valmis, vikoja: %d" % fails)
		return true
	return false
