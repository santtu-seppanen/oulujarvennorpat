extends RefCounted
## Hahmojen ulkonäöt character.gd:lle (Quaternius Universal Base Characters, CC0).

const Character := preload("res://scripts/character.gd")

## Pelaaja: järvimies maastovihreässä takissa, farkuissa ja kumisaappaissa, parta.
const PLAYER := {
	"shirt": Color(0.24, 0.32, 0.2), "pants": Color(0.2, 0.26, 0.4), "shoes": Color(0.1, 0.12, 0.1),
	"hair": "Hair_SimpleParted", "hair_color": Color(0.35, 0.25, 0.15), "beard": true, "height": 1.8,
	"belly": 0.3, "bulk": 0.05,
}


static func make(parent: Node3D, look: Dictionary) -> Node3D:
	var c := Character.new()
	parent.add_child(c)
	c.setup(look)
	return c
