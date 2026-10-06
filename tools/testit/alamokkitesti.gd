extends SceneTree
## Alamökin testi (headless): godot --headless --path . -s tools/testit/alamokkitesti.gd
## Ovista sisään keittiöön ja saunaan, tietokoneen hahmot lauteilla ja hellalla, saunominen, pyttipannun paisto
## (vain Marko), annoksen syönti, kokonainen ristiseiskapeli pöydässä sekä kätkön olut ja viina: humala heittelee
## ohjausta, tolkuttomana konttaillaan ja lopulta sammutaan.

class Push:
	extends RefCounted
	var throttle := 1.0
	var steer := 0.0
	var fast := false
	var jump := false

	func think(_d: float) -> void:
		pass



var main: Node3D
var Mokki: GDScript
var fails := 0
var step := 0
var clock := 0.0  # pelin aika (headless --fixed-fps ajaa seinäkelloa nopeammin)
var ts := 0.0  # vaiheen alku
var start_rot := 0.0
var start_pos := Vector3.ZERO


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Mokki = load("res://scripts/mokki.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func now() -> float:
	return clock


func next() -> void:
	step += 1
	ts = now()


func _put(p: CharacterBody3D, name: String, toward: String) -> void:
	var m: Node3D = main.world.mokki
	var a: Vector3 = m.points[name]
	var b: Vector3 = m.points[toward]
	p.global_position = a + Vector3.UP * 0.1
	p.rotation.y = atan2(-(b - a).x, -(b - a).z)
	p.velocity = Vector3.ZERO


func _process(delta: float) -> bool:
	clock += delta
	var t := now() - ts
	var p: CharacterBody3D = main.player
	var m: Node3D = main.world.mokki
	match step:
		0:
			if now() > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 13, 0)  # keskipäivä: ei auringonlaskua
				# Keittiön ovesta sisään kävellen.
				_put(p, "keittio_ovi", "keittio")
				p.brain = Push.new()
				next()
		1:
			if t > 2.5:
				p.brain = null
				check(Mokki.room_at(p.global_position) == "keittio", "kävellen ovesta keittiöön (%s)" % Mokki.room_at(p.global_position))
				# Saunan ovesta suoraan löylyhuoneeseen.
				_put(p, "sauna_ovi", "loylyhuone")
				p.brain = Push.new()
				next()
		2:
			if t > 1.2:
				check(Mokki.room_at(p.global_position) == "loylyhuone", "saunan ovesta löylyhuoneeseen (%s)" % Mokki.room_at(p.global_position))
				next()
		3:
			if t > 0.2:
				p.brain = null
				check(main._interaction().get("text", "") == "E: istu lauteille", "löylyhuoneessa voi istua lauteille")
				# Tietokoneen hahmot: Jaakko saunaan, Marko hellalle.
				main.crew[2].brain._start("sauna")
				main.crew[1].brain._start("kokkaus")
				main.start_activity("sauna")
				check(main.activity == "sauna" and p.pose.begins_with("Sitting"), "lauteilla istutaan")
				check(p.global_position.y > Mokki.DY + 0.4, "ylälauteella (y %.2f)" % (p.global_position.y - Mokki.DY))
				main.sauna.act()
				next()
		4:
			if t > 3.0 and t < 3.1:
				main.sauna.act()
			if t > 9.0:
				print("kuumuus %.0f, löyly %.0f, pisteet %.1f" % [main.sauna.heat, main.sauna.loyly, main.sauna.points])
				check(main.sauna.points > 0.5, "löylyistä pisteitä")
				next()
		5:
			# Löylyä koko ajan: kuumuus nousee liian korkeaksi.
			if fmod(t, 0.8) < 0.02 and main.activity == "sauna":
				main.sauna.act()
			if main.activity == "" or t > 30.0:
				print("ajettiin pois %.1f s:n jälkeen" % t)
				check(main.activity == "", "liian kuuma ajaa pois lauteilta")
				check(not p.pose.begins_with("Sitting") and not p._shape.disabled, "noustu lauteilta")
				next()
		6:
			if t > 1.0:
				print("pois lauteilta: %s, y %.2f" % [Mokki.room_at(p.global_position), p.global_position.y - Mokki.DY])
				check(Mokki.room_at(p.global_position) == "loylyhuone" and p.global_position.y < Mokki.DY + 0.7, "lauteilta lattialle")
				# Pyttipannua: ensin Santtuna (ei osaa), sitten Markona.
				p.global_position = m.cook_spot + Vector3.UP * 0.05
				next()
		7:
			var jj: Node3D = main.crew[2]
			var mm: Node3D = main.crew[1]
			var arrived: bool = jj.pose.begins_with("Sitting") and mm.global_position.distance_to(m.cook_spot) < 0.8
			if t > 0.3 and (arrived or t > 40.0):
				print("tietokoneen hahmot perillä %.1f s:n jälkeen" % t)
				check(main._interaction().get("text", "") == "Vain Marko osaa tehdä pyttipannua", "vain Marko osaa kokata")
				var j: Node3D = main.crew[2]
				print("Jaakko: %s %s, %s" % [j.brain.activity, j.pose, Mokki.room_at(j.global_position)])
				var mk: Node3D = main.crew[1]
				print("Marko: %s %s, hellalle %.1f m" % [mk.brain.activity, mk.pose, mk.global_position.distance_to(m.cook_spot)])
				check(j.pose.begins_with("Sitting") and Mokki.room_at(j.global_position) == "loylyhuone", "tietokoneen Jaakko lauteilla")
				check(mk.global_position.distance_to(m.cook_spot) < 0.8, "tietokoneen Marko hellalla")
				mk.brain._timer = 0.0  # Marko lopettaa: annoksia lautaselle
				next()
		8:
			if t > 0.5:
				var n: int = main.kokkaus.annokset
				check(n >= 2, "tietokoneen Marko paistoi pyttipannua (%d)" % n)
				main.kokkaus._set_count(0)
				main.choose_character(1)
				p = main.player
				p.global_position = m.cook_spot + Vector3.UP * 0.05
				next()
		9:
			if t > 0.5:
				check(main._interaction().get("text", "") == "E: paista pyttipannua", "Marko voi paistaa")
				main.start_activity("kokkaus")
				check(main.activity == "kokkaus", "paisto alkaa")
				main.kokkaus.act()  # perunat pannulle
				next()
		10:
			if t > 3.5:
				main.kokkaus.act()  # sipuli ja makkara
				next()
		11:
			if t > 3.5:
				main.kokkaus.act()  # lautaselle
				check(main.kokkaus.annokset == 1, "pyttipannu lautaselle (%d)" % main.kokkaus.annokset)
				main.kokkaus.act()
				next()
		12:
			if t > 6.5:
				check(main.kokkaus._state == "", "liian kauan pannulla: pyttipannu palaa")
				check(main.kokkaus.annokset == 1, "palanut ei mene lautaselle")
				main.end_activity()
				# Pöytään: annoksen syönti ja ristiseiska.
				p.global_position = m.points.keittio + Vector3.UP * 0.05
				p.stamina = 20.0
				main.kortit.bot_delay = 0.4
				next()
		13:
			if t > 0.5:
				check(main._interaction().get("text", "").begins_with("E: istu pöytään"), "pöytään voi istua")
				main.start_activity("kortit")
				check(main.kokkaus.annokset == 0 and p.stamina > 99.0, "pöydässä syötiin pyttipannua")
				check(main.kortit._ui.visible, "korttinäkymä auki")
				main.kortit.act()
				check(main.kortit.logic.phase == "play", "kortit jaettu")
				for j in [0, 2, 3]:
					print("%s: %s" % [main.crew[j].display_name, main.crew[j].brain.activity])
				next()
		14:
			var k = main.kortit
			var L = k.logic
			if L.phase != "over" and L.actor() == main.player_index:
				if L.phase == "play":
					k._on_card(L.bot_play(main.player_index, k._rng))
				else:
					k._on_card(L.bot_give(main.player_index, k._rng))
			if L.phase == "over" or t > 90.0:
				check(L.phase == "over" and L.finished.size() == 4, "ristiseiska pelattiin loppuun (%d siirtoa)" % L.moves)
				var near := 0
				for j in [0, 2, 3]:
					var b: Node3D = main.crew[j]
					if Mokki.room_at(b.global_position) == "keittio":
						near += 1
				print("voittaja %s, keittiössä tietokoneen hahmoja %d" % [main.Porukka.CREW[L.finished[0]].name, near])
				check(near >= 1, "tietokoneen hahmoja tuli pöytään")
				main.end_activity()
				check(not main.kortit._ui.visible and main.activity == "", "pöydästä noustu")
				# Kätkölle saunan taakse.
				_put(p, "katko", "sauna_ovi")
				p.promille = 0.0
				next()
		15:
			if t > 0.5:
				check(main._near_stash() and main._interaction().get("text", "").begins_with("E: kylmä olut"), "kätkö saunan takana")
				for k in 4:
					main._beer()
				print("neljä olutta: %.2f ‰ (%s)" % [p.promille, main.drunk_text(p.promille)])
				check(p.promille > 0.8 and p.pose != "Ryomii", "humalassa mutta kävelee")
				# Suoraan kävely heittelee: suunta muuttuu, vaikka ohjataan suoraan.
				ts = now()
				p.global_position = main.world.mokki.points.piha + Vector3.UP * 0.1
				start_rot = p.rotation.y
				p.brain = null
				Input.action_press("forward")
				next()
		16:
			if t > 2.5:
				Input.action_release("forward")
				var turn := absf(wrapf(p.rotation.y - start_rot, -PI, PI))
				print("humalassa suoraan kävellessä suunta kääntyi %.0f°" % rad_to_deg(turn))
				check(turn > deg_to_rad(5.0), "humala heittelee ohjausta")
				for k in 6:
					main._booze()
				next()
		17:
			if t > 0.3:
				print("viinan jälkeen %.2f ‰, asento %s" % [p.promille, p.pose])
				check(p.pose == "Ryomii", "tolkuttomassa humalassa konttaillaan")
				start_pos = p.global_position
				Input.action_press("forward")
				next()
		18:
			if t > 2.0:
				Input.action_release("forward")
				var d: float = p.global_position.distance_to(start_pos)
				print("konttasi 2 s: %.1f m" % d)
				check(d < 1.5, "kävely ei onnistu (konttaus hidasta)")
				main._booze()
				main._booze()
				next()
		19:
			if t > 0.3:
				check(p.pose == "Sammunut", "sammuu (%.2f ‰)" % p.promille)
				start_pos = p.global_position
				Input.action_press("forward")
				next()
		20:
			if t > 1.5:
				Input.action_release("forward")
				check(p.global_position.distance_to(start_pos) < 0.2, "sammuneena ei liikuta")
				p.promille = 2.0
				next()
		21:
			if t > 0.3:
				check(p.pose == "", "herää, kun humala laskee (%s)" % p.pose)
				print("vikoja %d" % fails)
				return true
	if now() > 240.0:
		check(false, "aikaraja (vaihe %d)" % step)
		return true
	return false
