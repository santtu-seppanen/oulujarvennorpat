extends RefCounted
## Trailerin leikkaus: kohtaukset järjestyksessä. Ensin pelin oma saapumiskohtaus (scripts/saapuminen.gd, torstai-ilta),
## sitten kohtaukset tästä listasta ja lopuksi oodi Oulujärvelle terassilla auringon laskiessa. Kaikki on mökin omia
## minipelejä ja puuhia; ne kuvataan pelin omilla toiminnoilla (tietokonehahmot pelaavat oikeasti), joten kuva seuraa
## pelin muutoksia.
##
## Kohtaus: {dur: kesto s, until: Callable -> bool (päättyy aiemmin), t: [kk, pv, h, min] alkuhetki, t2: loppuhetki
## (kello etenee), txt: otsikko, setup: Callable, tick: Callable(k, dt), done: Callable, cam: Callable(k) -> [paikka,
## katse], fov, keep: Callable -> Array (minipelin ruudut, jotka jäävät näkyviin)}.

const ODE_MAX := 28.0


## Soutajan korvike: pyytää vetoa eteenpäin ja ohjaa kohti suuntaa (on_foot.gd lukee brain.throttle ja steer).
class RowBrain:
	extends RefCounted
	var throttle := 1.0
	var steer := 0.0
	var fast := false
	var jump := false

	func think(_d: float) -> void:
		pass

	func reset() -> void:
		pass


## Kävelijä (tai konttaaja) kohti pistettä: samat syötteet kuin ai.gd:ssä.
class GoBrain:
	extends RefCounted
	var body: CharacterBody3D
	var target := Vector3.ZERO
	var go := false
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump := false

	func think(_d: float) -> void:
		throttle = 0.0
		steer = 0.0
		if not go:
			return
		var p := body.global_position
		var d := Vector2(target.x - p.x, target.z - p.z)
		if d.length() < 0.6:
			return
		var diff := wrapf(atan2(-d.x, -d.y) - body.rotation.y, -PI, PI)
		steer = clampf(diff * 2.5, -1.0, 1.0)
		throttle = 1.0 if absf(diff) < 0.7 else 0.25

	func reset() -> void:
		pass


