extends Node3D
## Päikkäreiden välianimaatio ylämökin sisältä: kamera katsoo ovelta mökin sisään kohti järven puoleista ikkunaa,
## josta näkyy järvimaisema. Oven oikealla puolella on parisänky ja vasemmalla vuodesohva. Porukan omat hahmot
## (Santtu, Marko ja Jaakko omine ulkonäköineen; Jukka ei nuku päikkäreitä) nukkuvat selällään ruudullisten
## untuvapeittojen alla, rinta nousee ja laskee, ja kuorsaus nousee Z-kirjaimina. Kamera liukuu hitaasti ovelta
## sisemmäs. Sisätila on mökin pohjan sisällä ja näkyy vain välianimaation ajan (main.gd: _nap ja _wake);
## hahmot rakennetaan vasta ensimmäisellä kerralla.

const B := preload("res://scripts/build.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Looks := preload("res://scripts/looks.gd")
const Porukka := preload("res://scripts/porukka.gd")

## Huonekalut mökin kehyksessä (x pitkin järven puoleista seinää, v järvelle), ovelta katsottuna:
## parisänky oikealla (+x), vuodesohva vasemmalla (-x); pääty metsän puoleista seinää (ovea) vasten.
const DOUBLE := [0.45, 1.85, -1.75, 0.3]  # [x0, x1, v0, v1]
const SOFA := [-1.85, -0.85, -1.75, 0.3]
## Ikkuna järven puoleisessa päädyssä (mokki.gd _cabin): x-väli ja korkeus lattiasta.
const WINDOW := [-0.65, 0.65, 0.85, 1.9]

var cam: Camera3D
var _t := 0.0
var sleepers: Array[Node3D] = []  # nukkujien hahmot (character.gd)
var _slots: Array = []  # nukkumapaikat: [jalkopään paikka, suunta päähän]
var _zzz: Array[Label3D] = []
var _cam_a := Vector3.ZERO
var _cam_b := Vector3.ZERO
var _look := Vector3.ZERO


func _ready() -> void:
	visible = false
	var fy := Mokki.floor_y()
	var o := Mokki.cw(0.0, 0.0)
	var x := Vector3(Mokki.CABIN_X.x, 0.0, Mokki.CABIN_X.y)
	var z := -Vector3(Mokki.CABIN_LAKE.x, 0.0, Mokki.CABIN_LAKE.y)
	transform = Transform3D(Basis(x, Vector3.UP, z), Vector3(o.x, fy, o.y))
	_build_room()
	_double_bed()
	_sofa_bed()
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.05
	add_child(cam)
	var dc := (Mokki.CABIN_DOOR.x + Mokki.CABIN_DOOR.y) * 0.5
	_cam_a = _p(dc, -Mokki.CABIN_HV + 0.3, 1.75)  # ovelta
	_cam_b = _p(dc, -Mokki.CABIN_HV + 0.85, 1.65)
	_look = _p(dc * 0.3, Mokki.CABIN_HV, 0.85)  # ikkunaa kohti
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.8, 0.55)
	lamp.light_energy = 1.0
	lamp.omni_range = 4.5
	lamp.position = _p(0.0, -0.5, 2.0)
	add_child(lamp)
	var window := OmniLight3D.new()  # päivänvalo järven puoleisesta ikkunasta
	window.light_color = Color(0.9, 0.95, 1.0)
	window.light_energy = 1.4
	window.omni_range = 4.5
	window.position = _p(0.0, Mokki.CABIN_HV - 0.4, 1.4)
	add_child(window)
	process_mode = Node.PROCESS_MODE_DISABLED


## Paikallinen piste mökin kehyksestä (x, v, korkeus lattiasta).
static func _p(x: float, v: float, y: float) -> Vector3:
	return Vector3(x, y, -v)


