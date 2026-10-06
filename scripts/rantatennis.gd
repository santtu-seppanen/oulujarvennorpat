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
## Moninpeli: kaikki pelaavat samaa peliä samalla pallolla. Host pitää kirjaa osallistujista (tn_join,
## tn_leave -> tn_state) ja ohjaa tietokoneen hahmoja. Jokainen lyönti lähetetään kaikille (tn_hit: paikka,
## nopeus, lyöjä, kohde ja lyöntien määrä), ja kukin kone laskee saman lentoradan itse. Pallon putoamisen
## maahan ratkaisee pallon kohteen ohjaaja (tn_miss): pelaajan oma kone tai tietokoneen hahmolla host. Pallo
## näkyy myös niille, jotka eivät pelaa.

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
var session := false  # peli käynnissä (joku pelaa)
var active := false  # oma pelaaja on mukana
var hits := 0
var record := 0
var spots := {}  # hahmon indeksi -> pelipaikka (hostilta)
var players: Array = []  # [{i, body, spot, racket}]
var _brains := {}  # tämän koneen ohjaamat tietokoneen hahmot kentällä: indeksi -> Brain
var _state := "idle"  # idle (syöttö) | fly | wait (maassa, odotetaan kohteen konetta) | dead (pomppii maassa)
var _ball: MeshInstance3D
var _shadow: MeshInstance3D
var _ring: MeshInstance3D
var _sign: Label3D
var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _target_i := -1  # kenelle pallo on menossa
var _hitter_i := -1
var _rally := 0  # rallin tunnus (syöttäjän arpoma), vanhentuneet viestit ohitetaan
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
	var mp: Node = game.mp
	mp.on("tn_join", func(d: Dictionary, _from: int) -> void:
		if _host():
			record = maxi(record, int(d.get("rec", 0)))
			_add_human(int(d.i))
			_commit())
	mp.on("tn_leave", func(d: Dictionary, _from: int) -> void:
		if _host():
			_remove(int(d.i))
			_commit())
	mp.on("tn_state", func(d: Dictionary, from: int) -> void:
		if from == mp.net.host_id:
			_apply_state(d))
	mp.on("tn_hit", func(d: Dictionary, _from: int) -> void: _on_hit(d))
	mp.on("tn_miss", func(d: Dictionary, _from: int) -> void: _on_miss(d))


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


# --- Osallistujat: host pitää kirjaa (yksinpelissä tämä kone) -------------------------------------------------

func can_start(p: Vector3) -> bool:
	return not active and in_field(p, 0.5) and absf(p.y - Terrain.h(p.x, p.z)) < 0.6


## Oma pelaaja mukaan: hostilla suoraan, muilla pyyntö hostille.
func start() -> void:
	if active:
		return
	var i: int = game.player_index
	if _host():
		_add_human(i)
		_commit()
	else:
		game.mp.send({"t": "tn_join", "i": i, "rec": record, "to": game.mp.net.host_id})


## Oma pelaaja pois pelistä (kentältä poistuminen, hahmon vaihto).
func stop() -> void:
	if not active:
		return
	var i: int = game.player_index
	if _host():
		_remove(i)
		_commit()
	else:
		spots.erase(i)
		_sync_players()
		game.mp.send({"t": "tn_leave", "i": i, "to": game.mp.net.host_id})


func _host() -> bool:
	return not game.mp.online() or game.mp.net.is_host()


## Tämä kone ohjaa hahmoa i (oma pelaaja tai tämän koneen tietokone): se ratkaisee, lyökö i pallon.
func _owns(i: int) -> bool:
	return i >= 0 and game.crew_modes[i] in ["player", "ai"]


func _human(i: int) -> bool:
	return game.crew_modes[i] != "ai"


