extends Node3D
## Päikkäreiden välianimaatio ylämökin sisältä: kamera katsoo ovelta mökin sisään kohti järven puoleista ikkunaa,
## josta näkyy järvimaisema. Oven oikealla puolella on parisänky ja vasemmalla vuodesohva. Porukan omat hahmot
## (Santtu, Marko ja Jaakko omine ulkonäköineen; Jukka ei nuku päikkäreitä) nukkuvat selällään ruudullisten
## untuvapeittojen alla, rinta nousee ja laskee, ja kuorsaus nousee Z-kirjaimina. Kamera liukuu hitaasti ovelta
## sisemmäs. Sisätila on mökin pohjan sisällä ja näkyy vain välianimaation ajan (main.gd: _nap ja _wake);
## hahmot rakennetaan vasta ensimmäisellä kerralla.
## Kamera kulkee viiden kuvan läpi: ovelta sisään, alas sänkyjen väliin nukkujien kasvoihin ja lopuksi ikkunalle.
## Yöversio (oodin jälkeen, main.gd go_to_bed): yöpöydän lamppu sammuu kesken kuvan ja huone jää kuutamon varaan.

const B := preload("res://scripts/build.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Looks := preload("res://scripts/looks.gd")
const Porukka := preload("res://scripts/porukka.gd")

## Huonekalut mökin kehyksessä (x pitkin järven puoleista seinää, v järvelle), ovelta katsottuna:
## parisänky oikealla (+x), vuodesohva vasemmalla (-x); pääty metsän puoleista seinää (ovea) vasten.
const DOUBLE := [0.6, 1.9, -0.25, 1.8]  # [x0, x1, v0, v1]; pääty ikkunaseinää vasten, oven edusta vapaa
const SOFA := [-1.85, -0.85, -1.75, 0.3]
## Ikkuna järven puoleisessa päädyssä (mokki.gd _cabin): x-väli ja korkeus lattiasta.
const WAINSCOT := 1.0  # vaaleansinisen puolipaneelin korkeus
const WINDOW := [-0.65, 0.65, 0.85, 1.9]

var cam: Camera3D
var _t := 0.0
var sleepers: Array[Node3D] = []  # nukkujien hahmot (character.gd)
var _slots: Array = []  # nukkumapaikat: [jalkopään paikka, suunta päähän]
var _zzz: Array[Label3D] = []
var _keys: Array = []  # kameran kuvat: [aika 0..1, paikka, katsekohde]
var _len := 10.0
var _night := false
var _lamp: OmniLight3D
var _window_light: OmniLight3D
var _shade_mat: StandardMaterial3D
var _lamp_off := false
var _view: SubViewport
var _view_cam: Camera3D
var _jukka_root: Node3D  # Jukan patja ja nukkuja: vain yöllä
var _jukka_ch: Node3D


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
	_mattress()
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.05
	add_child(cam)
	# Rauhallinen panorointi sekä päivällä että yöllä: sama alku ovelta, sitten hidas katse sängystä sohvaan,
	# lattialle ja lopuksi ikkunalle (viimeinen käännös pitkä ja loiva).
	_keys = [
		[0.0, _p(0.85, -1.55, 1.85), _p(0.1, 1.8, 0.95)],  # ovelta koko huone
		[0.25, _p(0.3, -0.9, 1.55), _p(0.0, 1.8, 0.9)],
		[0.45, _p(0.25, -0.8, 1.5), _p(1.3, 1.3, 0.6)],  # parisänky
		[0.62, _p(0.15, -0.7, 1.5), _p(-1.2, -1.3, 0.5)],  # vuodesohva
		[0.78, _p(0.1, -0.5, 1.45), _p(-0.2, 0.2, 0.45)],  # lattia ja Jukan paikka
		[1.0, _p(0.05, -0.3, 1.45), _p(0.0, 1.8, 1.4)],  # lopuksi ikkuna
	]
	_lamp = OmniLight3D.new()
	_lamp.light_color = Color(1.0, 0.8, 0.55)
	_lamp.light_energy = 1.0
	_lamp.omni_range = 4.5
	_lamp.position = _p(0.3, 1.5, 1.3)
	add_child(_lamp)
	_build_view()
	_window_light = OmniLight3D.new()  # päivänvalo (yöllä kuutamo) järven puoleisesta ikkunasta
	_window_light.light_color = Color(0.9, 0.95, 1.0)
	_window_light.light_energy = 1.4
	_window_light.omni_range = 4.5
	_window_light.position = _p(0.0, Mokki.CABIN_HV - 0.4, 1.4)
	add_child(_window_light)
	process_mode = Node.PROCESS_MODE_DISABLED


## Ikkunan järvinäkymä: pieni SubViewport renderöi pelin oikean maailman kameralla, joka on mökin ulkopuolella
## ikkunan kohdalla katse järvelle (samat valot, taivas ja vesi kuin pelissä), ja kuva on ikkunan aukossa.
func _build_view() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(768, 640)
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	_view_cam = Camera3D.new()
	_view_cam.fov = 62.0
	_view_cam.far = 9000.0
	_view.add_child(_view_cam)
	var w: Array = WINDOW
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w[1] - w[0], w[3] - w[2])
	quad.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _view.get_texture()
	quad.material_override = mat
	quad.position = _p((w[0] + w[1]) * 0.5, Mokki.CABIN_HV - 0.2, (w[2] + w[3]) * 0.5)  # normaali +z = huoneeseen päin
	add_child(quad)


