extends Node
## Lettujen paisto alamökin keittiössä. Vain Marko osaa kokata: hellan edessä E kaataa taikinan pannulle,
## kääntää letun ja nostaa sen pöydän lautaselle. Kumpikin puoli kannattaa paistaa kullanruskeaksi; liian
## kauan pannulla ja lettu palaa pohjaan. Pöytään istuva syö letun (kunto täyteen). Lettujen määrä on
## moninpelissä yhteinen (viesti "letut"), ja tietokoneen Marko paistaa myös (mokki.gd cooked-signaali).

const Ui := preload("res://scripts/ui.gd")
const B := preload("res://scripts/build.gd")

const SPEED := 0.2  # paistoaste sekunnissa: kullanruskea 3–4 sekunnissa
const MAX_PILE := 20
const BATTER := Color(0.96, 0.9, 0.68)
const GOLDEN := Color(0.86, 0.6, 0.26)
const BURNT := Color(0.18, 0.11, 0.07)

var game: Node3D
var letut := 0  # lautasella pöydässä
var _state := ""  # "" tyhjä pannu | "1" ensimmäinen puoli | "2" toinen puoli
var _p := 0.0
var _side1 := 0.0
var _made := 0
var _perfect := 0
var _flip_t := 0.0
var _in_pan: MeshInstance3D
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
	game.mp.on("letut", func(d: Dictionary, _from: int) -> void: _set_count(int(d.n)))
	_in_pan = MeshInstance3D.new()
	_in_pan.mesh = B.cyl(0.1, 0.1, 0.012, 20)
	_pan_mat = StandardMaterial3D.new()
	_pan_mat.roughness = 0.8
	_in_pan.material_override = _pan_mat
	_in_pan.position = m.pan_pos + Vector3.UP * 0.006
	_in_pan.visible = false
	game.add_child(_in_pan)
	_pile = Node3D.new()
	_pile.position = m.plate_pos + Vector3.UP * 0.012
	game.add_child(_pile)
	_build_ui()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "top", 520)
	Ui.label(box, "MARKON LETTUPANNU", 24, Ui.YELLOW)
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
			_sizzle_on(true)
			Sfx.play_on(_in_pan, "water", -10.0, 1.6)
		"1":
			_side1 = _p
			_state = "2"
			_p = 0.0
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
				game.toast("Lettu jäi raa'aksi – taikina valui pitkin hellaa")
				Sfx.play("lose", -10.0)
			else:
				_made += 1
				if a == "kullanruskea" and b == "kullanruskea":
					_perfect += 1
					game.toast("Täydellinen lettu!")
					Sfx.play("win_small", -8.0)
				else:
					game.toast("Lettu lautaselle (%s ja %s)" % [a, b])
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
		game.toast("Paistoit %d lettua, joista %d täydellisiä. Pöydässä nyt %d." % [_made, _perfect, letut], 5.0)


func prompt() -> String:
	var t: String = {"": "E: kaada taikina pannulle", "1": "E: käännä lettu", "2": "E: nosta lautaselle"}[_state]
	return t + " · W: lopeta"


## Lettuja lautaselle (paistettu tai tietokoneen Markon tekemiä).
func add(n: int) -> void:
	_set_count(mini(MAX_PILE, letut + n))
	game.mp.send({"t": "letut", "n": letut})


## Pöytään istuva syö letun, jos lautasella on.
func eat() -> void:
	if letut <= 0:
		return
	_set_count(letut - 1)
	game.mp.send({"t": "letut", "n": letut})
	game.player.stamina = 100.0
	game.player.exhausted = false
	game.toast("Söit Markon letun mansikkahillon kanssa. Kunto täynnä!")
	Sfx.play("pickup", -8.0)


func _set_count(n: int) -> void:
	letut = n
	for ch in _pile.get_children():
		ch.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GOLDEN
	mat.roughness = 0.85
	for k in letut:
		var mi := MeshInstance3D.new()
		mi.mesh = B.cyl(0.1, 0.1, 0.008, 18)
		mi.material_override = mat
		mi.position = Vector3(sin(k * 2.3) * 0.006, k * 0.009, cos(k * 1.7) * 0.006)
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
	var c := BATTER.lerp(GOLDEN, clampf(_p / 0.7, 0.0, 1.0))
	if _p > 0.7:
		c = GOLDEN.lerp(BURNT, clampf((_p - 0.7) / 0.45, 0.0, 1.0))
	_pan_mat.albedo_color = c
	if _p >= 1.15:
		_state = ""
		_in_pan.visible = false
		_sizzle_on(false)
		game.toast("Lettu paloi pohjaan! Savua koko keittiö täynnä.")
		Sfx.play("lose", -8.0)
	_refresh()


func _refresh() -> void:
	if not _ui.visible:
		return
	_meter.set_value(_p if _state != "" else 0.0)
	match _state:
		"":
			_info.text = "Pannu kuumana. Kaada taikina (E). Pöydässä %d lettua." % letut
		"1":
			_info.text = "Ensimmäinen puoli: %s – käännä kullanruskeana (E)" % doneness(_p)
		"2":
			_info.text = "Toinen puoli: %s – nosta lautaselle (E)" % doneness(_p)
