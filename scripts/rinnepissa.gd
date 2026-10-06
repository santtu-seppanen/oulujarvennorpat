extends Node3D
## Rinteeseen virtsaaminen pitkospuiden alkupäässä ennen huussia. Suihku lentää hahmon edestä heittoliikkeenä ja
## osuu maastoon; kaaren pituus mitataan vaakasuoraan jaloista osumakohtaan. W/S nostaa ja laskee kaarta, A/D
## kääntää. Markon erikoiskyky: suuri kaari 5 metrin päähän, muilta noin 2 m; metsän mustikat pidentävät kaarta
## (mustikat.gd), mutta muut eivät silti yllä Markon kaareen. Humala heiluttaa suihkua. Paine
## nousee alussa ja hiipuu lopussa tipoiksi; märät läikät jäävät maahan. E tai F lopettaa kesken.
## Moninpelissä suihku näkyy muillakin: kulma, suunnan heilunta ja lähtönopeus lähetetään (viesti "pissa"),
## ja vastaanottaja laskee kaaren itse hahmon paikasta.

const B := preload("res://scripts/build.gd")

const TIME := 7.0
const G := 9.8
## Lähtönopeus täydellä paineella (m/s): pitkospuilta alamäkeen Markolla n. 5 m, muilla n. 2 m.
const SPEED_MARKO := 6.1
const SPEED := 3.4
const HIP := 0.92
const SEND_RATE := 15.0
const REMOTE_TIMEOUT := 0.6  # näin kauan ilman viestiä, niin toisen suihku loppuu
const LINES_MARKO := ["Katsokaa ja oppikaa.", "Tämä on taitolaji.", "Kaari kuin Oulujärven sateenkaari."]
const LINES := ["No niin, rinteeseen.", "Ei kato kukaan.", "Pitkospuilta on hyvä lasettaa."]