## Näkymäkamera mökin ulkopuolelle ikkunan kohdalle, katse järvelle (kutsutaan, kun välianimaatio alkaa).
func _aim_view() -> void:
	var from := to_global(_p(0.0, Mokki.CABIN_HV + 0.5, 1.45))
	var at := to_global(_p(0.0, Mokki.CABIN_HV + 300.0, 1.0))
	_view_cam.global_position = from
	_view_cam.look_at(at, Vector3.UP)


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
	for k in 14:  # lankkulattia, vuorotellen vaaleampaa ja tummempaa
		var x0 := -hx + k * (hx * 2.0 / 14.0)
		_bx(x0, x0 + hx * 2.0 / 14.0 - 0.012, -hv, hv, 0.0, 0.02, Color(0.45, 0.32, 0.21).lightened(0.05 * (k % 3)))
	var panel := Color(0.93, 0.93, 0.9)  # ylä puoli valkoiseksi maalattua hirttä
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
	_detail_walls(hx, hv)
	# Räsymatto ikkunan edessä.
	var stripes := [Color(0.7, 0.2, 0.15), Color(0.2, 0.35, 0.6), Color(0.85, 0.8, 0.6), Color(0.3, 0.5, 0.3)]
	for k in 10:
		_bx(-0.6, 0.35, 0.45 + k * 0.1, 0.55 + k * 0.1, 0.02, 0.03, stripes[k % stripes.size()])
	# Yöpöytä sänkyjen välissä ja sen lamppu.
	var wood := Color(0.5, 0.36, 0.22)
	_bx(0.05, 0.5, 1.35, 1.78, 0.0, 0.5, wood)
	_bx(0.03, 0.52, 1.33, 1.8, 0.5, 0.53, wood.lightened(0.1))
	_bx(0.1, 0.45, 1.33, 1.35, 0.32, 0.46, wood.darkened(0.2))  # laatikon etuosa
	var lampb := MeshInstance3D.new()
	lampb.mesh = B.cyl(0.04, 0.07, 0.22, 12)
	lampb.material_override = B.mat(Color(0.3, 0.3, 0.32))
	lampb.position = _p(0.3, 1.55, 0.64)
	add_child(lampb)
	var shade := MeshInstance3D.new()
	shade.mesh = B.cyl(0.07, 0.14, 0.16, 14)
	_shade_mat = StandardMaterial3D.new()
	_shade_mat.albedo_color = Color(1.0, 0.9, 0.7)
	_shade_mat.emission_enabled = true
	_shade_mat.emission = Color(1.0, 0.8, 0.5)
	_shade_mat.emission_energy_multiplier = 1.4
	shade.material_override = _shade_mat
	shade.position = _p(0.3, 1.55, 0.84)
	add_child(shade)
	var book := Color(0.25, 0.3, 0.5)
	_bx(0.1, 0.25, 1.45, 1.68, 0.53, 0.56, book)  # iltalukemisto
	var mug := MeshInstance3D.new()
	mug.mesh = B.cyl(0.04, 0.035, 0.09, 10)
	mug.material_override = B.mat(Color(0.9, 0.9, 0.88))
	mug.position = _p(-0.45, hv - 0.09, w[2] + 0.045)
	add_child(mug)


