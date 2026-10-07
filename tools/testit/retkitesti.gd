extends SceneTree
## Tutkimusmatkan testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/retkitesti.gd
## Pelaaja nousee kumiveneeseen ja aloittaa tutkimusmatkan (Q): musiikki soi, tietokoneen hahmot lähtevät
## vanaveteen. Autopilotti soutaa reitin (tutkimusmatka.gd ROUTE) niemen ympäri kätkölle: vene ei jää
## matalikkoon, ja uimarit pysyvät jonossa veneen perässä. Perillä porukka nousee kätkölle, pelaaja kävelee
## kätkölle ja ottaa huikan (Q), ja matka päättyy. Lisäksi kumiveneen rakenne: soutajan jalat pohjan
## yläpuolella ja veneen sisällä, pohja vedenpinnan yläpuolella.

## Soutaa veneen reittipisteitä pitkin samoilla syötteillä kuin pelaaja.
class Pilot:
	extends RefCounted
	var boat: Node3D
	var path: Array
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump := false

	func reset() -> void:
		pass

	func think(_delta: float) -> void:
		var p := boat.global_position
		while path.size() > 1 and Vector2(p.x, p.z).distance_to(path[0]) < 6.0:
			path.pop_front()
		var d: Vector2 = path[0] - Vector2(p.x, p.z)
		if d.length() < 2.0:
			throttle = 0.0
			steer = 0.0
			return
		var diff := wrapf(atan2(-d.x, -d.y) - boat.rotation.y, -PI, PI)
		steer = clampf(diff * 2.0, -1.0, 1.0)
		throttle = 1.0 if absf(diff) < 0.6 else 0.3


## Kävelee suoraan kohteeseen.
class Walk:
	extends RefCounted
	var body: CharacterBody3D
	var goal := Vector3.ZERO
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump := false

	func reset() -> void:
		pass

	func think(_delta: float) -> void:
		var p := body.global_position
		var d := Vector2(goal.x - p.x, goal.z - p.z)
		throttle = 1.0 if d.length() > 0.5 else 0.0
		steer = clampf(wrapf(atan2(-d.x, -d.y) - body.rotation.y, -PI, PI) * 3.0, -1.0, 1.0)


