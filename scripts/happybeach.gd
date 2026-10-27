extends Node3D
## Camping Happy Beach (oikea paikka: Vankkuritie 1, Säräisniemi; pelissä tiivistetty Siperianrannan hiekkarannan
## törmälle n. 700 m mökiltä luoteeseen, ks. reitti.gd). Leirintäalue on ympärivuotinen: ravintola ja baari,
## kioski ja vastaanotto, mökkejä ja asuntovaunujen kausipaikkoja, ja hiekkaranta kävelymatkan päässä.
##
## Pelissä: tasainen alue törmän päällä (terraform), parkkipaikka tien päässä, ravintola- ja baarirakennus terasseineen
## järven puolella, kioski, kolme punamullattua mökkiä, kolme asuntovaunua, lippu, auringonlaskupenkit törmän
## reunalla, pitkospolku rantaan, hiekkarannalla aurinkotuolit ja laituri järveen. Baari on auki joka päivä klo 20–02; E ostaa oluen (main.gd).
##
## Kehys: alueen solmu on kierretty niin, että paikallinen +X on a (hiekkarannan suuntaan kaakkoon) ja -Z on b
## (järvelle), y on alueen tasosta (pad_y) ylöspäin. Ks. Reitti.cw ja Reitti.wc.

const B := preload("res://scripts/build.gd")
const Looks := preload("res://scripts/looks.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Reitti := preload("res://scripts/reitti.gd")

## Tasattava alue (a, b): [a0, a1, b0, b1], ja parkkipaikka sen sisällä.
const PAD := [-30.0, 22.0, -20.0, 24.0]
const LOT := [-8.0, 22.0, -14.0, 4.0]
const BLEND := 5.0
## Pitkospolku törmältä rantaan (a, alku-b, loppu-b).
const PATH_A := 6.5
const PATH_B := [24.0, 47.5]
## Portaat baarin tasanteelta rannalle (b-väli); pitkospolku jatkuu portaiden alapäästä rantaan.
const STAIR_B := [25.0, 38.0]
## Aukioloaika joka päivä: auki klo 20 ja kiinni klo 02 (yli keskiyön).
const OPEN_HOUR := 20
const CLOSE_HOUR := 2
const HOURS_TEXT := "joka päivä 20–02"
const ATM := Vector2(-6.8, 8.2)  # pankkiautomaatin edusta (a, b) tien puoleisen seinän vieressä oven oikealla puolella
const DECK_H := 0.1

const WALL := Color(0.95, 0.92, 0.82)
const TRIM := Color(0.1, 0.6, 0.65)
const ROOF := Color(0.13, 0.27, 0.3)
const RED := Color(0.55, 0.16, 0.11)
const WOOD := Color(0.62, 0.5, 0.36)
const GLASS := Color(0.45, 0.62, 0.72)
const GREY := Color(0.56, 0.58, 0.6)  # ravintolan harmaa puuverhous (oikea rakennus)
const METAL := Color(0.8, 0.82, 0.84)  # vaalea peltikatto

## Alueen tason korkeus (terraform).
static var pad_y := 8.6

var lamps: Array[StandardMaterial3D] = []
var _lamp_light: OmniLight3D
var _root: Node3D
var _batch: B.Batch


# --- Maasto ---------------------------------------------------------------------------------------------------

static func _in(q: Vector2, r: Array, m := 0.0) -> bool:
	return q.x >= r[0] - m and q.x <= r[1] + m and q.y >= r[2] - m and q.y <= r[3] + m


## Alue tasaiseksi (keskikorkeuteen) ja nurmeksi ennen kuin world.gd rakentaa maaston; parkkipaikka soraa, polku
## polkua, reunoilla BLEND m siirtymä. Kaukoverkko lasketaan tarkan alle, ettei se pilkistä läpi.
static func terraform() -> void:
	var g := Terrain.near
	if g == null:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for ab: Vector2 in [Vector2(PAD[0], PAD[2]), Vector2(PAD[1], PAD[2]), Vector2(PAD[0], PAD[3]), Vector2(PAD[1], PAD[3])]:
		var w := Reitti.cw(ab.x, ab.y)
		lo = lo.min(w)
		hi = hi.max(w)
	lo -= Vector2.ONE * (BLEND + 3.0)
	hi += Vector2.ONE * (BLEND + 3.0)
	var cls := g.classes.duplicate()
	var nodes := []
	var sum := 0.0
	var n := 0
	for j in range(int((lo.y + g.half) / g.step), int((hi.y + g.half) / g.step) + 1):
		for i in range(int((lo.x + g.half) / g.step), int((hi.x + g.half) / g.step) + 1):
			var p := Vector2(-g.half + i * g.step, -g.half + j * g.step)
			var q := Reitti.wc(p)
			var out := maxf(maxf(PAD[0] - q.x, q.x - PAD[1]), maxf(PAD[2] - q.y, q.y - PAD[3]))
			if out < BLEND:
				nodes.append([j * g.n + i, out])
			if out < 0.0:
				sum += g.heights[j * g.n + i]
				n += 1
			if i < g.n - 1 and j < g.n - 1:
				var c := j * (g.n - 1) + i
				if out < 0.8 and cls[c] != Terrain.WATER:
					cls[c] = Terrain.FILL if _in(q, LOT) else Terrain.YARD
				elif absf(q.x - PATH_A) < 1.2 and q.y > PATH_B[0] - 1.0 and q.y < PATH_B[1] and cls[c] == Terrain.FOREST:
					cls[c] = Terrain.PATH
	g.classes = cls
	if n == 0:
		return
	pad_y = sum / n
	var hs := g.heights
	for e in nodes:
		hs[e[0]] = lerpf(pad_y, hs[e[0]], smoothstep(0.0, BLEND, e[1]))
	g.heights = hs
	var f := Terrain.far
	if f == null:
		return
	var fs := f.heights
	for fj in range(int((lo.y - 16.0 + f.half) / f.step), int((hi.y + 16.0 + f.half) / f.step) + 1):
		for fi in range(int((lo.x - 16.0 + f.half) / f.step), int((hi.x + 16.0 + f.half) / f.step) + 1):
			var x := -f.half + fi * f.step
			var z := -f.half + fj * f.step
			var m := INF
			for dz in range(-16, 17, 4):
				for dx in range(-16, 17, 4):
					m = minf(m, g.h(x + dx, z + dz))
			fs[fj * f.n + fi] = minf(fs[fj * f.n + fi], m)
	f.heights = fs


## Puut pois alueelta, sen reunoilta ja rantapolulta (trees.gd).
static func clears_tree(x: float, z: float) -> bool:
	if absf(x - Reitti.K.x) > 70.0 or absf(z - Reitti.K.y) > 70.0:
		return false
	var q := Reitti.wc(Vector2(x, z))
	if _in(q, PAD, 2.5):
		return true
	return absf(q.x - PATH_A) < 1.8 and q.y > PATH_B[0] and q.y < PATH_B[1]


# --- Aukioloajat ja baari -------------------------------------------------------------------------------------

## Onko baari ja kioski auki hetkellä lt (sun.local()): joka päivä klo 20–02.
static func is_open(lt: Dictionary) -> bool:
	var h: int = lt.hour
	return h >= OPEN_HOUR or h < CLOSE_HOUR


static func open_text(_lt: Dictionary) -> String:
	return "auki joka päivä %d–%02d" % [OPEN_HOUR, CLOSE_HOUR]


## Laiturin (kehyksessä a = 14, b = 46…60) muskelivenepaikka (muskelivene.gd): vene laiturin kaakkoispuolella keula
## järvelle, pelaaja nousee laiturille. Vesi on tässä yli 0,5 m syvää.
## Sataman rakenteet kehyksessä (a, b): [a1, b1, a2, b2, varoalueen puolikas leveys]. Satelliittikuvan mukaan satama on suorakaiteen
## muotoinen allas, jota rajaavat louhikkoaallonmurtajat (etelässä rantapenger ja itäpäässä kärki, pohjoisessa pitkä
## murtaja) ja sisällä kolme kelluvaa laituria; sisääntulo on idässä, ja länsipäässä ovat pysäköintialue ja nostoramppi.
const MARINA_LINES := [[-2.0, 50.4, 76.0, 50.4, 4.5], [75.0, 50.4, 75.0, 62.0, 4.5], [-2.0, 50.4, -2.0, 90.0, 4.0],
	[-2.0, 90.0, 52.0, 90.0, 4.5], [24.0, 80.0, 66.0, 80.0, 8.5]]
const JETTY_W := 2.4  # laiturin leveys (m), kuten Äpätin pääsillassa
const MARINA_TOP := 0.9  # penkereen harja vedenpinnan (y = 0) yläpuolella

static func jetty_mooring() -> Dictionary:
	var bw := Reitti.cw(17.2, 57.2)
	var dw := Reitti.cw(14.7, 56.0)
	return {"name": "Happy Beachin satama", "pos": Vector3(bw.x, 0.0, bw.y), "yaw": atan2(-Reitti.N.x, -Reitti.N.y),
		"deck": Vector3(dw.x, 1.4, dw.y), "avoid": _marina_avoid()}


## Sataman rakenteet (aallonmurtajat, päälaituri ja kelluvat laiturit) automaattiajon varoalueina: pieniä Rect2-ruutuja
## viivojen (a1, b1, a2, b2) varrella; ruudun puolikas leveys on r (m).
static func _marina_avoid() -> Array:
	var out: Array = []
	for l: Array in MARINA_LINES:
		var p0 := Vector2(l[0], l[1])
		var p1 := Vector2(l[2], l[3])
		var n := maxi(1, ceili(p0.distance_to(p1) / 5.0))
		for k in n + 1:
			var q := Reitti.cw(lerpf(p0.x, p1.x, float(k) / n), lerpf(p0.y, p1.y, float(k) / n))
			out.append(Rect2(q - Vector2(l[4], l[4]), Vector2(l[4], l[4]) * 2.0))
	return out


## Pelaaja alueella (parkkipaikka, rakennukset ja terassi).
static func in_camp(p: Vector3) -> bool:
	return _in(Reitti.wc(Vector2(p.x, p.z)), PAD, 6.0)


# --- Rakentaminen ---------------------------------------------------------------------------------------------

func _ready() -> void:
	_root = Node3D.new()
	_root.position = Vector3(Reitti.K.x, pad_y, Reitti.K.y)
	_root.rotation.y = Reitti.yaw()
	add_child(_root)
	_batch = B.Batch.new()
	_main_building()
	_build_pocket()
	_kiosk()
	for k in 3:
		_cabin(-24.0, -2.0 + k * 9.0)
	_caravan(14.0, 12.0, 0.15)
	_caravan(19.0, 17.0, -0.2)
	_caravan(14.0, 20.5, 0.05)
	_flag(3.5, 7.0)
	_entrance()
	_benches()
	_beach_path()
	_beach_and_jetty()
	var mi := MeshInstance3D.new()
	mi.mesh = _batch.commit()
	mi.material_override = B.vcol_mat()
	_root.add_child(mi)
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = P(-4.0, 3.2, 19.0)
	_lamp_light.light_color = Color(1.0, 0.72, 0.42)
	_lamp_light.omni_range = 16.0
	_lamp_light.shadow_enabled = false
	_lamp_light.visible = false
	_root.add_child(_lamp_light)
	set_lamp(0.0)


## Paikallinen paikka kehyksessä: a, y (alueen tasosta), b.
static func P(a: float, y: float, b: float) -> Vector3:
	return Vector3(a, y, -b)


## Paikallinen korkeus alueen tasosta maailman maaston pintaan kohdassa (a, b).
static func ground(a: float, b: float) -> float:
	var w := Reitti.cw(a, b)
	return Terrain.h(w.x, w.y) - pad_y


## Laatikko paikallisessa kehyksessä; keskipiste (a, y, b), koko (a:n, y:n, b:n suunnassa).
func _box(c: Vector3, size: Vector3, color: Color, collide := true) -> void:
	B.box(_root, Vector3(size.x, size.y, size.z), P(c.x, c.y, c.z), color, collide)


## Harjakatto: pituus ridge harjan suuntaan, leveys span, korkeus rise; harja a-suunnassa (along_a) tai b:n.
func _roof(c: Vector3, span: float, ridge: float, rise: float, color: Color, along_a: bool) -> MeshInstance3D:
	var pm := PrismMesh.new()
	pm.size = Vector3(span, rise, ridge)
	var mi := B.mesh(_root, pm, P(c.x, c.y, c.z), color)
	if along_a:
		mi.rotation.y = PI * 0.5
	return mi


## Ikkuna rakennuksen b-puoleiseen seinään (lasi ja valkoiset pielet), keskikohta (a, y), seinän b.
func _window(a: float, y: float, b: float, w: float, h: float, side: float) -> void:
	_box(Vector3(a, y, b + side * 0.02), Vector3(w, h, 0.06), GLASS, false)
	_box(Vector3(a, y, b + side * 0.04), Vector3(w + 0.16, 0.08, 0.04), Color.WHITE, false)
	_box(Vector3(a, y + h * 0.5 + 0.04, b + side * 0.04), Vector3(w + 0.16, 0.08, 0.04), Color.WHITE, false)
	_box(Vector3(a, y - h * 0.5 - 0.04, b + side * 0.04), Vector3(w + 0.16, 0.08, 0.04), Color.WHITE, false)
	_box(Vector3(a, y, b + side * 0.04), Vector3(0.06, h, 0.04), Color.WHITE, false)


func _lamp_bulb(pos: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.9, 0.6)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.75, 0.35)
	m.emission_energy_multiplier = 0.0
	lamps.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = B.sphere(0.09, 8)
	mi.material_override = m
	mi.position = pos
	_root.add_child(mi)


