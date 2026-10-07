extends Node3D
## Oulujärven norpat: pelin juuri. Rakentaa ympäristön (taivas, aurinko), maailman (world.gd), pelaajan
## (on_foot.gd), HUD:n (kompassi, tutka, sijainti ja kunto), kartan (M) ja valikot. Aloituspaikka
## 64.432089 N, 26.886448 E, Äpätti, Vaala.

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
const Sauna := preload("res://scripts/sauna.gd")
const Kokkaus := preload("res://scripts/kokkaus.gd")
const Kahvi := preload("res://scripts/kahvi.gd")
const Mustikat := preload("res://scripts/mustikat.gd")
const Paikkarit := preload("res://scripts/paikkarit.gd")
const Korttipeli := preload("res://scripts/korttipeli.gd")
const Chat := preload("res://scripts/chat.gd")
const WcGame := preload("res://scripts/wc_game.gd")
const Rinnepissa := preload("res://scripts/rinnepissa.gd")
const Rantatennis := preload("res://scripts/rantatennis.gd")
const Amerikanpallo := preload("res://scripts/amerikanpallo.gd")
const Tutkimusmatka := preload("res://scripts/tutkimusmatka.gd")
## Aloituspaikat pihan kehyksessä (u, v): Santtu teltalla, Marko pöydän ääressä, Jaakko etuterassilla,
## Jukka grillillä.
const SPAWNS := [Vector2(-6.9, 1.2), Vector2(-4.9, -1.05), Vector2(-2.2, 3.6), Vector2(-8.6, -1.6)]

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
## Alamökin minipeli käynnissä: "" | sauna | kokkaus | kahvi | kortit (vastaava solmu: start, act, stop, prompt).
var activity := ""
var sauna: Node
var kokkaus: Node
var kahvi: Node  # Jukan aamukahvit liedellä (kahvi.gd)
var mustikat: Node3D  # mustikkamättäät metsässä: suihku paranee (mustikat.gd)
var kortit: Node
var chat: Node
var pissa: Node3D  # rinteeseen virtsaaminen pitkospuilla (rinnepissa.gd)
var wc: CanvasLayer = null  # huussin minipeli käynnissä (wc_game.gd)
var tennis: Node3D  # rantatennis ylämökin edessä (rantatennis.gd)
var heittely: Node3D  # amerikkalaisen jalkapallon heittely vedessä (amerikanpallo.gd)
var ballgames: Array = []  # yhteiset pallopelit (pallopeli.gd): tennis ja heittely
var retki: Node3D  # tutkimusmatka kumiveneellä viinakätkölle (tutkimusmatka.gd)
## Päikkärit ylämökissä: jäljellä oleva uniaika ja ruudun pimennys.
const NAP_T := 10.0
var _nap_t := 0.0
var _nap_fx: ColorRect
var _nap_scene: Node3D  # välianimaatio: norpat nukkumassa ylämökissä (paikkarit.gd)
var _nap_day := -1  # päivä, jolloin klo 16 päikkärikutsu on jo tullut
var _coffee_day := -1  # päivä, jolloin Jukka on jo huutanut kahville
var _toast: Label
var _toast_t := 0.0
var _was_fps := false
var _drunk_label: Label
var _drunk_fx: ColorRect
var _was_out := false
## Minipeleissä katsotaan silmistä: lauteilta kiukaalle, hellalla pannuun, pöydässä kortteihin (kallistus).
const ACTIVITY_PITCH := {"sauna": -0.3, "kokkaus": -0.9, "kahvi": -0.9, "kortit": -0.42}
const LOOK_YAW := 1.9  # pöydässä ja lauteilla katse kääntyy näin paljon sivulle (A/D, hiiren oikea nappi)
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
	world.mokki.bodies = crew
	sauna = Sauna.new()
	sauna.game = self
	add_child(sauna)
	kokkaus = Kokkaus.new()
	kokkaus.game = self
	add_child(kokkaus)
	kahvi = Kahvi.new()
	kahvi.game = self
	add_child(kahvi)
	mustikat = Mustikat.new()
	mustikat.game = self
	add_child(mustikat)
	_nap_scene = Paikkarit.new()
	add_child(_nap_scene)
	# Tietokoneen hahmojen puheet (esim. klo 16 "päikkäreille!") kuplina.
	world.mokki.talk.connect(func(who: String, text: String) -> void:
		for j in Porukka.CREW.size():
			if Porukka.CREW[j].name == who:
				chat.ai_say(j, text))
	world.mokki.napped.connect(_coffee_call)
	mp.on("kahvikutsu", func(_d: Dictionary, _from: int) -> void: _coffee_shout())
	kortit = Korttipeli.new()
	kortit.game = self
	add_child(kortit)
	pissa = Rinnepissa.new()
	pissa.game = self
	add_child(pissa)
	tennis = Rantatennis.new()
	tennis.game = self
	add_child(tennis)
	heittely = Amerikanpallo.new()
	heittely.game = self
	add_child(heittely)
	ballgames = [tennis, heittely]
	retki = Tutkimusmatka.new()
	retki.game = self
	add_child(retki)
	chat = Chat.new()
	chat.game = self
	add_child(chat)
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
	end_activity()
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
	end_activity()
	if _nap_t > 0.0:
		_wake()
	if pissa != null and pissa.active:
		pissa.stop()
	for g in ballgames:
		g.stop()
	player_index = i
	player = crew[i]
	_amb.player = player
	_map.player = player
	_compass.player = player
	_mm.player = player
	player.activate_camera()


