extends CharacterBody3D
## Hahmo jalan: W/S eteen/taakse, A/D kääntyy, Shift juoksee, välilyönti hyppää. Kamera takaa (CamCtl).
## Vedessä kahlataan (hitaampi, roiskeet) ja syvässä uidaan: pää pysyy pinnalla, Shift ui nopeammin.
## Samaa hahmoa ohjaa joko pelaaja (näppäimet) tai tietokone (brain = ai.gd, samat syötteet). Hahmo voi myös
## istua penkillä (sit_at), olla sisällä saunassa tai mökissä (set_hidden_inside) ja soutaa kumivenettä (boat).

const B := preload("res://scripts/build.gd")
const Looks := preload("res://scripts/looks.gd")
const Terrain := preload("res://scripts/terrain.gd")

const WALK := 2.3
const RUN := 5.4
## Juoksu kuluttaa kuntoa: täydellä kunnolla jaksaa juosta noin 20 s.
const RUN_DRAIN := 5.0
const TURN := 2.6
const GRAVITY := 20.0
const JUMP_SPEED := 6.5
const SWIM := 1.1
const SWIM_FAST := 1.9
const SWIM_DRAIN := 3.0
## Uidaan, kun vettä on yli tämän verran (m): silloin pelaaja kelluu niin, että pää on pinnalla.
const SWIM_DEPTH := 1.35
const FLOAT_Y := -1.25  # vartalon juuren korkeus vedenpinnasta uidessa
## Humala (promilleina): ohjaus heittelee, raskaassa humalassa ohjaus välillä kääntyy, CRAWL:sta ylöspäin
## kävely ei onnistu vaan konttaillaan, ja OUT:sta ylöspäin sammutaan, kunnes humala laskee alle CRAWL:n.
const CRAWL := 3.0
const OUT := 3.6
const SOBER_RATE := 0.004  # promillea sekunnissa (1 ‰ haihtuu noin neljässä minuutissa)
const CRAWL_SPEED := 0.45

var controls_enabled := true
var world: Node3D
var look: Dictionary = Looks.PLAYER
var display_name := ""
var is_player := true
var brain: RefCounted = null  # ai.gd: kun asetettu, syötteet tulevat siltä
## Moninpeli: hahmoa ohjataan toisella koneella, tila tulee verkosta (net_apply) ja tässä vain näytetään.
var remote := false
var pose := ""  # tekoälyn asento paikallaan (Sitting_Idle, Idle_Talking, ...)
var airborne := false
var boat: CharacterBody3D = null
var hidden_inside := false
var surface := Terrain.FOREST
var speed := 0.0
var stamina := 100.0
var exhausted := false
var swimming := false
## Veden syvyys pelaajan kohdalla (0 = kuivalla tai laiturilla).
var water_depth := 0.0
var on_wood := false
var promille := 0.0
var drinks := 0
var _drunk_t := 0.0
var _drink_t := 0.0

var _body: Node3D
var _cam: Camera3D
var _cam_ready := false
var _step_t := 0.0
var _breath_t := 0.0
var _shape: CollisionShape3D
var _label: Label3D
var _net_pos := Vector3.ZERO
var _net_rot := 0.0
var _net_throttle := 0.0
var _net_steer := 0.0


func _ready() -> void:
	collision_mask |= Terrain.COLLISION_LAYER
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	_shape = B.capsule_shape(0.3, 1.8)
	add_child(_shape)
	_body = Looks.make(self, look)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 9000.0
	_cam.top_level = true
	add_child(_cam)
	if display_name != "":
		_label = B.guide(self, display_name, Vector3(0, 2.15, 0), 48, Color(1, 0.95, 0.75))


func body() -> Node3D:
	return _body


func activate_camera() -> void:
	_cam.current = true
	_cam_ready = false


# --- Syötteet: näppäimet tai tekoäly --------------------------------------------------------------------------

func input_throttle() -> float:
	if remote:
		return _net_throttle
	if brain != null:
		return brain.throttle
	return Input.get_axis("back", "forward")