## Illalla valot päälle (main.gd, kuten mokki.set_lamp): k 0..1.
func set_lamp(k: float) -> void:
	for m in lamps:
		m.emission_energy_multiplier = 3.0 * k
	_lamp_light.visible = k > 0.02
	_lamp_light.light_energy = 1.3 * k


## Ravintolan sisätila on erillinen "tasku" taivaalla leirintäalueen yläpuolella (Normipäivän Siitarin tapaan): ulko-ovelta
## E astuu sisään, ja sisällä on baaritiski ja baarimikko, lava ja karaoke, tanssilattia diskopalloineen, Sinikka, pöytäseurue,
## korttipelaajat, jukeboksi, pajatso, hedelmäpeli ja pokeri (baari.gd). Taskun paikallinen kehys on (a, b) kuten leirintäalueella:
## taskun solmu on kiertämätön, a = +x ja b = -z, ja pelaaja kävelee lattialla (törmäyslattia) POCKET_UP metriä alueen yläpuolella.
const IN_A := Vector2(-11.0, 3.0)
const IN_B := Vector2(9.0, 16.0)
const FLOOR_H := 0.1
const POCKET_UP := 300.0
## Ulko-ovet (a, b) leirintäalueen kehyksessä: terassin ovi järven puolella ja parkkipaikan ovi tien puolella; sisällä
## vastaavat poistumispisteet (a, b taskussa) ja paikka, johon ulos tullaan.
const DOORS := {
	"terassi": {"out": [-4.0, 16.9], "in": [-4.0, 15.0], "exit": [-4.0, 17.2]},
	"tie": {"out": [-8.0, 8.1], "in": [-8.0, 10.2], "exit": [-8.0, 7.6]},
}
## Toimintopisteet sisällä: id -> [a, b, säde, vihje]. Lähin voittaa (spot_at).
const SPOTS := {
	"tiski": [-3.75, 11.8, 1.7, "E: tilaa baaritiskiltä"],
	"karaoke": [1.5, 12.2, 0.9, "E: laula karaokea lavalla"],
	"jukeboksi": [-9.9, 15.1, 0.8, "E: jukeboksi, valitse biisi"],
	"pokeri": [-9.9, 13.4, 0.8, "E: pelaa pokeria"],
	"hedelma": [-9.9, 11.7, 0.8, "E: pelaa hedelmäpeliä"],
	"pajatso": [-9.9, 10.0, 0.8, "E: pelaa pajatsoa"],
	"tanssi": [0.8, 14.5, 1.3, "E: tanssimaan"],
	"sinikka": [-1.0, 11.9, 1.0, "E: Sinikka baaritiskillä"],
	"seurue": [-7.5, 13.2, 1.4, "E: juttele pöytäseurueen kanssa"],
	"ovi_terassi": [-4.0, 15.0, 1.0, "E: ulos terassille"],
	"ovi_tie": [-8.0, 10.2, 1.0, "E: ulos parkkipaikalle"],
}
const MENU_ITEMS := [
	["Tuoppi olutta", 0.22, 0.0], ["Lonkero", 0.2, 0.0], ["Siideri", 0.16, 0.0], ["Viinapaukku", 0.12, 0.0],
	["Kahvi ja pulla", 0.0, 0.25], ["Hampurilainen ja ranskalaiset", 0.0, 0.1],
]
const SEURUE_LINES := ["Istu vaan! Mistäs päin sitä ollaan?", "Äpätistä? Siellä on kyllä kaunista.", "Täällä on hyvä äänentoisto – laula sinäkin!",
	"Meillä on serkun synttärit, tultiin koko porukalla.", "Kahvia ja pullaa, se on parasta.", "Happy Beachilla on aina hyvä tunnelma."]
const SINIKKA_LINES := ["Moi! Tulitko sinäkin Äpätistä?", "Tanssittaisiinko, kun biisi soi?", "Baarimikko tekee parasta lonkeroa.",
	"Sinikka täällä, hauska tavata.", "Karaokessa sinun pitäisi laulaa jotain."]
const BARTENDER_LINES := ["Mitäs laitetaan?", "Karaoke alkaa, kun joku uskaltaa.", "Sinikka käy täällä joka viikko."]

var pocket: Node3D  # sisätilan juuri taivaalla
var roof_nodes: Array[Node3D] = []
var _screen: Label3D
var _disco_ball: MeshInstance3D
var _disco_lights: Array[OmniLight3D] = []
var _in_light: OmniLight3D
var _jukebox: AudioStreamPlayer3D
var disco_on := 0.0  # sekuntia, kunnes disko sammuu (jukeboksi tai karaoke)
var sinikka: Node3D
var _seurue: Array[Node3D] = []
var _bartender: Node3D
var _bubbles := {}  # hahmo -> [Label3D, aika]
var _chat_t := 6.0
var _t := 0.0


## Pelaaja taskussa (sisällä ravintolassa).
func in_pocket(p: Vector3) -> bool:
	return pocket != null and p.y > pocket.global_position.y - 2.0 and Vector2(p.x - pocket.global_position.x,
		p.z - pocket.global_position.z).length() < 60.0


## Staattinen apu kameralle (on_foot.gd): sisällä ollaan, kun pelaaja on taskun kohdalla.
static var pocket_y := INF

static func in_building(p: Vector3) -> bool:
	return pocket_y < INF and p.y > pocket_y - 2.0 and p.y < pocket_y + 6.0


## Paikka taskussa (a, b) maailmaan (lattian pinnalle).
func world_at(a: float, b: float) -> Vector3:
	return pocket.global_position + Vector3(a, FLOOR_H, -b)


func local_ab(p: Vector3) -> Vector2:
	var d := p - pocket.global_position
	return Vector2(d.x, -d.z)


## Lähin toimintopiste sisällä pelaajan kohdalla: {id, text}, tai tyhjä.
func spot_at(p: Vector3) -> Dictionary:
	if not in_pocket(p):
		return {}
	var q := local_ab(p)
	var best := {}
	var bd := INF
	for id: String in SPOTS:
		var e: Array = SPOTS[id]
		var d := q.distance_to(Vector2(e[0], e[1]))
		if d < e[2] and d < bd:
			bd = d
			best = {"id": id, "text": e[3]}
	return best


## Ulko-ovi pelaajan kohdalla (leirintäalueella): ovi-id tai "".
func door_at(p: Vector3) -> String:
	var best := ""
	var bd := 1.8
	for id: String in DOORS:
		var o: Array = DOORS[id].out
		var w := Reitti.cw(o[0], o[1])
		var d := Vector2(p.x - w.x, p.z - w.y).length()
		if d < bd and absf(p.y - (pad_y + DECK_H)) < 2.0 and not in_pocket(p):
			bd = d
			best = id
	return best


## Ulko-oven paikka maailmassa (x, z).
func cw_door(door: String) -> Vector2:
	var o: Array = DOORS[door].out
	return Reitti.cw(o[0], o[1])


## Ulkoa sisään (ovi-id) ja sisältä ulos (se ovi, jonka luona ollaan).
func enter(door: String) -> void:
	var e: Array = DOORS[door]["in"]
	# Sisääntulo oven toimintopisteen (säde 1 m) ulkopuolelle, ettei toinen E heitä heti takaisin ulos.
	_teleport(world_at(e[0], e[1] + (-1.4 if door == "terassi" else 1.4)), Vector3(0, 0, 0))
	_door_lock = Engine.get_physics_frames() + 40
	_greet()


func leave(door: String) -> void:
	if Engine.get_physics_frames() < _door_lock:
		return
	var e: Array = DOORS[door].exit
	var w := Reitti.cw(e[0], e[1])
	_teleport(Vector3(w.x, pad_y + DECK_H + 0.05, w.y), Vector3.ZERO)


func _teleport(pos: Vector3, _unused: Vector3) -> void:
	var pl: CharacterBody3D = game.player
	pl.global_position = pos
	pl.velocity = Vector3.ZERO


var game: Node3D
var _door_lock := 0


func _greet() -> void:
	say(_bartender, "Iltaa! Tervetuloa Happy Beachille.")


