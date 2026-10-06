extends "res://scripts/pallopeli.gd"
## Amerikkalaisen jalkapallon heittely vedessä alamökin edustalla, samalla mekaniikalla kuin rantatennis
## (pallopeli.gd): koko porukka heittelee yhdessä vyötäröön asti vedessä, ja heitot lasketaan, kunnes pallo
## putoaa veteen. E heittää ja ottaa kiinni. Pallo kiertää lennossa pituusakselinsa ympäri (spiraali) ja kelluu
## pudottuaan. Paikka on 20-30 m rannasta, jossa vettä on 0,7-1 m: kahlataan, ei uida.

## Pelialue pihan kehyksessä (u itään, v järvelle) ja pelipaikat salmiakkina, naapuriin n. 5,5 m.
const AREA_C := Vector2(-4.0, 27.0)
const AREA_H := Vector2(8.0, 6.0)
const SPOTS := [Vector2(-4.5, 0.0), Vector2(0.0, 3.2), Vector2(4.5, 0.0), Vector2(0.0, -3.2)]

var _spin := 0.0


func _init() -> void:
	title = "Amerikkalainen jalkapallo"
	msg = "af"
	section = "amerikanpallo"
	save_path = "user://amerikanpallo.cfg"
	unit = "heittoa"
	unit_gen = "heiton"
	serve_text = "E: heitä (pallo lähtee sille, jota kohti katsot)"
	hit_verb = "ota kiinni ja heitä"
	fall_text = "Pallo veteen"
	start_text = "Heitellään palloa vedessä yhdessä. E heittää ja ottaa kiinni."
	ball_r = 0.09
	hit_h = 1.5  # rinnan korkeudelle (jalat pohjassa)
	sweet = 1.5
	low = 0.95
	high = 2.7
	reach = 1.3
	swing_amp = 2.4  # heitto pään yli
	flight = Vector3(0.8, 0.1, 0.0)
	flight_min = 1.0
	flight_max = 1.6
	hit_sound = ["whoosh", -10.0, 1.1]
	lines_miss = ["Plums!", "Liukas pallo!", "Ei se mitään, uusiks!", "Aalto vei."]
	lines_good = ["Spiraali!", "Touchdown!", "Hyvä koppi!", "Nyt lentää!"]


static func area_local(p: Vector2) -> Vector2:
	return Mokki.wy(p) - AREA_C


func in_area(p: Vector3, m := 0.0) -> bool:
	var q := area_local(Vector2(p.x, p.z))
	return absf(q.x) <= AREA_H.x + m and absf(q.y) <= AREA_H.y + m


func can_start(p: Vector3) -> bool:
	return not active and in_area(p, 0.5) and game.player.water_depth > 0.25


func _spot_pos(k: int) -> Vector3:
	var q: Vector2 = AREA_C + (SPOTS[k] if k >= 0 else Vector2.ZERO)
	var w := Mokki.yw(q.x, q.y)
	return Vector3(w.x, Terrain.h(w.x, w.y), w.y)


## Pallo putoaa järven pintaan (tai maahan, jos lentää rannalle).
func _ground(x: float, z: float) -> float:
	return maxf(Terrain.h(x, z), 0.0)


## Rannasta kahlaten: saunan rantaan ja sieltä suoraan paikalle.
func _route_to(b: CharacterBody3D) -> Array:
	var p := b.global_position
	if in_area(p, 12.0):
		return []
	var m: Node3D = game.world.mokki
	return m.route(p, "ranta_vesi")


## Ruskea nahkapallo, valkoiset nauhat ja raidat; pitkä akseli z.
func _make_ball() -> Node3D:
	var n := Node3D.new()
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.42, 0.2, 0.08)
	leather.roughness = 0.6
	var white := B.mat(Color(0.95, 0.95, 0.92))
	var body := MeshInstance3D.new()
	body.mesh = B.sphere(ball_r, 16)
	body.material_override = leather
	body.scale = Vector3(1.0, 1.0, 1.75)
	n.add_child(body)
	for z: float in [-0.1, 0.1]:
		var stripe := MeshInstance3D.new()
		stripe.mesh = B.cyl(ball_r * 0.86, ball_r * 0.86, 0.012, 16)
		stripe.material_override = white
		stripe.rotation = Vector3(PI * 0.5, 0, 0)
		stripe.position = Vector3(0, 0, z)
		n.add_child(stripe)
	var laces := MeshInstance3D.new()
	laces.mesh = B.boxm(Vector3(0.012, 0.01, 0.09))
	laces.material_override = white
	laces.position = Vector3(0, ball_r * 0.98, 0)
	n.add_child(laces)
	for k in 4:
		var l := MeshInstance3D.new()
		l.mesh = B.boxm(Vector3(0.035, 0.01, 0.008))
		l.material_override = white
		l.position = Vector3(0, ball_r * 0.99, -0.03 + k * 0.02)
		n.add_child(l)
	return n


## Spiraali: kärki lentosuuntaan, kierre pituusakselin ympäri.
func _orient_ball(delta: float) -> void:
	_spin += 14.0 * delta
	if _vel.length() > 0.1:
		_ball.basis = Basis.looking_at(-_vel.normalized()) * Basis(Vector3.BACK, _spin)


## Pallo kelluu pudottuaan ja ajelehtii hiljalleen.
func _dead_motion(delta: float) -> void:
	_vel = Vector3(_vel.x, 0.0, _vel.z) * pow(0.25, delta)
	_pos += _vel * delta
	_spin += delta
	_pos.y = _ground(_pos.x, _pos.z) + ball_r * 0.4 + sin(_spin * 3.0) * 0.01
	_ball.basis = Basis(Vector3.UP, _spin * 0.3)  # kyljellään vedessä


func _drop_ball() -> void:
	super._drop_ball()
	Sfx.play_on(_ball, "water", -6.0, 1.3)  # loiskis
