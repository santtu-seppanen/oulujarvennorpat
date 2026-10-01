extends Node
## Moninpeli: kukin pelaaja ohjaa omaa mökkiläistään, vapaita hahmoja ohjaa hostin (huoneeseen ensimmäisenä
## liittyneen) tietokone. Jokainen kone lähettää ohjaamiensa hahmojen tilan 12 kertaa sekunnissa
## (on_foot.gd net_state), ja muilla koneilla hahmot liukuvat tilasta toiseen. Kumiveneen tilan lähettää
## soutaja tai, kun vene on vapaana, host. Host jakaa hahmovaraukset ja pitää kelloa. Maailma rakennetaan
## jokaisella koneella samasta aineistosta, joten sitä ei lähetetä. Yhteys: net.gd ja server/.
##
## Viestit: s (hahmojen ja veneen tila), claim (hahmon varaus hostilta), roster (varaukset), aika (hostin
## kello), nopeus (T pohjassa muulla kuin hostilla).

signal roster_changed
signal failed(why: String)

const Net := preload("res://scripts/net.gd")
const RATE := 12.0

var game: Node3D
var net: Node
var owners := {}  # hahmon indeksi -> pelaajan tunnus
var mine := -1  # oma hahmo, -1 = ei vielä valittu
var preset := 0

var _send_t := 0.0
var _time_t := 0.0
var _fast := {}  # hostilla: tunnus -> T pohjassa
var _sent_fast := false
var _host_fast := false
var _handlers := {}  # viestityyppi -> Callable(d: Dictionary, from: int): minipelien viestit


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	net = Net.new()
	add_child(net)
	net.welcomed.connect(_on_welcome)
	net.message.connect(_on_message)
	net.peer_joined.connect(_on_join)
	net.peer_left.connect(_on_leave)
	net.failed.connect(_on_failed)


func online() -> bool:
	return net.online()


func room() -> String:
	return net.room


func players() -> int:
	return net.peers.size() + 1


## Uusi huone satunnaisella koodilla; p = alkuhetki (sun.gd PRESETS).
func create(p: int) -> void:
	preset = p
	net.join(Net.new_code())


func join(code: String) -> void:
	preset = 0  # jos huone onkin tyhjä, tästä tulee host
	net.join(code)


## Hahmon varaus: host päättää, muut pyytävät hostilta.
func claim(i: int) -> void:
	if net.is_host():
		_grant(net.my_id, i)
	else:
		net.send({"t": "claim", "i": i, "to": net.host_id})


## Viesti muille (yksinpelissä ei tee mitään).
func send(d: Dictionary) -> void:
	if net.online():
		net.send(d)


## Minipelin viestityypin käsittelijä.
func on(type: String, cb: Callable) -> void:
	_handlers[type] = cb


func taken_by_other(i: int) -> bool:
	return owners.has(i) and owners[i] != net.my_id


## Tietokone ohjaa vapaita hahmoja vain hostilla (ja yksinpelissä).
func _authority() -> bool:
	return not net.online() or net.is_host()


func _grant(id: int, i: int) -> void:
	if i < 0 or i >= game.crew.size() or (owners.has(i) and owners[i] != id):
		_send_roster()
		return
	for j in owners.keys():
		if owners[j] == id:
			owners.erase(j)
	owners[i] = id
	_apply()
	_send_roster()


func _send_roster() -> void:
	var o := {}
	for i in owners:
		o[str(i)] = owners[i]
	net.send({"t": "roster", "o": o})
	roster_changed.emit()


func _send_time() -> void:
	net.send({"t": "aika", "u": int(game.sun.t_utc), "f": _host_fast})


## Hahmojen ohjaus varausten mukaan: oma pelaaja, muiden pelaajat verkosta, vapaat hostin tekoälylle.
func _apply() -> void:
	var was := mine
	mine = -1
	for i in owners:
		if owners[i] == net.my_id:
			mine = i
	for j in game.crew.size():
		var mode := "ai"
		if j == mine:
			mode = "player"
		elif owners.has(j) or not _authority():
			mode = "remote"
		game.set_crew_mode(j, mode)
	if mine >= 0 and mine != was:
		game.set_player(mine)
		game.respawn()


# --- Yhteyden tapahtumat --------------------------------------------------------------------------------------

