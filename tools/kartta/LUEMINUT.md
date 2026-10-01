# Kartta-aineisto: bake.py

`bake.py` hakee avoimen lähdeaineiston, yhdistää sen ja kirjoittaa pelin datan kansioon `assets/map/`.

## Ajo

```sh
python3 -m venv venv
venv/bin/pip install -r tools/kartta/requirements.txt
venv/bin/python tools/kartta/bake.py --cache ~/kartta-cache
```

Ensimmäisellä ajolla lähdeaineisto (n. 120 Mt) ladataan välimuistiin; seuraavat ajot vievät alle minuutin.
VMI-rastereista (1–2 Gt/teema) luetaan HTTP-aluepyynnöillä vain alueen laatat.

## Kehys

- Origo: ETRS-TM35FIN E 494 531, N 7 145 169: korkeusmallin pikselin keskipiste, 0,9 m aloituspisteestä
  (64.432089 N, 26.886448 E), joten tarkan ruudukon pisteet ovat täsmälleen korkeusmallin pikseleissä.
- x itään, z etelään, y ylös metreinä Oulujärven pinnasta (122,81 m N2000).
- Kolmiointi lävistäjällä (1,0)–(0,1) kuten Godotin HeightMapShape3D (Jolt): `terrain.gd`, `terrain.gdshader`
  ja puiden maanpinta laskevat korkeuden samalla tavalla, joten näkyvä pinta = törmäyspinta.

## Lähteet

| Aineisto | Osoite | Lisenssi |
|---|---|---|
| Korkeusmalli 2 m | `https://kartat.kapsi.fi/files/korkeusmalli/hila_2m/etrs-tm35fin-n2000/<R4>/<R43>/<lehti>.tif` | MML, CC BY 4.0 |
| Maastotietokanta (shp) | `https://kartat.kapsi.fi/files/maastotietokanta/kaikki/etrs89/shp/<Q4>/<Q44>/<lehti>.shp.zip` | MML, CC BY 4.0 |
| Laserkeilaus 2011 (laz) | `https://www.nic.funet.fi/index/geodata/mml/laserkeilaus/2008_latest/2011/<Q444>/1/<lehti>.laz` | MML, CC BY 4.0 |
| MVMI 2023 (16 m) | `https://www.nic.funet.fi/index/geodata/luke/vmi/2023/<teema>_vmi1x_1923.tif` | Luke, CC BY 4.0 |
| OpenStreetMap | `https://api.openstreetmap.org/api/0.6/map?bbox=26.855,64.420,26.918,64.445` | ODbL |

Lehtijako: 6 × 6 km korkeusmallilehdet Q4444F (E 488–494 km, N 7140–7146 km), Q4444H (E 494–500, N 7140–7146),
R4333E (E 488–494, N 7146–7152) ja R4333G (E 494–500, N 7146–7152). Laserlehdet ovat 3 × 3 km neljänneksiä
(1 lounas, 2 luode, 3 kaakko, 4 koillinen).

Ei avoimena: järven syvyydet (MML:n syvyyskäyrät poistettiin avoimesta datasta 2012, Traficomin syvyysalueet
eivät ole avoimessa WFS:ssä). Pohja on arvio: syvyys kasvaa etäisyyden mukaan rannasta (enintään 9 m), ja
matalikot (MTK 38700) ja vesikivet (38511) on painettu pinnan lähelle.

## Tulosteet (`assets/map/`)

| Tiedosto | Sisältö |
|---|---|
| `maasto.bin` | `ONM2`; lähiruudukko (1001², 2 m, ±1000 m) ja kaukoruudukko (641², 16 m, ±5120 m): kummastakin `u32 n, f32 askel, f32 puolikas, f32[n²] korkeus, u8[(n−1)²] pintaluokka` |
| `puut.bin` | `ONP2`; puut järjestyksessä kaukolohko (512 m) → laji → lähilohko (128 m), lohkotaulukot (alku, määrä) ja kaksi datatekstuuria: RGBAF (x, y, z, pituus) ja RGBA8 (latvuksen säde × 40, laji, kaksi satunnaislukua) |
| `kohteet.json` | rakennukset (tyyppi, laserkorkeus, pohja), tiet ja polut (luokka, nimi, päällyste), lammet (pinta, reuna), kivet, vesikivet, matalikot, tervahaudat, linjataulut, veneenlaskupaikat, puomit, paikannimet, metatiedot |
| `kartta_lahi.png`, `kartta_koko.png` | karttakuvat tutkaan ja M-karttaan (1 m/px lähialue, 8 m/px koko alue) |

Pintaluokat: 0 metsä, 1 järvi, 2 hiekka, 3 kallio/kivikko, 4 suo, 5 pelto, 6 piha, 7 tie, 8 polku/ajopolku,
9 hakkuuaukea, 10 täyttömaa, 11 lampi. Puulajit: 0 mänty, 1 kuusi, 2 koivu, 3 haapa/muu lehtipuu, 4 pensas.
