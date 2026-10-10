extends Node
## Korttipelit alamökin keittiön pöydässä: ristiseiska (säännöt ristiseiska.gd) ja tuppi (tuppi.gd); pelimuoto
## valitaan pöydässä ennen jakoa. Kortit pelataan pöydälle: ristiseiskan rivit tai tupin tikki näkyvät pöydän
## keskellä ja kunkin pelaajan käsi kuvapuoli alaspäin hänen edessään, joten pöydän ääressä näkee, kuka pelaa
## ja paljonko kortteja muilla on. Istuva pelaaja näkee oman kätensä ruudun alareunassa ja pelaa klikkaamalla;
## A/D tai hiiren oikea nappi pohjassa kääntää katsetta pöydän ympäri, ja E näyttää pöydän suoraan ylhäältä.
## Mukana ovat aina kaikki neljä mökkiläistä: pöydässä istuvat ihmiset pelaavat itse, muiden puolesta pelaa
## tietokone, ja tietokoneen ohjaamat hahmot kävelevät pöytään.
##
## Moninpelissä pelitilaa pitää host: muut lähettävät siirtonsa ("rs") ja host jakaa tilan ("rs_tila").

const R := preload("res://scripts/ristiseiska.gd")
const T := preload("res://scripts/tuppi.gd")
const Ui := preload("res://scripts/ui.gd")

var bot_delay := 1.2  # tietokoneen siirron viive (testissä pienempi)
const RED := Color(0.8, 0.08, 0.1)

var game: Node3D
var kind := "ristiseiska"  # ristiseiska | tuppi
var logic := R.new()
var tuppi := T.new()
var top_view := false  # E: pöytä suoraan ylhäältä
var humans := {}  # mökkiläisen indeksi -> pöydässä istuva ihminen (hostin tieto)
var _rng := RandomNumberGenerator.new()
var _bot_t := 0.0
var _ai_at_table := false
var _seen_moves := -1
var _seen_phase := ""

var _ui: CanvasLayer
var _title: Label
var _kind_btn: Button
var _hand: HBoxContainer
var _status: Label
var _players: Label
var _deal_btn: Button

## Pöydän kortit 3D:nä: kortin koko (leveys pitkin pöytää, korkeus pöydän poikki), rivien väli ja kortit
## yhdestä tekstuurikartasta (13 x 5 ruutua, viimeisellä rivillä selkäpuoli).
const CARD_W := 0.058
const CARD_H := 0.082
const PITCH_V := 0.062
const PITCH_U := 0.098
const CELL := Vector2i(96, 134)
var _table: Node3D
var _marker: MeshInstance3D
var _card_mat: StandardMaterial3D
var _meshes := {}  # kortti (52 = selkä) -> ArrayMesh
var _atlas: SubViewport
var _atlas_wait := 0
var _anim := {}  # kortti -> [alku, loppu, aika] viimeisimmän siirron liukuma


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	game.mp.on("rs", func(d: Dictionary, from: int) -> void:
		if game.mp.net.is_host():
			_handle(d, from))
	game.mp.on("rs_tila", func(d: Dictionary, from: int) -> void:
		if from == game.mp.net.host_id:
			kind = d.k
			logic.from_dict(d.s)
			tuppi.from_dict(d.tu)
			humans.clear()
			for i in d.hu:
				humans[int(i)] = true
			_changed())
	game.mp.net.peer_joined.connect(func(_id: int) -> void:
		if game.mp.net.is_host():
			_broadcast())
	_build_ui()
	_build_table()


func _authority() -> bool:
	return not game.mp.online() or game.mp.net.is_host()


# --- Toiminta (main.gd kutsuu) --------------------------------------------------------------------------------

func start() -> bool:
	var m: Node3D = game.world.mokki
	var seat: Array = m.table_seats[game.player_index]
	game.player.sit_at(seat[0], seat[1])
	_ui.visible = true
	CamCtl.free_mouse = true
	_request("istu")
	game.kokkaus.eat()
	game.kahvi.drink()
	_refresh()
	return true


## E: pöytä ylhäältä tai takaisin omalle paikalle.
func act() -> void:
	top_view = not top_view
	_update_view()


