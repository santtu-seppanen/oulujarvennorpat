extends Node
## Aurinko ja pelin kello: auringon paikka lasketaan NOAA:n algoritmilla aloituspaikalle (64.432089 N,
## 26.886448 E) pelin päivämäärästä ja kellonajasta (Suomen aika, kesäaika maaliskuun viimeisestä sunnuntaista
## lokakuun viimeiseen). Kello kulkee 60 kertaa todellista nopeammin (pelivuorokausi 24 minuuttia), T kelaa
## 20-kertaisesti, ja päivämäärä vaihtuu keskiyöllä, joten aurinko laskee joka ilta oikeaan aikaan ja oikeaan
## suuntaan. Esim. 7.7. aurinko koskettaa Oulujärven horisonttia klo 23.24 suunnassa 334° (NNW) kuten
## valokuvassa 20260707_232437.
##
## Ohjaa DirectionalLight3D:tä (suunta, väri, voimakkuus, varjot), taivasvarjostinta (sävyt, auringon kiekko,
## iltarusko, tähdet) ja ympäristön usvaa ja ambienttia.

const LAT := 64.432089
const LON := 26.886448
const TIME_SCALE := 60.0
const FAST := 20.0
## Ilmakehän taittuminen nostaa auringon horisontissa noin puoli astetta (näennäinen korkeus).
const SUN_RADIUS := 0.27

## Alkuhetket valikkoon: [nimi, kuukausi, päivä, tunti, minuutti]; "now" = laitteen kello.
const PRESETS := [
	["Kesäilta 7.7. klo 21.30", 7, 7, 21, 30],
	["Juhannusaatto klo 22.00", 6, 19, 22, 0],
	["Elokuun ilta 4.8. klo 19.30", 8, 4, 19, 30],
	["Nyt (laitteen kello)", 0, 0, 0, 0],
]

var light: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
## Pelin hetki: Unix-aika sekunteina UTC (päivämäärä ja kellonaika samassa).
var t_utc := 0.0
var fast := false
var key_fast := false  # T pohjassa tällä koneella
var remote_fast := false  # moninpeli: joku muu kelaa
var altitude := 0.0  # astetta, näennäinen (taittuminen mukana)
var azimuth := 0.0   # astetta pohjoisesta myötäpäivään
var sun_dir := Vector3.UP  # suunta aurinkoon pelin kehyksessä (x itään, z etelään)
var max_shadow := 180.0
var shadows_allowed := true

var _sky_t := 0.0
var _today_cache := {}


func _ready() -> void:
	start_preset(0)


