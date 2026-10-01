extends CharacterBody3D
## Pelaaja jalan: W/S eteen/taakse, A/D kääntyy, Shift juoksee, välilyönti hyppää. Kamera takaa (CamCtl).
## Vedessä kahlataan (hitaampi, roiskeet) ja syvässä uidaan: pää pysyy pinnalla, Shift ui nopeammin.

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

var controls_enabled := true
var world: Node3D
var surface := Terrain.FOREST
var speed := 0.0
var stamina := 100.0
var exhausted := false
var swimming := false
## Veden syvyys pelaajan kohdalla (0 = kuivalla).
var water_depth := 0.0

var _body: Node3D
var _cam: Camera3D
var _cam_ready := false
var _step_t := 0.0
var _breath_t := 0.0


func _ready() -> void:
	collision_mask |= Terrain.COLLISION_LAYER
	floor_max_angle = deg_to_rad(50.0)
	add_child(B.capsule_shape(0.3, 1.8))
	_body = Looks.make(self, Looks.PLAYER)
	CamCtl.mark_own_body(_body)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 9000.0
	_cam.top_level = true
	add_child(_cam)


func activate_camera() -> void:
	_cam.current = true
	_cam_ready = false


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
	if exhausted:
		_breath_t -= delta
		if _breath_t <= 0.0:
			_breath_t = 0.75
			Sfx.play("whoosh", -10.0, 0.5)


func _physics_process(delta: float) -> void:
	var p := global_position
	surface = Terrain.surface(p.x, p.z)
	var level: float = world.water_level_at(p.x, p.z) if world != null else 0.0
	water_depth = maxf(0.0, level - Terrain.h(p.x, p.z)) if not is_nan(level) else 0.0
	swimming = water_depth > SWIM_DEPTH

	var throttle := 0.0
	var steer := 0.0
	var fast := false
	var jump_pressed := false
	if controls_enabled:
		throttle = Input.get_axis("back", "forward")
		steer = Input.get_axis("right", "left")
		fast = Input.is_key_pressed(KEY_SHIFT) and throttle > 0.0 and not exhausted
		jump_pressed = Input.is_action_just_pressed("jump") and not swimming
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
		_body.play("Swim_Fwd" if absf(speed) > 0.2 else "Swim_Idle", 0.3, maxf(0.6, absf(speed) / SWIM))
		_step_t += delta
		if _step_t > (0.9 if absf(speed) > 0.2 else 2.2):
			_step_t = 0.0
			Sfx.play("water", -12.0 if absf(speed) > 0.2 else -18.0, randf_range(1.1, 1.4))
		_update_camera(delta)
		return

	var running := fast
	tire(running, absf(speed) < 0.2, delta, RUN_DRAIN)
	var ground := 1.0
	if water_depth > 0.05:
		ground = clampf(1.0 - water_depth * 0.55, 0.35, 1.0)  # kahlaus
	elif surface == Terrain.BOG:
		ground = 0.75
	elif surface == Terrain.SAND:
		ground = 0.9
	var want := throttle * (RUN if running else WALK) * ground
	if throttle < 0.0:
		want *= 0.6
	speed = move_toward(speed, want, 12.0 * delta)
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	if is_on_floor():
		velocity.y = JUMP_SPEED if jump_pressed else 0.0
		if jump_pressed:
			Sfx.play("whoosh", -8.0, 1.4)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	speed = Vector2(velocity.x, velocity.z).dot(Vector2(fwd.x, fwd.z))

	var s := absf(speed)
	if not is_on_floor():
		_body.play("Jump", 0.1)
	elif s < 0.2:
		_body.play("Idle", 0.25)
	elif s < 2.8:
		_body.play("Walk", 0.2, signf(speed) * s / 1.6)
	else:
		_body.play("Sprint", 0.2, s / 6.0)
	# Askeleet pinnan mukaan; vedessä loiskahdukset.
	_step_t += s * delta
	var stride := 0.75 if s < 2.8 else 1.4
	if _step_t > stride:
		_step_t = 0.0
		if water_depth > 0.05 or surface == Terrain.BOG:
			Sfx.play("water", -9.0, randf_range(1.4, 1.8))
		var step := "step_hard" if surface in [Terrain.ROAD, Terrain.ROCK, Terrain.FILL] else "step_grass"
		Sfx.play(step, -8.0 + (3.0 if s > 2.8 else 0.0), randf_range(0.9, 1.1))
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var eye: Vector3 = _body.to_global(_body.bone_position("Head")) + Vector3.UP * 0.08
	CamCtl.update_camera(_cam, self, eye, 4.2, 2.6, absf(speed) > 0.5, delta, not _cam_ready)
	_cam_ready = true
