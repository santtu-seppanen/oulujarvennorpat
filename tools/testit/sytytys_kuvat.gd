extends SceneTree
## Sytytysminipelin kuvakaappaukset: godot --path . --resolution 1280x720 -s tools/testit/sytytys_kuvat.gd -- <kansio>
var out := "user://sytytys"
var g: CanvasLayer
var frames := 0
var shots := ["alku", "asettelu", "savu", "liekki"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		g = load("res://scripts/sytytys_game.gd").new()
		root.add_child(g)
		g._t = 1.0
	elif frames == 8:
		_shot("alku")
		for s in [0, 2, 1, 3]:
			g.place(s)
		g.cursor = 4
	elif frames == 14:
		_shot("asettelu")
		g.place(4)
		g.light()
	elif frames == 20:
		g._step(2.0)
		g.set_process(false)
	elif frames == 24:
		_shot("savu")
		g.set_process(true)
		g.toggle_damper()
		g.smoke = 0.0
		g.prog = 0.0
		g._step(2.0)
		g.set_process(false)
	elif frames == 30:
		_shot("liekki")
		return true
	return false


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("kuva ", name)
