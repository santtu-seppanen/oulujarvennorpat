extends Node3D
## Päikkäreiden välianimaatio ylämökin sisältä: kolme norppaa nukkuu sängyissä peittojen alla, kyljet
## nousevat ja laskevat, ja kuorsaus nousee Zzz-kuplina. Kamera liukuu hitaasti oven puoleisesta nurkasta
## sänkyjä kohti. Sisätila (lattia, räsymatto, sängyt, yöpöytä ja lamppu) on mökin pohjan sisällä ja näkyy vain
## välianimaation ajan (main.gd: _nap ja _wake).

const B := preload("res://scripts/build.gd")
const Mokki := preload("res://scripts/mokki.gd")

## Sängyt mökin kehyksessä [x0, x1, v0, v1], pää x0- tai v-päässä (head: suunta paikallisesti).
const BEDS := [[-2.25, -0.35, 1.35, 2.25, Vector2(-1, 0)], [0.35, 2.25, 1.35, 2.25, Vector2(1, 0)],
	[-2.25, -1.35, -2.2, -0.3, Vector2(0, -1)]]

var cam: Camera3D
var _t := 0.0
var _seals: Array[Node3D] = []
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
	for k in BEDS.size():
		_bed(BEDS[k], k)
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	add_child(cam)
	_cam_a = _p(2.05, -2.1, 1.85)
	_cam_b = _p(1.2, -1.2, 1.55)
	_look = _p(-0.7, 1.1, 0.45)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 1.6
	lamp.omni_range = 5.5
	lamp.position = _p(-0.1, 0.2, 2.0)
	add_child(lamp)
	var window := OmniLight3D.new()  # iltapäivän valo järven puoleisista ikkunoista
	window.light_color = Color(0.85, 0.9, 1.0)
	window.light_energy = 0.8
	window.omni_range = 4.0
	window.position = _p(0.0, 2.3, 1.4)
	add_child(window)


## Paikallinen piste mökin kehyksestä (x, v, korkeus lattiasta).
static func _p(x: float, v: float, y: float) -> Vector3:
	return Vector3(x, y, -v)


func _box(size: Vector3, at: Vector3, col: Color, rot := Basis()) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = B.boxm(size)
	mi.material_override = B.mat(col)
	mi.transform = Transform3D(rot, at)
	add_child(mi)
	return mi


func _ball(r: float, at: Vector3, scale_: Vector3, col: Color, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = B.sphere(r, 14)
	mi.material_override = B.mat(col)
	mi.position = at
	mi.scale = scale_
	(parent if parent != null else self).add_child(mi)
	return mi


## Lattia, seinäpaneelit sisäpuolelle, räsymatto, yöpöytä ja lamppu.
func _build_room() -> void:
	var hx := Mokki.CABIN_HX - 0.2
	var hv := Mokki.CABIN_HV - 0.2
	_box(Vector3(hx * 2.0, 0.02, hv * 2.0), _p(0, 0, 0.01), Color(0.62, 0.48, 0.32))
	var panel := Color(0.78, 0.66, 0.48)
	for s: float in [-1.0, 1.0]:
		_box(Vector3(hx * 2.0, 2.3, 0.02), _p(0, s * (hv - 0.01), 1.15), panel)
		_box(Vector3(0.02, 2.3, hv * 2.0), _p(s * (hx - 0.01), 0, 1.15), panel)
	_box(Vector3(hx * 2.0, 0.02, hv * 2.0), _p(0, 0, 2.33), Color(0.86, 0.8, 0.68))  # sisäkatto
	# Räsymatto raidoittain.
	var stripes := [Color(0.7, 0.2, 0.15), Color(0.2, 0.35, 0.6), Color(0.85, 0.8, 0.6), Color(0.3, 0.5, 0.3)]
	for k in 8:
		_box(Vector3(1.6, 0.012, 0.14), _p(0.0, -0.9 + k * 0.14, 0.025), stripes[k % stripes.size()])
	# Yöpöytä, lamppu ja kahvimuki sänkyjen välissä.
	_box(Vector3(0.5, 0.5, 0.4), _p(0.0, 1.8, 0.25), Color(0.5, 0.36, 0.22))
	var lampb := MeshInstance3D.new()
	lampb.mesh = B.cyl(0.05, 0.09, 0.3, 12)
	lampb.material_override = B.mat(Color(0.3, 0.3, 0.32))
	lampb.position = _p(-0.1, 1.85, 0.65)
	add_child(lampb)
	var shade := MeshInstance3D.new()
	shade.mesh = B.cyl(0.08, 0.16, 0.18, 14)
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(1.0, 0.9, 0.7)
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.8, 0.5)
	sm.emission_energy_multiplier = 1.5
	shade.material_override = sm
	shade.position = _p(-0.1, 1.85, 0.88)
	add_child(shade)
	var mug := MeshInstance3D.new()
	mug.mesh = B.cyl(0.04, 0.035, 0.09, 10)
	mug.material_override = B.mat(Color(0.9, 0.9, 0.88))
	mug.position = _p(0.12, 1.75, 0.55)
	add_child(mug)