## Jako (nappi tai välilyönti), kun peli ei ole käynnissä.
func deal() -> void:
	if not playing():
		_request("jaa")


func stop(_why := "") -> void:
	_ui.visible = false
	CamCtl.free_mouse = false
	top_view = false
	_update_view()
	game.player.stand_up()
	_request("nouse")


func prompt() -> String:
	var look := "E: pöytä ylhäältä" if not top_view else "E: takaisin paikalle"
	if not playing():
		return "Välilyönti: jaa kortit (%s) · %s · W: nouse pöydästä" % [_kind_name(), look]
	return "Klikkaa korttia · %s · A/D: katso ympärille · W: nouse pöydästä" % look


func playing() -> bool:
	if kind == "tuppi":
		return tuppi.phase == "bid" or tuppi.phase == "play" or tuppi.phase == "trick"
	return logic.phase == "play" or logic.phase == "give"


func _kind_name() -> String:
	return "tuppi" if kind == "tuppi" else "ristiseiska"


## Ylhäältä katsottaessa oma paikka on ruudun alareunassa ja koko pöytä näkyy.
func _update_view() -> void:
	var p: Node3D = game.player
	p.view_override_on = top_view
	if not top_view:
		return
	var f := _table.global_transform
	var mine := f.affine_inverse() * (game.world.mokki.table_seats[game.player_index][0] as Vector3)
	var away := f.basis * Vector3(-signf(mine.x), 0.0, 0.0)
	var eye := f * Vector3(0.0, 1.0, 0.0)
	p.view_override = Transform3D(Basis(), eye).looking_at(f.origin, away.normalized())


# --- Pelitila (host) ------------------------------------------------------------------------------------------

func _request(a: String, c := -1) -> void:
	var d := {"t": "rs", "a": a, "i": game.player_index, "c": c}
	if _authority():
		_handle(d, game.mp.net.my_id)
	else:
		d["to"] = game.mp.net.host_id
		game.mp.send(d)


func _handle(d: Dictionary, from: int) -> void:
	var i := int(d.get("i", -1))
	if i < 0 or i >= 4:
		return
	# Siirron saa tehdä vain hahmoa ohjaava pelaaja.
	if game.mp.online():
		if game.mp.owners.get(i, -1) != from:
			return
	elif i != game.player_index:
		return
	var c := int(d.get("c", -1))
	match d.get("a", ""):
		"istu":
			humans[i] = true
		"nouse":
			humans.erase(i)
		"muoto":
			if not playing():
				kind = "tuppi" if kind == "ristiseiska" else "ristiseiska"
		"jaa":
			if not playing():
				if kind == "tuppi":
					tuppi.deal(_rng.randi())
				else:
					logic.deal(_rng.randi())
				_bot_t = 0.0
		"pelaa":
			if kind == "tuppi":
				tuppi.play(i, c)
			else:
				logic.play(i, c)
		"anna":
			logic.give(i, c)
		"tarjoa":
			tuppi.bid(i, c)
	_broadcast()


func _broadcast() -> void:
	game.mp.send({"t": "rs_tila", "k": kind, "s": logic.to_dict(), "tu": tuppi.to_dict(), "hu": humans.keys()})
	_changed()


func _process(delta: float) -> void:
	_atlas_ready()
	_animate(delta)
	if not _authority():
		return
	# Pöydästä poistuneet ihmiset (yhteys katkesi tai hahmo vaihtui) korvautuvat tietokoneella.
	for i in humans.keys():
		var here: bool = (i == game.player_index and game.activity == "kortit") or \
			(game.mp.online() and game.mp.owners.has(i) and game.mp.owners[i] != game.mp.net.my_id)
		if not here:
			humans.erase(i)
			_broadcast()
	var on := playing()
	if on != _ai_at_table:
		_ai_at_table = on
		_gather_ai(on)
	if not on:
		return
	if kind == "tuppi":
		_tuppi_bot(delta)
		return
	var a := logic.actor()
	if humans.has(a):
		return
	_bot_t += delta
	if _bot_t < bot_delay:
		return
	_bot_t = 0.0
	if logic.phase == "play":
		logic.play(a, logic.bot_play(a, _rng))
	else:
		logic.give(a, logic.bot_give(a, _rng))
	_broadcast()


