extends Node3D
## Spartan-rantatennis ylämökin edessä ruohokentällä: koko porukka pelaa yhdessä isoilla puumailoilla, eikä
## vastakkain. Pallo pidetään ilmassa ja lyönnit lasketaan, kunnes pallo osuu maahan. Ennätys on yhteinen
## (user://rantatennis.cfg): joko kaikki voittavat (uusi ennätys) tai kaikki häviävät.
## - Kentällä E aloittaa: tietokoneen hahmot tulevat kentälle omille paikoilleen mailat kädessä.
## - E syöttää ja lyö. Pallo lähtee sille, jota kohti hahmo katsoo. Lyönti onnistuu, kun pallo on mailan
##   ulottuvilla (n. 1,2 m) sopivalla korkeudella; hyvällä korkeudella pallo menee tarkemmin. Keltainen rengas
##   näyttää, mihin omalle vuorolle tuleva pallo putoaa lyöntikorkeudelle.
## - Tietokoneen hahmot juoksevat pallon alle ja lyövät useimmiten; humala heikentää tarkkuutta molemmilla.
## - Kentältä poistuminen lopettaa pelin, ja tietokoneen hahmot palaavat omiin puuhiinsa.
## Moninpelissä mukana ovat tämän koneen pelaaja ja tämän koneen ohjaamat tietokoneen hahmot.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Ai := preload("res://scripts/ai.gd")
const Porukka := preload("res://scripts/porukka.gd")

## Kenttä ylämökin kehyksessä (x pitkin järven puoleista seinää, v järvelle): mökin maanpuoleinen sivu.
const FIELD_C := Vector2(-2.5, -11.0)
const FIELD_H := Vector2(7.0, 4.5)  # puolikkaat leveydet
## Pelipaikat kentän kehyksessä (x, v): salmiakki, naapuriin n. 4,6 m.
const SPOTS := [Vector2(-3.8, 0.0), Vector2(0.0, 2.6), Vector2(3.8, 0.0), Vector2(0.0, -2.6)]
const G := 9.81
const BALL_R := 0.045
const HIT_H := 1.1  # lyöntikorkeus maasta, jolle pallo tähdätään
const REACH := 1.25  # mailan ulottuvuus vaakasuoraan hahmon keskeltä
const LOW := 0.3
const HIGH := 2.4
const SWING_T := 0.4
const LINES_MISS := ["Voi ei!", "Ei se mitään, uusiks!", "Aurinko häikäs.", "Mun moka."]
const LINES_GOOD := ["Hyvä!", "Pidetään pystyssä!", "Nyt menee!", "Tasasta!"]

## Tietokoneen hahmo kentällä: kävelee paikalleen ja juoksee pallon alle samoilla syötteillä kuin pelaaja.
class Brain:
	extends RefCounted
	var body: CharacterBody3D
	var path: Array = []  # reitti kentälle (mökin portaita ylös), sitten goal
	var goal := Vector3.ZERO
	var face := Vector3.ZERO
	var ready := false
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump := false
	var _stuck := 0.0
	var _last := Vector3.ZERO

	func reset() -> void:
		pass

	func think(delta: float) -> void:
		throttle = 0.0
		steer = 0.0
		fast = false
		jump = false
		var p := body.global_position
		var t: Vector3 = path[0] if not path.is_empty() else goal
		var d := Vector2(t.x - p.x, t.z - p.z)
		if d.length() < (0.6 if not path.is_empty() else 0.3):
			_stuck = 0.0
			if not path.is_empty():
				path.pop_front()
				return
			ready = true
			var f := Vector2(face.x - p.x, face.z - p.z)
			if f.length() > 0.1:
				steer = clampf(wrapf(atan2(-f.x, -f.y) - body.rotation.y, -PI, PI) * 2.5, -1.0, 1.0)
			return
		var diff := wrapf(atan2(-d.x, -d.y) - body.rotation.y, -PI, PI)
		steer = clampf(diff * 3.0, -1.0, 1.0)
		throttle = 1.0 if absf(diff) < 0.8 else 0.15
		fast = d.length() > 1.0 and absf(diff) < 0.5 and not body.exhausted
		if Vector2(p.x - _last.x, p.z - _last.z).length() < 0.2 * delta and throttle > 0.5:
			_stuck += delta
		else:
			_stuck = maxf(0.0, _stuck - delta)
		_last = p
		if _stuck > 2.0:
			jump = true
		if _stuck > 5.0:
			body.global_position = t + Vector3.UP * 0.3
			body.velocity = Vector3.ZERO
			_stuck = 0.0


