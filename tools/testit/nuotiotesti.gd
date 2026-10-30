extends SceneTree
## Nuotion ja lautapelin testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/nuotiotesti.gd
## - Makkaranpaisto: hiilloksella kypsyy tasaisesti, liekissä noettuu ja palaa, raaka/palanut/hyvä tuloksen mukaan.
## - Muistelu: neljän tarinan ilta, valinnat muuttavat tunnelmaa, päivän vaikutus mainepisteisiin ja lopputuloksen rivit.
## - Lautapeli (ysäritrivia): vastauksen tunnistus, oikea vastaus antaa kiilan ja pitää vuoron, väärä siirtää vuoron.

var main: Node3D
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var _afrikka_started := false


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func n_lit() -> bool:
	return main.nuotio.lit


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
	match step:
		0:
			if clock > 2.0:
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 9, 20, 0)
				_tekstit()
				var n: Node = main.nuotio
				p.global_position = n.pos + Vector3(-2.0, 0.1, 0.0)
				p.velocity = Vector3.ZERO
				next()
		1:
			if t > 0.5:
				var unlit: Dictionary = main._interaction()
				check(not n_lit() and str(unlit.get("text", "")).contains("sammunut") and not unlit.has("cb"), "sammunutta nuotiota ei voi käyttää: %s" % unlit.get("text", ""))
				main.sauna.carried[main.player_index] = 4
				unlit = main._interaction()
				check(str(unlit.get("text", "")).contains("sytytä nuotio"), "halot sylissä: nuotion voi sytyttää")
				main.nuotio.ignite(4, 1.0, false)
				check(n_lit(), "sytytysminipelin jälkeen nuotio palaa")
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("makkaraa"), "kehote nuotiolla: %s" % it.get("text", ""))
				it.cb.call()
				check(main.activity == "makkara", "makkaranpaisto alkoi")
				var mk: Node = main.makkara
				mk.act()
				check(mk._state == "paisto", "makkara tikun päässä")
				next()
		2:
			var mk: Node = main.makkara
			# Hiillos kypsyttää tasaisesti: seisotaan paikassa, jossa ei ole liekkiä.
			mk._x = 0.0
			mk._t = 0.0
			var flame_free := _free_x(mk)
			mk._x = flame_free
			var before: float = mk._p
			for i in 120:
				mk._cook(0.05)
			check(mk._p > before + 0.2 and mk._soot == 0.0, "hiilloksella kypsyy ilman nokea (%.2f, noki %.2f)" % [mk._p, mk._soot])
			check(mk.grade() in ["raaka", "melkein", "hyva"], "kypsyys ei vielä palanut: %s" % mk.grade())
			mk._p = 0.7
			mk._soot = 0.0
			check(mk.grade() == "hyva", "kypsä ja nokeamaton on hyvä")
			mk._p = 0.3
			check(mk.grade() == "raaka", "liian vähän on raaka")
			# Liekissä noettuu ja palaa.
			mk._p = 0.2
			mk._soot = 0.0
			mk._t = 0.0
			var fx: float = mk.flames()[0]
			mk._x = fx
			check(mk.in_flame(), "liekin kohdalla makkara on liekissä")
			for i in 40:
				mk._cook(0.05)
				mk._t = 0.0
				mk._x = fx
			check(mk._soot >= mk.SOOT_MAX and mk.grade() == "palanut", "liekissä makkara palaa (noki %.2f)" % mk._soot)
			# Hyvä makkara täyttää kunnon ja kuittaa tehtävän.
			mk._p = 0.7
			mk._soot = 0.0
			p.stamina = 20.0
			mk.act()
			check(p.stamina == 100.0, "hyvä makkara palauttaa kunnon")
			main.end_activity()
			check(main.activity == "", "nuotiolta nousu")
			next()
		3:
			if t > 0.3:
				p.global_position = main.nuotio.pos + Vector3(-2.0, 0.1, 0.0)
				p.velocity = Vector3.ZERO
				next()
		4:
			if t > 0.4:
				main._unhandled_input(_key_q())
				check(main.activity == "", "tarinoita ei kerrota ennen auringonlaskua")
				main.sun.t_utc = main.sun._local_to_utc(2026, 7, 9, 22, 30)
				main.sun._update(true)
				check(main.sunset_now(), "klo 22.30 on auringonlaskun aika (korkeus %.1f)" % main.sun.altitude)
				main._unhandled_input(_key_q())
				check(main.activity == "muistelu", "Q aloittaa muistelun")
				var ms: Node = main.muistelu
				var maine0: int = main.maine
				check(ms._phase == "choose", "ensimmäinen tarina alkaa heti ilman E:tä")
				var told_first := 0
				for k in 4:
					check(ms._phase == "choose", "tarina %d valittavana" % (k + 1))
					ms.choose(0)
					told_first += 1
					check(ms._phase == "reply", "vastaus tarinaan %d" % (k + 1))
					if k == 0:
						ms._reply_t = 0.0
						ms._process(0.1)  # vastauksen jälkeen seuraava tarina alkaa itsestään ilman E:tä
					else:
						ms.act()
				check(ms._phase == "done", "illan päätös 4 tarinan jälkeen")
				var d: int = main.tarina.day
				check(int(ms.told[d]) == 4, "kerrottuja tarinoita %d" % ms.told[d])
				ms.evening[d] = 6
				ms.day_ended(d)
				check(main.maine == mini(100, maine0 + 4) and ms.mood_morning == 2, "hyvä ilta nostaa mainetta (%d)" % main.maine)
				check(not ms.ending_lines().is_empty() and ms.win_line() != "", "lopputuloksessa nuotiorivit")
				ms.evening[d] = -4
				ms.day_ended(d)
				check(ms.mood_morning == -1, "kiusallinen ilta jättää nuokkuvan aamun")
				main.end_activity()
				next()
		5:
			if t > 0.3:
				var m: Node3D = main.world.mokki
				var seat: Array = m.table_seats[main.player_index]
				p.global_position = seat[1] + (seat[0] - seat[1]).normalized() * 0.5
				p.velocity = Vector3.ZERO
				next()
		6:
			if t > 0.4:
				var lp: Node = main.lautapeli
				check(lp.matches("Ranskan", ["ranska"]) and lp.matches("hakkinen", ["häkkinen"]) and not lp.matches("Saksa", ["ranska"]), "vastauksen tunnistus")
				check(lp.matches("2000", ["2000"]) and not lp.matches("200", ["2000"]), "numerovastaus täsmää")
				main.start_activity("lautapeli")
				check(main.activity == "lautapeli" and lp.phase == "valinta", "lautapelit alkoivat pelin valinnalla")
				lp.choose(0)
				lp.turn = main.player_index
				lp.act()
				check(lp.phase == "ask" and lp.turn == main.player_index, "pelaajan kysymys: %s" % lp.q[1])
				var w0: int = lp.wedges[lp.turn].size()
				lp.submit((lp.q[2] as Array)[0])
				check(lp.wedges[main.player_index].size() == w0 + 1 and lp.right_count == 1, "oikea vastaus antaa kiilan")
				lp.step(lp.RESULT_T + 0.1)
				check(lp.phase == "ask" and lp.turn == main.player_index, "oikea vastaus pitää vuoron")
				lp.submit("ei tiedossa")
				check(lp.turn != main.player_index and lp.phase == "result", "väärä vastaus siirtää vuoron")
				# Pelaaja voittaa neljällä kiilalla.
				lp.step(lp.RESULT_T + 0.1)
				lp.turn = main.player_index
				lp.wedges[main.player_index] = [0, 1, 2]
				lp.right_count = 2
				lp._begin_turn()
				lp.submit((lp.q[2] as Array)[0])
				check(lp.phase == "over" and lp.winner == main.player_index, "neljäs kiila voittaa pelin")
				check(int(lp.wins.get(main.player_index, 0)) == 1 and not lp.ending_lines().is_empty(), "voitto kirjataan lopputulokseen")
				main.end_activity()
				next()
		7:
			if not _afrikka_started:
				_afrikka_started = true
				_afrikka()
		8:
			# Moninpeli: toisen koneen nuotion ja kiukaan tila tulee viestillä.
			main.nuotio.douse()
			main.mp._on_message({"t": "nuotio", "f": 300.0, "from": 2})
			check(main.nuotio.lit and absf(main.nuotio.fire - 300.0) < 1.0, "nuotion tila synkkautuu toiselta koneelta")
			main.mp._on_message({"t": "nuotio", "f": 0.0, "from": 2})
			check(not main.nuotio.lit, "nuotion sammuminen synkkautuu")
			main.mp._on_message({"t": "halko", "f": 200.0, "T": 30.0, "from": 2})
			check(absf(main.sauna.fire - 200.0) < 1.0 and absf(main.sauna.temp - 30.0) < 1.0, "kiukaan tila synkkautuu toiselta koneelta")
			print("Valmis, vikoja: %d" % fails)
			quit(1 if fails > 0 else 0)
	return false