## Sisäänkäynnin ovi metsän puoleisessa seinässä (x0..x1): valkoinen karmi, kaksi kehyslaudoitettua paneelia,
## ovenkahva ja varvasportti-kynnys; ovi on raollaan, ja raosta tulee ulkoa päivänvaloa.
func _door(x0: float, x1: float, hv: float) -> void:
	var white := Color(0.96, 0.96, 0.94)
	var leaf := Color(0.55, 0.38, 0.24)
	var v := -hv
	_bx(x0 - 0.06, x0, v, v + 0.07, 0.0, 2.08, white)  # karmi
	_bx(x1, x1 + 0.06, v, v + 0.07, 0.0, 2.08, white)
	_bx(x0 - 0.06, x1 + 0.06, v, v + 0.07, 2.02, 2.08, white)
	_bx(x0, x1, v, v + 0.06, 0.0, 0.025, Color(0.4, 0.3, 0.2))  # kynnys
	_bx(x0, x1, v + 0.01, v + 0.05, 0.025, 2.02, leaf)  # ovilehti
	for k in 2:  # kaksi koholla olevaa paneelia
		var y0 := 0.2 + k * 0.95
		_bx(x0 + 0.1, x1 - 0.1, v + 0.05, v + 0.065, y0, y0 + 0.8, leaf.lightened(0.12))
	_bx(x1 - 0.12, x1 - 0.05, v + 0.05, v + 0.09, 1.0, 1.04, Color(0.75, 0.75, 0.72))  # kahva
	var hook := Color(0.2, 0.2, 0.22)  # vaatenaulakko oven vieressä, takki ja saappaat
	_bx(x1 + 0.2, x1 + 0.9, v, v + 0.03, 1.6, 1.64, Color(0.5, 0.36, 0.22))
	for hx2: float in [x1 + 0.35, x1 + 0.7]:
		_bx(hx2 - 0.01, hx2 + 0.01, v + 0.03, v + 0.07, 1.6, 1.66, hook)
	_bx(x1 + 0.28, x1 + 0.44, v + 0.05, v + 0.12, 0.95, 1.55, Color(0.2, 0.3, 0.2))  # takki
	for bx: float in [x0 + 0.15, x0 + 0.4]:
		_bx(bx, bx + 0.14, v + 0.12, v + 0.4, 0.0, 0.22, Color(0.12, 0.12, 0.14))  # saappaat


