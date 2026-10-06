# Oulujärven norpat

3D-peli Oulujärven rannalla Äpätissä (Vaala). Maailma on tehty oikeasta kartta-aineistosta: maaston
muodot, rantaviiva, lammet, suot, hiekkarannat, tiet ja polut, rakennukset ja noin 700 000 puuta ovat oikeilla
paikoillaan. Pelin perusmekaniikka (hahmo, kävely, juoksu, kamera, kosketusohjaimet, äänet, asetukset ja valikot)
on otettu Normipäivä Saloisissa -pelistä.

Aloituspaikka: **64.432089 N, 26.886448 E** (ETRS-TM35FIN E 494 532, N 7 145 169), mökkitontti Äpätin
rannassa. Pelissä paikasta puhutaan kaikkialla Äpättinä (maastotietokannassa niemen nimi on Saunaniemi).

## Pelaaminen

Avaa projekti Godot 4.7:llä ja käynnistä (F5). Alussa valitaan, kuka mökin porukasta olet (Santtu, Marko,
Jaakko tai Jukka) ja ajankohta; muita ohjaa tietokone.

| Näppäin | Toiminto |
|---|---|
| W / S | kävele eteen / taakse |
| A / D | käänny |
| Shift | juokse (kuluttaa kuntoa), uidessa ui nopeammin |
| Välilyönti | hyppää |
| E | nouse kumiveneeseen / veneestä; veneessä W/S soutaa, A/D kääntää; alamökissä istu lauteille, heitä löylyä, paista pyttipannua (Marko), keitä aamukahvit (Jukka), istu pöytään; halkovajassa halot syliin ja löylyhuoneessa halko kiukaaseen; ylämökin ovella päikkärit; mustikkamättäällä syö mustikoita; ylämökin edessä rantatennis (syötä ja lyö); vedessä alamökin edustalla amerikkalaisen jalkapallon heittely (heitä ja ota kiinni) |
| A / D (minipelissä) | pöydässä ja lauteilla katse kääntyy (myös hiiren oikea nappi pohjassa korttipöydässä) |
| Q | kätköllä (saunan takana tai rannan rinteessä) huikka viinaa (E = olut); huussin ovella kakkonen (E = ykkönen) |
| F | lopettaa huussin minipelin, rinteeseen virtsaamisen, rantatenniksen tai pallon heittelyn |
| Enter | keskustelu: kirjoita viesti, Enter lähettää ja Esc peruu; viesti näkyy puhekuplana hahmon yläpuolella |
| T (pohjassa) | kelaa aikaa 20-kertaisesti |
| M | kartta: rulla zoomaa, klikkaus asettaa kohteen kompassiin ja tutkaan |
| V | FPS / kolmas persoona |
| R | takaisin aloituspaikalle |
| Esc | taukovalikko ja asetukset |

Vedessä kahlataan (hidastaa syvyyden mukaan), ja yli 1,35 m syvässä uidaan. HUD näyttää lähimmän paikannimen,
sijainnin koordinaatteina, maaston pinnan, korkeuden merenpinnasta ja vedessä syvyyden.

## Alamökki: sauna, keittiö ja kätkö

Alamökin ovet ovat terassin puoleisella pitkällä sivulla katon alla (valokuva `20210709_171210.jpg`). Pelissä
alamökki on pidennetty törmään päin (9,1 m), jotta koko porukka mahtuu sisälle.

Sisällä on oma näkymänsä: kamera siirtyy huoneen yläkulmaan vastakkaiselle puolelle kuin pelaaja ja seuraa
pelaajaa sieltä, joten koko huone näkyy eikä kamera painu ahtaassa huoneessa pelaajan selkään. Ulos
tultaessa palataan tavalliseen kameraan. V vaihtaa sisälläkin FPS-näkymään.

