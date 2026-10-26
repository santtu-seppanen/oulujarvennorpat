# Oulujärven norpat: traileri

Traileri tehdään pelikuvasta Godotin Movie Maker -tilalla (kiinteä 30 fps, jokainen ruutu täydellä laadulla) ja
kappale liitetään ffmpegillä. Kappale tehdään Sunolla: sanat ja tyylikehote ovat `docs/traileri/biisi.md`.

## Vaiheet

1. Kappale on `assets/music/oulujarven_norpat.mp3` (Suno, 190 s, n. 120 bpm; sanat ja kehote `docs/traileri/biisi.md`).
   Leikkauksen osat (`SECTIONS` leikkaus.gd:ssä) on mitattu tämän kappaleen äänenvoimakkuudesta. Jos vaihdat kappaleen, mittaa
   uudet osat ja `SONG_LEN`.
2. Renderöi video (oletuksena kappaleen pituuteen 190 s; `--kesto=<s>` skaalaa kaiken):

   ```
   godot --path . --write-movie ~/traileri/traileri.avi --fixed-fps 30 --resolution 1920x1080 \
     -s tools/traileri/traileri.gd
   ```

   Peli-ikkuna aukeaa, eikä sitä saa sulkea. Näyttöohjain tarvitaan (ei `--headless`). 1080p:llä 2,5 min kestää
   tehosta riippuen 10–40 min.
3. Liitä kappale: `tools/traileri/kokoa.sh ~/traileri/traileri.avi assets/music/oulujarven_norpat.mp3 ~/traileri/traileri.mp4`

## Esikatselu

- Otosten keskikuvat PNG:nä (nopea tapa tarkistaa kuvakulmat): lisää `--kuvat=<kansio>`.
- Vain osa: `--alku=20 --loppu=40` (sekunteja kappaleessa).
- Pienempi tarkkuus: `--resolution 960x540`.

## Leikkaus

`tools/traileri/leikkaus.gd`: otokset järjestyksessä osittain (intro, v1, c1, v2, c2, solo, v3, bridge, final, outro). Osan otokset
jakavat osan ajan `bars`-painojensa suhteessa, joten otoksen lisääminen tai poistaminen ei siirrä muita osia. Sanarivejä ei näytetä
(ne eivät ole kappaleen oikeassa ajoituksessa).

- Otos: `a`→`b` kameran liike, `la`→`lb` katsepiste, `t` = [kk, pv, tunti, min] (valo), `txt` = otsikko.
- `car: true`: auto ajaa täyttä vauhtia sataman tietä, kamera seuraa (hyppyrin otos `jump: true`).
- Alapalkin sanat tulevat `LYRICS`-listasta ja otsikot `txt`-kentistä; pelin oma käyttöliittymä piilotetaan.