func _process(delta: float) -> void:
	if state == "menu" and not _menu.visible:
		_start_play()
	# Minipelissä A/D kääntää katsetta (hahmo istuu paikallaan), esim. pöydässä muita pelaajia kohti.
	if activity != "" and not Chat.typing and not get_tree().paused:
		var turn := Input.get_axis("right", "left")
		if turn != 0.0:
			CamCtl.yaw = clampf(CamCtl.yaw + turn * 1.6 * delta, -LOOK_YAW, LOOK_YAW)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		RenderingServer.global_shader_parameter_set("lod_eye", cam.global_position)
		if world.mokki != null:
			world.mokki.update_roofs(cam.global_position, player.global_position + Vector3.UP * 1.5)
	if world.trees != null:
		world.trees.update_around(player.global_position)
	if world.mokki != null:
		world.mokki.set_lamp(1.0 - smoothstep(-5.0, 3.0, sun.altitude))
	if _nap_t > 0.0:
		_nap_t -= delta
		# Häivytys mustaan välianimaation alussa ja lopussa.
		_nap_fx.color.a = 1.0 - minf(1.0, minf((NAP_T - _nap_t) / 1.2, _nap_t / 1.2))
		if _nap_t <= 0.0:
			_wake()
	_nap_call()
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if _nap_t > 0.0 and event.is_action_pressed("interact"):
		_wake()
		return
	if state != "play" or get_tree().paused or wc != null or pissa.active or _nap_t > 0.0:
		return
	if event.is_action_pressed("map"):
		_map.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		respawn()
	elif event.is_action_pressed("interact"):
		if activity != "":
			_activity_node().act()
		elif _ballgame() != null:
			_ballgame().act()
		elif player.boat != null:
			player.leave_boat()
		else:
			var it := _interaction()
			if it.has("cb"):
				it.cb.call()
	elif _ballgame() != null and event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_ballgame().stop()  # F lopettaa pallopelin
	elif activity != "" and (event.is_action_pressed("forward") or event.is_action_pressed("back")):
		end_activity()
	elif activity != "" and event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Vapaalla kursorilla (korttipöytä) hiiren oikea nappi pohjassa katsellaan ympärille.
		CamCtl.yaw = clampf(CamCtl.yaw - event.relative.x * 0.005, -LOOK_YAW, LOOK_YAW)
		CamCtl.pitch = clampf(CamCtl.pitch - event.relative.y * 0.005, -1.1, 0.5)
	elif event.is_action_pressed("drink") and player.boat != null:
		retki.toggle()  # veneessä Q: tutkimusmatka viinakätkölle
	elif event.is_action_pressed("drink") and activity == "" and _near_stash():
		_booze()
	elif event.is_action_pressed("drink") and activity == "" and _can_act() and Mokki.at_outhouse(player.global_position):
		_start_wc("kakkonen")


