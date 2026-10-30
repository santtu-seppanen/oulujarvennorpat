extends SceneTree
## Puutesti: korttilohkojen välit täsmäävät puiden paikkoihin, lohkot rakentuvat ja karsiutuvat pelaajan mukana ja
## törmäysrungot seuraavat lähipuita pienestä poolista.
## godot --headless --path . -s tools/testit/puutesti.gd

var main: Node3D
var frames := 0
var errors := 0
var tall := -1


func check(ok: bool, what: String) -> void:
	print("%s %s" % ["OK  " if ok else "VIKA", what])
	if not ok:
		errors += 1


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	var tr = main.world.trees
	if frames == 3:
		# Jokainen puu löytyy oman lajinsa ja 32 m ruutunsa väleistä, ja välit kattavat keskilohkon.
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var bad := 0
		for _i in 3000:
			var i := rng.randi_range(0, tr.count - 1)
			var k := Vector2i(floori((tr.data_a[i * 4] + tr.half) / tr.CARD_CHUNK), floori((tr.data_a[i * 4 + 2] + tr.half) / tr.CARD_CHUNK))
			var r: Vector2i = tr._card_range(k, tr.data_b[i * 4 + 1])
			if i < r.x or i >= r.x + r.y:
				bad += 1
		check(bad == 0, "puut kuuluvat oman korttilohkonsa väliin (%d väärin)" % bad)
		var sum_ok := true
		for mid in [Vector2i(40, 40), Vector2i(41, 39), Vector2i(10, 70)]:
			for sp in tr.SPECIES:
				var whole: Vector2i = tr._range(tr.near_tab, mid.y * tr.nn + mid.x, sp)
				var n := 0
				for j in 4:
					for i in 4:
						n += tr._card_range(Vector2i(mid.x * 4 + i, mid.y * 4 + j), sp).y
				sum_ok = sum_ok and n == whole.y
		check(sum_ok, "korttilohkot summautuvat keskilohkoksi")
		# Pelaaja korkean puun viereen.
		for i in tr.count:
			if tr.data_a[i * 4 + 3] > 8.0 and absf(tr.data_a[i * 4]) < 400.0 and absf(tr.data_a[i * 4 + 2]) < 400.0 \
					and tr.data_b[i * 4 + 1] != tr.BUSH:
				tall = i
				break
		check(tall >= 0, "korkea puu löytyy")
		main.player.global_position = Vector3(tr.data_a[tall * 4] + 3.0, tr.data_a[tall * 4 + 1] + 1.0, tr.data_a[tall * 4 + 2])
	if frames == 120:
		check(tr._built.size() > 20, "korttilohkoja rakennettu (%d)" % tr._built.size())
		check(tr._built_mid.size() > 20, "keskilohkoja rakennettu (%d)" % tr._built_mid.size())
		check(tr._queue.is_empty(), "korttijono tyhjä")
		check(tr._col_active > 0 and tr._col_active <= tr.COLLIDE_POOL, "törmäysrunkoja %d (pooli %d)" % [tr._col_active, tr.COLLIDE_POOL])
		var near := false
		for cs: CollisionShape3D in tr._col_pool:
			if not cs.disabled and cs.position.distance_to(Vector3(tr.data_a[tall * 4], tr.data_a[tall * 4 + 1] + 2.0, tr.data_a[tall * 4 + 2])) < 0.01:
				near = true
		check(near, "viereinen puu on mukana törmäyksissä")
		# Kauas: vanhat lohkot karsiutuvat, uudet rakentuvat.
		main.player.global_position = Vector3(tr.data_a[tall * 4] + 600.0, 5.0, tr.data_a[tall * 4 + 2])
	if frames == 300:
		check(tr._queue.is_empty() and tr._built.size() > 5, "uudet lohkot rakentuneet (%d)" % tr._built.size())
		var far := false
		for k: Vector2i in tr._built.keys():
			var c := Vector2((k.x + 0.5) * tr.CARD_CHUNK - tr.half, (k.y + 0.5) * tr.CARD_CHUNK - tr.half)
			if c.distance_to(Vector2(main.player.global_position.x, main.player.global_position.z)) > tr.CARD_RADIUS + tr.CARD_CHUNK + 1.0:
				far = true
		check(not far, "kaukaiset korttilohkot poistettu")
		print("Puutesti valmis, virheitä: %d" % errors)
		return true
	return false