func _box(size: Vector3, at: Vector3, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = B.boxm(size)
	mi.material_override = B.mat(col)
	mi.position = at
	add_child(mi)
	return mi


## Laatikko mökin kehyksen rajoista x0..x1, v0..v1 ja korkeuksista y0..y1.
func _bx(x0: float, x1: float, v0: float, v1: float, y0: float, y1: float, col: Color) -> MeshInstance3D:
	return _box(Vector3(x1 - x0, y1 - y0, v1 - v0), _p((x0 + x1) * 0.5, (v0 + v1) * 0.5, (y0 + y1) * 0.5), col)


## Lattia, paneloidut seinät (järven puoleisessa ikkunan aukko), sisäkatto, räsymatto ja lamppu ikkunalaudalla.
func _build_room() -> void:
	var hx := Mokki.CABIN_HX - 0.2
	var hv := Mokki.CABIN_HV - 0.2
	_bx(-hx, hx, -hv, hv, 0.0, 0.02, Color(0.62, 0.48, 0.32))
	var panel := Color(0.78, 0.66, 0.48)
	_bx(-hx, hx, -hv - 0.02, -hv, 0.0, 2.3, panel)  # metsän puoli (ovi kameran takana)
	_bx(-hx - 0.02, -hx, -hv, hv, 0.0, 2.3, panel)
	_bx(hx, hx + 0.02, -hv, hv, 0.0, 2.3, panel)
	# Järven puoleinen seinä ikkuna-aukon ympäriltä: ikkunasta näkyy oikea järvimaisema.
	var w: Array = WINDOW
	_bx(-hx, w[0], hv, hv + 0.02, 0.0, 2.3, panel)
	_bx(w[1], hx, hv, hv + 0.02, 0.0, 2.3, panel)
	_bx(w[0], w[1], hv, hv + 0.02, 0.0, w[2], panel)
	_bx(w[0], w[1], hv, hv + 0.02, w[3], 2.3, panel)
	_bx(w[0] - 0.05, w[1] + 0.05, hv - 0.18, hv, w[2] - 0.04, w[2], Color(0.95, 0.95, 0.93))  # ikkunalauta
	_bx(-hx, hx, -hv, hv, 2.3, 2.32, Color(0.86, 0.8, 0.68))  # sisäkatto
	# Räsymatto sänkyjen välissä.
	var stripes := [Color(0.7, 0.2, 0.15), Color(0.2, 0.35, 0.6), Color(0.85, 0.8, 0.6), Color(0.3, 0.5, 0.3)]
	for k in 10:
		_bx(-0.65, 0.3, -1.3 + k * 0.13, -1.17 + k * 0.13, 0.02, 0.03, stripes[k % stripes.size()])
	# Pieni lamppu ja kahvimuki ikkunalaudalla.
	var lampb := MeshInstance3D.new()
	lampb.mesh = B.cyl(0.04, 0.07, 0.22, 12)
	lampb.material_override = B.mat(Color(0.3, 0.3, 0.32))
	lampb.position = _p(0.5, hv - 0.09, w[2] + 0.11)
	add_child(lampb)
	var shade := MeshInstance3D.new()
	shade.mesh = B.cyl(0.06, 0.12, 0.14, 14)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1.0, 0.9, 0.7)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.8, 0.5)
	sm.emission_energy_multiplier = 1.2
	shade.material_override = sm
	shade.position = _p(0.5, hv - 0.09, w[2] + 0.29)
	add_child(shade)
	var mug := MeshInstance3D.new()
	mug.mesh = B.cyl(0.04, 0.035, 0.09, 10)
	mug.material_override = B.mat(Color(0.9, 0.9, 0.88))
	mug.position = _p(-0.45, hv - 0.09, w[2] + 0.045)
	add_child(mug)


## Parisänky oven oikealla puolella: puurunko, päätylauta metsän puoleista seinää vasten, kaksi tyynyä, yhteinen
## untuvapeitto; kaksi nukkujaa vierekkäin.
func _double_bed() -> void:
	var r: Array = DOUBLE
	var wood := Color(0.55, 0.4, 0.26)
	_bx(r[0], r[1], r[2], r[3], 0.0, 0.32, wood)
	_bx(r[0] + 0.04, r[1] - 0.04, r[2] + 0.04, r[3] - 0.04, 0.32, 0.46, Color(0.92, 0.92, 0.9))
	_bx(r[0], r[1], r[2], r[2] + 0.06, 0.0, 0.95, wood.darkened(0.1))  # päätylauta
	var length: float = r[3] - r[2]
	for k in 2:
		var x: float = lerpf(r[0], r[1], 0.27 + k * 0.46)
		_bx(x - 0.28, x + 0.28, r[2] + 0.08, r[2] + 0.42, 0.46, 0.57, Color(0.95, 0.95, 0.97))  # tyyny
		_slot(x, r[3] - 0.05, 0.6, length)
	_duvet((r[0] + r[1]) * 0.5, r[1] - r[0] + 0.08, r[2], r[3], Color(0.65, 0.12, 0.1))


## Vuodesohva oven vasemmalla puolella: avattu sohva, selkänoja länsiseinää vasten ja käsinojat päissä, patja ja
## peitto; yksi nukkuja.
func _sofa_bed() -> void:
	var r: Array = SOFA
	var fabric := Color(0.3, 0.42, 0.33)
	_bx(r[0], r[1], r[2], r[3], 0.0, 0.3, fabric.darkened(0.2))
	_bx(r[0] + 0.02, r[1] - 0.02, r[2] + 0.1, r[3] - 0.1, 0.3, 0.42, fabric)  # patja
	_bx(r[0], r[0] + 0.18, r[2], r[3], 0.3, 0.85, fabric.darkened(0.1))  # selkänoja
	for v: float in [r[2], r[3] - 0.12]:
		_bx(r[0], r[1], v, v + 0.12, 0.3, 0.62, fabric.darkened(0.15))  # käsinojat
	var x: float = (r[0] + 0.18 + r[1]) * 0.5
	_bx(x - 0.28, x + 0.28, r[2] + 0.13, r[2] + 0.45, 0.42, 0.52, Color(0.95, 0.95, 0.97))  # tyyny
	_slot(x, r[3] - 0.15, 0.56, r[3] - r[2] - 0.25)
	_duvet(x, r[1] - r[0] - 0.16, r[2] + 0.12, r[3] - 0.12, Color(0.15, 0.3, 0.55))


