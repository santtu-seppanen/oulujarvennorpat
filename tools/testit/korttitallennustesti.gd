extends SceneTree
## Korttipelien tallennuksen testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/korttitallennustesti.gd
## Kesken jäänyt tuppi ja ristiseiskan viikonloppupisteet palautuvat levyltä samaan kohtaan.

var main: Node3D
var fails := 0
var frames := 0


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://korttipelit.cfg"))
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _process(_d: float) -> bool:
	frames += 1
	if frames < 60:
		return false
	var k: Node = main.kortit
	# Ristiseiska: yksi kierros pelataan loppuun, pisteet kertyvät.
	k.logic.deal(7)
	var rng := RandomNumberGenerator.new()
	while k.logic.phase != "over":
		var a: int = k.logic.actor()
		if k.logic.phase == "play":
			k.logic.play(a, k.logic.bot_play(a, rng))
		else:
			k.logic.give(a, k.logic.bot_give(a, rng))
	check(k.logic.rounds == 1, "kierros kirjattu")
	check(k.leaders().size() >= 1 and k.leaders().has(k.logic.finished[0]), "voittaja on pisteiden johtaja")
	# Tuppi kesken: jako aloitettu, muutama kortti pelattu.
	k.kind = "tuppi"
	k.tuppi.deal(11)
	for p in 4:
		k.tuppi.bid(k.tuppi.actor(), k.tuppi.bot_bid(k.tuppi.actor(), rng))
	for i in 5:
		k.tuppi.play(k.tuppi.actor(), k.tuppi.bot_play(k.tuppi.actor(), rng))
	k.tuppi.scores = [12, 0]
	k._broadcast()
	var want_tuppi: Dictionary = JSON.parse_string(JSON.stringify(k.tuppi.to_dict()))
	var want_totals: Array = k.logic.totals.duplicate()
	# Uusi korttipeli-solmu lataa tallennuksen.
	var k2: Node = load("res://scripts/korttipeli.gd").new()
	k2.game = main
	main.add_child(k2)
	check(k2.kind == "tuppi", "pelimuoto palautui")
	check(k2.tuppi.scores == [12, 0], "tupin pisteet palautuivat")
	check(JSON.parse_string(JSON.stringify(k2.tuppi.to_dict())) == want_tuppi, "tupin kesken oleva jako palautui samaan kohtaan")
	check(k2.logic.totals == want_totals and k2.logic.rounds == 1, "ristiseiskan viikonloppupisteet palautuivat")
	k2.reset_weekend()
	check(k2.logic.totals == [0, 0, 0, 0] and k2.leaders().is_empty(), "uusi viikonloppu nollaa pisteet")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://korttipelit.cfg"))
	print("Korttitallennustesti valmis, virheitä: %d" % fails)
	return true
