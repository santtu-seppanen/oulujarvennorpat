extends SceneTree
## Rantatenniksen moninpelitesti (headless, kaksi konetta): käynnistä palvelin (cd server && npx wrangler dev)
##   godot --headless --fixed-fps 60 --path . -s tools/testit/tennismoninpeli.gd -- --rooli=host --huone=TNIS --palvelin=ws://localhost:8787
##   godot --headless --fixed-fps 60 --path . -s tools/testit/tennismoninpeli.gd -- --rooli=vieras --huone=TNIS --palvelin=ws://localhost:8787
## Host on Santtu, vieras Marko. Molemmat menevät kentälle, ja hostin tietokone tuo Jaakon ja Jukan mukaan.
## Vieras syöttää. Kumpikin lyö omalle vuorolleen tulevat pallot, hostin tietokone lyö Jaakon ja Jukan pallot.
## Tarkistetaan, että pallo kulkee koneelta toiselle: kummallakin sama ralli, lyöntimäärä kasvaa ja toisen
## koneen lyönnit näkyvät. Lopuksi vieras jättää lyömättä: molemmilla ralli päättyy samaan lyöntimäärään ja
## ennätykseen. Kentältä poistuttua peli loppuu.

const AiS := preload("res://scripts/ai.gd")
const Terrain := preload("res://scripts/terrain.gd")
const GOAL := 14

var main: Node3D
var T: GDScript  # ladataan vasta, kun Sfx ym. ovat olemassa
var role := "host"
var code := "TNIS"
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var seen_by := {}  # lyöjä -> lyöntejä
var max_hits := 0
var rally := 0
var over_hits := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rooli="):
			role = a.trim_prefix("--rooli=")
		elif a.begins_with("--huone="):
			code = a.trim_prefix("--huone=")
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	T = load("res://scripts/rantatennis.gd")


func check(ok: bool, what: String) -> void:
	print("[%s] %s%s" % [role, "OK   " if ok else "VIKA ", what])
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = clock


