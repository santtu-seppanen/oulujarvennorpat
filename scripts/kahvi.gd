extends Node
## Aamukahvit alamökin keittiön liedellä: Jukan erikoistaito. Pannukahvi keitetään kuin mökillä ennenkin:
## E nostaa pannun liedelle, ja kun vesi kiehuu, E lisää kahvinpurut. Kahvi kiehahtaa, ja kun vaahto nousee
## pannun reunoille, E nostaa pannun pois liedeltä ennen kuin se kiehuu yli. Kupit pöytään: pöytään istuva juo
## kupin, jolloin kunto palaa ja humala laskee. Kuppien määrä on moninpelissä yhteinen (viesti "kahvi"), ja
## tietokoneen Jukka keittää myös (mokki.gd coffee-signaali).

const Ui := preload("res://scripts/ui.gd")
const B := preload("res://scripts/build.gd")

const HEAT := 0.16  # veden kuumeneminen sekunnissa: kiehuu n. 5 sekunnissa
const RISE := 0.32  # vaahdon nousu sekunnissa purujen jälkeen
const BOIL := 0.8  # tästä ylöspäin vesi kiehuu
const FOAM := Vector2(0.62, 0.9)  # vaahto pannun reunoilla: tässä nostetaan pois
const MAX_CUPS := 8
const SOBER := 0.3  # kuppi laskee humalaa näin monta promillea

var game: Node3D
var kupit := 0  # pöydässä
var _state := ""  # "" | "vesi" (kuumenee) | "kiehuu" (purut lisätty, vaahto nousee)
var _p := 0.0
var _weak := false
var _made := 0
var _pot: Node3D
var _steam: CPUParticles3D
var _cups: Node3D
var _boil: AudioStreamPlayer3D
var _ui: CanvasLayer
var _meter: Ui.Meter
var _info: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Node3D = game.world.mokki
	m.coffee.connect(func(n: int) -> void: add(n))
	game.mp.on("kahvi", func(d: Dictionary, _from: int) -> void: _set_count(int(d.n)))
	var side: Vector3 = (m.cook_face - m.cook_spot).cross(Vector3.UP).normalized()
	_pot = _make_pot()
	_pot.position = m.pan_pos + side * 0.24 + Vector3.UP * 0.01
	_pot.visible = false
	game.add_child(_pot)
	_cups = Node3D.new()
	_cups.position = m.plate_pos - side * 0.32 + Vector3.UP * 0.005
	game.add_child(_cups)
	_build_ui()


## Kahvipannu: kiiltävä teräspannu, kansi, nokka ja kahva; höyry nousee kiehuessa.
func _make_pot() -> Node3D:
	var n := Node3D.new()
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.79, 0.8)
	steel.metallic = 0.85
	steel.roughness = 0.25
	var parts := [[B.cyl(0.075, 0.09, 0.2, 18), Vector3(0, 0.1, 0), Vector3.ZERO],
		[B.cyl(0.06, 0.077, 0.03, 18), Vector3(0, 0.215, 0), Vector3.ZERO],
		[B.sphere(0.018, 8), Vector3(0, 0.24, 0), Vector3.ZERO],
		[B.cyl(0.012, 0.022, 0.1, 8), Vector3(0.1, 0.15, 0), Vector3(0, 0, -0.9)],
		[B.boxm(Vector3(0.02, 0.12, 0.025)), Vector3(-0.115, 0.13, 0), Vector3(0, 0, 0.3)]]
	for pp in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = pp[0]
		mi.material_override = steel
		mi.position = pp[1]
		mi.rotation = pp[2]
		n.add_child(mi)
	_steam = CPUParticles3D.new()
	_steam.amount = 24
	_steam.lifetime = 1.6
	_steam.emitting = false
	_steam.position = Vector3(0.14, 0.2, 0)
	_steam.direction = Vector3(0.3, 1, 0)
	_steam.spread = 15.0
	_steam.gravity = Vector3(0, 0.25, 0)
	_steam.initial_velocity_min = 0.15
	_steam.initial_velocity_max = 0.3
	_steam.scale_amount_min = 0.6
	_steam.scale_amount_max = 1.4
	var puff := SphereMesh.new()
	puff.radius = 0.025
	puff.height = 0.05
	_steam.mesh = puff
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1, 1, 1, 0.25)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_steam.material_override = sm
	n.add_child(_steam)
	return n


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "top", 520)
	Ui.label(box, "JUKAN AAMUKAHVIT", 24, Ui.YELLOW)
	_meter = Ui.Meter.new()
	box.add_child(_meter)
	_info = Ui.label(box, "", 17)


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
	_ui.visible = true
	_refresh()
	return true


func act() -> void:
	match _state:
		"":
			_state = "vesi"
			_p = 0.0
			_pot.visible = true
			_boil_on(true)
			Sfx.play_on(_pot, "water", -10.0, 1.4)
		"vesi":
			_weak = _p < BOIL
			_state = "kiehuu"
			_p = 0.0
			Sfx.play_on(_pot, "cloth", -10.0, 1.6)
			if _weak:
				game.toast("Vesi ei vielä kiehunut – kahvista tulee laihaa.", 2.5)
		"kiehuu":
			_pour(_p)
	_refresh()


