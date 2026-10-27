# Oulujärven norpat: traileri

Traileri tehdään pelikuvasta Godotin Movie Maker -tilalla (kiinteä 30 fps, jokainen ruutu täydellä laadulla) ja
kappale liitetään ffmpegillä. Kappale on tehty Sunolla: sanat ja tyylikehote ovat `docs/traileri/biisi.md`.

## Sisältö

1. **Saapuminen** (`scripts/saapuminen.gd`, sama kohtaus näytetään pelissä uuden pelin alussa): torstai-iltana norpat ajavat
   mökin pihaan (sauna on kylmä), nostavat kaljakorit takakontista, kantavat ne ylämökin portaita terassille, Jukka panee
   saunan lämpiämään ja kaikki heittävät vaatteet pois uikkareilleen. Kestää n. 50 s; pelissä sen voi ohittaa E:llä tai välilyönnillä.
2. **Mökin minipelit** (`leikkaus.gd`): Spartan pinkiponki, amerikanpallo, pyttipannun paisto, virtsaaminen rinteeseen, ristiseiska,
   päikkärit, tutkimusmatka ja viinakätkön etsintä metsän takaiselta hiekkarannalta, nuotiolla istuskelu
   ja vihainen työpuhelu. Pelin tietokonehahmot ja minipelit toimivat oikeasti, joten kuva seuraa pelin muutoksia.
3. **Oodi Oulujärvelle**: neljä norppaa laulaa terassilla oodin (`oodi.gd`) auringon laskiessa; kamera kuvaa heitä selän takaa auringon laskiessa horisonttiin. Laulun jälkeen kuva häipyy mustaan ja ruutuun tulee teksti "Äpätin Mökkiseikkailu - pelattavissa pian" (`CARD_TEXT` traileri.gd:ssä).

Ääninä on vain biisi: videon omaa ääniraitaa (puhe, pelin äänet) ei käytetä.

## Vaiheet

1. Kappale on `assets/music/oulujarven_norpat.mp3` (Suno, 189 s). Se soi alusta ja häipyy, kun oodi alkaa.
2. Renderöi video:

   ```
   godot --path . --write-movie ~/traileri/traileri.avi --fixed-fps 30 --resolution 1280x720 \
     -s tools/traileri/traileri.gd
   ```

   Peli-ikkuna aukeaa, eikä sitä saa sulkea tai peittää (macOS lopettaa muuten piirtämisen). Näyttöohjain tarvitaan
   (ei `--headless`). Lopuksi tulostuu kohtausten aikamerkit.
3. Liitä kappale: `tools/traileri/kokoa.sh ~/traileri/traileri.avi assets/music/oulujarven_norpat.mp3 ~/traileri/traileri.mp4`
   ja kopioi tulos `docs/traileri/oulujarven_norpat_traileri.mp4`:ksi.

## Esikatselu

- Kuva sekunnin välein PNG:nä: lisää `--kuvat=<kansio>`. Vain alku: `--loppu=<s>`. Aloitus kohtauksesta n: `--alku=<n>` (0 = saapuminen).
- Saapumiskohtauksen kuvat: `godot --path . -s tools/testit/saapuminen_kuvat.gd -- <kansio>`.

## Leikkaus

`tools/traileri/leikkaus.gd`: kohtaukset järjestyksessä. Kohtaus on sanakirja: `dur` (kesto s), `t` (kellonaika [kk, pv, h, min]),
`txt` (otsikko), `setup`/`tick`/`done` (alustus, joka ruutu, lopetus), `cam` (kameran paikka ja katse kohtauksen etenemisen k
mukaan) ja `ui: true`, jos minipelin ruutu peittää kuvan. Viimeinen kohtaus päättyy oodin loppuun (`until`).
