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
				check(main.activity == "muistelu", "Q aloittaa muistelun")
				var ms: Node = main.muistelu
				var maine0: int = main.maine
				ms.act()  # intro -> ensimmäinen tarina
				var told_first := 0
				for k in 4:
					check(ms._phase == "choose", "tarina %d valittavana" % (k + 1))
					ms.choose(0)
					told_first += 1
					check(ms._phase == "reply", "vastaus tarinaan %d" % (k + 1))
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
			print("Valmis, vikoja: %d" % fails)
			quit(1 if fails > 0 else 0)
	return false


## Afrikan tähti: kartta, arvonta, liikkuminen, kaupungin jakaminen ja koko peli tietokoneen pelaamana.
func _afrikka() -> void:
	var at: Node = main.afrikka
	var A: GDScript = load("res://scripts/afrikantahti.gd")
	var all_linked := true
	for c in A.CITIES.size():
		if A.distance(A.START, c) >= 99:
			all_linked = false
	check(all_linked and A.neighbors(A.START).size() >= 2, "kaikki kaupungit saavutettavissa Tunisista")
	main.start_activity("lautapeli")
	main.lautapeli.choose(1)
	await create_timer(0.3).timeout
	check(main.activity == "afrikka" and at.phase == "roll", "Q-valinta 2 aloittaa Afrikan tähden")
	var set_ok: bool = at.gem_city.size() == A.GEM_COUNT and not at.gem_city.has(A.START) and at.star_city != A.START \
		and not at.gem_city.has(at.star_city)
	check(set_ok, "timantit ja tähti arvottu eri kaupunkeihin (%s, tähti %d)" % [at.gem_city, at.star_city])
	check(A.distance(A.START, at.star_city) >= 3, "tähti on kaukana aloituksesta")
	# Pelaajan vuoro: noppa, liike vain naapuriin, timantti kerätään saapuessa.
	at.turn = main.player_index
	at.phase = "roll"
	at.roll()
	check(at.phase == "move" and at.left == at.dice and at.dice >= 1 and at.dice <= 6, "heitto antaa %d liikettä" % at.dice)
	var far_city: int = at.gem_city[0]
	var before: int = at.pos[main.player_index]
	at.hop(far_city if not A.neighbors(before).has(far_city) else -1)
	check(at.pos[main.player_index] == before or A.neighbors(before).has(far_city), "ei hypätä muuhun kuin naapuriin")
	at.pos[main.player_index] = A.neighbors(at.gem_city[0])[0]
	at.left = 3
	at.phase = "move"
	at.hop(at.gem_city[0])
	check(at.gems[main.player_index].has(0) and at.left == 2, "timantti kerätty saapuessa")
	# Toisen pelaajan kaupunkiin päättävä vuoro lähettää toisen takaisin Tunisiin.
	var other: int = (main.player_index + 1) % 4
	at.pos[other] = at.gem_city[0]
	at.end_turn()
	check(at.pos[other] == A.START and at.turn == (main.player_index + 1) % 4, "samaan kaupunkiin päätyvä lähettää toisen takaisin")
	# Koko peli tietokoneen pelaamana: pelaaja heittää ja liikkuu myös automaattisesti.
	at.new_game()
	var guard := 0
	while at.phase != "over" and guard < 6000:
		if at.turn == main.player_index:
			if at.phase == "roll":
				at.roll()
			elif at.phase == "move":
				at.hop(at._ai_pick())
		else:
			at.step(5.0)
		guard += 1
	check(at.phase == "over" and at.winner >= 0, "peli päättyy voittoon (%d askelta)" % guard)
	if at.winner >= 0:
		check(at.gems[at.winner].size() == A.GEM_COUNT and at.star[at.winner] and at.pos[at.winner] == A.START, "voittajalla kaikki ja Tunisissa")
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
