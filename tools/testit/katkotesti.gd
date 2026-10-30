extends SceneTree
## Omien kätköjen testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/katkotesti.gd
## Tekeminen on lukossa, kunnes tutkimusmatkan kätköltä on haettu viinaa; sen jälkeen sopivassa paikassa E tekee kätkön.

var main: Node3D
var fails := 0
var frames := 0


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
	if frames < 60:
		return false
	var T := load("res://scripts/terrain.gd")
	var ok_k: Node3D = main.omat_katkot
	var s: Vector3 = main.world.start_position()
	var spot := Vector3.INF
	for r in range(30, 200, 10):
		for a in 16:
			var x := s.x + cos(a * TAU / 16.0) * r
			var z := s.z + sin(a * TAU / 16.0) * r
			var p := Vector3(x, T.h(x, z), z)
			main.player.global_position = p
			if ok_k.can_build(p):
				spot = p
				break
		if spot != Vector3.INF:
			break
	check(spot != Vector3.INF, "sopiva paikka löytyi lähimaastosta")
	main.player.global_position = spot
	check(not main.tarina.stash_unlocked, "tekeminen lukossa alussa")
	check(main._interaction().get("text", "").find("kätkö") < 0, "ei tarjota ennen avausta")
	main.tarina.unlock_stash()
	check(main._interaction().get("text", "").find("uusi viinakätkö") >= 0, "avauksen jälkeen E tarjoaa kätkön")
	main._make_stash()
	check(ok_k.spots.size() == 1, "kätkö tehty")
	check(ok_k.near(main.player.global_position), "kätkön luona")
	check(not ok_k.can_build(spot), "samaan paikkaan ei toista")
	check(main._interaction().get("text", "").find("Viinakätkö") >= 0, "kätkö toimii kuten muut")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ok_k.SAVE_PATH))
	print("Kätkötesti valmis, virheitä: %d" % fails)
	return true