## Afrikan tähti (alkuperäisten sääntöjen mukaan): verkko, kiekot, ostaminen, rahat, meritien maksu ja koko peli.
func _afrikka() -> void:
	var at: Node = main.afrikka
	var A: GDScript = load("res://scripts/afrikantahti.gd")
	var h: int = main.player_index
	# Verkko: jokainen kaupunki saavutettavissa Tangerista.
	var seen := {0: true}
	var q: Array = [0]
	while not q.is_empty():
		var n: int = q.pop_front()
		for e: Dictionary in at.adj[n]:
			if not seen.has(e.to):
				seen[e.to] = true
				q.append(e.to)
	var all_linked := true
	for c in A.CITIES.size():
		if not seen.has(c):
			all_linked = false
	check(all_linked, "kaikki kaupungit saavutettavissa Tangerista maa- ja meriteitse")
	main.start_activity("lautapeli")
	main.lautapeli.choose(1)
	await create_timer(0.3).timeout
	check(main.activity == "afrikka" and at.phase == "roll", "Q-valinta 2 aloittaa Afrikan tähden")
	var counts := {}
	for tk in at.tokens:
		counts[tk] = int(counts.get(tk, 0)) + 1
	check(counts.get("tahti", 0) == 1 and counts.get("rubiini", 0) == 2 and counts.get("smaragdi", 0) == 3 and counts.get("topaasi", 0) == 4
		and counts.get("rosvo", 0) == 3 and counts.get("hevosenkenka", 0) == 5 and counts.get("tyhja", 0) == 8, "kiekot: tähti, 2 rubiinia, 3 smaragdia, 4 topaasia, 3 rosvoa, 5 hevosenkenkää, 8 tyhjää")
	check(at.tokens[0] == "" and at.tokens[1] == "" and at.money[h] == 300 and at.pos[h] == 0, "Tangerissa ja Kairossa ei kiekkoa, rahaa 300 £")
	# Vuoron valikko ja noppa.
	at.turn = h
	at.phase = "roll"
	at._build_opts()
	check(at.opts.any(func(o: Dictionary) -> bool: return o.id == "roll"), "valikossa on nopan heitto")
	at.confirm(0)
	check(at.dice >= 1 and at.dice <= 6, "heitto antoi %d" % at.dice)
	# Kiekon osto kaupungissa: rubiini +1000 £, kiekko pois.
	var city := 9
	at.turn = h
	at.phase = "roll"
	at.pos[h] = city
	at.money[h] = 300
	at.left = 0
	at.tokens[city] = "rubiini"
	at._build_opts()
	var bi: int = at.opts.find_custom(func(o: Dictionary) -> bool: return o.id == "buy")
	check(bi >= 0, "kaupungissa voi ostaa kiekon")
	at.confirm(bi)
	check(at.money[h] == 1200 and at.tokens[city] == "", "rubiini: -100 £ +1000 £ (%d £), kiekko pois" % at.money[h])
	# Rosvo vie kaikki rahat; tähti jää mukaan; hevosenkenkä ennen tähteä on turha.
	at.turn = h
	at.phase = "roll"
	at.tokens[city] = "rosvo"
	at._build_opts()
	at.confirm(at.opts.find_custom(func(o: Dictionary) -> bool: return o.id == "buy"))
	check(at.money[h] == 0, "rosvo vie kaikki rahat")
	at.star_found = false
	at.tokens[city] = "hevosenkenka"
	at.turn = h
	at.phase = "roll"
	at.money[h] = 300
	at._open_token(true)
	check(at.carry[h] == "", "hevosenkenkä ennen tähteä ei kelpaa")
	at.tokens[city] = "tahti"
	at._open_token(true)
	check(at.carry[h] == "tahti" and at.star_found, "tähden löytäjä kantaa tähteä")
	# Meritie maksaa 100 £: ilman rahaa satamasta ei lähdetä merelle.
	var port := 23
	at.turn = h
	at.carry[h] = ""
	at.prev = -1
	at.pos[h] = port
	at.money[h] = 50
	var sea_poor := false
	for e: Dictionary in at._cands():
		if at.nodes[e.to].kind == "meri":
			sea_poor = true
	check(not sea_poor, "ilman 100 £ ei lähdetä merelle")
	at.money[h] = 500
	var sea_ok := false
	for e: Dictionary in at._cands():
		if at.nodes[e.to].kind == "meri":
			sea_ok = true
			at._step(e.to)
			break
	check(sea_ok and at.money[h] == 400, "meritien lähtö maksaa 100 £ (%d £)" % at.money[h])
	# Koko peli tietokoneen pelaamana (myös pelaajan puolesta).
	at.new_game()
	var guard := 0
	while at.phase != "over" and guard < 40000:
		if at.turn == h and (at.phase == "roll" or at.phase == "choose"):
			at.confirm(at._ai_pick())
		else:
			at.step(5.0)
		guard += 1
	check(at.phase == "over" and at.winner >= 0, "peli päättyy voittoon (%d askelta)" % guard)
	if at.winner >= 0:
		check(at.carry[at.winner] != "" and at.pos[at.winner] <= 1, "voittajalla tähti tai hevosenkenkä ja hän on Tangerissa tai Kairossa")
		check(not at.ending_lines().is_empty(), "voitto kirjataan lopputulokseen")
	main.end_activity()
	next()