var game: Node3D
var save_path := "user://rantatennis.cfg"  # testit käyttävät omaa tiedostoaan
var active := false
var hits := 0
var record := 0
var players: Array = []  # [{body, i, brain, spot, racket}]
var _state := "idle"  # idle (pallo hukassa, syöttö) | fly | dead (pomppii maassa)
var _ball: MeshInstance3D
var _shadow: MeshInstance3D
var _ring: MeshInstance3D
var _sign: Label3D
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _target: Dictionary = {}  # kenelle pallo on menossa
var _last_hitter: Dictionary = {}
var _will_hit := true
var _dead_t := 0.0
var _swing := {}  # hahmo -> jäljellä oleva lyöntiaika
var _cool := 0.0
var _rng := RandomNumberGenerator.new()


# --- Kenttä ---------------------------------------------------------------------------------------------------

## Kentän kehyksestä (x, v) maailmaan (x, z).
static func fw(x: float, v: float) -> Vector2:
	return Mokki.cw(FIELD_C.x + x, FIELD_C.y + v)


static func local(p: Vector2) -> Vector2:
	return Mokki.wc(p) - FIELD_C


static func in_field(p: Vector3, m := 0.0) -> bool:
	var q := local(Vector2(p.x, p.z))
	return absf(q.x) <= FIELD_H.x + m and absf(q.y) <= FIELD_H.y + m


## Kenttä tasaiseksi (keskikorkeuteen) ja ruohoksi ennen kuin world.gd rakentaa maaston; reunoilla 2 m siirtymä.
static func terraform() -> void:
	var g := Terrain.near
	if g == null:
		return
	var c := fw(0.0, 0.0)
	var r := FIELD_H.length() + 4.0
	var sum := 0.0
	var n := 0
	var nodes := []
	var cls := g.classes.duplicate()
	for j in range(int((c.y - r + g.half) / g.step), int((c.y + r + g.half) / g.step) + 1):
		for i in range(int((c.x - r + g.half) / g.step), int((c.x + r + g.half) / g.step) + 1):
			var p := Vector2(-g.half + i * g.step, -g.half + j * g.step)
			var q := local(p)
			var out := maxf(absf(q.x) - FIELD_H.x, absf(q.y) - FIELD_H.y)
			if out < 3.0:
				nodes.append([j * g.n + i, out])
			if out < 0.0:
				sum += g.heights[j * g.n + i]
				n += 1
			if out < 0.8 and i < g.n - 1 and j < g.n - 1:
				cls[j * (g.n - 1) + i] = Terrain.YARD
	g.classes = cls
	if n == 0:
		return
	var flat := sum / n
	var hs := g.heights
	for e in nodes:
		hs[e[0]] = lerpf(flat, hs[e[0]], smoothstep(1.0, 3.0, e[1]))
	g.heights = hs


## Puut pois kentältä ja sen reunoilta.
static func clears_tree(x: float, z: float) -> bool:
	var c := fw(0.0, 0.0)
	if absf(x - c.x) > 14.0 or absf(z - c.y) > 14.0:
		return false
	return in_field(Vector3(x, 0.0, z), 2.0)


func _ready() -> void:
	_rng.randomize()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		record = int(cfg.get_value("rantatennis", "ennatys", 0))
	_build_field()
	_ball = MeshInstance3D.new()
	_ball.mesh = B.sphere(BALL_R, 12)
	_ball.material_override = B.mat(Color(0.95, 0.9, 0.15))
	_ball.top_level = true
	_ball.visible = false
	add_child(_ball)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = B.cyl(0.07, 0.07, 0.005, 12)
	_shadow.material_override = B.unshaded(Color(0, 0, 0, 0.45))
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow.top_level = true
	_shadow.visible = false
	add_child(_shadow)
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.42
	t.outer_radius = 0.5
	t.rings = 24
	t.ring_segments = 4
	_ring.mesh = t
	_ring.material_override = B.unshaded(Color(1.0, 0.8, 0.1, 0.8))
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.top_level = true
	_ring.visible = false
	add_child(_ring)


