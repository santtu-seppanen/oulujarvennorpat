extends Node
## Happy Beachin baarirakennuksen toiminnot sisällä (happybeach.gd), alamökin minipelien tapaan aktiviteettina "baari":
## - tiski: tilausvalikko (olut, lonkero, siideri, viinapaukku, kahvi ja pulla, hampurilainen), baarimikko kommentoi
## - karaoke: lavalla laulu osumalla E:llä tahtiin (osumapalkki), sanat baarin ruudulla; onnistuminen kuittaa tehtävän
## - jukeboksi: soittaa pelin musiikkikappaleita huoneessa, diskovalot pyörivät musiikin ajan
## - pajatso: kolme rullaa, pelimerkit (ei oikeaa rahaa)
## - hedelmäpeli: kolme rullaa, voi lukita rullia ennen uutta pyöräytystä
## - Sinikka: juttelu, drinkin tarjoaminen ja yhteistanssi; pöytäseurue ja korttipelaajat: jutustelu
## - tanssi: tanssilattialla pyöritään diskopallon alla
## Käyttöliittymä on valikon tyylinen (ui.gd); W/S tai E (valikoissa) lopettaa.

const Ui := preload("res://scripts/ui.gd")

const TRACKS := [
	["Chariots of Fire", "res://assets/music/chariots_of_fire_alku.ogg"],
	["Oodi (säestys)", "res://assets/music/oodi_saestys.ogg"],
	["Retkimusiikki", "res://assets/music/retkimusiikki_silmukka.ogg"],
]
const LYRICS := ["Äpätin ilta, järvi on tyyni", "Aurinko laskee, saunassa kuuma", "Happy Beachilla tanssitaan yhdessä",
	"Kippis kaikille, yö on vielä nuori"]
const BEATS := 12
const FLIRT_LIMIT := 4.0  # näin paljon Sinikan flirttailua, niin vaimo soittaa
const MAINE_LOSS := 10
const WIFE_LINES := ["Kuka se Sinikka on?! Kuulin taustalta karaokea ja naurua. Tuu heti kotiin!",
	"Kuule, naapurin Pirjo sanoi nähneensä sut tanssimassa jonkun kanssa! Selitä!",
	"Onko toi se Sinikka taas siellä?! Mää en kestä tätä, sanon vaan.",
	"Mää olen kuullut kaiken! Ei ole sopivaa flirttailla Happy Beachilla, kun kotona odotetaan!"]
const SLOT_SYMBOLS := ["Kirs", "Sitr", "Kello", "Tähti", "777"]
const FRUITS := ["Kirsikka", "Sitruuna", "Luumu", "Kello", "Seiska"]

var game: Node3D
var mode := ""  # tiski | karaoke | jukeboksi | pajatso | tanssi
var _ui: CanvasLayer
var _box: VBoxContainer
var _status: Label
var _tokens := 10
var _reels: Array[Label] = []
var _held := [false, false, false]
var _hold_btns: Array[Button] = []
var _with_sinikka := false
var _flirt := 0.0  # flirttailun määrä: laskee ajan myötä, ja liika flirtti saa vaimon soittamaan
var _call_ui: CanvasLayer
var _call_label: Label
var _call_t := 0.0
var _calls := 0
var _force := ""  # pakotettu tila ilman toimintopistettä (yhteistanssi)
# Karaoke
var _meter: Ui.Meter
var _beat := 0
var _hits := 0
var _pos := 0.0
var _dir := 1.0
var _zone := Vector2(0.4, 0.6)
var _pause := 0.0
var _stage_back := Vector3.ZERO
# Tanssi
var _dance_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	_call_ui = CanvasLayer.new()
	_call_ui.layer = 22
	_call_ui.visible = false
	add_child(_call_ui)
	var cbox := Ui.panel(_call_ui, "top", 620)
	Ui.label(cbox, "VAIMO SOITTAA", 22, Color(1.0, 0.35, 0.3))
	_call_label = Ui.label(cbox, "", 18)


