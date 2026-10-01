extends Node3D
## Oulujärven norpat: pelin juuri. Rakentaa ympäristön (taivas, aurinko), maailman (world.gd), pelaajan
## (on_foot.gd), HUD:n (kompassi, tutka, sijainti ja kunto), kartan (M) ja valikot. Aloituspaikka
## 64.432089 N, 26.886448 E, Äpätinniemi, Vaala.

const B := preload("res://scripts/build.gd")
const Terrain := preload("res://scripts/terrain.gd")
const World := preload("res://scripts/world.gd")
const OnFoot := preload("res://scripts/on_foot.gd")
const Ambience := preload("res://scripts/ambience.gd")
const Compass := preload("res://scripts/compass.gd")
const Minimap := preload("res://scripts/minimap.gd")
const MapView := preload("res://scripts/map_view.gd")
const Menu := preload("res://scripts/menu.gd")

## Aloituspisteen maantieteelliset koordinaatit ja metrit astetta kohden (GRS80, 64,43° N): HUD:n sijainti.
const START_LAT := 64.432089
const START_LON := 26.886448
const M_PER_DEG_LAT := 111483.9
const M_PER_DEG_LON := 48185.5

static var skip_menu := false

var state := "menu"
var world: Node3D
var player: CharacterBody3D
var _env: Environment
var _sun: DirectionalLight3D
var _hud: CanvasLayer
var _place: Label
var _coords: Label
var _fps_label: Label
var _stamina: ProgressBar
var _compass: Control
var _map: Control
var _menu: CanvasLayer
var _start_offset := Vector3.ZERO


func _ready() -> void:
	_setup_input()
	_setup_environment()
	world = World.new()
	add_child(world)
	player = OnFoot.new()
	player.world = world
	add_child(player)
	respawn()
	var amb := Ambience.new()
	amb.player = player
	add_child(amb)
	_build_hud()
	_menu = Menu.new()
	_menu.game = self
	add_child(_menu)
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	if skip_menu:
		skip_menu = false
		_start_play()
	else:
		_menu.open_main()


func _start_play() -> void:
	state = "play"
	_hud.visible = true
	player.activate_camera()


## Valikon kutsu, kun alkuvalikko suljetaan.
func start_position() -> Vector3:
	return world.start_position()


func map_sources() -> Array:
	return world.sources()


func map_open() -> bool:
	return _map.visible


## Pelaaja aloituspaikalle rannalle, katse järvelle (pohjoiseen).
func respawn() -> void:
	var s: Vector3 = world.start_position()
	player.global_position = s + Vector3(0, 0.2, 0)
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	player.activate_camera()


func _process(_delta: float) -> void:
	if state == "menu" and not _menu.visible:
		_start_play()
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		RenderingServer.global_shader_parameter_set("lod_eye", cam.global_position)
	if world.trees != null:
		world.trees.update_around(player.global_position)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state != "play" or get_tree().paused:
		return
	if event.is_action_pressed("map"):
		_map.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		respawn()


# --- Syöte, ympäristö ja asetukset ----------------------------------------------------------------------------

func _setup_input() -> void:
	_add_action("forward", [KEY_W, KEY_UP])
	_add_action("back", [KEY_S, KEY_DOWN])
	_add_action("left", [KEY_A, KEY_LEFT])
	_add_action("right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("interact", [KEY_E])
	_add_action("restart", [KEY_R])
	_add_action("map", [KEY_M])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _setup_environment() -> void:
	var sky := Sky.new()
	sky.sky_material = B.shader_mat("res://shaders/sky.gdshader")
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.8
	env.ssil_enabled = true
	env.ssil_intensity = 0.6
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	# Järviusva: kauempana sininen utu, horisontti häipyy taivaaseen.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.72, 0.79, 0.87)
	env.fog_sun_scatter = 0.25
	env.fog_depth_begin = 250.0
	env.fog_depth_end = 5500.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.1
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Kesäillan aurinko luoteesta järven yllä.
	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-28, 140, 0)
	sun.light_color = Color(1.0, 0.92, 0.8)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _apply_settings() -> void:
	var q: int = Settings.get_v("quality")
	_env.ssao_enabled = q >= 2
	_env.ssil_enabled = q >= 3
	_env.glow_enabled = q >= 2
	_sun.shadow_enabled = q >= 1
	_sun.directional_shadow_max_distance = [70.0, 70.0, 120.0, 180.0][q]
	_sun.shadow_blur = [0.5, 0.5, 1.0, 1.5][q]
	_fps_label.visible = Settings.get_v("show_fps")
	get_tree().call_group(B.GUIDES, "set_visible", Settings.get_v("show_guides"))


# --- HUD ------------------------------------------------------------------------------------------------------

func _label(parent: Node, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	parent.add_child(l)
	return l


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.visible = false
	add_child(_hud)
	_map = MapView.new()
	_map.player = player
	_map.world = world
	_compass = Compass.new()
	_compass.player = player
	_compass.paper = _map
	_hud.add_child(_compass)
	var mm := Minimap.new()
	mm.player = player
	mm.map_view = _map
	_hud.add_child(mm)
	_place = _label(_hud, 26)
	_place.position = Vector2(20, 16)
	_coords = _label(_hud, 15)
	_coords.position = Vector2(20, 52)
	_stamina = ProgressBar.new()
	_stamina.show_percentage = false
	_stamina.position = Vector2(20, 82)
	_stamina.size = Vector2(180, 10)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.75, 0.15)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	_stamina.add_theme_stylebox_override("fill", fill)
	_stamina.add_theme_stylebox_override("background", bg)
	_hud.add_child(_stamina)
	_fps_label = _label(_hud, 16)
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -120
	_fps_label.offset_top = 64
	# Kartta omalla kerroksellaan HUD:n päällä.
	var map_layer := CanvasLayer.new()
	map_layer.layer = 30
	map_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(map_layer)
	map_layer.add_child(_map)


func _update_hud() -> void:
	if not _hud.visible:
		return
	var p := player.global_position
	var near: Dictionary = world.nearest_name(Vector2(p.x, p.z))
	var where: String = near.name if near.dist < 450.0 else "Äpätinniemi"
	if player.swimming:
		where += " · uimassa"
	elif player.water_depth > 0.05:
		where += " · kahlaamassa"
	_place.text = where
	var lat := START_LAT - p.z / M_PER_DEG_LAT
	var lon := START_LON + p.x / M_PER_DEG_LON
	var depth := ""
	if player.water_depth > 0.05:
		depth = " · syvyys %.1f m" % player.water_depth
	_coords.text = "%.5f N  %.5f E · %s · %.1f m mpy%s" % [lat, lon, Terrain.SURFACE_NAMES[player.surface],
		Terrain.h(p.x, p.z) + float(world.data.meta.water_level_n2000), depth]
	_stamina.value = player.stamina
	_stamina.modulate = Color(1, 0.4, 0.3) if player.exhausted else Color.WHITE
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