## Nukkumapaikka: jalkopää (x, v), korkeus ja pituus; pää metsän puoleista seinää kohti. Kuorsaus pään yllä.
func _slot(x: float, v_foot: float, y: float, length: float) -> void:
	_slots.append([_p(x, v_foot, y), Vector3(0, 0, 1)])  # pää -v-suuntaan eli paikallisesti +z
	var z := Label3D.new()
	z.text = "Z"
	z.font_size = 64
	z.pixel_size = 0.004
	z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	z.modulate = Color(1, 1, 1, 0.9)
	z.outline_size = 12
	z.set_meta("base", _p(x + 0.1, v_foot - length + 0.3, y + 0.5))
	z.set_meta("phase", _zzz.size() * 1.3)
	add_child(z)
	_zzz.append(z)


## Pehmeä ruudullinen untuvapeitto jalkopäästä rintaan asti: litistetty kapseli, joka pullistuu nukkujien päällä
## ja valuu reunojen yli; yläreunassa valkoinen lakanan taite.
func _duvet(xc: float, width: float, v_head: float, v_foot: float, col: Color) -> void:
	var cover := (v_foot - v_head) * 0.66
	var mid := _p(xc, v_foot - cover * 0.5, 0.66)
	var duvet := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = width * 0.5
	cap.height = cover + cap.radius
	cap.radial_segments = 28
	cap.rings = 8
	duvet.mesh = cap
	duvet.material_override = _plaid(col)
	# Kapselin akseli (y) pituussuuntaan (paikallinen z), leveys x:ään, paksuus litistettynä ylös.
	duvet.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN * 0.42), mid)
	add_child(duvet)
	var fold := MeshInstance3D.new()
	var fc := CapsuleMesh.new()
	fc.radius = 0.07
	fc.height = width + 0.05
	fold.mesh = fc
	fold.material_override = B.mat(Color(0.95, 0.95, 0.97))
	fold.transform = Transform3D(Basis(Vector3.UP * 0.6, Vector3.RIGHT, Vector3.BACK).orthonormalized().scaled(Vector3.ONE),
		mid + Vector3(0, 0.12, cover * 0.5))
	fold.basis = Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(1.0, 1.0, 0.6))
	add_child(fold)


## Ruudullinen kangas: vaaleammat ja tummemmat raidat ristiin pohjavärin päällä.
func _plaid(base: Color) -> StandardMaterial3D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	for y in 32:
		for x in 32:
			var col := base
			if x % 16 < 4:
				col = col.lightened(0.25)
			if y % 16 < 4:
				col = col.lightened(0.25)
			if x % 16 == 9 or y % 16 == 9:
				col = col.darkened(0.45)
			img.set_pixel(x, y, col)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(2.5, 2.5, 2.5)
	m.roughness = 0.95
	return m


## Porukan nukkujat paikoilleen: kaikki paitsi Jukka (ei nuku päikkäreitä), selällään pää tyynyllä.
func _build_sleepers() -> void:
	var k := 0
	for i in Porukka.CREW.size():
		if Porukka.CREW[i].name == "Jukka" or k >= _slots.size():
			continue
		var slot: Array = _slots[k]
		k += 1
		var holder := Node3D.new()
		holder.position = slot[0]
		holder.basis = Basis.looking_at(-(slot[1] as Vector3))  # paikallinen +z päähän päin
		add_child(holder)
		var ch := Looks.make(holder, Porukka.look(i))
		Porukka.decorate(i, ch)
		ch.rotation.x = PI * 0.5  # selällään, kasvot ylös
		ch.play("Idle", 0.0, 0.3)
		sleepers.append(ch)


func play() -> void:
	if sleepers.is_empty():
		_build_sleepers()
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_t = 0.0
	cam.current = true


func stop() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED  # nukkujien animaatiot seis, kun välianimaatio ei näy


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var k := smoothstep(0.0, 10.0, _t)
	cam.position = _cam_a.lerp(_cam_b, k)
	cam.look_at(to_global(_look), Vector3.UP)
	# Hengitys: rinta nousee ja laskee, kullakin omassa tahdissaan.
	for i in sleepers.size():
		sleepers[i].set_override("spine_03", Vector3.RIGHT, sin(_t * 1.6 + i * 1.7) * 0.05)
	# Kuorsaus: Z nousee ja kasvaa, häipyy ja alkaa alusta.
	for z in _zzz:
		var ph := fmod(_t * 0.45 + float(z.get_meta("phase")), 1.0)
		z.position = (z.get_meta("base") as Vector3) + Vector3(sin(ph * 6.0) * 0.08, ph * 0.7, 0)
		z.modulate.a = sin(ph * PI) * 0.9
		z.font_size = int(40 + ph * 50)
