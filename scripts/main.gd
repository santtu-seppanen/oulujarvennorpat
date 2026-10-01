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
const Sun := preload("res://scripts/sun.gd")
const Porukka := preload("res://scripts/porukka.gd")
const Ai := preload("res://scripts/ai.gd")
const Kumivene := preload("res://scripts/kumivene.gd")
const Mokki := preload("res://scripts/mokki.gd")
const Moninpeli := preload("res://scripts/moninpeli.gd")
## Aloituspaikat pihan kehyksessä (u, v): Santtu teltalla, Marko pöydän ääressä, Jaakko etuterassilla,
## Jukka grillillä.
const SPAWNS := [Vector2(-5.6, 0.6), Vector2(-3.7, -1.0), Vector2(-2.2, 3.6), Vector2(-8.6, -1.6)]

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
var sun: Node
var _hud: CanvasLayer
var _place: Label
var _coords: Label
var _fps_label: Label
var _stamina: ProgressBar
var _compass: Control
var _map: Control
var _menu: CanvasLayer
var _start_offset := Vector3.ZERO
var crew: Array = []
var crew_modes: Array = []  # player | ai | remote (moninpelissä toisen koneen ohjaama)
var player_index := 0
var mp: Node
var boat: CharacterBody3D
var _amb: Node
var _mm: Control
var _clock: Label
var _prompt: Label


func _ready() -> void:
	_setup_input()
	_setup_environment()
	world = World.new()
	add_child(world)
	for i in Porukka.CREW.size():
		var b := OnFoot.new()
		b.world = world
		b.look = Porukka.look(i)
		b.display_name = Porukka.CREW[i].name
		add_child(b)
		Porukka.decorate(i, b.body())
		var w: Vector2 = Mokki.yw(SPAWNS[i].x, SPAWNS[i].y)
		b.global_position = Vector3(w.x, Mokki.DY + 0.1, w.y)
		b.rotation.y = randf() * TAU
		crew.append(b)
		crew_modes.append("")
	player = crew[0]
	boat = Kumivene.new()
	add_child(boat)
	var bw: Vector2 = Mokki.yw(-4.6, 9.0)
	boat.global_position = Vector3(bw.x, 0.0, bw.y)
	boat.rotation.y = atan2(-Mokki.LAKE.x, -Mokki.LAKE.y) + 0.6
	_amb = Ambience.new()
	_amb.player = player
	add_child(_amb)
	_build_hud()
	choose_character(0)
	mp = Moninpeli.new()
	mp.game = self
	add_child(mp)
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


## Pelaaja omalle aloituspaikalleen mökin terassille, katse järvelle.
func respawn() -> void:
	if player.boat != null:
		player.leave_boat()
	player.set_hidden_inside(false)
	player.pose = ""
	var w: Vector2 = Mokki.yw(SPAWNS[player_index].x, SPAWNS[player_index].y)
	player.global_position = Vector3(w.x, Mokki.DY + 0.1, w.y)
	player.rotation.y = atan2(-Mokki.LAKE.x, -Mokki.LAKE.y)
	player.velocity = Vector3.ZERO
	player.activate_camera()


## Pelaaja ohjaa hahmoa i, muita ohjaa tietokone.
func choose_character(i: int) -> void:
	for j in crew.size():
		set_crew_mode(j, "player" if j == i else "ai")
	set_player(i)


## Kuka hahmoa j ohjaa: tämän koneen pelaaja, tietokone tai (moninpelissä) toinen kone.
func set_crew_mode(j: int, mode: String) -> void:
	if crew_modes[j] == mode:
		return
	crew_modes[j] = mode
	var b: CharacterBody3D = crew[j]
	if b.brain != null:
		b.brain.reset()  # vapauttaa istumapaikan
		b.brain = null
	if b.boat != null and mode == "ai":
		b.leave_boat()
	b.set_remote(mode == "remote")
	b.is_player = mode == "player"
	b.controls_enabled = true
	if mode == "player":
		CamCtl.mark_own_body(b.body())
		return
	if mode == "ai":
		b.brain = Ai.new(b, world.mokki, sun, Porukka.CREW[j].name)
	for mi in b.body().find_children("*", "VisualInstance3D", true, false):
		(mi as VisualInstance3D).layers = 1


## Kamera, HUD ja äänet seuraamaan hahmoa i.
func set_player(i: int) -> void:
	player_index = i
	player = crew[i]
	_amb.player = player
	_map.player = player
	_compass.player = player
	_mm.player = player
	player.activate_camera()


func _process(_delta: float) -> void:
	if state == "menu" and not _menu.visible:
		_start_play()
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		RenderingServer.global_shader_parameter_set("lod_eye", cam.global_position)
	if world.trees != null:
		world.trees.update_around(player.global_position)
	if world.mokki != null:
		world.mokki.set_lamp(1.0 - smoothstep(-5.0, 3.0, sun.altitude))
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if state != "play" or get_tree().paused:
		return
	if event.is_action_pressed("map"):
		_map.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		respawn()
	elif event.is_action_pressed("interact"):
		if player.boat != null:
			player.leave_boat()
		elif _near_boat():
			player.enter_boat(boat)


func _near_boat() -> bool:
	return boat.rower == null and player.global_position.distance_to(boat.global_position) < 2.6 \
		and not player.hidden_inside


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
	var sky_mat := B.shader_mat("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
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
	# Aurinko oikeassa paikassa pelin päivämäärän ja kellonajan mukaan (sun.gd).
	var light := DirectionalLight3D.new()
	_sun = light
	light.shadow_enabled = true
	light.shadow_blur = 1.5
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_max_distance = 180.0
	light.directional_shadow_blend_splits = true
	add_child(light)
	sun = Sun.new()
	sun.light = light
	sun.env = env
	sun.sky_mat = sky_mat
	add_child(sun)


func _apply_settings() -> void:
	var q: int = Settings.get_v("quality")
	_env.ssao_enabled = q >= 2
	_env.ssil_enabled = q >= 3
	_env.glow_enabled = q >= 2
	sun.shadows_allowed = q >= 1
	sun.max_shadow = [70.0, 70.0, 120.0, 180.0][q]
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
	_mm = mm
	_place = _label(_hud, 26)
	_place.position = Vector2(20, 16)
	_coords = _label(_hud, 15)
	_coords.position = Vector2(20, 52)
	_clock = _label(_hud, 17)
	_clock.position = Vector2(20, 100)
	_prompt = _label(_hud, 22)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = -90
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	if player.boat != null:
		where += " · soutamassa"
	elif player.swimming:
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
	var day: Dictionary = sun.today()
	_clock.text = "%s · %s · aurinko laskee %s, nousee %s%s" % [Porukka.CREW[player_index].name, sun.clock_text(),
		day.set, day.rise, "  ▶▶ (T)" if sun.fast else ""]
	if mp.online():
		_clock.text += "\nMoninpeli: huone %s · %d pelaajaa" % [mp.room(), mp.players()]
	if player.boat != null:
		_prompt.text = "W/S soutaa · A/D kääntää · E nouse veneestä"
	elif _near_boat():
		_prompt.text = "E: nouse kumiveneeseen"
	else:
		_prompt.text = ""
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