## Tupissa täysi tikki jää hetkeksi näkyviin ennen kuin voittaja kerää sen.
func _tuppi_bot(delta: float) -> void:
	var a := tuppi.actor()
	if tuppi.phase != "trick" and humans.has(a):
		return
	_bot_t += delta
	if _bot_t < (bot_delay * 1.5 if tuppi.phase == "trick" else bot_delay):
		return
	_bot_t = 0.0
	match tuppi.phase:
		"trick":
			tuppi.collect()
		"bid":
			tuppi.bid(a, tuppi.bot_bid(a, _rng))
		"play":
			tuppi.play(a, tuppi.bot_play(a, _rng))
	_broadcast()


## Tietokoneen ohjaamat mökkiläiset pöytään pelin ajaksi.
func _gather_ai(on: bool) -> void:
	for j in game.crew.size():
		var b: CharacterBody3D = game.crew[j]
		if game.crew_modes[j] != "ai" or b.brain == null:
			continue
		if on:
			b.brain.cards(j)
		else:
			b.brain.cards_end()


# --- Näyttö ---------------------------------------------------------------------------------------------------

func _name(i: int) -> String:
	return game.Porukka.CREW[i].name


## Tilan muutos: äänet, pöydän kortit ja viimeisimmän siirron liukuma, sitten näkymä.
func _changed() -> void:
	if kind == "tuppi":
		_tuppi_changed()
		return
	var new_move := logic.moves != _seen_moves and not logic.last.is_empty()
	if new_move and game.activity == "kortit":
		var l: Dictionary = logic.last
		Sfx.play("cloth" if l.a == "pelasi" else "pickup", -10.0, randf_range(0.9, 1.2))
	if logic.phase == "over" and _seen_phase != "over" and _seen_phase != "":
		var w: int = logic.finished[0]
		var loser: int = logic.finished[-1]
		var me: int = game.player_index
		if game.activity == "kortit":
			game.toast("%s voitti ristiseiskan! %s jäi viimeiseksi." % [_name(w), _name(loser)], 6.0)
			Sfx.play("win" if w == me else ("lose" if loser == me else "win_small"), -6.0)
	_anim.clear()
	if new_move and logic.moves == _seen_moves + 1 and logic.last.a == "pelasi":
		var l: Dictionary = logic.last
		_anim[int(l.c)] = [_hand_pos(int(l.p), 0, 1), _slot_pos(int(l.c)), 0.0]
	_seen_moves = logic.moves
	_seen_phase = logic.phase
	_layout_table()
	_refresh()


func _team_name(t: int) -> String:
	return "%s & %s" % [_name(t), _name(t + 2)]


