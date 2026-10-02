extends SceneTree
## Väliaikainen: pelaaja paikalleen, kuva pelaajan kamerasta. -- <kansio> nimi:u,v,suunta_deg ...
var Mokki: GDScript
var main: Node3D
var frames := 0
var out := ""
var shots := []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0]
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1200, 800)
	Mokki = load("res://scripts/mokki.gd")
	for a in args.slice(1):
		var p: PackedStringArray = a.split(":")
		shots.append([p[0], p[1].split_floats(",")])

func _process(_d: float) -> bool:
	frames += 1
	if frames < 60: return false
	var idx := (frames - 60) / 60
	if idx >= shots.size(): return true
	var s: Array = shots[idx]
	var ph := (frames - 60) % 60
	if ph == 0:
		var c: PackedFloat64Array = s[1]
		var w: Vector2 = Mokki.yw(c[0], c[1])
		main.player.global_position = Vector3(w.x, Mokki.DY + 0.05, w.y)
		var d: Vector2 = Mokki.EAST * cos(deg_to_rad(c[2])) + Mokki.LAKE * sin(deg_to_rad(c[2]))
		main.player.rotation.y = atan2(-d.x, -d.y)
		main.player.velocity = Vector3.ZERO
		var sun = main.sun
		sun.t_utc = sun._local_to_utc(2026, 7, 7, 14, 0)
		sun._update(true)
	if ph == 59:
		root.get_texture().get_image().save_png(out.path_join(s[0] + ".png"))
		print("kuva ", s[0], " huone=", Mokki.room_at(main.player.global_position))
	return false
