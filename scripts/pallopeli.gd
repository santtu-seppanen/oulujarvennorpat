extends Node3D
## Yhteinen pallopeli, jota pelataan yhdessä eikä vastakkain: pallo pidetään ilmassa, ja lyönnit tai heitot
## lasketaan, kunnes pallo putoaa maahan tai veteen. Ennätys on yhteinen: joko kaikki voittavat (uusi ennätys)
## tai kaikki häviävät. Lajit perivät tämän: rantatennis.gd (ruohokenttä ylämökin edessä, mailat) ja
## amerikanpallo.gd (heittely vedessä alamökin edustalla).
## - Alueella E aloittaa: tietokoneen hahmot tulevat omille paikoilleen.
## - E syöttää ja lyö (tai heittää ja ottaa kiinni). Pallo lähtee sille, jota kohti hahmo katsoo. Onnistuu, kun
##   pallo on ulottuvilla sopivalla korkeudella; hyvällä korkeudella pallo menee tarkemmin. Keltainen rengas
##   näyttää, mihin omalle vuorolle tuleva pallo putoaa.
## - Tietokoneen hahmot menevät pallon alle ja onnistuvat useimmiten; humala heikentää tarkkuutta kaikilla.
## - F tai alueelta poistuminen lopettaa pelin, ja tietokoneen hahmot palaavat omiin puuhiinsa.
## Moninpeli: host pitää kirjaa osallistujista (<msg>_join, <msg>_leave -> <msg>_state) ja ohjaa tietokoneen
## hahmoja. Jokainen lyönti lähetetään kaikille (<msg>_hit: paikka, nopeus, lyöjä, kohde ja määrä), ja kukin
## kone laskee saman lentoradan itse. Pallon putoamisen ratkaisee pallon kohteen ohjaaja (<msg>_miss): pelaajan
## oma kone tai tietokoneen hahmolla host. Pallo näkyy myös niille, jotka eivät pelaa.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Ai := preload("res://scripts/ai.gd")
const Porukka := preload("res://scripts/porukka.gd")

const G := 9.81
const SWING_T := 0.4

## Tietokoneen hahmo pelissä: kävelee paikalleen ja juoksee (tai kahlaa) pallon alle samoilla syötteillä kuin
## pelaaja.
class Brain:
	extends RefCounted
	var body: CharacterBody3D
	var path: Array = []  # reitti alueelle, sitten goal
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


# --- Lajin asetukset (aliluokka asettaa _init:ssä) --------------------------------------------------------------

var title := "Pallopeli"
var msg := "pp"  # viestien etuliite
var section := "pallopeli"  # ennätyksen avain tiedostossa
var unit := "lyöntiä"
var unit_gen := "lyönnin"  # "... 12 lyönnin jälkeen"
var serve_text := "E: syötä (pallo lähtee sille, jota kohti katsot)"
var hit_verb := "lyö"
var fall_text := "Pallo maahan"
var start_text := "Pidetään pallo ilmassa yhdessä. E syöttää ja lyö."
var ball_r := 0.045
var hit_h := 1.1  # tähtäyskorkeus jalkojen tasosta
var reach := 1.25  # ulottuvuus vaakasuoraan hahmon keskeltä
var low := 0.3
var high := 2.4
var sweet := 1.2  # paras korkeus jalkojen tasosta
var swing_amp := 1.4  # olkavarren heilahdus (rad)
var flight := Vector3(0.75, 0.12, 0.0)  # lentoaika: perus + metriä kohden, ...
var flight_min := 1.0
var flight_max := 1.7
var hit_sound := ["axe", -14.0, 2.2]
var lines_miss := ["Voi ei!", "Ei se mitään, uusiks!", "Aurinko häikäs.", "Mun moka."]
var lines_good := ["Hyvä!", "Pidetään pystyssä!", "Nyt menee!", "Tasasta!"]

# --- Tila ------------------------------------------------------------------------------------------------------

var game: Node3D
var save_path := "user://pallopeli.cfg"  # testit käyttävät omaa tiedostoaan
var session := false  # peli käynnissä (joku pelaa)
var active := false  # oma pelaaja on mukana
var hits := 0
var record := 0
var spots := {}  # hahmon indeksi -> pelipaikka (hostilta)
var players: Array = []  # [{i, body, spot, item}]
var _brains := {}  # tämän koneen ohjaamat tietokoneen hahmot pelissä: indeksi -> Brain
var _state := "idle"  # idle (syöttö) | fly | wait (maassa, odotetaan kohteen konetta) | dead (pallo maassa)
var _ball: Node3D
var _shadow: MeshInstance3D
var _ring: MeshInstance3D
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


