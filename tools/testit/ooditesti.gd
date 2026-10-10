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
					var n: int = (part[1][r] as String).split(" ").size()
					var beats := 0
					for d: int in mel[1]:
						beats += d
					if n != mel[0].size() or mel[0].size() != mel[1].size() or beats != Oodi.LINE:
						ok = false
						print("  rivi '%s': %d sanaa, %d säveltä, %d iskua" % [part[1][r], n, mel[0].size(), beats])
			check(ok, "sanat ja sävel täsmäävät")
			check(Oodi.lines().size() == 76, "laulussa %d sanaa" % Oodi.lines().size())
			check(ResourceLoader.exists(Oodi.MUSIC), "säestys olemassa")
			next()
		1:
			if clock > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 23, 59)
				next()
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
				print("vikoja %d" % fails)
				quit(1 if fails > 0 else 0)
	return false
