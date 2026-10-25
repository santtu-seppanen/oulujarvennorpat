extends SceneTree
## Näkyvyysetäisyyden testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/asetustesti.gd
## Lyhyt etäisyys lyhentää usvaa ja kameran kaukorajaa, täysi palauttaa entiset arvot; asetus palautetaan lopuksi.

var main: Node3D
var frames := 0
var fails := 0
var keep := 3
var S: Node


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	S = root.get_node("Settings")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _process(_d: float) -> bool:
	frames += 1
	if frames == 30:
		keep = S.get_v("view_distance")
		S.set_v("view_distance", 0)
	elif frames == 40:
		check(is_equal_approx(main._env.fog_depth_end, 5500.0 * 800.0 / 9000.0), "lyhyt: usva päättyy %.0f m" % main._env.fog_depth_end)
		check(is_equal_approx(main.player._cam.far, 800.0), "lyhyt: kameran kaukoraja %.0f m" % main.player._cam.far)
		S.set_v("view_distance", 3)
	elif frames == 50:
		check(is_equal_approx(main._env.fog_depth_end, 5500.0) and is_equal_approx(main._env.fog_depth_begin, 250.0), "täysi: entinen usva")
		check(is_equal_approx(main.player._cam.far, 9000.0), "täysi: kaukoraja 9000 m")
		S.set_v("view_distance", keep)
		print("vikoja %d" % fails)
		return true
	return false