## Hirsimäiset vaakalaudat seiniin, kattopalkit, ikkunan kehys ja verhot sekä seinäkoristeet.
func _detail_walls(hx: float, hv: float) -> void:
	# Alapuoli vaaleansininen puolipaneeli (korkeus WAINSCOT), yläpuoli valkoiseksi maalattua hirttä.
	var blue := Color(0.62, 0.78, 0.9)
	var wl: Array = WINDOW
	var dx0: float = Mokki.CABIN_DOOR.x  # ovi metsän puoleisessa seinässä, ikkunaa vastapäätä
	var dx1: float = Mokki.CABIN_DOOR.y
	_bx(-hx, dx0, -hv, -hv + 0.02, 0.0, WAINSCOT, blue)
	_bx(dx1, hx, -hv, -hv + 0.02, 0.0, WAINSCOT, blue)
	_bx(-hx, -hx + 0.02, -hv, hv, 0.0, WAINSCOT, blue)
	_bx(hx - 0.02, hx, -hv, hv, 0.0, WAINSCOT, blue)
	_bx(-hx, wl[0], hv - 0.02, hv, 0.0, WAINSCOT, blue)
	_bx(wl[1], hx, hv - 0.02, hv, 0.0, WAINSCOT, blue)
	_bx(wl[0], wl[1], hv - 0.02, hv, 0.0, wl[2], blue)
	var rail := Color(0.97, 0.97, 0.95)  # paneelin yläreunan lista
	_bx(-hx, dx0, -hv, -hv + 0.04, WAINSCOT, WAINSCOT + 0.04, rail)
	_bx(dx1, hx, -hv, -hv + 0.04, WAINSCOT, WAINSCOT + 0.04, rail)
	_door(dx0, dx1, hv)
	_bx(-hx, -hx + 0.04, -hv, hv, WAINSCOT, WAINSCOT + 0.04, rail)
	_bx(hx - 0.04, hx, -hv, hv, WAINSCOT, WAINSCOT + 0.04, rail)
	var batten := Color(0.8, 0.8, 0.77)  # hirsien saumat maalin alla
	for k in 5:
		var y := WAINSCOT + 0.2 + k * 0.25
		_bx(-hx, hx, -hv, -hv + 0.02, y, y + 0.04, batten)
		_bx(-hx, -hx + 0.02, -hv, hv, y, y + 0.04, batten)
		_bx(hx - 0.02, hx, -hv, hv, y, y + 0.04, batten)
		var w: Array = WINDOW
		if y + 0.04 < w[2] or y > w[3]:
			_bx(-hx, w[0], hv - 0.02, hv, y, y + 0.04, batten)
			_bx(w[1], hx, hv - 0.02, hv, y, y + 0.04, batten)
	var beam := Color(0.42, 0.3, 0.19)
	for v: float in [-1.1, 0.0, 1.1]:
		_bx(-hx, hx, v - 0.07, v + 0.07, 2.16, 2.3, beam)
	# Ikkunan kehys ja ristikarmi sekä vaaleat verhot.
	var w: Array = WINDOW
	var fr := Color(0.95, 0.95, 0.93)
	_bx(w[0] - 0.04, w[0], hv - 0.1, hv, w[2], w[3], fr)
	_bx(w[1], w[1] + 0.04, hv - 0.1, hv, w[2], w[3], fr)
	_bx(w[0], w[1], hv - 0.1, hv, w[3], w[3] + 0.04, fr)
	_bx(-0.02, 0.02, hv - 0.06, hv - 0.04, w[2], w[3], fr)
	_bx(w[0], w[1], hv - 0.06, hv - 0.04, (w[2] + w[3]) * 0.5 - 0.02, (w[2] + w[3]) * 0.5 + 0.02, fr)
	_bx(w[0] - 0.4, w[0] - 0.02, hv - 0.14, hv - 0.06, w[2] - 0.1, w[3] + 0.25, Color(0.92, 0.85, 0.7))
	_bx(w[1] + 0.02, w[1] + 0.4, hv - 0.14, hv - 0.06, w[2] - 0.1, w[3] + 0.25, Color(0.92, 0.85, 0.7))
	_bx(w[0] - 0.45, w[1] + 0.45, hv - 0.16, hv - 0.12, w[3] + 0.22, w[3] + 0.26, beam)  # verhotanko
	# Itäseinällä hylly kirjoineen ja kehystetty kuva, länsiseinällä viiri ja kuva sohvan yllä.
	var shelf := Color(0.5, 0.36, 0.22)
	_bx(hx - 0.2, hx, 0.5, 1.5, 1.2, 1.24, shelf)
	var cols := [Color(0.7, 0.2, 0.15), Color(0.2, 0.4, 0.6), Color(0.85, 0.75, 0.3), Color(0.3, 0.5, 0.3), Color(0.6, 0.4, 0.55)]
	for k in 8:
		_bx(hx - 0.17, hx - 0.03, 0.55 + k * 0.11, 0.63 + k * 0.11, 1.24, 1.24 + 0.16 + (k % 3) * 0.03, cols[k % cols.size()])
	_bx(hx - 0.03, hx, -0.1, 0.4, 1.35, 1.8, Color(0.25, 0.18, 0.12))  # kuvan kehys
	_bx(hx - 0.035, hx - 0.03, -0.05, 0.35, 1.4, 1.75, Color(0.45, 0.62, 0.72))  # järvimaisema
	_bx(hx - 0.04, hx - 0.03, -0.05, 0.35, 1.4, 1.52, Color(0.2, 0.35, 0.2))
	_bx(-hx, -hx + 0.03, -0.5, 0.2, 1.3, 1.9, Color(0.75, 0.15, 0.12))  # viiri
	_bx(-hx + 0.03, -hx + 0.04, -0.4, 0.1, 1.5, 1.7, Color(0.95, 0.9, 0.5))