## Puhekupla hahmon yläpuolelle.
func say(who: Node3D, text: String, t := 3.4) -> void:
	if who == null:
		return
	if _bubbles.has(who):
		_bubbles[who][0].queue_free()
	var l := Label3D.new()
	l.text = text
	l.font_size = 30
	l.pixel_size = 0.0045
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = Color(1, 1, 0.85)
	l.outline_size = 8
	l.position = Vector3(0, 2.15, 0)
	who.add_child(l)
	_bubbles[who] = [l, t]


func set_screen(text: String) -> void:
	_screen.text = text


## Jukeboksin musiikki alkaa (stream) tai loppuu (null); disko pyörii musiikin ajan.
func play_music(stream: AudioStream) -> void:
	_jukebox.stop()
	if stream == null:
		disco_on = 0.0
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_jukebox.stream = stream
	_jukebox.play()
	disco_on = 1.0e6


func music_playing() -> bool:
	return _jukebox.playing


func _process(delta: float) -> void:
	_t += delta
	if disco_on > 0.0:
		disco_on -= delta
	var on := disco_on > 0.0
	if _disco_ball != null:
		_disco_ball.rotation.y += delta * 1.2
	for k in _disco_lights.size():
		var l := _disco_lights[k]
		l.visible = on
		if on:
			l.light_color = Color.from_hsv(fmod(_t * 0.25 + k * 0.33, 1.0), 0.8, 1.0)
			l.position = Vector3(0.8 + sin(_t * 1.5 + k * 2.1) * 2.0, 2.5, -(13.5 + cos(_t * 1.1 + k * 2.1) * 1.5))
	if not on and _jukebox != null and _jukebox.playing:
		_jukebox.stop()
	for who: Node3D in _bubbles.keys():
		_bubbles[who][1] -= delta
		if _bubbles[who][1] <= 0.0:
			_bubbles[who][0].queue_free()
			_bubbles.erase(who)
	# Seurue ja baarimikko jutustelevat itsekseen (kuplat), kun pelaaja on sisällä.
	if game != null and in_pocket(game.player.global_position):
		_chat_t -= delta
		if _chat_t <= 0.0:
			_chat_t = randf_range(5.0, 9.0)
			match randi() % 2:
				0:
					say(_seurue.pick_random(), SEURUE_LINES.pick_random())
				_:
					say(_bartender, BARTENDER_LINES.pick_random())


## Sinikka tanssilattialle tai takaisin baaritiskille.
func place_sinikka(dancing: bool) -> void:
	var q := Vector2(1.9, 14.3) if dancing else Vector2(-1.0, 11.1)
	sinikka.position = Vector3(q.x, FLOOR_H, -q.y)


## Ravintola ja baari ulkoa: vaalea rakennus turkoosein pielin, harjakatto, terassi järven puolella ja ovet terassille ja
## parkkipaikalle (E avaa oven, sisätila on taskussa, ks. _build_pocket).
func _main_building() -> void:
	# Oikean rakennuksen mukaan: harmaa pystypaneeli, matala vaalea peltikatto, valkoinen suippo torni, lippusalot ja
	# antenni, ramppi kaiteineen sekä pyöreä kyltti.
	_box(Vector3(-4.0, 1.5, 12.5), Vector3(14.0, 3.0, 7.0), GREY)
	for a: float in range(-10, 3, 1):  # pystylaudoituksen saumat
		_box(Vector3(float(a) - 0.5, 1.5, 16.02), Vector3(0.03, 3.0, 0.02), GREY.darkened(0.25), false)
		_box(Vector3(float(a) - 0.5, 1.5, 8.98), Vector3(0.03, 3.0, 0.02), GREY.darkened(0.25), false)
	_box(Vector3(-4.0, 3.02, 12.5), Vector3(14.3, 0.08, 7.3), Color.WHITE, false)
	_roof(Vector3(-4.0, 3.75, 12.5), 8.0, 14.8, 1.5, METAL, true)
	# Matala sivusiipi länsipäässä oman pulpettikattonsa alla ja korkea etuosa (päätykolmio sisäänkäynnin yllä).
	_box(Vector3(-12.2, 1.25, 12.5), Vector3(3.4, 2.5, 6.0), GREY.lightened(0.05))
	_roof(Vector3(-12.2, 2.95, 12.5), 6.2, 3.8, 0.9, METAL, true)
	_box(Vector3(-4.0, 3.6, 16.04), Vector3(4.2, 0.9, 0.06), GREY, false)  # päätykolmion etulevy
	var gable := PrismMesh.new()
	gable.size = Vector3(4.4, 1.3, 0.3)
	B.mesh(_root, gable, P(-4.0, 3.75, 16.15), GREY)
	# Valkoinen suippo torni itäpäässä: harmaa runko, ikkunarivi ja pyramidikatto.
	_box(Vector3(2.4, 3.2, 15.2), Vector3(2.0, 6.4, 2.0), GREY.lightened(0.04))
	_box(Vector3(2.4, 4.6, 14.17), Vector3(0.9, 0.5, 0.05), GLASS, false)
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 1.7
	spire.height = 2.2
	spire.radial_segments = 4
	spire.rings = 0
	var sp := B.mesh(_root, spire, P(2.4, 7.5, 15.2), Color(0.96, 0.96, 0.98))
	sp.rotation.y = PI * 0.25
	# Antenni katonharjalla.
	_box(Vector3(-7.0, 5.1, 12.5), Vector3(0.04, 3.0, 0.04), Color(0.7, 0.7, 0.72), false)
	for k in 4:
		_box(Vector3(-7.0, 5.9 + k * 0.35, 12.5), Vector3(0.02, 0.02, 1.2 - k * 0.2), Color(0.7, 0.7, 0.72), false)
	# Kuusi valkoista lippusalkoa itäpäädyn viereen.
	for k in 6:
		_box(Vector3(7.5 + k * 0.7, 3.5 + 0.25 * float(k % 3), 12.0 + k * 0.15), Vector3(0.07, 7.0 + 0.5 * float(k % 3), 0.07),
			Color(0.95, 0.95, 0.95), false)
	# Pyöreä kyltti pylvään päässä pihan puolella (tien suunnasta tultaessa).
	_box(Vector3(5.0, 1.7, 8.0), Vector3(0.08, 3.4, 0.08), Color(0.7, 0.7, 0.72), false)
	var disc := B.mesh(_root, B.cyl(0.55, 0.55, 0.05, 20), P(5.0, 3.3, 8.0), Color(0.85, 0.87, 0.9))
	disc.rotation.x = PI * 0.5
	# Ramppi kaiteineen tien puoleisen seinän edessä: loiva penger ja siksak-kaide.
	for k in 8:
		var rx := -11.0 + k * 1.3
		_box(Vector3(rx, 0.22 + 0.01 * float(k), 8.1), Vector3(1.3, 0.04, 1.2), Color(0.5, 0.5, 0.52), false)
		_box(Vector3(rx, 0.55, 7.55 + 0.06 * float(k % 2)), Vector3(0.04, 1.0, 0.04), Color(0.3, 0.3, 0.32), false)
		_box(Vector3(rx + 0.65, 0.95, 7.55 + 0.35 * float(k % 2)), Vector3(1.3, 0.03, 0.03), Color(0.3, 0.3, 0.32), false)
	# Pensaita ja ruusupensas ratamon vieressä.
	for pos: Vector3 in [Vector3(8.5, 0.0, 8.4), Vector3(9.6, 0.0, 9.5), Vector3(10.8, 0.0, 8.6)]:
		B.mesh(_root, B.sphere(0.8, 8), P(pos.x, 0.55, pos.z), Color(0.22, 0.36, 0.18))
		B.mesh(_root, B.sphere(0.12, 6), P(pos.x + 0.3, 0.95, pos.z - 0.3), Color(0.85, 0.3, 0.5))
	# Ikkunat ja ovet järven puolen seinässä (b = 16, ulospäin +b) ja tien puolen seinässä (b = 9, ulospäin -b).
	for a: float in [-9.0, 1.0]:
		_window(a, 1.7, 16.0, 1.4, 1.2, 1.0)
	_box(Vector3(-4.0, 1.1, 16.04), Vector3(1.0, 2.2, 0.06), TRIM, false)
	_box(Vector3(-4.0, 2.4, 16.3), Vector3(1.6, 0.06, 0.6), TRIM, false)  # oven katos
	for a: float in [-10.0, -5.5, -2.0, 1.5]:
		_window(a, 1.7, 9.0, 1.2, 1.1, -1.0)
	_box(Vector3(-8.0, 1.1, 8.96), Vector3(1.0, 2.2, 0.06), TRIM, false)
	_box(Vector3(-8.0, 2.4, 8.7), Vector3(1.6, 0.06, 0.6), TRIM, false)
	_terrace()
	_atm()
	# Kyltit: nimi päätykolmion levyssä ja aukioloajat oven vieressä.
	var big := B.sign_plate(_root, "CAMPING HAPPY BEACH", TRIM, Color.WHITE, 0.3, 54, Color(0.95, 0.9, 0.5))
	big.position = P(-4.0, 3.5, 16.45)
	var hours := B.sign_plate(_root, "KIOSKI JA BAARI\n" + HOURS_TEXT, Color(0.97, 0.95, 0.88), Color(0.1, 0.1, 0.12), 0.18, 34,
		TRIM)
	hours.position = P(-6.75, 1.9, 16.12)


## Pankkiautomaatti tien puoleisessa seinässä oven vieressä: tummanharmaa kotelo, hehkuva näyttö, näppäimistö,
## korttirako ja setelirako sekä vihreä kyltti (ulospäin -b). Nosto: baari.gd atm_withdraw, kerran päivässä.
func _atm() -> void:
	var a := ATM.x
	var body := Color(0.2, 0.22, 0.25)
	_box(Vector3(a, 0.95, 8.74), Vector3(0.9, 1.9, 0.5), body)
	_box(Vector3(a, 1.0, 8.485), Vector3(0.8, 1.6, 0.02), body.lightened(0.12), false)  # etulevy
	var scr := StandardMaterial3D.new()
	scr.albedo_color = Color(0.3, 0.8, 0.9)
	scr.emission_enabled = true
	scr.emission = Color(0.25, 0.75, 0.9)
	scr.emission_energy_multiplier = 1.6
	var mi := MeshInstance3D.new()
	mi.mesh = B.boxm(Vector3(0.52, 0.34, 0.02))
	mi.material_override = scr
	mi.position = P(a, 1.52, 8.47)
	_root.add_child(mi)
	_box(Vector3(a, 1.52, 8.48), Vector3(0.58, 0.4, 0.02), Color(0.08, 0.08, 0.1), false)  # näytön kehys
	for r in 4:  # näppäimistö 3 x 4
		for c in 3:
			_box(Vector3(a - 0.1 + c * 0.1, 1.2 - r * 0.075, 8.465), Vector3(0.08, 0.05, 0.02), Color(0.75, 0.77, 0.8), false)
	_box(Vector3(a + 0.28, 1.15, 8.47), Vector3(0.08, 0.3, 0.02), Color(0.1, 0.1, 0.12), false)  # sivupainikkeet
	_box(Vector3(a, 0.78, 8.47), Vector3(0.5, 0.03, 0.02), Color(0.02, 0.02, 0.03), false)  # korttirako
	_box(Vector3(a, 0.6, 8.47), Vector3(0.5, 0.09, 0.02), Color(0.45, 0.85, 0.5), false)  # setelirako
	_box(Vector3(a, 0.6, 8.46), Vector3(0.44, 0.04, 0.02), Color(0.02, 0.02, 0.03), false)
	var plate := B.sign_plate(_root, "PANKKIAUTOMAATTI", Color(0.1, 0.5, 0.3), Color.WHITE, 0.2, 30, Color.WHITE)
	plate.position = P(a, 2.1, 8.49)
	_lamp_bulb(P(a - 0.55, 2.35, 8.55))


