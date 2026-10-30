extends SceneTree
## Keskiyön oodin testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/ooditesti.gd
## - Sanat ja sävel täsmäävät: joka rivillä yhtä monta sanaa kuin säveltä, rivi 2 tahtia.
## - Klo 0.00 tietokoneen hahmot kävelevät etuterassin kaiteelle, laulu alkaa säestyksellä, rivit kuplina
##   laulajien päällä, ja lopuksi porukka palaa omiin puuhiinsa.

var Oodi: GDScript

var main: Node3D
var Mokki: GDScript
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var m0 := 0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Mokki = load("res://scripts/mokki.gd")
	Oodi = load("res://scripts/oodi.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = clock


func _process(delta: float) -> bool:
	clock += delta
	var t := clock - ts
	var o: Node = main.oodi
	match step:
		0:
			var ok := true
			for part in Oodi.SONG:
				for r in 4:
					var mel: Array = part[0][r]
					var n: int = Oodi.words(part[1][r]).size()
					var beats := 0
					for d: int in mel[1]:
						beats += d
					if n != mel[0].size() or mel[0].size() != mel[1].size() or beats != Oodi.LINE:
						ok = false
						print("  rivi '%s': %d sanaa, %d säveltä, %d iskua" % [part[1][r], n, mel[0].size(), beats])
			check(ok, "sanat ja sävel täsmäävät")
			check(Oodi.lines().size() == 34, "laulussa %d sanaa" % Oodi.lines().size())
			check(ResourceLoader.exists(Oodi.MUSIC), "säestys olemassa")
			next()
		1:
			if clock > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 23, 59)
				main.car.driver = main.player  # ajossa mökillä ei tapahdu mitään
				m0 = main.maine
				step = 11
				ts = clock
		11:
			if o.state == "laulu" or t > 90.0:
				check(main.travelling() and o.state == "laulu", "autolla ajaessa oodi käynnistyy (pelaaja poissa)")
				check(o._away and o._away_text == "matkalla", "ajossa oleva lasketaan poissaolevaksi")
				check(main.maine < m0, "missatusta oodista menetetään mainepisteitä (%d -> %d)" % [m0, main.maine])
				main.car.driver = null
				o._end()
				o._day = -1
				main.maine = m0
				step = 12
				ts = clock
		12:
			if t > 15.0:  # porukka ehtii asettua ennen toista oodia
				main.kahvi._set_count(3)
				main.kokkaus._set_count(2)
				main.tarjoilu._set_steaks(4)
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 23, 59)
				step = 2
				ts = clock
		2:
			if o.state == "kokoontuu" or t > 10.0:
				check(o.state == "kokoontuu", "keskiyöllä porukka kokoontuu")
				var n := 0
				for j in main.crew.size():
					var b: Node3D = main.crew[j]
					if main.crew_modes[j] == "ai" and b.brain != null and b.brain.activity == "oodi":
						n += 1
				check(n == 3, "tietokoneen hahmot (%d) matkalla etuterassille" % n)
				next()
		3:
			if o.state == "laulu" or t > 60.0:
				check(o.state == "laulu", "laulu alkoi %.0f s:n jälkeen" % t)
				for j in main.crew.size():
					var b: Node3D = main.crew[j]
					if main.crew_modes[j] != "ai":
						continue
					var s: Vector3 = o.spot(j)
					var d := Vector2(b.global_position.x - s.x, b.global_position.z - s.z).length()
					print("  %s: %.2f m paikaltaan, %s" % [b.display_name, d, b.pose])
					check(d < 0.8 and b.brain.singing_ready(), "%s etuterassin kaiteella" % b.display_name)
				check(o._player.stream != null, "säestys soi")
				next()
		4:
			if t > 8.0:
				# Ensimmäinen rivi kuplana ensimmäisen laulajan päällä.
				check(o._next > 0 and main.chat._bubbles.has(0), "ensimmäinen rivi laulettu (%d sanaa)" % o._next)
				o._t = (Oodi.beats() - 12) * 60.0 / Oodi.BPM  # loppuun
				next()
		5:
			if o.state == "" or t > 20.0:
				check(o.state == "" and o._next == Oodi.lines().size(), "kaikki %d sanaa laulettu ja laulu päättyi" % o._next)
				var free := true
				for j in main.crew.size():
					var b: Node3D = main.crew[j]
					if main.crew_modes[j] == "ai" and b.brain.activity == "oodi":
						free = false
				check(free, "porukka palasi omiin puuhiinsa")
				next()
		6:
			if t > 3.0:
				check(o.state == "", "samana yönä ei uudestaan")
				check(main.kahvi.kupit == 0 and main.kokkaus.annokset == 0 and main.tarjoilu.pihvit == 0, "oodin jälkeen kahvit ja ruoat nollattu")
				main.kokkaus._set_count(3)
				main.tarjoilu.add_steaks(2)
				check(main.kokkaus.annokset == 0 and main.tarjoilu.pihvit == 2, "pihvien tullessa pyttipannu katoaa")
				main.tennis.session = true  # kaikki pelaamassa
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 8, 12, 0)
				next()
		7:
			if t > 2.0:
				check(main.ball_playing() and main.kokkaus.annokset == 0, "pallopelin aikana ei tehdä ruokaa")
				main.tennis.session = false
				next()
		8:
			var mk: CharacterBody3D = main.crew[main.tarjoilu._marko_index()]
			if mk.brain != null and (mk.brain.activity == "kokkaus" or mk.brain._want == "kokkaus") or t > 20.0:
				check(main.kokkaus.annokset == 0, "pyttipannua ei ole ennen kuin Marko on paistanut")
				check(mk.brain.activity == "kokkaus" or mk.brain._want == "kokkaus", "pelin loputtua Marko menee paistamaan")
				next()
		9:
			if main.kokkaus.annokset > 0 or t > 150.0:
				check(main.kokkaus.annokset > 0, "Markon paistama pyttipannu tulee pöytään (%d, %.0f s)" % [main.kokkaus.annokset, t])
				main.kahvi._set_count(0)
				step = 10
				ts = clock
		10:
			if t > 3.0:
				main._coffee_day = -1
				main._coffee_call()
				check(main._coffee_pending and main.kahvi.kupit == 0, "ilman keitettyä kahvia ei kahvia eikä huutoa")
				main.kahvi.add(2)
				step = 13
				ts = clock
		13:
			if t > 1.0:
				check(not main._coffee_pending and main._coffee_day == main.sun.local().day, "kun kahvia on, Jukka huutaa kahville")
				main.tarjoilu._set_steaks(0)
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 8, 20, 0)
				next()
		14:
			if main.tarjoilu.pihvit > 0 or t > 200.0:
				check(main.tarjoilu.pihvit > 0, "Markon grillaamat pihvit tulevat pöytään (%d, %.0f s)" % [main.tarjoilu.pihvit, t])
				print("vikoja %d" % fails)
				quit(1 if fails > 0 else 0)
	return false
