extends RefCounted
## Kaikki nauhoitettavat repliikit [ääni, teksti] (tools/puhe/nauhoita.py ajaa tämän). Rivit tulevat pelin omista vakioista,
## joten uusi repliikki vakiossa tulee mukaan seuraavalla nauhoituksella. Dynaamiset rivit (esim. trivian vastaukset ja
## muistelun "Muistatko kun <tarina>") ja pelaajien viestit eivät ole mukana: ne näkyvät vain tekstinä.

const VOICES := ["santtu", "marko", "jaakko", "jukka"]
const Ai := preload("res://scripts/ai.gd")
const Main := preload("res://scripts/main.gd")
const Afrikka := preload("res://scripts/afrikantahti.gd")
const Lauta := preload("res://scripts/lautapeli.gd")
const Tarjoilu := preload("res://scripts/tarjoilupoyta.gd")
const Retki := preload("res://scripts/tutkimusmatka.gd")
const Muistelu := preload("res://scripts/muistelu.gd")
const Loppu := preload("res://scripts/loppu.gd")
const Oodi := preload("res://scripts/oodi.gd")
const Tyo := preload("res://scripts/tyopuhelu.gd")
const Baari := preload("res://scripts/baari.gd")


static func all() -> Array:
	var out: Array = []
	var every: Array = []  # rivit, joita voi sanoa kuka tahansa mökkiläinen
	every.append_array(Ai.LINES_NAP)
	every.append_array(Main.RIDE_LINES_A)
	every.append_array(Main.RIDE_LINES_B)
	every.append_array([Afrikka.STAR_FOUND, Afrikka.STAR_MINE])
	every.append_array(Lauta.PASS_LINES)
	every.append_array(Tarjoilu.PRAISE_COFFEE)
	every.append_array(Tarjoilu.PRAISE_FOOD)
	every.append_array(Tarjoilu.PRAISE_STEAK)
	every.append_array(Retki.LINES_START)
	every.append_array(Retki.LINES_ROW)
	every.append_array(Retki.LINES_STASH)
	every.append_array(Retki.LINES_HOME)
	every.append_array(Loppu.LOSS_LINES)
	for s: Dictionary in Muistelu.STORIES + Muistelu.OWN:
		every.append(s.text)
		for o: Array in s.opts:
			every.append(o[2])
	for v: String in VOICES:
		for t: String in every:
			out.append([v, t])
	# Tietylle äänelle.
	for t: String in Ai.LINES_JUKKA:
		out.append(["jukka", t])
	for t: String in Main.COFFEE_LINES:
		out.append(["jukka", t])
	out.append(["marko", Tarjoilu.BREAKFAST_LINE])
	out.append(["marko", Tarjoilu.STEAK_LINE])
	for t: String in Tyo.MUMBLES:
		out.append(["jaakko", t])
	for e: Array in Loppu.RING_LINES:
		if e[0] == "kaikki":
			for v: String in VOICES:
				out.append([v, e[1]])
		else:
			out.append([str(e[0]).to_lower(), e[1]])
	for t: String in ["Nuotiolla oli kivaa.", "Ensi kerralla nuotiolla vähän vähemmän piikittelyä."]:
		out.append(["jaakko", t])
	# Puhelut: nalkuttava mies (esimies) ja nalkuttava nainen (vaimo).
	for c: Array in Tyo.CALLS:
		out.append(["esimies", c[1]])
	for t: String in Baari.WIFE_LINES:
		out.append(["vaimo", t])
	# Oodi: jokainen sana jokaisella äänellä (toistetaan sävelen korkeudella).
	var seen := {}
	for part: Array in Oodi.SONG:
		for line: String in part[1]:
			for w: String in Oodi.words(line):
				seen[w] = true
	for v: String in VOICES:
		for w: String in seen:
			out.append([v, w])
	return out