- **Vasen ovi, keittiö:** keittiö oikealla, jääkaappi takanurkassa ja terassin pöydän kokoinen pöytä (1,5 × 0,8 m) penkkeineen järven puoleisen ikkunan edessä.
  - Vain Marko osaa kokata: hellalla paistetaan pyttipannua. Perunakuutiot pannulle, sipuli ja makkara joukkoon, kun perunat ovat kullanruskeita, ja annos lautaselle kananmunan ja punajuuren kanssa; liian kauan pannulla ja pyttipannu palaa.
  - Jukan erikoistaito on keittää aamukahvit liedellä (`scripts/kahvi.gd`): E nostaa pannun liedelle, kun vesi kiehuu, E lisää purut, ja kun kahvi kiehahtaa ja vaahto nousee, E nostaa pannun pois ennen kuin se kiehuu yli. Onnistunut pannu antaa neljä kuppia pöytään.
  - Pöytään istuva syö annoksen, jolloin kunto palaa täyteen, ja juo kupin kahvia, jolloin humala laskee. Hellaa käyttää kerrallaan yksi.
  - Pöydässä pelataan ristiseiskaa (`scripts/ristiseiska.gd`) kaikki neljä yhdessä: pöydässä istuvat ihmiset pelaavat itse, muiden puolesta tietokone, ja tietokoneen hahmot kävelevät pöytään.
  - Kortit pelataan pöydälle: rivit näkyvät pöydän keskellä ja kunkin käsi kuvapuoli alaspäin hänen edessään, joten muita pelaajia voi katsella pelatessa. Oma käsi on ruudun alareunassa.
  - Säännöt: ristiseiskan saanut aloittaa; seiskan tai rivin jatkon saa pelata, ja jos voi pelata, on pelattava. Ässä tai kuningas antaa lisävuoron. Jos ei voi pelata, edellinen pelaaja antaa valitsemansa kortin.
- **Oikea ovi, sauna:** pelkkä löylyhuone. Ovi on sisältä katsoen vasemmassa nurkassa ja kiuas heti oven oikealla puolella. Lauteet ovat perällä, ja niille mahtuu juuri neljä. Saunan ovelle kuljetaan katon alle jatketulla terassilla; räystäät ovat lyhyet eikä niiden alla ole tolppia.
  - **Lämmitys haloilla:** halot haetaan syliin halkovajasta (itäterassilla, E, neljä kerrallaan) ja lisätään kiukaaseen löylyhuoneessa (E kiukaan vieressä). Halko palaa 2,5 min, ja kiukaaseen mahtuu neljä. Tulen palaessa sauna lämpenee (piipusta nousee savua, luukusta hehkuu), ja sammuneena se jäähtyy; kylmässä saunassa löyly ei riitä hyviin löylyihin. Kun tuli hiipuu, saunoja muistutetaan lisäämään haloja, ja tietokoneen hahmot käyvät lämmittämässä. Moninpelissä tulen tila lähetetään muille.
  - Lauteille istutaan lähimmälle vapaalle paikalle, joten jos joku jo saunoo, viereen voi istua.
  - Saunominen on minipeli: lauteilla E heittää löylyä, ja kuumuus pitää pitää hyvien löylyjen alueella.
  - Liika löyly ajaa järveen. Pulahdus järveen saunan jälkeen antaa lisäpisteet.
  - Moninpelissä löyly tuntuu kaikilla lauteilla istujilla.
- **Kätkö saunan takana:** piilossa havujen alla rinteessä alamökin oikealla puolella (saunan ovea katsottaessa), saunan takakulun muurin takana, on ehtymätön olut- ja viinakätkö (E olut, Q viina). Kompassin kätköosoitin näyttää lähimmän kätkön.
  - Mitä enemmän juo, sitä vaikeampi hahmoa on ohjata: ohjaus heittelee, kuva kahdentuu ja hahmo horjuu sivuttain. Raskaassa humalassa ohjaus kääntyy välillä väärin päin.
  - 3 promillesta ylöspäin kävely ei enää onnistu, vaan konttaillaan. 3,6 promillesta ylöspäin sammutaan, kunnes humala laskee.
  - Humala haihtuu noin promillen neljässä minuutissa.

Hahmot eivät mene toistensa sisään: istuvaankaan ei voi kävellä, ja pöydästä tai lauteilta noustaan vapaaseen
kohtaan.

Testit: `tools/testit/alamokkitesti.gd`, `tools/testit/liiketesti.gd`, `tools/testit/ristiseiskatesti.gd` ja
`tools/testit/arkitesti.gd` (päikkärit ja klo 16, välianimaatio, kahvit, mustikat, kätköosoitin ja saunan
lämmitys haloilla).

## Huussi ja pitkospuut

