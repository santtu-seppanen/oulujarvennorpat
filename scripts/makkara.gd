extends Node
## Makkaranpaisto nuotiolla (nuotio.gd): pelaaja istuu hirrelle ja paistaa makkaraa tikun päässä. A/D siirtää
## makkaraa hiilloksen yllä: makkara kypsyy tasaisesti hiilloksella, mutta liekit vaeltavat nuotiossa, ja
## liekissä makkara noettuu ja palaa. E nostaa makkaran pois ja syö sen: raaka ja palanut makkara ovat
## molemmat huonoja, täydellisestä nuotiomakkarasta kunto palaa täyteen.

const Ui := preload("res://scripts/ui.gd")
const Chat := preload("res://scripts/chat.gd")

const SPEED := 1.3  # makkaran siirto sekunnissa (palkin leveys on 2)
const REACH := 1.05  # makkaraa voi viedä näin kauas keskeltä
const BASE := 0.065  # kypsyminen sekunnissa hiilloksen keskellä
const FLAME_RATE := 0.28  # liekissä kypsyminen kovenee tämän verran sekunnissa
const FLAME_W := 0.15  # liekin puolikas leveys
const SOOT_RATE := 0.4  # nokeaminen sekunnissa liekissä
const RAW := 0.5
const DONE := Vector2(0.55, 0.9)
const BURN := 1.0  # tästä ylöspäin palanut
const SOOT_MAX := 0.6  # tästä ylöspäin noessa palanut
const SOOT_OK := 0.35

var game: Node3D
var _on := false
var _state := ""  # "" | "paisto"
var _x := 0.0
var _p := 0.0
var _soot := 0.0
var _t := 0.0
var _made := 0
var _good := 0
var _ui: CanvasLayer
var _strip: Strip
var _meter: Ui.Meter
var _info: Label
var _stick: MeshInstance3D
var _sausage: MeshInstance3D
var _mat: StandardMaterial3D


## Lämpöpalkki: hiillos (oranssi) ja vaeltavat liekit (punakeltainen), makkaran paikka valkoisena.
class Strip:
	extends Control
	var flames: Array = []
	var x := 0.0
	var reach := 1.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 46)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
		var n := 40
		for k in n:
			var u := (k + 0.5) / n * 2.0 - 1.0
			var h := clampf((1.1 - absf(u)) / 0.5, 0.0, 1.0)
			draw_rect(Rect2(Vector2(size.x * k / n, size.y * (1.0 - 0.55 * h)), Vector2(size.x / n + 1, size.y * 0.55 * h)),
				Color(0.85, 0.35, 0.08, 0.35 + 0.5 * h))
		for f: float in flames:
			var cx := size.x * (f + 1.0) * 0.5
			var w := size.x * 0.5 * 0.15
			draw_colored_polygon(PackedVector2Array([Vector2(cx - w, size.y), Vector2(cx, 2), Vector2(cx + w, size.y)]),
				Color(1.0, 0.3, 0.1, 0.85))
			draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 0.5, size.y), Vector2(cx, size.y * 0.4),
				Vector2(cx + w * 0.5, size.y)]), Color(1.0, 0.85, 0.3, 0.9))
		var mx := size.x * (x + 1.0) * 0.5
		draw_rect(Rect2(Vector2(mx - 3, 0), Vector2(6, size.y)), Color.WHITE)
		draw_rect(Rect2(Vector2.ZERO, size), Ui.YELLOW, false, 1.5)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "bottom", 560)
	Ui.label(box, "NUOTIO · MAKKARANPAISTO", 20, Ui.YELLOW)
	_strip = Strip.new()
	box.add_child(_strip)
	_meter = Ui.Meter.new()
	box.add_child(_meter)
	_info = Ui.label(box, "", 16)
	_mat = StandardMaterial3D.new()
	_stick = MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = 0.01
	sc.bottom_radius = 0.012
	sc.height = 1.0
	_stick.mesh = sc
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.2)
	_stick.material_override = wood
	_stick.visible = false
	game.add_child(_stick)
	_sausage = MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.035
	cap.height = 0.2
	_sausage.mesh = cap
	_sausage.material_override = _mat
	_sausage.visible = false
	game.add_child(_sausage)


func start() -> bool:
	game.nuotio.sit_player()
	_on = true
	_state = ""
	_made = 0
	_good = 0
	_ui.visible = true
	_refresh()
	return true


func stop(_why := "") -> void:
	_on = false
	_ui.visible = false
	_stick.visible = false
	_sausage.visible = false
	_state = ""
	game.nuotio.stand_player()
	if _made > 0:
		game.toast("Paistoit %d makkaraa nuotiolla, joista %d hyvää." % [_made, _good], 4.0)


func prompt() -> String:
	if _state == "":
		return "E: pistä makkara tikun päähän · W: poistu nuotiolta"
	return "A/D: siirrä makkaraa hiilloksella (ei liekkiin!) · E: nosta pois ja syö · W: poistu nuotiolta"


