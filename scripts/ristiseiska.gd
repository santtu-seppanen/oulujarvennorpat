extends RefCounted
## Ristiseiska: säännöt, pelitila ja tietokonepelaajan valinnat (käyttöliittymä on korttipeli.gd:ssä).
## Kortti on luku maa * 13 + (arvo - 1): arvo 1 = ässä .. 13 = kuningas, maat risti, ruutu, hertta, pata.
##
## Säännöt:
## - Kaikki kortit jaetaan neljälle, 13 kullekin. Ristiseiskan saanut aloittaa pelaamalla sen.
## - Pöytään saa laittaa minkä tahansa maan seiskan tai jatkaa pöydässä olevaa riviä yhdellä ylöspäin
##   (8, 9, .. K) tai alaspäin (6, 5, .. A). Jos voi pelata, on pelattava. Kahdeksikkoa ei saa pelata ennen
##   kuutosta eikä vitosta ennen kahdeksikkoa: rivi etenee 7, 6, 8, 5 ja siitä vapaasti molempiin suuntiin.
## - Peli kiertää myötäpäivään (pelaajien indeksit pöydässä pienenevään suuntaan, ks. Korttipeli).
## - Ässän tai kuninkaan pelannut saa pelata heti uudestaan.
## - Jos ei voi pelata, edellinen pelaaja antaa hänelle valitsemansa kortin, ja vuoro siirtyy seuraavalle.
## - Ensimmäisenä kortit loppuun pelannut voittaa kierroksen ja saa 0 pistettä; muut saavat yhden pisteen
##   jokaisesta käteen jääneestä kortista. Pisteet summataan (totals), ja viikonlopun lopussa vähiten pisteitä
##   saanut on ristiseiskan voittaja (tarina.gd).

const SUITS := ["risti", "ruutu", "hertta", "pata"]
const RANKS := ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const CLUB7 := 6
const MAX_MOVES := 3000  # varmuuden vuoksi: peli päättyy viimeistään tähän
const DIR := -1  # vuoron kiertosuunta: pöydän paikat 0..3 kiertävät vastapäivään, joten myötäpäivään mennään alaspäin

var n := 4
var hands: Array = []  # pelaaja -> Array[int], järjestetty
var low := [0, 0, 0, 0]  # maan rivin pienin arvo pöydässä, 0 = rivi ei ole alkanut
var high := [0, 0, 0, 0]
var turn := 0
var phase := "idle"  # idle | play | give | over
var giver := -1
var finished: Array = []  # pelaajat siinä järjestyksessä, kun kortit loppuivat
var started := false  # ristiseiska pöydässä
var last := {}  # viimeisin tapahtuma: {a: "pelasi"/"antoi", p: pelaaja, c: kortti, to: saaja}
var moves := 0
var totals := [0, 0, 0, 0]  # pisteet koko viikonlopulta (pienin voittaa)
var points := [0, 0, 0, 0]  # viimeisimmän kierroksen pisteet
var rounds := 0  # pelatut kierrokset


static func suit(c: int) -> int:
	return c / 13


static func rank(c: int) -> int:
	return c % 13 + 1


static func card_name(c: int) -> String:
	return "%s %s" % [SUITS[suit(c)], RANKS[rank(c) - 1]]