var main: Node3D
var R: GDScript
var Kumivene: GDScript
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var max_lag := 0.0
var lag_n := 0
var lag_sum := 0.0
var stuck_t := 0.0
var last_bp := Vector3.ZERO
var pilot: Pilot


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	R = load("res://scripts/tutkimusmatka.gd")
	Kumivene = load("res://scripts/kumivene.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func followers() -> Array:
	return main.retki._brains.keys()


func _process(delta: float) -> bool:
	clock += delta
	ts += delta
	var retki: Node3D = main.retki
	var boat: Node3D = main.boat
	var pl: CharacterBody3D = main.player
	match step:
		0:
			if ts > 2.0:
				# Kätkö oikeissa koordinaateissa ja maalla, rantautumispaikassa vettä.
				var s: Vector2 = R.STASH
				var lat: float = main.START_LAT - s.y / main.M_PER_DEG_LAT
				var lon: float = main.START_LON + s.x / main.M_PER_DEG_LON
				check(absf(lat - 64.431850) < 1e-6 and absf(lon - 26.880575) < 1e-6, "kätkö %.6f N %.6f E" % [lat, lon])
				var T: GDScript = load("res://scripts/terrain.gd")
				check(T.h(s.x, s.y) > 0.5, "kätkö maalla (%.2f m)" % T.h(s.x, s.y))
				var l: Vector2 = R.LANDING
				check(T.h(l.x, l.y) < -0.1, "rantautumispaikassa vettä (%.2f m)" % T.h(l.x, l.y))
				pl.global_position = boat.global_position + Vector3(1.5, 0.5, 0)
				ts = 0.0
				step = 1
		1:
			if ts > 0.5:
				key(KEY_E)
				ts = 0.0
				step = 2
		2:
			if ts > 0.5:
				check(pl.boat == boat, "pelaaja veneessä")
				_check_boat_build()
				key(KEY_Q)
				ts = 0.0
				step = 3
		3:
			if ts > 1.0:
				check(retki.active and retki.state == "matka", "tutkimusmatka alkoi")
				check(retki.music.playing, "musiikki soi (%s)" % ("syntetisoitu" if retki.music.synth else "tiedosto"))
				check(followers().size() == 3, "kolme tietokoneen hahmoa mukana (%d)" % followers().size())
				pilot = Pilot.new()
				pilot.boat = boat
				pilot.path = R.ROUTE.duplicate()
				pl.brain = pilot
				last_bp = boat.global_position
				ts = 0.0
				step = 4
		4:
			# Soudetaan: vene liikkuu, uimarit pysyvät perässä.
			var bp := boat.global_position
			stuck_t = stuck_t + delta if bp.distance_to(last_bp) < 0.2 * delta else 0.0
			last_bp = bp
			if ts > 30.0:
				for j in followers():
					var b: CharacterBody3D = main.crew[j]
					var lag: float = Vector2(b.global_position.x - bp.x, b.global_position.z - bp.z).length()
					max_lag = maxf(max_lag, lag)
					lag_sum += lag
					lag_n += 1
			if stuck_t > 8.0:
				check(false, "vene jumissa kohdassa %s" % bp)
				return _finish()
			if retki.state == "perilla":
				check(true, "perillä %.0f s soutamisen jälkeen" % ts)
				check(retki.music.playing, "musiikki soi vielä perillä")
				check(lag_n > 0 and lag_sum / lag_n < 14.0, "uimarit vanavedessä: keskimäärin %.1f m veneestä" % (lag_sum / maxf(1, lag_n)))
				check(max_lag < 30.0, "kukaan ei jäänyt jälkeen (enintään %.1f m)" % max_lag)
				ts = 0.0
				step = 5
			elif ts > 400.0:
				check(false, "ei perillä 400 s:ssa (vene %s, kätkölle %.0f m)" % [bp, Vector2(bp.x, bp.z).distance_to(R.STASH)])
				return _finish()
		5:
			if ts > 25.0:
				var near := 0
				for j in followers():
					var b: CharacterBody3D = main.crew[j]
					if b.global_position.distance_to(retki.stash_pos) < 4.0:
						near += 1
				check(near >= 2, "porukka kätköllä (%d/3)" % near)
				pl.brain = null
				key(KEY_E)  # veneestä
				ts = 0.0
				step = 6
		6:
			if ts > 0.5:
				check(pl.boat == null, "noustiin veneestä")
				var w := Walk.new()
				w.body = pl
				w.goal = retki.stash_pos
				pl.brain = w
				ts = 0.0
				step = 7
		7:
			if retki.near_stash(pl.global_position) or ts > 30.0:
				pl.brain = null
				check(retki.near_stash(pl.global_position), "pelaaja kätköllä")
				var it: Dictionary = main._interaction()
				check(String(it.get("text", "")).contains("Viinakätkö"), "kätkön kehote: " + String(it.get("text", "")))
				var d0: int = pl.drinks
				key(KEY_Q)
				ts = 0.0
				step = 8
				set_meta("d0", d0)
		8:
			if ts > 0.5:
				check(pl.drinks == int(get_meta("d0")) + 1, "huikka viinaa kätköltä")
				ts = 0.0
				step = 9
		9:
			if not retki.active:
				check(true, "matka päättyi, musiikki häipyy")
				var back := 0
				var Ai: GDScript = load("res://scripts/ai.gd")
				for j in 4:
					if main.crew_modes[j] == "ai" and is_instance_of(main.crew[j].brain, Ai):
						back += 1
				check(back == 3, "tietokoneen hahmot omiin puuhiinsa (%d/3)" % back)
				return _finish()
			if ts > 60.0:
				check(false, "matka ei päättynyt")
				return _finish()
	return false


## Kumiveneen rakenne: soutajan jalat pohjan päällä veneen sisällä, pohja vedenpinnan yläpuolella.
func _check_boat_build() -> void:
	var boat: Node3D = main.boat
	var hull: Node3D = boat._hull
	var ch: Node3D = main.player.body()
	check(Kumivene.FLOOR_Y > 0.0, "pohja vedenpinnan yläpuolella (%.2f m)" % Kumivene.FLOOR_Y)
	await create_timer(0.3).timeout
	var inner: float = Kumivene.WIDTH * 0.5 - Kumivene.TUBE * 2.0
	for bn in ["foot_l", "foot_r", "ball_l", "ball_r", "calf_l", "calf_r"]:
		var w: Vector3 = ch.global_transform * ch.bone_position(bn)
		var l: Vector3 = hull.global_transform.affine_inverse() * w
		check(l.y > Kumivene.FLOOR_Y - 0.01 and absf(l.x) < inner and absf(l.z) < Kumivene.LENGTH * 0.5 - Kumivene.TUBE,
			"%s veneen sisällä pohjan päällä (%.2f, %.2f, %.2f)" % [bn, l.x, l.y, l.z])


func _finish() -> bool:
	print("VALMIS: %d virhettä (%.0f s)" % [fails, clock])
	quit(1 if fails > 0 else 0)
	return true