func act() -> void:
	if _state == "":
		_state = "paisto"
		_p = 0.0
		_soot = 0.0
		_x = 0.0
		_stick.visible = true
		_sausage.visible = true
		Sfx.play("pickup", -8.0)
	else:
		_eat()
	_refresh()


## Liekkien paikat palkilla (-1..1): kaksi vaeltavaa liekkiä.
func flames() -> Array:
	return [0.75 * sin(_t * 0.9 + 0.5), 0.8 * sin(_t * 0.55 + 2.4)]


func in_flame() -> bool:
	for f: float in flames():
		if absf(_x - f) < FLAME_W:
			return true
	return false


## Hiilloksen lämpö kohdassa x (0..1): tasainen keskellä, vähenee reunoilla.
static func ember(x: float) -> float:
	return clampf((1.1 - absf(x)) / 0.5, 0.0, 1.0)


## Kypsyyden mukainen tulos: "raaka" | "melkein" | "hyva" | "palanut".
func grade() -> String:
	if _p > BURN or _soot >= SOOT_MAX:
		return "palanut"
	if _p < RAW:
		return "raaka"
	if _p < DONE.x or _p > DONE.y or _soot > SOOT_OK:
		return "melkein"
	return "hyva"


func _eat() -> void:
	_state = ""
	_stick.visible = false
	_sausage.visible = false
	_made += 1
	var p: CharacterBody3D = game.player
	match grade():
		"hyva":
			game.toast("Täydellinen nuotiomakkara! Kunto palaa.", 4.0)
			Sfx.play("win_small", -8.0)
			p.stamina = 100.0
			_good += 1
			game.tarina.complete("makkara")
		"melkein":
			game.toast("Ihan hyvä makkara, vähän nokinen tai vaisu. Kelpaa kyllä.", 3.5)
			p.stamina = minf(100.0, p.stamina + 40.0)
		"raaka":
			game.toast("Raaka makkara. Vatsa kurnii.", 3.5)
			Sfx.play("lose", -10.0)
			p.stamina = maxf(0.0, p.stamina - 35.0)
		_:
			game.toast("Hiiltynyt makkara. Pitäisi pysyä hiilloksella, ei liekissä.", 3.5)
			Sfx.play("lose", -10.0)


func _process(delta: float) -> void:
	_t += delta
	if not _on:
		return
	if not Chat.typing:
		_x = clampf(_x + Input.get_axis("left", "right") * SPEED * delta, -REACH, REACH)
	if _state == "paisto":
		_cook(delta)
	_place()
	_strip.flames = flames()
	_strip.x = _x
	_strip.queue_redraw()
	_refresh()


func _cook(delta: float) -> void:
	var rate := BASE * ember(_x)
	if in_flame():
		rate += FLAME_RATE
		_soot += SOOT_RATE * delta
	_p += rate * delta
	var c := Color(0.85, 0.45, 0.45).lerp(Color(0.55, 0.28, 0.14), clampf(_p / 0.7, 0.0, 1.0))
	c = c.lerp(Color(0.04, 0.03, 0.03), clampf(maxf(_soot, (_p - DONE.y) / 0.4), 0.0, 1.0))
	_mat.albedo_color = c
	if _p >= 1.3:
		_eat()


## Tikku ja makkara nuotion päälle, tikun toinen pää pelaajan kädessä.
func _place() -> void:
	if _state != "paisto":
		return
	var p: CharacterBody3D = game.player
	var right: Vector3 = p.global_transform.basis.x
	var fwd: Vector3 = -p.global_transform.basis.z
	var tip: Vector3 = game.nuotio.pos + Vector3(0, 0.42, 0) + right * (_x * 0.42)
	var hand: Vector3 = p.global_position + Vector3(0, 0.75, 0) + fwd * 0.25 + right * 0.15
	var d := tip - hand
	_stick.mesh.height = d.length()
	_stick.global_position = (tip + hand) * 0.5
	_stick.look_at(tip, Vector3.UP)
	_stick.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	_sausage.global_position = tip - d.normalized() * 0.1
	_sausage.look_at(tip, Vector3.UP)
	_sausage.rotate_object_local(Vector3.RIGHT, PI * 0.5)


func _refresh() -> void:
	_strip.visible = _state != ""
	_meter.visible = _state != ""
	if _state == "":
		_info.text = "Nuotio rätisee. E pistää makkaran tikun päähän."
		return
	_meter.zones = [[0.0, RAW / 1.3, Color(0.8, 0.4, 0.4, 0.7)], [DONE.x / 1.3, DONE.y / 1.3, Color(0.25, 0.7, 0.3, 0.85)],
		[DONE.y / 1.3, 1.0, Color(0.3, 0.2, 0.2, 0.85)]]
	_meter.set_value(_p / 1.3)
	_info.text = "Liekissä makkara noettuu%s" % (": NOKEA!" if _soot > SOOT_OK else ". Pysy hiilloksella ja nosta pois vihreällä.")