# --- Lajin koukut (aliluokka ylikirjoittaa) --------------------------------------------------------------------

## Pelipaikan k maailmanpaikka jalkojen tasolla (k = -1: alueen keskipiste).
func _spot_pos(_k: int) -> Vector3:
	return Vector3.ZERO


func spot_count() -> int:
	return 4


## Onko p pelialueella (marginaalilla m).
func in_area(_p: Vector3, _m := 0.0) -> bool:
	return false


func can_start(p: Vector3) -> bool:
	return not active and in_area(p, 0.5)


## Reitti alueelle tietokoneen hahmolle (mokki.gd reittipisteet), tyhjä jos ollaan jo lähellä.
func _route_to(_b: CharacterBody3D) -> Array:
	return []


## Väline käteen (maila) tai null.
func _give_item(_b: CharacterBody3D) -> Node3D:
	return null


## Pinta, johon pallo putoaa (maa tai veden pinta).
func _ground(x: float, z: float) -> float:
	return Terrain.h(x, z)


## Hahmon jalkojen taso (ulottuvuus mitataan tästä).
func _feet(b: CharacterBody3D) -> float:
	return Terrain.h(b.global_position.x, b.global_position.z)


func _make_ball() -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = B.sphere(ball_r, 12)
	mi.material_override = B.mat(Color(0.95, 0.9, 0.15))
	return mi


## Pallon asento lennossa (esim. kierre).
func _orient_ball(_delta: float) -> void:
	pass


## Pallo putosi: pomppu maassa tai kellunta vedessä.
func _dead_motion(delta: float) -> void:
	_vel.y -= G * delta
	_pos += _vel * delta
	var g := _ground(_pos.x, _pos.z)
	if _pos.y - ball_r <= g:
		_pos.y = g + ball_r
		_vel = Vector3(_vel.x * 0.6, absf(_vel.y) * 0.4, _vel.z * 0.6)


func _on_record() -> void:
	pass


# --- Rakentaminen ----------------------------------------------------------------------------------------------

func _ready() -> void:
	_rng.randomize()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		record = int(cfg.get_value(section, "ennatys", 0))
	_ball = _make_ball()
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
	mp.on(msg + "_join", func(d: Dictionary, _from: int) -> void:
		if _host():
			record = maxi(record, int(d.get("rec", 0)))
			_add_human(int(d.i))
			_commit())
	mp.on(msg + "_leave", func(d: Dictionary, _from: int) -> void:
		if _host():
			_remove(int(d.i))
			_commit())
	mp.on(msg + "_state", func(d: Dictionary, from: int) -> void:
		if from == mp.net.host_id:
			_apply_state(d))
	mp.on(msg + "_hit", func(d: Dictionary, _from: int) -> void: _on_hit(d))
	mp.on(msg + "_miss", func(d: Dictionary, _from: int) -> void: _on_miss(d))


# --- Osallistujat: host pitää kirjaa (yksinpelissä tämä kone) -------------------------------------------------

## Oma pelaaja mukaan: hostilla suoraan, muilla pyyntö hostille.
func start() -> void:
	if active:
		return
	var i: int = game.player_index
	if _host():
		_add_human(i)
		_commit()
	else:
		game.mp.send({"t": msg + "_join", "i": i, "rec": record, "to": game.mp.net.host_id})


## Oma pelaaja pois pelistä (F, alueelta poistuminen, hahmon vaihto).
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
		game.mp.send({"t": msg + "_leave", "i": i, "to": game.mp.net.host_id})


func _host() -> bool:
	return not game.mp.online() or game.mp.net.is_host()


## Tämä kone ohjaa hahmoa i (oma pelaaja tai tämän koneen tietokone): se ratkaisee, onnistuuko i.
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
		var b: CharacterBody3D = game.crew[j]
		if spots.has(j) or game.crew_modes[j] != "ai" or b.boat != null:
			continue
		if b.hidden_inside:
			continue  # päikkäreillä tai huussissa
		var k := _nearest_spot(b.global_position, spots.values())
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
	game.mp.send({"t": msg + "_state", "on": session, "s": o, "rec": record, "h": hits})


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


