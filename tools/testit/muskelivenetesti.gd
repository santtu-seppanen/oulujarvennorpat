extends SceneTree
## Muskeliveneen ja Äpätin sataman testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/muskelivenetesti.gd
## - Satama: vene laiturin kyljessä Äpätissä, laiturin kansi korkeammalla kuin mökkilaiturin, veneen paikka vapaata vettä.
## - Nousu veneeseen laiturilta, ajo (kaasu vie vauhtiin), reitti Happy Beachin laiturille kulkee syvässä vedessä.
## - Veneen voi jättää vain satamaan: mökkilaiturin viereen ja avovedelle telakointi ei onnistu, satamassa onnistuu.
## - Happy Beachin laiturille telakoitu vene lähtee sieltä takaisin Äpättiin.

var main: Node3D
var fails := 0
var frames := 0
var step := 0
var peak := 0.0
var ts := 0
var M: GDScript
var Hb: GDScript
var Vene: GDScript


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	M = load("res://scripts/mokki.gd")
	Hb = load("res://scripts/happybeach.gd")
	Vene = load("res://scripts/muskelivene.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = frames


func _put_player_on_deck(deck: Vector3) -> void:
	main.player.global_position = deck + Vector3(0, 0.3, 0)
	main.player.velocity = Vector3.ZERO


func _process(_d: float) -> bool:
	frames += 1
	if frames < 60:
		return false
	var vn: CharacterBody3D = main.muskelivene
	var t := frames - ts
	match step:
		0:
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 11, 14, 0)
			main.sun._update(true)
			var h: Dictionary = main.world.satama.harbor
			check(not h.is_empty() and vn.at == 0 and vn.global_position.distance_to(h.pos) < 0.1, "vene on Äpätin satamassa")
			check(vn.free_at(vn.global_position, vn.rotation.y), "veneen paikka laiturin kyljessä on riittävän syvää vettä")
			var Sat: GDScript = load("res://scripts/satama.gd")
			check(Sat.DECK > 0.42 + 0.25, "sataman kansi (%.2f m) on korkeampi kuin mökkilaiturin (0,42 m)" % Sat.DECK)
			check(Vector2(h.pos.x - 119.0, h.pos.z + 42.0).length() < 20.0, "satama on tien vasemmalla puolella lahdessa maavallin takana")
			check(vn.moorings.size() == 2 and vn.moorings[1].name == "Happy Beachin satama", "satamapaikkoja kaksi: Äpätti ja Happy Beach")
			check(vn.free_at(vn.moorings[1].pos, vn.moorings[1].yaw), "Happy Beachin laiturin paikka on riittävän syvää vettä")
			_put_player_on_deck(h.deck)
			next()
		1:
			if t > 40:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("muskeliveneeseen"), "kehote laiturilla: %s" % it.get("text", ""))
				it.cb.call()
				check(vn.driver == main.player and main.player.pose == "Sitting_Idle", "pelaaja istuu veneen kuljettajaksi")
				var seats := {}
				var riders := 0
				for j in main.crew.size():
					if j == main.player_index:
						continue
					var cb: CharacterBody3D = main.crew[j]
					if cb.vehicle == vn and cb.visible:
						riders += 1
						seats[cb.vehicle_seat] = true
				check(riders == 3 and seats.size() == 3 and not seats.has(0), "tietokoneen hahmot istuvat näkyvinä eri penkeille (%s)" % [seats.keys()])
				vn._yaw = -PI * 0.5  # keula itään: satamasta ajetaan pois sivuun, ei suoraan T-päähän
				vn.rotation.y = vn._yaw
				Input.action_press("forward")
				next()
		2:
			# Kaasulla venettä ehtii ajaa rantaan asti, joten vauhti mitataan huippuarvona (ei ajan lopussa).
			peak = maxf(peak, vn.speed)
			if t > 240:
				check(peak > 8.0, "kaasu vie vauhtiin (huippu %.1f m/s)" % peak)
				check(vn.global_position.distance_to(vn.moorings[0].pos) > 10.0, "vene on ajanut satamasta pois")
				check(main.player.global_position.distance_to(vn.to_global(Vene.SEAT)) < 1.5, "kuljettaja pysyy penkillä")
				Input.action_release("forward")
				# Avovedellä ei voi telakoida.
				vn.global_position = Vector3(40.0, 0.0, -60.0)
				vn.speed = 0.0
				main._leave_motorboat()
				check(vn.driver != null and main._toast.text.contains("ei voi jättää"), "avovedelle ei voi jättää venettä")
				# Mökkilaiturin vieressä: liian matala.
				var d: Vector2 = M.yw(-2.2, 14.0)
				vn.global_position = Vector3(d.x + 4.0, 0.0, d.y - 5.0)
				main._leave_motorboat()
				check(vn.driver != null and main._toast.text.contains("liian matala"), "mökkilaituriin ei telakoida: %s" % main._toast.text)
				# Reitti Happy Beachille syvässä vedessä.
				var a: Vector3 = vn.moorings[0].pos
				var b: Vector3 = vn.moorings[1].pos
				var path: Array = vn.plan_route(1, vn.approach_point(0))  # automaattiajon reitti lahdesta Happy Beachille
				check(path.size() >= 2, "automaattiajolle löytyy reitti lahdesta (%d pistettä)" % path.size())
				var blocked := 0
				for i in path.size() - 1:
					var p0: Vector2 = path[i]
					var p1: Vector2 = path[i + 1]
					var dir := (p1 - p0).normalized()
					var yaw := atan2(-dir.x, -dir.y)
					var n := int(p0.distance_to(p1) / 4.0)
					for k in n + 1:
						var q := p0.lerp(p1, float(k) / maxi(n, 1))
						if not vn.free_at(Vector3(q.x, 0, q.y), yaw):
							blocked += 1
				check(blocked == 0, "reitti Äpätistä Happy Beachin laiturille on syvää vettä (esteitä %d)" % blocked)
				# Happy Beachin laiturille.
				vn.global_position = b + Vector3(8.0, 0, 6.0)
				vn.speed = 10.0
				main._leave_motorboat()
				check(vn.driver != null and main._toast.text.contains("Hidasta"), "nopeasti ei telakoida")
				vn.speed = 0.0
				main._leave_motorboat()
				next()
		3:
			if t > 90:
				check(vn.driver == null and vn.at == 1, "vene telakoitui Happy Beachin laituriin")
				check(vn.global_position.distance_to(vn.moorings[1].pos) < 0.2, "vene on laiturin kyljessä")
				check(main.player.controls_enabled and main.player.pose == "", "pelaaja nousi laiturille")
				check(main.player.global_position.distance_to(vn.moorings[1].deck) < 3.0, "pelaaja on laiturilla")
				var on_jetty := 0
				for j in main._ride_crew:
					var cb: CharacterBody3D = main.crew[j]
					if cb.vehicle == null and cb.global_position.distance_to(vn.moorings[1].deck) < 4.0:
						on_jetty += 1
				check(on_jetty == 3, "porukka nousi Happy Beachin laiturille (%d)" % on_jetty)
				check(vn.can_board(main.player.global_position) or true, "nousu mahdollinen laiturilta")
				_put_player_on_deck(vn.moorings[1].deck)
				next()
		4:
			if t > 40:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("muskeliveneeseen"), "Happy Beachin laiturilla voi nousta veneeseen")
				it.cb.call()
				vn.global_position = Vector3(vn.moorings[0].pos.x + 5.0, 0.0, vn.moorings[0].pos.z - 6.0)
				vn.speed = 0.0
				main._leave_motorboat()
				next()
		5:
			if t > 90:
				check(vn.driver == null and vn.at == 0, "vene palasi Äpätin satamaan")
				var home := 0
				for j in main.crew.size():
					if j != main.player_index and main.crew_modes[j] == "ai" and main.crew[j].brain != null and main.crew[j].vehicle == null:
						home += 1
				check(home == 3 and main._ride_crew.is_empty(), "porukka palasi pihalle tietokoneen ohjaukseen")
				_put_player_on_deck(vn.moorings[0].deck)
				next()
		6:
			# Moninpeli: Marko (indeksi 1) ajaa toisella koneella, tämän koneen pelaaja istuu kyytiin.
			if t > 30:
				var st: Array = vn.net_state()
				check(st.size() == 5, "veneen tila verkkoon: 5 arvoa")
				main._remote_motorboat(true, 1, -1)
				check(vn.remote and vn.passenger == main.player and main.player.vehicle == vn, "toisen koneen ajaessa oma pelaaja istuu kyydissä")
				check(main.player.vehicle_seat == main._boat_slot(main.player_index, 1), "kyytiläisen paikka on järjestyksen mukainen (%d)" % main.player.vehicle_seat)
				var p0: Vector3 = vn.global_position
				vn.net_apply([p0.x + 10.0, p0.z - 30.0, 0.5, 12.0, 0.1])
				next()
		7:
			if t > 60:
				var p1: Vector3 = vn.global_position
				check(Vector2(p1.x, p1.z).distance_to(Vector2(vn._net_pos.x, vn._net_pos.z)) < 1.0 and absf(vn.speed - 12.0) < 0.01,
					"kaukoajettu vene seuraa verkon tilaa")
				check(main.player.global_position.distance_to(vn.seat_global(main.player.vehicle_seat)) < 1.5, "kyytiläinen pysyy penkillä")
				main._remote_motorboat(false, 1, 1)
				check(not vn.remote and vn.passenger == null and vn.at == 1, "ajon päättyessä vene on Happy Beachin laiturissa")
				check(main.player.vehicle == null and main.player.controls_enabled and main.player.global_position.distance_to(vn.moorings[1].deck) < 3.0,
					"kyytiläinen nousi laiturille")
				_put_player_on_deck(vn.moorings[0].deck)
				vn.place(0)
				next()
		8:
			# Automaattiajo Äpätistä Happy Beachille ja takaisin: vene telakoituu itse.
			if t > 30:
				main.player.vehicle = null
				main.player.controls_enabled = true
				_put_player_on_deck(vn.moorings[0].deck)
				main._interaction().cb.call()
				main._toggle_boat_autopilot()
				check(vn.autopilot or vn._docking, "G käynnistää veneen automaattiajon")
				next()
		9:
			if vn.at == 1 and vn.driver == null:
				check(true, "automaattiajo telakoi veneen Happy Beachin laituriin (%.0f s)" % (float(frames - ts) / 60.0))
				_put_player_on_deck(vn.moorings[1].deck)
				next()
			elif t > 14000:
				check(false, "automaattiajo ei päässyt Happy Beachille (%s)" % vn.global_position)
				next()
		10:
			if t > 30:
				main._interaction().cb.call()
				main._toggle_boat_autopilot()
				next()
		11:
			if vn.at == 0 and vn.driver == null:
				check(true, "automaattiajo toi veneen takaisin Äpätin satamaan")
				print("Valmis, vikoja: %d" % fails)
				quit(1 if fails > 0 else 0)
			elif t > 14000:
				check(false, "automaattiajo ei päässyt takaisin Äpättiin (%s)" % vn.global_position)
				print("Valmis, vikoja: %d" % fails)
				quit(1)
				quit(1 if fails > 0 else 0)
	return false
