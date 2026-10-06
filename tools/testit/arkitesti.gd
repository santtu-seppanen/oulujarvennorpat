extends SceneTree
## Mökin arjen testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/arkitesti.gd
## - Päikkärit: ylämökin ovi metsän puolella, Santtu nukkuu (kunto täyteen, humala laskee); Jukka ei nuku.
## - Jukan aamukahvit liedellä: vesi kiehuu, purut, pannu pois vaahdon noustessa -> neljä kuppia pöytään;
##   pöytään istuva juo kupin. Muut eivät osaa keittää.
## - Mustikat: metsässä mättäitä; kourallisia syömällä Santun kaari pitenee, mutta jää Markon kaaren alle.
## - Kätköosoitin: kompassi näyttää lähimmän kätkön (saunan takana tai rannan rinteessä).

var main: Node3D
var Mokki: GDScript
var Terrain: GDScript
var fails := 0
var step := 0
var clock := 0.0
var ts := 0.0
var arcs := {}


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Mokki = load("res://scripts/mokki.gd")
	Terrain = load("res://scripts/terrain.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func next() -> void:
	step += 1
	ts = clock


func _put(p: CharacterBody3D, at: Vector3) -> void:
	p.global_position = at + Vector3.UP * 0.05
	p.velocity = Vector3.ZERO


func _process(delta: float) -> bool:
	clock += delta
	if main == null or main.get_script() == null:
		print("VIKA peli ei käynnisty")
		return true
	var t := clock - ts
	var p: CharacterBody3D = main.player
	var m: Node3D = main.world.mokki
	match step:
		0:
			if clock > 2.0:
				for c in main.crew:
					if c != p:
						c.brain = null
						var w: Vector2 = Mokki.yw(-9.5, -2.5 + 1.2 * main.crew.find(c))
						_put(c, Vector3(w.x, Mokki.DY, w.y))
				# Ovi metsän puolella: oven edusta on järven puolta kauempana järvestä kuin mökin keskipiste.
				var d: Vector3 = Mokki.cabin_door()
				var lake_side: float = Mokki.wc(Vector2(d.x, d.z)).y
				check(lake_side < -Mokki.CABIN_HV, "ylämökin ovi metsän puolella (v %.2f)" % lake_side)
				p.promille = 2.0
				p.stamina = 20.0
				_put(p, d)
				next()
		1:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("päikkärit"), "päikkärikehote: %s" % it.get("text", ""))
				it.cb.call()
				check(p.hidden_inside and not p.controls_enabled, "nukkumassa sisällä")
				next()
		2:
			if t > main.NAP_T + 0.5:
				check(not p.hidden_inside and p.controls_enabled and main._nap_t <= 0.0, "heräsi päikkäreiltä")
				check(p.stamina >= 99.0 and p.promille < 1.0, "kunto täynnä, humala laskenut (%.1f ‰)" % p.promille)
				main.choose_character(3)  # Jukka
				next()
		3:
			if t > 0.5:
				p = main.player
				for c in main.crew:
					if c != p:
						c.brain = null
				_put(p, Mokki.cabin_door())
				next()
		4:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(not it.has("cb") and str(it.get("text", "")).contains("Jukka ei nuku"), "Jukka ei nuku: %s" % it.get("text", ""))
				_put(p, m.cook_spot)
				next()
		5:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(str(it.get("text", "")).contains("aamukahvit"), "kahvikehote: %s" % it.get("text", ""))
				it.cb.call()
				check(main.activity == "kahvi", "kahvinkeitto alkoi")
				main.kahvi.act()  # pannu liedelle
				next()
		6:
			if main.kahvi._p >= 0.85:
				main.kahvi.act()  # purut
				next()
			elif t > 15.0:
				check(false, "vesi ei kiehunut")
				next()
		7:
			if main.kahvi._p >= 0.75:
				var before: int = main.kahvi.kupit
				main.kahvi.act()  # pannu pois
				check(main.kahvi.kupit == before + 4, "täydellinen pannukahvi: %d kuppia" % main.kahvi.kupit)
				main.end_activity()
				next()
			elif t > 10.0:
				check(false, "vaahto ei noussut")
				next()
		8:
			if t > 0.5:
				p.promille = 1.0
				var n: int = main.kahvi.kupit
				main.kahvi.drink()
				check(main.kahvi.kupit == n - 1 and p.promille < 0.75, "kahvikupista humala laskee")
				main.choose_character(0)  # Santtu
				next()
		9:
			# Muut eivät osaa keittää.
			if t > 0.5:
				p = main.player
				_put(p, m.cook_spot)
				next()
		10:
			if t > 0.5:
				var it: Dictionary = main._interaction()
				check(not it.has("cb") and str(it.get("text", "")).contains("Jukka keittää"), "Santtu ei keitä: %s" % it.get("text", ""))
				var bushes: Array = main.mustikat.bushes
				print("mustikkamättäitä %d" % bushes.size())
				check(bushes.size() >= 25, "metsässä mustikkamättäitä")
				arcs["ennen"] = _arc(p)
				next()
		11:
			# Syödään kourallisia eri mättäistä, kunnes mustikkavoima on täynnä.
			var bushes: Array = main.mustikat.bushes
			var n: int = main.mustikat.eaten.get(0, 0)
			if n < main.Mustikat.MAX:
				for b in bushes:
					if b.t <= 0.0:
						_put(p, b.p)
						break
				if t > 0.2:
					var it: Dictionary = main._interaction()
					if str(it.get("text", "")).contains("mustikoita"):
						it.cb.call()
					ts = clock
			else:
				check(true, "söi %d kourallista mustikoita" % n)
				next()
		12:
			if t > 0.3:
				arcs["jalkeen"] = _arc(p)
				_put(p, m.points.piha)  # pois Markon suihkun tieltä
				main.choose_character(1)
				next()
		13:
			if t > 0.5:
				arcs["marko"] = _arc(main.player)
				print("kaari Santtu ennen %.2f m, mustikoiden jälkeen %.2f m, Marko %.2f m" % [arcs.ennen, arcs.jalkeen, arcs.marko])
				check(arcs.jalkeen > arcs.ennen + 0.6, "mustikat pidentävät kaarta")
				check(arcs.jalkeen < arcs.marko - 0.5, "Markon kaari on silti komein")
				main.choose_character(0)
				next()
		14:
			if t > 0.5:
				p = main.player
				_put(p, m.points.sauna_ovi)
				main._update_hud()
				var c: Vector2 = main._compass.cache
				check(c.distance_to(Vector2(m.stash_pos.x, m.stash_pos.z)) < 0.1, "osoitin saunalla: saunan takana oleva kätkö")
				var rs: Vector3 = main.world.ranta.stash_pos
				_put(p, rs + Vector3(-15, 0, 0))
				main._update_hud()
				c = main._compass.cache
				check(c.distance_to(Vector2(rs.x, rs.z)) < 0.1, "osoitin rannalla: rannan kätkö (%s)" % main._compass.cache_text)
				# Saunan kätkö: rinteessä takakulun takana, oven edustalta ei ylety.
				_put(p, m.points.sauna_ovi)
				check(not main._near_stash(), "saunan kätkö ei näy oven edustalle")
				_put(p, m.stash_pos)
				check(main._near_stash() and main._interaction().get("text", "").begins_with("E: kylmä olut"), "saunan kätkö takakulusta")
				var q: Vector2 = Mokki.wy(Vector2(m.stash_pos.x, m.stash_pos.z))
				check(q.y < Mokki.BACK, "kätkö saunan takana (v %.2f)" % q.y)
				print("vikoja %d" % fails)
				return true
	if clock > 200.0:
		check(false, "aikaraja (vaihe %d)" % step)
		return true
	return false


## Kaaren pituus suoraan pitkospuiden alusta alamäkeen: pissa käynnissä hetki täydellä paineella.
func _arc(p: CharacterBody3D) -> float:
	var q: Vector2 = Mokki.PEE_SPOT
	var w: Vector2 = Mokki.yw(q.x, q.y)
	p.global_position = Vector3(w.x, Mokki.duck_y(q, 2.0) + 0.1, w.y)
	var d: Vector2 = Mokki.EAST * 0.8 + Mokki.LAKE * 0.6
	p.rotation.y = atan2(-d.x, -d.y)
	p.velocity = Vector3.ZERO
	var ps: Node3D = main.pissa
	ps.start()
	ps._t = 1.0
	var best := 0.0
	for k in 60:
		ps._physics_process(1.0 / 60.0)
		best = maxf(best, ps._mine.dist)
	ps.stop()
	return best
