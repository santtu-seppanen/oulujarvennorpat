extends SceneTree
## Kuvakaappaukset tarkistukseen: godot --path . -s tools/testit/kuvat.gd -- <kansio>
## Pelaaja aloituspaikalla, sitten kamera kiertää muutamaan kohtaan (rannalta järvelle, metsään, ilmasta).

var main: Node3D
var frames := 0
var out := "user://kuvat"
var shots := []
var cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1600, 900)
	# [kuvan nimi, kameran paikka, katsottava piste]
	# Kameran korkeus maanpinnasta (y), katsepisteen korkeus maanpinnasta.
	shots = [
		["pelaaja", null, null],
		["ranta_jarvelle", Vector3(0, 1.7, 8), Vector3(0, 1.0, -200)],
		["niemen_karki", Vector3(-80, 60, 260), Vector3(80, 0, -60)],
		["metsa", Vector3(-150, 1.7, 150), Vector3(-100, 3, 100)],
		["metsa2", Vector3(100, 1.7, 250), Vector3(160, 2, 180)],
		["ilmasta", Vector3(300, 400, 900), Vector3(0, 0, 0)],
		["satama", Vector3(260, 25, -120), Vector3(180, 0, -40)],
		["talot", Vector3(215, 1.7, 40), Vector3(205, 3, 20)],
	]


func _process(_delta: float) -> bool:
	frames += 1
	var idx := (frames - 60) / 40
	if frames < 60:
		return false
	if idx >= shots.size():
		return true
	var s: Array = shots[idx]
	var phase := (frames - 60) % 40
	if phase == 0 and s[1] != null:
		if cam == null:
			cam = Camera3D.new()
			cam.far = 9000.0
			cam.fov = 65.0
			main.add_child(cam)
		cam.current = true
		var T := preload("res://scripts/terrain.gd")
		var a: Vector3 = s[1]
		var b: Vector3 = s[2]
		a.y += maxf(T.h(a.x, a.z), 0.0)
		b.y += maxf(T.h(b.x, b.z), 0.0)
		cam.global_position = a
		cam.look_at(b, Vector3.UP)
		main.world.trees.update_around(s[1])
	if phase == 39:
		var img := root.get_texture().get_image()
		img.save_png(out.path_join(s[0] + ".png"))
		print("kuva %s (%d FPS)" % [s[0], Engine.get_frames_per_second()])
	return false