func start_preset(i: int) -> void:
	var p: Array = PRESETS[i]
	if p[1] == 0:
		t_utc = Time.get_unix_time_from_system()
	else:
		var y: int = Time.get_datetime_dict_from_system().year
		t_utc = _local_to_utc(y, p[1], p[2], p[3], p[4])
	_today_cache.clear()
	_update(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_T and not event.echo:
		key_fast = event.pressed


func _process(delta: float) -> void:
	if not can_process():  # moninpelissä kello kulkee myös valikon ollessa auki
		return
	fast = key_fast or remote_fast
	t_utc += delta * TIME_SCALE * (FAST if fast else 1.0)
	_update(false, delta)


# --- Aika ----------------------------------------------------------------------------------------------------

## Suomen aikavyöhyke annettuna UTC-hetkenä: +3 h kesäaikana, muuten +2 h.
static func utc_offset(t: float) -> int:
	var d := Time.get_datetime_dict_from_unix_time(int(t))
	var start := _last_sunday(d.year, 3) + 3600.0  # 01.00 UTC
	var end := _last_sunday(d.year, 10) + 3600.0
	return 3 if t >= start and t < end else 2


static func _last_sunday(y: int, m: int) -> float:
	var t := Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": 31, "hour": 0, "minute": 0, "second": 0})
	var wd: int = Time.get_datetime_dict_from_unix_time(int(t)).weekday  # 0 = sunnuntai
	return t - wd * 86400.0


static func _local_to_utc(y: int, mo: int, d: int, h: int, mi: int) -> float:
	var t := Time.get_unix_time_from_datetime_dict({"year": y, "month": mo, "day": d, "hour": h, "minute": mi, "second": 0})
	t -= 3 * 3600.0
	return t - (utc_offset(t) - 3) * 3600.0


## Paikallinen aika sanakirjana (year, month, day, hour, minute).
func local() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(int(t_utc) + utc_offset(t_utc) * 3600)


func clock_text() -> String:
	var d := local()
	return "%d.%d. klo %02d.%02d" % [d.day, d.month, d.hour, d.minute]


## Tämän päivän auringonlasku ja -nousu paikallisena kellonaikana ("–" jos aurinko ei laske / nouse).
func today() -> Dictionary:
	var d := local()
	var key := "%d-%d-%d" % [d.year, d.month, d.day]
	if not _today_cache.has(key):
		var midnight := _local_to_utc(d.year, d.month, d.day, 0, 0)
		var rise := "–"
		var set_ := "–"
		var prev := position_at(midnight).x
		for m in range(2, 24 * 60 + 1, 2):
			var a := position_at(midnight + m * 60.0).x
			var hhmm := "%02d.%02d" % [m / 60 % 24, m % 60]
			if prev < -SUN_RADIUS and a >= -SUN_RADIUS:
				rise = hhmm
			elif prev >= -SUN_RADIUS and a < -SUN_RADIUS:
				set_ = hhmm
			prev = a
		_today_cache = {key: {"rise": rise, "set": set_}}
	return _today_cache[key]


# --- Auringon paikka (NOAA Solar Calculator) ------------------------------------------------------------------

## (näennäinen korkeus, atsimuutti) asteina UTC-hetkellä t.
static func position_at(t: float) -> Vector2:
	var jd := t / 86400.0 + 2440587.5
	var T := (jd - 2451545.0) / 36525.0
	var L0 := fposmod(280.46646 + T * (36000.76983 + T * 0.0003032), 360.0)
	var M := 357.52911 + T * (35999.05029 - 0.0001537 * T)
	var e := 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
	var Mr := deg_to_rad(M)
	var C := sin(Mr) * (1.914602 - T * (0.004817 + 0.000014 * T)) + sin(2.0 * Mr) * (0.019993 - 0.000101 * T) \
		+ sin(3.0 * Mr) * 0.000289
	var om := deg_to_rad(125.04 - 1934.136 * T)
	var lam := deg_to_rad(L0 + C - 0.00569 - 0.00478 * sin(om))
	var eps0 := 23.0 + (26.0 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60.0) / 60.0
	var eps := deg_to_rad(eps0 + 0.00256 * cos(om))
	var dec := asin(sin(eps) * sin(lam))
	var y := pow(tan(eps / 2.0), 2.0)
	var L0r := deg_to_rad(L0)
	var eot := 4.0 * rad_to_deg(y * sin(2.0 * L0r) - 2.0 * e * sin(Mr) + 4.0 * e * y * sin(Mr) * cos(2.0 * L0r)
		- 0.5 * y * y * sin(4.0 * L0r) - 1.25 * e * e * sin(2.0 * Mr))
	var minutes := fposmod(t, 86400.0) / 60.0
	var tst := fposmod(minutes + eot + 4.0 * LON, 1440.0)
	var ha := deg_to_rad(tst / 4.0 - 180.0)
	var lat := deg_to_rad(LAT)
	var zen := acos(clampf(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha), -1.0, 1.0))
	var az := fposmod(rad_to_deg(atan2(sin(ha), cos(ha) * sin(lat) - tan(dec) * cos(lat))) + 180.0, 360.0)
	var alt := 90.0 - rad_to_deg(zen)
	# Taittuminen (Sæmundsson), vain horisontin tuntumassa merkitsevä.
	if alt > -2.0:
		alt += 1.02 / tan(deg_to_rad(alt + 10.3 / (maxf(alt, -1.9) + 5.11))) / 60.0
	return Vector2(alt, az)


