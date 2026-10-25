extends SceneTree
## Läpipelitesti (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/lapipeli.gd -- <hahmo 0-3> <voitto|laiska|haviö> [kelaus, oletus 30; 0.5 pitää tekoälyt uskottavina]
## Pelaa koko viikonlopun torstaista sunnuntaihin kelaamalla aikaa (tietokoneen hahmot, tekoälyt, päivänvaihdokset ja
## ilmoitukset pyörivät oikeina) ja tekee jokaisen tehtävän päivänsä aikana (voitto), jättää ne tekemättä (laiska) tai
## ajaa maineen nollaan (haviö). Vikoina SCRIPT ERROR -rivit lokissa (kaikki tulostetaan) ja loppu, joka ei käynnisty.

var main: Node3D
var who := 0
var mode := "voitto"
var fails := 0
var frames := 0
var last_day := -1
var BOOST := 30.0  # lisäkelaus oikean 60-kertaisen päälle (kolmas argumentti)


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	who = int(a[0]) if a.size() > 0 else 0
	mode = a[1] if a.size() > 1 else "voitto"
	BOOST = float(a[2]) if a.size() > 2 else 30.0
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _process(delta: float) -> bool:
	frames += 1
	var ta: Node = main.tarina
	if frames == 60:
		main.choose_character(who)
		main.sun.start_preset(main.Sun.STORY_PRESET)
		print("pelaaja %s, tila %s" % [main.Porukka.CREW[main.player_index].name, mode])
		return false
	if frames < 120:
		return false
	if not ta.finished and not ta.lost:
		main.sun.t_utc += delta * 60.0 * BOOST
	if mode == "voitto" and ta.active and not ta.finished:
		# Tehtävät tulevat tehdyiksi päivän aikana (pelikohtaiset tapahtumat kuittaavat ne muuten itse).
		for t in ta.tasks_for(ta.day):
			if not ta.is_done(t.id):
				ta.complete(t.id)
				if not ta.is_done(t.id) and ta._paused(t.id):
					ta.done[ta.day][t.id] = true  # rannan tehtävät ovat tauolla mökillä: kuitataan suoraan
	if mode == "haviö" and ta.day >= 1 and main.maine > 0:
		main.lose_maine(main.maine, "testi")
	if main.maine != _maine:
		print("maine %d -> %d (päivä %d klo %s): %s" % [_maine, main.maine, ta.day, main.sun.clock_text(), main._toast.text])
		_maine = main.maine
	if ta.day != last_day:
		last_day = ta.day
		print("päivä %d: %s (klo %s, maine %d, tehty %d/%d)" % [ta.day, ta.DAYS[ta.day].title, main.sun.clock_text(), main.maine,
			ta.count_done(ta.day), ta.tasks_for(ta.day).size()])
	if ta.finished or ta.lost or main.maine <= 0:
		_wait += 1
		if not main.loppu.active and _wait > 120:
			check(false, "loppu ei käynnisty (finished %s, lost %s, maine %d)" % [ta.finished, ta.lost, main.maine])
			return _done()
		if main.loppu.active and not _checked:
			_checked = true
			check(true, "loppu käynnistyi: %s" % main.loppu.mode)
			check(main.loppu.mode == ("voitto" if mode != "haviö" else "tappio"), "oikea loppu (%s)" % main.loppu.mode)
			if mode == "voitto":
				for d in 4:
					var missing := []
					for t in ta.tasks_for(d):
						if not ta.is_done(t.id, d):
							missing.append(t.id)
					check(missing.is_empty(), "päivän %d tehtävät tehty (%d/%d, puuttuu %s)" % [d, ta.count_done(d), ta.tasks_for(d).size(), missing])
		if main.loppu.active:
			_extra += 1  # anna cutscenen pyöriä hetki virheiden varalta
			if _extra > 900:
				return _done()
	if frames > 120000:
		check(false, "aikaraja: päivä %d klo %s" % [ta.day, main.sun.clock_text()])
		return _done()
	return false


var _extra := 0
var _wait := 0
var _maine := 50
var _checked := false


func _done() -> bool:
	print("Läpipeli valmis, virheitä: %d" % fails)
	quit(1 if fails > 0 else 0)
	return true
