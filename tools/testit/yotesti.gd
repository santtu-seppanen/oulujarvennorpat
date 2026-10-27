extends SceneTree
## Pankkiautomaatti, oodin jälkeinen yöuni ylämökissä, sauna sammuu (sytytysminipeli), pokerin PIDÄ-kyltti ja häviöruudun E
## (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/yotesti.gd

var main: Node3D
var fails := 0
var frames := 0
var step := 0
var t0 := 0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)


func _process(_d: float) -> bool:
	frames += 1
	if frames > 2500:
		print("AIKAKATKAISU vaiheessa %d" % step)
		quit(1)
	if frames < 60:
		return false
	var h: Node3D = main.world.happy
	match step:
		0:
			# Pankkiautomaatti: 20 € kerran päivässä.
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 11, 14, 0)
			var w: Vector2 = load("res://scripts/reitti.gd").cw(h.ATM.x, h.ATM.y)
			main.player.global_position = Vector3(w.x, load("res://scripts/terrain.gd").h(w.x, w.y) + 0.1, w.y)
			main.player.velocity = Vector3.ZERO
			step = 1
		1:
			check(h.atm_near(main.player.global_position), "automaatin luona")
			var it: Dictionary = main._interaction()
			check(it.has("cb") and str(it.text).contains("20 €"), "nostokehote: %s" % it.get("text", ""))
			var before: int = main.baari._tokens
			it.cb.call()
			check(main.baari._tokens == before + 20, "nosto antaa 20 €")
			var again: Dictionary = main._interaction()
			check(not again.has("cb"), "toista nostoa ei samana päivänä: %s" % again.get("text", ""))
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 12, 14, 0)
			check(main._interaction().has("cb"), "seuraavana päivänä taas nosto")
			# Pokeri: PIDÄ-kyltti piirtyy ilman virheitä.
			step = 2
		2:
			var PG: GDScript = load("res://scripts/pokeri_game.gd")
			var pk: CanvasLayer = PG.new()
			root.add_child(pk)
			pk._deal()
			pk._toggle(1)
			pk._toggle(3)
			check(pk._held[1] and pk._held[3], "pokeri: kortit pidetty")
			pk._reveal = [1.0, 1.0, 1.0, 1.0, 1.0]
			var o: Vector2 = pk._origin()
			var r: Rect2 = pk._card_rect(1)
			var sign_bottom: float = r.position.y + pk.CARD_H + 14.0 + 36.0
			check(sign_bottom < o.y + 548.0, "PIDÄ-kyltti alapaneelin yläpuolella")
			pk.queue_free()
			# Sauna: tuli sammuu eikä tietokone sytytä sitä heti uudelleen.
			main.sauna.fire = 0.0
			main.sauna.temp = 90.0
			main.world.mokki.sauna_temp = 90.0
			main.world.mokki.fire_left = 0.0
			t0 = frames
			step = 3
		3:
			var m = main.world.mokki
			check(m.fire_left <= 0.0 and m.sauna_temp >= 60.0, "sauna sammunut mutta lämmin: tietokone ei hae haloja")
			main.sauna.carried[main.player_index] = 4
			main.player.global_position = m.kiuas_pos + Vector3(0.5, 0.0, 0.0)
			var it: Dictionary = main._interaction()
			check(str(it.get("text", "")).contains("sytytä"), "sytytys tarjolla: %s" % it.get("text", ""))
			main.sauna.fire = 200.0
			it = main._interaction()
			check(str(it.get("text", "")).contains("halko"), "palavaan tuleen halko: %s" % it.get("text", ""))
			main.sauna.fire = 100.0
			it = main._interaction()
			check(str(it.get("text", "")).contains("sytytä"), "hiipuvaan tuleen sytytys: %s" % it.get("text", ""))
			step = 4
		4:
			# Oodin jälkeen yöuni.
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 11, 1, 0)
			main.go_to_bed()
			check(main._nap_night and main._nap_t > 0.0, "yöuni alkaa oodin jälkeen")
			check(main._nap_scene.visible and main._nap_scene._night, "yöversio näkyy")
			var ai_in_bed := 0
			for j in main.crew.size():
				if main.crew_modes[j] == "ai" and main.crew[j].brain != null and main.crew[j].brain.activity == "yo":
					ai_in_bed += 1
			check(ai_in_bed >= 1, "tietokoneen hahmot menevät nukkumaan (%d)" % ai_in_bed)
			t0 = frames
			step = 5
		5:
			if frames - t0 < 60 * 9:
				return false
			var lamp: OmniLight3D = main._nap_scene._lamp
			check(lamp.light_energy < 0.01, "yöpöydän lamppu on sammunut")
			main._wake()
			check(main.sun.local().hour == 7, "herätys aamuseitsemältä (klo %d)" % main.sun.local().hour)
			check(not main.player.hidden_inside and main.player.controls_enabled, "pelaaja hereillä")
			step = 6
		6:
			# Moninpeli: kaverin päikkäriviesti vie myös oman pelaajan ylämökkiin; yöllä Jukka nukkuu patjalla.
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 11, 16, 0)
			main._remote_nap(false)
			check(main._nap_t > 0.0 and not main._nap_night, "kaverin päikkärit vievät mukaan")
			check(main._nap_scene.sleepers.size() == 3 and not main._nap_scene._jukka_root.visible, "päivällä kolme nukkujaa, Jukka ei")
			main._wake()
			main._remote_nap(true)
			check(main._nap_night and main._nap_scene._jukka_root.visible and main._nap_scene._jukka_ch != null, "yöllä Jukka nukkuu lattialla")
			main._wake()
			step = 9
		9:
			# Häviöruutu: vain E uudelleenkäynnistää.
			var L: Node = main.loppu
			L.start_loss()
			L._t = 100.0  # kohtaus loppuun: tekstikortti näkyviin
			check(L._card_text.contains("E: uusi peli") and not L._card_text.contains("R"), "häviöteksti: %s" % L._card_text.replace("\n", " "))
			Input.action_release("interact")
			Input.parse_input_event(_key(KEY_R, true))
			Input.parse_input_event(_key(KEY_ENTER, true))
			t0 = frames
			step = 7
		7:
			if frames - t0 < 5:
				return false
			check(main.loppu.active, "R ja Enter eivät aloita uutta peliä")
			Input.parse_input_event(_key(KEY_R, false))
			Input.parse_input_event(_key(KEY_ENTER, false))
			_press("interact")
			t0 = frames
			step = 8
		8:
			if frames - t0 < 5:
				return false
			print("loppu.active = ", main.loppu.active)
			check(not main.loppu.active, "E aloittaa uuden pelin")
			print("--- %d virhettä" % fails)
			quit(1 if fails > 0 else 0)
	return false


func _key(code: Key, down: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	return ev