# --- Kätköt: saunan takana rinteessä, rannan rinteessä (ranta.gd) ja tutkimusmatkan kätkö (tutkimusmatka.gd) ----

func _near_stash() -> bool:
	if player.pose == "Sammunut" or player.boat != null:
		return false
	var s: Vector3 = world.mokki.stash_pos
	var p := player.global_position
	return (Vector2(p.x - s.x, p.z - s.z).length() < 1.5 and p.y > Mokki.DY - 0.3 and p.y < Mokki.DY + 1.2) \
		or _near_beach_stash()


## Metsän kätköt: rannan rinteessä ja tutkimusmatkan kätkö.
func _near_beach_stash() -> bool:
	var s: Vector3 = world.ranta.stash_pos
	var p := player.global_position
	return (Vector2(p.x - s.x, p.z - s.z).length() < 1.6 and absf(p.y - s.y) < 1.5) or retki.near_stash(p)


## Viinakätköosoitin: kompassin keltainen merkki lähimpään kätköön (saunan takana, rannan rinteessä tai
## tutkimusmatkan kätkö); tutkimusmatkalla aina matkan kätköön.
func _point_to_stash(p: Vector3) -> void:
	var best := Vector2.INF
	var list: Array = [retki.stash_pos] if retki.active else [world.mokki.stash_pos, world.ranta.stash_pos, retki.stash_pos]
	for s: Vector3 in list:
		var q := Vector2(s.x, s.z)
		if q.distance_to(Vector2(p.x, p.z)) < best.distance_to(Vector2(p.x, p.z)):
			best = q
	_compass.cache = best
	_compass.cache_text = "kätkö %d m" % roundi(best.distance_to(Vector2(p.x, p.z)))


func _beer() -> void:
	player.drink(0.22)
	toast(["Kylmä olut kätköstä. Kippis!", "Tsuih! Taas yksi kylmä.", "Olutta riittää – kätkö ei tyhjene."][randi() % 3]
		+ " (%d. huikka, %.1f ‰)" % [player.drinks, player.promille])


func _booze() -> void:
	player.drink(0.45)
	toast(["Huikka viinaa. Polttaa!", "Viinapullo kiertää – ja kirvelee.", "Hyi saakeli, mutta hyvää."][randi() % 3]
		+ " (%d. huikka, %.1f ‰)" % [player.drinks, player.promille])


static func drunk_text(pm: float) -> String:
	if pm < 0.3:
		return ""
	if pm < 0.8:
		return "hiprakassa"
	if pm < 1.5:
		return "humalassa"
	if pm < 2.2:
		return "kännissä"
	if pm < 3.0:
		return "kaatokännissä"
	if pm < 3.6:
		return "tolkuttomassa humalassa – kävely ei onnistu"
	return "sammunut"


## Kourallinen mustikoita: suihku pitenee (rinnepissa.gd), Markolla erikoiskyvyn päälle.
func _eat_berries(k: int) -> void:
	mustikat.eat(k, player_index)
	var n: int = mustikat.eaten[player_index]
	var t := "Mustikoita! Suihku paranee (%d/%d kourallista)." % [n, Mustikat.MAX]
	if Porukka.CREW[player_index].name != "Marko" and n >= Mustikat.MAX:
		t = "Mustikkavoimaa täynnä – Markon kaareen ei silti ylletä."
	toast(t, 3.0)


