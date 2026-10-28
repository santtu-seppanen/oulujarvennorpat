extends RefCounted
## Hiirellä painettavat neliskanttiset automaattinapit (pokerin, hedelmäpelin ja pajatson alarivi). Nappi painaa
## samaa toimintoa (action) kuin sen näppäin, joten pelit lukevat hiiren ja näppäimistön samalla tavalla. Napin
## pitoa (hold) tarvitsevat pajatson kolikon jännitys ja peukalotuki: toiminto pysyy painettuna, kunnes hiiri nousee.

const MG := preload("res://scripts/mg_draw.gd")

## Nappi: {r: Rect2 (pelin virtuaalipikseleinä), label, sub, col, lit, blink, hold sekä action (painaa toiminnon) tai call (kutsuu funktiota)}
var list: Array = []
var _down := {}  # nappi (indeksi) -> [toiminto, kehys, hiiri nousi]
var _hover := -1


## Käsittelee hiiren tapahtuman; k = pelin skaala (virtuaalipikselit → ruutu). Palauttaa true, jos osui nappiin.
func input(event: InputEvent, k: float) -> bool:
	if event is InputEventMouseMotion:
		_hover = _at(event.position / k)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var i := _at(event.position / k)
			if i < 0:
				return false
			var b: Dictionary = list[i]
			if b.has("call"):
				(b["call"] as Callable).call()
				return true
			var a: String = b.get("action", "")
			if a != "" and not _down.has(i):
				Input.action_press(a)
				_down[i] = [a, Engine.get_process_frames(), false]
			return true
		for i in _down:
			_down[i][2] = true
	return false


func _at(p: Vector2) -> int:
	for i in list.size():
		if (list[i].r as Rect2).has_point(p):
			return i
	return -1


## Kutsutaan kerran kehyksessä pelin _processin lopussa: päästää napit, kun kehys on nähnyt painalluksen.
func tick() -> void:
	for i in _down.keys():
		var d: Array = _down[i]
		if Engine.get_process_frames() > d[1] and (d[2] or not list[i].get("hold", false)):
			Input.action_release(d[0])
			_down.erase(i)


func release_all() -> void:
	for i in _down:
		Input.action_release(_down[i][0])
	_down.clear()


func draw(ci: CanvasItem, font: Font, t: float) -> void:
	for i in list.size():
		var b: Dictionary = list[i]
		var lit: bool = b.get("lit", false)
		if lit and b.get("blink", false):
			lit = int(t * 3.0) % 2 == 0
		draw_button(ci, font, b.r, b.label, b.get("sub", ""), b.col, lit, _down.has(i), _hover == i)


## Yksi nappi: tummassa upotuksessa neliskanttinen, kiiltävä pinta; palaa kirkkaana, kun lit.
static func draw_button(ci: CanvasItem, font: Font, r: Rect2, label: String, sub: String, base: Color, lit: bool, pressed := false,
		hover := false) -> void:
	var col := base if lit else base.darkened(0.42)
	if hover and not lit:
		col = base.darkened(0.25)
	if lit:
		MG.glow(ci, r.get_center(), maxf(r.size.x, r.size.y) * 0.9, Color(base.r, base.g, base.b, 0.45))
	MG.box(ci, r.grow(6), Color(0.1, 0.09, 0.09), 8, 0, Color(0.38, 0.36, 0.34), 2)
	var off := 3.0 if pressed else 0.0
	var bt := Rect2(r.position + Vector2(0, off), r.size)
	MG.box(ci, bt, col.darkened(0.4), 6, 0, MG.OUTLINE, 2)
	MG.box(ci, Rect2(bt.position, Vector2(bt.size.x, bt.size.y - (3.0 if pressed else 7.0))), col, 6)
	ci.draw_rect(Rect2(bt.position + Vector2(6, 4), Vector2(bt.size.x - 12, 4)), Color(1, 1, 1, 0.3 if lit else 0.12))
	var fg := Color(0.1, 0.05, 0.02) if lit else Color(0.95, 0.9, 0.85, 0.85)
	var fs := clampi(int(r.size.x / maxf(float(label.length()), 4.0) * 1.35), 11, 22)
	var y := bt.position.y + bt.size.y * (0.5 if sub == "" else 0.42) + fs * 0.35
	ci.draw_string(font, Vector2(bt.position.x, y), label, HORIZONTAL_ALIGNMENT_CENTER, bt.size.x, fs, fg)
	if sub != "":
		ci.draw_string(font, Vector2(bt.position.x, bt.position.y + bt.size.y - 9), sub, HORIZONTAL_ALIGNMENT_CENTER, bt.size.x, 11, fg)