func start() -> bool:
	var h: Node3D = game.world.happy
	var spot: Dictionary = h.spot_at(game.player.global_position)
	if spot.is_empty() and _force == "":
		return false
	mode = _force if _force != "" else spot.id
	_force = ""
	var target := Vector2(-3.75, 10.2)
	match mode:
		"jukeboksi":
			target = Vector2(-10.5, 13.4)
		"pajatso":
			target = Vector2(-10.5, 10.6)
		"karaoke":
			_stage_back = game.player.global_position
			var st: Vector3 = h.world_at(1.5, 10.9)
			game.player.global_position = st + Vector3(0, 0.32, 0)
			target = Vector2(1.5, 14.5)
		"hedelma":
			target = Vector2(-10.5, 11.7)
		"tanssi":
			target = Vector2(0.8, 14.5)
			if _with_sinikka:
				h.place_sinikka(true)
				game.player.global_position = h.world_at(0.2, 14.3)
				target = Vector2(1.9, 14.3)
		"sinikka":
			target = Vector2(-1.0, 11.1)
		"seurue":
			target = Vector2(-8.8, 14.4)
		"kortit":
			target = Vector2(-8.4, 11.9)
	var tw: Vector3 = h.world_at(target.x, target.y)
	var d: Vector3 = tw - game.player.global_position
	game.player.rotation.y = atan2(-d.x, -d.z)
	game.player.velocity = Vector3.ZERO
	_build()
	_ui.visible = true
	CamCtl.free_mouse = true
	return true


func stop(_why := "") -> void:
	_ui.visible = false
	CamCtl.free_mouse = false
	if mode == "karaoke":
		game.player.global_position = _stage_back
		game.world.happy.set_screen("KARAOKE\nE: laula")
	if mode == "tanssi":
		_dance_t = 0.0
		game.world.happy.place_sinikka(false)
		_with_sinikka = false
	mode = ""


func prompt() -> String:
	match mode:
		"karaoke":
			return "E: osu tahtiin, kun osoitin on vihreällä · W/S: lopeta"
		"pajatso", "hedelma":
			return "E: pyöräytä · W/S: lopeta"
		"tanssi":
			return "Tanssit diskopallon alla · W/S: lopeta"
	return "Valitse klikkaamalla · E tai W/S: lopeta"


func act() -> void:
	match mode:
		"karaoke":
			_sing_hit()
		"pajatso", "hedelma":
			_spin()
		_:
			game.end_activity()


# --- Näkymät --------------------------------------------------------------------------------------------------

