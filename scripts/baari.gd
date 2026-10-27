extends Node
## Happy Beachin baarirakennuksen toiminnot sisällä (happybeach.gd), alamökin minipelien tapaan aktiviteettina "baari":
## - tiski: tilausvalikko (olut, lonkero, siideri, viinapaukku, kahvi ja pulla, hampurilainen), baarimikko kommentoi
## - karaoke: lavalla laulu osumalla E:llä tahtiin (osumapalkki), sanat baarin ruudulla; onnistuminen kuittaa tehtävän
## - jukeboksi: soittaa pelin musiikkikappaleita huoneessa, diskovalot pyörivät musiikin ajan
## - pajatso: kolme rullaa, pelimerkit (ei oikeaa rahaa)
## - hedelmäpeli: kolme rullaa, voi lukita rullia ennen uutta pyöräytystä ja tuplata voiton
## - pokeri: Coinline-jokeripokeri (pokeri_game.gd), viisi korttia ja jokeri, pidä ja vaihda, tuplaus
## Jokaisella pelillä on ohje (ohje.gd): se aukeaa ensimmäisellä kerralla itsestään, ja H avaa sen uudelleen.
## - Sinikka: juttelu, drinkin tarjoaminen ja yhteistanssi; pöytäseurue ja korttipelaajat: jutustelu
## - tanssi: tanssilattialla eurodance-rytmipeli diskopallon alla (tanssi_game.gd), yksin tai Sinikan kanssa
## Käyttöliittymä on valikon tyylinen (ui.gd); F tai E (valikoissa) lopettaa.

const Ui := preload("res://scripts/ui.gd")
const PajatsoGame := preload("res://scripts/pajatso_game.gd")
const HedelmapeliGame := preload("res://scripts/hedelmapeli_game.gd")
const PokeriGame := preload("res://scripts/pokeri_game.gd")
const KaraokeGame := preload("res://scripts/karaoke_game.gd")
const TanssiGame := preload("res://scripts/tanssi_game.gd")

