extends RefCounted
## Trailerin leikkaus: otokset järjestyksessä, kesto tahteina (4/4). Biisin rakenne (docs/traileri/biisi.md) on
## alkusoitto 4, säkeistö 8, kertosäe 8, säkeistö 8, kertosäe 8, sooloa 8, säkeistö 8, bridge 4, loppukertosäe 12 ja
## lopetus 4 tahtia (yhteensä 72 tahtia, n. 124 bpm). Renderöinti venyttää kestot kappaleen oikeaan pituuteen (--kesto).
##
## Otos: {bars, a, b: kameran alku- ja loppupaikka, la, lb: katsepisteen alku ja loppu, t: [kk, pv, h, min], txt: teksti,
## car: true = auto ajaa sataman tietä (hyppyri), rel: "boat" | "sinikka" = paikat suhteessa kumiveneeseen tai Sinikkaan
## (Sinikan paikalliskehys), game: peliskripti, jonka minipeli avataan ruudulle (play: sille kutsuttava metodi),
## call: näytetään vihainen työpuhelu (Jaakon saunapuhelu) kuvan päällä}. Paikat lasketaan tässä pelin omilla
## apufunktioilla, joten ne seuraavat maailman muutoksia.

const BEATS_PER_BAR := 4
const BPM := 120.0
const SONG_LEN := 190.0  # assets/music/oulujarven_norpat.mp3 (Suno), sekuntia

## Kappaleen osat sekunteina (energiakäyrästä: rauhallinen alku, hiljainen siirtymä 126–138 s, kovin loppu).
## Osan otokset jakavat osan ajan `bars`-painojensa suhteessa.
const SECTIONS := {"intro": [0.0, 12.0], "v1": [12.0, 36.0], "c1": [36.0, 61.0], "v2": [61.0, 77.0], "c2": [77.0, 102.0],
	"solo": [102.0, 112.0], "v3": [112.0, 126.0], "bridge": [126.0, 138.0], "final": [138.0, 188.0], "outro": [188.0, 190.0]}

## Sanat tahdeittain: [alkutahti, teksti]. Alkutahti on kappaleessa (0 = alku). Näytetään alapalkissa.
const LYRICS := [
	[4, "Halot syliin, kiuas tulille"], [6, "Pelti auki, älä unohda"], [8, "Santtu nauraa, Jaakko puhelimessa"], [10, "Löylyä, löylyä..."],
	[12, "Oulujärven norpat, norpat, norpat!"], [14, "Torstaista sunnuntaihin mennään!"], [16, "Sauna palaa, ei tää lopu ennen!"],
	[18, "Tänään ei mökiltä lähdetä!"],
	[20, "Marko paistaa pyttipannua"], [22, "Jukka keittää kahvit liedellä"], [24, "Ristiseiska pöydässä, tuppi perään"],
	[26, "Nuotiolla makkara on musta"],
	[28, "Oulujärven norpat, norpat, norpat!"], [30, "Torstaista sunnuntaihin mennään!"], [32, "Sauna palaa, ei tää lopu ennen!"],
	[34, "Tänään ei mökiltä lähdetä!"],
	[44, "Lauantaina Happy Beachille, täysillä tietä"], [46, "Muskelivene vaahtoaa järven yli"], [48, "Karaoke soi, Jukka laulaa väärin"],
	[50, "Kumivene ulapalle, kätkö kutsuu"],
	[52, "Keskiyö, laiturin päässä, neljä miestä rivissä"], [54, "Järvi on musta ja tähdet on kirkkaat"],
	[56, "Oulujärven norpat, norpat, norpat!"], [58, "Vainojen virmat, oi vaietkaa!"], [60, "Pirttimme piilköhöt paikoillaan!"],
	[62, "Yks on pannukahvi, toinen kalja"], [64, "Sunnuntaina... vielä yks löyly!"], [68, "Norpat! Äpätti!"]]


