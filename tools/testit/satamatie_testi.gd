extends SceneTree
## Sataman tien ajotesti (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/satamatie_testi.gd
## Auto ajaa täyttä vauhtia mökin ajouran päästä satamaan tien keskiviivaa pitkin: ei törmäyksiä puihin,
## vauhti ei putoa.


var Satama: GDScript
var main: Node3D
var clock := 0.0
var started := false
var ri := 1
var min_speed := 99.0
var hits := 0
var done := false


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	Satama = load("res://scripts/satama.gd")
	main = load("res://main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	clock += delta
	if clock < 2.0:
		return false
	var car: CharacterBody3D = main.car
	var line: Array = Satama.ROAD_LINE
	if not started:
		started = true
		car.place(line[0], line[1])
		car.speed = 22.0
		return false
	var p := Vector2(car.global_position.x, car.global_position.z)
	while ri < line.size() - 1 and p.distance_to(line[ri]) < 8.0:
		ri += 1
	var want: Vector2 = line[ri] - p
	car.rotation.y = atan2(-want.x, -want.y)
	if car.speed > 3.0:
		car.speed = 22.0
	min_speed = minf(min_speed, car.speed)
	if car.get_slide_collision_count() > 0:
		hits += 1
	if ri >= line.size() - 1 or clock > 40.0:
		print("perillä=", ri >= line.size() - 1, " törmäyksiä=", hits, " min_vauhti=%.1f" % min_speed, " t=%.1f" % clock)
		return true
	return false
