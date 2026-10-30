extends Node3D
## Pelaajan omat viinakätköt lähimaastossa. Kätkön tekeminen avautuu, kun tutkimusmatkan kätköltä on haettu viinaa
## (tarina.gd stash_unlocked): sen jälkeen E sopivassa metsän, kallion tai hakkuuaukean kohdassa mökin lähellä
## kaivaa uuden kätkön (sama lahonnut laatikko havujen alla kuin ranta.gd:n kätkö, ehtymätön: E olut, Q viina).
## Kätköt tallentuvat levylle (SAVE_PATH) ja näkyvät kompassin kätköosoittimessa.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Ranta := preload("res://scripts/ranta.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Reitti := preload("res://scripts/reitti.gd")

const SAVE_PATH := "user://omat_katkot.cfg"
const MAX_COUNT := 6
const RADIUS := 250.0  # lähimaasto: näin kaukana aloituspaikasta saa kätkeä
const MIN_GAP := 15.0  # kätköjen väli
const OK_SURFACES := [Terrain.FOREST, Terrain.ROCK, Terrain.CLEARING]

var game: Node3D
var spots: Array[Vector3] = []  # kätköjen paikat (pinnan yläpuolella kuten muillakin kätköillä)


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for v: Variant in cfg.get_value("katkot", "paikat", []):
		if v is Vector2:
			_build(v)


## Voiko tähän tehdä uuden kätkön: maalla metsässä, kalliolla tai aukealla, kaukana teistä, mökeistä ja muista kätköistä.
func can_build(p: Vector3) -> bool:
	if spots.size() >= MAX_COUNT or game.player.boat != null or game.player.swimming or game.player.hidden_inside:
		return false
	if not Terrain.surface(p.x, p.z) in OK_SURFACES or Terrain.is_water(p.x, p.z):
		return false
	var s: Vector3 = game.world.start_position()
	if Vector2(p.x - s.x, p.z - s.z).length() > RADIUS or Mokki.room_at(p) != "":
		return false
	if absf(p.y - Terrain.h(p.x, p.z)) > 0.5 or Reitti.on_route(p.x, p.z):
		return false
	var q := Vector2(p.x, p.z)
	for o: Vector3 in spots + [game.world.mokki.stash_pos, game.world.ranta.stash_pos, game.retki.stash_pos]:
		if Vector2(o.x, o.z).distance_to(q) < MIN_GAP:
			return false
	return true


func near(p: Vector3) -> bool:
	for s in spots:
		if Vector2(p.x - s.x, p.z - s.z).length() < 1.6 and absf(p.y - s.y) < 1.5:
			return true
	return false


func build_at(p: Vector3) -> void:
	_build(Vector2(p.x, p.z))
	var cfg := ConfigFile.new()
	cfg.set_value("katkot", "paikat", spots.map(func(s: Vector3) -> Vector2: return Vector2(s.x, s.z)))
	cfg.save(SAVE_PATH)


func _build(at: Vector2) -> void:
	var down := Vector2(Terrain.h(at.x - 1.0, at.y) - Terrain.h(at.x + 1.0, at.y),
		Terrain.h(at.x, at.y - 1.0) - Terrain.h(at.x, at.y + 1.0))
	if down.length() < 0.01:
		down = Vector2.RIGHT
	var batch := B.Batch.new()
	spots.append(Ranta.build_stash(batch, at, down, 100 + spots.size()))
	var mi := MeshInstance3D.new()
	mi.mesh = batch.commit()
	mi.material_override = B.vcol_mat()
	add_child(mi)
