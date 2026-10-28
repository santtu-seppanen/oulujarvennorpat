extends CanvasLayer
## Minipelien ohjeruutu: seikkaperäiset säännöt ja näppäimet jokaiselle pelille (TEXTS). open(id) näyttää ohjeen ja
## kutsuu closed-takaisinkutsun, kun se suljetaan; pelin ajan peli odottaa (baari.gd ja pöytäpelit tarkistavat is_open()).
## Ohjeet ovat aina piilossa, kunnes pelaaja pyytää ne: J avaa ohjeen pelin aikana (sama näppäin kuin tehtävälistan
## piilotus pääpelissä), eikä mikään peli avaa ohjetta itsestään (open_first ei näytä mitään).
## J / E / Enter / välilyönti / Esc / klikkaus sulkee, nuolet ↑↓ ja hiiren rulla vierittävät.

const Ui := preload("res://scripts/ui.gd")

## id -> [otsikko, ohjeteksti (BBCode)].
const TEXTS := {
	"pajatso": ["PAJATSO", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Kolikko voittorakoon. Keskellä [b]14 €[/b], reunoilla 2–3 € tai panos takaisin (R).

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]E[/b] kolikko lyöntipaikalle, pohjassa voima kasvaa, irti = lento
[b]Välilyönti[/b] peukalotuki · [b]S[/b] snaiffaus
[b]K[/b] tönäise (liian kova = TILT) · [b]W[/b] maksuvipu
[b]D[/b] vaihtokone: 2 € kolikko kahdeksi euroksi

[b]F[/b] / [b]Esc[/b] lopettaa[/center]"""],
	"hedelma": ["HEDELMÄPELI", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Kolme samaa tai kolme hedelmää keskilinjalle.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]W / S[/b] panos 1–3 € · [b]E[/b] pyöräytä
Häviön jälkeen [b]1 2 3[/b] lukitsee rullan (ei kahdesti peräkkäin)
Voitot kertyvät koneeseen ja maksetaan, kun lopetat.

[color=#ffd23a][b]Voitot (panos 1 €)[/b][/color]
RAY 30 · apila/meloni 20 · päärynä/rypäle 12 · luumu/appelsiini 10 · tähti 4 · mitkä tahansa kolme hedelmää 2

[b]F[/b] / [b]Esc[/b] lopettaa ja ottaa voitot[/center]"""],
	"pokeri": ["POKERI", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Viisi korttia, jokeri villi. Pienin voitto: kaksi paria.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]W / S[/b] panos 1–5 € · [b]E[/b] jaa
[b]1–5[/b] tai klikkaus: PIDÄ · [b]E[/b] vaihda loput
Voitolla [b]E[/b] talteen tai [b]A[/b] PIENI (A–6) / [b]D[/b] SUURI (8–K) tuplaa
Musta seiska vie voiton, punainen päättää tuplauksen

[color=#ffd23a][b]Voitot (× panos)[/b][/color]
Viitoset 50 · Värisuora 50 · Neloset 25 · Täyskäsi 10 · Väri 6 · Suora 4 · Kolmoset 2 · Kaksi paria 1

[b]F[/b] / [b]Esc[/b] lopettaa[/center]"""],
	"karaoke": ["KARAOKE", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Paina nuotit osumalinjalla: tarkka osuma antaa enemmän pisteitä.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]↑ ↓[/b] + [b]E[/b] kappale · [b]A S K L[/b] (tai nuolet) nuotit
Pitkässä nuotissa pidä pohjassa. Putki nostaa kerrointa, huti katkaisee. Humala sotkee ajoitusta.

[b]F[/b] / [b]Esc[/b] lopettaa[/center]"""],
	"tanssi": ["TANSSILATTIA", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Paina nuolta, kun se osuu osumalinjalle.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]A S W D[/b] tai nuolet · neljä osumaa putkeen nostaa kerrointa (×1,0 → ×1,6)
Sinikan kanssa tulos paranee, mutta liika flirttailu saa vaimon soittamaan!