static func scenes(main: Node3D) -> Array:
	var Mokki: GDScript = load("res://scripts/mokki.gd")
	var Terrain: GDScript = load("res://scripts/terrain.gd")
	var Tennis: GDScript = load("res://scripts/rantatennis.gd")
	var Retki: GDScript = load("res://scripts/tutkimusmatka.gd")
	var y := func(u: float, v: float, h: float) -> Vector3:
		var w: Vector2 = Mokki.yw(u, v)
		return Vector3(w.x, h, w.y)
	var D: float = Mokki.DY
	var st := {"frame": 0, "game": null, "row": null, "ode": false, "brains": [], "dr": {}}
	# Hahmot takaisin normaaliin: Santtu pelaajana, muut tietokoneella.
	var normal := func() -> void:
		main.choose_character(0)
		for j in range(1, 4):
			main.set_crew_mode(j, "ai")
	# Hahmo j paikalleen (kevyesti maan yläpuolelle) ja katse suuntaan yaw.
	var put := func(j: int, p: Vector3, yaw: float) -> void:
		var b: CharacterBody3D = main.crew[j]
		b.set_hidden_inside(false)
		b.global_position = p + Vector3(0, 0.1, 0)
		b.rotation.y = yaw
		b.velocity = Vector3.ZERO
	var ground := func(p: Vector3) -> Vector3:
		return Vector3(p.x, maxf(Terrain.h(p.x, p.z), 0.0), p.z)
	var s: Array = []

	# --- Spartan pinkiponki ------------------------------------------------------------------------------------
	var court: Vector2 = Tennis.fw(0.0, 0.0)
	var cg: float = Terrain.h(court.x, court.y)
	s.append({"dur": 6.0, "t": [7, 10, 14, 0], "txt": "SPARTAN PINKIPONKI",
		"setup": func() -> void:
			var tn: Node3D = main.tennis
			tn.save_path = "user://trailer_tennis.cfg"
			main.player.global_position = Vector3(court.x, cg + 0.1, court.y)
			tn.start()
			for pl in tn.players:
				(pl.body as Node3D).global_position = tn._spot_pos(pl.spot) + Vector3.UP * 0.1
				if tn._brains.has(pl.i):
					tn._brains[pl.i].path = []
			st.frame = 0,
		"tick": func(_k: float, _dt: float) -> void:
			st.frame += 1
			if st.frame % 18 == 0:
				main.tennis.act(),
		"cam": func(k: float) -> Array:
			var w: Vector2 = Tennis.fw(lerpf(-3.0, 3.0, k), -Tennis.FIELD_H.y - 3.0)
			return [Vector3(w.x, cg + lerpf(3.2, 2.2, k), w.y), Vector3(court.x, cg + 1.0, court.y)],
		"done": func() -> void: main.tennis.stop()})

	# --- Amerikanpallo vedessä -------------------------------------------------------------------------------
	s.append({"dur": 8.0, "t": [7, 10, 16, 30], "txt": "AMERIKANPALLO", "fov": 78.0,
		"setup": func() -> void:
			var tn: Node3D = main.heittely
			tn.save_path = "user://trailer_pallo.cfg"
			main.player.global_position = tn._spot_pos(-1) + Vector3.UP * 0.1
			tn.start()
			# Kaikki neljä heti omille paikoilleen vyötäröön asti vedessä.
			for pl in tn.players:
				(pl.body as Node3D).global_position = tn._spot_pos(pl.spot) + Vector3.UP * 0.1
				if tn._brains.has(pl.i):
					tn._brains[pl.i].path = []
			st.frame = 0,
		"tick": func(_k: float, _dt: float) -> void:
			st.frame += 1
			if st.frame % 18 == 0:
				main.heittely.act(),
		"cam": func(k: float) -> Array:
			var c: Vector3 = main.heittely._spot_pos(-1)
			var side := Vector3(Mokki.EAST.x, 0.0, Mokki.EAST.y)
			var shore := -Vector3(Mokki.LAKE.x, 0.0, Mokki.LAKE.y)
			return [c - shore * 6.0 + side * lerpf(-1.5, 1.5, k) + Vector3(0, 1.9, 0), c + Vector3(0, 0.7, 0)],
		"done": func() -> void: main.heittely.stop()})

	# --- Pyttipannun paisto (Markon minipeli) ---------------------------------------------------------------
	s.append({"dur": 8.0, "t": [7, 10, 12, 0], "txt": "PYTTIPANNU",
		"keep": func() -> Array: return [main.kokkaus._ui],
		"setup": func() -> void:
			main.choose_character(1)
			main.start_activity("kokkaus")
			st.frame = 0,
		"tick": func(_k: float, _dt: float) -> void:
			st.frame += 1
			# Perunat pannulle, käännös kullanruskeina ja annos lautaselle.
			if st.frame == 12:
				st.camt = (main.player._cam as Camera3D).global_transform  # kamera lukitaan hellan yläpuolelle
			if st.frame == 15 or st.frame == 105 or st.frame == 175:
				main.kokkaus.act(),
		"cam": func(_k: float) -> Array:
			var c: Transform3D = st.camt if st.has("camt") else (main.player._cam as Camera3D).global_transform
			return [c.origin, c.origin - c.basis.z],
		"done": func() -> void:
			main.end_activity()
			normal.call()})

	# --- Virtsaaminen rinteeseen (Markon erikoiskyky) --------------------------------------------------------
	s.append({"dur": 6.0, "t": [7, 11, 11, 0], "txt": "RINTEESEEN",
		"setup": func() -> void:
			main.choose_character(1)
			var w: Vector2 = Mokki.yw(Mokki.PEE_SPOT.x, Mokki.PEE_SPOT.y)
			main.player.global_position = Vector3(w.x, Terrain.h(w.x, w.y) + 2.0, w.y)
			main.player.rotation.y = atan2(-Mokki.EAST.x, -Mokki.EAST.y)
			main.player.velocity = Vector3.ZERO
			st.frame = 0,
		"tick": func(_k: float, _dt: float) -> void:
			st.frame += 1
			if st.frame == 20:
				main.pissa.start(),
		"cam": func(k: float) -> Array:
			var p: Vector3 = main.player.global_position
			var f: Vector3 = -main.player.global_transform.basis.z
			var side: Vector3 = main.player.global_transform.basis.x
			return [p - f * 0.5 + side * lerpf(3.6, 2.6, k) + Vector3(0, 1.5, 0), p + f * 2.5 + Vector3(0, 0.7, 0)],
		"done": func() -> void:
			main.pissa.stop()
			normal.call()})

	# --- Ristiseiska pöydässä ---------------------------------------------------------------------------------
	s.append({"dur": 6.0, "t": [7, 10, 21, 30], "txt": "RISTISEISKA",
		"keep": func() -> Array: return [main.kortit._ui],
		"setup": func() -> void:
			main.set_crew_mode(0, "player")
			for j in 4:
				var w: Vector2 = Mokki.yw(-4.9 + j * 0.3, 1.5)
				put.call(j, Vector3(w.x, D, w.y), 0.0)
			main.start_activity("kortit")
			st.frame = 0,
		"tick": func(_k: float, _dt: float) -> void:
			st.frame += 1
			if st.frame == 40:
				main.kortit.deal()
			if st.frame == 130:
				main.kortit.act(),
		"cam": func(_k: float) -> Array:
			var c: Camera3D = main.player._cam
			return [c.global_position, c.global_position - c.global_basis.z],
		"done": func() -> void:
			main.end_activity()
			normal.call()})

	# --- Päikkärit ylämökissä --------------------------------------------------------------------------------
	s.append({"dur": 4.0, "t": [7, 11, 16, 0], "txt": "PÄIKKÄRIT",
		"setup": func() -> void:
			main._nap_scene.play(),
		"cam": func(_k: float) -> Array:
			var c: Camera3D = main._nap_scene.cam
			return [c.global_position, c.global_position - c.global_basis.z],
		"done": func() -> void: main._nap_scene.stop()})

	# --- Tutkimusmatka: soutu lahden poikki -----------------------------------------------------------------
	s.append({"dur": 5.0, "t": [7, 11, 12, 0], "txt": "TUTKIMUSMATKA",
		"setup": func() -> void:
			var boat: CharacterBody3D = main.boat
			var w: Vector2 = Mokki.yw(-4.6, 9.0)
			boat.global_position = Vector3(w.x, 0.0, w.y)
			boat.rotation.y = atan2(-Mokki.LAKE.x, -Mokki.LAKE.y) + 0.25
			boat.speed = 0.0
			var rower: CharacterBody3D = main.crew[1]
			rower.set_hidden_inside(false)
			rower.global_position = boat.global_position + Vector3.UP * 0.4
			if rower.brain != null:
				rower.brain.reset()
			var rb := RowBrain.new()
			rower.brain = rb
			rower.enter_boat(boat)
			st.row = rb,
		"tick": func(k: float, _dt: float) -> void:
			(st.row as RowBrain).steer = 0.25 if k < 0.5 else -0.1,
		"cam": func(k: float) -> Array:
			var b: Vector3 = main.boat.global_position
			var back: Vector3 = main.boat.global_transform.basis.z
			var side: Vector3 = main.boat.global_transform.basis.x
			return [b - back * lerpf(6.0, 7.5, k) + side * lerpf(3.0, -2.5, k) + Vector3(0, 1.4, 0), b + Vector3(0, 0.9, 0)],
		"done": func() -> void:
			var rower: CharacterBody3D = main.crew[1]
			rower.leave_boat()
			rower.brain = null
			main.set_crew_mode(1, "")
			main.set_crew_mode(1, "ai")})

	# --- Viinakätkön etsintä metsän takaisella hiekkarannalla ------------------------------------------------
	var landing: Vector2 = Retki.LANDING
	s.append({"dur": 7.0, "t": [7, 11, 12, 40], "txt": "VIINAKÄTKÖN ETSINTÄ",
		"setup": func() -> void:
			var stash: Vector3 = main.retki.stash_pos
			var a := Vector3(landing.x, 0.0, landing.y)
			var dir := Vector3(stash.x - a.x, 0.0, stash.z - a.z).normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			for j in 4:
				var b: CharacterBody3D = main.crew[j]
				if b.brain != null:
					b.brain.reset()
				var p: Vector3 = ground.call(a + side * (j - 1.5) * 1.3 - dir * 1.0)
				put.call(j, p, atan2(-dir.x, -dir.z))
				var gb := GoBrain.new()
				gb.body = b
				gb.target = stash
				gb.go = true
				b.brain = gb
				b.controls_enabled = true,
		"cam": func(k: float) -> Array:
			var stash: Vector3 = main.retki.stash_pos
			var c := Vector3.ZERO
			for b in main.crew:
				c += (b as Node3D).global_position
			c /= 4.0
			var dir := Vector3(stash.x - c.x, 0.0, stash.z - c.z).normalized()
			var side := Vector3(-dir.z, 0.0, dir.x)
			return [c - dir * lerpf(7.0, 5.0, k) + side * lerpf(2.5, -1.5, k) + Vector3(0, 1.7, 0), c + dir * 3.0 + Vector3(0, 0.8, 0)],
		"done": func() -> void:
			for j in 4:
				main.crew[j].brain = null
				main.set_crew_mode(j, "")
			normal.call()})

	# --- Nuotiolla istuskelu ---------------------------------------------------------------------------------
	s.append({"dur": 6.0, "t": [7, 11, 22, 20], "txt": "NUOTIOLLA",
		"setup": func() -> void:
			normal.call()
			main.nuotio.ignite(4, 1.0, false)
			var fp: Vector3 = main.world.mokki.fire_pos
			for j in 4:
				put.call(j, ground.call(fp + Vector3(-2.0 + j * 1.0, 0, 2.5)), 0.0)
			main.start_activity("makkara"),
		"cam": func(k: float) -> Array:
			var fp: Vector3 = main.world.mokki.fire_pos
			var land := Vector3(Mokki.LAKE.x, 0.0, Mokki.LAKE.y) * -1.0
			var side := Vector3(Mokki.EAST.x, 0.0, Mokki.EAST.y)
			return [fp + land * lerpf(5.5, 4.0, k) + side * lerpf(-3.0, 1.5, k) + Vector3(0, 1.5, 0), fp + Vector3(0, 0.8, 0)],
		"done": func() -> void:
			main.end_activity()
			normal.call()})

	# --- Vihainen työpuhelu saunassa -------------------------------------------------------------------------
	s.append({"dur": 7.0, "t": [7, 12, 19, 30], "txt": "TYÖPUHELU",
		"keep": func() -> Array: return [main.tyopuhelu._ui],
		"setup": func() -> void:
			main.choose_character(2)
			main.sauna.temp = 85.0
			main.sauna.fire = 600.0
			var m: Node3D = main.world.mokki
			var seat: Array = m.sauna_seats[0]
			main.player.global_position = (seat[0] as Vector3) + Vector3(0, 0.2, 0)
			main.start_activity("sauna")
			st.frame = 0,
		"tick": func(_k: float, _dt: float) -> void:
			st.frame += 1
			if st.frame == 40:
				var t: Node = main.tyopuhelu
				t.called_day = -1
				t.trigger()
				t._title.text = "TYÖPUHELU · ESIMIES"
				t._text.text = "\"JAAKKO! Missä ne raportit on?! Vastaa nyt heti!\"\n\nVastaatko saunassa?",
		"cam": func(_k: float) -> Array:
			var c: Camera3D = main.player._cam
			return [c.global_position, c.global_position - c.global_basis.z],
		"done": func() -> void:
			main.tyopuhelu.answer(false)
			main.end_activity()
			normal.call()})

	# --- Oodi Oulujärvelle terassilla, aurinko laskee ------------------------------------------------------
	s.append({"dur": ODE_MAX, "t": [7, 12, 23, 4], "t2": [7, 12, 23, 34], "txt": "",
		"fov": 85.0,
		"setup": func() -> void:
			main.set_crew_mode(0, "ai")
			for j in 4:
				var sp: Vector3 = main.oodi.spot(j)  # laulupaikka kaiteella; aloitus pari metriä taempaa
				var back := Vector3(Mokki.LAKE.x, 0.0, Mokki.LAKE.y) * -1.2
				put.call(j, sp, 0.0)
				if main.crew[j].brain == null:
					main.set_crew_mode(j, "ai")
			main.oodi._gather(false)
			st.ode = false,
		"until": func() -> bool:
			if main.oodi.state == "laulu":
				st.ode = true
			return st.ode and main.oodi.state == "",
		"tick": func(_k: float, _dt: float) -> void:
			# Neljä riviin kaiteen ääreen kasvot järvelle heti alusta (kamera kuvaa heidät selän takaa).
			for j in 4:
				var b: CharacterBody3D = main.crew[j]
				var sp: Vector3 = main.oodi.spot(j)
				b.global_position = Vector3(sp.x, sp.y, sp.z)
				b.velocity = Vector3.ZERO
				b.rotation.y = atan2(-Mokki.LAKE.x, -Mokki.LAKE.y),
		"cam": func(k: float) -> Array:
			# Selän takaa keskeltä: neljä laulajaa rivissä, aurinko laskee horisonttiin heidän yli.
			return [y.call(-0.6, lerpf(1.3, 1.6, k), D + lerpf(1.5, 1.6, k)), y.call(-0.5, 9.0, D + lerpf(1.7, 2.0, k))]})
	return s