## Host: ihminen i peliin. Ensimmäinen aloittaa pelin, ja tietokoneen hahmot tulevat mukaan.
func _add_human(i: int) -> void:
	if not session:
		session = true
		hits = 0
		_state = "idle"
		spots.clear()
	if not spots.has(i):
		spots[i] = _nearest_spot((game.crew[i] as Node3D).global_position, spots.values())
	for j in game.crew.size():
		if spots.has(j) or game.crew_modes[j] != "ai" or (game.crew[j] as CharacterBody3D).boat != null:
			continue
		var k := _nearest_spot((game.crew[j] as Node3D).global_position, spots.values())
		if k >= 0:
			spots[j] = k


## Host: ihminen i pois. Kun ihmisiä ei enää ole, peli loppuu.
func _remove(i: int) -> void:
	spots.erase(i)
	for j in spots:
		if _human(j):
			return
	session = false
	spots.clear()


## Host: osallistujat käyttöön ja kaikille.
func _commit() -> void:
	_sync_players()
	var o := {}
	for i in spots:
		o[str(i)] = spots[i]
	game.mp.send({"t": "tn_state", "on": session, "s": o, "rec": record, "h": hits})


func _apply_state(d: Dictionary) -> void:
	session = bool(d.on)
	spots.clear()
	for k in d.s:
		spots[int(k)] = int(d.s[k])
	if int(d.rec) > record:
		_set_record(int(d.rec))
	if not session:
		_state = "idle"
	_sync_players()


## Osallistujalista (mailat käteen ja pois) ja tämän koneen tietokoneen hahmojen ohjaus pelipaikkojen mukaan.
func _sync_players() -> void:
	for pl in players.duplicate():
		if spots.get(pl.i, -1) != pl.spot:
			_drop(pl)
	for i in spots:
		if not players.any(func(pl: Dictionary) -> bool: return pl.i == i):
			var b: CharacterBody3D = game.crew[i]
			players.append({"i": i, "body": b, "spot": spots[i], "racket": _give_racket(b)})
	_update_brains()
	var was := active
	active = session and spots.has(game.player_index)
	if active and not was:
		game.toast("Rantatennis! Pidetään pallo ilmassa yhdessä. E syöttää ja lyö.", 4.0)
	elif was and not active:
		game.toast("Rantatennis loppui. Ennätys %d lyöntiä." % record, 3.0)
	if not session:
		_ball.visible = false
		_shadow.visible = false
		_ring.visible = false
		_swing.clear()


func _drop(pl: Dictionary) -> void:
	var b: CharacterBody3D = pl.body
	(pl.racket as Node).queue_free()
	b.body().set_override("upperarm_r", Vector3.RIGHT, 0.0)
	_swing.erase(b)
	players.erase(pl)


## Tämän koneen tietokoneen hahmot kentälle (Brain) ja kentältä takaisin omiin puuhiinsa (ai.gd).
func _update_brains() -> void:
	for i in _brains.keys():
		var b: CharacterBody3D = game.crew[i]
		if spots.has(i) and game.crew_modes[i] == "ai" and b.brain == _brains[i]:
			continue
		if b.brain == _brains[i] and game.crew_modes[i] == "ai":
			b.brain = Ai.new(b, game.world.mokki, game.sun, Porukka.CREW[i].name)
		_brains.erase(i)
	for pl in players:
		var i: int = pl.i
		var b: CharacterBody3D = pl.body
		if game.crew_modes[i] != "ai" or _brains.has(i):
			continue
		if b.brain != null:
			b.brain.reset()
		if b.pose.begins_with("Sitting"):
			b.stand_up()
		b.pose = ""
		b.set_hidden_inside(false)
		var br := Brain.new()
		br.body = b
		br.goal = _spot_pos(pl.spot)
		br.face = _spot_pos(-1)
		br.path = _route_to_field(b)
		b.brain = br
		_brains[i] = br


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
	return _player(game.player_index)


func _player(i: int) -> Dictionary:
	for pl in players:
		if pl.i == i:
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


