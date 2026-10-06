extends SceneTree
## Hiekkarannan ja viinakätkön kuvakaappaukset: godot --path . -s tools/testit/ranta_kuvat.gd -- <kansio>

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


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 30:
		var Ranta: GDScript = load("res://scripts/ranta.gd")
		var Terrain: GDScript = load("res://scripts/terrain.gd")
		var s: Vector3 = main.world.ranta.stash_pos
		var sx: float = Ranta.shore_x(100.0)
		var h := func(x: float, z: float) -> float: return Terrain.h(x, z)
		var tr: Array = Ranta.TRAIL
		# [nimi, kameran paikka, katsepiste]
		shots = [
			["katko", s + Vector3(-1.6, 1.4, 1.4), s],
			["rinne_alas", Vector3(tr[11].x, h.call(tr[11].x, tr[11].y) + 1.7, tr[11].y), Vector3(sx + 10, 0.0, 104.0)],
			["ranta_jarvelta", Vector3(sx + 30.0, 1.6, 96.0), Vector3(sx - 4.0, 1.0, 100.0)],
			["ranta_sivulta", Vector3(sx - 2.0, 1.8, 124.0), Vector3(sx, 0.3, 90.0)],
			["polku_ylamokilta", Vector3(tr[0].x - 2.0, h.call(tr[0].x, tr[0].y) + 2.0, tr[0].y - 3.0), Vector3(tr[3].x, h.call(tr[3].x, tr[3].y), tr[3].y)],
			["polku_metsassa", Vector3(tr[6].x, h.call(tr[6].x, tr[6].y) + 1.7, tr[6].y), Vector3(tr[8].x, h.call(tr[8].x, tr[8].y) + 1.0, tr[8].y)],
			["ilmasta", Vector3(sx + 25.0, 30.0, 140.0), Vector3(sx - 5.0, 0.0, 98.0)],
		]
	if frames < 60:
		return false
	var idx := (frames - 60) / 50
	if idx >= shots.size():
		return true
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
		main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 15, 0)
		main.sun._update(true)
		main.world.trees.update_around(cam.global_position)
	if phase == 49:
		root.get_texture().get_image().save_png(out.path_join(s[0] + ".png"))
		print("kuva %s" % s[0])
	return false