func _process(delta: float) -> bool:
	clock += delta
	var t := clock - ts
	var mp: Node = main.mp
	var tn: Node3D = main.tennis
	var p: CharacterBody3D = main.player
	var other := 1 if role == "host" else 0
	match step:
		0:
			if clock > (1.0 if role == "host" else 4.0):
				if role == "host":
					mp.preset = 0
					mp.net.join(code)
				else:
					mp.join(code.to_lower())
				next()
		1:
			if mp.online() and (role == "host" or not mp.owners.is_empty()):
				mp.claim(0 if role == "host" else 1)
				next()
			elif t > 20.0:
				check(false, "yhteys palvelimeen")
				return _end()
		2:
			if mp.mine >= 0 and (role != "host" or not mp.net.peers.is_empty()):
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 7, 14, 0)
				tn.save_path = "user://rantatennis_mp_%s.cfg" % role
				tn.record = 0
				var c: Vector2 = T.fw(0.0 if role == "host" else 2.0, 0.0)
				p = main.player
				p.global_position = Vector3(c.x, Terrain.h(c.x, c.y) + 0.1, c.y)
				p.velocity = Vector3.ZERO
				next()
		3:
			if t > (1.0 if role == "host" else 3.0):
				main._interaction().cb.call()
				next()
		4:
			# Kaikki neljä mukana ja paikoillaan kummallakin koneella.
			if tn.active:
				_to_spot()
			var near: Array = tn.players.filter(func(pl: Dictionary) -> bool:
				return (pl.body as Node3D).global_position.distance_to(tn._spot_pos(pl.spot)) < 1.6)
			if tn.active and tn.spots.size() == 4 and near.size() == 4:
				check(tn.spots.has(0) and tn.spots.has(1), "molemmat pelaajat mukana, paikat %s" % [tn.spots])
				check(main.crew_modes[other] == "remote" and tn.players.size() == 4, "toisen pelaajan maila näkyy")
				next()
			elif t > 90.0:
				check(false, "peli ei alkanut kummallakin: aktiivinen %s paikat %s lähellä %d" % [tn.active, tn.spots, near.size()])
				return _end()
		5:
			# Vieras syöttää hostille.
			if t > 3.0:
				if role == "vieras":
					_face(main.crew[0])
					tn.act()
					check(tn._state == "fly" and tn._target_i == 0, "vieras syötti hostille")
				next()
		6:
			if tn._state == "fly" or tn._state == "wait":
				if rally == 0:
					rally = tn._rally
				if tn.hits > max_hits:
					max_hits = tn.hits
					seen_by[tn._hitter_i] = seen_by.get(tn._hitter_i, 0) + 1
				if tn._target_i == main.player_index and tn._state == "fly":
					var land: Vector3 = tn._landing()
					p.global_position = Vector3(land.x, p.global_position.y, land.z)
					p.velocity = Vector3.ZERO
					var dh: float = tn._pos.y - Terrain.h(p.global_position.x, p.global_position.z)
					if tn._vel.y < 0.0 and tn._quality(p) > 0.0 and dh < 1.3:
						if role == "vieras" and tn.hits >= GOAL:
							pass  # jätetään lyömättä: pallo maahan
						else:
							_face(main.crew[[other, 2, other, 3][tn.hits % 4]])
							tn._cool = 0.0
							tn.act()
			if tn._state == "dead" and max_hits > 0:
				over_hits = tn.hits
				print("[%s] ralli %d päättyi %d lyöntiin, lyöjät %s, ennätys %d" % [role, tn._rally, over_hits, seen_by, tn.record])
				next()
			elif t > 120.0:
				check(false, "ralli jumissa: tila %s lyöntejä %d kohde %d" % [tn._state, tn.hits, tn._target_i])
				return _end()
		7:
			check(tn._rally == rally, "koko ralli samalla tunnuksella")
			check(seen_by.get(other, 0) >= 2, "toisen pelaajan lyönnit tulivat perille (%d)" % seen_by.get(other, 0))
			check(seen_by.get(2, 0) + seen_by.get(3, 0) >= 2, "tietokoneen lyönnit näkyvät (%d)" % (seen_by.get(2, 0) + seen_by.get(3, 0)))
			check(over_hits >= GOAL, "ralli kesti %d lyöntiä" % over_hits)
			check(tn.record == over_hits, "ennätys %d" % tn.record)
			print("[%s] TULOS %d" % [role, over_hits])
			next()
		8:
			# Vieras lähtee ensin kentältä, host perässä: sitten peli loppuu.
			if t > (2.0 if role == "vieras" else 5.0):
				var w: Vector2 = T.fw(0.0, -T.FIELD_H.y - 8.0)
				p.global_position = Vector3(w.x, Terrain.h(w.x, w.y) + 0.2, w.y)
				next()
		9:
			if t > 3.0:
				check(not tn.active, "oma pelaaja pois pelistä")
				if role == "vieras":
					check(tn.session and not tn.spots.has(1), "host jatkaa ilman vierasta")
				else:
					check(not tn.session, "peli loppui")
					var back := 0
					for j in [2, 3]:
						if main.crew[j].brain is AiS:
							back += 1
					check(back == 2, "tietokoneen hahmot palasivat omiin puuhiinsa")
				next()
		10:
			if t > 3.0:
				if role == "vieras":
					check(not tn.session, "hostin lähtö lopetti pelin vieraallakin")
				DirAccess.remove_absolute(ProjectSettings.globalize_path(tn.save_path))
				return _end()
	if clock > 300.0:
		check(false, "aikaraja (vaihe %d)" % step)
		return _end()
	return false


func _to_spot() -> void:
	var p: CharacterBody3D = main.player
	p.global_position = main.tennis._spot_pos(main.tennis._me().spot) + Vector3.UP * 0.1
	p.velocity = Vector3.ZERO


func _face(b: Node3D) -> void:
	var p: CharacterBody3D = main.player
	var d := b.global_position - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)


func _end() -> bool:
	print("[%s] vikoja %d" % [role, fails])
	main.mp.net.leave()
	return true
