extends SceneTree
## Rantatenniksen kuvakaappaukset: godot --path . -s tools/testit/tennis_kuvat.gd -- <kansio>

var main: Node3D
var frames := 0
var out := "user://kuvat"
var cam: Camera3D
var T: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1600, 800)
	T = load("res://scripts/rantatennis.gd")


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	if cam == null:
		cam = Camera3D.new()
		cam.far = 9000.0
		cam.fov = 70.0
		main.add_child(cam)
	cam.current = true
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	main.world.trees.update_around(from)


func _process(_delta: float) -> bool:
	frames += 1
	var tn: Node3D = main.tennis
	var c: Vector2 = T.fw(0.0, 0.0)
	var g: float = load("res://scripts/terrain.gd").h(c.x, c.y)
	var mid := Vector3(c.x, g + 1.0, c.y)
	match frames:
		30:
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 16, 0)
			tn.save_path = "user://rantatennis_kuva.cfg"
			main.player.global_position = Vector3(c.x, g + 0.1, c.y)
			tn.start()
			for pl in tn.players:
				(pl.body as Node3D).global_position = tn._spot_pos(pl.spot) + Vector3.UP * 0.1
				if pl.brain != null:
					pl.brain.path = []
		120:
			var me: Dictionary = tn._me()
			main.player.global_position = tn._spot_pos(me.spot) + Vector3.UP * 0.1
			var o: Vector3 = tn._spot_pos(2 if me.spot != 2 else 0)
			var d: Vector3 = o - main.player.global_position
			main.player.rotation.y = atan2(-d.x, -d.z)
		150:
			tn.act()
			var w: Vector2 = T.fw(0.0, -T.FIELD_H.y - 3.0)
			_shot("kentta", Vector3(w.x, g + 3.5, w.y), mid)
		175:
			root.get_texture().get_image().save_png(out.path_join("kentta.png"))
		180:
			var b: Node3D = tn.players[1].body
			var f := -b.global_transform.basis.z
			_shot("maila", b.global_position + f * 1.6 + Vector3.UP * 1.5 + b.global_transform.basis.x * 0.6, b.global_position + Vector3.UP * 1.0)
		200:
			root.get_texture().get_image().save_png(out.path_join("maila.png"))
		205:
			var b: Node3D = tn.players[1].body
			tn._start_swing(b)
			_shot("lyonti", b.global_position + b.global_transform.basis.x * 2.6 + Vector3.UP * 1.3, b.global_position + Vector3.UP * 1.1)
		214:
			root.get_texture().get_image().save_png(out.path_join("lyonti.png"))
		220:
			var w: Vector2 = Mokki().cw(0.0, 4.0)
			_shot("ylamokilta", Vector3(w.x, g + 6.0, w.y), mid)
		240:
			root.get_texture().get_image().save_png(out.path_join("ylamokilta.png"))
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://rantatennis_kuva.cfg"))
			return true
	return false


func Mokki() -> GDScript:
	return load("res://scripts/mokki.gd")
