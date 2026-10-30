extends SceneTree
## Nauhoitetut puheet (headless): jokaiselle puhe_lauseet.gd:n riville on nauhoite, puhelujen äänet ja oodin sanat löytyvät,
## eikä pelaajien kirjoittamilla viesteillä ole nauhoitetta: godot --headless --path . -s tools/testit/puhetesti.gd

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _initialize() -> void:
	var Puhe: GDScript = load("res://scripts/puhe.gd")
	var rows: Array = load("res://scripts/puhe_lauseet.gd").all()
	var missing := 0
	for e: Array in rows:
		if not Puhe.has(e[0], e[1]):
			missing += 1
			print("  puuttuu: %s / %s" % [e[0], e[1]])
	check(rows.size() > 500 and missing == 0, "kaikki %d repliikkiä nauhoitettu (puuttuu %d)" % [rows.size(), missing])
	var Tyo: GDScript = load("res://scripts/tyopuhelu.gd")
	check(Puhe.has("esimies", Tyo.CALLS[0][1]), "esimiehen puhelu: nalkuttava miesääni")
	check(Puhe.has("vaimo", load("res://scripts/baari.gd").WIFE_LINES[0]), "vaimon puhelu: nalkuttava naisääni")
	check(not Puhe.has("santtu", "Tämä on pelaajan itse kirjoittama viesti, jota ei ole nauhoitettu."), "kirjoitetulla viestillä ei ole nauhoitetta")
	var Oodi: GDScript = load("res://scripts/oodi.gd")
	var w: String = Oodi.words(Oodi.VERSE[0])[0]
	check(Puhe.has("marko", w), "oodin sana '%s' nauhoitettu" % w)
	check(Puhe.key("marko", " a ") == Puhe.key("marko", "a"), "tiiviste ei välitä välilyönneistä")
	var node: Node = Puhe.new()
	root.add_child(node)
	check(node.play("esimies", Tyo.CALLS[0][1]) and node.speaking(), "nauhoite soi (speaking)")
	check(not node.play("santtu", "Ei nauhoitettu rivi"), "nauhoittamaton rivi ei soi")
	print("--- %d virhettä" % fails)
	quit(1 if fails > 0 else 0)
