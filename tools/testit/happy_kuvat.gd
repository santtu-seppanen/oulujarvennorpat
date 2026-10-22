extends SceneTree
## Happy Beachin kuvakaappaukset: godot --path . -s tools/testit/happy_kuvat.gd -- <kansio>
## Ulkoa (oikean rakennuksen valokuvan kuvakulma) ja sisältä (Siitarin yläkamera).

const Reitti := preload("res://scripts/reitti.gd")

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
	root.size = Vector2i(1400, 800)
	Mokki = load("res://scripts/mokki.gd")


func _y(u: float, v: float, y: float) -> Vector3:
	var w: Vector2 = Mokki.yw(u, v)
	return Vector3(w.x, Mokki.DY + y, w.y)


func _w(a: float, y: float, b: float) -> Vector3:
	var h: Node3D = main.world.happy
	var w := Reitti.cw(a, b)
	return Vector3(w.x, h.pad_y + y, w.y)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 60:
		return false
	var h: Node3D = main.world.happy
	if shots.is_empty():
		# [nimi, kamera, kohde, sisällä]
		shots = [
			["ulko_tielta", _w(-12.0, 1.7, 3.0), _w(-4.0, 2.5, 12.0), false],
			["ulko_kulma", _w(6.0, 1.7, 6.0), _w(-3.0, 2.5, 12.0), false],
			["ulko_jarvelta", _w(-4.0, 2.0, 27.0), _w(-3.0, 3.0, 14.0), false],
			["teltta_poyta", _y(-6.2, 2.2, 2.2), _y(-4.9, 0.25, 0.9), false],
			["sisa_baari", Vector3.ZERO, h.world_at(-3.0, 12.5), true],
			["sisa_seurue", Vector3.ZERO, h.world_at(-8.0, 13.0), true],
			["sisa_tanssi", Vector3.ZERO, h.world_at(0.5, 13.5), true],
		]
	var idx := (frames - 60) / 45
	if idx >= shots.size():
		return true
	var s: Array = shots[idx]
	var phase := (frames - 60) % 45
	if phase == 0:
		var sun = main.sun
		sun.t_utc = sun._local_to_utc(2026, 7, 10, 21, 30)
		sun._update(true)
		if s[0] == "teltta_poyta":
			main.tarjoilu.add_steaks(4)
			main.kokkaus._set_count(4)
		if s[3]:
			main.player.global_position = s[2]
			main.player.velocity = Vector3.ZERO
			main.player.activate_camera()
		else:
			if cam == null:
				cam = Camera3D.new()
				cam.far = 9000.0
				cam.fov = 70.0
				main.add_child(cam)
			cam.current = true
			cam.global_position = s[1]
			cam.look_at(s[2], Vector3.UP)
			main.world.trees.update_around(cam.global_position)
	if phase == 44:
		root.get_texture().get_image().save_png(out.path_join(s[0] + ".png"))
		print("kuva ", s[0])
	return false