func deal(seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var deck := range(52)
	for i in range(51, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = deck[i]
		deck[i] = deck[j]
		deck[j] = t
	hands.clear()
	for p in n:
		var h: Array = deck.slice(p * 13, p * 13 + 13)
		h.sort()
		hands.append(h)
	low = [0, 0, 0, 0]
	high = [0, 0, 0, 0]
	finished.clear()
	started = false
	last = {}
	moves = 0
	giver = -1
	for p in n:
		if hands[p].has(CLUB7):
			turn = p
	phase = "play"


func can_play(c: int) -> bool:
	if not started:
		return c == CLUB7
	var s := suit(c)
	var r := rank(c)
	if low[s] == 0:
		return r == 7
	if r == 8:
		return high[s] == 7 and low[s] <= 6  # kahdeksikko vasta kuutosen jälkeen
	if r == 5:
		return low[s] == 6 and high[s] >= 8  # vitonen vasta kahdeksikon jälkeen
	return r == low[s] - 1 or r == high[s] + 1


func playable(p: int) -> Array:
	var out := []
	for c in hands[p]:
		if can_play(c):
			out.append(c)
	return out


func active(p: int) -> bool:
	return not hands[p].is_empty()


func next_active(p: int) -> int:
	for k in range(1, n + 1):
		var q := (p + DIR * k + n * n) % n
		if active(q):
			return q
	return p


func prev_active(p: int) -> int:
	for k in range(1, n + 1):
		var q := (p - DIR * k + n * n) % n
		if active(q):
			return q
	return p


## Kuka on vuorossa toimimaan: pelaamaan (play) tai antamaan korttia (give). -1 kun peli ei ole käynnissä.
func actor() -> int:
	if phase == "play":
		return turn
	if phase == "give":
		return giver
	return -1


func play(p: int, c: int) -> bool:
	if phase != "play" or p != turn or not hands[p].has(c) or not can_play(c):
		return false
	hands[p].erase(c)
	var s := suit(c)
	var r := rank(c)
	if low[s] == 0:
		low[s] = r
		high[s] = r
	else:
		low[s] = mini(low[s], r)
		high[s] = maxi(high[s], r)
	started = true
	last = {"a": "pelasi", "p": p, "c": c}
	moves += 1
	if not active(p):
		finished.append(p)
	if _check_over():
		return true
	if active(p) and (r == 1 or r == 13):
		_begin_turn(p)  # ässä tai kuningas: uusi vuoro
	else:
		_begin_turn(next_active(p))
	return true


func give(p: int, c: int) -> bool:
	if phase != "give" or p != giver or not hands[p].has(c):
		return false
	hands[p].erase(c)
	hands[turn].append(c)
	hands[turn].sort()
	last = {"a": "antoi", "p": p, "c": c, "to": turn}
	moves += 1
	if not active(p):
		finished.append(p)
	if _check_over():
		return true
	_begin_turn(next_active(turn))
	return true


func _begin_turn(p: int) -> void:
	turn = p
	if playable(p).is_empty():
		phase = "give"
		giver = prev_active(p)
	else:
		phase = "play"
		giver = -1


func _check_over() -> bool:
	var left := []
	for p in n:
		if active(p):
			left.append(p)
	if finished.is_empty() and moves < MAX_MOVES:
		return false
	# Kierros päättyy, kun ensimmäinen on pelannut kortit loppuun (tai varmuusraja täyttyy): muut sijoitetaan
	# käteen jääneiden korttien mukaan, ja pisteet kirjataan.
	left.sort_custom(func(a: int, b: int) -> bool: return hands[a].size() < hands[b].size())
	for p in left:
		if not finished.has(p):
			finished.append(p)
	if finished.size() < n:
		for p in n:
			if not finished.has(p):
				finished.append(p)
	for p in n:
		points[p] = hands[p].size()
		totals[p] += points[p]
	rounds += 1
	phase = "over"
	giver = -1
	return true


# --- Tietokonepelaaja -----------------------------------------------------------------------------------------

## Pelattava kortti: ässä ja kuningas antavat lisävuoron, ja kannattaa avata rivejä, joissa on omia kortteja.
func bot_play(p: int, rng: RandomNumberGenerator) -> int:
	var best := -1
	var best_score := -INF
	for c in playable(p):
		var s := suit(c)
		var r := rank(c)
		var score := rng.randf() * 0.5
		if r == 1 or r == 13:
			score += 3.0
		for o in hands[p]:
			if o == c or suit(o) != s:
				continue
			var ro := rank(o)
			if (r <= 7 and ro < r) or (r >= 7 and ro > r):
				score += 1.0  # oma kortti tämän takana
		# Avaamaton rivi auttaa muita, jos omia kortteja ei ole sen takana.
		if r == 7 and c != CLUB7:
			score -= 0.8
		if score > best_score:
			best_score = score
			best = c
	return best


## Annettava kortti: se, jota on vaikeinta saada pöytään (kauimpana rivin päästä).
func bot_give(p: int, rng: RandomNumberGenerator) -> int:
	var best := -1
	var best_d := -INF
	for c in hands[p]:
		var s := suit(c)
		var r := rank(c)
		var d := 0.0
		if low[s] == 0:
			d = absf(r - 7) + 1.0
		elif r < low[s]:
			d = low[s] - r
		else:
			d = r - high[s]
		d += rng.randf() * 0.3
		if d > best_d:
			best_d = d
			best = c
	return best


# --- Verkko ---------------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"h": hands, "lo": low, "hi": high, "t": turn, "ph": phase, "g": giver, "f": finished, "st": started,
		"l": last, "m": moves, "to": totals, "po": points, "ro": rounds}


func from_dict(d: Dictionary) -> void:
	hands.clear()
	for h in d.h:
		var a := []
		for c in h:
			a.append(int(c))
		hands.append(a)
	low = (d.lo as Array).map(func(x: Variant) -> int: return int(x))
	high = (d.hi as Array).map(func(x: Variant) -> int: return int(x))
	turn = int(d.t)
	phase = d.ph
	giver = int(d.g)
	finished = (d.f as Array).map(func(x: Variant) -> int: return int(x))
	started = d.st
	last = {}
	for k in d.l:
		last[k] = d.l[k] if k == "a" else int(d.l[k])
	moves = int(d.m)
	totals = (d.get("to", [0, 0, 0, 0]) as Array).map(func(x: Variant) -> int: return int(x))
	points = (d.get("po", [0, 0, 0, 0]) as Array).map(func(x: Variant) -> int: return int(x))
	rounds = int(d.get("ro", 0))
