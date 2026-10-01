extends SceneTree
## Mökkipihan kuvakaappaukset valokuvien kuvakulmista: godot --path . -s tools/testit/mokki_kuvat.gd -- <kansio>
## Jokaisella kuvalla oma kellonaika (paikallista aikaa 7.7.), jotta auringonlasku näkyy oikeassa suunnassa.

var Mokki: GDScript

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
	root.size = Vector2i(1600, 800)
	Mokki = load("res://scripts/mokki.gd")
	var e: Array = Mokki.stair_ends()
	var top: Vector2 = e[1]
	var cab: Vector2 = Mokki.cw(4.6, 1.5)
	var fy: float = Mokki.floor_y()
	# [nimi, kameran paikka, katsepiste, kuukausi, päivä, tunti, minuutti]
	shots = [
		["porukka", _y(-6.0, 2.4, Mokki.DY + 1.7), _y(-3.7, 0.0, Mokki.DY + 0.6), 7, 7, 18, 0],
		["panoraama_ilta", Vector3(top.x + 0.3, fy + 1.6, top.y + 0.5), Vector3(-9, 0, -30), 7, 7, 23, 15],
		["portaat_teltasta", _y(-3.7, 0.9, 1.6 + Mokki.DY), _y(-7.0, -6.0, 3.5), 7, 7, 20, 34],
		["sauna_ylhaalta", Vector3(cab.x, fy + 1.7, cab.y), Vector3(-1.5, 1.0, -9.0), 7, 9, 3, 8],
		["jarvelta", _y(-3.0, 30.0, 1.2), _y(-3.0, 0.0, 3.0), 8, 4, 18, 27],
		["tormasta_ylos", _y(-5.0, 1.5, Mokki.DY + 1.5), Vector3(-6, 9.5, 6), 10, 1, 17, 51],
		["ilmasta", _y(-14.0, 18.0, 16.0), _y(-3.0, -2.0, 2.0), 7, 7, 15, 0],
		["laiturilta", _y(-2.2, 13.0, 2.1), Vector3(-200, 0, -380), 7, 7, 23, 22],
		["porukka", _y(-6.5, 2.6, Mokki.DY + 1.7), _y(-3.7, -0.3, Mokki.DY + 0.7), 7, 7, 18, 0],
		["porukka2", _y(-2.0, 1.2, Mokki.DY + 1.5), _y(-5.5, -0.5, Mokki.DY + 0.9), 7, 7, 18, 0],
		["vene", null, null, 7, 7, 19, 0],
		["valikko", Vector3(30, 20, 30), Vector3(0, 2, 0), 7, 7, 21, 30],
	]


func _y(u: float, v: float, y: float) -> Vector3:
	var w: Vector2 = Mokki.yw(u, v)
	return Vector3(w.x, y, w.y)


func _process(_delta: float) -> bool:
	frames += 1
	var idx := (frames - 60) / 50
	if frames < 60:
		return false
	if idx >= shots.size():
		return true
	var s: Array = shots[idx]
	var phase := (frames - 60) % 50
	if s[1] == null and phase > 0 and cam != null:
		var b: Node3D = main.boat
		cam.global_position = b.global_position + b.global_transform.basis.x * 2.2 + Vector3.UP * 1.1 - b.global_transform.basis.z * 0.6
		cam.look_at(b.global_position + Vector3.UP * 0.4, Vector3.UP)
	if phase == 0:
		if cam == null:
			cam = Camera3D.new()
			cam.far = 9000.0
			cam.fov = 75.0
			main.add_child(cam)
		cam.current = true
		if s[1] == null:
			# Pelaaja soutaa kumivenettä; kamera sivulta.
			var b: Node3D = main.boat
			if main.player.boat == null:
				main.player.enter_boat(b)
				main.player.brain = load("res://tools/testit/mokkitesti.gd").Push.new()
			var side: Vector3 = b.global_transform.basis.x
			cam.global_position = b.global_position + side * 2.2 + Vector3.UP * 1.1 - b.global_transform.basis.z * 0.6
			cam.look_at(b.global_position + Vector3.UP * 0.4, Vector3.UP)
		else:
			cam.global_position = s[1]
			cam.look_at(s[2], Vector3.UP)
		var sun = main.sun
		sun.t_utc = sun._local_to_utc(2026, s[3], s[4], s[5], s[6])
		sun._update(true)
		main.world.trees.update_around(cam.global_position)
		if s[0] == "valikko":
			main._menu.open_main()
			main._menu._choose()
	if phase == 49:
		var img := root.get_texture().get_image()
		img.save_png(out.path_join(s[0] + ".png"))
		var sun = main.sun
		print("kuva %s: aurinko %.1f° / %.0f°, %s" % [s[0], sun.altitude, sun.azimuth, sun.clock_text()])
	return false