func input_steer() -> float:
	if remote:
		return _net_steer
	if brain != null:
		return brain.steer
	return Input.get_axis("right", "left")


func _input_fast() -> bool:
	if brain != null:
		return brain.fast
	return Input.is_key_pressed(KEY_SHIFT)


func _input_jump() -> bool:
	if brain != null:
		return brain.jump
	return Input.is_action_just_pressed("jump")


## Kunnon kulutus ja palautuminen.
func tire(exerting: bool, resting: bool, delta: float, drain: float) -> void:
	if exerting:
		stamina = maxf(0.0, stamina - drain * delta)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(100.0, stamina + (22.0 if resting else 12.0) * delta)
		if exhausted and stamina >= 35.0:
			exhausted = false
	if exhausted and is_player:
		_breath_t -= delta
		if _breath_t <= 0.0:
			_breath_t = 0.75
			Sfx.play("whoosh", -10.0, 0.5)


func _sound(snd: String, vol: float, pitch: float) -> void:
	if is_player:
		Sfx.play(snd, vol, pitch)
	elif _cam_dist() < 25.0:
		Sfx.play_on(self, snd, vol - 4.0, pitch)


func _cam_dist() -> float:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position.distance_to(global_position) if cam != null else INF


# --- Istuminen, sisällä olo ja vene ---------------------------------------------------------------------------

## Istuu penkille kohdassa seat (penkin keskikohta lattiatasolla), kasvot kohti pistettä face.
func sit_at(seat: Vector3, face: Vector3) -> void:
	var d := face - seat
	rotation.y = atan2(-d.x, -d.z)
	global_position = seat - Vector3(d.x, 0, d.z).normalized() * 0.08
	velocity = Vector3.ZERO
	pose = "Sitting_Idle"
	_shape.disabled = true  # penkki ja lauteet saavat olla kapselin sisällä


## Nousee seisomaan: penkiltä askel taaksepäin pöydästä, lauteilta (forward) eteenpäin alas.
func stand_up(forward := false) -> void:
	var fwd := -global_transform.basis.z
	global_position += fwd * (0.45 if forward else -0.45)
	global_position.y += 0.05
	pose = ""
	_shape.disabled = hidden_inside


## Saunassa tai mökissä: näkymätön eikä törmää.
func set_hidden_inside(on: bool) -> void:
	hidden_inside = on
	visible = not on
	_shape.disabled = on
	velocity = Vector3.ZERO


func enter_boat(b: CharacterBody3D) -> void:
	boat = b
	b.rower = self
	add_collision_exception_with(b)
	b.add_collision_exception_with(self)
	_shape.disabled = true
	pose = ""
	speed = 0.0


