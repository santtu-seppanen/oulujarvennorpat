extends SceneTree
## Piper-puhesynteesin testi (ei headless, koska puhe ohitetaan silloin): godot --audio-driver Dummy --path . -s tools/testit/piper_testi.gd
## Vaatii asennetun Piperin (sh tools/piper/asenna.sh). Neljä miesääntä puhuu, ja jono tyhjenee.
var p: Node
var t := 0.0
var step := 0
var spoken := 0.0


func _initialize() -> void:
	p = load("res://scripts/piper_puhe.gd").new()
	root.add_child(p)


func _process(delta: float) -> bool:
	t += delta
	match step:
		0:
			if p.is_up:
				print("OK   Piper-palvelin valmis (%.1f s)" % t)
				for v in [[1.0, 1.0], [0.84, 0.95], [1.13, 1.08], [0.74, 0.88]]:
					print("OK   jonoon: ", p.speak("Muistatko kun uitiin pimeässä ja huudettiin kaikki yhtä aikaa?", v[0], v[1], 0.8))
				step = 1
				t = 0.0
			elif t > 60.0:
				print("VIKA Piper ei käynnisty")
				quit(1)
				return true
		1:
			if p.speaking():
				spoken += delta
			elif t > 1.0:
				print("OK   neljä puhetta soitettu, kesto %.1f s" % spoken if spoken > 8.0 else "VIKA puhe jäi lyhyeksi (%.1f s)" % spoken)
				quit(0)
				return true
			if t > 90.0:
				print("VIKA puhe ei päättynyt")
				quit(1)
				return true
	return false
