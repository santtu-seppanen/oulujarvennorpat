extends SceneTree
## Mökkipihan testi (headless): godot --headless --path . -s tools/testit/mokkitesti.gd
## Portaat ylös, laiturilla kuivana, kumiveneellä soutu, tietokoneen hahmojen liikkuminen ja auringonlaskun aika.

class Push:
	extends RefCounted
	var throttle := 1.0
	var steer := 0.0
	var fast := false
	var jump := false

	func think(_d: float) -> void:
		pass


var main: Node3D
var Mokki: GDScript
var frames := 0
var fails := 0
var start := {}
var push := Push.new()


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Mokki = load("res://scripts/mokki.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _process(_delta: float) -> bool:
	frames += 1
	var p: CharacterBody3D = main.player
	match frames:
		5:
			var sun = main.sun
			sun.t_utc = sun._local_to_utc(2026, 7, 7, 12, 0)
			var d: Dictionary = sun.today()
			print("7.7.2026 aurinko laskee %s, nousee %s" % [d.set, d.rise])
			# Valokuvassa 20260707_232437 aurinko koskettaa horisonttia: alareuna pinnassa, keskipiste ~0,27° yllä.
			var at: Vector2 = sun.position_at(sun._local_to_utc(2026, 7, 7, 23, 24))
			print("7.7. klo 23.24 aurinko %.2f° suunnassa %.0f°" % [at.x, at.y])
			check(at.x > 0.0 and at.x < 0.6 and absf(at.y - 334.0) < 2.0, "aurinko koskettaa horisonttia NNW:ssä klo 23.24")
			sun.start_preset(0)
			for b in main.crew:
				start[b] = b.global_position
			# Portaiden alapäähän kasvot ylös.
			var e: Array = Mokki.stair_ends()
			var a: Vector2 = e[0]
			var t: Vector2 = e[1]
			p.global_position = Vector3(a.x, Mokki.DY + 0.1, a.y) + Vector3((t - a).normalized().x, 0, (t - a).normalized().y) * 0.3
			p.rotation.y = atan2(-(t - a).x, -(t - a).y)
			p.brain = push
		480:
			print("portaiden jälkeen y %.2f (ylämökin lattia %.2f)" % [p.global_position.y, Mokki.floor_y()])
			check(p.global_position.y > Mokki.floor_y() - 0.4, "portaat ylös ylämökin terassille")
			# Laiturille.
			var w: Vector2 = Mokki.yw(-2.2, 10.0)
			p.brain = null
			p.global_position = Vector3(w.x, 0.6, w.y)
			p.velocity = Vector3.ZERO
		540:
			print("laiturilla: syvyys %.2f, lattialla %s, puuta %s" % [p.water_depth, p.is_on_floor(), p.on_wood])
			check(p.water_depth < 0.01 and p.is_on_floor(), "laiturilla ei kahlata")
			# Veneeseen ja soutamaan.
			p.global_position = main.boat.global_position + Vector3(0.5, 0.5, 0)
			p.enter_boat(main.boat)
			p.brain = push
			start["boat"] = main.boat.global_position
		1100:
			var moved: float = main.boat.global_position.distance_to(start.boat)
			print("vene liikkui %.1f m, nopeus %.2f m/s" % [moved, main.boat.speed])
			check(moved > 2.0, "kumivene liikkuu soutamalla")
			p.brain = null
			p.leave_boat()
		1130:
			check(p.boat == null and not p._shape.disabled, "veneestä noustu")
			var n := 0
			for b in main.crew:
				if b != p:
					var d: float = b.global_position.distance_to(start[b])
					print("%s: %s, liikkui %.1f m, asento %s" % [b.display_name, b.brain.activity, d, b.pose])
					if d > 1.0 or b.hidden_inside or b.pose != "":
						n += 1
			check(n >= 2, "tietokoneen hahmot touhuavat")
			print("vikoja %d" % fails)
			return true
	return false
