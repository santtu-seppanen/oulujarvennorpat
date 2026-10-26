extends RefCounted
## Kartan (map_view.gd) ja tutkan (minimap.gd) kiinnostavat kohteet: mökki ja sen paikat, Happy Beach ja ravintola, kätköt
## (myös omat), pallopelipaikat, mustikat, ranta, vene, auto ja porukka. Jokainen kohde: {name, p (x, z), kind, major}.
## Reitit (reitit()) piirretään viivoina: Happy Beachin ajoreitti ja tutkimusmatkan soutureitti.

const Mokki := preload("res://scripts/mokki.gd")
const Reitti := preload("res://scripts/reitti.gd")
const Ranta := preload("res://scripts/ranta.gd")
const Rantatennis := preload("res://scripts/rantatennis.gd")
const Amerikanpallo := preload("res://scripts/amerikanpallo.gd")
const Tutkimusmatka := preload("res://scripts/tutkimusmatka.gd")
const Happybeach := preload("res://scripts/happybeach.gd")

## Lajit: väri ja selite.
const KINDS := {
	"koti": [Color(1.0, 0.85, 0.1), "mökki"],
	"leiri": [Color(0.1, 0.7, 0.75), "Happy Beach"],
	"katko": [Color(0.95, 0.55, 0.05), "viinakätkö"],
	"peli": [Color(0.3, 0.75, 0.3), "pallopeli"],
	"paikka": [Color(0.85, 0.85, 0.85), "paikka"],
	"mustikka": [Color(0.3, 0.3, 0.8), "mustikat"],
	"kulku": [Color(0.9, 0.3, 0.3), "auto ja vene"],
	"porukka": [Color(0.9, 0.4, 0.8), "porukka"],
}


static func _v(p: Vector2) -> Vector2:
	return p


static func list(game: Node3D) -> Array:
	var out: Array = []
	var w: Node3D = game.world
	var s: Vector3 = w.start_position()
	out.append({"name": "Mökki", "p": Vector2(s.x, s.z), "kind": "koti", "major": true})
	out.append({"name": "Happy Beach", "p": Reitti.K, "kind": "leiri", "major": true})
	var door := Reitti.cw(-4.0, 16.9)
	out.append({"name": "Ravintola (baari, karaoke)", "p": door, "kind": "leiri", "major": false})
	out.append({"name": "Happy Beachin laituri", "p": Reitti.cw(14.0, 54.0), "kind": "leiri", "major": false})
	out.append({"name": "Parkkipaikka", "p": Reitti.cw(10.0, -6.0), "kind": "leiri", "major": false})
	out.append({"name": "Auton paikka", "p": Reitti.HOME_SPOT, "kind": "paikka", "major": false})
	# Mökin paikat.
	out.append({"name": "Huussi", "p": Mokki.yw(11.5, -1.7), "kind": "paikka", "major": false})
	out.append({"name": "Grillikatos", "p": Mokki.yw(-9.0, -1.4), "kind": "paikka", "major": false})
	out.append({"name": "Nuotiopaikka", "p": Vector2(game.nuotio.pos.x, game.nuotio.pos.z), "kind": "paikka", "major": false})
	out.append({"name": "Tarjoilupöytä", "p": game.tarjoilu.pos_xz(), "kind": "paikka", "major": false})
	out.append({"name": "Rantatennis", "p": Rantatennis.fw(0.0, 0.0), "kind": "peli", "major": false})
	out.append({"name": "Jalkapallon heitto", "p": Mokki.yw(Amerikanpallo.AREA_C.x, Amerikanpallo.AREA_C.y), "kind": "peli",
		"major": false})
	out.append({"name": "Hiekkaranta", "p": Vector2((Ranta.BEACH_X.x + Ranta.BEACH_X.y) * 0.5, (Ranta.BEACH_Z.x + Ranta.BEACH_Z.y) * 0.5),
		"kind": "paikka", "major": true})
	out.append({"name": "Viinakätkö (sauna)", "p": Vector2(w.mokki.stash_pos.x, w.mokki.stash_pos.z), "kind": "katko", "major": false})
	out.append({"name": "Viinakätkö (ranta)", "p": Vector2(w.ranta.stash_pos.x, w.ranta.stash_pos.z), "kind": "katko", "major": false})
	out.append({"name": "Tutkimusmatkan kätkö", "p": Vector2(game.retki.stash_pos.x, game.retki.stash_pos.z), "kind": "katko",
		"major": true})
	for sp: Vector3 in game.omat_katkot.spots:
		out.append({"name": "Oma kätkö", "p": Vector2(sp.x, sp.z), "kind": "katko", "major": false})
	for b: Dictionary in game.mustikat.bushes:
		out.append({"name": "", "p": Vector2(b.p.x, b.p.z), "kind": "mustikka", "major": false})
	# Liikkuvat: auto, vene ja porukka.
	if game.car != null:
		out.append({"name": "Auto", "p": Vector2(game.car.global_position.x, game.car.global_position.z), "kind": "kulku",
			"major": true})
	if game.boat != null:
		out.append({"name": "Kumivene", "p": Vector2(game.boat.global_position.x, game.boat.global_position.z), "kind": "kulku",
			"major": false})
	for i in game.crew.size():
		if i == game.player_index:
			continue
		var b: CharacterBody3D = game.crew[i]
		if b.visible:
			out.append({"name": game.Porukka.CREW[i].name, "p": Vector2(b.global_position.x, b.global_position.z), "kind": "porukka",
				"major": false})
	return out


## Reitit viivoina: [nimi, pisteet, väri].
static func reitit() -> Array:
	var rowing: Array = []
	for p: Vector2 in Tutkimusmatka.ROUTE:
		rowing.append(Vector2(p.x, p.y))
	return [["Äpätintie · Vankkuritie (Happy Beach)", Reitti.ROUTE, Color(0.85, 0.2, 0.2, 0.9)],
		["Tutkimusmatkan soutureitti", rowing, Color(0.1, 0.3, 0.8, 0.8)]]
