# Oulujärven norpat

3D-peli Oulujärven rannalla Äpätinniemessä (Vaala). Maailma on tehty oikeasta kartta-aineistosta: maaston
muodot, rantaviiva, lammet, suot, hiekkarannat, tiet ja polut, rakennukset ja noin 700 000 puuta ovat oikeilla
paikoillaan. Pelin perusmekaniikka (hahmo, kävely, juoksu, kamera, kosketusohjaimet, äänet, asetukset ja valikot)
on otettu Normipäivä Saloisissa -pelistä.

Aloituspaikka: **64.432089 N, 26.886448 E** (ETRS-TM35FIN E 494 532, N 7 145 169), mökkitontti Saunaniemen
rannassa Äpätinniemen kärjessä.

## Pelaaminen

Avaa projekti Godot 4.7:llä ja käynnistä (F5). Alussa valitaan, kuka mökin porukasta olet (Santtu, Marko,
Jaakko tai Jukka) ja ajankohta; muita ohjaa tietokone.

| Näppäin | Toiminto |
|---|---|
| W / S | kävele eteen / taakse |
| A / D | käänny |
| Shift | juokse (kuluttaa kuntoa), uidessa ui nopeammin |
| Välilyönti | hyppää |
| E | nouse kumiveneeseen / veneestä; veneessä W/S soutaa, A/D kääntää; alamökissä istu lauteille, heitä löylyä, paista lettuja, istu pöytään |
| Q | kätköllä saunan takana huikka viinaa (E = olut) |
| T (pohjassa) | kelaa aikaa 20-kertaisesti |
| M | kartta: rulla zoomaa, klikkaus asettaa kohteen kompassiin ja tutkaan |
| V | FPS / kolmas persoona |
| R | takaisin aloituspaikalle |
| Esc | taukovalikko ja asetukset |

Vedessä kahlataan (hidastaa syvyyden mukaan), ja yli 1,35 m syvässä uidaan. HUD näyttää lähimmän paikannimen,
sijainnin koordinaatteina, maaston pinnan, korkeuden merenpinnasta ja vedessä syvyyden.

## Alamökki: sauna, keittiö ja kätkö

Alamökin ovet ovat terassin puoleisella pitkällä sivulla katon alla (valokuva `20210709_171210.jpg`):

- **Vasen ovi, keittiö:** pieni keittiö oikealla ja pöytä neljälle järven puoleisen ikkunan edessä.
  - Vain Marko osaa kokata: hellalla paistetaan lettuja. Kaada taikina, käännä kullanruskeana ja nosta lautaselle; liian kauan pannulla ja lettu palaa.
  - Pöytään istuva syö letun, jolloin kunto palaa täyteen.
  - Pöydässä pelataan ristiseiskaa (`scripts/ristiseiska.gd`) kaikki neljä yhdessä: pöydässä istuvat ihmiset pelaavat itse, muiden puolesta tietokone, ja tietokoneen hahmot kävelevät pöytään.
  - Säännöt: ristiseiskan saanut aloittaa; seiskan tai rivin jatkon saa pelata, ja jos voi pelata, on pelattava. Ässä tai kuningas antaa lisävuoron. Jos ei voi pelata, edellinen pelaaja antaa valitsemansa kortin.
- **Oikea ovi, sauna:** pukuhuone ja löylyhuone, jossa lauteet ja kiuas.
  - Saunominen on minipeli: lauteilla E heittää löylyä, ja kuumuus pitää pitää hyvien löylyjen alueella.
  - Liika löyly ajaa järveen. Pulahdus järveen saunan jälkeen antaa lisäpisteet.
  - Moninpelissä löyly tuntuu kaikilla lauteilla istujilla.
- **Kätkö saunan takana:** törmässä on ehtymätön olut- ja viinakätkö (E olut, Q viina).
  - Mitä enemmän juo, sitä vaikeampi hahmoa on ohjata: ohjaus heittelee, kuva kahdentuu ja hahmo horjuu sivuttain. Raskaassa humalassa ohjaus kääntyy välillä väärin päin.
  - 3 promillesta ylöspäin kävely ei enää onnistu, vaan konttaillaan. 3,6 promillesta ylöspäin sammutaan, kunnes humala laskee.
  - Humala haihtuu noin promillen neljässä minuutissa.

Testit: `tools/testit/alamokkitesti.gd` ja `tools/testit/ristiseiskatesti.gd`.

## Moninpeli

Valikosta **Moninpeli → Luo uusi peli** avaa huoneen ja näyttää sen nelikirjaimisen koodin; kaverit liittyvät
koodilla (**Liity peliin**), selaimessa tai työpöytäversiossa. Kukin valitsee oman mökkiläisensä, ja vapaita
hahmoja ohjaa huoneen luojan (hostin) tietokone. Host pitää myös kelloa; T kelaa aikaa kaikilta. Jos host
lähtee, seuraava pelaaja jatkaa hostina.

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
rantasauna eli alamökki (kuisti, piippu, lyhdyt, halkovaja), iso terassi grillikatoksineen ja telttoineen,
etuterassi, kelluva laituri tikkaineen, huussi, ylämökki törmän päällä (aurinkopaneelit, antenni, säleikkö,
terassi) ja jyrkät portaat (38°, 22 askelmaa) törmään. Terassin kohdalta maastoa kaivetaan, ja kaivannon
reunat peitetään alkuperäisen maanpinnan mukaisella kivimuurilla ja sammalella. Rannassa on keltainen
kumivene, jolla voi soutaa.

Porukka (`scripts/porukka.gd`, `scripts/ai.gd`): tietokoneen ohjaamat hahmot istuvat pöydän ääressä ja
juttelevat, grillaavat, käyvät saunassa ja uimassa, ylämökillä ja huussissa, ja kerääntyvät laiturille ja
etuterassille katsomaan auringonlaskua.

Aurinko (`scripts/sun.gd`) lasketaan NOAA:n algoritmilla aloituspaikalle pelin päivämäärän ja kellonajan
mukaan (Suomen aika, kesäaika huomioiden), ilmakehän taittuminen mukana. Pelivuorokausi kestää 24 minuuttia ja
päivä vaihtuu keskiyöllä, joten aurinko laskee joka ilta oikeaan aikaan oikeaan suuntaan. Esimerkiksi 7.7.
aurinko koskettaa horisonttia klo 23.24 suunnassa 334° (luode-pohjoinen), kuten saman illan valokuvassa.

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
| `scripts/porukka.gd`, `scripts/ai.gd` | hahmot ja tietokoneen ohjaus |
| `tools/testit/savutesti.gd`, `kuvat.gd` | savutesti (headless) ja kuvakaappaukset |
| `tools/testit/mokkitesti.gd`, `mokki_kuvat.gd` | mökin testi (`--headless --fixed-fps 60`) ja kuvakaappaukset valokuvien kuvakulmista |

## Tekijänoikeudet

- Korkeusmalli, maastotietokanta ja laserkeilausaineisto © Maanmittauslaitos (CC BY 4.0)
- MVMI-kartta-aineisto 2023 © Luonnonvarakeskus (CC BY 4.0)
- © OpenStreetMap-tekijät (ODbL)
- Hahmot ja animaatiot: Quaternius (CC0); äänet: OpenGameArt ja Kenney (CC0), ks. `assets/sounds/LICENSE.md`