## Valkoiset rajat ruohossa ja ennätystaulu kentän laidalla mökin puolella.
func _build_field() -> void:
	var batch := B.Batch.new()
	var white := Color(0.92, 0.92, 0.88)
	var line := func(a: Vector2, b: Vector2) -> void:
		var segs := maxi(1, int(a.distance_to(b) / 1.0))
		for s in segs:
			var p0 := a.lerp(b, float(s) / segs)
			var p1 := a.lerp(b, float(s + 1) / segs)
			var w0 := fw(p0.x, p0.y)
			var w1 := fw(p1.x, p1.y)
			var m := (w0 + w1) * 0.5
			var d := w1 - w0
			batch.add(B.boxm(Vector3(0.06, 0.02, d.length() + 0.06)), Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)),
				Vector3(m.x, Terrain.h(m.x, m.y) + 0.005, m.y)), white)
	var hx := FIELD_H.x - 0.5
	var hv := FIELD_H.y - 0.5
	line.call(Vector2(-hx, -hv), Vector2(hx, -hv))
	line.call(Vector2(hx, -hv), Vector2(hx, hv))
	line.call(Vector2(hx, hv), Vector2(-hx, hv))
	line.call(Vector2(-hx, hv), Vector2(-hx, -hv))
	# Taulu kahdella tolpalla kentän mökin puoleisella laidalla, teksti kentälle päin.
	var bp := fw(-FIELD_H.x + 1.2, FIELD_H.y + 0.4)
	var by := Terrain.h(bp.x, bp.y)
	var bx := Vector3(Mokki.CABIN_X.x, 0, Mokki.CABIN_X.y)
	for s: float in [-0.55, 0.55]:
		batch.add(B.boxm(Vector3(0.07, 1.6, 0.07)), Transform3D(Basis(), Vector3(bp.x, by + 0.8, bp.y) + bx * s),
			Color(0.45, 0.33, 0.2))
	var face := Basis.looking_at(Vector3(Mokki.CABIN_LAKE.x, 0, Mokki.CABIN_LAKE.y))  # teksti kentälle päin
	batch.add(B.boxm(Vector3(1.3, 0.55, 0.04)), Transform3D(face, Vector3(bp.x, by + 1.35, bp.y)), Color(0.18, 0.3, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = batch.commit()
	mi.material_override = B.vcol_mat()
	add_child(mi)
	_sign = B.label(self, "", Vector3(bp.x, by + 1.35, bp.y) + face * Vector3(0, 0, 0.03), 30, Color(1, 0.97, 0.85))
	_sign.basis = face
	_update_sign()


func _update_sign() -> void:
	_sign.text = "RANTATENNIS\nEnnätys %d lyöntiä" % record


# --- Pelin aloitus ja lopetus ---------------------------------------------------------------------------------

func can_start(p: Vector3) -> bool:
	return not active and in_field(p, 0.5) and absf(p.y - Terrain.h(p.x, p.z)) < 0.6


func start() -> void:
	if active:
		return
	active = true
	hits = 0
	_state = "idle"
	players.clear()
	var me: CharacterBody3D = game.player
	var mine := _nearest_spot(me.global_position, [])
	players.append({"body": me, "i": game.player_index, "brain": null, "spot": mine, "racket": _give_racket(me)})
	var taken := [mine]
	for j in game.crew.size():
		if game.crew_modes[j] != "ai":
			continue
		var b: CharacterBody3D = game.crew[j]
		if b.boat != null or taken.size() >= SPOTS.size():
			continue
		var k := _nearest_spot(b.global_position, taken)
		taken.append(k)
		if b.brain != null:
			b.brain.reset()
		if b.pose.begins_with("Sitting"):
			b.stand_up()
		b.pose = ""
		b.set_hidden_inside(false)
		var br := Brain.new()
		br.body = b
		br.goal = _spot_pos(k)
		br.face = _spot_pos(-1)
		br.path = _route_to_field(b)
		b.brain = br
		players.append({"body": b, "i": j, "brain": br, "spot": k, "racket": _give_racket(b)})
	game.toast("Rantatennis! Pidetään pallo ilmassa yhdessä. E syöttää ja lyö.", 4.0)


func stop() -> void:
	if not active:
		return
	active = false
	_state = "idle"
	_ball.visible = false
	_shadow.visible = false
	_ring.visible = false
	for pl in players:
		var b: CharacterBody3D = pl.body
		(pl.racket as Node).queue_free()
		b.body().set_override("upperarm_r", Vector3.RIGHT, 0.0)
		if pl.brain != null and b.brain == pl.brain:
			b.brain = Ai.new(b, game.world.mokki, game.sun, Porukka.CREW[pl.i].name)
	players.clear()
	_swing.clear()


func _spot_pos(k: int) -> Vector3:
	var q: Vector2 = SPOTS[k] if k >= 0 else Vector2.ZERO
	var w := fw(q.x, q.y)
	return Vector3(w.x, Terrain.h(w.x, w.y), w.y)


func _nearest_spot(p: Vector3, taken: Array) -> int:
	var best := -1
	for k in SPOTS.size():
		if taken.has(k):
			continue
		if best < 0 or _spot_pos(k).distance_to(p) < _spot_pos(best).distance_to(p):
			best = k
	return best


## Alhaalta pihasta ja saunalta portaita ylös ylämökin terassille ja sen maanpuoleisesta reunasta kentälle.
func _route_to_field(b: CharacterBody3D) -> Array:
	var p := b.global_position
	var q := local(Vector2(p.x, p.z))
	if p.y > Mokki.floor_y() - 1.5 and q.length() < 30.0:
		return []
	var m: Node3D = game.world.mokki
	var path: Array = m.route(p, "ylamokki_ovi")
	var off := Mokki.cw(3.8, -2.6)
	path.append(Vector3(off.x, Terrain.h(off.x, off.y), off.y))
	return path


## Iso puinen Spartan-maila oikeaan käteen: varsi kämmenestä käsivarren suuntaan, lapa kasvot eteenpäin.
func _give_racket(b: CharacterBody3D) -> Node3D:
	var r := Node3D.new()
	var wood := B.mat(Color(0.74, 0.56, 0.34))
	var face := MeshInstance3D.new()
	face.mesh = B.cyl(0.15, 0.15, 0.014, 20)
	face.material_override = wood
	face.basis = Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(1.0, 1.15, 1.0))
	face.position = Vector3(0, 0.29, 0)
	r.add_child(face)
	var paint := MeshInstance3D.new()
	paint.mesh = B.cyl(0.1, 0.1, 0.016, 20)
	paint.material_override = B.mat(Color(0.1, 0.35, 0.7) if b.get_index() % 2 == 0 else Color(0.75, 0.15, 0.1))
	paint.basis = face.basis
	paint.position = face.position
	r.add_child(paint)
	var grip := MeshInstance3D.new()
	grip.mesh = B.boxm(Vector3(0.035, 0.18, 0.028))
	grip.material_override = B.mat(Color(0.25, 0.18, 0.12))
	grip.position = Vector3(0, 0.06, 0)
	r.add_child(grip)
	var holder := Node3D.new()
	holder.add_child(r)
	r.basis = Basis(Vector3.BACK, -PI * 0.5)
	b.body().attach("hand_r", holder, Vector3(0.06, 0.0, 0.0))
	return holder


# --- Pallo ----------------------------------------------------------------------------------------------------

## E: syöttö tai lyönti (ohi, jos pallo ei ole ulottuvilla).
func act() -> void:
	if not active or _cool > 0.0:
		return
	var me := _me()
	if me.is_empty():
		return
	_cool = 0.35
	_start_swing(me.body)
	if _state == "idle":
		var b: CharacterBody3D = me.body
		var f := -b.global_transform.basis.z
		_pos = b.global_position + Vector3(f.x, 0, f.z) * 0.5 + Vector3.UP * 1.3
		_hit(me, 1.0)
		return
	if _state != "fly":
		return
	var q := _quality(me.body)
	if q > 0.0:
		_hit(me, q)


func _me() -> Dictionary:
	for pl in players:
		if pl.brain == null:
			return pl
	return {}


## Lyönnin laatu 0..1 pallon paikasta hahmoon nähden (0 = ei ulottuvilla).
func _quality(b: CharacterBody3D) -> float:
	var p := b.global_position
	var g := Terrain.h(p.x, p.z)
	var dh := _pos.y - g
	var dx := Vector2(_pos.x - p.x, _pos.z - p.z).length()
	if dx > REACH or dh < LOW or dh > HIGH:
		return 0.0
	var qh := 1.0 - clampf(absf(dh - 1.2) - 0.35, 0.0, 1.0)
	var qx := 1.0 - 0.5 * dx / REACH
	return maxf(0.05, qh * qx)


## Lyönti hahmolta pl: pallo kohti sitä, jota hahmo katsoo (tietokone: satunnainen, useimmiten pelaaja).
func _hit(pl: Dictionary, q: float) -> void:
	var b: CharacterBody3D = pl.body
	var to := _choose_target(pl)
	var sigma: float = 0.2 + (1.0 - q) * 1.1 + b.promille * 0.45
	if pl.brain != null:
		sigma = 0.3 + b.promille * 0.5
	var tb: CharacterBody3D = to.body
	var aim := tb.global_position
	if to.brain != null:
		aim = _spot_pos(to.spot)  # tietokone palaa paikalleen; tähdätään sinne
	if to == pl:
		aim = b.global_position
	aim += Vector3(_rng.randfn(0.0, sigma), 0.0, _rng.randfn(0.0, sigma))
	var dest := Vector3(aim.x, Terrain.h(aim.x, aim.z) + HIT_H, aim.z)
	var dist := Vector2(dest.x - _pos.x, dest.z - _pos.z).length()
	var t := clampf(0.75 + 0.12 * dist, 1.0, 1.7)
	_vel = Vector3((dest.x - _pos.x) / t, (dest.y - _pos.y + 0.5 * G * t * t) / t, (dest.z - _pos.z) / t)
	hits += 1
	_state = "fly"
	_target = to
	_last_hitter = pl
	_will_hit = true
	if to.brain != null:
		var tbody: CharacterBody3D = to.body
		_will_hit = _rng.randf() < clampf(0.93 - tbody.promille * 0.15 - sigma * 0.08, 0.4, 0.97)
	_ball.visible = true
	Sfx.play_on(b, "axe", -14.0, 2.2)
	if hits > 1 and hits % 10 == 0:
		_say(players[_rng.randi() % players.size()], LINES_GOOD[_rng.randi() % LINES_GOOD.size()])


func _choose_target(pl: Dictionary) -> Dictionary:
	var others := players.filter(func(o: Dictionary) -> bool: return o != pl and (o.brain == null or o.brain.ready))
	if others.is_empty():
		return pl
	if pl.brain == null:
		var b: CharacterBody3D = pl.body
		var f := -b.global_transform.basis.z
		var best: Dictionary = others[0]
		var bd := INF
		for o in others:
			var d: Vector3 = (o.body as Node3D).global_position - b.global_position
			var a := absf(Vector2(f.x, f.z).angle_to(Vector2(d.x, d.z)))
			if a < bd:
				bd = a
				best = o
		return best
	var me := _me()
	if not me.is_empty() and others.has(me) and _rng.randf() < 0.5:
		return me
	return others[_rng.randi() % others.size()]


## Pallon putoamiskohta lyöntikorkeudelle (laskeva osa lentoa).
func _landing() -> Vector3:
	var g := Terrain.h(_pos.x, _pos.z) + HIT_H
	var disc := _vel.y * _vel.y + 2.0 * G * (_pos.y - g)
	if disc < 0.0:
		return Vector3(_pos.x, g, _pos.z)
	var t := (_vel.y + sqrt(disc)) / G
	return Vector3(_pos.x + _vel.x * t, g, _pos.z + _vel.z * t)


func _say(pl: Dictionary, text: String) -> void:
	if pl.brain != null and game.chat != null:
		game.chat.show_message(pl.i, text)


func _start_swing(b: CharacterBody3D) -> void:
	_swing[b] = SWING_T


func _physics_process(delta: float) -> void:
	if not active:
		return
	_cool = maxf(0.0, _cool - delta)
	# Mailakäsi: lyönti heilauttaa käsivarren eteen ja ylös.
	for b in _swing.keys():
		_swing[b] -= delta
		var s: float = _swing[b]
		var k := clampf(1.0 - s / SWING_T, 0.0, 1.0)
		(b as CharacterBody3D).body().set_override("upperarm_r", Vector3.RIGHT, sin(k * PI) * 1.4)
		if s <= 0.0:
			_swing.erase(b)
	var me := _me()
	if me.is_empty() or not in_field((me.body as Node3D).global_position, 4.0):
		stop()
		game.toast("Rantatennis loppui. Ennätys %d lyöntiä." % record, 3.0)
		return
	match _state:
		"fly":
			_vel.y -= G * delta
			_pos += _vel * delta
			var land := _landing()
			for pl in players:
				if pl.brain != null:
					(pl.brain as Brain).goal = land if pl == _target else _spot_pos(pl.spot)
					(pl.brain as Brain).face = _spot_pos(-1) if pl == _target else _pos
			_ring.visible = _target == me
			_ring.global_position = Vector3(land.x, Terrain.h(land.x, land.z) + 0.03, land.z)
			# Tietokoneen lyönti, kun pallo laskeutuu ulottuville lyöntikorkeudelle.
			if _target.brain != null and _vel.y < 0.0:
				var tb: CharacterBody3D = _target.body
				var q := _quality(tb)
				var dh := _pos.y - Terrain.h(tb.global_position.x, tb.global_position.z)
				if q > 0.0 and dh < HIT_H + 0.25:
					if _will_hit:
						_start_swing(tb)
						_hit(_target, q)
					elif dh < LOW + 0.1 and not _swing.has(tb):
						_start_swing(tb)  # myöhästynyt lyönti
			var g := Terrain.h(_pos.x, _pos.z)
			if _pos.y - BALL_R <= g:
				_pos.y = g + BALL_R
				_vel = Vector3(_vel.x * 0.5, absf(_vel.y) * 0.45, _vel.z * 0.5)
				_state = "dead"
				_dead_t = 1.6
				_ring.visible = false
				_rally_over()
		"dead":
			_dead_t -= delta
			_vel.y -= G * delta
			_pos += _vel * delta
			var g := Terrain.h(_pos.x, _pos.z)
			if _pos.y - BALL_R <= g:
				_pos.y = g + BALL_R
				_vel = Vector3(_vel.x * 0.6, absf(_vel.y) * 0.4, _vel.z * 0.6)
			if _dead_t <= 0.0:
				_state = "idle"
				_ball.visible = false
				hits = 0
				for pl in players:
					if pl.brain != null:
						(pl.brain as Brain).goal = _spot_pos(pl.spot)
						(pl.brain as Brain).face = _spot_pos(-1)
	_ball.global_position = _pos
	_shadow.visible = _ball.visible
	_shadow.global_position = Vector3(_pos.x, Terrain.h(_pos.x, _pos.z) + 0.01, _pos.z)


## Pallo maahan: kaikki voittavat (uusi ennätys) tai kaikki häviävät.
func _rally_over() -> void:
	if hits > record:
		record = hits
		var cfg := ConfigFile.new()
		cfg.set_value("rantatennis", "ennatys", record)
		cfg.save(save_path)
		_update_sign()
		game.toast("Uusi ennätys: %d lyöntiä! Kaikki voittivat!" % hits, 4.0)
		Sfx.play("pickup", -8.0, 1.2)
	else:
		game.toast("Pallo maahan %d lyönnin jälkeen – kaikki hävisivät. Ennätys %d." % [hits, record], 3.5)
	if _target.get("brain") != null:
		_say(_target, LINES_MISS[_rng.randi() % LINES_MISS.size()])


func prompt() -> String:
	var s := "Rantatennis · %d lyöntiä · ennätys %d · " % [hits, record]
	match _state:
		"idle":
			return s + "E: syötä (pallo lähtee sille, jota kohti katsot)"
		"fly":
			return s + ("E: lyö! Mene keltaiseen renkaaseen" if _target == _me() else "E: lyö")
	return s + "pallo maassa"
