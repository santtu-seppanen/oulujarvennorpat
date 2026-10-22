extends Node
## Illan pihvit grillikatoksen kaasugrillillä: vain Marko saa grillata. E laittaa pihvit grillille, ja kun ne ovat
## kypsiä (vihreä alue), E nostaa ne pois ennen kuin ne palavat. Onnistuneesta erästä tulee neljä pihviä
## tarjoilupöydälle (tarjoilupoyta.gd), raakana tai palaneena vähemmän. Tehtävä kuittautuu klo 20-22.

const Ui := preload("res://scripts/ui.gd")

const SPEED := 0.12  # kypsyminen sekunnissa
const RAW := 0.55
const DONE := Vector2(0.55, 0.85)

var game: Node3D
var grilled := 0
var _state := ""  # "" | "gril"
var _p := 0.0
var _made := 0
var _ui: CanvasLayer
var _meter: Ui.Meter
var _info: Label
var _steaks: Node3D
var _steak_mat: StandardMaterial3D
var _smoke: CPUParticles3D
var _sizzle: AudioStreamPlayer3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Node3D = game.world.mokki
	_steaks = Node3D.new()
	_steaks.position = m.grill_pos
	_steaks.visible = false
	game.add_child(_steaks)
	_steak_mat = StandardMaterial3D.new()
	for k in 4:
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.07
		sp.height = 0.14
		mi.mesh = sp
		mi.material_override = _steak_mat
		mi.scale = Vector3(1.3, 0.3, 0.9)
		mi.position = Vector3((k % 2) * 0.2 - 0.1, 0.0, (k / 2) * 0.17 - 0.08)
		_steaks.add_child(mi)
	_smoke = CPUParticles3D.new()
	_smoke.amount = 20
	_smoke.lifetime = 1.8
	_smoke.direction = Vector3.UP
	_smoke.initial_velocity_min = 0.2
	_smoke.initial_velocity_max = 0.5
	_smoke.gravity = Vector3(0, 0.3, 0)
	_smoke.scale_amount_min = 0.05
	_smoke.scale_amount_max = 0.1
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	_smoke.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.8, 0.8, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke.material_override = mat
	_smoke.emitting = false
	_steaks.add_child(_smoke)
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "bottom", 520)
	Ui.label(box, "GRILLI · MARKON PIHVIT", 20, Ui.YELLOW)
	_meter = Ui.Meter.new()
	box.add_child(_meter)
	_info = Ui.label(box, "", 16)


func start() -> bool:
	var m: Node3D = game.world.mokki
	var p: CharacterBody3D = game.player
	p.global_position = m.grill_spot + Vector3(0, 0.05, 0)
	var d: Vector3 = m.grill_pos - p.global_position
	p.rotation.y = atan2(-d.x, -d.z)
	p.velocity = Vector3.ZERO
	p.pose = "Interact"
	_state = ""
	_made = 0
	_ui.visible = true
	_refresh()
	return true


func stop(_why := "") -> void:
	_ui.visible = false
	_steaks.visible = false
	_smoke.emitting = false
	_state = ""
	game.player.pose = ""
	if _made > 0:
		game.toast("Grillasit %d erää pihvejä. Tarjoilupöydällä nyt %d pihviä." % [_made, game.tarjoilu.pihvit], 5.0)


func prompt() -> String:
	return {"": "E: pihvit grillille", "gril": "E: pihvit pois grillistä, kun ne ovat kypsiä (vihreä)"}[_state] + " · W: lopeta"


func act() -> void:
	if _state == "":
		_state = "gril"
		_p = 0.0
		_steaks.visible = true
		_smoke.emitting = true
		Sfx.play("pickup", -8.0)
	else:
		_state = ""
		_steaks.visible = false
		_smoke.emitting = false
		var hour: int = game.sun.local().hour
		if _p < DONE.x:
			game.toast("Pihvit olivat vielä raakoja – vain yksi kelpaa.", 3.5)
			game.tarjoilu.add_steaks(1)
		elif _p <= DONE.y:
			game.toast("Täydellisen kypsät pihvit! Neljä pihviä tarjoilupöydälle.", 3.5)
			Sfx.play("win_small", -8.0)
			game.tarjoilu.add_steaks(4)
			_made += 1
			if hour >= 20 and hour < 22:
				game.tarina.complete("grilli")
		else:
			game.toast("Pihvit paloivat hiileksi – kaksi vielä kelpaa.", 3.5)
			Sfx.play("lose", -10.0)
			game.tarjoilu.add_steaks(2)
			_made += 1
	_refresh()


func _process(delta: float) -> void:
	if not _ui.visible or _state == "":
		return
	_p += SPEED * delta
	var c := Color(0.75, 0.45, 0.4).lerp(Color(0.35, 0.17, 0.1), clampf(_p / 0.6, 0.0, 1.0))
	if _p > DONE.y:
		c = Color(0.35, 0.17, 0.1).lerp(Color(0.05, 0.04, 0.04), clampf((_p - DONE.y) / 0.3, 0.0, 1.0))
	_steak_mat.albedo_color = c
	if _p >= 1.15:
		act()
		return
	_refresh()


func _refresh() -> void:
	_meter.zones = [[0.0, RAW, Color(0.8, 0.4, 0.4, 0.7)], [DONE.x, DONE.y, Color(0.25, 0.7, 0.3, 0.85)],
		[DONE.y, 1.15, Color(0.3, 0.2, 0.2, 0.85)]]
	_meter.set_value(_p / 1.15 if _state != "" else 0.0)
	_info.text = "Pihvit kypsyvät: nosta pois vihreällä." if _state != "" else "Kaasugrilli kuumana. E laittaa pihvit grillille. Tarjoilupöydällä %d pihviä." % game.tarjoilu.pihvit