## Pankkiautomaatin edessä (ulkona leirintäalueella)?
func atm_near(p: Vector3) -> bool:
	if in_pocket(p) or absf(p.y - (pad_y + DECK_H)) > 2.0:
		return false
	var w := Reitti.cw(ATM.x, ATM.y)
	return Vector2(p.x - w.x, p.z - w.y).length() < 1.5


## Terassi järven puolella (a -12…4, b 16…21,2): lankkulattia, portaat järvelle, kaide, pöytäryhmät tuoleineen,
## baaripöydät jakkaroineen, päivänvarjot, lämmittimet, istutuslaatikot, annostaulu ja valoköynnös.
func _terrace() -> void:
	var a0 := -12.0
	var a1 := 4.0
	var b0 := 16.0
	var b1 := 21.2
	var top := DECK_H
	_box(Vector3((a0 + a1) * 0.5, top * 0.5, (b0 + b1) * 0.5), Vector3(a1 - a0, top, b1 - b0), WOOD)
	# Lankkujen saumat b-suunnassa ja kantavat palkit reunassa.
	var a := a0 + 0.45
	while a < a1:
		_batch.add(B.boxm(Vector3(0.025, 0.012, b1 - b0)), Transform3D(Basis(), P(a, top + 0.006, (b0 + b1) * 0.5)), WOOD.darkened(0.3))
		a += 0.45
	_box(Vector3((a0 + a1) * 0.5, top * 0.5, b1 + 0.04), Vector3(a1 - a0 + 0.2, top + 0.04, 0.1), WOOD.darkened(0.25), false)
	for sa: float in [a0, -8.0, -4.0, 0.0, a1]:
		_box(Vector3(sa, -0.35, b1), Vector3(0.14, 0.9, 0.14), WOOD.darkened(0.35), false)
	# Portaat terassin etureunasta nurmelle (a -5,2…-2,8): kaksi askelta.
	for k in 2:
		_box(Vector3(-4.0, top - 0.06 - 0.12 * k, b1 + 0.3 + 0.35 * k), Vector3(2.4, 0.06, 0.35), WOOD.lightened(0.05), false)
	# Kaide: pylväät 2 m välein, ylä- ja välijohde; aukko portaiden kohdalla ja itäpäässä.
	var rail := WOOD.darkened(0.1)
	for pa in range(-12, 5, 2):
		if absf(float(pa) + 4.0) < 1.5:
			continue
		_box(Vector3(float(pa), top + 0.5, b1 - 0.05), Vector3(0.1, 1.0, 0.1), rail, false)
	for seg: Vector2 in [Vector2(-12.0, -5.3), Vector2(-2.7, 4.0)]:
		for ry: float in [0.95, 0.5]:
			_box(Vector3((seg.x + seg.y) * 0.5, top + ry, b1 - 0.05), Vector3(seg.y - seg.x, 0.05, 0.09), rail, false)
	for pb: float in [18.0, 20.0, 21.15]:
		_box(Vector3(a0 + 0.05, top + 0.5, pb), Vector3(0.1, 1.0, 0.1), rail, false)
	_box(Vector3(a0 + 0.05, top + 0.95, 19.2), Vector3(0.09, 0.05, 4.3), rail, false)
	_box(Vector3(a0 + 0.05, top + 0.5, 19.2), Vector3(0.09, 0.05, 4.3), rail, false)
	# Pöytäryhmät: kolme piknikpöytää ja kaksi pyöreää pöytää tuoleineen.
	for pos: Vector2 in [Vector2(-9.5, 19.6), Vector2(0.6, 19.8), Vector2(2.9, 18.6)]:
		_picnic(pos.x, pos.y)
		B.mesh(_root, B.cyl(0.07, 0.07, 0.16, 8), P(pos.x, top + 0.84, pos.y), Color(0.95, 0.85, 0.5))  # tuikkulyhty
	for pos: Vector2 in [Vector2(-6.4, 19.9), Vector2(-1.9, 19.9)]:
		B.mesh(_root, B.cyl(0.55, 0.55, 0.05, 14), P(pos.x, top + 0.76, pos.y), WOOD.lightened(0.1))
		B.mesh(_root, B.cyl(0.05, 0.05, 0.74, 8), P(pos.x, top + 0.38, pos.y), Color(0.25, 0.25, 0.27))
		B.mesh(_root, B.cyl(0.3, 0.3, 0.04, 10), P(pos.x, top + 0.02, pos.y), Color(0.25, 0.25, 0.27))
		for k in 4:
			var ang := k * PI * 0.5 + 0.4
			var cp := pos + Vector2(cos(ang), sin(ang)) * 0.95
			_box(Vector3(cp.x, top + 0.45, cp.y), Vector3(0.42, 0.05, 0.42), TRIM.darkened(0.1), false)
			_box(Vector3(cp.x, top + 0.22, cp.y), Vector3(0.05, 0.44, 0.05), Color(0.25, 0.25, 0.27), false)
			_box(Vector3(cp.x - cos(ang) * 0.2, top + 0.72, cp.y - sin(ang) * 0.2), Vector3(0.4, 0.4, 0.04), TRIM.darkened(0.1), false)
	# Baaritasku ja jakkarat kaiteen vieressä.
	_box(Vector3(-11.4, top + 0.55, 19.2), Vector3(0.5, 0.06, 3.0), WOOD.lightened(0.1), false)
	_box(Vector3(-11.4, top + 0.27, 19.2), Vector3(0.4, 0.54, 2.9), WOOD.darkened(0.2), false)
	for jb: float in [18.2, 19.2, 20.2]:
		B.mesh(_root, B.cyl(0.19, 0.19, 0.05, 10), P(-10.6, top + 0.72, jb), RED)
		B.mesh(_root, B.cyl(0.03, 0.03, 0.7, 6), P(-10.6, top + 0.36, jb), Color(0.3, 0.3, 0.32))
	# Päivänvarjot (kahdeksan kiilaa, keltainen ja valkoinen vuorotellen) ja terassilämmittimet.
	for pos: Vector2 in [Vector2(-9.5, 19.6), Vector2(0.6, 19.8), Vector2(-6.4, 19.9), Vector2(-1.9, 19.9)]:
		_box(Vector3(pos.x, 1.2, pos.y), Vector3(0.07, 2.4, 0.07), Color(0.4, 0.4, 0.4), false)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.5
		cone.height = 0.55
		cone.radial_segments = 8
		cone.rings = 0
		B.mesh(_root, cone, P(pos.x, 2.5, pos.y), Color(0.95, 0.75, 0.15))
		var cap := B.mesh(_root, cone, P(pos.x, 2.52, pos.y), Color(0.97, 0.97, 0.94))
		cap.scale = Vector3(1.002, 0.995, 1.002)
		cap.rotation.y = PI / 8.0
		B.mesh(_root, B.cyl(0.02, 0.02, 0.22, 6), P(pos.x, 2.86, pos.y), Color(0.4, 0.4, 0.4))
	for hp: Vector2 in [Vector2(-8.0, 16.8), Vector2(-0.4, 16.8)]:
		_box(Vector3(hp.x, 1.1, hp.y), Vector3(0.06, 2.2, 0.06), Color(0.45, 0.46, 0.48), false)
		B.mesh(_root, B.cyl(0.28, 0.12, 0.08, 10), P(hp.x, 2.25, hp.y), Color(0.7, 0.72, 0.75))
		B.mesh(_root, B.cyl(0.14, 0.14, 0.05, 10), P(hp.x, 2.18, hp.y), Color(1.0, 0.45, 0.15))
	# Istutuslaatikot seinustalla ja kukat, sekä annostaulu oven vieressä.
	for fa: float in [-11.0, -1.0, 2.0]:
		_box(Vector3(fa, top + 0.2, 16.3), Vector3(1.4, 0.4, 0.4), WOOD.darkened(0.3), false)
		for k in 4:
			B.mesh(_root, B.sphere(0.17, 6), P(fa - 0.5 + k * 0.33, top + 0.5, 16.3), [Color(0.85, 0.3, 0.5), Color(0.95, 0.8, 0.2), Color(0.9, 0.9, 0.95), Color(0.85, 0.3, 0.5)][k])
	_box(Vector3(-5.6, top + 0.55, 16.7), Vector3(0.7, 1.1, 0.06), Color(0.12, 0.12, 0.14), false)
	_box(Vector3(-5.6, top + 0.55, 16.65), Vector3(0.58, 0.9, 0.02), Color(0.9, 0.9, 0.85), false)
	# Valoköynnös etukaiteen yli ja pylväistä seinään.
	for k in 9:
		var la := -11.0 + k * 2.0
		_lamp_bulb(P(la, 2.55 - 0.2 * float(k % 2), 21.15))
	for ka: float in [-11.0, -1.0, 3.0]:
		_box(Vector3(ka, 1.3, 21.15), Vector3(0.07, 2.6, 0.07), Color(0.4, 0.4, 0.4), false)