## Parisänky oven oikealla puolella: puurunko, päätylauta ikkunan puoleista seinää vasten, kaksi tyynyä, yhteinen
## untuvapeitto; kaksi nukkujaa vierekkäin pää järveen päin. Oven edusta jää vapaaksi.
func _double_bed() -> void:
	var r: Array = DOUBLE
	var wood := Color(0.55, 0.4, 0.26)
	_bx(r[0], r[1], r[2], r[3], 0.0, 0.32, wood)
	_bx(r[0] + 0.04, r[1] - 0.04, r[2] + 0.04, r[3] - 0.04, 0.32, 0.46, Color(0.92, 0.92, 0.9))
	_bx(r[0], r[1], r[3] - 0.06, r[3], 0.0, 0.8, wood.darkened(0.1))  # päätylauta (ikkunalaudan alapuolella)
	var length: float = r[3] - r[2]
	for k in 2:
		var x: float = lerpf(r[0], r[1], 0.27 + k * 0.46)
		_bx(x - 0.28, x + 0.28, r[3] - 0.42, r[3] - 0.08, 0.46, 0.57, Color(0.95, 0.95, 0.97))  # tyyny
		_slot(x, r[2] + 0.05, 0.6, length, -1.0)
	_duvet((r[0] + r[1]) * 0.5, r[1] - r[0] + 0.08, r[3], r[2], Color(0.65, 0.12, 0.1), 0.66, true)


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
	_teddy(_p(r[1] - 0.2, r[3] - 0.12, 0.7))


## Jukka nukkuu lattialla (vain yöunilla): ohut makuualusta, pieni tyyny ja vihreä peitto; neljäs nukkumapaikka.
func _mattress() -> void:
	_jukka_root = Node3D.new()
	add_child(_jukka_root)
	var n0 := get_child_count()
	_bx(-0.35, 0.35, -1.25, 0.55, 0.0, 0.03, Color(0.35, 0.4, 0.55))
	_bx(-0.2, 0.2, -1.2, -0.9, 0.03, 0.1, Color(0.95, 0.95, 0.97))
	_slot(0.0, 0.5, 0.17, 1.7)
	_duvet(0.0, 0.72, -1.25, 0.55, Color(0.2, 0.5, 0.35), 0.23)
	while get_child_count() > n0:
		get_child(n0).reparent(_jukka_root, false)
	_jukka_root.visible = false