func _tuppi_changed() -> void:
	var L := tuppi
	var new_move := L.moves != _seen_moves and not L.last.is_empty()
	if new_move and game.activity == "kortit":
		Sfx.play("cloth" if L.last.a != "vei" else "pickup", -10.0, randf_range(0.9, 1.2))
	if L.phase == "over" and _seen_phase != "over" and _seen_phase != "" and game.activity == "kortit":
		var me := T.team(game.player_index)
		var k := 0 if L.gained[0] > 0 else 1
		var t := "%s: %s sai %d pistettä." % ["Rami" if L.mode == "rami" else "Nolo", _team_name(k), L.gained[k]]
		if L.winner >= 0:
			t += " %s voitti tupin!" % _team_name(L.winner)
		game.toast(t, 6.0)
		Sfx.play(("win" if L.winner >= 0 else "win_small") if k == me else "lose", -6.0)
	_anim.clear()
	if new_move and L.moves == _seen_moves + 1 and L.last.a == "pelasi":
		var c := int(L.last.c)
		_anim[c] = [_hand_pos(int(L.last.p), 0, 1), _trick_pos(int(L.last.p), L.trick.size() - 1), 0.0]
	_seen_moves = L.moves
	_seen_phase = L.phase
	_layout_table()
	_refresh()


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	_ui.visible = false
	add_child(_ui)
	# Pieni paneeli vasemmassa yläkulmassa, jotta pöytä ja muut pelaajat näkyvät.
	var top := Ui.panel(_ui, "top", 400)
	var pc: Control = top.get_parent()
	pc.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pc.offset_left = 16
	pc.offset_right = 416
	pc.offset_top = 140
	top.add_theme_constant_override("separation", 4)
	_title = Ui.label(top, "RISTISEISKA", 18, Ui.YELLOW)
	_players = Ui.label(top, "", 16)
	_players.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status = Ui.label(top, "", 16, Ui.YELLOW)
	var bottom := Control.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_left = -560
	bottom.offset_right = 560
	bottom.offset_top = -180
	bottom.offset_bottom = -100
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(bottom)
	_hand = HBoxContainer.new()
	_hand.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(_hand)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	top.add_child(btns)
	_deal_btn = Ui.button(btns, "Jaa kortit", deal)
	_kind_btn = Ui.button(btns, "Pelimuoto", func() -> void: _request("muoto"))
	var b2 := HBoxContainer.new()
	b2.alignment = BoxContainer.ALIGNMENT_CENTER
	b2.add_theme_constant_override("separation", 12)
	top.add_child(b2)
	Ui.button(b2, "Pöytä ylhäältä (E)", act)
	Ui.button(b2, "Nouse pöydästä (W)", func() -> void: game.end_activity())


func _refresh() -> void:
	if not _ui.visible:
		return
	_title.text = _kind_name().to_upper()
	_deal_btn.visible = not playing()
	_kind_btn.visible = not playing()
	_kind_btn.text = "Vaihda: %s" % ("ristiseiska" if kind == "tuppi" else "tuppi")
	if kind == "tuppi":
		_refresh_tuppi()
		return
	var me: int = game.player_index
	var playing := playing()
	# Pelaajat: vuoro, korttien määrä ja sijoitus.
	var parts := []
	for p in 4:
		var who := _name(p) + (" (sinä)" if p == me else ("" if humans.has(p) else " (kone)"))
		var info := ""
		if logic.finished.has(p):
			info = "%d." % (logic.finished.find(p) + 1)
		elif logic.hands.size() == 4:
			info = "%d korttia" % logic.hands[p].size()
		parts.append(("▶ " if playing and logic.actor() == p else "    ") + who + ("  " + info if info != "" else ""))
	_players.text = "\n".join(parts)
	var st := ""
	match logic.phase:
		"idle":
			st = "Jaa kortit (välilyönti). Ristiseiskan saanut aloittaa."
		"over":
			st = "Peli päättyi: " + ", ".join(logic.finished.map(func(p: int) -> String:
				return "%d. %s" % [logic.finished.find(p) + 1, _name(p)])) + ". Jaa uudet (välilyönti)."
		"play":
			st = "Sinun vuorosi: pelaa korostettu kortti" if logic.turn == me else "Vuorossa: %s" % _name(logic.turn)
		"give":
			if logic.giver == me:
				st = "%s ei voi pelata: anna hänelle kortti (klikkaa)" % _name(logic.turn)
			else:
				st = "%s ei voi pelata, %s antaa kortin" % [_name(logic.turn), _name(logic.giver)]
	if not logic.last.is_empty() and playing:
		var l: Dictionary = logic.last
		if l.a == "pelasi":
			st = "%s pelasi %s. %s" % [_name(l.p), R.card_name(l.c), st]
		else:
			st = "%s antoi kortin %s:lle. %s" % [_name(l.p), _name(l.to), st]
	_status.text = st
	# Oma käsi.
	if logic.hands.size() != 4:
		_show_hand([], func(_c: int) -> bool: return false, false)
		return
	_show_hand(logic.hands[me], func(c: int) -> bool:
		if logic.phase == "play" and logic.turn == me:
			return logic.can_play(c)
		return logic.phase == "give" and logic.giver == me, playing)


