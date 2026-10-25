extends SceneTree
## Saunan sytytysminipelin testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/sytytystesti.gd
## - Asettelu: ilmassa roikkuva klapi hylätään, esineet menevät jonon mukaan, Backspace/tyhjennys palauttaa jonoon.
## - Laatu: syttö keskellä on paras, klapi keskellä tukkii vedon, ilman sytykettä ei syty.
## - Pelti: kiinni savu täyttää saunan, mutta pellin ehtii avata kesken syttymisen.
## - Tulen kesto: täysi asettelu antaa neljä halkoa, huono veto lyhyemmän tulen.

var Game: GDScript
var fails := 0
var results: Array[Dictionary] = []


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _make(logs := 4) -> CanvasLayer:
	var g: CanvasLayer = Game.new()
	g.logs = logs
	g.finished.connect(func(r: Dictionary) -> void: results.append(r))
	root.add_child(g)
	g._t = 1.0
	return g


func _run(g: CanvasLayer, secs: float) -> void:
	var t := 0.0
	while is_instance_valid(g) and g.phase == "burn" and t < secs:
		g._step(0.05)
		t += 0.05


var frames := 0


func _initialize() -> void:
	Game = load("res://scripts/sytytys_game.gd")


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_testit()
	return frames > 3


func _testit() -> void:
	var g := _make()
	check(g.queue == ["klapi", "klapi", "sytto", "klapi", "klapi"], "jono neljällä halolla")
	check(Game.items_for(1) == ["klapi", "sytto"] and Game.items_for(3).size() == 4, "jono vähemmällä")
	check(not g.place(3), "ylärivin klapi ei pysy ilmassa")
	check(g.place(0) and g.place(2) and g.place(1), "klapit ja syttö alariville")
	check(not g.place(1), "täyteen paikkaan ei voi asettaa")
	g.undo()
	check(g.slots[1] == "" and g.queue[0] == "sytto", "Backspace palauttaa syttö-esineen jonoon")
	g.place(1)
	check(g.place(3) and g.place(4) and g.queue.is_empty(), "päälle kaksi klapia")
	check(g.layout_quality() == 1.0 and g.can_light(), "täydellinen asettelu")
	g.clear_all()
	check(g.slots.count("") == 5 and g.queue.size() == 5, "tyhjennys palauttaa kaiken")
	g.light()
	check(g.phase == "build", "ilman sytykettä ei syty")
	g.place(1)  # klapi keskelle
	g.place(0)
	g.place(2)  # syttö sivulle
	check(g.layout_quality() <= 0.4, "klapi keskellä tukkii vedon")
	g.queue_free()

	# Täydellinen asettelu, pelti auki: onnistuu nopeasti.
	g = _make()
	g.damper = true
	for s in [0, 2, 1, 3, 4]:
		g.place(s)
	g.light()
	_run(g, 10.0)
	var r: Dictionary = results.pop_back()
	check(r.ok and r.logs == 4 and r.quality == 1.0 and not r.smoky, "täydellinen sytytys onnistuu savuttamatta")

	# Pelti unohtui eikä sitä avata: savu täyttää saunan.
	g = _make()
	for s in [0, 2, 1, 3, 4]:
		g.place(s)
	g.light()
	_run(g, 10.0)
	r = results.pop_back()
	check(not r.ok and r.why.contains("Savu"), "unohtunut pelti: savu täyttää saunan")

	# Pelti avataan vasta tikun jälkeen: onnistuu, mutta savuttaa.
	g = _make()
	for s in [0, 2, 1, 3, 4]:
		g.place(s)
	g.light()
	var t := 0.0
	while t < 2.0:
		g._step(0.05)
		t += 0.05
	g.toggle_damper()
	_run(g, 10.0)
	r = results.pop_back()
	check(r.ok and r.smoky and r.damper, "pelti auki kesken syttymisen: sytyttää, savuttaa")

	# Tulen kesto: ainoa halko ja syttö.
	g = _make(1)
	g.damper = true
	g.place(0)
	g.place(1)
	g.light()
	_run(g, 10.0)
	r = results.pop_back()
	check(r.ok and r.logs == 1, "yksi halko riittää sytytykseen")

	# Esc/F keskeyttää ilman seurauksia.
	g = _make()
	g.quit()
	r = results.pop_back()
	check(r.quit and not r.ok, "F keskeyttää")

	print("vikoja %d" % fails)
	quit(1 if fails > 0 else 0)