## Pallopeli, jossa oma pelaaja on mukana (tai null).
func _ballgame() -> Node3D:
	for g in ballgames:
		if g.active:
			return g
	return null


# --- Päikkärit ylämökissä -------------------------------------------------------------------------------------

## Päikkärien jälkeen Jukka huutaa porukan kahville (kerran päivässä): kupit alamökin keittiön pöydässä.
## Huuto lähtee kaikille koneille (viesti "kahvikutsu"); kupit kulkevat kahvi.gd:n viestillä.
func _coffee_call() -> void:
	var j := _coffee_shout()
	if j < 0:
		return
	if crew_modes[j] == "ai" and kahvi.kupit < 4:
		kahvi.add(4 - kahvi.kupit)  # tietokoneen Jukka keitti kahvit päikkärien aikana
	mp.send({"t": "kahvikutsu"})


## Jukan huuto tällä koneella (kerran päivässä): kupla, puhe ja ilmoitus. Palauttaa Jukan indeksin tai -1.
func _coffee_shout() -> int:
	var day: int = sun.local().day
	if _coffee_day == day:
		return -1
	_coffee_day = day
	var j := -1
	for i in Porukka.CREW.size():
		if Porukka.CREW[i].name == "Jukka":
			j = i
	if j < 0:
		return -1
	chat.show_message(j, ["Kahville! Pannukahvit on valmiina.", "Herätys, kahvit on pöydässä!", "Kaffelle, pojat!"][day % 3])
	if j != player_index:
		toast("Jukka huutaa kahville: kupit alamökin keittiön pöydässä.", 4.0)
	return j


## Klo 16 aikoihin porukka lähtee päikkäreille (ai.gd): kerran päivässä ilmoitus pelaajalle.
func _nap_call() -> void:
	var lt: Dictionary = sun.local()
	if lt.hour == 16 and lt.minute < 10 and _nap_day != lt.day:
		_nap_day = lt.day
		var t := "Kello on neljä: porukka lähtee päikkäreille ylämökkiin."
		if Porukka.CREW[player_index].name == "Jukka":
			t += " Jukka keittää sillä aikaa kahvit."
		else:
			t += " E ylämökin ovella."
		toast(t, 5.0)


## Ylämökkiin nukkumaan: hahmo sisään, välianimaatio mökin sisältä (norpat nukkumassa). Herätessä kunto on
## täynnä ja humala laskenut.
func _nap() -> void:
	end_activity()
	player.controls_enabled = false
	player.velocity = Vector3.ZERO
	player.set_hidden_inside(true)
	Sfx.play("door", -6.0)
	if _nap_fx == null:
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_nap_fx = ColorRect.new()
		_nap_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
		_nap_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_nap_fx.color = Color(0.02, 0.02, 0.05, 0.0)
		layer.add_child(_nap_fx)
		var l := _label(layer, 30)
		l.text = "Zzz… päikkärit ylämökissä (E: herää)"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 40)
		_nap_fx.set_meta("label", l)
	_nap_fx.visible = true
	(_nap_fx.get_meta("label") as Label).visible = true
	_nap_fx.color.a = 1.0
	_hud.visible = false
	_nap_scene.play()
	_nap_t = NAP_T


func _wake() -> void:
	_nap_t = 0.0
	_nap_fx.visible = false
	(_nap_fx.get_meta("label") as Label).visible = false
	_nap_scene.stop()
	_hud.visible = true
	player.activate_camera()
	var d := Mokki.cabin_door()
	player.global_position = d + Vector3.UP * 0.05
	player.rotation.y = atan2(Mokki.CABIN_LAKE.x, Mokki.CABIN_LAKE.y)  # ovelta metsään päin
	player.velocity = Vector3.ZERO
	player.set_hidden_inside(false)
	player.controls_enabled = true
	player.stamina = 100.0
	player.exhausted = false
	player.promille = maxf(0.0, player.promille - 1.2)
	Sfx.play("door_close", -6.0)
	toast("Heräsit päikkäreiltä virkeänä. Kunto täynnä" + (", ja humala on laskenut." if player.drinks > 0 else "."), 3.5)
	_coffee_call()