## Pelin oma kappale (Suno, ks. docs/traileri/biisi.md): tiedosto lisätään jukeboksiin, valikkoon ja traileriin, kun se on olemassa.
const SONG_PATH := "res://assets/music/oulujarven_norpat.mp3"
const TRACKS := [
	["Oulujärven norpat", SONG_PATH],
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
var mode := ""  # tiski | karaoke | jukeboksi | pajatso | hedelma | pokeri | tanssi
var _ui: CanvasLayer
var _box: VBoxContainer
var _status: Label
var _tokens := 10  # euroja pajatsolle ja hedelmäpelille
const ATM_SUM := 20  # pankkiautomaatista saa päivässä kerran näin monta euroa
var _atm_key := -1  # päivä (vvvvkkpp), jona nosto on jo tehty
var _pot := 12  # pajatson potti säilyy koneessa
var _gnode: CanvasLayer
var in_game := false  # pajatso, hedelmäpeli, videopokeri, karaoke tai tanssi (canvas-minipeli tai sen ohje) on auki
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


## Päivän tunniste (vvvvkkpp) automaatin nostoa varten.
func _today_key() -> int:
	var lt: Dictionary = game.sun.local()
	return int(lt.year) * 10000 + int(lt.month) * 100 + int(lt.day)


func atm_ready() -> bool:
	return _atm_key != _today_key()


## Pankkiautomaatti Happy Beachin seinässä: 20 € pelirahaa kerran päivässä.
func atm_withdraw() -> void:
	if not atm_ready():
		game.toast("Päivän nosto on jo tehty. Automaatti antaa %d € joka päivä." % ATM_SUM, 3.0)
		return
	_atm_key = _today_key()
	_tokens += ATM_SUM
	Sfx.play("coin", -6.0, 0.9)
	game.toast("Nostit %d € pankkiautomaatilta. Pelirahaa nyt %d €." % [ATM_SUM, _tokens], 4.0)


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
	var tw: Vector3 = h.world_at(target.x, target.y)
	var d: Vector3 = tw - game.player.global_position
	game.player.rotation.y = atan2(-d.x, -d.z)
	game.player.velocity = Vector3.ZERO
	_build()
	_ui.visible = true
	CamCtl.free_mouse = true
	if mode == "pajatso" or mode == "hedelma" or mode == "pokeri":
		_launch_game()
	elif mode == "karaoke":
		_launch_karaoke()
	elif mode == "tanssi":
		_launch_dance()
	return true


## Pelin käynnistys: ensimmäisellä kerralla ohje (ohje.gd) aukeaa ensin, ja itse peli luodaan vasta ohjeen jälkeen.
## in_game on tosi heti, joten main.gd ei lopeta aktiviteettia F:llä ohjeen aikana.
func _begin(help_id: String, build: Callable) -> void:
	in_game = true
	_ui.visible = false
	var m := mode
	game.ohje.open_first(help_id, func() -> void:
		if game.activity == "baari" and mode == m and in_game:
			build.call())


func _attach(g: CanvasLayer) -> void:
	_gnode = g
	game.add_child(g)


## Karaoke on Normipäivän Frets on Fire -versio (karaoke_game.gd), kappaleena Oodi Oulujärvelle.
func _launch_karaoke() -> void:
	_begin("karaoke", func() -> void:
		var g := KaraokeGame.new()
		g.drunk = game.player.drunk()
		var h: Node3D = game.world.happy
		h.play_music(null)
		h.disco_on = 1.0e6
		g.line.connect(func(t: String) -> void: h.set_screen("♪ %s ♪" % t))
		g.finished.connect(_karaoke_end)
		_attach(g))


## Tanssilattia on eurodance-rytmipeli (tanssi_game.gd); Sinikan kanssa tanssiessa tulos paranee hieman.
func _launch_dance() -> void:
	_begin("tanssi", func() -> void:
		var g := TanssiGame.new()
		g.drunk = game.player.drunk()
		var h: Node3D = game.world.happy
		h.play_music(null)
		h.disco_on = 1.0e6
		h.set_screen("TANSSI\nA S W D")
		g.finished.connect(_dance_end)
		_attach(g))


## Minipelin canvas-kerros pois näkyvistä: peli ei vapauta itseään, kun se päättyy signaaliin.
func _drop_game() -> void:
	if is_instance_valid(_gnode):
		_gnode.queue_free()
	_gnode = null


func _dance_end(score: float, combo: int) -> void:
	in_game = false
	_drop_game()
	var h: Node3D = game.world.happy
	h.disco_on = 6.0
	game.player.pose = ""
	if _with_sinikka:
		score = minf(1.0, score + 0.05)
	var t := "Tanssi: %d %%, paras putki %d. " % [roundi(score * 100.0), combo]
	if score >= 0.8:
		t += "Lattia on sinun! Koko Happy Beach katsoo."
		Sfx.play("win", -6.0)
	elif score >= 0.45:
		t += "Hyvää menoa, yleisö taputtaa."
		Sfx.play("win_small", -6.0)
	else:
		t += "Rytmi hukassa, mutta meno oli lämmintä."
	h.set_screen("TANSSI\n%d %%" % roundi(score * 100.0))
	game.toast(t, 5.0)
	if score >= 0.35:
		game.tarina.complete("tanssi")
	if game.activity == "baari":
		game.end_activity()


func _karaoke_end(score: float) -> void:
	in_game = false
	_drop_game()
	var h: Node3D = game.world.happy
	h.disco_on = 6.0
	var t := "Oodi Oulujärvelle laulettu: %d %%. " % roundi(score * 100.0)
	if score >= 0.8:
		t += "Yleisö villiintyy! Tähtiesitys."
		Sfx.play("win", -6.0)
	elif score >= 0.45:
		t += "Aplodit kuuluvat."
		Sfx.play("win_small", -6.0)
	else:
		t += "Yleisö on kohtelias."
	h.set_screen("KARAOKE\n%d %%" % roundi(score * 100.0))
	game.toast(t, 5.0)
	if score >= 0.25:
		game.tarina.complete("laulu")
	if game.activity == "baari":
		game.end_activity()


## Pajatso ja hedelmäpeli ovat samat canvas-minipelit kuin Normipäivässä (pajatso_game.gd, hedelmapeli_game.gd);
## videopokeri on pokeri_game.gd.
func _launch_game() -> void:
	_begin(mode, func() -> void:
		var g: CanvasLayer
		if mode == "pajatso":
			var pg := PajatsoGame.new()
			pg.pot = _pot
			pg.finished.connect(func(m: float, pot: int) -> void:
				_pot = pot
				_game_end(m))
			g = pg
		elif mode == "pokeri":
			var kg := PokeriGame.new()
			kg.finished.connect(func(m: float) -> void: _game_end(m))
			g = kg
		else:
			var hg := HedelmapeliGame.new()
			hg.finished.connect(func(m: float) -> void: _game_end(m))
			g = hg
		g.drunk = game.player.drunk()
		g.money = float(_tokens)
		_attach(g))


## H avaa pelin ohjeen kesken pajatson, hedelmäpelin tai videopokerin (peli odottaa, kunnes ohje suljetaan).
func _input(event: InputEvent) -> void:
	if not in_game or mode not in ["pajatso", "hedelma", "pokeri"] or not is_instance_valid(_gnode) or game.ohje.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
		var g := _gnode
		g.process_mode = Node.PROCESS_MODE_DISABLED
		game.ohje.open(mode, func() -> void:
			if is_instance_valid(g):
				g.process_mode = Node.PROCESS_MODE_INHERIT)
		get_viewport().set_input_as_handled()


func _game_end(money_after: float) -> void:
	in_game = false
	_drop_game()
	var net := int(money_after) - _tokens
	_tokens = int(money_after)
	if game.activity == "baari":
		game.end_activity()
	if net >= 10:
		game.toast("Plussalla %d €! Tänään on onnenpäivä." % net, 3.0)
	elif net > 0:
		game.toast("Plussalla %d €." % net, 2.5)
	elif net < 0:
		game.toast("Peli vei %d €. Ei se mitään, se oli huvia." % -net, 2.5)


func stop(_why := "") -> void:
	if in_game:
		in_game = false
		if game.ohje.is_open():
			game.ohje.close()
		_drop_game()
	_ui.visible = false
	CamCtl.free_mouse = false
	if mode == "karaoke":
		game.player.global_position = _stage_back
		game.world.happy.set_screen("KARAOKE\nE: laula")
	if mode == "tanssi":
		_dance_t = 0.0
		game.player.pose = ""
		game.world.happy.place_sinikka(false)
		_with_sinikka = false
	mode = ""


func prompt() -> String:
	match mode:
		"karaoke":
			return ""
		"pajatso", "hedelma", "pokeri":
			return "H: ohje · F / Esc: lopeta"
		"tanssi":
			return "A S W D tai nuolet: askeleet tahtiin · Esc / F: lopeta"
	return "Valitse klikkaamalla · E tai F: lopeta"


func act() -> void:
	match mode:
		"karaoke":
			pass  # Frets on Fire -karaoke lukee näppäimet itse
		"pajatso", "hedelma", "pokeri":
			pass  # minipeli lukee E:n itse
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
		"pokeri": "VIDEOPOKERI", "hedelma": "HEDELMÄPELI", "tanssi": "TANSSILATTIA", "sinikka": "SINIKKA", "seurue": "PÖYTÄSEURUE"}[mode]
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
				if not ResourceLoader.exists(t[1]):
					continue
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
		"karaoke":
			_beat = 0
			_hits = 0
			_pause = 1.5
			_meter = Ui.Meter.new()
			_box.add_child(_meter)
			_status.text = "Valmistaudu..."
			game.world.happy.disco_on = 60.0
		"tanssi":
			_status.text = "Tanssit Sinikan kanssa diskopallon alla. F lopettaa." if _with_sinikka else "Diskopallo pyörii. F lopettaa."
			_dance_t = 0.0
			game.world.happy.disco_on = maxf(game.world.happy.disco_on, 40.0)
	Ui.button(_box, "Valmis (E)" if mode in ["tiski", "jukeboksi", "sinikka", "seurue"] else "Lopeta",
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
	Sfx.play("coin", -8.0)


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
	Sfx.play("coin", -8.0)
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
		if in_game and is_instance_valid(_gnode):
			game.player.pose = "Dance" if _gnode.dancing() else ""
		elif not in_game:
			game.player.rotation.y += delta * 2.4
	if mode != "karaoke" or _meter == null or in_game:
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
