extends Node
## Pyttipannun paisto alamökin keittiössä. Vain Marko osaa kokata: hellan edessä E kaataa perunakuutiot
## pannulle, lisää sipulin ja makkaran ja nostaa annoksen pöydän lautaselle paistetun kananmunan ja punajuuren
## kanssa. Perunat ja koko pannu kannattaa paistaa kullanruskeaksi; liian kauan pannulla ja pyttipannu palaa
## pohjaan. Pöytään istuva syö annoksen (kunto täyteen). Annosten määrä on moninpelissä yhteinen (viesti
## "pytti"), ja tietokoneen Marko paistaa myös (mokki.gd cooked-signaali).

const Ui := preload("res://scripts/ui.gd")
const B := preload("res://scripts/build.gd")

const SPEED := 0.2  # paistoaste sekunnissa: kullanruskea 3–4 sekunnissa
const MAX_PILE := 12
const CUBES := 34  # perunakuutioita pannulla
const RAW := Color(0.93, 0.88, 0.66)
const GOLDEN := Color(0.85, 0.6, 0.24)
const BURNT := Color(0.18, 0.11, 0.07)
const SAUSAGE := Color(0.55, 0.24, 0.17)
const ONION := Color(0.92, 0.86, 0.7)

var game: Node3D
var annokset := 0  # lautasella pöydässä
var _state := ""  # "" tyhjä pannu | "1" perunat paistuvat | "2" sipuli ja makkara joukossa
var _p := 0.0
var _side1 := 0.0
var _made := 0
var _perfect := 0
var _flip_t := 0.0
var _in_pan: Node3D
var _potato: MultiMeshInstance3D
var _extras: MultiMeshInstance3D
var _pan_mat: StandardMaterial3D
var _pile: Node3D
var _sizzle: AudioStreamPlayer3D
var _ui: CanvasLayer
var _meter: Ui.Meter
var _info: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Node3D = game.world.mokki
	m.cooked.connect(func(n: int) -> void: add(n))
	game.mp.on("pytti", func(d: Dictionary, _from: int) -> void: _set_count(int(d.n)))
	_in_pan = Node3D.new()
	_in_pan.position = m.pan_pos + Vector3.UP * 0.015
	_in_pan.visible = false
	game.add_child(_in_pan)
	_pan_mat = StandardMaterial3D.new()
	_pan_mat.roughness = 0.7
	_potato = _chunks(CUBES, 0.024, 7, func(_k: int) -> Color: return Color.WHITE)
	_potato.material_override = _pan_mat
	_in_pan.add_child(_potato)
	# Makkara (punaruskea) ja sipuli (vaalea) lisätään toisessa vaiheessa.
	_extras = _chunks(18, 0.02, 13, func(k: int) -> Color: return SAUSAGE if k % 3 != 0 else ONION)
	var em := StandardMaterial3D.new()
	em.vertex_color_use_as_albedo = true
	em.roughness = 0.6
	_extras.material_override = em
	_extras.visible = false
	_in_pan.add_child(_extras)
	_pile = Node3D.new()
	_pile.position = m.plate_pos + Vector3.UP * 0.012
	game.add_child(_pile)
	_build_ui()


## Pieniä kuutioita satunnaisesti pannun pohjalle (säde 0,09 m).
func _chunks(n: int, size: float, seed_: int, col: Callable) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = B.boxm(Vector3.ONE * size)
	mm.instance_count = n
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	for k in n:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 0.085
		var basis := Basis.from_euler(Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6))
		mm.set_instance_transform(k, Transform3D(basis, Vector3(cos(a) * r, rng.randf() * 0.012, sin(a) * r)))
		mm.set_instance_color(k, col.call(k))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	return mi


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "top", 520)
	Ui.label(box, "MARKON PYTTIPANNU", 24, Ui.YELLOW)
	_meter = Ui.Meter.new()
	_meter.zones = [[0.0, 0.45, Color(0.9, 0.85, 0.6, 0.6)], [0.45, 0.6, Color(0.85, 0.7, 0.35, 0.75)],
		[0.6, 0.82, Color(0.25, 0.7, 0.3, 0.85)], [0.82, 1.0, Color(0.55, 0.35, 0.15, 0.85)]]
	box.add_child(_meter)
	_info = Ui.label(box, "", 17)


## Paistoaste sanana.
static func doneness(p: float) -> String:
	if p < 0.45:
		return "raaka"
	if p < 0.6:
		return "vaalea"
	if p < 0.82:
		return "kullanruskea"
	if p < 1.0:
		return "tumma"
	return "palanut"


# --- Toiminta (main.gd kutsuu) --------------------------------------------------------------------------------

func start() -> bool:
	var m: Node3D = game.world.mokki
	var p: CharacterBody3D = game.player
	p.global_position = m.cook_spot + Vector3.UP * 0.05
	var d: Vector3 = m.cook_face - m.cook_spot
	p.rotation.y = atan2(-d.x, -d.z)
	p.velocity = Vector3.ZERO
	p.pose = "Idle"
	_state = ""
	_made = 0
	_perfect = 0
	_ui.visible = true
	_refresh()
	return true