func _on_welcome() -> void:
	# Valikko ja kartta pysäyttävät pelin, mutta moninpelissä muut liikkuvat silti.
	for n in game.crew + [game.boat, game.sun]:
		n.process_mode = Node.PROCESS_MODE_ALWAYS
	owners.clear()
	if net.is_host():
		game.sun.start_preset(preset)
	_apply()
	roster_changed.emit()


func _on_join(_id: int) -> void:
	if net.is_host():
		_send_roster()
		_send_time()


func _on_leave(id: int) -> void:
	for i in owners.keys():
		if owners[i] == id:
			owners.erase(i)
	_fast.erase(id)
	_apply()  # jos tästä tuli host, vapaat hahmot siirtyvät tämän koneen tekoälylle
	if net.is_host():
		_send_roster()
	roster_changed.emit()


## Yhteys katkesi: jatketaan yksin, muut hahmot tietokoneelle.
func _on_failed(why: String) -> void:
	owners.clear()
	if mine >= 0:
		owners[mine] = net.my_id
	_fast.clear()
	game.sun.remote_fast = false
	_apply()
	failed.emit(why)


func _on_message(d: Dictionary) -> void:
	var from := int(d.get("from", 0))
	match d.get("t", ""):
		"s":
			_on_state(d, from)
		"claim":
			if net.is_host():
				_grant(from, int(d.i))
		"roster":
			if from == net.host_id:
				owners.clear()
				for k in d.o:
					owners[int(k)] = int(d.o[k])
				_apply()
				roster_changed.emit()
		"aika":
			if from == net.host_id:
				var diff: float = float(d.u) - game.sun.t_utc
				if absf(diff) > 600.0:
					game.sun.t_utc = float(d.u)
				else:
					game.sun.t_utc += diff * 0.5
				game.sun.remote_fast = bool(d.f)
		"nopeus":
			_fast[from] = bool(d.on)
		var t:
			if _handlers.has(t):
				_handlers[t].call(d, from)


func _on_state(d: Dictionary, from: int) -> void:
	for c in d.get("c", []):
		var j := int(c[0])
		if j < 0 or j >= game.crew.size() or c.size() < 10:
			continue
		var b: CharacterBody3D = game.crew[j]
		if not b.remote:
			continue
		_boat_flag(b, int(c[6]) & 8 != 0, from)
		b.net_apply(c)
	if d.has("b") and game.boat.remote:
		game.boat.net_apply(d.b)


## Toinen pelaaja nousi veneeseen tai siitä pois. Jos kaksi ehti samaan aikaan, pienempi tunnus voittaa.
func _boat_flag(b: CharacterBody3D, in_boat: bool, from: int) -> void:
	var boat: CharacterBody3D = game.boat
	if in_boat and b.boat == null:
		var r: Node3D = boat.rower
		if r != null:
			if not r.remote and from > net.my_id:
				return  # oma pelaaja ehti ensin; toinen nousee pois saatuaan tilamme
			r.leave_boat()
		b.enter_boat(boat)
	elif not in_boat and b.boat != null:
		b.leave_boat()


# --- Lähetys --------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not net.online():
		return
	# Veneen tilasta vastaa soutaja, tai kun vene on vapaana, host.
	var r: Node3D = game.boat.rower
	var local: bool = (r != null and not r.remote) or (r == null and _authority())
	if game.boat.remote == local:
		game.boat.set_remote(not local)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = maxf(_send_t + 1.0 / RATE, 0.0)
		var cs := []
		for j in game.crew.size():
			if game.crew_modes[j] != "remote":
				cs.append(game.crew[j].net_state(j))
		var d := {"t": "s", "c": cs}
		if local:
			d["b"] = game.boat.net_state()
		if not cs.is_empty() or local:
			net.send(d)
	var sun: Node = game.sun
	if net.is_host():
		sun.remote_fast = _fast.values().has(true)
		var f: bool = sun.key_fast or sun.remote_fast
		_time_t -= delta
		if _time_t <= 0.0 or f != _host_fast:
			_host_fast = f
			_time_t = 1.0
			_send_time()
	elif sun.key_fast != _sent_fast:
		_sent_fast = sun.key_fast
		net.send({"t": "nopeus", "on": _sent_fast, "to": net.host_id})