func _build() -> void:
	for c in _ui.get_children():
		c.queue_free()
	_reels.clear()
	_meter = null
	_box = Ui.panel(_ui, "bottom", 560)
	var title: String = {"tiski": "HAPPY BEACH · BAARI", "karaoke": "KARAOKE", "jukeboksi": "JUKEBOKSI", "pajatso": "PAJATSO",
		"hedelma": "HEDELMÄPELI", "tanssi": "TANSSILATTIA", "sinikka": "SINIKKA", "seurue": "PÖYTÄSEURUE",
		"kortit": "KORTTIPELI"}[mode]
	Ui.label(_box, title, 22, Ui.YELLOW)
	_status = Ui.label(_box, "", 16)
	match mode:
		"tiski":
			_status.text = "Baarimikko: \"Mitäs laitetaan?\""
			for i in game.world.happy.MENU_ITEMS.size():
				var it: Array = game.world.happy.MENU_ITEMS[i]
				Ui.button(_box, it[0], func() -> void: _order(i)).custom_minimum_size = Vector2(300, 38)
		"jukeboksi":
			_status.text = "Toivo biisi:"
			for t: Array in TRACKS:
				Ui.button(_box, t[0], func() -> void: _play(t)).custom_minimum_size = Vector2(300, 38)
			Ui.button(_box, "Sammuta musiikki", func() -> void:
				game.world.happy.play_music(null)
				_status.text = "Musiikki pois.")
		"pajatso":
			_status.text = "Pelimerkkejä %d. E pyöräyttää." % _tokens
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 14)
			_box.add_child(row)
			for k in 3:
				var l := Ui.label(row, "—", 28, Color(1.0, 0.9, 0.4))
				l.custom_minimum_size = Vector2(110, 50)
				_reels.append(l)
			Ui.button(_box, "Pyöräytä (E)", _spin)
		"hedelma":
			_held = [false, false, false]
			_hold_btns.clear()
			_status.text = "Pelimerkkejä %d. Pyöräytä, lukitse rullia ja pyöräytä uudelleen." % _tokens
			var hrow := HBoxContainer.new()
			hrow.alignment = BoxContainer.ALIGNMENT_CENTER
			hrow.add_theme_constant_override("separation", 14)
			_box.add_child(hrow)
			for k in 3:
				var col := VBoxContainer.new()
				hrow.add_child(col)
				var l := Ui.label(col, "—", 24, Color(1.0, 0.9, 0.4))
				l.custom_minimum_size = Vector2(130, 46)
				_reels.append(l)
				var hb := Ui.button(col, "Lukitse", func() -> void: _toggle_hold(k))
				hb.custom_minimum_size = Vector2(130, 32)
				_hold_btns.append(hb)
			Ui.button(_box, "Pyöräytä (E)", _spin)
		"sinikka":
			_status.text = "Sinikka: \"Moi! Kiva nähdä.\""
			Ui.button(_box, "Juttele", func() -> void:
				_flirt_add(0.7)
				var t: String = game.world.happy.SINIKKA_LINES.pick_random()
				_status.text = "Sinikka: \"%s\"" % t
				game.world.happy.say(game.world.happy.sinikka, t))
			Ui.button(_box, "Tarjoa drinkki (lonkero)", func() -> void:
				game.player.drink(0.2)
				Sfx.play("register", -8.0)
				game.tarina.complete("baari")
				_flirt_add(1.2)
				var t := "Voi kiitos, juot sinäkin! Kippis!"
				_status.text = "Sinikka: \"%s\" (%.1f ‰)" % [t, game.player.promille]
				game.world.happy.say(game.world.happy.sinikka, t))
			Ui.button(_box, "Pyydä tanssimaan", func() -> void:
				_flirt_add(1.6)
				game.end_activity()
				_with_sinikka = true
				_force = "tanssi"
				game.start_activity("baari"))
		"seurue":
			_status.text = "Seurue: \"Istu vaan!\""
			Ui.button(_box, "Juttele seurueen kanssa", func() -> void:
				var t: String = game.world.happy.SEURUE_LINES.pick_random()
				_status.text = "Seurue: \"%s\"" % t
				game.world.happy.say(game.world.happy._seurue.pick_random(), t))
		"kortit":
			_status.text = "Paikalliset pelaavat korttia. Katsot olan yli."
			Ui.button(_box, "Katso peliä", func() -> void:
				var t: String = game.world.happy.CARD_LINES.pick_random()
				_status.text = "Pelaaja: %s" % t
				game.world.happy.say(game.world.happy._cardplayers.pick_random(), t))
		"karaoke":
			_beat = 0
			_hits = 0
			_pause = 1.5
			_meter = Ui.Meter.new()
			_box.add_child(_meter)
			_status.text = "Valmistaudu..."
			game.world.happy.disco_on = 60.0
		"tanssi":
			_status.text = "Tanssit Sinikan kanssa diskopallon alla. W/S lopettaa." if _with_sinikka else "Diskopallo pyörii. W/S lopettaa."
			_dance_t = 0.0
			game.world.happy.disco_on = maxf(game.world.happy.disco_on, 40.0)
	Ui.button(_box, "Valmis (E)" if mode in ["tiski", "jukeboksi", "sinikka", "seurue", "kortit"] else "Lopeta",
		func() -> void: game.end_activity())


func _order(i: int) -> void:
	var it: Array = game.world.happy.MENU_ITEMS[i]
	var p: CharacterBody3D = game.player
	Sfx.play("register", -6.0)
	if float(it[1]) > 0.0:
		p.drink(float(it[1]))
		game.tarina.complete("baari")
		_status.text = "Baarimikko: \"%s, tässä. Kippis!\" (%d. huikka, %.1f ‰)" % [it[0], p.drinks, p.promille]
	else:
		p.promille = maxf(0.0, p.promille - float(it[2]))
		p.stamina = 100.0
		p.exhausted = false
		_status.text = "Baarimikko: \"%s. Hyvä valinta.\" Kunto palautui." % it[0]
		Sfx.play("pickup", -8.0)


func _play(t: Array) -> void:
	game.world.happy.play_music(load(t[1]) as AudioStream)
	_status.text = "Soi: %s" % t[0]
	Sfx.play("coins_1", -8.0)


func _toggle_hold(k: int) -> void:
	_held[k] = not _held[k]
	_hold_btns[k].text = "LUKITTU" if _held[k] else "Lukitse"


