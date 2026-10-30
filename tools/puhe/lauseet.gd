extends SceneTree
## Tulostaa nauhoitettavat repliikit (ääni <tab> teksti): godot --headless --path . -s tools/puhe/lauseet.gd
## Käytetään tools/puhe/nauhoita.py:stä.

func _initialize() -> void:
	var seen := {}
	for e: Array in load("res://scripts/puhe_lauseet.gd").all():
		var line := "LAUSE\t%s\t%s" % [e[0], str(e[1]).strip_edges()]
		if not seen.has(line):
			seen[line] = true
			print(line)
	quit()