Huussi on saunan itäpuolella aivan rinteen reunassa, takaseinä rinnettä vasten. Saunan ovea ulkoa katsottaessa
kulku huussille lähtee alamökin oikealta puolelta: saunan oven edustalta takapäädyn halkopinon ohi saunan taakse,
ja takakulun päästä pitkospuut nousevat kaivannon muurin yli ja kulkevat rinteen reunaa pitkin huussin ovelle.
Alamökin vasemmalla (järven) puolella oleva etu- ja itäterassi on suljettu takaa: sieltä ei ole kulkua huussille
eikä saunan taakse.

- **Huussi** (`scripts/wc_game.gd`, Normipäivä Saloisissa -pelin vessaminipeli huussiversiona): ovella E on ykkönen ja Q kakkonen.
  - Ykkösessä suihku pidetään reiässä (WASD tai hiiri); tähtäin vaeltaa, humalassa enemmän.
  - Kakkosessa ponnistetaan vihreällä (E / välilyönti) kolme kertaa ja revitään paperia (E arkki, välilyönti valmis).
  - Sotkusta Santtu huomauttaa.
- **Rinteeseen virtsaaminen** (`scripts/rinnepissa.gd`): pitkospuiden alussa ennen huussia E aloittaa.
  - W/S nostaa ja laskee kaarta, A/D kääntää. Suihku lentää heittoliikkeenä ja osuu maastoon, ja märät läikät jäävät maahan.
  - Kaaren pituus ja hahmon ennätys näkyvät ruudulla.
  - **Markon erikoiskyky:** suuri kaari 5 metrin päähän; muilta onnistuu noin 2 m. Humala heiluttaa suihkua.
  - **Mustikat** (`scripts/mustikat.gd`): metsässä mökin ympärillä on mustikkamättäitä. Mättään vieressä E syö kourallisen, ja jokainen kourallinen (enintään 10) pidentää kaarta. Muiden kaari kasvaa noin 3,4 metriin, mutta Markon kaareen ei ylletä. Vaikutus hiipuu hiljalleen, ja syöty mätäs kasvaa marjat takaisin muutamassa minuutissa.
  - Moninpelissä suihku näkyy kaikilla: kulma ja lähtönopeus lähetetään muille, ja kaari lasketaan jokaisella koneella hahmon paikasta.

Tietokoneen hahmot käyvät huussissa samaa reittiä saunan takaa. Testi: `tools/testit/huussitesti.gd`.

## Hiekkaranta ja viinakätkö

Äpätin itärannan hiekkarannalle (`scripts/ranta.gd`) ei ole merkittyä polkua. Ylämökiltä kuljetaan noin 200 m
metsän läpi itä-kaakkoon ja Äpätintien yli törmän reunalle, ja sieltä vinosti rinnettä alas. Kätköosoitin
(kompassin keltainen merkki) näyttää lähimmän viinakätkön suunnan ja matkan: saunan takana olevan tai rannan.

- **Viinakätkö** (64.431214 N, 26.889959 E) on rinteessä, kun laskeudutaan rannalle: lahonnut
  puulaatikko havujen ja kivien alla, viinapulloja ja oluita. Ehtymätön kuten saunan kätkö (E olut, Q viina).
- **Hiekkaranta** törmän juurella: kuiva ranta on hiekkaa, rannassa ajopuu ja kiviä. Pohja on hiekkaa ja syvenee
  loivasti: ensin kahlataan, ja noin 18 m rannasta pääsee uimaan.

Testi: `tools/testit/rantatesti.gd` (`--headless --fixed-fps 60`), kuvakaappaukset `tools/testit/ranta_kuvat.gd`.

## Rantatennis ylämökin edessä

Ylämökin maanpuoleisella sivulla on tasainen ruohokenttä (14 × 9 m, valkoiset rajat), jossa pelataan
Spartan-rantatennistä isoilla puumailoilla (`scripts/rantatennis.gd`). Peliä ei pelata vastakkain, vaan koko
porukka yrittää yhdessä pitää pallon ilmassa: lyönnit lasketaan, kunnes pallo osuu maahan. Ennätys on yhteinen ja
näkyy kentän laidan taulussa. Uusi ennätys tarkoittaa, että kaikki voittivat; muuten kaikki hävisivät.