## Sisätila taskussa: lattia, seinät, ovet ja sisustus. Rakennetaan omaan solmuunsa taivaalle (_root ja _batch vaihdetaan
## väliaikaisesti, jotta ulkorakennuksen apufunktiot kelpaavat).
func _build_pocket() -> void:
	pocket = Node3D.new()
	pocket.position = Vector3(Reitti.K.x, pad_y + POCKET_UP, Reitti.K.y)
	add_child(pocket)
	pocket_y = pocket.position.y
	var outer_root := _root
	var outer_batch := _batch
	_root = pocket
	_batch = B.Batch.new()
	var f := FLOOR_H
	# Iso tumma alusta, ettei kaukomaasto näy seinien takaa, ja lattia.
	_box(Vector3(-4.0, -0.5, 12.5), Vector3(60.0, 1.0, 60.0), Color(0.04, 0.04, 0.05))
	_box(Vector3(-4.0, f * 0.5, 12.5), Vector3(14.0, f, 7.0), Color(0.55, 0.4, 0.26))
	# Seinät 3 m: päädyt umpinaiset, pitkillä seinillä oviaukot (1,2 m).
	_box(Vector3(-10.9, 1.5, 12.5), Vector3(0.2, 3.0, 7.0), WALL)
	_box(Vector3(2.9, 1.5, 12.5), Vector3(0.2, 3.0, 7.0), WALL)
	for side: Array in [[15.9, -4.0], [9.1, -8.0]]:
		var wb: float = side[0]
		var da: float = side[1]
		var left := (da - 0.6) - (-11.0)
		var right := 3.0 - (da + 0.6)
		if wb > 15.0:  # kameran puoleinen järviseinä on matala (Siitarin tapaan), törmäys täyskorkea
			_low_wall(Vector3(-11.0 + left * 0.5, 0, wb), Vector3(left, 3.0, 0.2))
			_low_wall(Vector3(da + 0.6 + right * 0.5, 0, wb), Vector3(right, 3.0, 0.2))
			continue
		_box(Vector3(-11.0 + left * 0.5, 1.5, wb), Vector3(left, 3.0, 0.2), WALL)
		_box(Vector3(da + 0.6 + right * 0.5, 1.5, wb), Vector3(right, 3.0, 0.2), WALL)
		_box(Vector3(da, 2.6, wb), Vector3(1.2, 0.8, 0.2), WALL, false)
	# Näkymättömät oviaukkojen tulpat (seinää ei voi ohittaa; poistutaan E:llä).
	_low_wall(Vector3(-4.0, 0, 16.15), Vector3(1.2, 3.0, 0.2))
	_box(Vector3(-8.0, 1.5, 8.85), Vector3(1.2, 3.0, 0.2), WALL, true)
	_box(Vector3(-8.0, 1.1, 9.22), Vector3(1.0, 2.2, 0.04), TRIM, false)  # tien oven sisäpuoli
	_box(Vector3(-4.0, 0.3, 15.78), Vector3(1.0, 0.6, 0.04), TRIM, false)  # järven oven sisäpuoli (matala seinä)
	for a: float in [-9.0, 1.0]:
		_box(Vector3(a, 0.62, 15.94), Vector3(1.6, 0.06, 0.12), Color(0.9, 0.88, 0.8), false)  # ikkunalaudat
	_interior()
	_in_light.visible = true
	var mi := MeshInstance3D.new()
	mi.mesh = _batch.commit()
	mi.material_override = B.vcol_mat()
	pocket.add_child(mi)
	_root = outer_root
	_batch = outer_batch


## Matala seinäpala (0,6 m) ja sen päällä näkymätön täyskorkea törmäys: kamera katsoo seinän yli.
func _low_wall(c: Vector3, size: Vector3) -> void:
	_box(Vector3(c.x, 0.3, c.z), Vector3(size.x, 0.6, size.z), WALL, false)
	var body := StaticBody3D.new()
	body.position = P(c.x, size.y * 0.5, c.z)
	body.add_child(B.box_shape(size))
	_root.add_child(body)


## Sisustus: baaritiski ja hyllyt, lava, tanssilattia, pöydät, jukeboksi ja pajatso.
func _interior() -> void:
	var f := FLOOR_H
	var dark := Color(0.2, 0.14, 0.1)
	# Baaritiski tien puoleisella seinällä: tiski, baarimikko, pullohylly seinällä ja jääkaappi, jakkarat edessä.
	_box(Vector3(-3.75, f + 0.55, 10.55), Vector3(4.6, 1.1, 0.7), dark)
	_box(Vector3(-3.75, f + 1.12, 10.55), Vector3(4.8, 0.07, 0.9), WOOD, false)
	_bartender = _npc({"shirt": Color(0.95, 0.95, 0.93), "pants": Color(0.08, 0.08, 0.1), "shoes": Color(0.08, 0.08, 0.08),
		"hair": "Hair_SimpleParted", "hair_color": Color(0.25, 0.18, 0.12), "beard": true, "height": 1.8, "belly": 0.4},
		P(-3.0, f, 9.8), 0.0, "Idle")
	_box(Vector3(-3.75, f + 1.6, 9.3), Vector3(4.6, 0.05, 0.3), WOOD, false)
	_box(Vector3(-3.75, f + 2.1, 9.3), Vector3(4.6, 0.05, 0.3), WOOD, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for row: float in [1.6, 2.1]:
		for k in 18:
			var col := Color.from_hsv(rng.randf(), 0.6, 0.7)
			var bx := -5.9 + k * 0.25
			_batch.add(B.cyl(0.035, 0.035, 0.2, 8), Transform3D(Basis(), P(bx, f + row + 0.13, 9.3)), col)
			_batch.add(B.cyl(0.013, 0.015, 0.1, 6), Transform3D(Basis(), P(bx, f + row + 0.3, 9.3)), col.darkened(0.3))
	_box(Vector3(-6.3, f + 0.9, 9.4), Vector3(0.8, 1.8, 0.6), Color(0.85, 0.85, 0.88))  # jääkaappi
	for k in 4:
		var sx := -5.2 + k * 1.1
		_box(Vector3(sx, f + 0.18, 11.65), Vector3(0.36, 0.06, 0.36), Color(0.75, 0.2, 0.15), false)
		_box(Vector3(sx, f + 0.0 + 0.1, 11.65), Vector3(0.06, 0.36, 0.06), Color(0.3, 0.3, 0.32), false)
		_box(Vector3(sx, f + 0.42, 11.65), Vector3(0.38, 0.1, 0.38), Color(0.75, 0.2, 0.15), false)
	var menu := B.sign_plate(_root, "BAARI\nolut · lonkero · siideri\nkahvi ja pulla · burgeri", Color(0.12, 0.1, 0.1),
		Color(0.95, 0.9, 0.6), 0.22, 30, TRIM)
	menu.position = P(-3.75, 2.75, 9.18)
	# Lava (karaoke) itäpäässä tien puoleisella seinällä: korotettu lattia, kaiuttimet, mikrofoni ja ruutu.
	_box(Vector3(1.5, f + 0.15, 10.7), Vector3(2.8, 0.3, 3.0), Color(0.3, 0.2, 0.35))
	for sa: float in [0.1, 2.9]:
		_box(Vector3(sa, f + 0.75, 9.7), Vector3(0.45, 0.9, 0.4), Color(0.08, 0.08, 0.09))
	_box(Vector3(1.5, f + 0.7, 11.6), Vector3(0.03, 0.8, 0.03), Color(0.3, 0.3, 0.32), false)
	_box(Vector3(1.5, f + 1.12, 11.6), Vector3(0.05, 0.12, 0.05), Color(0.15, 0.15, 0.16), false)
	_box(Vector3(1.5, 2.0, 9.14), Vector3(2.2, 1.25, 0.06), Color(0.04, 0.04, 0.06), false)
	_screen = Label3D.new()
	_screen.text = "KARAOKE\nE: laula"
	_screen.font_size = 40
	_screen.pixel_size = 0.0055
	_screen.modulate = Color(0.6, 0.95, 1.0)
	_screen.outline_size = 8
	_screen.position = P(1.5, 2.0, 9.2)
	_screen.rotation.y = PI  # ruutu katsoo huoneeseen päin (+b = -z)
	_root.add_child(_screen)
	# Tanssilattia lavan edessä: ruudukko ja diskopallo katossa.
	for i in 6:
		for j in 5:
			var c := Color(0.9, 0.9, 0.92) if (i + j) % 2 == 0 else Color(0.12, 0.12, 0.15)
			_batch.add(B.boxm(Vector3(0.6, 0.012, 0.6)), Transform3D(Basis(), P(-1.0 + 0.6 * i, f + 0.01, 12.9 + 0.6 * j)), c)
	_disco_ball = MeshInstance3D.new()
	_disco_ball.mesh = B.sphere(0.25, 12)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.85, 0.88, 0.9)
	dm.metallic = 1.0
	dm.roughness = 0.15
	_disco_ball.material_override = dm
	_disco_ball.position = P(0.8, 2.7, 14.1)
	_root.add_child(_disco_ball)
	roof_nodes.append(_disco_ball)
	for k in 3:
		var l := OmniLight3D.new()
		l.omni_range = 6.0
		l.light_energy = 1.6
		l.shadow_enabled = false
		l.visible = false
		_root.add_child(l)
		_disco_lights.append(l)
	# Pöydät ja tuolit ikkunoiden vieressä länsipäässä.
	for pos: Vector2 in [Vector2(-8.8, 14.6), Vector2(-6.2, 14.6), Vector2(-8.4, 11.9)]:
		_box(Vector3(pos.x, f + 0.72, pos.y), Vector3(0.9, 0.05, 0.9), WOOD)
		_box(Vector3(pos.x, f + 0.36, pos.y), Vector3(0.1, 0.7, 0.1), WOOD.darkened(0.3), false)
		for d: Vector2 in [Vector2(0.75, 0), Vector2(-0.75, 0), Vector2(0, 0.75), Vector2(0, -0.75)]:
			# Istuinkorkeus 0,45 m kuten Siitarissa (Sitting_Idle-animaation istuinkorkeus).
			_box(Vector3(pos.x + d.x, f + 0.45, pos.y + d.y), Vector3(0.45, 0.06, 0.45), Color(0.25, 0.4, 0.45), false)
			for lx: float in [-0.18, 0.18]:
				for lz: float in [-0.18, 0.18]:
					_box(Vector3(pos.x + d.x + lx, f + 0.22, pos.y + d.y + lz), Vector3(0.04, 0.44, 0.04), Color(0.3, 0.3, 0.32), false)
	# Jukeboksi ja pajatso länsiseinällä, etupuoli itään (+a).
	_box(Vector3(-10.5, f + 0.8, 15.1), Vector3(0.6, 1.6, 0.9), Color(0.55, 0.15, 0.12))
	_box(Vector3(-10.18, f + 1.2, 15.1), Vector3(0.04, 0.5, 0.7), Color(1.0, 0.75, 0.2), false)
	_box(Vector3(-10.18, f + 0.55, 15.1), Vector3(0.04, 0.3, 0.7), Color(0.2, 0.8, 0.9), false)
	_lamp_bulb(P(-10.1, f + 1.7, 15.1))
	# Pokeri (Coinline Casino) hedelmäpelin vieressä: punainen kaappi, musta otsikkopalkki ja painikepaneeli, sininen ruutu.
	_box(Vector3(-10.5, f + 0.85, 13.4), Vector3(0.6, 1.7, 0.7), Color(0.65, 0.1, 0.07))
	_box(Vector3(-10.18, f + 1.62, 13.4), Vector3(0.04, 0.16, 0.62), Color(0.07, 0.07, 0.08), false)  # POKERI-palkki
	_box(Vector3(-10.18, f + 1.7, 13.4), Vector3(0.045, 0.06, 0.3), Color(0.95, 0.8, 0.2), false)
	_box(Vector3(-10.18, f + 1.25, 13.4), Vector3(0.04, 0.4, 0.45), Color(0.2, 0.35, 0.8), false)  # ruutu
	_box(Vector3(-10.18, f + 0.9, 13.4), Vector3(0.04, 0.22, 0.62), Color(0.07, 0.07, 0.08), false)  # painikepaneeli
	for k in 5:
		_box(Vector3(-10.16, f + 0.95, 13.4 - 0.22 + k * 0.11), Vector3(0.05, 0.05, 0.08), Color(0.9, 0.2, 0.35), false)
	_box(Vector3(-10.5, f + 0.9, 10.0), Vector3(0.6, 1.8, 0.6), Color(0.1, 0.25, 0.55))
	_box(Vector3(-10.18, f + 1.35, 10.0), Vector3(0.04, 0.4, 0.45), Color(0.95, 0.9, 0.3), false)
	_box(Vector3(-10.18, f + 0.95, 10.0), Vector3(0.04, 0.12, 0.2), Color(0.8, 0.1, 0.1), false)
	_box(Vector3(-10.5, f + 0.85, 11.7), Vector3(0.6, 1.7, 0.7), Color(0.55, 0.1, 0.35))  # hedelmäpeli
	_box(Vector3(-10.18, f + 1.3, 11.7), Vector3(0.04, 0.4, 0.55), Color(0.3, 0.9, 0.4), false)
	_box(Vector3(-10.18, f + 0.9, 11.7), Vector3(0.04, 0.12, 0.4), Color(0.95, 0.8, 0.2), false)
	# Väki: Sinikka baaritiskillä, pöytäseurue ikkunapöydässä ja kaksi korttipelaajaa.
	sinikka = _npc(Looks.SINIKKA, P(-1.0, f, 11.1), 0.0, "Idle")
	# Pöytäseurue (Siitarin romaniseurueen mallit: naisilla samettihameet, miehillä tummat puvut) ikkunapöydässä.
	var skirt := Color(0.04, 0.04, 0.05)
	var seurue_looks := [
		{"model": "female", "shirt": Color(0.95, 0.92, 0.95), "pants": skirt, "shoes": Color(0.05, 0.05, 0.05), "hair": "Hair_Buns",
			"hair_color": Color(0.08, 0.06, 0.05), "height": 1.62, "skin": Color(0.92, 0.76, 0.62), "shine": 0.7},
		{"shirt": Color(0.1, 0.1, 0.12), "pants": Color(0.1, 0.1, 0.12), "shoes": Color(0.05, 0.05, 0.05), "hair": "Hair_SimpleParted",
			"hair_color": Color(0.06, 0.05, 0.05), "height": 1.78, "skin": Color(0.9, 0.74, 0.6), "belly": 0.3},
		{"model": "female", "shirt": Color(0.75, 0.15, 0.35), "pants": skirt, "shoes": Color(0.05, 0.05, 0.05), "hair": "Hair_Long",
			"hair_color": Color(0.1, 0.07, 0.05), "height": 1.66, "skin": Color(0.92, 0.76, 0.62), "shine": 0.7},
	]
	var seurue_at := [Vector2(-8.05, 14.6), Vector2(-9.55, 14.6), Vector2(-8.8, 13.85)]
	var seurue_yaw := [PI * 0.5, -PI * 0.5, 0.0]
	for k in 3:
		_seurue.append(_npc(seurue_looks[k], P(seurue_at[k].x, f, seurue_at[k].y), seurue_yaw[k], "Sitting_Idle"))
	# Sisävalo ja ääni: jukeboksi soi 3D-äänenä huoneessa.
	_in_light = OmniLight3D.new()
	_in_light.position = P(-4.0, 2.5, 12.5)
	_in_light.light_color = Color(1.0, 0.85, 0.6)
	_in_light.omni_range = 11.0
	_in_light.light_energy = 0.9
	_in_light.shadow_enabled = false
	_in_light.visible = false
	_root.add_child(_in_light)
	_jukebox = AudioStreamPlayer3D.new()
	_jukebox.position = P(-10.2, 1.0, 15.1)
	_jukebox.unit_size = 8.0
	_jukebox.max_distance = 40.0
	_jukebox.volume_db = -4.0
	_root.add_child(_jukebox)