# --- Huussi ja rinne ---------------------------------------------------------------------------------------------

func _can_act() -> bool:
	return player.boat == null and not player.hidden_inside and not player.swimming \
		and player.pose != "Sammunut" and player.pose != "Ryomii"


## Huussiin: hahmo piiloon huussin sisään ja minipeli ruudulle (ykkönen tai kakkonen).
func _start_wc(mode: String) -> void:
	end_activity()
	player.controls_enabled = false
	player.set_hidden_inside(true)
	_hud.visible = false
	Sfx.play("door", -6.0)
	wc = WcGame.new()
	wc.mode = mode
	wc.drunk = player.drunk()
	wc.finished.connect(_wc_result)
	add_child(wc)


## Huussista ulos oven eteen pitkospuille, ja tulos: sotkusta Santtu huomauttaa.
func _wc_result(mode: String, r: Dictionary) -> void:
	wc = null
	_hud.visible = true
	var d := Mokki.outhouse_door()
	player.global_position = d + Vector3.UP * 0.05
	var out := Mokki.yw(Mokki.DUCKBOARDS[1].x, Mokki.DUCKBOARDS[1].y) - Vector2(d.x, d.z)
	player.rotation.y = atan2(-out.x, -out.y)
	player.set_hidden_inside(false)
	player.controls_enabled = true
	var santtu: bool = Porukka.CREW[player_index].name == "Santtu"
	if mode == "ykkonen":
		if not r.done:
			toast("Jäi kesken. Hätä palaa kyllä.", 2.5)
		elif r.accuracy >= 0.85:
			toast("Napakymppi! Ei tippaakaan ohi.", 3.0)
		elif r.accuracy >= 0.6:
			toast("Melkein kaikki reikään. Pari tippaa penkille.", 3.0)
		elif santtu:
			toast("Penkki lainehtii! Pyyhitään äkkiä, ennen kuin vieraat huomaa.", 4.0)
		else:
			toast("Penkki lainehtii! Santtu: \"Superhost huomaa kaiken. Penkki pyyhitään!\"", 4.0)
		return
	if not r.done:
		toast("Jäi kesken. Tuntuu vielä.", 2.5)
		return
	var lines: Array[String] = []
	if r.hard > 0:
		lines.append("Liian kovaa ponnistettu, peräpukamat muistuttaa.")
	if r.sheets < WcGame.PAPER_OK.x:
		lines.append("Säästeliäs paperinkäyttö. Toivottavasti riitti.")
	else:
		lines.append("Siistiä työtä. Huussin luukku kiinni.")
	toast(" ".join(lines), 3.5)


# --- Alamökin minipelit ---------------------------------------------------------------------------------------

func _activity_node() -> Node:
	return {"sauna": sauna, "kokkaus": kokkaus, "kahvi": kahvi, "kortit": kortit}.get(activity, null)


func start_activity(a: String) -> void:
	end_activity()
	activity = a
	if not _activity_node().start():
		activity = ""
		return
	player.controls_enabled = false
	_was_fps = CamCtl.fps
	CamCtl.fps = true
	CamCtl.yaw = 0.0
	CamCtl.pitch = ACTIVITY_PITCH[a]


func end_activity(why := "") -> void:
	if activity == "":
		return
	var n := _activity_node()
	activity = ""
	player.controls_enabled = true
	CamCtl.fps = _was_fps
	CamCtl.pitch = 0.0 if _was_fps else -0.12
	n.stop(why)


## Lyhyt ilmoitus ruudun alareunaan.
func toast(text: String, secs := 3.0) -> void:
	_toast.text = text
	_toast_t = secs