## Lyönti tällä koneella ohjattavalta hahmolta pl: lentorata kohti sitä, jota hahmo katsoo (tietokone:
## satunnainen, usein ihminen), ja sama lyönti kaikille.
func _hit(pl: Dictionary, q: float) -> void:
	var b: CharacterBody3D = pl.body
	var to := _choose_target(pl)
	var sigma: float = 0.2 + (1.0 - q) * 1.1 + b.promille * 0.45
	if _brains.has(pl.i):
		sigma = 0.3 + b.promille * 0.5
	var tb: CharacterBody3D = to.body
	var aim := tb.global_position
	if not _human(to.i):
		aim = _spot_pos(to.spot)  # tietokone palaa paikalleen; tähdätään sinne
	if to.i == pl.i:
		aim = b.global_position
	aim += Vector3(_rng.randfn(0.0, sigma), 0.0, _rng.randfn(0.0, sigma))
	var dest := Vector3(aim.x, Terrain.h(aim.x, aim.z) + HIT_H, aim.z)
	var dist := Vector2(dest.x - _pos.x, dest.z - _pos.z).length()
	var t := clampf(0.75 + 0.12 * dist, 1.0, 1.7)
	var v := Vector3((dest.x - _pos.x) / t, (dest.y - _pos.y + 0.5 * G * t * t) / t, (dest.z - _pos.z) / t)
	var n := 1 if _state == "idle" else hits + 1
	var r := _rng.randi_range(1, 1 << 30) if n == 1 else _rally
	_launch(pl.i, to.i, _pos, v, n, r)
	game.mp.send({"t": "tn_hit", "r": r, "n": n, "by": pl.i, "k": to.i,
		"p": [_pos.x, _pos.y, _pos.z], "v": [v.x, v.y, v.z]})


## Pallo lentoon lyönnistä (oma tai toisen koneen): kaikki koneet laskevat saman radan.
func _launch(by: int, to: int, p: Vector3, v: Vector3, n: int, r: int) -> void:
	_pos = p
	_vel = v
	hits = n
	_rally = r
	_state = "fly"
	_target_i = to
	_hitter_i = by
	_ball.visible = true
	var hb: CharacterBody3D = game.crew[by]
	if by != game.player_index:
		_start_swing(hb)
	_will_hit = true
	if _brains.has(to):
		var tbody: CharacterBody3D = game.crew[to]
		_will_hit = _rng.randf() < clampf(0.93 - tbody.promille * 0.15 - 0.03 * float(hb.promille), 0.4, 0.97)
	Sfx.play_on(hb, "axe", -14.0, 2.2)
	if n > 1 and n % 10 == 0:
		var ai := players.filter(func(o: Dictionary) -> bool: return not _human(o.i))
		if not ai.is_empty():
			_say(ai[n / 10 % ai.size()], LINES_GOOD[n / 10 % LINES_GOOD.size()])


func _on_hit(d: Dictionary) -> void:
	var n := int(d.n)
	var r := int(d.r)
	var by := int(d.by)
	var to := int(d.k)  # "to" on verkossa vastaanottaja
	if not session or not spots.has(by) or not spots.has(to):
		return
	if n > 1 and (r != _rally or n <= hits):
		return  # vanha tai toisen rallin lyönti
	var p: Array = d.p
	var v: Array = d.v
	_launch(by, to, Vector3(p[0], p[1], p[2]), Vector3(v[0], v[1], v[2]), n, r)


func _on_miss(d: Dictionary) -> void:
	if not session or int(d.r) != _rally or not _state in ["fly", "wait"]:
		return
	hits = int(d.n)
	_drop_ball()
	_rally_over()


func _choose_target(pl: Dictionary) -> Dictionary:
	var others := players.filter(func(o: Dictionary) -> bool:
		return o.i != pl.i and (not _brains.has(o.i) or _brains[o.i].ready) and in_field((o.body as Node3D).global_position, 1.0))
	if others.is_empty():
		return pl
	if _human(pl.i):
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
	var humans := others.filter(func(o: Dictionary) -> bool: return _human(o.i))
	if not humans.is_empty() and _rng.randf() < 0.5:
		return humans[_rng.randi() % humans.size()]
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
	if game.chat != null:
		game.chat.show_message(pl.i, text)


func _start_swing(b: CharacterBody3D) -> void:
	_swing[b] = SWING_T