## Sänky: puurunko, patja, tyyny ja ruudullinen peitto; norppa nukkumassa peiton alla.
func _bed(r: Array, k: int) -> void:
	var c := _p((r[0] + r[1]) * 0.5, (r[2] + r[3]) * 0.5, 0.0)
	var w: float = r[1] - r[0]
	var d: float = r[3] - r[2]
	var head: Vector2 = r[4]
	_box(Vector3(w, 0.32, d), c + Vector3.UP * 0.16, Color(0.55, 0.4, 0.26))
	_box(Vector3(w - 0.08, 0.14, d - 0.08), c + Vector3.UP * 0.39, Color(0.92, 0.92, 0.9))
	# Pituussuunta: head on x- tai v-suuntainen.
	var along := Vector3(head.x, 0, -head.y)
	var length := w if absf(head.x) > 0.0 else d
	var across := Vector3.UP.cross(along).normalized()
	var pillow := c + along * (length * 0.5 - 0.25) + Vector3.UP * 0.5
	_box(Vector3(0.45, 0.1, 0.32) if absf(head.y) > 0.0 else Vector3(0.32, 0.1, 0.45), pillow, Color(0.95, 0.95, 0.97))
	var seal := _seal(k)
	seal.position = c + Vector3.UP * 0.62 + along * 0.05
	seal.basis = Basis.looking_at(along) * Basis(Vector3.BACK, 0.35 if k % 2 == 0 else -0.35)  # pää tyynylle, kyljellään
	add_child(seal)
	_seals.append(seal)
	# Peitto norpan takaosan päällä.
	var plaid: Color = [Color(0.65, 0.12, 0.1), Color(0.15, 0.3, 0.55), Color(0.2, 0.42, 0.25)][k]
	var blanket := _box(Vector3(w - 0.05, 0.08, d - 0.05) * Vector3(1.0 if absf(head.y) > 0.0 else 0.62, 1.0, 0.62 if absf(head.y) > 0.0 else 1.0),
		c - along * (length * 0.18) + Vector3.UP * 0.66, plaid)
	blanket.scale = Vector3(1.04, 1.0, 1.04)
	var z := Label3D.new()
	z.text = "Z"
	z.font_size = 64
	z.pixel_size = 0.004
	z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	z.modulate = Color(1, 1, 1, 0.9)
	z.outline_size = 12
	z.set_meta("base", c + along * (length * 0.5 - 0.2) + Vector3.UP * 1.0 + across * 0.1)
	z.set_meta("phase", k * 1.3)
	add_child(z)
	_zzz.append(z)


## Norppa: harmaa pyöreä vartalo vaaleine rengaskuvioineen, pää, kuono viiksineen, suljetut silmät ja räpylät.
## Paikallisesti pää -z-suuntaan.
func _seal(k: int) -> Node3D:
	var n := Node3D.new()
	var grey := Color(0.36, 0.38, 0.42).lerp(Color(0.46, 0.47, 0.5), k * 0.4)
	var body := _ball(0.28, Vector3(0, 0, 0.1), Vector3(1.0, 0.8, 2.1), grey, n)
	body.name = "Body"
	var ring := Color(0.62, 0.63, 0.66)
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + k
	for j in 9:
		var t := TorusMesh.new()
		t.inner_radius = 0.025
		t.outer_radius = 0.045
		t.rings = 10
		t.ring_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = t
		mi.material_override = B.mat(ring)
		var a := rng.randf_range(-1.0, 1.0)
		mi.position = Vector3(sin(a) * 0.22, cos(a) * 0.2, rng.randf_range(-0.35, 0.55))
		mi.basis = Basis.looking_at(mi.position.normalized()) * Basis(Vector3.RIGHT, PI * 0.5)
		n.add_child(mi)
	_ball(0.17, Vector3(0, 0.06, -0.55), Vector3(1.0, 0.9, 1.1), grey, n)  # pää
	_ball(0.09, Vector3(0, 0.02, -0.72), Vector3(1.1, 0.8, 1.0), grey.lightened(0.1), n)  # kuono
	_ball(0.025, Vector3(0, 0.05, -0.8), Vector3.ONE, Color(0.08, 0.08, 0.09), n)  # nenä
	for s: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()  # suljettu silmä: tumma viiva
		eye.mesh = B.boxm(Vector3(0.05, 0.008, 0.01))
		eye.material_override = B.mat(Color(0.05, 0.05, 0.06))
		eye.position = Vector3(s * 0.07, 0.13, -0.66)
		eye.rotation.z = s * 0.2
		n.add_child(eye)
		for w in 3:
			var wh := MeshInstance3D.new()
			wh.mesh = B.cyl(0.002, 0.002, 0.14, 4)
			wh.material_override = B.mat(Color(0.9, 0.9, 0.88))
			wh.position = Vector3(s * 0.1, 0.0 + w * 0.015, -0.74)
			wh.rotation = Vector3(0, 0, s * (1.35 + w * 0.1))
			n.add_child(wh)
		_ball(0.1, Vector3(s * 0.22, -0.12, -0.25), Vector3(0.35, 0.25, 1.0), grey.darkened(0.15), n)  # etuevä
		_ball(0.12, Vector3(s * 0.08, 0.0, 0.62), Vector3(0.9, 0.25, 1.1), grey.darkened(0.2), n)  # takaevä
	return n


func play() -> void:
	visible = true
	_t = 0.0
	cam.current = true


func stop() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var k := smoothstep(0.0, 10.0, _t)
	cam.position = _cam_a.lerp(_cam_b, k)
	cam.look_at(to_global(_look), Vector3.UP)
	# Hengitys: kylki nousee ja laskee, kullakin omassa tahdissaan.
	for i in _seals.size():
		var b := _seals[i].get_node("Body") as Node3D
		var s := 1.0 + sin(_t * 1.6 + i * 1.7) * 0.05
		b.scale = Vector3(1.0 * s, 0.8 * s, 2.1)
	# Kuorsaus: Z nousee ja kasvaa, häipyy ja alkaa alusta.
	for z in _zzz:
		var ph := fmod(_t * 0.45 + float(z.get_meta("phase")), 1.0)
		z.position = (z.get_meta("base") as Vector3) + Vector3(sin(ph * 6.0) * 0.08, ph * 0.7, 0)
		z.modulate.a = sin(ph * PI) * 0.9
		z.font_size = int(40 + ph * 50)
