extends SceneTree
## Ristiseiskan sääntötesti (headless): godot --headless --path . -s tools/testit/ristiseiskatesti.gd
## Pelataan 300 tietokonepeliä ja tarkistetaan, että kortit säilyvät, rivit ovat yhtenäisiä ja pelit päättyvät.

const R := preload("res://scripts/ristiseiska.gd")

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("VIKA " + what)


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var total_moves := 0
	var gives := 0
	var extra := 0
	var wins := [0, 0, 0, 0]
	for g in 300:
		var r := R.new()
		r.deal(g)
		check(r.hands[r.turn].has(R.CLUB7), "ristiseiskan haltija aloittaa")
		check(r.playable(r.turn) == [R.CLUB7], "ensin vain ristiseiska")
		var first := true
		while r.phase != "over":
			var p := r.actor()
			if r.phase == "play":
				var c := r.bot_play(p, rng)
				if first:
					check(c == R.CLUB7, "ensimmäinen kortti on ristiseiska")
					first = false
				var before := r.turn
				check(r.play(p, c), "pelattava kortti hyväksytään")
				if r.phase != "over" and (R.rank(c) == 1 or R.rank(c) == 13) and r.active(before):
					check(r.turn == before, "ässä tai kuningas antaa lisävuoron")
					extra += 1
			else:
				check(r.playable(r.turn).is_empty(), "antovaiheessa saaja ei voi pelata")
				check(r.giver == r.prev_active(r.turn), "antaja on edellinen pelaaja")
				check(not r.give(r.turn, r.hands[r.turn][0]) or r.turn == r.giver, "vain antaja voi antaa")
				check(r.give(p, r.bot_give(p, rng)), "anto hyväksytään")
				gives += 1
			# Rivin järjestys: 8 vasta 6:n ja 5 vasta 8:n jälkeen.
			for s in 4:
				if r.low[s] > 0:
					check(r.low[s] >= 6 or r.high[s] >= 8 or r.low[s] == 7, "5 tai pienempi vasta 8:n jälkeen")
					check(r.high[s] <= 7 or r.low[s] <= 6, "8 tai suurempi vasta 6:n jälkeen")
			# Kortit säilyvät: kädet + pöydän rivit = 52.
			var n := 0
			for h in r.hands:
				n += h.size()
			for s in 4:
				if r.low[s] > 0:
					n += r.high[s] - r.low[s] + 1
			check(n == 52, "kortteja yhteensä 52 (nyt %d)" % n)
		check(r.finished.size() == 4, "kaikki sijoitettu")
		check(r.points[r.finished[0]] == 0 and r.totals[r.finished[0]] == 0, "voittaja saa 0 pistettä")
		for p in 4:
			check(r.points[p] == r.hands[p].size(), "pisteet = käteen jääneet kortit")
		check(r.moves < R.MAX_MOVES, "peli päättyi sääntöjen mukaan")
		total_moves += r.moves
		wins[r.finished[0]] += 1
		# Verkkomuoto säilyttää tilan.
		var copy := R.new()
		copy.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
		check(copy.to_dict() == r.to_dict(), "tila säilyy JSON-muunnoksessa")
	print("300 peliä, siirtoja keskimäärin %.0f, antoja %d, lisävuoroja %d, voitot %s" % [total_moves / 300.0, gives, extra, wins])
	print("vikoja %d" % fails)
	quit(1 if fails > 0 else 0)