- Kentällä E aloittaa: tietokoneen hahmot tulevat paikoilleen mailat kädessä (pihalta portaita ylös).
- E syöttää ja lyö. Pallo lähtee sille, jota kohti hahmo katsoo. Lyönti onnistuu, kun pallo on mailan
  ulottuvilla sopivalla korkeudella; hyvällä korkeudella pallo menee tarkemmin. Keltainen rengas näyttää, mihin
  sinulle tuleva pallo putoaa.
- Tietokoneen hahmot juoksevat pallon alle ja lyövät useimmiten. Humala heikentää kaikkien tarkkuutta.
- F tai kentältä poistuminen lopettaa pelin.
- Moninpelissä kaikki pelaavat samaa peliä samalla pallolla: kaverit liittyvät kentällä E:llä, ja pallo
  kulkee koneelta toiselle. Host pitää kirjaa pelaajista ja ohjaa tietokoneen hahmoja. Jokainen lyönti
  lähetetään kaikille, ja kukin kone laskee saman lentoradan; pallon putoamisen ratkaisee sen kone, jolle pallo
  oli menossa. Lyöntimäärä ja ennätys ovat kaikilla samat.

Testit: `tools/testit/tennistesti.gd` (`--headless --fixed-fps 60`) ja kahden koneen
`tools/testit/tennismoninpeli.gd` (ohjeet tiedoston alussa), kuvakaappaukset `tools/testit/tennis_kuvat.gd`.

### Amerikkalaisen jalkapallon heittely vedessä

Samalla mekaniikalla (`scripts/pallopeli.gd`, yhteinen pohja rantatenniksen kanssa) heitellään amerikkalaista
jalkapalloa vedessä alamökin edustalla, 20-30 m rannasta, jossa vettä on 0,7-1 m (`scripts/amerikanpallo.gd`).
Vedessä E aloittaa, ja tietokoneen hahmot kahlaavat paikoilleen. E heittää ja ottaa kiinni; pallo lentää
spiraalina, ja heitot lasketaan, kunnes pallo putoaa veteen ja jää kellumaan. Ennätys on oma ja yhteinen, ja
moninpelissä pallo kulkee koneelta toiselle kuten tenniksessä. F lopettaa. Testi: `tools/testit/heittelytesti.gd`.

## Moninpeli

Valikosta **Moninpeli → Luo uusi peli** avaa huoneen ja näyttää sen nelikirjaimisen koodin; kaverit liittyvät
koodilla (**Liity peliin**), selaimessa tai työpöytäversiossa. Kukin valitsee oman mökkiläisensä, ja vapaita
hahmoja ohjaa huoneen luojan (hostin) tietokone. Host pitää myös kelloa; T kelaa aikaa kaikilta. Jos host
lähtee, seuraava pelaaja jatkaa hostina. Keskusteluviestit (Enter) näkyvät kaikille puhekuplina ja
keskusteluhistoriassa.

Välityspalvelin on `server/`-hakemistossa: Cloudflare Worker ja yksi Durable Object per huone
(`wss://norpat.santtu-seppane.workers.dev/huone/<KOODI>`). Pelaajat lähettävät ohjaamiensa hahmojen ja
kumiveneen tilan 12 kertaa sekunnissa (`scripts/moninpeli.gd`, `scripts/net.gd`); maailma rakennetaan
jokaisella koneella itse.

```sh
cd server && npm install
npx wrangler dev        # paikallinen palvelin, peliin: godot --path . -- --palvelin=ws://localhost:8787
npx wrangler deploy     # julkaisu Cloudflareen
node test.mjs           # protokollatesti (NORPAT_URL=wss://.../huone/X tuotantoa vastaan)
```

Kahden koneen testi: `tools/testit/moninpelitesti.gd` (ohjeet tiedoston alussa).

## Mökki

Aloituspaikan mökkipiha on mallinnettu valokuvista ja maastotietokannan pohjapiirroksista (`scripts/mokki.gd`):
rantasauna eli alamökki (kuisti, piippu, lyhdyt, halkovaja), iso terassi grillikatoksineen ja telttoineen (pöytä
penkkeineen teltan keskellä, teltta saunan katon ulkopuolella),
etuterassi, kelluva laituri tikkaineen, kulku saunan takaa, pitkospuut ja huussi rinteen reunassa, ylämökki törmän
päällä (harja kohtisuoraan järveä kohti, ovi metsän puoleisessa päädyssä, aurinkopaneelit, antenni, säleikkö,
kaiteeton terassi ja oven edessä tasanne portaineen) ja jyrkät portaat (38°, 22 askelmaa) törmään. Terassin kohdalta maastoa kaivetaan, ja kaivannon
reunat peitetään alkuperäisen maanpinnan mukaisella kivimuurilla ja sammalella. Rannassa on keltainen
kumivene, jolla voi soutaa.

