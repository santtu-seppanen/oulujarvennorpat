extends Node
## Nuotiopaikka rannalla pääterassin ja laiturin välissä: kivikehä, hiillos, liekit, savu ja lepattava valo sekä
## neljä istuinhirttä nuotion ympärillä (paikat mokki.gd fire_seats). Nuotiolla paistetaan makkaraa (makkara.gd)
## ja kerrotaan tarinoita (muistelu.gd): molemmissa pelaaja istuu hirrelle ja tietokoneen ohjaamat mökkiläiset
## tulevat istumaan ympärille.

const Terrain := preload("res://scripts/terrain.gd")

var game: Node3D
var pos := Vector3.ZERO
var _t := 0.0
var _light: OmniLight3D
var _glow: StandardMaterial3D


func _ready() -> void:
	var m: Node3D = game.world.mokki
	pos = m.fire_pos
	var root := Node3D.new()
	root.position = pos
	game.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 79
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.45, 0.44, 0.42)
	stone.roughness = 1.0
	for k in 10:
		var a := TAU * k / 10.0 + rng.randf_range(-0.12, 0.12)
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.16
		sp.height = 0.32
		mi.mesh = sp
		mi.material_override = stone
		mi.scale = Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.7, 1.0), rng.randf_range(0.9, 1.2))
		mi.position = Vector3(cos(a) * 0.62, 0.07, sin(a) * 0.62)
		mi.rotation.y = a
		root.add_child(mi)
	# Hiillos: tumma tuhkapohja ja hehkuva kiekko.
	var ash := MeshInstance3D.new()
	var ac := CylinderMesh.new()
	ac.top_radius = 0.5
	ac.bottom_radius = 0.5
	ac.height = 0.05
	ash.mesh = ac
	var am := StandardMaterial3D.new()
	am.albedo_color = Color(0.1, 0.09, 0.09)
	ash.material_override = am
	ash.position.y = 0.03
	root.add_child(ash)
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(0.9, 0.3, 0.05)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.4, 0.08)
	_glow.emission_energy_multiplier = 1.6
	var ember := MeshInstance3D.new()
	var ec := CylinderMesh.new()
	ec.top_radius = 0.36
	ec.bottom_radius = 0.4
	ec.height = 0.04
	ember.mesh = ec
	ember.material_override = _glow
	ember.position.y = 0.07
	root.add_child(ember)
	# Hiiltyneet puut ristiin hiilloksen päällä.
	var char_mat := StandardMaterial3D.new()
	char_mat.albedo_color = Color(0.13, 0.09, 0.07)
	for k in 3:
		var lg := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.06
		lc.bottom_radius = 0.07
		lc.height = 0.85
		lg.mesh = lc
		lg.material_override = char_mat
		lg.position = Vector3(0, 0.15 + 0.07 * k, 0)
		lg.rotation = Vector3(0, TAU * k / 3.0 + 0.4, PI * 0.5 + 0.12)
		root.add_child(lg)
	# Istuinhirret: kaatuneet rungot hahmon paikan kohdalla, pitkittäin nuotion ympäri.
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.36, 0.26, 0.17)
	bark.roughness = 1.0
	for s: Array in m.fire_seats:
		var d: Vector3 = s[0] - pos
		var lg := MeshInstance3D.new()
		var lc := CylinderMesh.new()
		lc.top_radius = 0.2
		lc.bottom_radius = 0.2
		lc.height = 1.2
		lg.mesh = lc
		lg.material_override = bark
		lg.position = Vector3(d.x, d.y + 0.18, d.z)
		lg.rotation = Vector3(0, atan2(d.x, d.z), PI * 0.5)
		root.add_child(lg)
	root.add_child(_flames())
	root.add_child(_smoke())
	_light = OmniLight3D.new()
	_light.position = Vector3(0, 0.8, 0)
	_light.light_color = Color(1.0, 0.55, 0.22)
	_light.omni_range = 9.0
	_light.light_energy = 1.6
	root.add_child(_light)


func _flames() -> CPUParticles3D:
	var f := CPUParticles3D.new()
	f.amount = 36
	f.lifetime = 0.9
	f.direction = Vector3.UP
	f.spread = 12.0
	f.initial_velocity_min = 0.5
	f.initial_velocity_max = 1.1
	f.gravity = Vector3(0, 0.4, 0)
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	f.emission_sphere_radius = 0.22
	f.scale_amount_min = 0.07
	f.scale_amount_max = 0.13
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	f.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.6, 0.1, 0.95))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	f.color_ramp = ramp
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	f.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	f.material_override = mat
	f.position.y = 0.2
	return f


func _smoke() -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.amount = 14
	s.lifetime = 3.2
	s.direction = Vector3.UP
	s.spread = 10.0
	s.initial_velocity_min = 0.4
	s.initial_velocity_max = 0.7
	s.gravity = Vector3(0.12, 0.2, 0)
	s.scale_amount_min = 0.12
	s.scale_amount_max = 0.3
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	s.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.7, 0.18)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.material_override = mat
	s.position.y = 0.9
	return s


func _process(delta: float) -> void:
	_t += delta
	if _light != null:
		_light.light_energy = 1.6 + 0.35 * sin(_t * 13.0) + 0.25 * sin(_t * 29.0 + 1.0)
		_glow.emission_energy_multiplier = 1.5 + 0.4 * sin(_t * 7.0)


## Pelaaja on nuotiolla (jaloilla rannalla, ei terassilla).
func near(p: Vector3) -> bool:
	return Vector2(p.x - pos.x, p.z - pos.z).length() < 2.8 and absf(p.y - pos.y) < 0.8


## Hahmon i istuinhirsi.
func seat(i: int) -> Array:
	return game.world.mokki.fire_seats[i % 4]


## Pelaaja istumaan omalle hirrelleen ja tietokoneen mökkiläiset muille.
func sit_player() -> void:
	var s := seat(game.player_index)
	game.player.sit_at(s[0], s[1])
	gather_ai(true)


func stand_player() -> void:
	game.player.stand_up()
	gather_ai(false)


## Tietokoneen ohjaamat mökkiläiset nuotiolle (on) tai pois.
func gather_ai(on: bool) -> void:
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if game.crew_modes[j] != "ai" or b.brain == null:
			continue
		if on:
			b.brain.fire(j)
		else:
			b.brain.fire_end()


## Onko hahmo j (tietokone) jo istumassa nuotiolla.
func seated(j: int) -> bool:
	var b: CharacterBody3D = game.crew[j]
	return b.brain != null and b.brain.fire_ready()


## Muut mökkiläiset kuin pelaaja (indeksit): tarinoiden kertojat ja kommentoijat.
func others() -> Array:
	var out: Array = []
	for j in game.crew.size():
		if j != game.player_index:
			out.append(j)
	return out