func _physics_process(delta: float) -> void:
	if not session:
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
	if active and not in_field(game.player.global_position, 4.0):
		stop()
		if not session:
			return
	if _host():
		_update_brains()  # hahmo vapautui tai varattiin kesken pelin
	match _state:
		"fly":
			_vel.y -= G * delta
			_pos += _vel * delta
			var land := _landing()
			for i in _brains:
				var pl := _player(i)
				var br: Brain = _brains[i]
				br.goal = land if i == _target_i else _spot_pos(pl.spot)
				br.face = _spot_pos(-1) if i == _target_i else _pos
			_ring.visible = _target_i == game.player_index and active
			_ring.global_position = Vector3(land.x, Terrain.h(land.x, land.z) + 0.03, land.z)
			# Tietokoneen lyönti, kun pallo laskeutuu ulottuville lyöntikorkeudelle.
			if _brains.has(_target_i) and _vel.y < 0.0:
				var tb: CharacterBody3D = game.crew[_target_i]
				var q := _quality(tb)
				var dh := _pos.y - Terrain.h(tb.global_position.x, tb.global_position.z)
				if q > 0.0 and dh < HIT_H + 0.25:
					if _will_hit:
						_start_swing(tb)
						_hit(_player(_target_i), q)
					elif dh < LOW + 0.1 and not _swing.has(tb):
						_start_swing(tb)  # myöhästynyt lyönti
			var g := Terrain.h(_pos.x, _pos.z)
			if _state == "fly" and _pos.y - BALL_R <= g:
				_ring.visible = false
				if _owns(_target_i) or not spots.has(_target_i):
					_drop_ball()
					_rally_over()
					game.mp.send({"t": "tn_miss", "r": _rally, "n": hits})
				else:
					# Kohteen kone ratkaisee: lyönti voi vielä tulla verkosta.
					_pos.y = g + BALL_R
					_state = "wait"
					_dead_t = 2.5
		"wait":
			_dead_t -= delta
			if _dead_t <= 0.0:
				_drop_ball()
				_rally_over()  # viesti ei tullut perille
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
				for i in _brains:
					(_brains[i] as Brain).goal = _spot_pos(_player(i).spot)
					(_brains[i] as Brain).face = _spot_pos(-1)
	_ball.global_position = _pos
	_shadow.visible = _ball.visible
	_shadow.global_position = Vector3(_pos.x, Terrain.h(_pos.x, _pos.z) + 0.01, _pos.z)


## Pallo pomppii maassa hetken, sitten syöttövuoro.
func _drop_ball() -> void:
	var g := Terrain.h(_pos.x, _pos.z)
	_pos.y = maxf(_pos.y, g + BALL_R)
	_vel = Vector3(_vel.x * 0.5, absf(_vel.y) * 0.45, _vel.z * 0.5)
	_state = "dead"
	_dead_t = 1.6
	_ring.visible = false


func _set_record(n: int) -> void:
	record = n
	var cfg := ConfigFile.new()
	cfg.set_value("rantatennis", "ennatys", record)
	cfg.save(save_path)
	_update_sign()


## Pallo maahan: kaikki voittavat (uusi ennätys) tai kaikki häviävät.
func _rally_over() -> void:
	if hits > record:
		_set_record(hits)
		game.toast("Uusi ennätys: %d lyöntiä! Kaikki voittivat!" % hits, 4.0)
		Sfx.play("pickup", -8.0, 1.2)
	else:
		game.toast("Pallo maahan %d lyönnin jälkeen – kaikki hävisivät. Ennätys %d." % [hits, record], 3.5)
	var pl := _player(_target_i)
	if not pl.is_empty() and not _human(pl.i):
		_say(pl, LINES_MISS[hits % LINES_MISS.size()])


func prompt() -> String:
	var s := "Rantatennis · %d lyöntiä · ennätys %d · " % [hits, record]
	match _state:
		"idle":
			return s + "E: syötä (pallo lähtee sille, jota kohti katsot)"
		"fly":
			return s + ("E: lyö! Mene keltaiseen renkaaseen" if _target_i == game.player_index else "E: lyö")
	return s + "pallo maassa"
