extends SceneTree
## Päikkärien ja yöunien välianimaation kuvat: godot --path . -s tools/testit/uni_kuvat.gd -- <kansio>
## Ajaa kummankin version ja tallentaa kuvan muutaman sekunnin välein.

var main: Node3D
var frames := 0
var out := "user://uni"
var mode := 0  # 0 päikkärit, 1 yö
var shot_f := [0.03, 0.2, 0.4, 0.55, 0.7, 0.85, 0.93]  # kuvat välianimaation suhteellisina hetkinä
var idx := 0
var t := 0.0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	root.size = Vector2i(1280, 720)


func _process(delta: float) -> bool:
	frames += 1
	if frames < 90:
		return false
	if frames == 90:
		main.crew_modes[main.player_index] = ""
		main.set_crew_mode(main.player_index, "player")
		main.sun.t_utc = main.sun._local_to_utc(2026, 7, 9, 16, 0)
		main._nap(false, false)
		t = 0.0
		return false
	t = main._nap_scene._t
	var len_s: float = main._nap_len
	if idx < shot_f.size() and t >= shot_f[idx] * len_s:
		root.get_texture().get_image().save_png("%s/%s_%d.png" % [out, "yo" if mode == 1 else "paiva", idx])
		idx += 1
	if idx >= shot_f.size():
		if mode == 0:
			main._wake()
			mode = 1
			idx = 0
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 10, 1, 0)
			main._nap(true, false)
			t = 0.0
		else:
			return true
	return false
