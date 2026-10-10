extends RefCounted
## Tuppi: säännöt, pelitila ja tietokonepelaajan valinnat (käyttöliittymä on korttipeli.gd:ssä).
## Kortti on luku maa * 13 + (arvo - 1) kuten ristiseiska.gd:ssä; tupissa ässä on suurin.
##
## Säännöt:
## - Neljä pelaajaa pareittain: vastakkain istuvat (pelaaja p ja p + 2) ovat paria. Kaikki kortit jaetaan.
## - Tarjous: jakajan vasemmalta alkaen kukin valitsee kädestään tarjouskortin kuvapuoli alaspäin (ei kakkosia
##   eikä kuvakortteja). Punainen on rami, musta nolo. Kortit käännetään samassa järjestyksessä: ensimmäinen
##   punainen ratkaisee, ja sen laittanut on ramin ilmoittaja. Jos punaisia ei ole, pelataan noloa.
##   Tarjouskortit palaavat käteen.
## - Ramissa ilmoittajan oikealla puolella istuva aloittaa, nolossa jakajan vasemmalla puolella istuva.
## - Valttia ei ole. Maata on tunnustettava; tikin vie aloitetun maan suurin kortti, ja tikin voittaja aloittaa
##   seuraavan.
## - Rami: ilmoittajan pari saa 4 pistettä jokaisesta tikistä yli kuuden, ja jos rami kaatuu, vastapari saa
##   8 pistettä jokaisesta omasta tikistään yli kuuden.
## - Nolo: vähemmän tikkejä saanut pari saa 4 pistettä jokaisesta tikistä, joka siltä puuttuu seitsemästä.
## - Pisteitä voi olla vain toisella parilla: kun pari saa pisteitä, vastaparin pisteet nollautuvat.
##   Ensimmäisenä 52 pisteeseen päässyt pari voittaa.
## (Sooli eli yksinpeli nolossa on jätetty pois.)

const R := preload("res://scripts/ristiseiska.gd")
const WIN := 52

var n := 4
var hands: Array = []  # pelaaja -> Array[int], järjestetty
var dealer := 3  # ensimmäisessä jaossa jakaja on 0
var phase := "idle"  # idle | bid | play | trick (täysi tikki pöydässä) | over (jako pelattu)
var turn := 0
var bids := [-1, -1, -1, -1]  # tarjouskortit
var mode := ""  # rami | nolo
var declarer := -1
var trick: Array = []  # [[pelaaja, kortti], ..] aloittajasta alkaen
var trick_winner := -1
var won := [0, 0, 0, 0]  # tikit pelaajittain
var played: Array = []  # tässä jaossa pelatut kortit (tietokone laskee kortit)
var scores := [0, 0]  # parit: 0 = pelaajat 0 ja 2, 1 = pelaajat 1 ja 3
var gained := [0, 0]  # viimeisimmän jaon pisteet
var winner := -1  # ottelun voittanut pari
var last := {}  # viimeisin tapahtuma: {a: "tarjosi"/"pelasi"/"vei", p: pelaaja, c: kortti}
var moves := 0


static func team(p: int) -> int:
	return p % 2


static func power(c: int) -> int:
	var r := R.rank(c)
	return 14 if r == 1 else r


static func bid_ok(c: int) -> bool:
	var r := R.rank(c)
	return r == 1 or (r >= 3 and r <= 10)


static func red(c: int) -> bool:
	return R.suit(c) == 1 or R.suit(c) == 2


func team_tricks(t: int) -> int:
	return won[t] + won[t + 2]


func deal(seed: int) -> void:
	if winner >= 0:
		scores = [0, 0]
		winner = -1
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
	dealer = (dealer + 1) % n
	bids = [-1, -1, -1, -1]
	mode = ""
	declarer = -1
	trick = []
	trick_winner = -1
	won = [0, 0, 0, 0]
	played = []
	gained = [0, 0]
	last = {}
	moves = 0
	turn = (dealer + 1) % n
	phase = "bid"


## Kuka on vuorossa: tarjoamaan tai pelaamaan. -1, kun kukaan ei ole (täysi tikki tai jako ohi).
func actor() -> int:
	return turn if phase == "bid" or phase == "play" else -1


## Kortit, jotka kelpaavat tarjoukseen (jos mikään ei kelpaa, mikä tahansa käy).
func bid_cards(p: int) -> Array:
	var out: Array = hands[p].filter(bid_ok)
	return out if not out.is_empty() else hands[p].duplicate()


func bid(p: int, c: int) -> bool:
	if phase != "bid" or p != turn or not bid_cards(p).has(c):
		return false
	bids[p] = c
	last = {"a": "tarjosi", "p": p, "c": c}
	moves += 1
	turn = (p + 1) % n
	if turn != (dealer + 1) % n:
		return true
	# Kaikki tarjosivat: käännetään jakajan vasemmalta alkaen.
	mode = "nolo"
	for k in n:
		var q := (dealer + 1 + k) % n
		if red(bids[q]):
			mode = "rami"
			declarer = q
			break
	turn = (declarer + n - 1) % n if mode == "rami" else (dealer + 1) % n
	phase = "play"
	return true


func lead_suit() -> int:
	return R.suit(trick[0][1]) if not trick.is_empty() else -1


func can_play(p: int, c: int) -> bool:
	if not hands[p].has(c):
		return false
	var s := lead_suit()
	if s < 0 or R.suit(c) == s:
		return true
	for o in hands[p]:
		if R.suit(o) == s:
			return false
	return true


func playable(p: int) -> Array:
	return hands[p].filter(func(c: int) -> bool: return can_play(p, c))