## Mitä E tekee tässä kohdassa: {text, cb} (cb puuttuu, jos pelkkä vihje).
func _interaction() -> Dictionary:
	if _near_boat():
		return {"text": "E: nouse kumiveneeseen", "cb": func() -> void: player.enter_boat(boat)}
	if player.hidden_inside or player.swimming or player.pose == "Sammunut":
		return {}
	if _near_stash():
		if _near_beach_stash():
			return {"text": "Viinakätkö! E: olut · Q: huikka viinaa", "cb": _beer}
		return {"text": "E: kylmä olut · Q: huikka viinaa (ehtymätön kätkö)", "cb": _beer}
	if player.pose == "Ryomii":
		return {}
	if Mokki.at_outhouse(player.global_position):
		return {"text": "E: huussiin, ykkönen · Q: kakkonen", "cb": func() -> void: _start_wc("ykkonen")}
	if Mokki.at_pee_spot(player.global_position):
		var t := "E: virtsaa rinteeseen"
		if Porukka.CREW[player_index].name == "Marko":
			t += " (erikoiskyky: suuri kaari 5 m)"
		return {"text": t, "cb": pissa.start}
	var bush: int = mustikat.near(player.global_position)
	if bush >= 0:
		return {"text": "E: syö mustikoita (suihku paranee)", "cb": func() -> void: _eat_berries(bush)}
	if Mokki.at_cabin_door(player.global_position):
		if Porukka.CREW[player_index].name == "Jukka":
			return {"text": "Jukka ei nuku päikkäreitä – aamukahvit keitetään alamökin liedellä"}
		if not Ai.nap_hours(sun):
			return {"text": "Päikkärit nukutaan klo 15–18 (nyt klo %02d.%02d)" % [sun.local().hour, sun.local().minute]}
		return {"text": "E: päikkärit ylämökissä", "cb": _nap}
	if tennis.can_start(player.global_position) and player.boat == null:
		return {"text": "E: rantatennis koko porukalla (ennätys %d lyöntiä)" % tennis.record, "cb": tennis.start}
	if heittely.can_start(player.global_position) and player.boat == null:
		return {"text": "E: amerikkalaisen jalkapallon heittely koko porukalla (ennätys %d heittoa)" % heittely.record,
			"cb": heittely.start}
	if Mokki.at_woodshed(player.global_position):
		return {"text": "E: halot syliin saunan kiukaaseen (sauna %d °C, %s)" % [roundi(sauna.temp), sauna.fire_text()],
			"cb": func() -> void: sauna.take_logs(player_index)}
	var m: Node3D = world.mokki
	match Mokki.room_at(player.global_position):
		"loylyhuone":
			var held: int = sauna.carried.get(player_index, 0)
			var kp: Vector3 = m.kiuas_pos
			if held > 0 and Vector2(player.global_position.x - kp.x, player.global_position.z - kp.z).length() < 1.3:
				return {"text": "E: halko kiukaaseen (sylissä %d · %s)" % [held, sauna.fire_text()],
					"cb": func() -> void: sauna.add_log(player_index)}
			return {"text": "E: istu lauteille (sauna %d °C, %s)" % [roundi(sauna.temp), sauna.fire_text()],
				"cb": func() -> void: start_activity("sauna")}
		"keittio":
			if player.global_position.distance_to(m.cook_spot) < 0.75:
				match Porukka.CREW[player_index].name:
					"Marko":
						return {"text": "E: paista pyttipannua", "cb": func() -> void: start_activity("kokkaus")}
					"Jukka":
						return {"text": "E: keitä aamukahvit liedellä", "cb": func() -> void: start_activity("kahvi")}
				return {"text": "Vain Marko osaa tehdä pyttipannua ja Jukka keittää aamukahvit"}
			var t := "E: istu pöytään (ristiseiska)"
			if kokkaus.annokset > 0:
				t += " · pöydässä %d annosta pyttipannua" % kokkaus.annokset
			if kahvi.kupit > 0:
				t += " · %d kuppia kahvia" % kahvi.kupit
			return {"text": t, "cb": func() -> void: start_activity("kortit")}
	return {}


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
	_add_action("drink", [KEY_Q])


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
	# Auringonpaiste: ohut tilavuususva, joka sirottaa auringonvaloa eteenpäin. Puiden latvusten ja rakennusten
	# varjot näkyvät ilmassa valokiiloina, kun katsoo aurinkoa kohti, ja ilta-aurinko hehkuu kultaisena
	# (Forward+; yhteensopivassa grafiikassa ei käytössä).
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0045
	env.volumetric_fog_albedo = Color(1.0, 0.97, 0.9)
	env.volumetric_fog_anisotropy = 0.8
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
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
	light.light_volumetric_fog_energy = 2.2  # valokiilat latvusten välistä
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
	_env.volumetric_fog_enabled = q >= 2  # auringonpaisteen valokiilat
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
	# Viinakätköosoitin: kompassissa lähimmän kätkön suunta ja matka (_update_hud).
	_compass.has_cache = true
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
	_drunk_label = _label(_hud, 15)
	_drunk_label.position = Vector2(210, 76)
	_drunk_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 0
	add_child(fx_layer)
	_drunk_fx = ColorRect.new()
	_drunk_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drunk_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drunk_fx.material = B.shader_mat("res://shaders/humala.gdshader")
	_drunk_fx.visible = false
	fx_layer.add_child(_drunk_fx)
	_toast = _label(_hud, 20)
	_toast.anchor_left = 0.5
	_toast.anchor_right = 0.5
	_toast.anchor_top = 1.0
	_toast.anchor_bottom = 1.0
	_toast.offset_left = -420
	_toast.offset_right = 420
	_toast.offset_top = -60
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
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
	_point_to_stash(p)
	var near: Dictionary = world.nearest_name(Vector2(p.x, p.z))
	var where: String = near.name if near.dist < 450.0 else "Äpätti"
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
	var pm: float = player.promille
	var dt := drunk_text(pm)
	_drunk_label.text = "%.1f ‰ · %s" % [pm, dt] if dt != "" else ""
	var d: float = player.drunk()
	_drunk_fx.visible = d > 0.08 or player.pose == "Sammunut"
	if _drunk_fx.visible:
		var mat: ShaderMaterial = _drunk_fx.material
		mat.set_shader_parameter("amount", d)
		mat.set_shader_parameter("out_k", 1.0 if player.pose == "Sammunut" else 0.0)
	var out: bool = player.pose == "Sammunut"
	if out != _was_out:
		_was_out = out
		toast("Sammuit kätkön viereen… Herätys, kun humala laskee." if out else "Heräsit. Pää on kuin kiuas.", 5.0)
	_stamina.modulate = Color(1, 0.4, 0.3) if player.exhausted else Color.WHITE
	var day: Dictionary = sun.today()
	_clock.text = "%s · %s · aurinko laskee %s, nousee %s%s" % [Porukka.CREW[player_index].name, sun.clock_text(),
		day.set, day.rise, "  ▶▶ (T)" if sun.fast else ""]
	if mp.online():
		_clock.text += "\nMoninpeli: huone %s · %d pelaajaa · Enter: viesti kaikille" % [mp.room(), mp.players()]
	if pissa.active:
		_prompt.text = pissa.prompt()
	elif _ballgame() != null:
		_prompt.text = _ballgame().prompt()
	elif activity != "":
		_prompt.text = _activity_node().prompt()
	elif player.boat != null:
		_prompt.text = "W/S soutaa · A/D kääntää · E %s · %s" % ["veneestä" if retki.active else "nouse veneestä", retki.prompt()]
	else:
		_prompt.text = _interaction().get("text", "")
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _toast_t > 0.0:
		_toast_t -= get_process_delta_time()
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
