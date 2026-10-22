extends SceneTree
## Lopun cutscenet kuviksi: godot --path . -s tools/testit/loppu_kuvat.gd -- <kansio> [tappio]
var main: Node3D
var frames := 0
var out := "user://kuvat"
var loss := false
var shots := []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	loss = args.size() > 1 and args[1] == "tappio"
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 60:
		main.sun.start_preset(main.Sun.STORY_PRESET)
	if frames == 90:
		if loss:
			main.maine = 0
		else:
			main.tarina._finish()
	if frames >= 90:
		var k := frames - 90
		for t in [150, 250, 360]:
			if k == t:
				root.get_texture().get_image().save_png(out.path_join("%s_%d.png" % ["tappio" if loss else "voitto", t]))
				print("kuva ", t, " ", main.loppu.active, " t=", main.loppu._t)
	return frames > 90 + 920