## Nousee veneestä sen viereen: laiturille tai rantaan, jos lähellä, muuten veteen.
func leave_boat() -> void:
	var b := boat
	if b == null:
		return
	b.rower = null
	boat = null
	_body.clear_ik()
	_body.rotation.y = 0.0
	_body.position = Vector3.ZERO
	var best := b.global_position + b.global_transform.basis.x * 1.1
	var space := get_world_3d().direct_space_state
	var top := -INF
	for k in 12:
		var a := TAU * k / 12.0
		var off := Vector3(cos(a), 0, sin(a)) * 1.3
		var from := b.global_position + off + Vector3.UP * 3.0
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0)
		q.exclude = [b.get_rid(), get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.position.y > top:
			top = hit.position.y
			best = hit.position
	global_position = best + Vector3.UP * 0.1
	velocity = Vector3.ZERO
	_shape.disabled = false
	remove_collision_exception_with(b)
	b.remove_collision_exception_with(self)
	_sound("water", -6.0, 1.2)


func _ride(delta: float) -> void:
	var seat: Vector3 = boat.global_transform * boat.SEAT
	global_position = seat
	rotation.y = boat.rotation.y
	velocity = Vector3.ZERO
	surface = Terrain.WATER
	water_depth = 0.0
	swimming = false
	_body.rotation.y = PI  # soutaja istuu kasvot perään
	_body.play("Sitting_Idle", 0.3)
	var hull: Node3D = boat._hull
	var rowing := absf(input_throttle()) > 0.05 or absf(input_steer()) > 0.05
	var ph: float = boat.phase if rowing else -1.0
	for s: float in [1.0, -1.0]:
		var h: Vector3 = hull.global_transform * boat.handle_pos(s, ph, input_steer())
		var target := _body.to_local(h)
		var side := "l" if s > 0.0 else "r"
		var pole := target + Vector3(0.45 * (1.0 if side == "l" else -1.0), -0.35, 0.1)
		_body.set_ik("arm_" + side, "upperarm_" + side, "lowerarm_" + side, "hand_" + side, target, pole)
	tire(rowing, not rowing, delta, 1.5)
	if is_player:
		_update_camera(delta)


# --- Fysiikka -------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if remote:
		_puppet(delta)
		return
	_drunk_t += delta
	promille = maxf(0.0, promille - SOBER_RATE * delta)
	if _drink_t > 0.0:
		_drink_t -= delta
		if _drink_t <= 0.0 and pose == "Interact":
			pose = ""
	if brain != null and controls_enabled:
		brain.think(delta)
	if boat != null:
		_ride(delta)
		return
	if hidden_inside:
		return
	# Istuessa törmäys on pois (sit_at); kun asento vaihtuu muuten kuin stand_up:lla, se palautetaan.
	if _shape.disabled and not pose.begins_with("Sitting"):
		_shape.disabled = false
	var p := global_position
	surface = Terrain.surface(p.x, p.z)
	var level: float = world.water_level_at(p.x, p.z) if world != null else 0.0
	var ground := Terrain.h(p.x, p.z)
	# Laiturilla ja terassilla seistään rakenteen päällä: syvyys jalkojen alta.
	if is_on_floor() and p.y > ground + 0.15:
		ground = p.y
	water_depth = maxf(0.0, level - ground) if not is_nan(level) else 0.0
	swimming = water_depth > SWIM_DEPTH

	_drunk_pose()
	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump_pressed := false
	if controls_enabled and pose != "Sammunut":
		throttle = input_throttle()
		steer = input_steer()
		fast = _input_fast() and throttle > 0.0 and not exhausted
		jump_pressed = _input_jump() and not swimming
		if brain == null and promille > 0.3:
			var d := drunk()
			# Ohjaus heittelee ja pyörii omia aikojaan; raskaassa humalassa välillä väärään suuntaan.
			steer += (sin(_drunk_t * 1.3) * 0.6 + sin(_drunk_t * 2.9 + 1.0) * 0.4) * d * 1.3
			if absf(throttle) > 0.1:
				steer += sin(_drunk_t * 0.5 + 2.0) * d * 0.8
			if d > 0.6 and sin(_drunk_t * 0.37) > 0.8:
				steer = -steer
			throttle *= 1.0 - 0.45 * d * absf(sin(_drunk_t * 0.7))
			fast = fast and d < 0.6  # kännissä ei juosta
			jump_pressed = jump_pressed and d < 0.75
	if pose == "Ryomii":
		throttle = clampf(throttle, -0.3, 1.0)
		fast = false
		jump_pressed = false
	if pose.begins_with("Sitting"):
		throttle = 0.0
		steer = 0.0
		jump_pressed = false
	rotation.y += steer * TURN * delta
	var fwd := -global_transform.basis.z

	if swimming:
		tire(fast, false, delta, SWIM_DRAIN)
		var want := throttle * (SWIM_FAST if fast else SWIM)
		if throttle < 0.0:
			want *= 0.5
		speed = move_toward(speed, want, 3.0 * delta)
		velocity.x = fwd.x * speed
		velocity.z = fwd.z * speed
		# Kelluu: vartalo hakeutuu pinnan alle niin, että pää jää pinnalle.
		velocity.y = clampf((level + FLOAT_Y - p.y) * 4.0, -3.0, 3.0)
		move_and_slide()
		airborne = false
		_animate(delta)
		_update_camera(delta)
		return

	var running := fast
	tire(running, absf(speed) < 0.2, delta, RUN_DRAIN)
	var gmul := 1.0
	if water_depth > 0.05:
		gmul = clampf(1.0 - water_depth * 0.55, 0.35, 1.0)  # kahlaus
	elif surface == Terrain.BOG and not on_wood:
		gmul = 0.75
	elif surface == Terrain.SAND and not on_wood:
		gmul = 0.9
	var want := throttle * (RUN if running else WALK) * gmul
	if throttle < 0.0:
		want *= 0.6
	if pose == "Ryomii":
		want = throttle * CRAWL_SPEED
	speed = move_toward(speed, want, 12.0 * delta)
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	# Humalassa horjutaan sivuttain.
	if brain == null and controls_enabled and promille > 0.3 and pose != "Ryomii":
		var side := Vector3(-fwd.z, 0, fwd.x)
		var lurch := sin(_drunk_t * 0.9) * 0.7 + sin(_drunk_t * 2.3 + 0.5) * 0.3
		velocity += side * lurch * drunk() * (0.6 + absf(speed) * 0.35)
	if pose == "Sammunut":
		velocity.x = 0.0
		velocity.z = 0.0
	if pose.begins_with("Sitting"):
		velocity = Vector3.ZERO
	elif is_on_floor():
		velocity.y = JUMP_SPEED if jump_pressed else 0.0
		if jump_pressed:
			_sound("whoosh", -8.0, 1.4)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	speed = Vector2(velocity.x, velocity.z).dot(Vector2(fwd.x, fwd.z))
	on_wood = false
	for i in get_slide_collision_count():
		var col := get_slide_collision(i).get_collider()
		if col != null and col.has_meta("puu"):
			on_wood = true
	airborne = not is_on_floor()
	_animate(delta)
	_update_camera(delta)


## Humala 0..1 (1 = konttausraja).
func drunk() -> float:
	return clampf(promille / CRAWL, 0.0, 1.0)


## Olut tai viina: promille kasvaa, hahmo ottaa huikan.
func drink(amount: float) -> void:
	promille += amount
	drinks += 1
	if pose == "" or pose == "Interact":
		pose = "Interact"
		_drink_t = 1.1
	_sound("glass", -8.0, randf_range(0.9, 1.15))


## Humalan asento: konttaus ja sammuminen (eivät koske istumista tai tekoälyn asentoja).
func _drunk_pose() -> void:
	if pose != "" and pose != "Ryomii" and pose != "Sammunut" and pose != "Interact":
		return
	if promille >= OUT:
		if pose != "Sammunut":
			_sound("body_fall", -4.0, 1.0)
		pose = "Sammunut"
	elif pose == "Sammunut" and promille >= CRAWL:
		pass  # herätään vasta, kun humala on laskenut konttausrajan alle
	elif promille >= CRAWL:
		pose = "Ryomii"
	elif pose == "Ryomii" or pose == "Sammunut":
		pose = ""


## Kameran heilunta humalassa.
func drunk_shake() -> Vector3:
	var d := drunk()
	if d < 0.05 or brain != null:
		return Vector3.ZERO
	return Vector3(sin(_drunk_t * 0.8), sin(_drunk_t * 1.1) * 0.5, cos(_drunk_t * 0.7)) * 0.35 * d


## Animaatio ja askeläänet nopeuden, asennon ja pinnan mukaan: sama omalle, tekoälyn ja verkon hahmolle.
func _animate(delta: float) -> void:
	var s := absf(speed)
	var lying := pose == "Sammunut" and not swimming
	_body.rotation.x = -PI * 0.5 if lying else 0.0
	_body.position.y = 0.16 if lying else 0.0
	if swimming:
		_body.play("Swim_Fwd" if s > 0.2 else "Swim_Idle", 0.3, maxf(0.6, s / SWIM))
		_step_t += delta
		if _step_t > (0.9 if s > 0.2 else 2.2):
			_step_t = 0.0
			_sound("water", -12.0 if s > 0.2 else -18.0, randf_range(1.1, 1.4))
		return
	if pose == "Sammunut":
		_body.play("Idle", 0.5, 0.3)
		return
	if pose == "Ryomii":
		_body.play("Crouch_Fwd" if s > 0.08 else "Crouch_Idle", 0.3, maxf(0.5, s / CRAWL_SPEED))
		return
	if pose != "" and s < 0.2:
		_body.play(pose, 0.35)
	elif airborne and not pose.begins_with("Sitting"):
		_body.play("Jump", 0.1)
	elif s < 0.2:
		_body.play("Idle", 0.25)
	elif s < 2.8:
		_body.play("Walk", 0.2, signf(speed) * s / 1.6)
	else:
		_body.play("Sprint", 0.2, s / 6.0)
	# Askeleet pinnan mukaan; laiturilla ja terassilla puuta, vedessä loiskahdukset.
	_step_t += s * delta
	var stride := 0.75 if s < 2.8 else 1.4
	if _step_t > stride:
		_step_t = 0.0
		if water_depth > 0.05 or (surface == Terrain.BOG and not on_wood):
			_sound("water", -9.0, randf_range(1.4, 1.8))
		var step := "step_hard" if on_wood or surface in [Terrain.ROAD, Terrain.ROCK, Terrain.FILL] else "step_grass"
		_sound(step, -8.0 + (3.0 if s > 2.8 else 0.0), randf_range(0.9, 1.1))


# --- Moninpeli ------------------------------------------------------------------------------------------------

func set_remote(on: bool) -> void:
	remote = on
	_net_pos = global_position
	_net_rot = rotation.y
	_net_throttle = 0.0
	_net_steer = 0.0


## Tila verkkoon: [hahmo, x, y, z, suunta, nopeus, liput, asento, kaasu, kääntö]; liput 1 ui, 2 ilmassa,
## 4 sisällä, 8 veneessä.
func net_state(index: int) -> Array:
	var p := global_position
	var f := (1 if swimming else 0) | (2 if airborne else 0) | (4 if hidden_inside else 0) | (8 if boat != null else 0)
	var th := input_throttle() if controls_enabled else 0.0
	var st := input_steer() if controls_enabled else 0.0
	return [index, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(rotation.y, 0.01),
		snappedf(speed, 0.01), f, pose, snappedf(th, 0.01), snappedf(st, 0.01)]


## Toisen koneen lähettämä tila (net_state); veneeseen nousu ja siitä poistuminen hoidetaan moninpeli.gd:ssä.
func net_apply(a: Array) -> void:
	_net_pos = Vector3(a[1], a[2], a[3])
	_net_rot = a[4]
	speed = a[5]
	var f := int(a[6])
	swimming = f & 1 != 0
	airborne = f & 2 != 0
	if (f & 4 != 0) != hidden_inside:
		set_hidden_inside(f & 4 != 0)
	pose = a[7]
	_net_throttle = a[8]
	_net_steer = a[9]


## Verkon hahmo: liukuu kohti viimeisintä tilaa, animaatio ja äänet paikallisesti.
func _puppet(delta: float) -> void:
	if boat != null:
		_ride(delta)
		return
	if hidden_inside:
		return
	var k := 1.0 - exp(-12.0 * delta)
	if global_position.distance_to(_net_pos) > 4.0:
		global_position = _net_pos
	else:
		global_position = global_position.lerp(_net_pos, k)
	rotation.y = lerp_angle(rotation.y, _net_rot, k)
	velocity = Vector3.ZERO
	var p := global_position
	surface = Terrain.surface(p.x, p.z)
	var ground := Terrain.h(p.x, p.z)
	on_wood = p.y > ground + 0.15 and not airborne
	var level: float = world.water_level_at(p.x, p.z) if world != null else 0.0
	water_depth = maxf(0.0, level - (p.y if on_wood else ground)) if not is_nan(level) else 0.0
	_animate(delta)


func _update_camera(delta: float) -> void:
	if not is_player:
		return
	var eye: Vector3 = _body.to_global(_body.bone_position("Head")) + Vector3.UP * 0.08
	CamCtl.update_camera(_cam, self, eye, 4.2, 2.6, absf(speed) > 0.5, delta, not _cam_ready, drunk_shake())
	_cam_ready = true
