extends SceneTree
## Tupin sääntötesti (headless): godot --headless --path . -s tools/testit/tuppitesti.gd
## Pelataan tietokoneotteluita 52 pisteeseen ja tarkistetaan tarjous, maan tunnustus, tikit ja pisteet.

const T := preload("res://scripts/tuppi.gd")
const R := preload("res://scripts/ristiseiska.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("VIKA " + what)


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var deals := 0
	var rami := 0
	var rami_ok := 0
	var matches := [0, 0]
	var seed := 0
	for g in 40:
		var t := T.new()
		while t.winner < 0 and deals < 5000:
			var before: Array = t.scores.duplicate()
			t.deal(seed)
			seed += 1
			deals += 1
			check(t.phase == "bid" and t.turn == (t.dealer + 1) % 4, "tarjous alkaa jakajan vasemmalta")
			for k in 4:
				var p := t.actor()
				var c := t.bot_bid(p, rng)
				check(T.bid_ok(c), "tarjouskortti ei ole kakkonen eikä kuvakortti")
				check(t.bid(p, c), "tarjous hyväksytään")
			check(t.phase == "play", "tarjouksen jälkeen pelataan")
			var first_red := -1
			for k in 4:
				var q := (t.dealer + 1 + k) % 4
				if T.red(t.bids[q]):
					first_red = q
					break
			check(t.mode == ("rami" if first_red >= 0 else "nolo"), "punainen = rami, muuten nolo")
			check(t.declarer == first_red, "ensimmäinen punainen on ilmoittaja")
			check(t.turn == ((first_red + 3) % 4 if first_red >= 0 else (t.dealer + 1) % 4), "oikea aloittaja")
			for h in t.hands:
				check(h.size() == 13, "tarjouskortit palasivat käteen")
			while t.phase != "over":
				if t.phase == "trick":
					var w: int = t.trick_winner
					var lead := R.suit(t.trick[0][1])
					for e in t.trick:
						if R.suit(e[1]) == lead:
							check(T.power(e[1]) <= T.power(t.leading()[1]), "tikin vie maan suurin")
					check(t.collect() and (t.phase == "over" or t.turn == w), "tikin voittaja aloittaa")
					continue
				var p := t.actor()
				var c := t.bot_play(p, rng)
				var s := t.lead_suit()
				if s >= 0 and R.suit(c) != s:
					for o in t.hands[p]:
						check(R.suit(o) != s, "maata on tunnustettava")
				check(not t.play((p + 1) % 4, c), "vain vuorossa oleva pelaa")
				check(t.play(p, c), "pelattava kortti hyväksytään")
				var n: int = t.played.size()
				for h in t.hands:
					n += h.size()
				check(n == 52, "kortteja 52")
			check(t.won[0] + t.won[1] + t.won[2] + t.won[3] == 13, "13 tikkiä")
			# Pisteet: vain toisella parilla, ja saatu määrä sääntöjen mukaan.
			var tt := [t.team_tricks(0), t.team_tricks(1)]
			var exp := [0, 0]
			if t.mode == "rami":
				rami += 1
				var d := T.team(t.declarer)
				if tt[d] >= 7:
					rami_ok += 1
					exp[d] = 4 * (tt[d] - 6)
				else:
					exp[1 - d] = 8 * (tt[1 - d] - 6)
			else:
				var low := 0 if tt[0] < tt[1] else 1
				exp[low] = 4 * (7 - tt[low])
			check(t.gained == exp, "pisteet %s (odotettu %s)" % [t.gained, exp])
			check(t.scores[0] == 0 or t.scores[1] == 0, "pisteitä vain toisella parilla")
			for k in 2:
				if exp[k] > 0:
					check(t.scores[k] == before[k] + exp[k] and t.scores[1 - k] == 0, "pisteet kertyvät ja vastapari nollautuu")
			var copy := T.new()
			copy.from_dict(JSON.parse_string(JSON.stringify(t.to_dict())))
			check(copy.to_dict() == t.to_dict(), "tila säilyy JSON-muunnoksessa")
		check(t.winner >= 0 and t.scores[t.winner] >= T.WIN, "ottelu päättyi 52 pisteeseen")
		matches[t.winner] += 1
	print("40 ottelua, %d jakoa, ramia %d (onnistui %d), voitot pareittain %s" % [deals, rami, rami_ok, matches])
	print("vikoja %d" % fails)
	quit(1 if fails > 0 else 0)