func _spin() -> void:
	if (mode != "pajatso" and mode != "hedelma") or _reels.is_empty():
		return
	if _tokens <= 0:
		_tokens = 5
		_status.text = "Baarimikko lainaa viisi pelimerkkiä."
		return
	_tokens -= 1
	var r: Array[String] = []
	var symbols: Array = SLOT_SYMBOLS if mode == "pajatso" else FRUITS
	for k in 3:
		if mode == "hedelma" and _held[k] and _reels[k].text in symbols:
			r.append(_reels[k].text)
		else:
			r.append(symbols[randi() % symbols.size()])
		_reels[k].text = r[k]
	if mode == "hedelma":
		_held = [false, false, false]
		for hb in _hold_btns:
			hb.text = "Lukitse"
	Sfx.play("coins_2", -8.0)
	var win := 0
	if r[0] == r[1] and r[1] == r[2]:
		win = 30 if r[0] in ["777", "Seiska"] else 10
	elif r[0] == r[1] or r[1] == r[2] or r[0] == r[2]:
		win = 2
	_tokens += win
	_status.text = ("Voitto! +%d · " % win if win > 0 else "Ei voittoa · ") + "pelimerkkejä %d" % _tokens
	if win >= 10:
		Sfx.play("win", -8.0)


# --- Karaoke ja tanssi ----------------------------------------------------------------------------------------

## Flirttailu Sinikan kanssa: liika flirtti saa vaimon soittamaan äkäisen puhelun, ja mainepisteet laskevat.
func _flirt_add(n: float) -> void:
	_flirt += n
	if _flirt >= FLIRT_LIMIT:
		_flirt = 0.0
		_wife_call()


func _wife_call() -> void:
	_calls += 1
	game.maine = maxi(0, game.maine - MAINE_LOSS)
	var t: String = WIFE_LINES[(_calls - 1) % WIFE_LINES.size()]
	_call_label.text = "\"%s\"\n\nMainepisteet -%d (nyt %d/100)" % [t, MAINE_LOSS, game.maine]
	_call_ui.visible = true
	_call_t = 8.0
	Sfx.play("alert", -4.0)
	game.toast("Vaimo soitti äkäisen puhelun Sinikasta! Mainepisteet -%d." % MAINE_LOSS, 5.0)


func _process(delta: float) -> void:
	_flirt = maxf(0.0, _flirt - delta / 45.0)  # flirtti haihtuu ajan myötä
	if _call_t > 0.0:
		_call_t -= delta
		if _call_t <= 0.0:
			_call_ui.visible = false
	if mode == "tanssi":
		_dance_t += delta
		game.player.rotation.y += delta * 2.4
		game.player.global_position.y += sin(_dance_t * 9.0) * 0.0  # pysyy lattialla
	if mode != "karaoke" or _meter == null:
		return
	if _beat >= BEATS:
		return
	if _pause > 0.0:
		_pause -= delta
		if _pause <= 0.0:
			_next_beat()
		return
	_pos += _dir * (0.7 + 0.05 * _beat) * delta
	if _pos > 1.0 or _pos < 0.0:
		_pos = clampf(_pos, 0.0, 1.0)
		_dir = -_dir
	_meter.set_value(_pos)


func _next_beat() -> void:
	var c := randf_range(0.25, 0.75)
	_zone = Vector2(c - 0.09, c + 0.09)
	_meter.zones = [[_zone.x, _zone.y, Color(0.2, 0.75, 0.3, 0.8)]]
	_meter.queue_redraw()
	var line: String = LYRICS[(_beat / 3) % LYRICS.size()]
	_status.text = "♪ %s ♪   (%d/%d, osumia %d)" % [line, _beat + 1, BEATS, _hits]
	game.world.happy.set_screen("♪ %s ♪\nosumia %d" % [line, _hits])


func _sing_hit() -> void:
	if _meter == null or _pause > 0.0 or _beat >= BEATS:
		return
	if _pos >= _zone.x and _pos <= _zone.y:
		_hits += 1
		Sfx.play("win_small", -10.0)
	else:
		Sfx.play("lose", -16.0)
	_beat += 1
	if _beat >= BEATS:
		_finish_song()
	else:
		_pause = 0.35


func _finish_song() -> void:
	var t := "Laulu loppui: %d/%d osumaa. " % [_hits, BEATS]
	if _hits >= 9:
		t += "Yleisö villiintyy! Tähtiesitys."
		Sfx.play("win", -6.0)
	elif _hits >= 5:
		t += "Aplodit kuuluvat."
		Sfx.play("win_small", -6.0)
	else:
		t += "Yleisö on kohtelias."
	_status.text = t
	game.world.happy.set_screen("KARAOKE\n%d/%d" % [_hits, BEATS])
	game.toast(t, 5.0)
	game.tarina.complete("laulu")
	_pause = 0.0