## Tikin tämänhetkinen voittaja [pelaaja, kortti].
func leading() -> Array:
	var best: Array = trick[0]
	for e in trick:
		if R.suit(e[1]) == R.suit(best[1]) and power(e[1]) > power(best[1]):
			best = e
	return best


func play(p: int, c: int) -> bool:
	if phase != "play" or p != turn or not can_play(p, c):
		return false
	hands[p].erase(c)
	trick.append([p, c])
	played.append(c)
	last = {"a": "pelasi", "p": p, "c": c}
	moves += 1
	if trick.size() < n:
		turn = (p + 1) % n
		return true
	trick_winner = leading()[0]
	phase = "trick"
	return true


## Täysi tikki voittajalle (korttipeli kutsuu pienen tauon jälkeen, jotta tikki ehditään nähdä).
func collect() -> bool:
	if phase != "trick":
		return false
	won[trick_winner] += 1
	last = {"a": "vei", "p": trick_winner, "c": trick[-1][1]}
	moves += 1
	trick = []
	turn = trick_winner
	trick_winner = -1
	phase = "play"
	if not hands[turn].is_empty():
		return true
	_score()
	phase = "over"
	return true


func _score() -> void:
	gained = [0, 0]
	var t := [team_tricks(0), team_tricks(1)]
	if mode == "rami":
		var d := team(declarer)
		if t[d] >= 7:
			gained[d] = 4 * (t[d] - 6)
		else:
			gained[1 - d] = 8 * (t[1 - d] - 6)
	else:
		var low := 0 if t[0] < t[1] else 1
		gained[low] = 4 * (7 - t[low])
	for k in 2:
		if gained[k] > 0:
			scores[1 - k] = 0
			scores[k] += gained[k]
			if scores[k] >= WIN:
				winner = k


# --- Tietokonepelaaja -----------------------------------------------------------------------------------------

## Tarjous: vahva käsi (ässät, kuninkaat, pitkät maat) tarjoaa ramia punaisella, heikko noloa mustalla.
func bot_bid(p: int, rng: RandomNumberGenerator) -> int:
	var hcp := 0.0
	var counts := [0, 0, 0, 0]
	for c in hands[p]:
		hcp += maxf(0.0, power(c) - 10.0)
		counts[R.suit(c)] += 1
	for k in 4:
		hcp += maxf(0.0, counts[k] - 4.0)
	var want_red := hcp + rng.randf() * 2.0 > 15.0
	var cs := bid_cards(p)
	var pick: Array = cs.filter(func(c: int) -> bool: return red(c) == want_red)
	if pick.is_empty():
		pick = cs
	pick.sort_custom(func(a: int, b: int) -> bool: return power(a) < power(b))
	return pick[0]


## Onko kortti maansa suurin jäljellä oleva (varma tikki, jos sillä aloitetaan).
func _boss(p: int, c: int) -> bool:
	for o in range(R.suit(c) * 13, R.suit(c) * 13 + 13):
		if power(o) > power(c) and not played.has(o) and not hands[p].has(o):
			return false
	return true


func bot_play(p: int, rng: RandomNumberGenerator) -> int:
	var cs := playable(p)
	cs.sort_custom(func(a: int, b: int) -> bool: return power(a) < power(b))
	var want := mode == "rami"  # ramissa kumpikin pari haluaa tikkejä, nolossa välttelee
	if trick.is_empty():
		if want:
			for c in cs:
				if _boss(p, c):
					return c
			return cs[0]
		# Nolossa aloitetaan pienellä, mieluiten lyhyestä maasta.
		return cs[0] if rng.randf() < 0.7 else cs[mini(1, cs.size() - 1)]
	var best: Array = leading()
	var follow := R.suit(cs[0]) == lead_suit()
	var beats := cs.filter(func(c: int) -> bool: return follow and power(c) > power(best[1]))
	var under := cs.filter(func(c: int) -> bool: return not follow or power(c) < power(best[1]))
	var last_seat := trick.size() == n - 1
	if want:
		if team(best[0]) == team(p) and (last_seat or _boss(p, best[1])):
			return cs[0]  # pari vie jo
		if not beats.is_empty():
			# Viimeisenä riittää pienin voittava, muuten varma tikki suurimmalla.
			return beats[-1] if not last_seat and _boss(p, beats[-1]) else beats[0]
		return cs[0]
	# Nolo: suurin kortti, joka jää alle; jos tikki tulee kuitenkin, viedään suurimmalla.
	if not follow:
		return cs[-1]
	if not under.is_empty():
		return under[-1]
	return cs[-1] if last_seat else cs[0]


# --- Verkko ---------------------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"h": hands, "d": dealer, "ph": phase, "t": turn, "b": bids, "mo": mode, "de": declarer, "tr": trick,
		"tw": trick_winner, "w": won, "pl": played, "s": scores, "g": gained, "wi": winner, "l": last, "m": moves}


static func _ints(a: Variant) -> Array:
	return (a as Array).map(func(x: Variant) -> int: return int(x))


func from_dict(d: Dictionary) -> void:
	hands = (d.h as Array).map(func(h: Variant) -> Array: return _ints(h))
	dealer = int(d.d)
	phase = d.ph
	turn = int(d.t)
	bids = _ints(d.b)
	mode = d.mo
	declarer = int(d.de)
	trick = (d.tr as Array).map(func(e: Variant) -> Array: return _ints(e))
	trick_winner = int(d.tw)
	won = _ints(d.w)
	played = _ints(d.pl)
	scores = _ints(d.s)
	gained = _ints(d.g)
	winner = int(d.wi)
	last = {}
	for k in d.l:
		last[k] = d.l[k] if k == "a" else int(d.l[k])
	moves = int(d.m)