## Tekstien pituusrajat (puhekuplassa enintään 120 merkkiä) ja kysymysten eheys.
func _tekstit() -> void:
	var ms: GDScript = load("res://scripts/muistelu.gd")
	var ok := true
	for s: Dictionary in ms.STORIES + ms.OWN:
		if s.text.length() > 120:
			ok = false
			print("  liian pitkä: ", s.text)
		if s.opts.size() != 3:
			ok = false
		for o: Array in s.opts:
			if o[2].length() > 120:
				ok = false
				print("  liian pitkä vastaus: ", o[2])
	check(ok, "tarinoiden tekstit mahtuvat puhekuplaan")
	var lp: GDScript = load("res://scripts/lautapeli.gd")
	var cats := {}
	for qn: Array in lp.QUESTIONS:
		cats[qn[0]] = int(cats.get(qn[0], 0)) + 1
	check(cats.size() == lp.CATS.size() and cats.values().all(func(n: int) -> bool: return n >= 5), "jokaisessa aihepiirissä vähintään 5 kysymystä")


## Paikka, jossa kumpikaan liekki ei ole.
func _free_x(mk: Node) -> float:
	for x in [0.0, -0.3, 0.3, -0.5, 0.5]:
		var free := true
		for f: float in mk.flames():
			if absf(x - f) < mk.FLAME_W + 0.1:
				free = false
		if free:
			return x
	return 0.0


func _key_q() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_Q
	e.physical_keycode = KEY_Q
	e.pressed = true
	return e
