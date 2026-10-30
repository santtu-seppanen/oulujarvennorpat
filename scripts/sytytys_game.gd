extends CanvasLayer
## Saunan sytytys: kun kiuas on sammunut, tuli tehdään itse. Pesään asetellaan klapit ja syttö (tuohi ja pilkkeet) pyramidiksi
## ja muistetaan avata pelti, ennen kuin tulitikku raapaistaan.
## Pesä: alarivillä kolme paikkaa, päällä kaksi, jotka nojaavat kahteen alapaikkaan (tue ensin alta). Syttö kuuluu alarivin
## keskelle, klapit sen kummallekin puolelle ja päälle: silloin tuli vetää. Klapi keskellä tukkii vedon, ja syttö ylhäällä
## syttyy hitaasti. Pelti kiinni: savu täyttää saunan, ellei peltiä ehdi avata kesken syttymisen.
## A / D valitsee paikan, E asettaa seuraavan, Backspace ottaa viimeisen pois, R tyhjentää, P avaa ja sulkee pellin, Enter raapaisee
## tulitikun. F lopettaa. Hiirellä: klikkaa paikkaa tai peltiä.

const MG := preload("res://scripts/mg_draw.gd")

signal finished(res: Dictionary)

const SLOTS := 5  # 0..2 alarivi, 3..4 päällä
const BURN_MAX := 9.0  # näin kauan tuli yrittää syttyä
const RATE_OPEN := 0.34  # syttymisnopeus sekunnissa pelti auki ja täydellä vedolla
const RATE_SHUT := 0.07
const SMOKE_UP := 0.3
const SMOKE_DOWN := 0.5
const SMOKY_AT := 0.5  # tästä ylöspäin savuttanut sauna haisee ja tuli jää pienemmäksi
const INPUT_DELAY := 0.25

var damper := false  # pelti auki
var outdoor := false  # nuotio: ei peltiä, veto on aina auki
var logs := 4  # syliin otetut halot
var drunk := 0.0

var slots: Array[String] = []  # "" | "klapi" | "sytto"
var queue: Array[String] = []  # jäljellä olevat esineet
var cursor := 1
var phase := "build"  # build / burn / done
var prog := 0.0
var smoke := 0.0
var peak_smoke := 0.0
var quality := 1.0
var _stack: Array[int] = []  # asetetut paikat järjestyksessä (Backspace)
var _bt := 0.0
var _t := 0.0
var _match := 0.0
var _root: Control
var _info: Label
var _say: Label
var _say_t := 0.0


func _ready() -> void:
	layer = 6
	slots.resize(SLOTS)
	slots.fill("")
	queue = items_for(logs)
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.draw.connect(_draw_root)
	add_child(_root)
	_info = _label(24, 40)
	_say = _label(28, 84)
	if outdoor:
		damper = true
		say("Tuohta, pilkkeitä ja klapeja. Syttö keskelle, klapit sen ympärille!")
	else:
		say("Tuohta, pilkkeitä ja klapeja. Pelti auki ennen tikkua!")