# --- Valaistus ------------------------------------------------------------------------------------------------

func _update(force: bool, delta := 0.0) -> void:
	var p := position_at(t_utc)
	altitude = p.x
	azimuth = p.y
	var a := deg_to_rad(altitude)
	var z := deg_to_rad(azimuth)
	sun_dir = Vector3(sin(z) * cos(a), sin(a), -cos(z) * cos(a))
	if light == null:
		return
	# Valo tulee auringosta; horisontin alla kuu-/hämärävalo hyvin heikkona ylhäältä vastakkaiselta puolelta.
	var day := smoothstep(-SUN_RADIUS, 6.0, altitude)
	var warm := 1.0 - smoothstep(1.0, 18.0, altitude)
	var src := sun_dir if altitude > -SUN_RADIUS else Vector3(-sun_dir.x, 0.6, -sun_dir.z).normalized()
	light.look_at_from_position(Vector3.ZERO, -src, Vector3.UP if absf(src.y) < 0.99 else Vector3.FORWARD)
	var noon_col := Color(1.0, 0.95, 0.86)
	var low_col := Color(1.0, 0.5, 0.22)
	light.light_color = noon_col.lerp(low_col, warm) if altitude > -SUN_RADIUS else Color(0.55, 0.62, 0.8)
	light.light_energy = 0.05 + 1.25 * day if altitude > -SUN_RADIUS else 0.04
	light.shadow_enabled = shadows_allowed and altitude > 0.5
	light.directional_shadow_max_distance = max_shadow

	# Taivas: väri korkeuden mukaan; hämärä (siviilihämärä -6°, merenkulku -12°) tummentaa.
	var twi := smoothstep(-12.0, 2.0, altitude)
	var top := Color(0.025, 0.035, 0.08).lerp(Color(0.18, 0.3, 0.55), twi).lerp(Color(0.22, 0.42, 0.78), day)
	var hor := Color(0.04, 0.05, 0.09).lerp(Color(0.55, 0.55, 0.62), twi).lerp(Color(0.8, 0.85, 0.9), day * (1.0 - warm * 0.6))
	var glow := Color(1.0, 0.4, 0.1) * 1.7 * (smoothstep(-9.0, -0.5, altitude) * (1.0 - smoothstep(4.0, 16.0, altitude)))
	var disk := Color(1.0, 0.98, 0.92).lerp(Color(1.0, 0.38, 0.1), warm)
	_sky_t -= delta
	if force or _sky_t <= 0.0:
		_sky_t = 0.2  # säteilykartta päivittyy vaiheittain, ei joka ruutu
		if sky_mat != null:
			sky_mat.set_shader_parameter("top_color", top)
			sky_mat.set_shader_parameter("horizon_color", hor)
			sky_mat.set_shader_parameter("ground_color", hor.darkened(0.45))
			sky_mat.set_shader_parameter("sun_dir", sun_dir)
			sky_mat.set_shader_parameter("sun_color", disk)
			sky_mat.set_shader_parameter("glow_color", glow)
			sky_mat.set_shader_parameter("night", 1.0 - smoothstep(-14.0, -6.0, altitude))
			sky_mat.set_shader_parameter("cloud_light", 0.12 + 0.88 * twi)
		if env != null:
			env.fog_light_color = Color(0.06, 0.07, 0.1).lerp(Color(0.72, 0.79, 0.87), twi).lerp(Color(0.95, 0.66, 0.5), warm * twi * 0.55)
			env.fog_sun_scatter = 0.25 + 0.5 * warm
			env.ambient_light_energy = 0.15 + 0.85 * twi
			env.tonemap_exposure = 1.05 + 0.6 * (1.0 - twi)