## Hahmo normipäivän malleilla (looks.gd) sisätilaan: paikka, kääntö (y) ja animaatio.
func _npc(look: Dictionary, pos: Vector3, yaw: float, anim: String) -> Node3D:
	var c := Looks.make(_root, look)
	c.position = pos + (Vector3(0, 0.02, 0) if anim.begins_with("Sitting") else Vector3.ZERO)
	c.rotation.y = yaw
	c.play(anim, 0.0)
	return c


func _picnic(a: float, b: float) -> void:
	_box(Vector3(a, DECK_H + 0.75, b), Vector3(1.9, 0.06, 0.8), WOOD)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(a, DECK_H + 0.45, b + s * 0.75), Vector3(1.9, 0.05, 0.3), WOOD, false)
	_box(Vector3(a - 0.7, DECK_H + 0.37, b), Vector3(0.08, 0.74, 1.5), WOOD, false)
	_box(Vector3(a + 0.7, DECK_H + 0.37, b), Vector3(0.08, 0.74, 1.5), WOOD, false)


## Kioski ja vastaanotto parkkipaikan vieressä.
func _kiosk() -> void:
	_box(Vector3(-14.0, 1.35, 4.0), Vector3(3.6, 2.7, 3.2), Color(0.1, 0.55, 0.6))
	_roof(Vector3(-14.0, 3.2, 4.0), 3.6, 4.2, 0.9, ROOF, false)
	_box(Vector3(-14.0, 1.5, 2.37), Vector3(1.8, 1.1, 0.06), GLASS, false)  # myyntiluukku parkkipaikalle
	_box(Vector3(-14.0, 0.95, 2.2), Vector3(2.2, 0.06, 0.45), WOOD, false)
	_box(Vector3(-14.0, 2.4, 2.38), Vector3(3.0, 0.05, 0.1), Color.WHITE, false)
	var s := B.sign_plate(_root, "KIOSKI · VASTAANOTTO", Color(0.97, 0.95, 0.88), TRIM.darkened(0.3), 0.2, 40, TRIM)
	s.position = P(-14.0, 2.75, 2.33)


## Punamullattu mökki (4,2 x 3,6) valkoisin nurkin, ovi ja ikkuna a-suuntaan (itään).
func _cabin(a: float, b: float) -> void:
	_box(Vector3(a, 1.2, b), Vector3(4.2, 2.4, 3.6), RED)
	_box(Vector3(a, 2.42, b), Vector3(4.4, 0.08, 3.8), Color.WHITE, false)
	_roof(Vector3(a, 3.1, b), 4.6, 4.4, 1.3, ROOF.darkened(0.2), true)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(a + s * 2.12, 1.2, b - 1.82), Vector3(0.12, 2.4, 0.12), Color.WHITE, false)
		_box(Vector3(a + s * 2.12, 1.2, b + 1.82), Vector3(0.12, 2.4, 0.12), Color.WHITE, false)
	# Ovi ja ikkuna kohti pihaa (+a).
	_box(Vector3(a + 2.12, 1.0, b - 0.7), Vector3(0.06, 2.0, 0.9), Color.WHITE, false)
	_box(Vector3(a + 2.13, 1.4, b + 0.8), Vector3(0.06, 0.9, 0.9), GLASS, false)
	_box(Vector3(a + 2.9, 0.12, b - 0.7), Vector3(1.4, 0.24, 1.3), WOOD)  # rappu
	_box(Vector3(a + 0.1, 0.05, b + 2.3), Vector3(1.0, 0.1, 0.5), WOOD.darkened(0.2), false)  # polttopuupino


## Asuntovaunu kausipaikalla: valkoinen runko, kaarevat päädyt, ikkunat, tukijalat ja markiisi.
func _caravan(a: float, b: float, yaw: float) -> void:
	var node := Node3D.new()
	node.position = P(a, 0.0, b)
	node.rotation.y = yaw
	_root.add_child(node)
	B.box(node, Vector3(2.3, 2.0, 6.6), Vector3(0.0, 1.35, 0.0), Color(0.95, 0.95, 0.93))
	B.mesh(node, B.boxm(Vector3(2.35, 0.25, 6.7)), Vector3(0.0, 0.5, 0.0), Color(0.5, 0.52, 0.55))
	B.mesh(node, B.boxm(Vector3(2.32, 0.12, 6.62)), Vector3(0.0, 1.3, 0.0), Color(0.35, 0.55, 0.7))
	for z: float in [-1.8, 0.2, 2.0]:
		for s: float in [-1.0, 1.0]:
			B.mesh(node, B.boxm(Vector3(0.06, 0.7, 1.0)), Vector3(s * 1.16, 1.6, z), GLASS)
	for s: float in [-1.0, 1.0]:
		B.mesh(node, B.cyl(0.38, 0.38, 0.22, 14), Vector3(s * 1.2, 0.38, 0.4), Color(0.08, 0.08, 0.09), Vector3(0, 0, 90))
	B.mesh(node, B.boxm(Vector3(0.1, 0.1, 1.8)), Vector3(0.0, 0.7, -4.0), Color(0.3, 0.3, 0.32))  # vetokanki
	B.mesh(node, B.boxm(Vector3(2.0, 0.06, 2.0)), Vector3(1.9, 2.0, 0.2), Color(0.1, 0.6, 0.65)).rotation.z = -0.25  # markiisi
	B.mesh(node, B.boxm(Vector3(1.8, 0.04, 1.8)), Vector3(1.9, 0.02, 0.2), Color(0.35, 0.45, 0.3))  # matto


func _flag(a: float, b: float) -> void:
	_box(Vector3(a, 4.0, b), Vector3(0.1, 8.0, 0.1), Color(0.85, 0.85, 0.85))
	_box(Vector3(a, 7.2, b - 0.8), Vector3(0.02, 1.0, 1.6), Color.WHITE, false)
	_box(Vector3(a, 7.2, b - 0.8), Vector3(0.03, 1.0, 0.24), Color(0.0, 0.21, 0.56), false)
	_box(Vector3(a, 7.2, b - 0.8), Vector3(0.03, 0.24, 1.6), Color(0.0, 0.21, 0.56), false)


## Sisäänkäynti: iso kyltti tien varrella ("Camping Happy Beach · Vankkuritie 1") ja kaksi valopylvästä.
func _entrance() -> void:
	var s := B.sign_plate(_root, "CAMPING HAPPY BEACH\nVankkuritie 1 · ympärivuotinen", TRIM, Color.WHITE, 0.3, 54,
		Color(0.95, 0.9, 0.5))
	var w: float = s.get_meta("width")
	s.position = P(18.0, 2.3, -17.0)  # tien (a ≈ 11 kohdassa b = -17) vieressä, teksti tulijaa kohti
	_box(Vector3(18.0 - w * 0.5 + 0.1, 1.15, -17.0), Vector3(0.12, 2.3, 0.12), WOOD, false)
	_box(Vector3(18.0 + w * 0.5 - 0.1, 1.15, -17.0), Vector3(0.12, 2.3, 0.12), WOOD, false)
	for sa: float in [3.0, 10.6]:
		_box(Vector3(sa, 1.4, -11.0), Vector3(0.1, 2.8, 0.1), WOOD, false)
		_lamp_bulb(P(sa, 2.9, -11.0))


