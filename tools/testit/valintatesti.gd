extends SceneTree
## Ohjeet piilossa kunnes J, ja valintalistojen yhteinen logiikka (headless):
## godot --headless --fixed-fps 60 --path . -s tools/testit/valintatesti.gd

var main: Node3D
var fails := 0
var frames := 0
var step := 0
var t0 := 0
var Hb: GDScript
var Ui: GDScript


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Hb = load("res://scripts/happybeach.gd")
	Ui = load("res://scripts/ui.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	return ev


func _at(id: String) -> void:
	var e: Array = Hb.SPOTS[id]
	main.player.global_position = main.world.happy.world_at(e[0], e[1])
	main.player.velocity = Vector3.ZERO


func _process(_d: float) -> bool:
	frames += 1
	if frames > 3000:
		print("AIKAKATKAISU vaiheessa %d" % step)
		quit(1)
	if frames < 60:
		return false
	match step:
		0:
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 11, 21, 0)
			main.sun._update(true)
			# Yhteinen valintalogiikka: ylös/alas kiertää, numero valitsee ja vahvistaa.
			check(Ui.pick_key(_key(KEY_3), 0, 5) == {"sel": 2, "confirm": true}, "numero 3 valitsee ja vahvistaa")
			check(Ui.pick_key(_key(KEY_9), 0, 5).is_empty(), "numero yli listan ei tee mitään")
			check(Ui.pick_key(_key(KEY_S), 4, 5).get("sel", -1) == 0, "alas kiertää alkuun")
			check(Ui.pick_key(_key(KEY_W), 0, 5).get("sel", -1) == 4, "ylös kiertää loppuun")
			check(Ui.pick_key(_key(KEY_D), 1, 5).get("sel", -1) == 2 and Ui.pick_key(_key(KEY_A), 1, 5).get("sel", -1) == 0, "A/D kuten W/S")
			check(Ui.choice_text(1, "Kahvi", true) == "> 2. Kahvi" and Ui.choice_text(0, "Olut", false) == "   1. Olut", "valintarivin muoto")
			# Pajatso: ohje ei aukea itsestään, J avaa ja sulkee.
			_at("pajatso")
			main.start_activity("baari")
			check(main.baari.in_game and is_instance_valid(main.baari._gnode), "pajatso aukeaa heti")
			check(not main.ohje.is_open(), "ohje piilossa pelin alussa")
			main.baari._input(_key(KEY_J))
			check(main.ohje.is_open(), "J avaa ohjeen")
			main.ohje.close()
			main.end_activity()
			# Karaoke ja tanssi: ohje myös niissä.
			for id: String in ["karaoke", "tanssi"]:
				_at(id)
				main.start_activity("baari")
				check(not main.ohje.is_open(), "%s: ohje piilossa alussa" % id)
				main.baari._input(_key(KEY_J))
				check(main.ohje.is_open(), "%s: J avaa ohjeen" % id)
				main.ohje.close()
				main.end_activity()
			step = 1
		1:
			# Baarin tiski: näppäimistövalinta kuten muissa listoissa.
			_at("tiski")
			main.start_activity("baari")
			var b: Node = main.baari
			check(b._choices.size() == 7 and b._sel == 0, "tiskillä lista (%d riviä) ja valinta ensimmäisessä" % b._choices.size())
			check(b.keeps_arrows(), "nuolet kuuluvat listalle")
			b._unhandled_input(_key(KEY_S))
			check(b._sel == 1, "alas siirtää valintaa")
			check(str(b._choices[1][0].text).begins_with("> 2."), "korostettu rivi: %s" % b._choices[1][0].text)
			var before: float = main.player.promille
			b._unhandled_input(_key(KEY_1))
			check(main.player.promille > before and b._sel == 0, "numero 1 tilaa heti (olut)")
			b.act()
			check(main.activity == "baari", "E vahvistaa korostetun rivin eikä lopeta")
			b._sel = b._choices.size() - 1
			b.act()
			check(main.activity == "", "viimeinen rivi Valmis lopettaa")
			# Jukeboksi ja Sinikka käyttävät samaa.
			_at("jukeboksi")
			main.start_activity("baari")
			check(main.baari._choices.size() >= 2 and main.baari.keeps_arrows(), "jukeboksi on lista")
			main.end_activity()
			_at("sinikka")
			main.start_activity("baari")
			check(main.baari._choices.size() == 4, "Sinikka: kolme valintaa ja Valmis")
			main.end_activity()
			# Ohje ei aukea itsestään lautapeleissä.
			main.ohje.open_first("trivia")
			check(not main.ohje.is_open(), "open_first ei avaa ohjetta")
			print("--- %d virhettä" % fails)
			quit(1 if fails > 0 else 0)
	return false
