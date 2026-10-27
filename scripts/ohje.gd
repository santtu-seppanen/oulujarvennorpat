extends CanvasLayer
## Minipelien ohjeruutu: seikkaperäiset säännöt ja näppäimet jokaiselle pelille (TEXTS). open(id) näyttää ohjeen ja
## kutsuu closed-takaisinkutsun, kun se suljetaan; pelin ajan peli odottaa (baari.gd ja pöytäpelit tarkistavat is_open()).
## Ohjeet ovat aina piilossa, kunnes pelaaja pyytää ne: J avaa ohjeen pelin aikana (sama näppäin kuin tehtävälistan
## piilotus pääpelissä), eikä mikään peli avaa ohjetta itsestään (open_first ei näytä mitään).
## J / E / Enter / välilyönti / Esc / klikkaus sulkee, nuolet ↑↓ ja hiiren rulla vierittävät.

const Ui := preload("res://scripts/ui.gd")

## id -> [otsikko, ohjeteksti (BBCode)].
const TEXTS := {
	"pajatso": ["PAJATSO", """[color=#ffd23a][b]Tavoite[/b][/color]
Saa euron kolikko putoamaan voittorakoon. Keskirako [b]14 €[/b] on vaikein, reunoilla maksetaan 2–3 € tai panos takaisin (R).

[color=#ffd23a][b]Näin pelaat[/b][/color]
• [b]E[/b]: kolikko lyöntipaikalle. Pidä pohjassa, niin voima kasvaa; päästä irti, niin kolikko lentää.
• [b]Välilyönti[/b] pohjassa: peukalotuki (ei tärinää, voima kasvaa hitaammin). [b]S[/b]: snaiffaus.
• [b]K[/b]: tönäise konetta lennon aikana. Liian kova tönäisy = TILT ja ulos!
• [b]W[/b]: maksuvipu, kun kolikko on rakoon mennyt.
• [b]D[/b]: vaihtokoneella kahden euron kolikko kahdeksi euroksi.

[b]F[/b] / [b]Esc[/b] lopettaa, rahat jäävät taskuun."""],
	"hedelma": ["HEDELMÄPELI", """[color=#ffd23a][b]Tavoite[/b][/color]
Saa keskilinjalle kolme samaa tai kolme hedelmää.

[color=#ffd23a][b]Näin pelaat[/b][/color]
• [b]W / S[/b]: panos 1–3 €. [b]E[/b]: pyöräytä.
• Häviön jälkeen [b]1[/b], [b]2[/b], [b]3[/b] lukitsee rullan seuraavaksi kierrokseksi (ei kahta kierrosta peräkkäin).
• Voitolla [b]E[/b] vie voiton talteen. Tuplausta ei ole.

[color=#ffd23a][b]Voitot (panos 1 €)[/b][/color]
RAY 30 · apila/meloni 20 · päärynä/rypäle 12 · luumu/appelsiini 10 · tähti 4 · mitkä tahansa kolme hedelmää 2.

[b]F[/b] / [b]Esc[/b] lopettaa."""],
	"pokeri": ["POKERI", """[color=#ffd23a][b]Tavoite[/b][/color]
Jokeripokeri: viisi korttia, jokeri on villi. Pienin voitto on kaksi paria.

[color=#ffd23a][b]Näin pelaat[/b][/color]
• [b]W / S[/b]: panos 1–5 €. [b]E[/b]: jaa viisi korttia.
• [b]1–5[/b] tai klikkaus: pidä kortti (PIDÄ). [b]E[/b]: vaihda loput kerran.
• Voitolla [b]E[/b] vie talteen tai [b]A[/b] = PIENI (A–6), [b]D[/b] = SUURI (8–K) tuplaa. Seiska: musta vie voiton, punainen päättää tuplauksen.

[color=#ffd23a][b]Voitot (× panos)[/b][/color]
Viitoset 50 · Värisuora 50 · Neloset 25 · Täyskäsi 10 · Väri 6 · Suora 4 · Kolmoset 2 · Kaksi paria 1.

Vinkki: pidä jokeri aina. [b]F[/b] / [b]Esc[/b] lopettaa."""],
	"karaoke": ["KARAOKE", """[color=#ffd23a][b]Tavoite[/b][/color]
Paina nuotit oikeaan aikaan. Tarkka osuma antaa enemmän pisteitä.

[color=#ffd23a][b]Näin pelaat[/b][/color]
• [b]↑ ↓[/b] ja [b]E[/b]: valitse kappale.
• Nuotit tulevat neljää kaistaa alas: paina [b]A S K L[/b] (tai nuolet), kun nuotti on osumalinjalla.
• Pitkässä nuotissa pidä näppäin pohjassa loppuun.
• Peräkkäiset osumat nostavat kerrointa, huti katkaisee putken. Humala sotkee ajoitusta.

[b]F[/b] / [b]Esc[/b] lopettaa."""],
	"tanssi": ["TANSSILATTIA", """[color=#ffd23a][b]Tavoite[/b][/color]
Paina nuolta, kun se osuu osumalinjalle.

[color=#ffd23a][b]Näin pelaat[/b][/color]
• Neljä kaistaa: [b]A S W D[/b] tai nuolinäppäimet.
• Neljä osumaa putkeen nostaa kerrointa (×1,0 → ×1,6). Huti katkaisee putken.
• Sinikan kanssa tulos paranee, mutta liika flirttailu saa vaimon soittamaan!

[b]F[/b] / [b]Esc[/b] lopettaa."""],
	"trivia": ["YSÄRITRIVIA", """[color=#ffd23a][b]Tavoite[/b][/color]
Ensimmäinen, jolla on neljä kiilaa (aihepiiriä kuudesta), voittaa.

[color=#ffd23a][b]Näin pelaat[/b][/color]
• Omalla vuorolla [b]Enter[/b], kirjoita vastaus chattiin ja Enter uudelleen. Aikaa 45 s. [b]E[/b] ohittaa.
• Oikein: kiila ja uusi kysymys. Väärin: vuoro siirtyy.
• Pikkuvirheet kirjoitusasussa eivät haittaa.

[b]W[/b] nousee pöydästä."""],
	"afrikka": ["AFRIKAN TÄHTI", """[color=#ffd23a][b]Tavoite[/b][/color]
Löydä Afrikan tähti kaupunkien kiekoista ja vie se ensimmäisenä Tangeriin tai Kairoon.

[color=#ffd23a][b]Näin pelaat[/b][/color]
• Vuorolla valitse valikosta ([b]↑ ↓[/b], [b]E[/b] tai numero; myös klikkaus): [i]Heitä noppa[/i], [i]Lennä[/i] (300 £) tai kaupungissa [i]Osta kiekko[/i] (100 £).
• Maatie: ilmainen, noppa kertoo askelet. Meritie: 100 £ sataman lähdöstä. Voit pysähtyä kesken.
• Kiekko: tyhjä · topaasi +300 £ · smaragdi +600 £ · rubiini +1000 £ · rosvo vie kaikki rahat · hevosenkenkä (käy tähden sijaan, kun tähti on löytynyt) · [b]Afrikan tähti[/b].
• Erikoispaikat: Kapkaupunki +500 £ ensimmäiselle · Accra tuplaa jalokiven · Lagos: myrsky kolmeksi vuoroksi · Pyhä Helena ja Saharan autiomaa: vapaa vasta nopalla 1 tai 2.
• Aloitusraha 300 £.

[b]F[/b] nousee pöydästä, [b]J[/b] avaa ohjeen."""],
	"muistelu": ["MUISTATKO KUN", """[color=#ffd23a][b]Tavoite[/b][/color]
Nuotiolla kerrotaan neljä ysärimuistoa. Vastauksesi muuttavat illan tunnelmaa, mikä näkyy aamun mainepisteissä.

[color=#ffd23a][b]Näin pelaat[/b][/color]
• [b]E[/b] jatkaa tarinaa.
• Vastaus: [b]↑ ↓[/b] ja [b]E[/b], tai [b]1[/b] [b]2[/b] [b]3[/b] / klikkaus.
• Kannustus ja vitsit nostavat tunnelmaa, piikittely laskee.

[b]F[/b] poistuu nuotiolta valinnoissa, [b]W[/b] muulloin."""],
	"kortit": ["KORTTIPELIT", """[color=#ffd23a][b]Ristiseiska[/b][/color]
Laske kortit riveihin seiskasta alkaen; ristiseiskan saanut aloittaa. Pelaa jatko, jos voit. Ässä ja kuningas antavat lisävuoron. Jos et voi, edellinen antaa sinulle kortin. Ensin tyhjäksi voittaa, muut saavat pisteen jokaisesta kortista.

[color=#ffd23a][b]Tuppi[/b][/color]
Neljä pelaajaa, vastapelaajat ovat pari. Tarjouskortti: punainen = rami, musta = nolo. Maata on tunnustettava, ässä vie. Ensin 52 pisteeseen voittaa.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]Välilyönti[/b] jakaa, klikkaus pelaa kortin, [b]A/D[/b] katsoo ympärille, [b]E[/b] ylhäältä. [b]W[/b] nousee pöydästä."""],
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
	var box := Ui.panel(self, "center", 860.0)
	_panel = box.get_parent()
	_title = Ui.label(box, "", 28, Ui.YELLOW)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.scroll_active = true
	_body.fit_content = false
	_body.custom_minimum_size = Vector2(820, 470)
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_font_size_override("bold_font_size", 21)
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_body)
	_foot = Ui.label(box, "E / Enter / klikkaus: valmis   ·   ↑ ↓ vierittää   ·   J avaa ohjeen pelissä milloin tahansa", 15,
		Color(0.8, 0.8, 0.85))


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
	_title.text = "OHJE · %s" % t[0]
	_body.text = t[1]
	_body.scroll_to_line(0)
	var vp := get_viewport().get_visible_rect().size
	_body.custom_minimum_size.y = clampf(vp.y - 230.0, 240.0, 520.0)
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
