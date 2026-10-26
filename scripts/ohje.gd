extends CanvasLayer
## Minipelien ohjeruutu: seikkaperäiset säännöt ja näppäimet jokaiselle pelille (TEXTS). open(id) näyttää ohjeen ja
## kutsuu closed-takaisinkutsun, kun se suljetaan; pelin ajan peli odottaa (baari.gd ja pöytäpelit tarkistavat is_open()).
## Ensimmäisellä kerralla (per istunto) ohje aukeaa itsestään (open_first), ja H avaa sen milloin tahansa uudelleen.
## E / Enter / välilyönti / Esc / klikkaus sulkee, nuolet ↑↓ ja hiiren rulla vierittävät.

const Ui := preload("res://scripts/ui.gd")

## id -> [otsikko, ohjeteksti (BBCode)].
const TEXTS := {
	"pajatso": ["PAJATSO", """[color=#ffd23a][b]Tavoite[/b][/color]
Pelaa euron kolikoilla ja yritä saada kolikko putoamaan suoraan voittoraon porttiin. Rakoja on yhdeksän: R (panos takaisin), 2, 3, 3, [b]14[/b], 3, 3, 2 ja R euroa. Keskirako 14 € on vaikein, koska tappien välistä mahtuu vain tarkka kolikko.

[color=#ffd23a][b]Näin pelaat[/b][/color]
[b]1. Kolikko sisään:[/b] paina [b]E[/b], niin euron kolikko putoaa lasin taakse lyöntipaikalle. Jos euron kolikoita ei ole, vaihda kahden euron kolikko kahdeksi euroksi vaihtokoneella ([b]D[/b] vääntää kahvaa).
[b]2. Voima:[/b] pidä [b]E[/b] pohjassa, niin sormeen kertyy voimaa (mitä pidempään, sitä kovempi isku). Päästä irti, niin laukaisin napsahtaa ja kolikko lentää vasemmalle ylös.
  • Sormi tärisee, humalassa enemmän. [b]Välilyönti[/b] pohjassa on peukalotuki: ei tärinää, mutta voima kertyy hitaammin.
  • [b]S[/b] on snaiffaus: sormenpää jarruttaa iskua hieman.
  • Kolikko lähtee aina vasemmalle ja hieman ylös, ja voima on ainoa, mitä hallitset. Kovin isku (voimalyönti) lennättää kolikon vasemman laidan 2 €:n porttiin.
[b]3. Tönäisy:[/b] kun kolikko lentää, [b]K[/b] tönäisee konetta ja vaimentaa porttien jousia hetkeksi. Liian kova tönäisy laukaisee TILT-hälyttimen, ja isäntä heittää sinut ulos!
[b]4. Voitto:[/b] kun kolikko on mennyt rakoon, paina [b]W[/b] (maksuvipu): luisti pyyhkäisee voiton juuri sen raon kolikkoputkesta kouruun. Tyhjästä putkesta kone maksaa tyhjää. Ohi mennyt kolikko valuu koneen varantoon.

[color=#ffd23a][b]Vinkit[/b][/color]
• Peukalotuki ([b]välilyönti[/b]) toistaa lyönnin lähes samanlaisena, kun haet sopivaa voimaa.
• Seiskan portti on ahtain ja sen jousi jäykin, joten sinne osuminen vaatii tarkkuutta.

[color=#ffd23a][b]Lopetus[/b][/color]
[b]F[/b] tai [b]Esc[/b] lopettaa ja rahat jäävät taskuun."""],
	"hedelma": ["HEDELMÄPELI", """[color=#ffd23a][b]Tavoite[/b][/color]
Saa kolmelle rullalle keskilinjaan kolme samaa symbolia. Panos on 1 € pyöräytykseltä.

[color=#ffd23a][b]Voittotaulukko (kolme samaa)[/b][/color]
Seiska 100 € · BAR 50 € · Kello 30 € · Meloni 20 € · Viinirypäle 15 € · Luumu 12 € · Appelsiini 10 € · Sitruuna 8 € · Kirsikka 10 €.
Lisäksi: kirsikka ensimmäisellä rullalla antaa panoksen takaisin (1 €) ja kaksi kirsikkaa vasemmalla 3 €.

[color=#ffd23a][b]Näin pelaat[/b][/color]
[b]1. Pyöräytä:[/b] [b]E[/b] ottaa panoksen ja pyöräyttää rullat. Rullat pysähtyvät yksi kerrallaan vasemmalta oikealle.
[b]2. Lukitse:[/b] jos pyöräytys hävisi, saat valita rullia lukittavaksi näppäimillä [b]1[/b], [b]2[/b] ja [b]3[/b] (rulla kerrallaan, uudestaan painaminen avaa lukon). Lukitut rullat eivät pyöri seuraavalla pyöräytyksellä. Lukitusta saa kuitenkin vain joka toisella kierroksella: lukitun pyöräytyksen jälkeen ei voi lukita heti uudestaan.
[b]3. Voitto ja tuplaus:[/b] kun voitat, kone odottaa päätöstäsi:
  • [b]E[/b] vie voiton talteen (kolikot putoavat tarjottimelle).
  • [b]Vasen (A tai ←)[/b] tuplaa PIENI: koneen kortti on 1–6.
  • [b]Oikea (D tai →)[/b] tuplaa SUURI: koneen kortti on 8–13.
  • Seiska vie aina, eli kortti 7 hävittää tuplauksen. Oikea arvaus kaksinkertaistaa voiton, ja voit tuplata uudestaan tai viedä talteen. Raja on 50 €, jolloin kone maksaa voiton automaattisesti.

[color=#ffd23a][b]Vinkit[/b][/color]
• Kaksi samaa rullilla: lukitse ne ja yritä kolmatta.
• Tuplaus on 50/50 (seiska vie): ahne jää usein ilman.

[color=#ffd23a][b]Lopetus[/b][/color]
[b]F[/b] tai [b]Esc[/b] lopettaa, ja voitto menee talteen."""],
	"pokeri": ["VIDEOPOKERI", """[color=#ffd23a][b]Tavoite[/b][/color]
Saat viisi korttia ja yrität muodostaa pokerikäden. Pelataan Jacks or Better: pari kymppejä pienempiä ei voita, vähintään jätkäpari (J–J) tarvitaan. Panos on 1–5 kolikkoa.

[color=#ffd23a][b]Näin pelaat[/b][/color]
[b]1. Panos:[/b] [b]W / ↑[/b] nostaa panosta ja [b]S / ↓[/b] laskee sitä (1–5 €). Viiden kolikon panos antaa kuninkaalliselle väristölle jättipotin.
[b]2. Jako:[/b] [b]E[/b] ottaa panoksen ja jakaa viisi korttia.
[b]3. Pidä kortit:[/b] valitse kortit, jotka pidät: näppäimet [b]1–5[/b] tai klikkaus kortin päällä pitää tai vapauttaa kortin. Vaihtoehtoisesti [b]A / D[/b] siirtää vihreää valintaa ja [b]välilyönti[/b] pitää kortin. Pidetyt kortit saavat merkinnän PIDÄ.
[b]4. Vaihto:[/b] [b]E[/b] vaihtaa pitämättömät kortit uusiin. Kierros päättyy, ja kone maksaa voiton voittotaulukon mukaan.
[b]5. Tuplaus:[/b] voiton jälkeen [b]E[/b] vie voiton talteen. Tai voit yrittää tuplata: [b]vasen (A / ←)[/b] arvaa PIENI (kone nostaa kortin A–6) ja [b]oikea (D / →)[/b] arvaa SUURI (8–K). Seiska vie aina. Oikea arvaus kaksinkertaistaa voiton, ja voit tuplata uudestaan, kunnes voitto on 100 €.

[color=#ffd23a][b]Käsien arvot (kerroin × panos)[/b][/color]
Kuninkaallinen värisuora 250 · Värisuora 50 · Neloset 25 · Täyskäsi 9 · Väri 6 · Suora 4 · Kolmoset 3 · Kaksi paria 2 · Jätkäpari tai parempi 1.

[color=#ffd23a][b]Vinkit[/b][/color]
• Pidä aina pari ja kolme samaa. Neljä samaa väriä kannattaa pitää.
• Älä pidä yhtä isoa korttia, jos kädessä on jo pari.

[color=#ffd23a][b]Lopetus[/b][/color]
[b]F[/b] tai [b]Esc[/b] lopettaa, ja voitto jää taskuun."""],
	"karaoke": ["KARAOKE", """[color=#ffd23a][b]Tavoite[/b][/color]
Laula kappale painamalla nuotit oikealla hetkellä, Frets on Fire -tyyliin. Mitä tarkemmin osut, sitä isompi pistesaalis.

[color=#ffd23a][b]Näin pelaat[/b][/color]
[b]1. Kappale:[/b] valitse listasta kappale [b]↑ ↓[/b] ja [b]E[/b] (tai Enter / välilyönti).
[b]2. Nuotit:[/b] ruudulla on neljä kaistaa. Värilliset nuotit laskeutuvat alas osumalinjalle, ja kun nuotti on linjalla, paina sen kaistan näppäintä: [b]A[/b], [b]S[/b], [b]K[/b] tai [b]L[/b] (tai nuolet ← ↓ ↑ →).
[b]3. Pitkät nuotit:[/b] pidä näppäin pohjassa nuotin loppuun asti, niin saat bonuksen.
[b]4. Putki:[/b] peräkkäiset osumat kasvattavat kerrointa. Huti tai väärä painallus katkaisee putken.
Sanat näkyvät alhaalla, ja laulettava tavu on korostettuna. Humala nykii nuotteja ja viivästää painalluksia.

[color=#ffd23a][b]Lopetus[/b][/color]
[b]F[/b] tai [b]Esc[/b] lopettaa kesken."""],
	"tanssi": ["TANSSILATTIA", """[color=#ffd23a][b]Tavoite[/b][/color]
Tanssi eurodance-biisin tahtiin: paina nuolta oikealla hetkellä, kun se osuu ruudun osumalinjalle.

[color=#ffd23a][b]Näin pelaat[/b][/color]
[b]1. Kaistat:[/b] neljä kaistaa, ← ↓ ↑ → eli [b]A S W D[/b] tai nuolinäppäimet. Nuolet laskeutuvat ylhäältä alas.
[b]2. Osumat:[/b] paina kaistan näppäin juuri kun nuoli on linjan päällä. TÄYDELLINEN, HYVÄ ja OK riippuvat ajoituksesta. Jokainen näppäily ilman nuolta tai ohi mennyt nuoli katkaisee putken.
[b]3. Putki ja kerroin:[/b] neljä osumaa putkeen nostaa kerrointa (×1,0 → ×1,6). Oikean reunan Lattia-palkki kertoo menon.
[b]4. Sinikka:[/b] jos tanssit Sinikan kanssa, tulos paranee vähän. Mutta liika flirttailu saa vaimon soittamaan!
Humala nykii ajoitusta. Biisi kestää 20 tahtia, ja kertosäkeessä askeleita tulee tiheämmin.

[color=#ffd23a][b]Lopetus[/b][/color]
[b]F[/b] tai [b]Esc[/b] lopettaa kesken."""],
	"trivia": ["YSÄRITRIVIA", """[color=#ffd23a][b]Tavoite[/b][/color]
Ensimmäinen, jolla on neljä kiilaa (aihepiiriä), voittaa. Aihepiirejä on kuusi: urheilu, musiikki, elokuvat ja tv, tekniikka ja pelit, Suomi ja maantieto sekä mökkielämä.

[color=#ffd23a][b]Näin pelaat[/b][/color]
[b]1. Vuoro:[/b] vuorossa oleva saa kysymyksen aihepiiristä, josta hänellä ei vielä ole kiilaa.
[b]2. Vastaus:[/b] kun vuoro on sinun, paina [b]Enter[/b], kirjoita vastaus chattiin ja paina Enter uudelleen. Vastausaikaa on 45 sekuntia. [b]E[/b] ohittaa kysymyksen.
[b]3. Oikein:[/b] saat kiilan ja pidät vuoron. [b]Väärin:[/b] vuoro siirtyy seuraavalle.
Muiden mökkiläisten puolesta vastaa tietokone, ja heidän taitonsa vaihtelee hahmoittain. Pikkuvirheet kirjoitusasussa eivät haittaa (isot kirjaimet ja ääkköset ovat vapaaehtoisia).

[color=#ffd23a][b]Lopetus[/b][/color]
[b]W[/b] nousee pöydästä."""],
	"afrikka": ["AFRIKAN TÄHTI", """[color=#ffd23a][b]Tavoite[/b][/color]
Etsi Afrikan tähti (suuri timantti) maitse, meritse ja ilmateitse ja vie se Tangeriin tai Kairoon. Voittaa se, joka ehtii perille ensin.

[color=#ffd23a][b]Pelilauta[/b][/color]
Kartalla on punaisia ympyröitä (kaupunkeja ja satamia). Kussakin on sinipuolinen kiekko sokkona. Kaupunkeja yhdistää kolmenlaisia reittejä:
  • [b]Maatie[/b] (musta pisteviiva): liikut ilmaiseksi nopan silmäluvun verran pisteitä eteenpäin.
  • [b]Meritie[/b] (sininen pisteviiva): sataman välillä matka maksaa 100 £ / meritie, ja liikut nopan verran sinisiä pisteitä.
  • [b]Lentoreitti[/b] (punainen viiva): maksaa 300 £, ei noppaa, ja lennät suoraan seuraavaan kaupunkiin.

[color=#ffd23a][b]Näin pelaat[/b][/color]
Joka vuorolla ruudun alareunaan tulee valikko. [b]↑ ↓[/b] (tai W/S, A/D) siirtää valintaa, [b]E[/b] vahvistaa, ja numerot [b]1, 2, 3…[/b] valitsevat suoraan. Voit myös klikata valikon nappia tai kaupunkia kartalla (valittu kohde korostuu vihreällä renkaalla).
[b]1. Vuoron alku:[/b] [i]Heitä noppa[/i], [i]Lennä[/i] (300 £, ei noppaa, suoraan punaista viivaa pitkin) tai, jos seisot kaupungissa jossa on kiekko, [i]Osta kiekko[/i] (100 £) tai [i]Odota ja yritä avata kiekko nopalla[/i] (4–6 avaa ilmaiseksi, muuten vuoro menee).
[b]2. Liikkuminen:[/b] noppa kertoo, montako pistettä kuljet. Pisteitä pitkin nappula kulkee itsestään. Kaupungissa valitset seuraavan reitin tai [i]Pysähdy tähän[/i]. Jos meritie, lähtö satamasta maksaa 100 £ (ilman rahaa ei voi lähteä). Voit pysähtyä ennen kuin silmäluku on käytetty.
[b]3. Kiekko:[/b] kun pysähdyt kaupunkiin, kiekon voi ostaa 100 £:lla ja kääntää. Tyhjä: pois · topaasi +300 £ · smaragdi +600 £ · rubiini +1000 £ · rosvo: menetät kaikki rahat · hevosenkenkä: ei mitään, ellei tähteä ole vielä löydetty; sen jälkeen löydetty hevosenkenkä käy tähden asemesta · [b]Afrikan tähti[/b]: vie se Tangeriin tai Kairoon.
[b]4. Voitto:[/b] se, joka tuo tähden (tai hevosenkengän sen löytymisen jälkeen) ensimmäisenä Tangeriin tai Kairoon, voittaa heti.
[b]5. Erikoispaikat:[/b] Kapkaupunki: ensimmäinen perille saa 500 £ · Accra (Kultarannikko): jalokivestä saa tuplahinnan · Lagos: tyhjän kiekon ostaja jää kolmeksi vuoroksi pois (myrsky) · Pyhä Helena: pidätetään, kunnes noppa antaa 1 tai 2 · Saharan autiomaa (musta piste sinisessä renkaassa): jos vuoro päättyy siihen, beduiinit pidättävät, kunnes noppa antaa 1 tai 2.
[b]6. Rahat:[/b] aloitat 300 £:lla. Tähti kantaa kirkkaan merkin nappulan vieressä.

[color=#ffd23a][b]Vinkit[/b][/color]
• Rosvo vie kaikki rahat, joten jalokivi kannattaa heti käyttää lentoon tai merimatkaan.
• Lentoreitit säästävät aikaa, mutta kuluttavat rahaa.

[color=#ffd23a][b]Lopetus[/b][/color]
[b]F[/b] nousee pöydästä. [b]H[/b] avaa ohjeen uudestaan pelin aikana."""],
	"muistelu": ["MUISTATKO KUN", """[color=#ffd23a][b]Tavoite[/b][/color]
Nuotiolla porukka kertoo vuorotellen ysärimuistoja, ja sinä valitset, miten reagoit. Valinnat muuttavat illan tunnelmaa (−2…+2), ja tunnelma vaikuttaa seuraavaan aamuun (mainepisteet) ja pelin loppuun.

[color=#ffd23a][b]Näin pelaat[/b][/color]
[b]1. Aloita:[/b] [b]E[/b] jatkaa. Illassa on neljä tarinaa: kolme kertoo joku muu, ja neljännen kerrot itse.
[b]2. Valitse vastaus:[/b] [b]↑ ↓[/b] (tai [b]← →[/b] / A / D) siirtää valintaa, [b]E[/b] vahvistaa. Voit myös painaa [b]1[/b], [b]2[/b] tai [b]3[/b] tai klikata vastausta.
[b]3. Seuraava:[/b] kun vastaus on annettu, kerronta jatkuu [b]E[/b]:llä.
Hyvä, vitsikäs ja kannustava vastaus nostaa tunnelmaa, piikittely ja nyrpeys laskee sitä. Saman illan vaikutus on rajattu, joten toistaminen ei kasvata sitä loputtomasti.

[color=#ffd23a][b]Lopetus[/b][/color]
[b]F[/b] poistuu nuotiolta valintojen aikana, [b]W[/b] muulloin."""],
	"kortit": ["KORTTIPELIT", """[color=#ffd23a][b]Ristiseiska[/b][/color]
Pelaajat laskevat kortit riveihin seiskasta alkaen. Ristiseiskan saanut aloittaa. Seiskan tai rivin jatkon saa pelata, ja jos voi pelata, on pelattava (rivi etenee 7, 6, 8, 5 ja siitä vapaasti). Ässä tai kuningas antaa lisävuoron. Jos ei voi pelata, edellinen pelaaja antaa valitsemansa kortin. Ensimmäinen, jonka kortit loppuvat, voittaa kierroksen (0 pistettä); muut saavat yhden pisteen jokaisesta jääneestä kortista. Viikonlopun vähiten pisteitä saanut voittaa.

[color=#ffd23a][b]Tuppi[/b][/color]
Neljä pelaajaa, vastakkain istuvat ovat pari. Jokainen laittaa tarjouskortin (punainen = rami, musta = nolo). Ramissa ilmoittajan pari saa 4 pistettä jokaisesta tikistä yli kuuden, nolossa vähemmän tikkejä saanut pari saa pisteet. Maata on tunnustettava, tikin vie suurin kortti (ässä on suurin). Ensimmäinen 52 pisteeseen voittaa.

[color=#ffd23a][b]Ohjaus[/b][/color]
[b]Välilyönti[/b] jakaa kortit. [b]Klikkaa korttia[/b] pelataksesi sen. [b]A/D[/b] tai hiiren oikea nappi pohjassa katsoo pöydän ympäri. [b]E[/b] näyttää pöydän ylhäältä. [b]W[/b] nousee pöydästä, ja peli tallentuu."""],
}

signal closed

## Testit (skip_menu) eivät avaa ohjetta itsestään.
var auto := true

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
	_body.add_theme_font_size_override("normal_font_size", 17)
	_body.add_theme_font_size_override("bold_font_size", 17)
	_body.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(_body)
	_foot = Ui.label(box, "E / Enter / klikkaus: valmis   ·   ↑ ↓ vierittää   ·   H avaa ohjeen pelissä milloin tahansa", 15,
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


## Avaa ohjeen vain, jos sitä ei ole vielä näytetty tässä istunnossa; muuten kutsuu on_close heti.
func open_first(id: String, on_close := Callable()) -> void:
	if _seen.has(id) or not auto:
		if on_close.is_valid():
			on_close.call()
		return
	open(id, on_close)


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
		elif not event.echo and kc in [KEY_E, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE, KEY_H, KEY_F]:
			close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()
