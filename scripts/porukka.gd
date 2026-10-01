extends RefCounted
## Mökin porukka valokuvista vasemmalta oikealle: Santtu, Marko, Jaakko ja Jukka. Kesämökillä uikkareissa
## paljain jaloin; tukka, vartalo ja korut kuvien mukaan. Pelaaja valitsee alussa yhden, muita ohjaa ai.gd.

const CREW := [
	{
		"name": "Santtu",
		"desc": "Lyhyt vaaleanruskea tukka pystyssä, hoikka, kultaketju kaulassa. Naurattaa aina.",
		"chain": Color(0.95, 0.75, 0.3),
		"look": {"hair": "Hair_SimpleParted", "hair_color": Color(0.55, 0.36, 0.2), "beard": false, "height": 1.8,
			"belly": 0.2, "bulk": -0.05, "shoulders": 0.05, "skin": Color(1.0, 0.86, 0.8),
			"pants": Color(0.12, 0.22, 0.48), "shoes": Color(0.86, 0.66, 0.55)},
	},
	{
		"name": "Marko",
		"desc": "Lyhyeksi ajeltu vaalea tukka, tukeva, hopeinen riipus ja tatuoinnit. Kumiveneen kapteeni.",
		"chain": Color(0.85, 0.85, 0.88),
		"pendant": true,
		"look": {"hair": "Hair_Buzzed", "hair_color": Color(0.86, 0.76, 0.52), "beard": false, "height": 1.79,
			"belly": 0.65, "bulk": 0.35, "shoulders": 0.25, "skin": Color(1.0, 0.82, 0.76),
			"pants": Color(0.08, 0.08, 0.09), "shoes": Color(0.9, 0.66, 0.56)},
	},
	{
		"name": "Jaakko",
		"desc": "Vaalea pörröinen tukka, pisin porukasta, karvainen rinta. Ensimmäisenä laiturin päässä.",
		"look": {"hair": "Hair_SimpleParted", "hair_color": Color(0.8, 0.66, 0.4), "beard": false, "height": 1.85,
			"belly": 0.3, "bulk": 0.05, "shoulders": 0.1, "skin": Color(1.0, 0.88, 0.8),
			"pants": Color(0.72, 0.12, 0.1), "shoes": Color(0.88, 0.68, 0.56)},
	},
	{
		"name": "Jukka",
		"desc": "Tumma lyhyt tukka ja sänkiparta, tukeva, iloinen virne. Grillimestari.",
		"look": {"hair": "Hair_Buzzed", "hair_color": Color(0.17, 0.12, 0.09), "beard": true, "height": 1.77,
			"belly": 0.55, "bulk": 0.25, "shoulders": 0.15, "skin": Color(1.0, 0.85, 0.76),
			"pants": Color(0.26, 0.33, 0.18), "shoes": Color(0.86, 0.64, 0.52)},
	},
]


## Täydentää ulkonäön: paljas yläruumis (sleeve_x < 0) ja polvipituiset uimashortsit.
static func look(i: int) -> Dictionary:
	var l: Dictionary = CREW[i].look.duplicate()
	l["sleeve_x"] = -1.0
	l["shorts_y"] = 0.58
	l["shirt"] = l.pants
	l["bare_skin"] = Color(0.93, 0.72, 0.6)
	return l


## Kaulakorut hahmon luustoon.
static func decorate(i: int, ch: Node3D) -> void:
	var c: Dictionary = CREW[i]
	if not c.has("chain"):
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = c.chain
	m.metallic = 0.9
	m.roughness = 0.25
	var t := TorusMesh.new()
	t.inner_radius = 0.085
	t.outer_radius = 0.093
	t.rings = 24
	t.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = t
	mi.material_override = m
	ch.attach("neck_01", mi, Vector3(0, -0.04, -0.035))
	mi.rotate_x(deg_to_rad(-38.0))
	if c.get("pendant", false):
		var p := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.016
		s.height = 0.04
		p.mesh = s
		p.material_override = m
		ch.attach("spine_03", p, Vector3(0, 0.06, -0.13))