func act() -> void:
	var p: CharacterBody3D = game.player
	match _state:
		"":
			_state = "1"
			_p = 0.0
			_in_pan.visible = true
			_extras.visible = false
			_sizzle_on(true)
			Sfx.play_on(_in_pan, "water", -10.0, 1.6)
		"1":
			_side1 = _p
			_state = "2"
			_p = maxf(0.0, _p - 0.45)  # sipuli ja makkara jäähdyttävät pannun hetkeksi
			_extras.visible = true
			p.pose = "Interact"
			_flip_t = 0.7
			Sfx.play_on(_in_pan, "whoosh", -8.0, 1.3)
		"2":
			var a := doneness(_side1)
			var b := doneness(_p)
			_state = ""
			_in_pan.visible = false
			_sizzle_on(false)
			p.pose = "Interact"
			_flip_t = 0.7
			if a == "raaka" or b == "raaka":
				game.toast("Perunat jäi raa'oiksi ja koviksi – ei kelpaa kenellekään")
				Sfx.play("lose", -10.0)
			else:
				_made += 1
				if a == "kullanruskea" and b == "kullanruskea":
					_perfect += 1
					game.toast("Täydellinen pyttipannu! Rapeat perunat, kananmuna päälle.")
					Sfx.play("win_small", -8.0)
				else:
					game.toast("Pyttipannu lautaselle (perunat %s, pannu %s)" % [a, b])
					Sfx.play("pickup", -8.0)
				add(1)
	_refresh()


func stop(_why := "") -> void:
	_ui.visible = false
	_in_pan.visible = false
	_sizzle_on(false)
	_state = ""
	game.player.pose = ""
	if _made > 0:
		game.toast("Paistoit %d pyttipannua, joista %d täydellisiä. Pöydässä nyt %d annosta." % [_made, _perfect, annokset], 5.0)


func prompt() -> String:
	var t: String = {"": "E: perunakuutiot pannulle", "1": "E: lisää sipuli ja makkara", "2": "E: annos lautaselle"}[_state]
	return t + " · W: lopeta"


## Annoksia lautaselle (paistettu tai tietokoneen Markon tekemiä).
func add(n: int) -> void:
	_set_count(mini(MAX_PILE, annokset + n))
	game.mp.send({"t": "pytti", "n": annokset})


## Pöytään istuva syö annoksen, jos lautasella on.
func eat() -> void:
	if annokset <= 0:
		return
	_set_count(annokset - 1)
	game.mp.send({"t": "pytti", "n": annokset})
	game.player.stamina = 100.0
	game.player.exhausted = false
	game.toast("Söit Markon pyttipannua punajuuren ja paistetun kananmunan kanssa. Kunto täynnä!")
	Sfx.play("pickup", -8.0)


## Annokset pöydässä: pyttipannukeko, jonka päällä paistettu kananmuna ja punajuuret vieressä.
func _set_count(n: int) -> void:
	annokset = n
	for ch in _pile.get_children():
		ch.queue_free()
	var food := StandardMaterial3D.new()
	food.albedo_color = GOLDEN
	food.roughness = 0.85
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.97, 0.96, 0.92)
	var yolk := StandardMaterial3D.new()
	yolk.albedo_color = Color(1.0, 0.72, 0.1)
	var beet := StandardMaterial3D.new()
	beet.albedo_color = Color(0.45, 0.05, 0.15)
	for k in annokset:
		var a := k * 2.4
		var o := Vector3(cos(a), 0, sin(a)) * (0.035 * sqrt(k)) + Vector3.UP * floorf(k / 4.0) * 0.025
		_part(B.sphere(0.06, 10), food, o, Vector3(1.0, 0.35, 1.0))
		_part(B.cyl(0.035, 0.035, 0.006, 14), white, o + Vector3.UP * 0.022)
		_part(B.sphere(0.012, 8), yolk, o + Vector3(0.004, 0.026, 0.0))
		_part(B.boxm(Vector3(0.02, 0.012, 0.02)), beet, o + Vector3(0.05, 0.004, 0.02))


func _part(mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	_pile.add_child(mi)


func _sizzle_on(on: bool) -> void:
	if on and _sizzle == null:
		_sizzle = Sfx.loop_on(_in_pan, "fire", -12.0)
		_sizzle.pitch_scale = 1.8
	elif not on and _sizzle != null:
		_sizzle.queue_free()
		_sizzle = null


func _process(delta: float) -> void:
	if _flip_t > 0.0:
		_flip_t -= delta
		if _flip_t <= 0.0 and game.activity == "kokkaus":
			game.player.pose = "Idle"
	if _state == "":
		return
	_p += SPEED * delta
	var c := RAW.lerp(GOLDEN, clampf(_p / 0.7, 0.0, 1.0))
	if _p > 0.7:
		c = GOLDEN.lerp(BURNT, clampf((_p - 0.7) / 0.45, 0.0, 1.0))
	_pan_mat.albedo_color = c
	if _state == "2":
		_in_pan.rotation.y += delta * 0.8  # Marko sekoittaa
	if _p >= 1.15:
		_state = ""
		_in_pan.visible = false
		_sizzle_on(false)
		game.toast("Pyttipannu paloi pohjaan! Savua koko keittiö täynnä.")
		Sfx.play("lose", -8.0)
	_refresh()


func _refresh() -> void:
	if not _ui.visible:
		return
	_meter.set_value(_p if _state != "" else 0.0)
	match _state:
		"":
			_info.text = "Pannu kuumana, voita pohjalle. Perunakuutiot pannulle (E). Pöydässä %d annosta." % annokset
		"1":
			_info.text = "Perunat: %s – lisää sipuli ja makkara, kun perunat ovat kullanruskeita (E)" % doneness(_p)
		"2":
			_info.text = "Pyttipannu: %s – annos lautaselle kullanruskeana (E)" % doneness(_p)
