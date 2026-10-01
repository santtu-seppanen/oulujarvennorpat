extends Node
## Moninpelin yhteys välityspalvelimeen (server/, Cloudflare Worker + Durable Object): WebSocket ja
## JSON-viestit. Huone tunnistetaan koodilla; palvelin jakaa tunnukset, kertoo kuka on host (ensimmäisenä
## liittynyt) ja välittää viestit muille. Toimii sekä selaimessa että työpöytäversiossa.
##
## Palvelimen osoitteen voi vaihtaa komentoriviltä: godot --path . -- --palvelin=ws://localhost:8787

signal welcomed
signal message(d: Dictionary)
signal peer_joined(id: int)
signal peer_left(id: int)
signal failed(why: String)

const SERVER := "wss://norpat.santtu-seppane.workers.dev"
const CODE_CHARS := "ABCDEFHJKLMNPRSTUVY"

var room := ""
var my_id := 0
var host_id := 0
var peers: Array[int] = []

var _ws := WebSocketPeer.new()
var _state := WebSocketPeer.STATE_CLOSED
var _full := false


static func server_url() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--palvelin="):
			return a.trim_prefix("--palvelin=")
	return SERVER


static func new_code() -> String:
	var s := ""
	for i in 4:
		s += CODE_CHARS[randi() % CODE_CHARS.length()]
	return s


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func online() -> bool:
	return my_id != 0


## Yhteys auki tai avautumassa.
func busy() -> bool:
	return _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED


func is_host() -> bool:
	return my_id != 0 and my_id == host_id


func join(code: String) -> void:
	room = code.strip_edges().to_upper()
	my_id = 0
	_full = false
	_ws = WebSocketPeer.new()
	_ws.outbound_buffer_size = 1 << 18
	var err := _ws.connect_to_url(server_url() + "/huone/" + room)
	if err != OK:
		failed.emit("Palvelimeen ei saatu yhteyttä (%s)" % error_string(err))


func leave() -> void:
	_ws.close()
	my_id = 0
	host_id = 0
	peers.clear()


func send(d: Dictionary) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(d))


func _process(_delta: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	while st == WebSocketPeer.STATE_OPEN and _ws.get_available_packet_count() > 0:
		var d: Variant = JSON.parse_string(_ws.get_packet().get_string_from_utf8())
		if d is Dictionary:
			_handle(d)
	if st == WebSocketPeer.STATE_CLOSED and _state != WebSocketPeer.STATE_CLOSED:
		var why := "Yhteys palvelimeen katkesi" if my_id != 0 else "Palvelimeen ei saatu yhteyttä"
		if _full:
			why = "Huone on täynnä"
		my_id = 0
		host_id = 0
		peers.clear()
		failed.emit(why)
	_state = st


func _handle(d: Dictionary) -> void:
	match d.get("t", ""):
		"welcome":
			my_id = int(d.id)
			host_id = int(d.host)
			peers.clear()
			for p in d.peers:
				peers.append(int(p))
			welcomed.emit()
		"join":
			host_id = int(d.host)
			peers.append(int(d.id))
			peer_joined.emit(int(d.id))
		"leave":
			host_id = int(d.host)
			peers.erase(int(d.id))
			peer_left.emit(int(d.id))
		"full":
			_full = true
			_ws.close()
		_:
			message.emit(d)
