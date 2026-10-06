extends SceneTree
## Amerikkalaisen jalkapallon heittely vedessä (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/heittelytesti.gd
## Pelaaja veteen alamökin edustalle (vettä 0,7-1 m) ja peli alkaa: tietokoneen hahmot kahlaavat paikoilleen.
## Pelaaja heittää ja ottaa kiinni omalle vuorolleen tulevat pallot (siirtyy renkaaseen), tietokone omansa.
## Lopuksi pelaaja jättää ottamatta: pallo veteen ja kelluu, heitot ennätykseksi. F lopettaa pelin, ja
## tietokoneen hahmot palaavat omiin puuhiinsa.

const AiS := preload("res://scripts/ai.gd")

var main: Node3D
var T: GDScript
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var ai_hits := 0
var my_hits := 0
var _prev_hits := 0


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	T = load("res://scripts/amerikanpallo.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = clock


func _process(delta: float) -> bool:
	clock += delta
	if main == null or main.get_script() == null:
		print("VIKA peli ei käynnisty")
		return true
	var t := clock - ts
	var p: CharacterBody3D = main.player
	var tn: Node3D = main.heittely
	match step:
		0:
			if clock > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 14, 0)
				tn.save_path = "user://amerikanpallo_testi.cfg"
				tn.record = 0
				var depths := []
				for k in 4:
					depths.append(snappedf(-(tn._spot_pos(k) as Vector3).y, 0.01))
				print("vettä pelipaikoilla %s m" % [depths])
				check(depths.all(func(d: float) -> bool: return d > 0.5 and d < 1.3), "pelipaikat kahlaussyvyydessä")
				p.global_position = tn._spot_pos(-1) + Vector3.UP * 0.1
				p.velocity = Vector3.ZERO
				next()
		1:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("amerikkalaisen jalkapallon"), "kehote: %s" % it.get("text", ""))
				it.cb.call()
				check(tn.active and tn.players.size() == 4, "peli alkoi, mukana %d" % tn.players.size())
				next()
		2:
			var ready: Array = tn.players.filter(func(pl: Dictionary) -> bool: return not tn._brains.has(pl.i) or tn._brains[pl.i].ready)
			if ready.size() == 4:
				print("kaikki paikoillaan %.1f s" % t)
				check(true, "tietokoneen hahmot kentälle")
				_to_spot()
				next()
			elif t > 90.0:
				for pl in tn.players:
					print("  %s %s valmis %s" % [main.Porukka.CREW[pl.i].name, (pl.body as Node3D).global_position, not tn._brains.has(pl.i) or tn._brains[pl.i].ready])
				check(false, "kaikki eivät päässeet kentälle")
				_to_spot()
				next()
		3:
			if t > 1.0:
				_face_ai()
				tn.act()
				check(tn.hits == 1 and tn._state == "fly", "syöttö")
				_prev_hits = 1
				next()
		4:
			# Ralli: pelaaja siirtyy omalle vuorolle tulevan pallon alle ja lyö sopivalla korkeudella.
			if tn.hits > _prev_hits:
				if tn._hitter_i == main.player_index:
					my_hits += 1
				else:
					ai_hits += 1
				_prev_hits = tn.hits
			if tn._state == "fly" and tn._target_i == main.player_index:
				var land: Vector3 = tn._landing()
				p.global_position = Vector3(land.x, p.global_position.y, land.z)
				p.velocity = Vector3.ZERO
				if tn._vel.y < 0.0 and tn._quality(p) > 0.0 and tn._pos.y - load("res://scripts/terrain.gd").h(p.global_position.x, p.global_position.z) < tn.hit_h + 0.2:
					_face_ai()
					tn._cool = 0.0
					if tn.hits >= 16:
						# Jätetään lyömättä: pallo maahan.
						step = 5
						ts = clock
					else:
						tn.act()
			if tn._state == "dead":
				print("ralli päättyi kesken %d lyöntiin" % tn.hits)
				if tn.hits < 16:
					# Tietokone huti: uusi syöttö.
					_prev_hits = 0
					step = 6
					ts = clock
			elif t > 120.0:
				print("tila %s lyöntejä %d kohde %d lyöjä %d pallo %s" % [tn._state, tn.hits, tn._target_i, tn._hitter_i, tn._pos])
				check(false, "ralli jumissa")
				return true
		5:
			if tn._state == "dead" or tn._state == "idle":
				print("lyöntejä %d (pelaaja %d, tietokone %d), ennätys %d" % [tn.hits, my_hits, ai_hits, tn.record])
				check(ai_hits >= 6, "tietokone lyö")
				check(my_hits >= 4, "pelaaja lyö")
				check(tn.record >= 16, "ennätys tallentui")
				var cfg := ConfigFile.new()
				check(cfg.load(tn.save_path) == OK and int(cfg.get_value("amerikanpallo", "ennatys", 0)) == tn.record, "ennätys tiedostossa")
				check(absf(tn._pos.y) < 0.15, "pallo kelluu vedessä (%.2f)" % tn._pos.y)
				next()
			elif t > 10.0:
				check(false, "pallo ei pudonnut")
				next()
		6:
			if tn._state == "idle":
				if step == 6 and tn.record < 16:
					_to_spot()
					_face_ai()
					tn.act()
					_prev_hits = 1
					step = 4
					ts = clock
					return false
			if t > 2.5 and tn.record >= 16:
				# F lopettaa pelin.
				var ev := InputEventKey.new()
				ev.keycode = KEY_F
				ev.pressed = true
				main._unhandled_input(ev)
				next()
		7:
			if t > 1.0:
				check(not tn.active and not tn.session, "F lopettaa pelin")
				var back := 0
				for j in main.crew.size():
					if main.crew_modes[j] == "ai" and main.crew[j].brain is AiS:
						back += 1
				check(back == 3, "tietokoneen hahmot palasivat omiin puuhiinsa")
				DirAccess.remove_absolute(ProjectSettings.globalize_path("user://amerikanpallo_testi.cfg"))
				print("vikoja %d" % fails)
				return true
	if clock > 400.0:
		check(false, "aikaraja (vaihe %d)" % step)
		return true
	return false


func _to_spot() -> void:
	var p: CharacterBody3D = main.player
	var me: Dictionary = main.heittely._me()
	p.global_position = main.heittely._spot_pos(me.spot) + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO


## Pelaaja katsomaan lähintä tietokoneen hahmoa.
func _face_ai() -> void:
	var p: CharacterBody3D = main.player
	var best: Node3D = null
	for pl in main.heittely.players:
		if main.heittely._brains.has(pl.i) and (best == null or (pl.body as Node3D).global_position.distance_to(p.global_position) < best.global_position.distance_to(p.global_position)):
			best = pl.body
	var d := best.global_position - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