## Yhden hahmon suihku: kaaren laskenta, pisarat, roiskeet, märät läikät ja solina.
class Stream:
	extends Node3D
	const B := preload("res://scripts/build.gd")
	const G := 9.8
	const HIP := 0.92
	const DROPS := 56
	const SPLASH := 10
	const MAX_SPOTS := 50

	var dist := 0.0  # kaaren pituus (0, jos ei osu mihinkään)
	var _t := 0.0
	var _hit := Vector3.ZERO
	var _hit_n := Vector3.UP
	var _landed := false
	var _arc := PackedVector3Array()
	var _spot_t := 0.0
	var _drops: MultiMeshInstance3D
	var _spots: Array[MeshInstance3D] = []
	var _spot_mat: StandardMaterial3D
	var _sound: AudioStreamPlayer3D

	func _ready() -> void:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var drop := SphereMesh.new()
		drop.radius = 0.016
		drop.height = 0.032
		drop.radial_segments = 6
		drop.rings = 3
		mm.mesh = drop
		mm.instance_count = DROPS + SPLASH
		mm.visible_instance_count = 0
		_drops = MultiMeshInstance3D.new()
		_drops.multimesh = mm
		_drops.material_override = B.unshaded(Color(1.0, 0.9, 0.35, 0.8))
		_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_drops.top_level = true
		add_child(_drops)
		_spot_mat = StandardMaterial3D.new()
		_spot_mat.albedo_color = Color(0.12, 0.1, 0.03, 0.45)
		_spot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_spot_mat.roughness = 0.15

	func active() -> bool:
		return _sound != null

	## Suihku hahmolta body: nousukulma a, suunta yaw (maailmassa), lähtönopeus v, paine full (0..1).
	func update(body: CharacterBody3D, a: float, yaw: float, v: float, full: float, delta: float) -> void:
		_t += delta
		if _sound == null:
			_sound = Sfx.loop_on(self, "water", -40.0)
			_sound.top_level = true
		var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var pos := body.global_position + Vector3.UP * HIP + fwd * 0.18
		_simulate(body, pos, (fwd * cos(a) + Vector3.UP * sin(a)) * maxf(v, 0.2))
		dist = Vector2(_hit.x - body.global_position.x, _hit.z - body.global_position.z).length() if _landed else 0.0
		_draw()
		_sound.global_position = _hit if _landed else pos
		_sound.volume_db = lerpf(-30.0, -9.0, full) if _landed else -40.0
		_sound.pitch_scale = 0.75 + full * 0.35
		_spot_t -= delta
		if _landed and _spot_t <= 0.0 and full > 0.15:
			_spot_t = 0.22
			_add_spot()

	## Suihku loppuu; märät läikät jäävät.
	func clear() -> void:
		_drops.multimesh.visible_instance_count = 0
		dist = 0.0
		if _sound != null:
			_sound.queue_free()
			_sound = null

	## Heittoliike pienin askelin; jokainen askel säteenä maastoa, rakennuksia ja järven pintaa vasten.
	func _simulate(body: CharacterBody3D, pos: Vector3, vel: Vector3) -> void:
		_arc = PackedVector3Array([pos])
		_landed = false
		var space := get_world_3d().direct_space_state
		var dt := 1.0 / 60.0
		for i in 180:
			var nxt := pos + vel * dt
			vel.y -= G * dt
			var q := PhysicsRayQueryParameters3D.create(pos, nxt)
			q.exclude = [body.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				_hit = hit.position
				_hit_n = hit.normal
				_landed = true
				_arc.append(_hit)
				return
			if nxt.y < 0.0:  # järveen
				_hit = pos.lerp(nxt, pos.y / maxf(pos.y - nxt.y, 0.001))
				_hit_n = Vector3.UP
				_landed = true
				_arc.append(_hit)
				return
			pos = nxt
			_arc.append(pos)

	## Pisarat virtaavat kaarta pitkin; osumakohdassa roiskeita.
	func _draw() -> void:
		var mm := _drops.multimesh
		var n := _arc.size()
		if n < 2:
			mm.visible_instance_count = 0
			return
		for k in DROPS:
			var f := fmod(float(k) / DROPS + _t * 2.2, 1.0) * (n - 1)
			var i := mini(int(f), n - 2)
			var pt := _arc[i].lerp(_arc[i + 1], f - i)
			mm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * (1.0 + randf() * 0.4)), pt))
		var cnt := DROPS
		if _landed:
			for k in SPLASH:
				var r := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)) * 0.09
				mm.set_instance_transform(DROPS + k, Transform3D(Basis(), _hit + r + _hit_n * 0.02))
			cnt += SPLASH
		mm.visible_instance_count = cnt

	## Märkä läikkä osumakohtaan pinnan suuntaisesti.
	func _add_spot() -> void:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = randf_range(0.08, 0.14)
		c.bottom_radius = c.top_radius
		c.height = 0.005
		c.radial_segments = 10
		mi.mesh = c
		mi.material_override = _spot_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
		var up := _hit_n.normalized()
		var x := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		mi.global_transform = Transform3D(Basis(x, up, x.cross(up)), _hit + up * 0.012)
		_spots.append(mi)
		if _spots.size() > MAX_SPOTS:
			_spots.pop_front().queue_free()


var game: Node3D
var active := false
var best := {}  # hahmon nimi -> pisin kaari (m)
var _who := ""
var _t := 0.0
var _angle := 0.75  # kaaren nousukulma (rad)
var _max := 0.0
var _send_t := 0.0
var _mine: Stream
var _remote := {}  # hahmon indeksi -> {stream, t (aika viimeisestä viestistä), a, y, v, f}


func _ready() -> void:
	_mine = Stream.new()
	add_child(_mine)
	game.mp.on("pissa", _on_remote)


func _player() -> CharacterBody3D:
	return game.player


func _marko() -> bool:
	return _who == "Marko"


## Metsän mustikoista lisää lähtönopeutta (mustikat.gd).
func _berries() -> float:
	return game.mustikat.boost(game.player_index) if game.get("mustikat") != null else 0.0


func start() -> void:
	var p := _player()
	_who = p.display_name
	active = true
	_t = 0.0
	_max = 0.0
	_angle = 0.75
	p.controls_enabled = false
	p.velocity = Vector3.ZERO
	p.pose = ""
	Sfx.play("cloth", -6.0, 1.6)  # vetoketju
	game.toast((LINES_MARKO if _marko() else LINES).pick_random(), 2.5)