[b]F[/b] / [b]Esc[/b] lopettaa[/center]"""],
	"trivia": ["YSÄRITRIVIA", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Ensimmäinen, jolla on neljä kiilaa (kuudesta aihepiiristä), voittaa.

[color=#ffd23a][b]Ohjaus[/b][/color]
Omalla vuorolla [b]Enter[/b], vastaus chattiin, Enter. Aikaa 45 s, [b]E[/b] ohittaa.
Oikein: kiila. Väärin: vuoro siirtyy. Pikkuvirheet sallitaan.

[b]W[/b] nousee pöydästä[/center]"""],
	"afrikka": ["AFRIKAN TÄHTI", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Löydä Afrikan tähti kiekoista ja vie se ensimmäisenä Tangeriin tai Kairoon.

[color=#ffd23a][b]Ohjaus[/b][/color]
Vuorolla valitse ([b]↑ ↓[/b], [b]E[/b], numero tai klikkaus): [i]Heitä noppa[/i], [i]Lennä[/i] (300 £) tai [i]Osta kiekko[/i] (100 £)
Meritie 100 £. Aloitusraha 300 £.
Kiekot: topaasi +300 · smaragdi +600 · rubiini +1000 · rosvo vie kaiken · hevosenkenkä · tähti
Kapkaupunki +500 ensimmäiselle · Accra tuplaa jalokiven · Lagos: myrsky · Pyhä Helena ja Sahara: vapaa nopalla 1–2

[b]F[/b] nousee pöydästä[/center]"""],
	"muistelu": ["MUISTATKO KUN", """[center][color=#ffd23a][b]Tavoite[/b][/color]
Nuotiolla neljä ysärimuistoa. Vastauksesi muuttavat illan tunnelmaa ja aamun mainepisteitä.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]E[/b] jatkaa · vastaus [b]↑ ↓[/b] + [b]E[/b], [b]1 2 3[/b] tai klikkaus
Kannustus nostaa tunnelmaa, piikittely laskee.

[b]F[/b] poistuu nuotiolta valinnoissa, [b]W[/b] muulloin[/center]"""],
	"kortit": ["KORTTIPELIT", """[center][color=#ffd23a][b]Ristiseiska[/b][/color]
Laske kortit riveihin seiskasta, ristiseiska aloittaa. Ässä ja kuningas = lisävuoro. Ei voi pelata: edellinen antaa kortin. Ensin tyhjäksi voittaa.

[color=#ffd23a][b]Tuppi[/b][/color]
Neljä pelaajaa, vastapelaajat pari. Punainen tarjouskortti = rami, musta = nolo. Maa tunnustettava, ässä vie. Ensin 52 pisteeseen.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]Välilyönti[/b] jakaa · klikkaus pelaa · [b]A/D[/b] katsoo ympärille · [b]E[/b] ylhäältä · [b]W[/b] nousee[/center]"""],
}
signal closed


var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _foot: Label
var _seen := {}
var _cb := Callable()
var _id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var box := Ui.panel(self, "center", 720.0)
	_panel = box.get_parent()
	# Pajatson kaappi: punainen lakkapinta, kultareunus ja musta LED-otsikkokyltti.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.5, 0.05, 0.07, 0.96)
	sb.border_color = Color(0.95, 0.78, 0.25)
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(22)
	sb.shadow_size = 18
	sb.shadow_color = Color(1.0, 0.75, 0.2, 0.35)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 20)
	_panel.add_theme_stylebox_override("panel", sb)
	var plate := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.04, 0.03, 0.05)
	psb.border_color = Color(0.7, 0.7, 0.75)
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(8)
	psb.content_margin_top = 6
	psb.content_margin_bottom = 6
	plate.add_theme_stylebox_override("panel", psb)
	box.add_child(plate)
	_title = Ui.label(plate, "", 30, Ui.YELLOW)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.fit_content = false
	_body.custom_minimum_size = Vector2(680, 400)
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_font_size_override("bold_font_size", 21)
	_body.add_theme_color_override("default_color", Color(1.0, 0.96, 0.85))
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_body)
	_foot = Ui.label(box, "E / klikkaus: sulje   ·   ↑ ↓ vierittää   ·   J: ohje", 15,
		Color(1.0, 0.85, 0.5))


func has_text(id: String) -> bool:
	return TEXTS.has(id)


func is_open() -> bool:
	return visible


## Näytä ohje id; on_close kutsutaan sulkemisen jälkeen.
func open(id: String, on_close := Callable()) -> void:
	if not TEXTS.has(id):
		if on_close.is_valid():
			on_close.call()
		return
	_id = id
	_seen[id] = true
	_cb = on_close
	var t: Array = TEXTS[id]
	_title.text = "★ %s ★" % t[0]
	_body.text = t[1]
	_body.scroll_to_line(0)
	var vp := get_viewport().get_visible_rect().size
	_body.custom_minimum_size.y = clampf(vp.y - 260.0, 240.0, 440.0)
	visible = true
	CamCtl.free_mouse = true


## Ohjetta ei avata itsestään: kutsuu on_close heti (säilytetty, jotta pelit voivat odottaa ohjeen jälkeen).
func open_first(_id: String, on_close := Callable()) -> void:
	if on_close.is_valid():
		on_close.call()


func close() -> void:
	if not visible:
		return
	visible = false
	var cb := _cb
	_cb = Callable()
	if cb.is_valid():
		cb.call()
	closed.emit()


func reset_seen() -> void:
	_seen.clear()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var kc: Key = event.keycode
		if kc == KEY_UP or kc == KEY_DOWN or kc == KEY_PAGEUP or kc == KEY_PAGEDOWN:
			var bar := _body.get_v_scroll_bar()
			var d := 60.0 if (kc == KEY_DOWN or kc == KEY_PAGEDOWN) else -60.0
			bar.value += d * (4.0 if kc == KEY_PAGEUP or kc == KEY_PAGEDOWN else 1.0)
		elif not event.echo and kc in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_J, KEY_F]:
			close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()
