extends Node
## Ympäristöäänet pelaajan ympäristön mukaan (maaston pintaluokat): metsän humina ja linnut metsässä,
## laineiden loiske rannalla ja vedessä, tuuli aukealla ja järvenselällä, varikset satunnaisesti.

const Terrain := preload("res://scripts/terrain.gd")

var player: Node3D
var _loops := {}
var _want := {}
var _probe_t := 0.0
var _crow_t := 20.0


func _ready() -> void:
	for k in ["amb_forest", "amb_birds", "wind", "water"]:
		var p := AudioStreamPlayer.new()
		p.stream = Sfx.stream(k)
		p.bus = "Ambience"
		p.volume_db = -80.0
		add_child(p)
		p.play()
		_loops[k] = p
		_want[k] = -80.0


func _process(delta: float) -> void:
	if player == null:
		return
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = 0.5
		_probe(player.global_position)
	for k in _loops:
		var p: AudioStreamPlayer = _loops[k]
		p.volume_db = move_toward(p.volume_db, _want[k], 12.0 * delta)
	_crow_t -= delta
	if _crow_t <= 0.0:
		_crow_t = randf_range(25.0, 70.0)
		if _want.amb_birds > -40.0:
			Sfx.play("crow", -18.0, randf_range(0.9, 1.1))


## Ympäristön osuudet 40 m säteellä: metsä, vesi.
func _probe(p: Vector3) -> void:
	var forest := 0.0
	var water := 0.0
	var n := 0.0
	for r: float in [0.0, 15.0, 40.0]:
		for k in (1 if r == 0.0 else 8):
			var d := Vector2.from_angle(TAU * k / 8.0) * r
			var s := Terrain.surface(p.x + d.x, p.z + d.y)
			n += 1.0
			if s == Terrain.WATER or s == Terrain.POND:
				water += 1.0
			elif s in [Terrain.FOREST, Terrain.BOG, Terrain.CLEARING]:
				forest += 1.0
	forest /= n
	water /= n
	_want.amb_forest = linear_to_db(maxf(forest * 0.9, 0.0001))
	_want.amb_birds = linear_to_db(maxf(forest * 0.6, 0.0001))
	_want.water = linear_to_db(maxf(clampf(water * 1.8, 0.0, 1.0) * (1.0 - water * 0.5), 0.0001)) - 6.0
	_want.wind = linear_to_db(maxf(0.15 + water * 0.7, 0.0001)) - 8.0
