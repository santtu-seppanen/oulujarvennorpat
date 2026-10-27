extends SceneTree
## Äpätin venesataman, videopokerin, Afrikan tähden ja ohjeruudun kuvakaappaukset: godot --path . -s tools/testit/satama_kuvat.gd -- <kansio>

var main: Node3D
var frames := 0
var out := "user://kuvat"
var shots := []
var cam: Camera3D
var pk: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1400, 800)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 30:
		var o := Vector3(116.0, 0.0, -23.0)
		shots = [
			["satama_ilmasta", o + Vector3(14.0, 22.0, -34.0), o + Vector3(0.0, 0.0, -16.0)],
			["satama_rannalta", o + Vector3(-4.0, 2.2, 14.0), o + Vector3(1.0, 0.8, -14.0)],
			["satama_laiturilta", o + Vector3(0.5, 2.0, -6.0), o + Vector3(3.0, 0.8, -19.0)],
			["satama_jarvelta", o + Vector3(30.0, 4.0, -44.0), o + Vector3(0.0, 1.0, -14.0)],
			["venevaja", o + Vector3(-6.0, 2.0, -2.0), o + Vector3(-14.0, 1.5, 7.0)],
		]
	if frames < 60:
		return false
	var idx := (frames - 60) / 50
	if idx < shots.size():
		var s: Array = shots[idx]
		var phase := (frames - 60) % 50
		if phase == 0:
			if cam == null:
				cam = Camera3D.new()
				cam.far = 9000.0
				cam.fov = 75.0
				main.add_child(cam)
			cam.current = true
			cam.global_position = s[1]
			cam.look_at(s[2], Vector3.UP)
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 16, 0)
			main.sun._update(true)
			main.world.trees.update_around(cam.global_position)
		if phase == 49:
			root.get_texture().get_image().save_png(out.path_join(s[0] + ".png"))
			print("kuva %s" % s[0])
		return false
	var t := frames - 60 - shots.size() * 50
	if t == 1:
		pk = load("res://scripts/pokeri_game.gd").new()
		main.add_child(pk)
	elif t == 10:
		pk._deal()
	elif t == 50:
		pk._toggle(0)
		pk._toggle(2)
		root.get_texture().get_image().save_png(out.path_join("pokeri.png"))
		pk.queue_free()
		main.ohje.auto = true
		main.ohje.open("pokeri")
	elif t == 70:
		root.get_texture().get_image().save_png(out.path_join("ohje_pokeri.png"))
		main.ohje.close()
		main.start_activity("lautapeli")
		main.lautapeli.choose(1)
	elif t == 130:
		main.afrikka.turn = main.player_index
		main.afrikka._begin_turn()
	elif t == 150:
		root.get_texture().get_image().save_png(out.path_join("afrikka.png"))
		main.ohje.open("afrikka")
	elif t == 170:
		root.get_texture().get_image().save_png(out.path_join("ohje_afrikka.png"))
		return true
	return false