## Pannu pois liedeltä: vaahdon korkeudesta riippuu, onnistuiko kahvi.
func _pour(foam: float) -> void:
	_state = ""
	_pot.visible = false
	_boil_on(false)
	if foam >= 1.0:
		game.toast("Kahvi kiehui yli! Liesi on purujen peitossa. Uusi pannu tulille.", 3.5)
		Sfx.play("lose", -10.0)
		return
	if foam < FOAM.x:
		game.toast("Nostit pannun liian aikaisin – purut eivät ehtineet kiehahtaa. Kaksi kuppia laihaa.", 3.5)
		add(2)
	elif _weak:
		game.toast("Kahvi kiehahti, mutta vesi oli haaleaa. Kolme kuppia laihanpuoleista pöytään.", 3.5)
		add(3)
	else:
		game.toast("Täydellinen pannukahvi! Neljä kuppia pöytään – aamu voi alkaa.", 3.5)
		Sfx.play("win_small", -8.0)
		add(4)
	_made += 1


func stop(_why := "") -> void:
	_ui.visible = false
	_pot.visible = false
	_boil_on(false)
	_state = ""
	game.player.pose = ""
	if _made > 0:
		game.toast("Keitit %d pannullista. Pöydässä nyt %d kuppia kahvia." % [_made, kupit], 4.0)


func prompt() -> String:
	var t: String = {"": "E: pannu liedelle", "vesi": "E: kahvinpurut veteen, kun vesi kiehuu",
		"kiehuu": "E: pannu pois liedeltä, kun kahvi kiehahtaa"}[_state]
	return t + " · W: lopeta"


## Kuppeja pöytään (keitetty tai tietokoneen Jukan keittämä).
func add(n: int) -> void:
	_set_count(mini(MAX_CUPS, kupit + n))
	game.mp.send({"t": "kahvi", "n": kupit})


## Pöytään istuva juo kupin, jos kahvia on: kunto täyteen ja humala laskee.
func drink() -> void:
	if kupit <= 0:
		return
	_set_count(kupit - 1)
	game.mp.send({"t": "kahvi", "n": kupit})
	var p: CharacterBody3D = game.player
	p.stamina = 100.0
	p.exhausted = false
	p.promille = maxf(0.0, p.promille - SOBER)
	game.toast("Jukan pannukahvia. Pää selkenee ja jalka nousee!", 3.0)
	Sfx.play("glass", -10.0, 0.8)


## Kupit pöydässä: valkoiset kupit tummalla kahvilla, rivissä.
func _set_count(n: int) -> void:
	kupit = n
	for ch in _cups.get_children():
		ch.queue_free()
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.96, 0.96, 0.94)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.11, 0.05)
	dark.roughness = 0.2
	for k in kupit:
		var o := Vector3((k % 4) * 0.1 - 0.15, 0, (k / 4) * 0.1)
		for pp in [[B.cyl(0.035, 0.028, 0.06, 12), white, o + Vector3.UP * 0.03], [B.cyl(0.032, 0.032, 0.003, 12), dark, o + Vector3.UP * 0.055]]:
			var mi := MeshInstance3D.new()
			mi.mesh = pp[0]
			mi.material_override = pp[1]
			mi.position = pp[2]
			_cups.add_child(mi)


func _boil_on(on: bool) -> void:
	_steam.emitting = on
	if on and _boil == null:
		_boil = Sfx.loop_on(_pot, "water", -16.0)
		_boil.pitch_scale = 0.6
	elif not on and _boil != null:
		_boil.queue_free()
		_boil = null


func _process(delta: float) -> void:
	if not _ui.visible:
		return
	match _state:
		"vesi":
			_p = minf(1.0, _p + HEAT * delta)
			_steam.speed_scale = clampf((_p - 0.3) * 2.0, 0.1, 1.0)  # höyry voimistuu veden kuumetessa
		"kiehuu":
			_p += RISE * delta
			if _p >= 1.0:
				_pour(1.0)
	_refresh()


func _refresh() -> void:
	match _state:
		"vesi":
			_meter.zones = [[0.0, BOIL, Color(0.35, 0.55, 0.85, 0.6)], [BOIL, 1.0, Color(0.25, 0.7, 0.3, 0.85)]]
			_meter.set_value(_p)
			_info.text = "Vesi %s" % ("kiehuu – purut sekaan!" if _p >= BOIL else "kuumenee…")
		"kiehuu":
			_meter.zones = [[0.0, FOAM.x, Color(0.55, 0.4, 0.25, 0.6)], [FOAM.x, FOAM.y, Color(0.25, 0.7, 0.3, 0.85)],
				[FOAM.y, 1.0, Color(0.8, 0.25, 0.15, 0.85)]]
			_meter.set_value(_p)
			_info.text = "Vaahto nousee: nosta pannu pois vihreällä, ennen kuin kiehuu yli!"
		_:
			_meter.zones = []
			_meter.set_value(0.0)
			_info.text = "Pöydässä %d kuppia kahvia." % kupit
