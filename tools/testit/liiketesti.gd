extends SceneTree
## Hahmojen liikkeiden testi (headless): godot --headless --path . -s tools/testit/liiketesti.gd
## Lauteilla jokainen saa oman paikan (pelaaja istuu saunojan viereen), istuvan ja seisovan läpi ei kävellä,
## tietokoneen hahmot kävelevät korttipöytään omille paikoilleen hyppimättä, pöydästä noustaan vapaaseen
## kohtaan, ja keskusteluviesti näkyy kuplana hahmon yläpuolella.

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
var t0 := 0.0
var ts := 0.0
var last := {}  # hahmo -> edellinen paikka
var jumps := {}  # hahmo -> suurin siirtymä yhdessä ruudussa kävellessä


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Mokki = load("res://scripts/mokki.gd")
	t0 = Time.get_ticks_msec() / 1000.0


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func now() -> float:
	return Time.get_ticks_msec() / 1000.0 - t0


func next() -> void:
	step += 1
	ts = now()


func flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func crew(i: int) -> CharacterBody3D:
	return main.crew[i]


func seated(b: CharacterBody3D) -> bool:
	return b.pose.begins_with("Sitting")


func _process(_delta: float) -> bool:
	var t := now() - ts
	var p: CharacterBody3D = main.player
	var m: Node3D = main.world.mokki
	match step:
		0:
			if now() > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 13, 0)
				p.global_position = m.points.loylyhuone + Vector3.UP * 0.1
				crew(2).brain._start("sauna")
				next()
		1:
			if seated(crew(2)) or t > 30.0:
				check(seated(crew(2)), "Jaakko istuu lauteilla (%.1f s)" % t)
				# Pelaaja seisoo Jaakon edessä: istuu lähimmälle vapaalle paikalle eli viereen.
				var js: Vector3 = crew(2).global_position
				p.global_position = Vector3(js.x, Mokki.DY + 0.1, js.z) + (m.points.loylyhuone - js).normalized() * 1.0
				p.global_position.y = Mokki.DY + 0.1
				main.start_activity("sauna")
				var d := flat(p.global_position, js)
				print("pelaaja %.2f m Jaakosta" % d)
				check(main.activity == "sauna" and d > 0.55 and d < 0.75, "pelaaja istuu Jaakon viereen")
				crew(1).brain._start("sauna")
				crew(3).brain._start("sauna")
				next()
		2:
			if (seated(crew(1)) and seated(crew(3))) or t > 40.0:
				var ok := true
				for i in 4:
					for j in range(i + 1, 4):
						if flat(crew(i).global_position, crew(j).global_position) < 0.5:
							ok = false
				check(seated(crew(1)) and seated(crew(3)), "kaikki neljä lauteilla (%.1f s)" % t)
				check(ok, "jokaisella oma paikka")
				check(m.free_seat(m.sauna_seats, null) == -1, "lauteet täynnä")
				main.end_activity()
				next()
		3:
			if t > 0.5:
				next()
		4:
			if t > 0.5:
				# Kaikki keittiöön: ristiseiska.
				for i in [1, 2, 3]:
					crew(i).brain.reset()
					var w: Vector2 = Mokki.yw(-6.9 + i * 0.8, 1.5)  # rivissä teltan edessä
					crew(i).global_position = Vector3(w.x, Mokki.DY + 0.1, w.y)
				p.global_position = m.points.keittio + Vector3.UP * 0.05
				next()
		5:
			if t > 0.5:
				main.kortit.bot_delay = 30.0  # tietokone ei pelaa ennen kuin kaikki ovat pöydässä
				main.start_activity("kortit")
				main.kortit.act()
				for i in [1, 2, 3]:
					last[i] = crew(i).body().global_position
					jumps[i] = 0.0
				next()
		6:
			var all := true
			for i in [1, 2, 3]:
				var b := crew(i)
				jumps[i] = maxf(jumps[i], flat(b.body().global_position, last[i]))
				if not seated(b):
					all = false
				last[i] = b.body().global_position
			if all or t > 45.0:
				print("pöydässä %.1f s:n jälkeen" % t)
				for i in [1, 2, 3]:
					var b := crew(i)
					var seat: Vector3 = m.table_seats[i][0]
					print("  %s: %s, paikalta %.2f m, suurin hyppy %.2f m" % [b.display_name, b.pose,
						flat(b.global_position, seat), jumps[i]])
					check(seated(b) and flat(b.global_position, seat) < 0.15, "%s omalla paikallaan" % b.display_name)
					check(jumps[i] < 0.3, "%s käveli pöytään (ei siirtoa)" % b.display_name)
				# Joku seisoo pelaajan takana: noustaan sivulle.
				var fwd := -p.global_transform.basis.z
				var j := crew(3)
				j.brain.reset()
				j.brain = Push.new()
				j.brain.throttle = 0.0
				j.global_position = p.global_position - fwd * 0.45 + Vector3.UP * 0.05
				next()
		7:
			if t > 0.5:
				main.end_activity()
				next()
		8:
			if t > 0.5:
				var d := flat(p.global_position, crew(3).global_position)
				print("noustessa %.2f m takana seisovasta" % d)
				check(d > 0.5, "pöydästä noustaan vapaaseen kohtaan")
				check(Mokki.room_at(p.global_position) == "keittio", "noustu keittiöön (%s)" % Mokki.room_at(p.global_position))
				# Pelaaja kävelee pöydässä istuvaa Markoa päin: ei mene sisään.
				var ms: Vector3 = crew(1).global_position
				var east: Vector3 = Vector3(Mokki.EAST.x, 0, Mokki.EAST.y)
				p.global_position = Vector3(ms.x, Mokki.DY + 0.1, ms.z) - east * 0.9
				p.rotation.y = atan2(-east.x, -east.z)
				p.brain = Push.new()
				next()
		9:
			if t > 2.0:
				p.brain = null
				var d := flat(p.global_position, crew(1).global_position)
				print("pelaaja jäi %.2f m päähän istuvasta Markosta" % d)
				check(d > 0.5 and seated(crew(1)), "istuvan läpi ei kävellä")
				# Keskustelu.
				main.chat.say("Moro, kuka pelaa?")
				var found := false
				for c in p.get_children():
					if c is Label3D and c.text == "Moro, kuka pelaa?":
						found = true
				check(found, "viesti kuplana pelaajan yläpuolella")
				main.chat.show_message(2, "Minä!")
				found = false
				for c in crew(2).get_children():
					if c is Label3D and c.text == "Minä!":
						found = true
				check(found, "toisen viesti kuplana hänen yläpuolellaan")
				print("vikoja %d" % fails)
				return true
	if now() > 200.0:
		check(false, "aikaraja (vaihe %d)" % step)
		return true
	return false