Päikkärit otetaan kello neljän aikoihin: porukka alkaa jutella, että nyt päikkäreille, ja lähtee ylämökkiin
nukkumaan noin tunniksi; pelaajalle tulee ilmoitus. Ylämökin ovella E vie nukkumaan: välianimaatiossa mökin
sisältä kolme norppaa nukkuu sängyissään peittojen alla kuorsaten (`scripts/paikkarit.gd`), ja herätessä kunto on
täynnä ja humala laskenut. Jukka ei nuku päikkäreitä, vaan keittää sillä aikaa kahvit alamökin liedellä.

Porukka (`scripts/porukka.gd`, `scripts/ai.gd`): tietokoneen ohjaamat hahmot istuvat pöydän ääressä ja
juttelevat, grillaavat, käyvät saunassa ja uimassa, nukkuvat päikkärit ylämökissä (paitsi Jukka, joka keittää
kahvit) ja käyvät huussissa, ja kerääntyvät laiturille ja etuterassille katsomaan auringonlaskua.

Aurinko (`scripts/sun.gd`) lasketaan NOAA:n algoritmilla aloituspaikalle pelin päivämäärän ja kellonajan
mukaan (Suomen aika, kesäaika huomioiden), ilmakehän taittuminen mukana. Pelivuorokausi kestää 24 minuuttia ja
päivä vaihtuu keskiyöllä, joten aurinko laskee joka ilta oikeaan aikaan oikeaan suuntaan. Esimerkiksi 7.7.
aurinko koskettaa horisonttia klo 23.24 suunnassa 334° (luode-pohjoinen), kuten saman illan valokuvassa.
Auringonpaiste on mallinnettu ohuella tilavuususvalla (keski- ja korkea grafiikka, Forward+): latvusten välistä
paistava aurinko näkyy ilmassa valokiiloina, ja ilta-aurinko hehkuu kultaisena.

Metsä on harvennettu puoleen laserkeilauksen puustosta (`scripts/trees.gd`, `THIN`). Soratiet (Äpätintie)
on piirretty omalla varjostimella (`shaders/road.gdshader`): harmaanruskeaa mursketta ja pikkukiviä
kohokuvioineen, renkaiden tiivistämät tummemmat urat, kupera ajorata ja ruohoiset pientareet; ajourilla
ruohokaista urien välissä.

## Kartta

Kävelyalue on 2 × 2 km aloituspaikan ympärillä (tarkka maasto, 2 m ruutu). Sen ympärillä näkyy 10 × 10 km
kaukomaasto (16 m ruutu, metsä mukana), ja järvenselkä jatkuu horisonttiin.

| Mitä | Lähde |
|---|---|
| Maanpinnan korkeus | MML korkeusmalli 2 m (lehdet Q4444F, Q4444H, R4333E, R4333G) |
| Järvet, lammet, suot, hietikot, kalliot, pellot, hakkuuaukeat, kivet, vesikivet, matalikot, tervahaudat, linjataulut, tiet, polut, rakennukset tyyppeineen, paikannimet | MML maastotietokanta (Q4444R, R4333R) |
| Puiden paikat, pituudet ja latvusten leveydet, rakennusten korkeudet | MML laserkeilaus 2011 (Q4444F4, Q4444H2, R4333E3, R4333G1) |
| Puulajit (mänty, kuusi, koivu, haapa ja muut lehtipuut) sekä metsä laseralueen ulkopuolella | Luke, monilähteinen VMI 2023 (16 m) |
| Veneenlaskupaikat | OpenStreetMap |

Valtapuut ovat laserkeilauksen latvusmallin paikallisia maksimeja. Vuoden 2011 keilaus (n. 0,5 pistettä/m²)
erottaa vain valtapuut, joten latvuston aukkoihin on lisätty puita vain sinne, missä laser näki latvustoa,
latvusmallin pituuksilla. Lajit arvotaan kunkin 16 m solun VMI-tilavuusosuuksista.