## Auringonlaskupenkit törmän reunalla, katse järvelle.
func _benches() -> void:
	for a: float in [-14.0, -8.0, 14.0]:
		var b := 26.5
		var gy := ground(a, b)
		_box(Vector3(a, gy + 0.45, b), Vector3(1.8, 0.07, 0.45), WOOD)
		_box(Vector3(a, gy + 0.75, b - 0.25), Vector3(1.8, 0.4, 0.06), WOOD, false)
		for s: float in [-0.8, 0.8]:
			_box(Vector3(a + s, gy + 0.22, b), Vector3(0.08, 0.44, 0.4), WOOD, false)


## Pitkospolku törmältä hiekkarannalle: lankut maaston pinnalla ja kaide yhdellä sivulla.
func _beach_path() -> void:
	var b: float = STAIR_B[1]
	while b < PATH_B[1]:
		var y0 := ground(PATH_A, b - 0.5)
		var y1 := ground(PATH_A, b + 0.5)
		var xf := Transform3D(Basis(Vector3.RIGHT, atan2(y1 - y0, 1.0)), P(PATH_A, (y0 + y1) * 0.5 + 0.05, b))
		_batch.add(B.boxm(Vector3(1.3, 0.05, 0.38)), xf, WOOD)
		b += 0.5
	b = STAIR_B[1]
	while b < PATH_B[1]:
		_batch.add(B.boxm(Vector3(0.07, 0.9, 0.07)), Transform3D(Basis(), P(PATH_A + 0.7, ground(PATH_A + 0.7, b) + 0.45, b)),
			WOOD.darkened(0.2))
		b += 3.0


## Portaat baarin tasanteelta törmää alas rannalle (pitkospolun kohdalla, a = PATH_A), mökin portaiden tapaan: valkoiset
## askelmat ja nousut, sivupalkit, tolpalliset kaiteet molemmin puolin, tasanteet ylä- ja alapäässä sekä tuet maahan.
## Törmäyskappale on rampin pinta askelmien etureunojen kautta.
func _bar_stairs() -> void:
	var w := 1.5
	var white := Color(0.8, 0.8, 0.78)
	var b0: float = STAIR_B[0]
	var b1: float = STAIR_B[1]
	var y0 := ground(PATH_A, b0) + 0.0
	var y1 := ground(PATH_A, b1) + 0.05
	var rise := y1 - y0
	var n := maxi(1, int(round(absf(rise) / 0.185)))
	var tr := (b1 - b0) / n
	var rs := rise / n
	for k in n:
		var ty := y0 + rs * (k + 1)
		var bk := b0 + tr * k
		_batch.add(B.boxm(Vector3(w, 0.05, tr + 0.04)), Transform3D(Basis(), P(PATH_A, ty - 0.025, bk + tr * 0.5)), white)
		_batch.add(B.boxm(Vector3(w - 0.06, absf(rs), 0.03)), Transform3D(Basis(), P(PATH_A, ty - rs * 0.5 - 0.04, bk + 0.015)), white.darkened(0.08))
	# Sivupalkit, kaiteet (tolpat, käsijohde ja välijohde) ja tuet maahan.
	var ang := atan2(rise, b1 - b0)  # nousukulma (b kasvaa alas)
	var len_s := Vector2(b1 - b0, rise).length()
	for sa: float in [PATH_A - w * 0.5 - 0.03, PATH_A + w * 0.5 + 0.03]:
		var mid := P(sa, (y0 + y1) * 0.5 - 0.1, (b0 + b1) * 0.5)
		var bas := Basis(Vector3.RIGHT, ang)  # b = -z paikallisessa kehyksessä
		_batch.add(B.boxm(Vector3(0.05, 0.3, len_s)), Transform3D(bas, mid), white)
		for rail_y: float in [0.93, 0.5]:
			_batch.add(B.boxm(Vector3(0.1 if rail_y > 0.9 else 0.03, 0.04 if rail_y > 0.9 else 0.09, len_s)),
				Transform3D(bas, P(sa, (y0 + y1) * 0.5 + rail_y, (b0 + b1) * 0.5)), white)
		var nn := int((b1 - b0) / 1.3)
		for k in nn + 1:
			var bb := b0 + 0.3 + (b1 - b0 - 0.6) * float(k) / nn
			var yy := lerpf(y0, y1, (bb - b0) / (b1 - b0))
			_batch.add(B.boxm(Vector3(0.07, 0.95, 0.07)), Transform3D(Basis(), P(sa, yy + 0.47, bb)), white)
	var bb := b0 + 1.6
	while bb < b1:
		var yy := lerpf(y0, y1, (bb - b0) / (b1 - b0)) - 0.15
		var g := ground(PATH_A, bb)
		if yy - g > 0.2:
			for sa: float in [PATH_A - w * 0.5, PATH_A + w * 0.5]:
				_batch.add(B.boxm(Vector3(0.1, yy - g + 0.2, 0.1)), Transform3D(Basis(), P(sa, (yy + g - 0.2) * 0.5, bb)), white.darkened(0.15))
		bb += 1.6
	# Tasanteet: ylhäällä baarin puolella ja alhaalla rannalla.
	_box(Vector3(PATH_A, y0 - 0.03, b0 - 0.6), Vector3(w + 0.3, 0.06, 1.2), white, false)
	_box(Vector3(PATH_A, y1 - 0.03, b1 + 0.6), Vector3(w + 0.3, 0.06, 1.2), white, false)
	# Törmäys: ramppi askelmien etureunojen kautta.
	var body := StaticBody3D.new()
	var cs := B.box_shape(Vector3(w, 0.2, len_s + 0.1))
	body.add_child(cs)
	body.position = P(PATH_A, (y0 + y1) * 0.5 - 0.1, (b0 + b1) * 0.5)
	body.rotation.x = ang
	_root.add_child(body)
	# Kyltti ylhäällä: "BAARI".
	var sg := B.sign_plate(_root, "BAARI ↑\nkioski · karaoke", TRIM, Color.WHITE, 0.2, 38, Color(0.95, 0.9, 0.5))
	sg.position = P(PATH_A - 1.4, y0 + 1.5, b0 - 0.4)
	sg.rotation.y = PI
	_box(Vector3(PATH_A - 1.4, y0 + 0.75, b0 - 0.4), Vector3(0.08, 1.5, 0.08), WOOD.darkened(0.3), false)


## Hiekkarannalla aurinkotuolit ja rantapallo, laituri järveen.
func _beach_and_jetty() -> void:
	for a: float in [-4.0, 0.0, 3.5]:
		var b := 45.6
		var gy := ground(a, b)
		_batch.add(B.boxm(Vector3(0.7, 0.07, 1.8)), Transform3D(Basis(Vector3.RIGHT, 0.2), P(a, gy + 0.3, b)), Color(0.1, 0.6, 0.65))
		for s: float in [-0.3, 0.3]:
			_batch.add(B.boxm(Vector3(0.05, 0.3, 0.05)), Transform3D(Basis(), P(a + s, gy + 0.12, b - 0.7)), WOOD)
	_batch.add(B.sphere(0.22, 10), Transform3D(Basis(), P(-1.8, ground(-1.8, 46.2) + 0.22, 46.2)), Color(0.95, 0.35, 0.2))
	# Laituri: kansi n. 1 m järven pinnan yläpuolella rannasta 14 m ulos, tolpat pohjaan.
	var ja := 14.0
	var b0 := 46.0
	var deck_y := maxf(0.75, ground(ja, b0) + pad_y + 0.05)  # kansi 0,75 m vedenpinnan yläpuolella kuten Äpätin sillalla
	var reach := 26.0
	var hw := JETTY_W * 0.5
	_box(Vector3(ja, deck_y - pad_y, b0 + reach * 0.5), Vector3(JETTY_W, 0.1, reach), WOOD)
	_box(Vector3(ja, deck_y - pad_y - 0.28, b0 + reach * 0.5), Vector3(JETTY_W, 0.35, reach), Color(0, 0, 0, 0), false)
	var k := 0.0
	while k <= reach:
		for s: float in [-hw + 0.12, hw - 0.12]:
			_box(Vector3(ja + s, deck_y - pad_y - 1.0, b0 + k), Vector3(0.12, 2.0, 0.12), WOOD.darkened(0.3), false)
		k += 3.5
	# T-pää (a 8…20) kuten Äpätin sillassa.
	_box(Vector3(ja, deck_y - pad_y, b0 + reach - 0.7), Vector3(12.0, 0.1, 1.6), WOOD)
	for pa: float in [8.4, 11.2, 14.0, 16.8, 19.6]:
		_box(Vector3(pa, deck_y - pad_y - 1.0, b0 + reach - 1.3), Vector3(0.12, 2.0, 0.12), WOOD.darkened(0.3), false)
		_box(Vector3(pa, deck_y - pad_y - 1.0, b0 + reach - 0.1), Vector3(0.12, 2.0, 0.12), WOOD.darkened(0.3), false)
	_box(Vector3(ja, deck_y - pad_y + 0.12, b0 + reach), Vector3(12.0, 0.3, 0.1), WOOD.darkened(0.3), false)  # päätyreunus
	for sa: float in [ja - hw, ja + hw - 0.1]:  # reunapalkit koko sillan matkalla
		_box(Vector3(sa + 0.05, deck_y - pad_y + 0.01, b0 + reach * 0.5), Vector3(0.1, 0.3, reach), WOOD.darkened(0.3), false)
	_harbor(ja, b0, reach, deck_y - pad_y + 0.05)
	_marina()
	_bar_stairs()