## Pehmo sohvan jalkopäässä.
func _teddy(at: Vector3) -> void:
	var fur := Color(0.62, 0.42, 0.25)
	for part: Array in [[Vector3.ZERO, 0.12], [Vector3(0, 0.15, 0), 0.085], [Vector3(-0.07, 0.22, 0.02), 0.03],
			[Vector3(0.07, 0.22, 0.02), 0.03], [Vector3(0, 0.14, 0.07), 0.035]]:
		var mi := MeshInstance3D.new()
		mi.mesh = B.sphere(float(part[1]))
		mi.material_override = B.mat(fur.lightened(0.15) if part[1] == 0.035 else fur)
		mi.position = at + (part[0] as Vector3)
		add_child(mi)


## Nukkumapaikka: jalkopää (x, v), korkeus ja pituus; pää metsän puoleista seinää kohti. Kuorsaus pään yllä.
func _slot(x: float, v_foot: float, y: float, length: float, hd := 1.0) -> void:
	# hd = 1: pää -v-suuntaan (paikallisesti +z, metsän puolelle); hd = -1: pää järveen päin.
	_slots.append([_p(x, v_foot, y), Vector3(0, 0, hd)])
	var z := Label3D.new()
	z.text = "Z"
	z.font_size = 64
	z.pixel_size = 0.004
	z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	z.modulate = Color(1, 1, 1, 0.9)
	z.outline_size = 12
	z.set_meta("base", _p(x + 0.1, v_foot - hd * (length - 0.3), y + 0.5))
	z.set_meta("phase", _zzz.size() * 1.3)
	add_child(z)
	_zzz.append(z)


## Pehmeä ruudullinen untuvapeitto jalkopäästä rintaan asti: litistetty kapseli, joka pullistuu nukkujien päällä
## ja valuu reunojen yli; yläreunassa valkoinen lakanan taite.
func _duvet(xc: float, width: float, v_head: float, v_foot: float, col: Color, y := 0.66, flip := false) -> void:
	var hd := -1.0 if flip else 1.0  # pään suunta paikallisessa z:ssä (flip: pää järveen päin, v kasvaa)
	var cover := absf(v_foot - v_head) * 0.56
	var mid := _p(xc, v_foot + (cover * 0.5 if flip else -cover * 0.5), y)
	var duvet := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = width * 0.5
	cap.height = cover + cap.radius
	cap.radial_segments = 28
	cap.rings = 8
	duvet.mesh = cap
	duvet.material_override = _plaid(col)
	# Kapselin akseli (y) pituussuuntaan (paikallinen z), leveys x:ään, paksuus litistettynä ylös.
	duvet.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN * 0.3), mid)
	add_child(duvet)
	var fold := MeshInstance3D.new()
	var fc := CapsuleMesh.new()
	fc.radius = 0.07
	fc.height = width + 0.05
	fold.mesh = fc
	fold.material_override = B.mat(Color(0.95, 0.95, 0.97))
	fold.transform = Transform3D(Basis(Vector3.UP * 0.6, Vector3.RIGHT, Vector3.BACK).orthonormalized().scaled(Vector3.ONE),
		mid + Vector3(0, 0.12, hd * cover * 0.5))
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


## Porukan nukkujat paikoilleen: sängyissä ja sohvalla Santtu, Marko ja Jaakko; Jukka (ei päikkäreitä) nukkuu yöllä
## lattialla. Selällään pää tyynyllä.
func _build_sleepers() -> void:
	var k := 0
	for i in Porukka.CREW.size():
		var jukka: bool = Porukka.CREW[i].name == "Jukka"
		if not jukka and k >= 3:
			continue
		var slot: Array = _slots[3 if jukka else k]
		if not jukka:
			k += 1
		var holder := Node3D.new()
		holder.position = slot[0]
		holder.basis = Basis.looking_at(-(slot[1] as Vector3))  # paikallinen +z päähän päin
		(_jukka_root if jukka else self).add_child(holder)
		var ch := Looks.make(holder, Porukka.look(i))
		Porukka.decorate(i, ch)
		ch.rotation.x = PI * 0.5  # selällään, kasvot ylös
		ch.play("Idle", 0.0, 0.3)
		if jukka:
			_jukka_ch = ch
		else:
			sleepers.append(ch)