## Oma käsi ruudun alareunaan: ok(kortti) kertoo, voiko kortin pelata nyt.
func _show_hand(hand: Array, ok: Callable, dim: bool) -> void:
	for ch in _hand.get_children():
		ch.queue_free()
	_hand.add_theme_constant_override("separation", 4 if hand.size() <= 14 else -14)
	var cards := hand.duplicate()
	if kind == "tuppi":
		# Tupissa ässä on suurin: maittain pienimmästä ässään.
		cards.sort_custom(func(a: int, b: int) -> bool:
			return R.suit(a) < R.suit(b) or (R.suit(a) == R.suit(b) and T.power(a) < T.power(b)))
	for c in cards:
		var cv := CardView.new()
		cv.card = c
		cv.custom_minimum_size = Vector2(50, 72)
		cv.active = ok.call(c)
		cv.dim = dim and not cv.active
		cv.clicked.connect(_on_card)
		_hand.add_child(cv)


func _refresh_tuppi() -> void:
	var L := tuppi
	var me: int = game.player_index
	var on := playing()
	var parts := []
	for p in 4:
		var who := _name(p) + (" (sinä)" if p == me else ("" if humans.has(p) else " (kone)"))
		var info := ""
		if L.phase == "bid" and L.bids[p] >= 0:
			info = "tarjosi"
		elif L.phase != "idle" and L.phase != "bid":
			info = "%d tikkiä" % L.won[p]
		if p == L.declarer:
			info += " · ilmoitti ramin"
		parts.append(("▶ " if L.actor() == p else "    ") + who + ("  " + info if info != "" else ""))
	for t in 2:
		parts.append("%s: %d pistettä%s" % [_team_name(t), L.scores[t], " (sinun parisi)" if T.team(me) == t else ""])
	_players.text = "\n".join(parts)
	var st := ""
	match L.phase:
		"idle":
			st = "Pareittain, vastakkain istuvat ovat paria. Jaa kortit (välilyönti)."
		"bid":
			if L.turn == me:
				st = "Tarjoa: valitse kortti (ei 2 eikä kuvakortti). Punainen = rami, musta = nolo."
			else:
				st = "Tarjous: %s valitsee korttia" % _name(L.turn)
		"play", "trick":
			st = ("Rami, ilmoittaja %s. " % _name(L.declarer)) if L.mode == "rami" else "Nolo: vältä tikkejä. "
			if L.phase == "trick":
				st += "%s vie tikin." % _name(L.trick_winner)
			elif L.turn == me:
				st += "Sinun vuorosi" + (": tunnusta maata" if not L.trick.is_empty() else "")
			else:
				st += "Vuorossa: %s" % _name(L.turn)
		"over":
			var k := 0 if L.gained[0] > 0 else 1
			st = "%s: %s %d–%d tikkiä, %s +%d. " % ["Rami" if L.mode == "rami" else "Nolo", _team_name(0),
				L.team_tricks(0), L.team_tricks(1), _team_name(k), L.gained[k]]
			st += ("%s voitti! Uusi ottelu (välilyönti)." % _team_name(L.winner)) if L.winner >= 0 \
				else "Seuraava jako (välilyönti)."
	_status.text = st
	if L.hands.size() != 4:
		_show_hand([], func(_c: int) -> bool: return false, false)
		return
	_show_hand(L.hands[me], func(c: int) -> bool:
		if L.phase == "bid" and L.turn == me:
			return L.bid_cards(me).has(c)
		return L.phase == "play" and L.turn == me and L.can_play(me, c), on)


func _on_card(c: int) -> void:
	var me: int = game.player_index
	if kind == "tuppi":
		if tuppi.phase == "bid" and tuppi.turn == me:
			_request("tarjoa", c)
		elif tuppi.phase == "play" and tuppi.turn == me:
			_request("pelaa", c)
		return
	if logic.phase == "play" and logic.turn == me and logic.can_play(c):
		_request("pelaa", c)
	elif logic.phase == "give" and logic.giver == me:
		_request("anna", c)