func _label(size: int, top: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.anchor_right = 1.0
	l.offset_top = top
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


## Esineet asetteluun: kaksi klapia, syttö ja loput klapit (1 halko: klapi ja syttö).
static func items_for(n: int) -> Array[String]:
	var q: Array[String] = []
	for k in mini(n, 2):
		q.append("klapi")
	q.append("sytto")
	for k in maxi(0, n - 2):
		q.append("klapi")
	return q


func say(t: String) -> void:
	_say.text = t
	_say_t = 2.6


# --- Pelilogiikka -----------------------------------------------------------------------------------------------

## Alapaikat, joille ylärivin paikka nojaa.
static func supports(slot: int) -> Array[int]:
	return [slot - 3, slot - 2] if slot >= 3 else []


## Voiko seuraavan esineen asettaa paikalle? Tyhjä merkkijono = voi, muuten syy.
func why_not(slot: int) -> String:
	if phase != "build" or queue.is_empty():
		return "Ei enää mitään asetettavaa."
	if slots[slot] != "":
		return "Paikka on jo täynnä."
	for s in supports(slot):
		if slots[s] == "":
			return "Ei pysy ilmassa – tue ensin alta."
	return ""


func place(slot: int) -> bool:
	var why := why_not(slot)
	if why != "":
		say(why)
		Sfx.play("step_wood", -12.0, 1.3)
		return false
	var item: String = queue.pop_front()
	slots[slot] = item
	_stack.append(slot)
	Sfx.play("step_wood", -6.0, 0.8 if item == "klapi" else 1.6)
	if queue.is_empty():
		say("Valmista. Pelti auki? Sitten tulitikku (Enter).")
	return true


## Ottaa viimeksi asetetun takaisin (ei, jos päällä on jotain sen varassa).
func undo() -> void:
	if phase != "build" or _stack.is_empty():
		return
	var slot: int = _stack.pop_back()
	queue.push_front(slots[slot])
	slots[slot] = ""
	Sfx.play("step_wood", -12.0, 1.1)


func clear_all() -> void:
	while not _stack.is_empty():
		undo()


func toggle_damper() -> void:
	if phase == "done" or outdoor:
		return
	damper = not damper
	Sfx.play("door", -10.0, 0.6 if damper else 0.9)
	say("Pelti auki." if damper else "Pelti kiinni.")


## Syttymisen laatu pesän asettelusta: 1 = täydellinen veto.
func layout_quality() -> float:
	var q := 1.0
	var sytto := slots.find("sytto")
	if sytto == 1:
		q = 1.0
	elif sytto in [0, 2]:
		q = 0.6
	else:
		q = 0.35
	if slots[1] == "klapi":
		q = minf(q, 0.4)  # tukkii vedon
	return q


func can_light() -> bool:
	return phase == "build" and queue.is_empty() and slots.has("sytto")


## Tulitikku: pesä syttyy tai ei.
func light() -> void:
	if phase != "build":
		return
	if not slots.has("sytto"):
		say("Ilman sytykettä klapit eivät syty. Aseta syttö.")
		return
	if slots.count("klapi") == 0:
		say("Pane edes yksi klapi syttyvän päälle.")
		return
	quality = layout_quality()
	phase = "burn"
	_bt = 0.0
	_match = 1.0
	Sfx.play("whoosh", -8.0, 1.8)
	say("Tikku sytyttää tuohen…" if damper else "Tikku sytyttää tuohen… mutta pelti on kiinni!")


func _step(delta: float) -> void:
	_match = maxf(0.0, _match - delta)
	_bt += delta
	prog += quality * (RATE_OPEN if damper else RATE_SHUT) * delta
	if damper:
		smoke = maxf(0.0, smoke - SMOKE_DOWN * delta)
	else:
		smoke += SMOKE_UP * delta
	peak_smoke = maxf(peak_smoke, smoke)
	if damper and prog < 1.0 and peak_smoke > 0.3 and _say_t <= 0.0:
		say("Veto otti – savu alkaa kadota.")
	if smoke >= 1.0:
		_end(false, "Savu täyttää saunan! Pelti oli kiinni. Klapit takaisin syliin, uusi yritys.")
	elif prog >= 1.0:
		_end(true, "")
	elif _bt >= BURN_MAX:
		_end(false, "Tuli sammui. Asettele klapit väljemmin: syttö keskelle, klapit sen sivuille ja päälle.")


func _end(ok: bool, why: String) -> void:
	phase = "done"
	var res := {"ok": ok, "logs": slots.count("klapi") if ok else 0, "quality": quality, "smoky": peak_smoke >= SMOKY_AT,
		"why": why, "damper": damper, "quit": false}
	if ok:
		Sfx.play("fire", -6.0, 1.2)
	else:
		Sfx.play("lose", -10.0)
	finished.emit(res)
	queue_free()


func quit() -> void:
	if phase == "done":
		return
	phase = "done"
	finished.emit({"ok": false, "logs": 0, "quality": 0.0, "smoky": false, "why": "", "damper": damper, "quit": true})
	queue_free()


# --- Syöte ja piirto --------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if phase == "done" or _t < INPUT_DELAY:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = event.position
		if not outdoor and _damper_rect().has_point(p):
			toggle_damper()
			return
		for s in SLOTS:
			if p.distance_to(slot_center(s)) < 46.0:
				cursor = s
				place(s)
				return
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_A, KEY_LEFT:
			if phase == "build":
				cursor = _move_cursor(-1)
		KEY_D, KEY_RIGHT:
			if phase == "build":
				cursor = _move_cursor(1)
		KEY_E, KEY_SPACE:
			place(cursor)
		KEY_ENTER, KEY_KP_ENTER:
			light()
		KEY_P:
			toggle_damper()
		KEY_BACKSPACE:
			undo()
		KEY_R:
			clear_all()
		KEY_F, KEY_ESCAPE:
			quit()


## Kursori kiertää paikat vasemmalta oikealle, alarivi ensin.
func _move_cursor(dir: int) -> int:
	return posmod(cursor + dir, SLOTS)


func _process(delta: float) -> void:
	if phase == "done":
		return
	_t += delta
	_say_t -= delta
	if _say_t <= 0.0 and phase == "build":
		_say.text = ""
	if phase == "burn":
		_step(delta)
	_info.text = _info_text()
	_root.queue_redraw()


func _info_text() -> String:
	if phase == "burn":
		return "Tuli yrittää syttyä…  %d %%" % roundi(prog * 100.0) + ("" if damper else "  · PELTI KIINNI! (P)")
	var next: String = "Kaikki paikallaan"
	if not queue.is_empty():
		next = "Seuraavaksi: " + {"klapi": "klapi", "sytto": "syttö (tuohi ja pilkkeet)"}[queue[0]]
	if outdoor:
		return "%s · A/D paikka, E aseta, Enter tikku, F pois" % next
	return "%s · pelti %s (P) · A/D paikka, E aseta, Enter tikku, F pois" % [next, "AUKI" if damper else "KIINNI"]


func _origin() -> Vector2:
	return _root.size / 2.0 + Vector2(-70, -10)


func slot_center(s: int) -> Vector2:
	var o := _origin()
	return o + [Vector2(-130, 120), Vector2(0, 120), Vector2(130, 120), Vector2(-65, 32), Vector2(65, 32)][s]


func _damper_rect() -> Rect2:
	return Rect2(_origin() + Vector2(300, -250), Vector2(120, 160))


func _draw_log(c: Vector2, ghost := false) -> void:
	var a := 0.45 if ghost else 1.0
	_root.draw_circle(c + Vector2(2, 3), 49.0, Color(0, 0, 0, 0.3 * a))
	_root.draw_circle(c, 49.0, Color(0.36, 0.22, 0.12, a))  # kaarna
	_root.draw_circle(c, 43.0, Color(0.86, 0.68, 0.44, a))  # pää
	for r in [32.0, 21.0, 10.0]:
		_root.draw_arc(c, r, 0.0, TAU, 24, Color(0.62, 0.43, 0.24, a), 2.0)
	_root.draw_line(c, c + Vector2(30, -12), Color(0.5, 0.33, 0.18, a), 1.5)  # halkeama
	_root.draw_arc(c, 49.0, 0.0, TAU, 28, Color(0.08, 0.06, 0.05, 0.9 * a), 2.0, true)


func _draw_sytto(c: Vector2, ghost := false) -> void:
	var a := 0.5 if ghost else 1.0
	for k in 7:  # pilkkeet viuhkana
		var ang := -PI / 2.0 + (k - 3) * 0.28
		var d := Vector2(cos(ang), sin(ang))
		_root.draw_line(c + Vector2(0, 28) - d * 4.0, c + Vector2(0, 28) + d * 52.0, Color(0.7, 0.52, 0.3, a), 5.0)
		_root.draw_line(c + Vector2(0, 28), c + Vector2(0, 28) + d * 52.0, Color(0.9, 0.75, 0.5, a), 1.5)
	# Tuohi: valkoinen kiehkura
	_root.draw_rect(Rect2(c + Vector2(-26, 14), Vector2(52, 20)), Color(0.95, 0.94, 0.88, a))
	_root.draw_rect(Rect2(c + Vector2(-26, 14), Vector2(52, 20)), Color(0.1, 0.08, 0.06, 0.9 * a), false, 2.0)
	for k in 4:
		_root.draw_line(c + Vector2(-22 + k * 14, 18), c + Vector2(-18 + k * 14, 18), Color(0.2, 0.17, 0.14, a), 2.0)


func _draw_root() -> void:
	var sz := _root.size
	var o := _origin()
	var t := Time.get_ticks_msec() / 1000.0
	_root.draw_rect(Rect2(Vector2.ZERO, sz), Color(0, 0, 0, 0.62))
	# Kiuas: harmaa rautakuori ja pesän aukko
	var body := Rect2(o + Vector2(-230, -170), Vector2(460, 380))
	MG.solid(_root, body, Color(0.28, 0.29, 0.32))
	var mouth := Rect2(o + Vector2(-200, -110), Vector2(400, 290))
	_root.draw_rect(mouth, Color(0.06, 0.04, 0.04))
	_root.draw_rect(mouth.grow(-4), Color(0.1, 0.07, 0.06))
	_root.draw_line(mouth.position + Vector2(0, mouth.size.y), mouth.end, Color(0.2, 0.2, 0.22), 6.0)  # arina
	for k in 9:
		_root.draw_line(o + Vector2(-190 + k * 47, 176), o + Vector2(-190 + k * 47, 188), Color(0.3, 0.3, 0.34), 4.0)
	# Esineet ja kursori
	for s in SLOTS:
		var c := slot_center(s)
		if slots[s] == "klapi":
			_draw_log(c)
		elif slots[s] == "sytto":
			_draw_sytto(c)
		elif phase == "build":
			_root.draw_arc(c, 48.0, 0.0, TAU, 28, Color(1, 1, 1, 0.12), 2.0, true)
	if phase == "build":
		var cc := slot_center(cursor)
		if not queue.is_empty() and slots[cursor] == "":
			if queue[0] == "klapi":
				_draw_log(cc, true)
			else:
				_draw_sytto(cc, true)
		var ok := why_not(cursor) == ""
		_root.draw_arc(cc, 54.0, 0.0, TAU, 28, Color(0.4, 1.0, 0.4, 0.9) if ok else Color(1.0, 0.45, 0.35, 0.9), 3.0, true)
	# Liekit
	if phase == "burn":
		var g := clampf(prog, 0.0, 1.0)
		for k in 9:
			var fx := o.x - 160.0 + k * 40.0
			var h := (30.0 + 110.0 * g) * (0.6 + 0.4 * sin(t * 9.0 + k * 1.7)) * (1.0 if k % 2 == 0 else 0.7)
			var base := Vector2(fx, o.y + 170.0)
			_root.draw_colored_polygon(PackedVector2Array([base + Vector2(-16, 0), base + Vector2(0, -h), base + Vector2(16, 0)]),
				Color(1.0, 0.45 + 0.3 * g, 0.1, 0.55 + 0.4 * g))
			_root.draw_colored_polygon(PackedVector2Array([base + Vector2(-8, 0), base + Vector2(0, -h * 0.6), base + Vector2(8, 0)]),
				Color(1.0, 0.9, 0.4, 0.8))
		# Tulitikku
		if _match > 0.0:
			var mp := o + Vector2(-90, 120) + Vector2(_match * 20.0, -_match * 30.0)
			_root.draw_line(mp, mp + Vector2(60, 40), Color(0.85, 0.7, 0.45), 4.0)
			_root.draw_circle(mp, 7.0, Color(1.0, 0.5, 0.1))
	# Savu pesän suusta
	if smoke > 0.02:
		for k in 14:
			var ph := fposmod(t * 0.5 + k * 0.17, 1.0)
			var sp := Vector2(o.x - 150.0 + k * 23.0, o.y - 100.0 - ph * 150.0 * (0.5 + smoke))
			_root.draw_circle(sp, 22.0 + 30.0 * ph, Color(0.45, 0.45, 0.47, clampf(smoke, 0.0, 1.0) * (1.0 - ph) * 0.55))
	# Pelti: piippu, jossa kääntyvä läppä (ei nuotiolla)
	if not outdoor:
		var dr := _damper_rect()
		MG.solid(_root, dr, Color(0.2, 0.2, 0.22))
		var mid := dr.get_center()
		var ang := PI / 2.0 if damper else 0.0
		var dir := Vector2(cos(ang), sin(ang))
		_root.draw_line(mid - dir * 46.0, mid + dir * 46.0, Color(0.85, 0.86, 0.9), 8.0)
		_root.draw_circle(mid, 8.0, Color(0.6, 0.6, 0.65))
		_root.draw_circle(mid + dir * 46.0, 6.0, Color(0.9, 0.7, 0.2))  # kahva
		var font := ThemeDB.fallback_font
		var col := Color(0.4, 1.0, 0.4) if damper else Color(1.0, 0.45, 0.35)
		_root.draw_string(font, dr.position + Vector2(-40, dr.size.y + 28), "PELTI: " + ("AUKI" if damper else "KIINNI"),
			HORIZONTAL_ALIGNMENT_CENTER, dr.size.x + 80, 22, col)
		_root.draw_string(font, dr.position + Vector2(-40, dr.size.y + 52), "(P tai klikkaa)", HORIZONTAL_ALIGNMENT_CENTER, dr.size.x + 80, 16, Color(1, 1, 1, 0.7))
	# Jäljellä olevat esineet
	for k in queue.size():
		var qc := o + Vector2(-230.0 + k * 62.0, 250)
		if queue[k] == "klapi":
			_root.draw_circle(qc, 22.0, Color(0.86, 0.68, 0.44))
			_root.draw_arc(qc, 22.0, 0.0, TAU, 20, MG.OUTLINE, 2.0, true)
		else:
			_root.draw_rect(Rect2(qc + Vector2(-22, -10), Vector2(44, 20)), Color(0.95, 0.94, 0.88))
			_root.draw_rect(Rect2(qc + Vector2(-22, -10), Vector2(44, 20)), MG.OUTLINE, false, 2.0)
	if phase == "burn":  # syttymismittari
		var bar := Rect2(o + Vector2(-230, 300), Vector2(460, 16))
		_root.draw_rect(bar, Color(0, 0, 0, 0.6))
		_root.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(prog, 0.0, 1.0), bar.size.y)), Color(1.0, 0.6, 0.15))
		_root.draw_rect(Rect2(bar.position + Vector2(0, 22), Vector2(bar.size.x * clampf(smoke, 0.0, 1.0), 10)), Color(0.6, 0.6, 0.65))
