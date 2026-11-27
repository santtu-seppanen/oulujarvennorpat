extends Node3D
## MPFB-rungot kuvina: porukka (neljä päähahmoa), Happy Beachin vieraat ja animaatioita.
## Ajo: godot --path . tools/testit/mpfb_kuvat.tscn -- <kansio>

const Looks := preload("res://scripts/looks.gd")
const Porukka := preload("res://scripts/porukka.gd")
const B := preload("res://scripts/build.gd")

var out := "user://mpfb"
var cam: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.62, 0.74, 0.88)
	env.environment.ambient_light_color = Color(0.8, 0.82, 0.88)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 150, 0)
	add_child(sun)
	B.mesh(self, B.boxm(Vector3(40, 0.1, 30)), Vector3(0, -0.05, 0), Color(0.45, 0.5, 0.4))
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	_run.call_deferred()


func _shot(name: String, from: Vector3, to: Vector3, fov := 30.0) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, to)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/" + name + ".png")
	print("kuva ", out, "/", name, ".png")


func _row(looks: Array, anim: String, gap := 1.0) -> Array:
	var cs := []
	for i in looks.size():
		var c := Looks.make(self, looks[i])
		c.position = Vector3((i - (looks.size() - 1) * 0.5) * gap, 0, 0)
		c.play(anim, 0.0)
		cs.append(c)
	return cs


func _clear(cs: Array) -> void:
	for c in cs:
		c.queue_free()


func _run() -> void:
	var crew := []
	for i in 4:
		crew.append(Porukka.look(i))
	var cs := _row(crew, "Idle", 1.0)
	for i in 6:
		await get_tree().process_frame
	await _shot("porukka_edesta", Vector3(0, 1.1, -4.6), Vector3(0, 0.95, 0), 32.0)
	await _shot("porukka_takaa", Vector3(0, 1.1, 4.6), Vector3(0, 0.95, 0), 32.0)
	await _shot("porukka_kasvot", Vector3(0, 1.6, -2.2), Vector3(0, 1.55, 0), 30.0)
	if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[1] == "parta":
		_clear(cs)
		var jk := _row([Porukka.look(3), Looks.player()], "Idle", 0.5)
		for i in 6:
			await get_tree().process_frame
		await _shot("parta_edesta", Vector3(0, 1.58, -0.8), Vector3(0, 1.55, 0), 28.0)
		await _shot("parta_sivulta", Vector3(-0.8, 1.58, -0.1), Vector3(0, 1.55, 0), 28.0)
		get_tree().quit()
		return
	_clear(cs)
	var guests := [Looks.sinikka_seura(), Looks.sinikka_bikini(), Looks.CASHIER, Looks.ANNA_LIISA, Looks.PAIVI, Looks.TERO, Looks.ARTO, Looks.JEMMARI]
	cs = _row(guests, "Idle", 1.0)
	for i in 6:
		await get_tree().process_frame
	await _shot("vieraat", Vector3(0, 1.2, -7.0), Vector3(0, 0.9, 0), 38.0)
	_clear(cs)
	var pl := _row([Looks.player()], "Walk", 1.0)
	for i in 10:
		await get_tree().process_frame
	await _shot("pelaaja", Vector3(0, 1.1, -3.2), Vector3(0, 0.95, 0))
	_clear(pl)
	cs = _row(crew, "Sitting_Idle", 1.2)
	await _shot("porukka_istuu", Vector3(0, 1.0, -4.8), Vector3(0, 0.7, 0), 32.0)
	get_tree().quit()