func stop() -> void:
	if not active:
		return
	active = false
	_mine.clear()
	game.mp.send({"t": "pissa", "i": game.player_index, "v": 0.0})
	var p := _player()
	p.controls_enabled = true
	Sfx.play("cloth", -8.0, 1.4)
	var m := snappedf(_max, 0.1)
	var rec: float = best.get(_who, 0.0)
	var text := ""
	if _t < 2.5:
		text = "Jäi kesken. Rinne odottaa."
	elif _marko():
		if _max >= 4.5:
			text = "Marko lasetti suurella kaarella %.1f metrin päähän rinteeseen! Erikoiskyky." % m
		else:
			text = "%.1f m. Kaari osui rinteeseen ennen aikojaan: nosta kaarta tai käänny alamäkeen." % m
	else:
		text = "%.1f m. Markon viiteen metriin on vielä matkaa." % m
	if _t >= 2.5 and _max > rec + 0.05:
		best[_who] = _max
		if rec > 0.0:
			text += " Uusi ennätys!"
	game.toast(text, 4.5)


## Kehoteteksti alareunaan (main.gd).
func prompt() -> String:
	var t := "W/S kaaren korkeus · A/D suunta · kaari %.1f m" % _mine.dist
	if _berries() > 0.0:
		t += " · mustikkavoimaa +%d %%" % roundi(_berries() / (SPEED_MARKO if _marko() else SPEED) * 100.0)
	if best.has(_who):
		t += " (ennätys %.1f m)" % best[_who]
	return t + " · E/F lopettaa"


func _pressure() -> float:
	return smoothstep(0.0, 0.5, _t) * (1.0 - smoothstep(TIME - 1.8, TIME, _t)) * (0.93 + 0.07 * sin(_t * 7.0))


func _physics_process(delta: float) -> void:
	_remotes(delta)
	if not active:
		return
	_t += delta
	var p := _player()
	if _t > 0.3 and (Input.is_action_just_pressed("interact") or Input.is_key_pressed(KEY_F)) or _t >= TIME \
			or p.pose == "Sammunut" or p.pose == "Ryomii":
		stop()
		return
	_angle = clampf(_angle + Input.get_axis("back", "forward") * 0.8 * delta, 0.05, 1.3)
	p.rotation.y += Input.get_axis("right", "left") * 1.2 * delta
	p.velocity = Vector3.ZERO
	var d: float = p.drunk()
	var a := _angle + sin(_t * 2.1) * d * 0.3 + sin(_t * 5.3) * 0.02
	var wobble := sin(_t * 1.7 + 1.0) * d * 0.35
	var pr := _pressure()
	var v := ((SPEED_MARKO if _marko() else SPEED) + _berries()) * pr
	_mine.update(p, a, p.rotation.y + wobble, v, pr, delta)
	if pr > 0.8:
		_max = maxf(_max, _mine.dist)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_RATE
		game.mp.send({"t": "pissa", "i": game.player_index, "a": snappedf(a, 0.01), "y": snappedf(wobble, 0.01),
			"v": snappedf(v, 0.01), "f": snappedf(pr, 0.01)})


# --- Moninpeli: muiden suihkut --------------------------------------------------------------------------------

func _on_remote(d: Dictionary, _from: int) -> void:
	var i := int(d.get("i", -1))
	if i < 0 or i >= game.crew.size() or i == game.player_index:
		return
	if not _remote.has(i):
		var s := Stream.new()
		add_child(s)
		_remote[i] = {"stream": s}
	var r: Dictionary = _remote[i]
	r.t = 0.0
	r.a = float(d.get("a", 0.75))
	r.y = float(d.get("y", 0.0))
	r.v = float(d.get("v", 0.0))
	r.f = float(d.get("f", 0.0))


## Toisten suihkut lasketaan heidän hahmonsa paikasta ja suunnasta (hahmon tila tulee moninpeli.gd:n kautta).
func _remotes(delta: float) -> void:
	for i in _remote:
		var r: Dictionary = _remote[i]
		var s: Stream = r.stream
		r.t += delta
		var body: CharacterBody3D = game.crew[i]
		if r.v <= 0.0 or r.t > REMOTE_TIMEOUT or body.hidden_inside or i == game.player_index:
			if s.active():
				s.clear()
			continue
		s.update(body, r.a, body.rotation.y + r.y, r.v, r.f, delta)
