extends SceneTree
## Saapumiskohtauksen kuvakaappaukset (kiinteä aika 30 ruutua/s): godot --path . -s tools/testit/saapuminen_kuvat.gd -- <kansio>
## Kohtaus ajetaan manuaalitilassa kuten trailerissa; kuva 1,5 s välein ja lopuksi tarkistus, että pelin hahmot palaavat.

var main: Node3D
var out := "user://kuvat"
var frames := 0
var sc: Node
var t := 0.0
var cam: Camera3D
var last := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 45:
		return false
	if sc == null:
		sc = main.saapuminen
		cam = Camera3D.new()
		cam.far = 3000.0
		main.add_child(cam)
		cam.make_current()
		sc.cam = cam
		sc.manual = true
		sc.sun_time = {"m": 7, "d": 9, "h": 17, "min": 40}
		main._hud.visible = false
		sc.start()
		return false
	if sc.active:
		sc.step(1.0 / 30.0)
		t += 1.0 / 30.0
		cam.make_current()
		if sc.phase != last:
			print("%.1f s: vaihe %s" % [t, sc.phase])
			last = sc.phase
		if frames % 90 == 0 and not sc._actors.is_empty():
			print("  t=%.1f actor0=%s cam=%s path=%d" % [t, sc._actors[0].node.global_position, cam.global_position, sc._actors[0].path.size()])
		if frames % 45 == 0:
			root.get_texture().get_image().save_png(out.path_join("s_%03d_%s.png" % [int(t * 10), sc.phase]))
		return false
	print("kohtaus päättyi %.1f s, hahmoja piilossa: %d" % [t, main.crew.filter(func(b): return b.hidden_inside).size()])
	return true