## Osallistujalista (välineet käteen ja pois) ja tämän koneen tietokoneen hahmojen ohjaus pelipaikkojen mukaan.
func _sync_players() -> void:
	for pl in players.duplicate():
		if spots.get(pl.i, -1) != pl.spot:
			_drop(pl)
	for i in spots:
		if not players.any(func(pl: Dictionary) -> bool: return pl.i == i):
			var b: CharacterBody3D = game.crew[i]
			players.append({"i": i, "body": b, "spot": spots[i], "item": _give_item(b)})
	_update_brains()
	var was := active
	active = session and spots.has(game.player_index)
	if active and not was:
		game.toast("%s! %s" % [title, start_text], 4.0)
	elif was and not active:
		game.toast("%s loppui. Ennätys %d %s." % [title, record, unit], 3.0)
	if not session:
		_ball.visible = false
		_shadow.visible = false
		_ring.visible = false
		_swing.clear()


func _drop(pl: Dictionary) -> void:
	var b: CharacterBody3D = pl.body
	if pl.item != null:
		(pl.item as Node).queue_free()
	b.body().set_override("upperarm_r", Vector3.RIGHT, 0.0)
	_swing.erase(b)
	players.erase(pl)


## Tämän koneen tietokoneen hahmot peliin (Brain) ja pelistä takaisin omiin puuhiinsa (ai.gd).
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
		br.path = _route_to(b)
		b.brain = br
		_brains[i] = br


func _nearest_spot(p: Vector3, taken: Array) -> int:
	var best := -1
	for k in spot_count():
		if taken.has(k):
			continue
		if best < 0 or _spot_pos(k).distance_to(p) < _spot_pos(best).distance_to(p):
			best = k
	return best


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
		_pos = Vector3(b.global_position.x, _feet(b), b.global_position.z) + Vector3(f.x, 0, f.z) * 0.5 + Vector3.UP * sweet
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