## Satama satelliittikuvan mukaan: rantapenger ja itäkärki, pohjoinen aallonmurtaja ja länsimuuri louhikkoa (törmäyskappaleet
## veneelle ja kävelyreitti penkereellä), kolme kelluvaa laituria sormilaitureineen ja pienveneineen, pysäköintialue ja
## nostoramppi länsipäässä sekä lamput ja kyltti.
func _marina() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var top := MARINA_TOP - pad_y
	var rock := Color(0.5, 0.48, 0.45)
	# Louhikkopenkereet: tasainen harja (kävelypinta) ja päälle ripoteltuja lohkareita.
	var mole := func(a0: float, b0: float, a1: float, b1: float, w: float) -> void:
		var ac := (a0 + a1) * 0.5
		var bc := (b0 + b1) * 0.5
		var len_a := absf(a1 - a0) + (w if b0 == b1 else 0.0)
		var len_b := absf(b1 - b0) + (w if a0 == a1 else 0.0)
		var bottom := -pad_y - 2.5
		_box(Vector3(ac, (top + bottom) * 0.5, bc), Vector3(maxf(len_a, w), top - bottom, maxf(len_b, w)), rock.darkened(0.15))
		var n := int(maxf(len_a, len_b) / 0.9)
		for k in n:
			var t := rng.randf()
			var pa := lerpf(a0, a1, t)
			var pb := lerpf(b0, b1, t)
			if b0 == b1:
				pb += rng.randf_range(-w * 0.5, w * 0.5)
			else:
				pa += rng.randf_range(-w * 0.5, w * 0.5)
			var sz := Vector3(rng.randf_range(0.8, 1.7), rng.randf_range(0.4, 0.9), rng.randf_range(0.8, 1.7))
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)))
			_batch.add(B.boxm(sz), Transform3D(basis, P(pa, top + 0.05, pb)), rock.darkened(0.2).lerp(Color(0.55, 0.52, 0.48), rng.randf()))
	mole.call(-2.0, 50.4, 76.0, 50.4, 4.0)   # rantapenger
	mole.call(75.0, 50.4, 75.0, 62.0, 4.0)   # itäkärki (sisääntulon eteläpuoli)
	mole.call(-2.0, 50.4, -2.0, 90.0, 3.5)   # länsimuuri
	mole.call(-2.0, 90.0, 52.0, 90.0, 4.0)   # pohjoinen aallonmurtaja
	# Kelluvat laiturit: kaksi päälaituria a-suunnassa sormilaitureineen kohtisuoraan, ja kulkulaituri pohjoismurtajalta.
	var pont := WOOD.lerp(Color(0.7, 0.68, 0.62), 0.5)
	var py := 0.35 - pad_y
	for row: float in [76.0, 83.0]:
		_box(Vector3(46.0, py, row), Vector3(42.0, 0.14, 1.6), pont, false)
		var a := 26.5
		while a < 67.0:
			for sd: float in [-1.0, 1.0]:
				_box(Vector3(a, py, row + sd * 3.4), Vector3(0.5, 0.12, 5.6), pont.darkened(0.1), false)
			a += 4.4
	# Päälaituri pohjoismurtajalta kellukkeille (kulku pohjoisesta).
	_box(Vector3(30.0, py, 87.5), Vector3(1.4, 0.14, 6.0), pont, false)
	# Pysäköintialue ja nostoramppi länsipäässä (hiekkarannan puolella).
	for k in 3:
		var ga := 2.0 + k * 9.0
		var gb := 40.0
		_box(Vector3(ga + 4.0, ground(ga + 4.0, gb) + 0.04, gb), Vector3(9.0, 0.06, 8.0), Color(0.42, 0.42, 0.44), false)
	for k in 6:
		var ra := 2.0 + k * 3.0
		_box(Vector3(ra, ground(ra, 45.5) + 0.05, 45.5), Vector3(0.12, 0.05, 6.0), Color(0.9, 0.9, 0.88), false)
	_box(Vector3(10.0, ground(10.0, 47.5) + 0.06, 47.5), Vector3(5.0, 0.08, 4.0), Color(0.62, 0.62, 0.6), false)  # ramppi
	# Lamput penkereen kulmissa ja kyltti.
	for q: Vector2 in [Vector2(70.0, 50.4), Vector2(30.0, 50.4), Vector2(48.0, 90.0), Vector2(75.0, 61.0)]:
		_box(Vector3(q.x, top + 1.4, q.y), Vector3(0.1, 2.8, 0.1), Color(0.3, 0.3, 0.32), false)
		_lamp_bulb(P(q.x, top + 2.85, q.y))
	var sg := B.sign_plate(_root, "HAPPY BEACH\nVENESATAMA", TRIM, Color.WHITE, 0.2, 38, Color(0.95, 0.9, 0.5))
	sg.position = P(4.0, top + 1.6, 44.0)
	sg.rotation.y = PI
	_box(Vector3(4.0, top + 0.8, 44.0), Vector3(0.08, 1.6, 0.08), WOOD.darkened(0.3), false)


## Laiturin yksityiskohdat: leveä purkupaikka päässä, kaiteet, pollarit, renkaat suojana, tikkaat, pelastusrengas,
## lyhdyt, kyltti, soutuvene ja uimapoijut sekä rantavarasto. Muskeliveneen paikka (jetty_mooring) on laiturin itäkyljessä
## (a ≈ 16,4, b ≈ 57,2), joten itäpuoli pidetään vapaana ja lisäosat rakennetaan länsipuolelle.
func _harbor(ja: float, b0: float, reach: float, dy: float) -> void:
	var steel := Color(0.3, 0.32, 0.35)
	var wood_d := WOOD.darkened(0.3)
	var end := b0 + reach
	# Laudoituksen saumat poikittain.
	var k := b0 + 0.5
	while k < end:
		_batch.add(B.boxm(Vector3(JETTY_W, 0.012, 0.025)), Transform3D(Basis(), P(ja, dy + 0.006, k)), WOOD.darkened(0.3))
		k += 0.5
	# Reunapalkit ja tolppien päät laiturin molemmin puolin.
	for sa: float in [ja - 1.18, ja + 1.18]:
		_box(Vector3(sa, dy + 0.06, b0 + reach * 0.5), Vector3(0.1, 0.12, reach), wood_d, false)
	k = b0 + 0.3
	while k <= end:
		for sa: float in [ja - 1.1, ja + 1.1]:
			_box(Vector3(sa, dy + 0.07, k), Vector3(0.16, 0.14, 0.16), wood_d, false)
		k += 3.5
	# Kaide laiturin länsireunalla ja päätyosan reunoilla (itäreuna jätetään auki veneen nousulle).
	for pb in range(int(b0) + 2, int(end), 3):
		_box(Vector3(ja - 1.12, dy + 0.5, float(pb)), Vector3(0.08, 1.0, 0.08), WOOD.lightened(0.05), false)
	_box(Vector3(ja - 1.12, dy + 0.95, (b0 + 2.0 + end - 1.0) * 0.5), Vector3(0.07, 0.06, end - b0 - 3.0), WOOD.lightened(0.05), false)
	_box(Vector3(ja - 1.12, dy + 0.5, (b0 + 2.0 + end - 1.0) * 0.5), Vector3(0.06, 0.05, end - b0 - 3.0), WOOD.lightened(0.05), false)
	# Pollarit veneen puolella ja päädyssä, sekä rengasfenderit itäkyljessä.
	for bb: float in [54.8, 57.2, 59.4]:
		B.mesh(_root, B.cyl(0.1, 0.1, 0.34, 8), P(ja + 1.0, dy + 0.17, bb), steel)
		B.mesh(_root, B.cyl(0.14, 0.14, 0.06, 8), P(ja + 1.0, dy + 0.36, bb), steel)
	for fb: float in [54.0, 56.0, 58.0]:
		B.mesh(_root, B.cyl(0.26, 0.26, 0.2, 10), P(ja + 1.22, dy - 0.28, fb), Color(0.08, 0.08, 0.09), Vector3(0, 0, 90))
	# Tikkaat veteen luoteiskulmassa ja pelastusrengas pylväässä.
	for rb: float in [end - 0.2, end - 2.6]:
		B.mesh(_root, B.cyl(0.02, 0.02, 1.2, 6), P(9.3, dy - 0.45, rb), steel)
	for rr in 4:
		B.mesh(_root, B.cyl(0.02, 0.02, 0.0 + 2.4, 6), P(9.3, dy - 0.7 - rr * 0.0, end - 1.4 - 1.2 + rr * 0.8), steel, Vector3(90, 0, 0))
	_box(Vector3(ja - 1.12, dy + 1.4, b0 + 3.0), Vector3(0.08, 1.8, 0.08), Color(0.85, 0.85, 0.85), false)
	B.mesh(_root, B.cyl(0.32, 0.32, 0.08, 14), P(ja - 1.06, dy + 1.5, b0 + 3.0), Color(0.95, 0.35, 0.12), Vector3(0, 0, 90))
	# Lyhtypylväät: kaksi laiturilla ja yksi päässä (iltaisin päällä, set_lamp).
	for lb: float in [b0 + 6.0, end - 0.3]:
		_box(Vector3(ja - 1.12, dy + 1.4, lb), Vector3(0.07, 2.8, 0.07), Color(0.3, 0.3, 0.32), false)
		_lamp_bulb(P(ja - 1.12, dy + 2.85, lb))
	# Kyltti laiturin juuressa ja ankkuri koristeena.
	var sg := B.sign_plate(_root, "HAPPY BEACH\nVENELAITURI", TRIM, Color.WHITE, 0.2, 38, Color(0.95, 0.9, 0.5))
	sg.position = P(ja - 1.6, dy + 1.35, b0 + 0.4)
	sg.rotation.y = PI
	_box(Vector3(ja - 1.6, dy + 0.65, b0 + 0.4), Vector3(0.08, 1.3, 0.08), wood_d, false)
	# Soutuvene köysin laiturin länsikyljessä ja uimapoijut.
	var boat := Node3D.new()
	boat.position = P(ja - 3.2, -pad_y, b0 + 8.0)
	boat.rotation.y = 0.12
	_root.add_child(boat)
	B.mesh(boat, B.boxm(Vector3(1.3, 0.4, 3.2)), Vector3(0, 0.0, 0), Color(0.75, 0.45, 0.22))
	B.mesh(boat, B.boxm(Vector3(1.1, 0.05, 3.0)), Vector3(0, 0.19, 0), Color(0.9, 0.85, 0.7))
	B.mesh(boat, B.boxm(Vector3(1.1, 0.06, 0.3)), Vector3(0, 0.26, 0.2), WOOD)
	B.mesh(boat, B.boxm(Vector3(0.05, 0.05, 1.8)), Vector3(0.55, 0.3, 0.2), WOOD, Vector3(0, 0, 0))
	B.mesh(_root, B.cyl(0.015, 0.015, 3.0, 4), P(ja - 1.7, dy - 0.15, b0 + 8.0), Color(0.8, 0.75, 0.6), Vector3(0, 0, 90))
	for i in 4:
		var pb := b0 + 3.0 + i * 4.0
		B.mesh(_root, B.sphere(0.2, 8), P(ja - 9.0, -pad_y, pb), Color(0.95, 0.3, 0.1) if i % 2 == 0 else Color.WHITE)
	# Rantavarasto laiturin juurella: pieni punainen vaja, polttopuuvaja ja pelastusveneen kannatin.
	var sa := 8.0
	var sb := 41.8
	var sy := ground(sa, sb)
	_box(Vector3(sa, sy + 0.9, sb), Vector3(2.4, 1.8, 2.0), RED)
	_roof(Vector3(sa, sy + 2.05, sb), 2.8, 2.6, 0.7, ROOF.darkened(0.2), true)
	_box(Vector3(sa + 1.22, sy + 0.8, sb), Vector3(0.05, 1.5, 0.9), Color.WHITE, false)
	_box(Vector3(sa + 1.23, sy + 1.35, sb + 0.6), Vector3(0.05, 0.4, 0.4), GLASS, false)
	for ta: float in [10.2, 10.8]:
		B.mesh(_root, B.cyl(0.25, 0.25, 0.8, 10), P(ta, ground(ta, 42.4) + 0.4, 42.4), Color(0.15, 0.3, 0.55))