# --- Kortit pöydällä ------------------------------------------------------------------------------------------
# Pöydän kehys (mokki.card_frame): x pitkin pöydän poikki itään, z = -v (pois järveltä). Pelaajat istuvat
# pöydän länsi- ja itäpuolella, rivit kulkevat pöydän pituussuunnassa niin, että ässä on länsipuolelta katsoen
# vasemmalla.

func _build_table() -> void:
	var m: Node3D = game.world.mokki
	_table = Node3D.new()
	game.add_child(_table)
	_table.global_transform = m.card_frame
	_card_mat = StandardMaterial3D.new()
	_card_mat.roughness = 0.6
	_card_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_card_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_card_mat.emission_enabled = true  # hämärässä keittiössäkin kortit erottuvat
	_card_mat.emission_energy_multiplier = 0.35
	_marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.09
	disc.bottom_radius = 0.09
	disc.height = 0.002
	_marker.mesh = disc
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.8, 0.1, 0.55)
	mm.emission_enabled = true
	mm.emission = Color(1.0, 0.7, 0.1)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = mm
	_marker.visible = false
	_table.add_child(_marker)
	# Korttikartta piirretään kerran omassa näkymässään samalla piirrolla kuin käsi (CardView).
	_atlas = SubViewport.new()
	_atlas.size = Vector2i(CELL.x * 13, CELL.y * 5)
	_atlas.render_target_update_mode = SubViewport.UPDATE_ONCE
	_atlas.transparent_bg = false
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.2, 0.2)
	bg.size = Vector2(_atlas.size)
	_atlas.add_child(bg)
	for c in 53:
		var cv := CardView.new()
		cv.card = c if c < 52 else 0
		cv.back = c == 52
		cv.position = Vector2((c % 13) * CELL.x, (c / 13) * CELL.y) + Vector2(2, 2)
		cv.size = Vector2(CELL) - Vector2(4, 4)
		_atlas.add_child(cv)
	add_child(_atlas)
	_set_texture(_atlas.get_texture())


## Kartta valmis: kopio kuvaksi mipmappeineen (kaukaa katsottuna terävämpi), ja näkymä pois.
func _atlas_ready() -> void:
	if _atlas == null:
		return
	if DisplayServer.get_name() == "headless":
		_atlas = null  # ilman näyttöä jätetään näkymän tekstuuri
		return
	_atlas_wait += 1
	if _atlas_wait < 3:
		return
	var img := _atlas.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		_set_texture(ImageTexture.create_from_image(img))
		_atlas.queue_free()
	_atlas = null


func _set_texture(t: Texture2D) -> void:
	_card_mat.albedo_texture = t
	_card_mat.emission_texture = t


## Kortin mesh: suorakaide pöydän tasossa, kuvan yläreuna +x-suuntaan (poispäin länsipuolen pelaajasta).
func _mesh(c: int) -> ArrayMesh:
	if _meshes.has(c):
		return _meshes[c]
	var col := c % 13 if c < 52 else 0
	var row := c / 13 if c < 52 else 4
	var u0 := float(col * CELL.x + 2) / (CELL.x * 13)
	var u1 := float(col * CELL.x + CELL.x - 2) / (CELL.x * 13)
	var v0 := float(row * CELL.y + 2) / (CELL.y * 5)
	var v1 := float(row * CELL.y + CELL.y - 2) / (CELL.y * 5)
	var h := CARD_H * 0.5
	var w := CARD_W * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(h, 0, -w), Vector3(h, 0, w), Vector3(-h, 0, w), Vector3(-h, 0, -w)]
	var uvs := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
	for k: int in [0, 2, 1, 0, 3, 2]:
		st.set_normal(Vector3.UP)
		st.set_uv(uvs[k])
		st.add_vertex(pts[k])
	var mesh := st.commit()
	_meshes[c] = mesh
	return mesh


## Pelatun kortin paikka rivissään.
func _slot_pos(c: int) -> Vector3:
	var s := R.suit(c)
	var r := R.rank(c)
	return Vector3((s - 1.5) * PITCH_U, 0.001, (r - 7) * PITCH_V)


