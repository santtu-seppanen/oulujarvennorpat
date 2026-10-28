extends SceneTree
## Tarinan testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/tarinatesti.gd
## - Valikon oletus on tarina: torstai klo 18, tehtävät hahmon mukaan (Jukka keittää kahvit, Marko paistaa).
## - Tehtävät kuittautuvat vain kerran ja vain oikeana päivänä; päikkärit (heräämisestä) ja kätkö, halot ja huussi.
## - Päivä vaihtuu keskiyöllä uusiin tehtäviin, ja sunnuntaina klo 21 viikonloppu päättyy.

var main: Node3D
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0


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


func _ids(d: int) -> Array:
	var out := []
	for t in main.tarina.tasks_for(d):
		out.append(t.id)
	return out


func _process(delta: float) -> bool:
	clock += delta
	if main == null or main.get_script() == null:
		print("VIKA peli ei käynnisty")
		return true
	var t := clock - ts
	var ta: Node = main.tarina
	match step:
		0:
			if clock > 2.0:
				check(ta.active == false, "tarina ei ole päällä muilla alkuhetkillä")
				main.sun.start_preset(main.Sun.STORY_PRESET)
				var lt: Dictionary = main.sun.local()
				check(ta.active and lt.weekday == 4 and lt.hour == 18, "tarina alkaa torstaina klo 18 (viikonpäivä %d, klo %d)" % [lt.weekday, lt.hour])
				check(not _ids(0).has("paikkarit") and not _ids(0).has("aamupala") and not _ids(0).has("kahvi"), "Santtun torstai: ei päikkäreitä, pyttipannun syöntiä eikä kahvinkeittoa %s" % [_ids(0)])
				check(_ids(1).has("paikkarit") and _ids(1).has("aamupala"), "Santtun perjantai: päikkärit ja pyttipannun syönti %s" % [_ids(1)])
				main.choose_character(3)
				check(_ids(0).has("kahvi") and not _ids(0).has("paikkarit"), "Jukan torstai: kahvit, ei päikkäreitä %s" % [_ids(0)])
				main.choose_character(1)
				check(_ids(1).has("pytti") and not _ids(1).has("kahvi") and not _ids(0).has("pytti"), "Markon pyttipannu perjantaina, ei torstaina %s" % [_ids(1)])
				main.choose_character(0)
				# Tehtävät arvotaan: tarkistetaan määrä ja se, että ennätystehtävät ovat joka päivä.
				for d in 4:
					var picks := 0
					for tk in ta.plan[d]:
						for pt in ta.POOL:
							if pt.id == tk.id:
								picks += 1
					check(picks == int(ta.DAYS[d].picks), "päivälle %d arvottiin %d poolitehtävää" % [d, ta.DAYS[d].picks])
					check(_ids(d).has("tennis") and _ids(d).has("heittely"), "päivän %d tehtävissä pinkiponki ja amerikkalainen" % d)
				check(_ids(2).has("retki") and _ids(2).has("laulu"), "lauantain kiinteät tehtävät: retki ja laulu")
				# Testin ajaksi torstaille tietyt tehtävät, perjantaille pöytä.
				ta.plan[0] = ta.plan[0].filter(func(x: Dictionary) -> bool: return not x.id in ["halot", "huussi", "katko", "poyta"])
				for pid in ["halot", "huussi", "katko"]:
					ta.plan[0].append(ta.POOL.filter(func(x: Dictionary) -> bool: return x.id == pid)[0])
				ta.plan[1] = ta.plan[1].filter(func(x: Dictionary) -> bool: return x.id != "poyta")
				ta.plan[1].append(ta.POOL.filter(func(x: Dictionary) -> bool: return x.id == "poyta")[0])
				next()
		1:
			if t > 0.5:
				ta.complete("halot")
				check(ta.is_done("halot"), "halot kuittautuvat")
				ta.complete("poyta")
				check(not ta.is_done("poyta"), "perjantain tehtävä ei kuittaudu torstaina")
				var n: int = ta.count_done(0)
				ta.complete("halot")
				check(ta.count_done(0) == n, "tehtävä kuittautuu vain kerran")
				main.sun.t_utc = main.sun._local_to_utc(main.sun.local().year, main.sun.local().month, main.sun.local().day, 15, 30)
				main._nap()
				next()
		2:
			if t > main.NAP_T + 0.5:
				check(not ta.is_done("paikkarit"), "torstaina päikkäreitä ei ole tehtävänä")
				main._wc_result("ykkonen", {"done": true, "accuracy": 1.0})
				check(ta.is_done("huussi"), "huussikäynti kuittaa tehtävän")
				main._beer()
				check(ta.is_done("katko"), "kätköltä olut kuittaa tehtävän")
				var lt2: Dictionary = main.sun.local()
				main.sun.t_utc += (24.0 - lt2.hour) * 3600.0 + 600.0  # perjantai klo 00.10
				next()
		3:
			if t > 0.5:
				check(ta.day == 1, "päivä vaihtui perjantaiksi (päivä %d)" % ta.day)
				ta.complete("tennis")
				check(ta.is_done("tennis"), "perjantain rantatennis kuittautuu")
				ta.records.tennis = 5
				ta._best.tennis = 12
				ta._poll(0.1)
				check(ta.records.tennis == 12, "uusi ennätys tallentuu seuraavaksi tavoitteeksi")
				check(ta.is_done("halot", 0), "torstain tulos säilyy")
				main.maine = 50
				ta._record_penalties(0)  # torstain pinkiponki ja heittely jäivät rikkomatta
				check(main.maine == 30, "rikkomaton ennätystavoite maksaa 10 mainepistettä kummaltakin (maine %d)" % main.maine)
				ta._record_penalties(1)  # perjantaina tennis tehty, heittely ei
				check(main.maine == 20, "tehty ennätystavoite ei maksa (maine %d)" % main.maine)
				main.sun.t_utc += 2.0 * 86400.0 + 17.0 * 3600.0 + 55.0 * 60.0  # sunnuntai klo 18.05
				next()
		4:
			if t > 0.5:
				check(ta.finished, "sunnuntaina klo 18 viikonloppu päättyy")
				next()
		_:
			print("Tarinatesti valmis, virheitä: %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
