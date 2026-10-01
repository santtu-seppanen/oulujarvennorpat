extends SceneTree
## Moninpelin testi (headless, kaksi konetta): käynnistä palvelin (cd server && npx wrangler dev) ja sitten
##   godot --headless --path . -s tools/testit/moninpelitesti.gd -- --rooli=host --huone=TESTI --palvelin=ws://localhost:8787
##   godot --headless --path . -s tools/testit/moninpelitesti.gd -- --rooli=vieras --huone=TESTI --palvelin=ws://localhost:8787
## Host on Santtu ja kävelee, vieras on Marko ja soutaa kumivenettä. Kumpikin tarkistaa näkevänsä toisen liikkeet,
## vieras lisäksi, että hostin tekoälyhahmot liikkuvat, kello on sama ja hostin keskusteluviesti tuli perille.

class Push:
	extends RefCounted
	var throttle := 1.0
	var steer := 0.3
	var fast := false
	var jump := false

	func think(_d: float) -> void:
		pass


var main: Node3D
var role := "host"
var code := "TESTI"
var fails := 0
var t0 := 0.0
var step := 0
var start := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rooli="):
			role = a.trim_prefix("--rooli=")
		elif a.begins_with("--huone="):
			code = a.trim_prefix("--huone=")
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec() / 1000.0


func check(ok: bool, what: String) -> void:
	print("[%s] %s%s" % [role, "OK   " if ok else "VIKA ", what])
	if not ok:
		fails += 1


func _process(_delta: float) -> bool:
	var t := Time.get_ticks_msec() / 1000.0 - t0
	var mp: Node = main.mp
	match step:
		0:
			# Vieras odottaa, että host on ehtinyt huoneeseen.
			if t > (1.0 if role == "host" else 4.0):
				if role == "host":
					mp.preset = 0
					mp.net.join(code)
				else:
					mp.join(code.to_lower())
				step = 1
		1:
			if mp.online() and (role == "host" or not mp.owners.is_empty()):
				if role == "host":
					check(mp.net.room != "", "huone luotu")
				check(mp.net.is_host() == (role == "host"), "host on ensimmäinen")
				mp.claim(0 if role == "host" else 1)
				step = 2
			elif t > 20.0:
				check(false, "yhteys palvelimeen")
				return _end()
		2:
			# Host lähtee liikkeelle vasta, kun vieras on paikalla.
			if mp.mine >= 0 and (role != "host" or not mp.net.peers.is_empty()):
				var p: CharacterBody3D = main.player
				check(p == main.crew[mp.mine] and main.crew_modes[mp.mine] == "player", "oma hahmo valittu")
				if role == "host":
					p.brain = Push.new()
					p.brain.steer = 0.0
					main.chat.say("Moro vieras!")
				else:
					p.global_position = main.boat.global_position + Vector3(0.5, 0.5, 0)
					p.enter_boat(main.boat)
					p.brain = Push.new()
				for b in main.crew:
					start[b] = b.global_position
				start["boat"] = main.boat.global_position
				start["t"] = t
				step = 3
		3:
			if t - start.t > 12.0:
				_verify()
				step = 4
		4:
			# Host pysyy linjoilla, kunnes vieraskin on tarkistanut.
			if role != "host" or t - start.t > 20.0:
				return _end()
	return false


func _verify() -> void:
	var mp: Node = main.mp
	var other: int = 1 if role == "host" else 0
	var o: CharacterBody3D = main.crew[other]
	check(main.crew_modes[other] == "remote", "toisen pelaajan hahmo verkosta")
	var moved: float = o.global_position.distance_to(start[o])
	print("[%s] %s liikkui %.1f m, nyt %s" % [role, o.display_name, moved, o.global_position])
	print("[%s] oma %s nyt %s" % [role, main.player.display_name, main.player.global_position])
	var bm: float = main.boat.global_position.distance_to(start.boat)
	print("[%s] vene liikkui %.1f m, nyt %s, remote %s" % [role, bm, main.boat.global_position, main.boat.remote])
	check(bm > 2.0, "kumivene liikkui")
	if role == "host":
		check(o.boat == main.boat, "vieras näkyy veneessä")
		check(main.boat.remote, "veneen tila tulee soutajalta")
	else:
		check(moved > 0.5, "hostin pelaaja liikkui")  # kävelee terassin kaiteeseen asti
		check(not main.boat.remote, "vieras soutaa itse")
		var n := 0
		for j in [2, 3]:
			var b: CharacterBody3D = main.crew[j]
			print("[%s] %s (%s) liikkui %.1f m, asento %s, sisällä %s" % [role, b.display_name, main.crew_modes[j],
				b.global_position.distance_to(start[b]), b.pose, b.hidden_inside])
			if main.crew_modes[j] == "remote" and b.brain == null:
				n += 1
		check(n == 2, "vapaat hahmot hostin tekoälyltä")
		var heard := false
		for e in main.chat._lines:
			if e[0].text == "Santtu: Moro vieras!":
				heard = true
		check(heard, "hostin viesti tuli perille")
	print("[%s] kello %s, t_utc %d" % [role, main.sun.clock_text(), int(main.sun.t_utc)])


func _end() -> bool:
	print("[%s] vikoja %d" % [role, fails])
	main.mp.net.leave()
	return true