## Otosten lista. Mokki ja Reitti ovat peliskriptien luokat (ladataan ajon aikana).
static func shots(Mokki: GDScript, Reitti: GDScript, Satama: GDScript, main: Node3D) -> Array:
	var y := func(u: float, v: float, h: float) -> Vector3:
		var w: Vector2 = Mokki.yw(u, v)
		return Vector3(w.x, h, w.y)
	var D: float = Mokki.DY
	var o := Vector3(Satama.ORIGIN.x, 0.0, Satama.ORIGIN.y)
	var hb := func(a: float, b: float, h: float) -> Vector3:
		var w: Vector2 = Reitti.cw(a, b)
		return Vector3(w.x, h, w.y)
	var fire: Vector3 = main.world.mokki.fire_pos
	var boat_pos: Vector3 = main.boat.global_position
	var fy := func(u: float, v: float) -> Vector3:  # kameran paikka nuotion luona paikallisessa kehyksessä, silmänkorkeudella
		var w: Vector2 = Mokki.yw(u, v)
		return Vector3(w.x, fire.y + 1.5, w.y)
	var s: Array = []
	var sec := {"n": "intro"}  # lambda kopioi arvot, joten osan nimi on sanakirjassa
	var add := func(d: Dictionary) -> void:
		d["sec"] = sec.n
		s.append(d)
	# Alkusoitto (4 tahtia): ilmakuva Äpätistä aamulla.
	sec.n = "intro"
	add.call({"bars": 4, "a": y.call(-30.0, 40.0, 38.0), "b": y.call(-12.0, 18.0, 14.0), "la": y.call(-3.0, 0.0, 3.0),
		"lb": y.call(-3.0, -2.0, 3.0), "t": [7, 9, 5, 30], "txt": "OULUJÄRVEN NORPAT"})
	# Säkeistö 1 (8): torstai, tie, halot, sauna, järvi.
	sec.n = "v1"
	add.call({"bars": 2, "car": true, "t": [7, 9, 17, 40], "txt": "TORSTAI"})
	add.call({"bars": 2, "a": y.call(-6.0, 2.4, D + 1.7), "b": y.call(-5.2, 1.6, D + 1.5), "la": y.call(-4.9, 0.25, D + 0.6),
		"lb": y.call(-4.9, -0.2, D + 0.7), "t": [7, 9, 18, 0]})
	add.call({"bars": 2, "a": y.call(-14.0, 18.0, 16.0), "b": y.call(-12.0, 14.0, 14.0), "la": y.call(-3.0, -2.0, 2.0),
		"lb": y.call(-3.0, -2.0, 2.0), "t": [7, 9, 18, 40], "call": "Jaakko! Missä ne raportit on?! Vastaa nyt heti!"})
	add.call({"bars": 2, "a": y.call(-3.0, 30.0, 1.2), "b": y.call(-3.0, 24.0, 1.6), "la": y.call(-3.0, 0.0, 3.0),
		"lb": y.call(-3.0, 0.0, 4.0), "t": [7, 9, 19, 40]})
	# Kertosäe 1 (8): yksi tahti per otos.
	sec.n = "c1"
	for k in [[y.call(-6.0, 2.4, D + 1.7), y.call(-4.9, 0.25, D + 0.6), [7, 9, 20, 30]], [y.call(-2.2, 13.0, 2.1), y.call(-3.0, 0.0, 3.0), [7, 9, 22, 20]],
			[y.call(-14.0, 18.0, 16.0), y.call(-3.0, -2.0, 2.0), [7, 9, 21, 10]], [fy.call(-12.0, -4.6), fire + Vector3(0, 0.5, 0), [7, 9, 22, 30]],
			[y.call(-2.0, 1.2, D + 1.5), y.call(-5.5, -0.5, D + 0.9), [7, 9, 21, 50]], [y.call(-3.0, 30.0, 1.2), y.call(-3.0, 0.0, 3.0), [7, 9, 23, 15]],
			[fy.call(-13.5, -5.2), fire + Vector3(0, 0.6, 0), [7, 9, 23, 20]], [y.call(-6.0, 2.4, D + 1.7), y.call(-4.9, 0.25, D + 0.6), [7, 9, 23, 40]]]:
		add.call({"bars": 1, "a": k[0], "b": k[0] + Vector3(0.12, 0.04, 0.12), "la": k[1], "lb": k[1], "t": k[2]})
	# Säkeistö 2 (8): perjantai, keittiö, nuotio.
	sec.n = "v2"
	add.call({"bars": 2, "a": y.call(-6.5, 2.6, D + 1.7), "b": y.call(-2.0, 1.2, D + 1.5), "la": y.call(-4.9, 0.0, D + 0.7),
		"lb": y.call(-5.5, -0.5, D + 0.9), "t": [7, 10, 18, 0], "txt": "PERJANTAI"})
	add.call({"bars": 2, "a": y.call(-6.0, 2.4, D + 1.7), "b": y.call(-5.2, 1.6, D + 1.5), "la": y.call(-4.9, 0.25, D + 0.6),
		"lb": y.call(-4.9, -0.2, D + 0.7), "t": [7, 10, 12, 0]})
	add.call({"bars": 2, "a": fy.call(-12.0, -4.6), "b": fy.call(-13.5, -5.2), "la": fire, "lb": fire,
		"t": [7, 10, 22, 0]})
	add.call({"bars": 2, "a": y.call(-6.2, -1.2, D + 1.6), "b": y.call(-6.0, -1.4, D + 1.55), "la": y.call(-9.3, -1.6, D + 0.2),
		"lb": y.call(-9.3, -1.8, D + 0.4), "t": [7, 10, 17, 0]})
	# Kertosäe 2 (8): Happy Beach, satama ilmasta, leiri.
	sec.n = "c2"
	var hbs := [[hb.call(30.0, 40.0, 45.0), hb.call(40.0, 70.0, 0.0), hb.call(60.0, 55.0, 30.0), [7, 10, 20, 30]],
		[hb.call(-10.0, 30.0, 14.0), hb.call(20.0, 50.0, 0.0), hb.call(-6.0, 34.0, 11.0), [7, 10, 21, 0]],
		[hb.call(-6.0, 34.0, 12.0), hb.call(40.0, 66.0, 0.0), hb.call(0.0, 36.0, 10.0), [7, 10, 21, 30]],
		[hb.call(8.0, 36.0, 9.0), hb.call(30.0, 62.0, 0.0), hb.call(14.0, 40.0, 7.0), [7, 10, 22, 0]]]
	for k in hbs:
		add.call({"bars": 2, "a": k[0], "b": k[2], "la": k[1], "lb": k[1], "t": k[3]})
	# Sooloa (8): lauantai, hyppyri ja muskelivene.
	sec.n = "solo"
	add.call({"bars": 4, "car": true, "jump": true, "t": [7, 11, 15, 0], "txt": "LAUANTAI"})
	add.call({"bars": 2, "a": o + Vector3(14.0, 22.0, -34.0), "b": o + Vector3(6.0, 12.0, -22.0), "la": o + Vector3(0.0, 0.0, -16.0),
		"lb": o + Vector3(2.0, 0.0, -16.0), "t": [7, 11, 16, 0]})
	add.call({"bars": 2, "a": o + Vector3(30.0, 4.0, -44.0), "b": o + Vector3(16.0, 3.0, -30.0), "la": o + Vector3(0.0, 1.0, -14.0),
		"lb": o + Vector3(1.0, 1.0, -16.0), "t": [7, 11, 17, 0]})
	# Säkeistö 3 (8): Happy Beach (Sinikka, minipelit), tutkimusmatka kumiveneellä.
	sec.n = "v3"
	add.call({"bars": 2, "rel": "sinikka", "a": Vector3(-3.2, 1.5, 2.8), "b": Vector3(-2.4, 1.5, 2.2), "la": Vector3(0.0, 1.45, 0.0),
		"lb": Vector3(0.0, 1.5, 0.0), "t": [7, 11, 21, 30], "txt": "HAPPY BEACH"})
	add.call({"bars": 1, "game": "res://scripts/pokeri_game.gd", "play": "_deal", "t": [7, 11, 21, 40]})
	add.call({"bars": 1, "game": "res://scripts/hedelmapeli_game.gd", "play": "_play", "t": [7, 11, 21, 45]})
	add.call({"bars": 2, "a": y.call(-6.0, 22.0, 3.2), "b": y.call(-4.0, 18.0, 2.2), "la": boat_pos + Vector3(0, 0.6, 0), "lb": boat_pos + Vector3(0, 0.6, 0),
		"t": [7, 11, 19, 0], "txt": "TUTKIMUSMATKA"})
	add.call({"bars": 2, "a": y.call(-3.0, 40.0, 3.0), "b": y.call(-3.0, 34.0, 2.2), "la": y.call(-3.0, 0.0, 3.0), "lb": y.call(-3.0, 0.0, 3.0),
		"t": [7, 11, 19, 30]})
	# Bridge (4): keskiyö laiturin päässä.
	sec.n = "bridge"
	add.call({"bars": 4, "a": y.call(-2.2, 13.0, 2.1), "b": y.call(-2.2, 15.0, 2.3), "la": y.call(-3.0, 0.0, 3.0), "lb": y.call(-3.0, 2.0, 3.2),
		"t": [7, 12, 0, 10], "txt": "KESKIYÖ"})
	# Loppukertosäe (12): nopea leikkaus, lopuksi pitkä auringonnousu.
	sec.n = "final"
	var fin := [[y.call(-6.0, 2.4, D + 1.7), y.call(-4.9, 0.25, D + 0.6), [7, 12, 5, 0]], [fy.call(-12.0, -4.6), fire, [7, 12, 6, 0]],
		[y.call(-14.0, 18.0, 16.0), y.call(-3.0, -2.0, 2.0), [7, 12, 7, 0]], [y.call(-2.0, 1.2, D + 1.5), y.call(-5.5, -0.5, D + 0.9), [7, 12, 8, 0]],
		[o + Vector3(14.0, 22.0, -34.0), o + Vector3(0.0, 0.0, -16.0), [7, 12, 9, 0]], [hb.call(30.0, 40.0, 45.0), hb.call(40.0, 70.0, 0.0), [7, 12, 10, 0]],
		[y.call(-2.2, 13.0, 2.1), y.call(-3.0, 0.0, 3.0), [7, 12, 11, 0]], [y.call(-3.0, 30.0, 1.2), y.call(-3.0, 0.0, 3.0), [7, 12, 12, 0]]]
	fin.append_array([[o + Vector3(30.0, 4.0, -44.0), o + Vector3(0.0, 1.0, -14.0), [7, 12, 13, 0]], [hb.call(-6.0, 34.0, 12.0), hb.call(40.0, 66.0, 0.0), [7, 12, 14, 0]],
		[y.call(-6.0, 2.4, D + 1.7), y.call(-4.9, 0.25, D + 0.6), [7, 12, 15, 0]], [fy.call(-12.0, -4.6), fire, [7, 12, 22, 0]],
		[y.call(-14.0, 18.0, 16.0), y.call(-3.0, -2.0, 2.0), [7, 12, 18, 0]], [hb.call(30.0, 40.0, 45.0), hb.call(40.0, 70.0, 0.0), [7, 12, 19, 0]],
		[y.call(-2.2, 13.0, 2.1), y.call(-3.0, 0.0, 3.0), [7, 12, 20, 30]], [o + Vector3(14.0, 22.0, -34.0), o + Vector3(0.0, 0.0, -16.0), [7, 12, 21, 0]]])
	for k in fin:
		add.call({"bars": 1, "a": k[0], "b": k[0] + Vector3(0.12, 0.04, 0.12), "la": k[1], "lb": k[1], "t": k[2]})
	add.call({"bars": 4, "a": y.call(-30.0, 40.0, 38.0), "b": y.call(-8.0, 16.0, 10.0), "la": y.call(-3.0, 0.0, 3.0), "lb": y.call(-3.0, -2.0, 3.0),
		"t": [7, 12, 21, 20], "txt": "SUNNUNTAI"})
	# Lopetus (4): auringonlasku ja otsikko.
	sec.n = "outro"
	add.call({"bars": 4, "a": y.call(-3.0, 30.0, 2.0), "b": y.call(-3.0, 22.0, 2.4), "la": y.call(-3.0, 0.0, 3.0), "lb": y.call(-3.0, 0.0, 4.5),
		"t": [7, 12, 22, 40], "txt": "OULUJÄRVEN NORPAT", "end": true})
	return s