## Onnistumisen laatu 0..1 pallon paikasta hahmoon nähden (0 = ei ulottuvilla).
func _quality(b: CharacterBody3D) -> float:
	var p := b.global_position
	var dh := _pos.y - _feet(b)
	var dx := Vector2(_pos.x - p.x, _pos.z - p.z).length()
	if dx > reach or dh < low or dh > high:
		return 0.0
	var qh := 1.0 - clampf(absf(dh - sweet) - 0.35, 0.0, 1.0)
	var qx := 1.0 - 0.5 * dx / reach
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
	var dest := Vector3(aim.x, Terrain.h(aim.x, aim.z) + hit_h, aim.z)
	var dist := Vector2(dest.x - _pos.x, dest.z - _pos.z).length()
	var t := clampf(flight.x + flight.y * dist, flight_min, flight_max)
	var v := Vector3((dest.x - _pos.x) / t, (dest.y - _pos.y + 0.5 * G * t * t) / t, (dest.z - _pos.z) / t)
	var n := 1 if _state == "idle" else hits + 1
	var r := _rng.randi_range(1, 1 << 30) if n == 1 else _rally
	_launch(pl.i, to.i, _pos, v, n, r)
	game.mp.send({"t": msg + "_hit", "r": r, "n": n, "by": pl.i, "k": to.i,
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
	Sfx.play_on(hb, hit_sound[0], hit_sound[1], hit_sound[2])
	if n > 1 and n % 10 == 0:
		var ai := players.filter(func(o: Dictionary) -> bool: return not _human(o.i))
		if not ai.is_empty():
			_say(ai[n / 10 % ai.size()], lines_good[n / 10 % lines_good.size()])


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
		return o.i != pl.i and (not _brains.has(o.i) or _brains[o.i].ready) and in_area((o.body as Node3D).global_position, 1.0))
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


## Pallon putoamiskohta tähtäyskorkeudelle (laskeva osa lentoa).
func _landing() -> Vector3:
	var g := Terrain.h(_pos.x, _pos.z) + hit_h
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
	# Lyöntikäsi heilahtaa eteen ja ylös.
	for b in _swing.keys():
		_swing[b] -= delta
		var s: float = _swing[b]
		var k := clampf(1.0 - s / SWING_T, 0.0, 1.0)
		(b as CharacterBody3D).body().set_override("upperarm_r", Vector3.RIGHT, sin(k * PI) * swing_amp)
		if s <= 0.0:
			_swing.erase(b)
	if active and not in_area(game.player.global_position, 4.0):
		stop()
		if not session:
			return
	if _host():
		_update_brains()  # hahmo vapautui tai varattiin kesken pelin
	match _state:
		"fly":
			_vel.y -= G * delta
			_pos += _vel * delta
			_orient_ball(delta)
			var land := _landing()
			for i in _brains:
				var pl := _player(i)
				var br: Brain = _brains[i]
				br.goal = land if i == _target_i else _spot_pos(pl.spot)
				br.face = _spot_pos(-1) if i == _target_i else _pos
			_ring.visible = _target_i == game.player_index and active
			_ring.global_position = Vector3(land.x, _ground(land.x, land.z) + 0.03, land.z)
			# Tietokoneen vuoro, kun pallo laskeutuu ulottuville tähtäyskorkeudelle.
			if _brains.has(_target_i) and _vel.y < 0.0:
				var tb: CharacterBody3D = game.crew[_target_i]
				var q := _quality(tb)
				var dh := _pos.y - _feet(tb)
				if q > 0.0 and dh < hit_h + 0.25:
					if _will_hit:
						_start_swing(tb)
						_hit(_player(_target_i), q)
					elif dh < low + 0.1 and not _swing.has(tb):
						_start_swing(tb)  # myöhästynyt yritys
			var g := _ground(_pos.x, _pos.z)
			if _state == "fly" and _pos.y - ball_r <= g:
				_ring.visible = false
				if _owns(_target_i) or not spots.has(_target_i):
					_drop_ball()
					_rally_over()
					game.mp.send({"t": msg + "_miss", "r": _rally, "n": hits})
				else:
					# Kohteen kone ratkaisee: lyönti voi vielä tulla verkosta.
					_pos.y = g + ball_r
					_state = "wait"
					_dead_t = 2.5
		"wait":
			_dead_t -= delta
			if _dead_t <= 0.0:
				_drop_ball()
				_rally_over()  # viesti ei tullut perille
		"dead":
			_dead_t -= delta
			_dead_motion(delta)
			if _dead_t <= 0.0:
				_state = "idle"
				_ball.visible = false
				hits = 0
				for i in _brains:
					(_brains[i] as Brain).goal = _spot_pos(_player(i).spot)
					(_brains[i] as Brain).face = _spot_pos(-1)
	_ball.global_position = _pos
	var gs := _ground(_pos.x, _pos.z)
	_shadow.visible = _ball.visible and gs <= Terrain.h(_pos.x, _pos.z) + 0.01  # varjo vain maalla
	_shadow.global_position = Vector3(_pos.x, gs + 0.01, _pos.z)


## Pallo putoaa hetkeksi maahan tai veteen, sitten syöttövuoro.
func _drop_ball() -> void:
	var g := _ground(_pos.x, _pos.z)
	_pos.y = maxf(_pos.y, g + ball_r)
	_vel = Vector3(_vel.x * 0.5, absf(_vel.y) * 0.45, _vel.z * 0.5)
	_state = "dead"
	_dead_t = 1.6
	_ring.visible = false


func _set_record(n: int) -> void:
	record = n
	var cfg := ConfigFile.new()
	cfg.set_value(section, "ennatys", record)
	cfg.save(save_path)
	_on_record()


## Pallo putosi: kaikki voittavat (uusi ennätys) tai kaikki häviävät.
func _rally_over() -> void:
	if hits > record:
		_set_record(hits)
		game.toast("Uusi ennätys: %d %s! Kaikki voittivat!" % [hits, unit], 4.0)
		Sfx.play("pickup", -8.0, 1.2)
	else:
		game.toast("%s %d %s jälkeen – kaikki hävisivät. Ennätys %d." % [fall_text, hits, unit_gen, record], 3.5)
	var pl := _player(_target_i)
	if not pl.is_empty() and not _human(pl.i):
		_say(pl, lines_miss[hits % lines_miss.size()])


func prompt() -> String:
	var s := "%s · %d %s · ennätys %d · " % [title, hits, unit, record]
	match _state:
		"idle":
			s += serve_text
		"fly":
			s += ("E: %s! Mene keltaiseen renkaaseen" % hit_verb) if _target_i == game.player_index else "E: %s" % hit_verb
		_:
			s += fall_text.to_lower()
	return s + " · F: lopeta"