func play(night := false, secs := 10.0) -> void:
	if sleepers.is_empty():
		_build_sleepers()
	_night = night
	_len = secs
	_jukka_root.visible = night  # Jukka nukkuu vain yöllä
	_lamp_off = false
	_lamp.light_energy = 1.0 if night else 0.0
	_shade_mat.emission_energy_multiplier = 1.4 if night else 0.0
	# Yöllä ikkunasta tulee vain himmeä sinertävä kuutamo.
	_window_light.light_color = Color(0.55, 0.65, 0.95) if night else Color(0.9, 0.95, 1.0)
	_window_light.light_energy = 0.7 if night else 1.4
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	_t = 0.0
	cam.current = true
	_aim_view()
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func stop() -> void:
	visible = false
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	process_mode = Node.PROCESS_MODE_DISABLED  # nukkujien animaatiot seis, kun välianimaatio ei näy


## Kameran paikka ja katse ajanhetkellä u (0..1): pehmeä käyrä kuvien läpi.
func _shot(u: float) -> Array:
	var keys: Array = _keys
	var n := keys.size()
	var i := 0
	while i < n - 2 and u > float(keys[i + 1][0]):
		i += 1
	var a: Array = keys[i]
	var b: Array = keys[i + 1]
	var w := clampf((u - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
	w = w * w * (3.0 - 2.0 * w)
	return [(a[1] as Vector3).lerp(b[1], w), (a[2] as Vector3).lerp(b[2], w)]


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	var sh := _shot(clampf(_t / _len, 0.0, 1.0))
	# Pieni käsivarainen heilunta, jotta kuva ei ole jäykkä.
	var sway := Vector3(sin(_t * 0.7) * 0.015, sin(_t * 1.1) * 0.01, cos(_t * 0.6) * 0.015)
	cam.position = (sh[0] as Vector3) + sway
	cam.look_at(to_global(sh[1]), Vector3.UP)
	# Päivällä lamppu ei pala lainkaan. Yöllä se palaa alussa ja sammuu hitaasti, ja ikkunan kuutamo himmenee
	# koko kohtauksen ajan.
	var u := clampf(_t / _len, 0.0, 1.0)
	var lamp_k := 0.0
	if _night:
		lamp_k = clampf(1.0 - (u - 0.2) / 0.2, 0.0, 1.0)
		if lamp_k <= 0.0 and not _lamp_off:
			_lamp_off = true
			Sfx.play("pickup", -8.0, 0.6)
		_window_light.light_energy = lerpf(0.7, 0.12, smoothstep(0.0, 1.0, u))
	_lamp.light_energy = lamp_k
	_shade_mat.emission_energy_multiplier = 1.4 * lamp_k
	# Hengitys: rinta nousee ja laskee, kullakin omassa tahdissaan.
	for i in sleepers.size():
		sleepers[i].set_override("spine_03", Vector3.RIGHT, sin(_t * 1.6 + i * 1.7) * 0.05)
	if _jukka_ch != null and _night:
		_jukka_ch.set_override("spine_03", Vector3.RIGHT, sin(_t * 1.6 + 5.0) * 0.05)
	# Kuorsaus: Z nousee ja kasvaa, häipyy ja alkaa alusta.
	for z in _zzz:
		var ph := fmod(_t * 0.45 + float(z.get_meta("phase")), 1.0)
		z.position = (z.get_meta("base") as Vector3) + Vector3(sin(ph * 6.0) * 0.08, ph * 0.7, 0)
		z.modulate.a = sin(ph * PI) * 0.9
		z.font_size = int(28 + ph * 34)
