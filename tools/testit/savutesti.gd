extends SceneTree
## Savutesti: rakentaa pelin ilman valikkoa, ajaa fysiikkaa hetken ja tarkistaa maaston, puut ja pelaajan.
## godot --headless --path . -s tools/testit/savutesti.gd

const Terrain := preload("res://scripts/terrain.gd")

var main: Node3D
var frames := 0
var t0 := 0


func _initialize() -> void:
	t0 = Time.get_ticks_msec()
	var Main := load("res://scripts/main.gd")
	Main.skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	print("rakennus %d ms" % (Time.get_ticks_msec() - t0))


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 5:
		# Törmäyspinta vs. Terrain.h satunnaisissa pisteissä.
		var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
		var worst := 0.0
		var rng := RandomNumberGenerator.new()
		for i in 300:
			var x := rng.randf_range(-900, 900)
			var z := rng.randf_range(-900, 900)
			var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80, z), Vector3(x, -40, z), Terrain.COLLISION_LAYER)
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				print("ei osumaa ", x, " ", z)
				continue
			worst = maxf(worst, absf(hit.position.y - Terrain.h(x, z)))
		print("törmäys vs h(): suurin ero %.4f m" % worst)
		var s: Vector3 = main.world.start_position()
		print("aloitus ", s, " pinta ", Terrain.SURFACE_NAMES[Terrain.surface(s.x, s.z)])
		print("puita ", main.world.trees.count)
	if frames == 200:
		main.player.global_position = Vector3(0, 0.0, -300)  # järvellä
	if frames == 236:
		var q: Vector3 = main.player.global_position
		print("järvellä: syvyys %.2f m, ui %s, y %.2f" % [main.player.water_depth, main.player.swimming, q.y])
		assert(main.player.swimming)
		main.player.global_position = main.world.start_position() + Vector3(0, 0.2, 0)
	if frames == 240:
		var p: Vector3 = main.player.global_position
		print("pelaaja 4 s jälkeen ", p, " maa ", Terrain.h(p.x, p.z), " lattialla ", main.player.is_on_floor())
		print("lähilohkoja ", main.world.trees._built.size(), " jonossa ", main.world.trees._queue.size())
		print("solmuja ", main.get_tree().get_node_count())
		return true
	return false
