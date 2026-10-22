extends SceneTree
## Happy Beachin baarin sisätilojen testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/baaritesti.gd
## Sisään ovesta, toimintopisteet (tiski, karaoke, jukeboksi, pajatso, tanssi), tilaus nostaa promilleja, karaoke
## kuittaa tehtävän, kahvi laskee humalaa, sisällä katto piiloutuu.

var main: Node3D
var fails := 0
var frames := 0
var step := 0
var Hb: GDScript


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Hb = load("res://scripts/happybeach.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _at(id: String) -> void:
	var e: Array = Hb.SPOTS[id]
	var w: Vector3 = main.world.happy.world_at(e[0], e[1])
	main.player.global_position = w
	main.player.velocity = Vector3.ZERO


func _process(_d: float) -> bool:
	frames += 1
	if frames < 60:
		return false
	var h: Node3D = main.world.happy
	match step:
		0:
			main.sun.t_utc += 2.0 * 86400.0  # lauantai
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 11, 21, 0)
			main.sun._update(true)
			_at("tiski")
			step = 1
		1:
			check(Hb.is_open(main.sun.local()), "baari auki lauantaina klo 21")
			for hh in [[19, false], [20, true], [23, true], [1, true], [2, false], [12, false]]:
				check(Hb.is_open({"hour": hh[0], "weekday": 0}) == hh[1], "aukioloaika 20–02: klo %d" % hh[0])
			check(h.spot_at(main.player.global_position).get("id", "") == "tiski", "tiskin toimintopiste")
			check(Hb.in_building(main.player.global_position), "pelaaja sisällä")
			main.start_activity("baari")
			check(main.activity == "baari", "baari-aktiviteetti alkaa")
			var before: float = main.player.promille
			main.baari._order(0)
			check(main.player.promille > before, "olut nostaa promilleja")
			var drunk: float = main.player.promille
			main.baari._order(4)
			check(main.player.promille < drunk, "kahvi laskee humalaa")
			main.end_activity()
			check(main.activity == "", "aktiviteetti loppuu")
			for id: String in ["jukeboksi", "pajatso", "tanssi", "karaoke"]:
				_at(id)
				check(h.spot_at(main.player.global_position).get("id", "") == id, "toimintopiste " + id)
			_at("pajatso")
			main.start_activity("baari")
			check(main.baari.in_game and is_instance_valid(main.baari._gnode), "pajatso (Normipäivän minipeli) aukeaa")
			main.end_activity()
			check(not main.baari.in_game, "pajatso sulkeutuu")
			_at("hedelma")
			main.start_activity("baari")
			check(main.baari.in_game and is_instance_valid(main.baari._gnode), "hedelmäpeli (Normipäivän minipeli) aukeaa")
			main.end_activity()
			_at("jukeboksi")
			main.start_activity("baari")
			main.baari._play(main.baari.TRACKS[0])
			check(h.music_playing(), "jukeboksi soi")
			main.end_activity()
			h.play_music(null)
			# Liika flirtti Sinikan kanssa: vaimo soittaa, maine laskee.
			var maine0: int = main.maine
			main.baari._flirt = 0.0
			for k in 3:
				main.baari._flirt_add(1.6)
			check(main.maine == maine0 - main.baari.MAINE_LOSS, "vaimon puhelu: maine laski %d -> %d" % [maine0, main.maine])
			check(main.baari._call_ui.visible, "puhelu näkyy ruudulla")
			_at("karaoke")
			main.start_activity("baari")
			step = 2
			frames = 60
		2:
			if frames < 140:
				return false
			var b = main.baari
			var kg = b._gnode
			check(b.in_game and kg != null and kg.real and kg._notes.size() > 20, "karaoke: Frets on Fire -versio, Oodin nuotit (%d)" % kg._notes.size())
			check(kg._title == "Oodi Oulujärvelle", "karaoken kappale on Oodi Oulujärvelle")
			check(kg._track != null and kg._track.playing, "Oodin säestys soi")
			kg._t = kg._end + 1.0  # kappale läpi
			kg._finish()
			check(not b.in_game and main.activity == "", "karaoke päättyy ja aktiviteetti loppuu")
			main.end_activity()
			# Ulkoa ovesta sisään: ovi tunnistetaan, taskussa lattialla pysytään (ei putoa), ovi ulos.
			var w: Vector2 = main.world.happy.cw_door("terassi")
			main.player.global_position = Vector3(w.x, h.pad_y + 0.2, w.y)
			check(h.door_at(main.player.global_position) == "terassi", "ulko-ovi tunnistetaan")
			check(main._interaction().get("text", "").find("sisään") >= 0, "E-vihje: sisään ravintolaan")
			h.enter("terassi")
			check(Hb.in_building(main.player.global_position), "taskussa sisällä")
			step = 3
			frames = 60
		3:
			if frames < 120:
				return false
			var y: float = main.player.global_position.y
			check(absf(y - (h.pocket.global_position.y + Hb.FLOOR_H)) < 0.3, "pelaaja pysyy lattialla (y %.2f)" % y)
			check(main._interaction().get("text", "").find("ulos terassille") >= 0, "E-vihje: ulos terassille")
			h.leave("terassi")
			check(not Hb.in_building(main.player.global_position), "ulkona ei sisällä")
			check(not h.in_pocket(main.player.global_position), "ulkona ei taskussa")
			print("Baaritesti valmis, virheitä: %d" % fails)
			return true
	return false