## Pelaajan p käden k:s kortti n:stä kuvapuoli alaspäin hänen edessään (viuhkana).
func _hand_pos(p: int, k: int, n: int) -> Vector3:
	var m: Node3D = game.world.mokki
	var seat: Vector3 = m.table_seats[p][0]
	var local := _table.global_transform.affine_inverse() * seat
	var west := local.x < 0.0
	var t := (k - (n - 1) * 0.5) * 0.011
	return Vector3((-0.3 if west else 0.3) + absf(t) * 0.15 * (1.0 if west else -1.0), 0.0015 + k * 0.0004,
		local.z + t)


func _card(c: int, pos: Vector3, yaw: float, face_up: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(c if face_up else 52)
	mi.material_override = _card_mat
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("card", c)
	_table.add_child(mi)
	return mi


## Pöydän kortit tilasta: pelatut rivit, kädet pelaajien edessä ja vuorossa olevan merkki.
func _layout_table() -> void:
	for ch in _table.get_children():
		if ch != _marker:
			ch.queue_free()
	if kind == "tuppi":
		_layout_tuppi()
		return
	var playing := playing()
	if logic.hands.size() != 4:
		_marker.visible = false
		return
	for s in 4:
		if logic.low[s] == 0:
			continue
		for r in range(logic.low[s], logic.high[s] + 1):
			var c: int = s * 13 + r - 1
			var mi := _card(c, _slot_pos(c), 0.0, true)
			if _anim.has(c):
				_anim[c].append(mi)
				mi.position = _anim[c][0]
	for p in 4:
		var hand: Array = logic.hands[p]
		var west := _hand_pos(p, 0, 1).x < 0.0
		for k in hand.size():
			var t := (k - (hand.size() - 1) * 0.5) * 0.06
			_card(hand[k], _hand_pos(p, k, hand.size()), (0.0 if west else PI) + t, false)
	_marker.visible = playing
	if playing:
		var hp := _hand_pos(logic.actor(), 0, 1)
		_marker.position = Vector3(hp.x, 0.0005, hp.z)


## Tupin tikin k:s kortti pelaajan p puolelle pöydän keskeltä (vinottain, ettei peitä edellisiä).
func _trick_pos(p: int, k: int) -> Vector3:
	var h := _hand_pos(p, 0, 1)
	return Vector3(signf(h.x) * 0.1, 0.002 + k * 0.0006, signf(h.z) * 0.05)


## Tupin pöytä: kädet, tarjouskortit kuvapuoli alaspäin, tikki keskellä ja voitetut tikit pinoina.
func _layout_tuppi() -> void:
	var L := tuppi
	_marker.visible = false
	if L.hands.size() != 4:
		return
	for p in 4:
		var hand: Array = L.hands[p]
		var hp := _hand_pos(p, 0, 1)
		var west := hp.x < 0.0
		var yaw := 0.0 if west else PI
		for k in hand.size():
			var t := (k - (hand.size() - 1) * 0.5) * 0.06
			_card(hand[k], _hand_pos(p, k, hand.size()), yaw + t, false)
		if L.phase == "bid" and L.bids[p] >= 0:
			_card(L.bids[p], Vector3(hp.x * 0.62, 0.002, hp.z), yaw, false)
		# Voitetut tikit pinona pelaajan vieressä pöydän päädyn puolella.
		for k in L.won[p]:
			_card(52, Vector3(hp.x * 0.8, 0.002 + k * 0.0008, hp.z + signf(hp.z) * 0.15), yaw + PI * 0.5 + k * 0.05,
				false)
	for k in L.trick.size():
		var e: Array = L.trick[k]
		var west := _hand_pos(e[0], 0, 1).x < 0.0
		var mi := _card(e[1], _trick_pos(e[0], k), (0.0 if west else PI) + (k - 1.5) * 0.12, true)
		if _anim.has(e[1]):
			_anim[e[1]].append(mi)
			mi.position = _anim[e[1]][0]
	var a := L.actor()
	_marker.visible = a >= 0
	if a >= 0:
		var hp := _hand_pos(a, 0, 1)
		_marker.position = Vector3(hp.x, 0.0005, hp.z)


## Viimeisin pelattu kortti liukuu pelaajan kädestä paikalleen.
func _animate(delta: float) -> void:
	for c in _anim.keys():
		var a: Array = _anim[c]
		if a.size() < 4 or not is_instance_valid(a[3]):
			continue
		a[2] = minf(1.0, a[2] + delta / 0.4)
		var k: float = ease(a[2], -2.0)
		var mi: MeshInstance3D = a[3]
		mi.position = (a[0] as Vector3).lerp(a[1], k) + Vector3.UP * sin(k * PI) * 0.06
		if a[2] >= 1.0:
			_anim.erase(c)


## Pelikortti piirrettynä: arvo kulmissa ja maa keskellä. Maat piirretään kuvioina (fontista riippumatta).
class CardView:
	extends Control
	signal clicked(card: int)
	var card := 0
	var back := false  # selkäpuoli (pöydällä kuvapuoli alaspäin)
	var ghost := false  # tyhjä paikka
	var active := false  # voi pelata / antaa
	var dim := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP if not ghost else Control.MOUSE_FILTER_IGNORE
		if active:
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(event: InputEvent) -> void:
		if active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(card)
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var s := card / 13
		var red := s == 1 or s == 2
		var ink := Color(0.8, 0.08, 0.1) if red else Color(0.08, 0.08, 0.1)
		if ghost:
			draw_rect(r, Color(1, 1, 1, 0.06))
			draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)
			return
		if back:
			draw_rect(r, Color(0.98, 0.97, 0.94))
			var inner := r.grow(-size.x * 0.08)
			draw_rect(inner, Color(0.62, 0.08, 0.12))
			for k in 9:
				var y := inner.position.y + inner.size.y * (k + 0.5) / 9.0
				draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(0.8, 0.25, 0.3), 2.0)
			draw_rect(inner, Color(0.3, 0.03, 0.05), false, 2.0)
			return
		var up := Vector2(0, -8) if active else Vector2.ZERO
		r.position += up
		draw_rect(r, Color(0.98, 0.97, 0.94) if not dim else Color(0.7, 0.69, 0.67))
		draw_rect(r, Color(1.0, 0.8, 0.1) if active else Color(0.3, 0.3, 0.3), false, 3.0 if active else 1.0)
		var font := ThemeDB.fallback_font
		var fs := int(size.y * 0.26)
		var txt: String = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][card % 13]
		draw_string(font, r.position + Vector2(3, fs), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		suit_shape(self, s, r.position + Vector2(size.x * 0.5, size.y * 0.6), size.x * 0.42, ink)

	## Maa kuviona keskipisteeseen c, koko w.
	static func suit_shape(ci: CanvasItem, s: int, c: Vector2, w: float, col: Color) -> void:
		var h := w * 0.5
		match s:
			0:  # risti: kolme palloa ja jalka
				for o in [Vector2(0, -0.32), Vector2(-0.3, 0.08), Vector2(0.3, 0.08)]:
					ci.draw_circle(c + o * w, h * 0.5, col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.0) * w, c + Vector2(-0.2, 0.5) * w,
					c + Vector2(0.2, 0.5) * w]), col)
			1:  # ruutu
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.55) * w, c + Vector2(0.4, 0) * w,
					c + Vector2(0, 0.55) * w, c + Vector2(-0.4, 0) * w]), col)
			2:  # hertta
				ci.draw_circle(c + Vector2(-0.24, -0.15) * w, h * 0.52, col)
				ci.draw_circle(c + Vector2(0.24, -0.15) * w, h * 0.52, col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.5, -0.06) * w, c + Vector2(0.5, -0.06) * w,
					c + Vector2(0, 0.52) * w]), col)
			3:  # pata: ylösalainen hertta ja jalka
				ci.draw_circle(c + Vector2(-0.24, 0.12) * w, h * 0.52, col)
				ci.draw_circle(c + Vector2(0.24, 0.12) * w, h * 0.52, col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.5, 0.03) * w, c + Vector2(0.5, 0.03) * w,
					c + Vector2(0, -0.55) * w]), col)
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0.1) * w, c + Vector2(-0.18, 0.55) * w,
					c + Vector2(0.18, 0.55) * w]), col)