Oulujärven pinta on 122,81 m (N2000) korkeusmallin tasoitetusta vedenpinnasta, ja pelin korkeudet ovat metrejä
järven pinnasta. Järven pohjan muoto on arvio: syvyysaineistoa ei ole avoimena (MML poisti syvyyskäyrät
avoimesta datasta 2012, eikä Traficomin syvyysalueita ole avoimessa rajapinnassa). Pohja syvenee rannasta
poispäin, ja maastotietokannan matalikot ja vesikivet ovat mukana.

Data tehdään uudelleen komennolla `tools/kartta/bake.py` (ks. [tools/kartta/LUEMINUT.md](tools/kartta/LUEMINUT.md)).

## Rakenne

| Tiedosto | Tehtävä |
|---|---|
| `scripts/main.gd` | pelin juuri: ympäristö, maailma, pelaaja, HUD, kartta, valikot |
| `scripts/world.gd` | maasto, vesi, tiet, rakennukset ja pienkohteet kartta-aineistosta |
| `scripts/terrain.gd` | korkeudet ja pintaluokat (`h(x, z)`, `surface(x, z)`) |
| `scripts/trees.gd` | metsä: kolme tarkkuustasoa, paikat varjostimessa datatekstuurista, rungot törmäävät |
| `scripts/on_foot.gd` | pelaaja: kävely, juoksu, hyppy, kahlaus ja uinti |
| `scripts/minimap.gd`, `scripts/map_view.gd`, `scripts/compass.gd` | tutka, kartta (M) ja kompassi |
| `scripts/ambience.gd` | ympäristöäänet maaston mukaan |
| `scripts/character.gd`, `looks.gd`, `cam_ctl.gd`, `settings.gd`, `menu.gd`, `audio.gd`, `touch_controls.gd`, `build.gd`, `foliage.gd` | Normipäivästä: hahmot, kamera, asetukset, valikot, äänet, kosketusohjaimet, apurit |
| `tools/kartta/bake.py` | kartta-aineisto → `assets/map/` |
| `scripts/mokki.gd`, `shaders/mokki.gdshader` | mökkipiha: rakennukset, terassit, portaat, laituri, maaston kaivu, reittipisteet |
| `scripts/sun.gd`, `shaders/sky.gdshader` | aurinko ja kello, taivas, iltarusko ja tähdet |
| `scripts/kumivene.gd` | kumivene ja soutaminen |
| `scripts/ranta.gd` | hiekkaranta ja viinakätkö rannan rinteessä |
| `scripts/kahvi.gd`, `scripts/mustikat.gd` | Jukan aamukahvit liedellä; mustikkamättäät, jotka pidentävät virtsauskaarta |
| `scripts/pallopeli.gd`, `scripts/rantatennis.gd`, `scripts/amerikanpallo.gd` | yhteiset pallopelit: pohja (osallistujat, moninpeli, lentorata, tekoäly, ennätys), rantatennis ylämökin edessä ja amerikkalaisen jalkapallon heittely vedessä |
| `scripts/paikkarit.gd` | päikkäreiden välianimaatio: norpat nukkumassa ylämökissä |
| `scripts/wc_game.gd`, `scripts/rinnepissa.gd` | huussin minipeli ja rinteeseen virtsaaminen |
| `scripts/porukka.gd`, `scripts/ai.gd` | hahmot ja tietokoneen ohjaus |
| `tools/testit/savutesti.gd`, `kuvat.gd` | savutesti (headless) ja kuvakaappaukset |
| `tools/testit/mokkitesti.gd`, `mokki_kuvat.gd` | mökin testi (`--headless --fixed-fps 60`) ja kuvakaappaukset valokuvien kuvakulmista |

## Tekijänoikeudet

- Korkeusmalli, maastotietokanta ja laserkeilausaineisto © Maanmittauslaitos (CC BY 4.0)
- MVMI-kartta-aineisto 2023 © Luonnonvarakeskus (CC BY 4.0)
- © OpenStreetMap-tekijät (ODbL)
- Hahmot ja animaatiot: Quaternius (CC0); äänet: OpenGameArt ja Kenney (CC0), ks. `assets/sounds/LICENSE.md`
