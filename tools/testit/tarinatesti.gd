extends SceneTree
## Tarinan testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/tarinatesti.gd
## - Valikon oletus on tarina: torstai klo 12, tehtävät hahmon mukaan (Jukka keittää kahvit, Marko paistaa).
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
				check(ta.active and lt.weekday == 4 and lt.hour == 12, "tarina alkaa torstaina klo 12 (viikonpäivä %d, klo %d)" % [lt.weekday, lt.hour])
				check(_ids(0).has("paikkarit") and not _ids(0).has("kahvi"), "Santtun torstai: päikkärit, ei kahvinkeittoa %s" % [_ids(0)])
				main.choose_character(3)
				check(_ids(0).has("kahvi") and not _ids(0).has("paikkarit"), "Jukan torstai: kahvit päikkärien tilalla %s" % [_ids(0)])
				main.choose_character(1)
				check(_ids(1).has("pytti") and not _ids(1).has("kahvi"), "Markon perjantai: pyttipannu %s" % [_ids(1)])
				main.choose_character(0)
				for d in 4:
					check(_ids(d).has("sauna") or d == 2, "päivän %d tehtävissä on sauna tai retki" % d)
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
				check(ta.is_done("paikkarit"), "päikkäreiltä herääminen kuittaa tehtävän")
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
				check(ta.is_done("halot", 0), "torstain tulos säilyy")
				main.sun.t_utc += 2.0 * 86400.0 + 20.0 * 3600.0 + 55.0 * 60.0  # sunnuntai klo 21.05
				next()
		4:
			if t > 0.5:
				check(ta.finished, "sunnuntaina klo 21 viikonloppu päättyy")
				next()
		_:
			print("Tarinatesti valmis, virheitä: %d" % fails)
			quit(1 if fails > 0 else 0)
			return true
	return false
