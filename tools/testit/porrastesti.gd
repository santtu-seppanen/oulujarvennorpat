extends SceneTree
## Portaiden testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/porrastesti.gd
## Pelaaja kävelee mökin kaikki portaat ylös ja alas pelkällä eteenpäin-syötteellä, hyppäämättä: päärappu
## terassilta ylämökille, rantaportaat, laiturin portaat ja ylämökin metsäportaat.

class Walk:
	extends RefCounted
	var body: CharacterBody3D
	var target := Vector3.ZERO
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump := false
	func reset() -> void:
		pass
	func think(_d: float) -> void:
		var p := body.global_position
		var d := Vector2(target.x - p.x, target.z - p.z)
		var diff := wrapf(atan2(-d.x, -d.y) - body.rotation.y, -PI, PI)
		steer = clampf(diff * 2.5, -1.0, 1.0)
		throttle = 1.0 if d.length() > 0.3 else 0.0
		jump = false

var main: Node3D
var M: GDScript
var frames := 0
var cases := []
var ci := -1
var t0 := 0
var w := Walk.new()
var fails := 0
var best := INF

func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	M = load("res://scripts/mokki.gd")

func v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

func build() -> void:
	var e: Array = M.stair_ends()
	var dir: Vector2 = (e[1] - e[0]).normalized()
	var fy: float = M.floor_y()
	var dy: float = M.DY
	var pairs := [
		["päärappu terassilta ylämökille", v3(e[0] - dir * 0.8, dy), v3(e[1] + dir * 0.8, fy)],
		["rantaportaat", v3(M.yw(-8.0, 4.4), 0.0), v3(M.yw(-8.0, 1.0), dy)],
		["laiturin portaat", v3(M.yw(-2.2, 6.8), 0.42), v3(M.yw(-2.2, 3.5), dy)],
		["ylämökin metsäportaat", M.cabin_steps_foot(), v3(M.cw(3.4, -2.5), fy)],
	]
	for pr in pairs:
		cases.append([pr[0] + " ylös", pr[1], pr[2]])
		cases.append([pr[0] + " alas", pr[2], pr[1]])

func start_case() -> void:
	var c: Array = cases[ci]
	var p: CharacterBody3D = main.player
	var a: Vector3 = c[1]
	var b: Vector3 = c[2]
	var T = load("res://scripts/terrain.gd")
	if a.y == 0.0:
		a.y = T.h(a.x, a.z)
		c[1] = a
	if b.y == 0.0:
		b.y = T.h(b.x, b.z)
		c[2] = b
	p.global_position = a + Vector3.UP * 0.3
	p.velocity = Vector3.ZERO
	var d := b - a
	p.rotation.y = atan2(-d.x, -d.z)
	w.body = p
	w.target = b
	p.brain = w
	t0 = frames
	best = INF

func _process(_d: float) -> bool:
	frames += 1
	if frames == 30:
		build()
		ci = 0
		start_case()
		return false
	if ci < 0:
		return false
	var p: CharacterBody3D = main.player
	var c: Array = cases[ci]
	var b: Vector3 = c[2]
	var dxz := Vector2(p.global_position.x - b.x, p.global_position.z - b.z).length()
	best = minf(best, dxz)
	var done := dxz < 0.5 and absf(p.global_position.y - b.y) < 0.35
	if done or frames - t0 > 60 * 20:
		var ok := done
		print(("OK   " if ok else "VIKA ") + "%s: %.1f s, loppu y %.2f (tavoite %.2f), lähin %.2f m, paikka %s" % [c[0], (frames - t0) / 60.0, p.global_position.y, b.y, best, p.global_position])
		if not ok:
			fails += 1
		ci += 1
		if ci >= cases.size():
			print("VIKOJA ", fails)
			quit(fails)
			return true
		start_case()
	return false
