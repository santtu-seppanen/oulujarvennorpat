extends Node
## Saunominen alamökin löylyhuoneessa: istu lauteille (E), heitä löylyä (E) ja pidä oma kuumuus hyvien
## löylyjen alueella mahdollisimman pitkään. Löyly nostaa kuumuutta hetkeksi ja haihtuu sitten; liika löyly
## ajaa lauteilta ja suoraan järveen. Saunan jälkeen pulahdus järveen antaa lisäpisteet.
##
## Löyly on kaikille saunojille yhteinen: moninpelissä toisen heittämä löyly tuntuu kaikilla (viesti "loyly"),
## ja tietokoneen hahmot heittävät myös (mokki.gd loyly-signaali hostilla).

const Ui := preload("res://scripts/ui.gd")
const B := preload("res://scripts/build.gd")

const GOOD := 55.0  # hyvien löylyjen alaraja
const HOT := 85.0  # tästä ylöspäin liian kuuma
const DIP_TIME := 90.0  # näin kauan saunan jälkeen pulahdus järveen lasketaan

var game: Node3D
var loyly := 0.0  # löylyn määrä 0..100
var heat := 0.0  # oma kuumuus 0..100
var points := 0.0
var best := 0
var _dip_t := 0.0
var _steam: CPUParticles3D
var _ui: CanvasLayer
var _meter: Ui.Meter
var _info: Label
var _score: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m: Node3D = game.world.mokki
	m.loyly.connect(func() -> void: throw(true))
	game.mp.on("loyly", func(_d: Dictionary, _from: int) -> void: throw(false))
	_steam = CPUParticles3D.new()
	_steam.position = m.kiuas_pos
	_steam.emitting = false
	_steam.one_shot = true
	_steam.amount = 48
	_steam.lifetime = 3.2
	_steam.explosiveness = 0.6
	_steam.direction = Vector3.UP
	_steam.spread = 35.0
	_steam.initial_velocity_min = 0.4
	_steam.initial_velocity_max = 0.9
	_steam.gravity = Vector3(0, 0.25, 0)
	_steam.damping_min = 0.3
	_steam.damping_max = 0.6
	_steam.scale_amount_min = 0.25
	_steam.scale_amount_max = 0.5
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 2.2))
	_steam.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.35))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	_steam.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _puff()
	q.material = mat
	_steam.mesh = q
	game.add_child(_steam)
	_build_ui()


## Pehmeä pyöreä höyryhattara.
static func _puff() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	var box := Ui.panel(_ui, "top", 520)
	Ui.label(box, "LÖYLYT", 24, Ui.YELLOW)
	_meter = Ui.Meter.new()
	_meter.zones = [[0.0, GOOD / 100.0, Color(0.25, 0.45, 0.7, 0.7)], [GOOD / 100.0, HOT / 100.0, Color(0.25, 0.7, 0.3, 0.8)],
		[HOT / 100.0, 1.0, Color(0.85, 0.2, 0.1, 0.85)]]
	box.add_child(_meter)
	_info = Ui.label(box, "", 17)
	_score = Ui.label(box, "", 17, Ui.YELLOW)


# --- Toiminta (main.gd kutsuu) --------------------------------------------------------------------------------

func start() -> bool:
	var m: Node3D = game.world.mokki
	var i: int = m.free_seat(m.sauna_seats, game.player)
	if i < 0:
		game.toast("Lauteet ovat täynnä")
		return false
	game.player.sit_at(m.sauna_seats[i][0], m.sauna_seats[i][1])
	heat = maxf(heat, 30.0)
	points = 0.0
	_ui.visible = true
	Sfx.play("cloth", -8.0)
	return true


func act() -> void:
	throw(true)
	game.player.pose = "Sitting_Talking"


func stop(why := "") -> void:
	_ui.visible = false
	game.player.stand_up(true)
	var p := int(points)
	best = maxi(best, p)
	_dip_t = DIP_TIME
	game.toast((why + "\n" if why != "" else "") + "Löylypisteet %d (paras %d). Nyt järveen pulahtamaan!" % [p, best], 5.0)


func prompt() -> String:
	return "E: heitä löylyä · W: pois lauteilta"


## Löylyä kiukaalle: sihahdus, höyry ja kuumuus kaikille saunojille.
func throw(local: bool) -> void:
	loyly = minf(100.0, loyly + 38.0)
	Sfx.play_on(_steam, "water", -2.0, 0.55)
	Sfx.play_on(_steam, "whoosh", -6.0, 0.45)
	_steam.restart()
	if local:
		game.mp.send({"t": "loyly"})


func _process(delta: float) -> void:
	loyly -= loyly * 0.18 * delta
	if game.activity == "sauna":
		# Kuumuus hakeutuu löylyn mukaiseen tasoon: nousee nopeasti, laskee hitaasti.
		var target := 32.0 + loyly * 0.95
		heat += (target - heat) * (0.35 if target > heat else 0.1) * delta
		if heat >= GOOD and heat < HOT:
			points += delta * (2.0 if heat > 72.0 else 1.0)
		elif heat >= HOT:
			points = maxf(0.0, points - delta * 1.5)
		if game.player.pose == "Sitting_Talking" and loyly < 60.0:
			game.player.pose = "Sitting_Idle"
		_meter.set_value(heat / 100.0)
		if heat < GOOD:
			_info.text = "Viileää – heitä löylyä (E)"
		elif heat < HOT:
			_info.text = "Hyvät löylyt!" if heat < 72.0 else "Nyt on löylyä! Tuplapisteet"
		else:
			_info.text = "Liian kuuma! Anna löylyn laskea…"
		_score.text = "Löylypisteet %d" % int(points)
		if heat >= 99.5:
			game.end_activity("Liian kuumat löylyt!")
	else:
		heat = move_toward(heat, 0.0, 3.0 * delta)
	if _dip_t > 0.0:
		_dip_t -= delta
		if game.player.swimming:
			_dip_t = 0.0
			best = maxi(best, int(points) + 20)
			game.toast("Ahhh! Pulahdus järveen saunan jälkeen: +20 pistettä (yhteensä %d)" % (int(points) + 20), 5.0)
			Sfx.play("win_small", -6.0)
