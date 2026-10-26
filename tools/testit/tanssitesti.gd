extends SceneTree
## Tanssilattian rytmipelin testi (headless): godot --headless --fixed-fps 60 --path . -s tools/testit/tanssitesti.gd
## - Askelkartta: riittävästi askelia, aikajärjestyksessä, kaikilla kaistoilla.
## - Täydellinen tanssi baarin tanssilattialla: koko putki, tulos lähes 100 %, aktiviteetti päättyy.
## - Ilman painalluksia kaikki huti: tulos 0. Väärä painallus katkaisee putken.

var main: Node3D
var fails := 0
var frames := 0
var step := 0
var Hb: GDScript
var Tanssi: GDScript


func _initialize() -> void:
	load("res://scripts/main.gd").skip_menu = true
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Hb = load("res://scripts/happybeach.gd")
	Tanssi = load("res://scripts/tanssi_game.gd")


func check(ok: bool, what: String) -> void:
	print(("OK   " if ok else "VIKA ") + what)
	if not ok:
		fails += 1


func _process(_d: float) -> bool:
	frames += 1
	if frames < 60:
		return false
	match step:
		0:
			main.sun.t_utc = main.sun._local_to_utc(2026, 7, 11, 21, 0)
			main.sun._update(true)
			var e: Array = Hb.SPOTS["tanssi"]
			main.player.global_position = main.world.happy.world_at(e[0], e[1])
			main.player.velocity = Vector3.ZERO
			step = 1
		1:
			check(main.world.happy.spot_at(main.player.global_position).get("id", "") == "tanssi", "tanssilattian toimintopiste")
			main.start_activity("baari")
			var b: Node = main.baari
			var g: Node = b._gnode
			check(main.activity == "baari" and b.in_game and g.get_script() == Tanssi, "tanssi aukeaa rytmipelinä")
			var notes: Array = g._notes
			var lanes := {}
			var sorted := true
			for i in notes.size():
				lanes[notes[i].lane] = true
				if i > 0 and notes[i].t < notes[i - 1].t:
					sorted = false
			check(notes.size() >= 80 and sorted and lanes.size() == 4, "askelkartta: %d askelta, 4 kaistaa, aikajärjestyksessä" % notes.size())
			# Täydellinen tanssi: jokainen askel täsmälleen tahtiin.
			for n in notes:
				g._t = n.t
				g.lane_press(n.lane)
				g._down[n.lane] = false
			check(g.best_combo == notes.size() and g.current_score() > 0.9, "täydellinen tanssi: putki %d, tulos %d %%" % [g.best_combo, roundi(g.current_score() * 100.0)])
			check(g.multiplier() >= 1.6, "putki nostaa kertoimen 1,6:een")
			g._t = g._end + 0.1
			g.step(0.01)
			check(not b.in_game and main.activity == "", "tanssi päättyy ja aktiviteetti loppuu")
			check(main.tarina.EXTRA[2].any(func(t: Dictionary) -> bool: return t.id == "tanssi"), "lauantain tehtävissä on tanssi")
			step = 2
		2:
			var g: Node = Tanssi.new()
			var res := []
			g.finished.connect(func(s: float, c: int) -> void: res.append([s, c]))
			root.add_child(g)
			for i in 4000:
				g.step(0.05)
			check(res.size() == 1 and res[0][0] == 0.0 and res[0][1] == 0, "ilman painalluksia tulos 0")
			var g2: Node = Tanssi.new()
			root.add_child(g2)
			var first: Dictionary = g2._notes[0]
			g2._t = first.t
			g2.lane_press(first.lane)
			g2._down[first.lane] = false
			check(g2._combo == 1, "osuma kasvattaa putkea")
			g2.lane_press((first.lane + 1) % 4, first.t + 5.0)
			check(g2._combo == 0, "väärä painallus katkaisee putken")
			g.queue_free()
			g2.queue_free()
			step = 3
		3:
			print("Valmis, vikoja: %d" % fails)
			quit(1 if fails > 0 else 0)
	return false
