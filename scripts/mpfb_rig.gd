extends RefCounted
## MPFB/MakeHuman-hahmot (tools/blender/luo_hahmot.py): ruumiintyypin valinta, luuston siistiminen ja Quaterniuksen
## UAL-animaatioiden sovitus MPFB-luurankoon. Luuranko on leivottu T-asentoon kuten Quaterniuksen, joten animaatio
## siirtyy maailmankierron muutoksena lepoasennosta (global delta), ja luuakselien erot (roll) sulavat siihen.

const DIR := "res://assets/characters/mpfb/"
const ANIM_FILE := "res://assets/characters/UAL1_Standard.glb"
const KINDS := ["m_norm", "m_heavy", "m_slim", "m_old", "f_norm", "f_slim", "f_heavy", "f_old", "f_bust"]
const TEX := DIR + "tex/"
## Runkojen pituudet (m, luo_hahmot.py:n loki); look.height skaalaa niistä.
const HEIGHT := {"m_norm": 1.793, "m_heavy": 1.781, "m_slim": 1.736, "m_old": 1.724, "f_norm": 1.603, "f_slim": 1.557, "f_heavy": 1.603, "f_old": 1.567, "f_bust": 1.609}
## Jalkapohjan nosto (m, mallin mittakaava) animaatioryhmittäin, mitattu `mpfb_hahmot.tscn maa` (alin jalan/kengän piste y = 0:n alla).
## Avain on animaation nimen alku, "" = muut jaloilla tehtävät. Istuessa, ajaessa ja uidessa ei nostoa (sovitus kontaktilla).
const SOLE := {
	"m_norm": {"": 0.034, "Walk": 0.043, "Jog": 0.037, "Sprint": 0.012, "Crouch": 0.009},
	"m_heavy": {"": 0.033, "Walk": 0.041, "Jog": 0.035, "Sprint": 0.010, "Crouch": 0.010},
	"m_slim": {"": 0.032, "Walk": 0.040, "Jog": 0.036, "Sprint": 0.012, "Crouch": 0.008},
	"m_old": {"": 0.030, "Walk": 0.035, "Jog": 0.025, "Sprint": 0.002, "Crouch": 0.011},
	"f_norm": {"": 0.022, "Walk": 0.033, "Jog": 0.025, "Sprint": 0.004, "Crouch": 0.004},
	"f_slim": {"": 0.020, "Walk": 0.032, "Jog": 0.024, "Sprint": 0.004, "Crouch": 0.004},
	"f_heavy": {"": 0.021, "Walk": 0.033, "Jog": 0.024, "Sprint": 0.003, "Crouch": 0.004},
	"f_bust": {"": 0.022, "Walk": 0.033, "Jog": 0.025, "Sprint": 0.004, "Crouch": 0.004},  # kuten f_norm, mittaa tarkistuksella
	"f_old": {"": 0.020, "Walk": 0.030, "Jog": 0.022, "Sprint": 0.001, "Crouch": 0.004},
}
## look.hair (Quaternius-nimi) -> MPFB-hiusverkko (glb:n verkon nimi). "" = kalju.
const HAIR := {
	"Hair_SimpleParted": "short02", "Hair_Buzzed": "short03", "Hair_BuzzedFemale": "short04", "Hair_Long": "long01",
	"Hair_Buns": "bob02", "long": "long01", "short": "short02", "parted": "short02", "bob": "bob02", "ponytail": "ponytail01",
}
## look.shoe -> MPFB-kenkä (1..6)
const SHOE := {"lenkkari": 5, "saapas": 1, "tyokenka": 1, "kavelykenka": 1, "kuukenka": 5, "kumisaapas": 1}
## Runkoon ja päähän kiinnitettyjen asusteiden luut: paikka on absoluuttinen Quaterniuksen mukaan (attach_shift).
const CORE_BONES := ["Head", "neck_01", "spine_03", "spine_02", "spine_01", "pelvis"]
const LEAF_FINGERS := ["thumb", "index", "middle", "ring", "pinky"]

static var _libs := {}  # tyyppi -> AnimationLibrary
static var _src_lib: AnimationLibrary
static var _src_rest := {}  # luu -> [parent-nimi, rest-kierto paikallinen, rest-paikka]
static var _src_order: Array = []
static var _src_origin := {}  # luu -> rest-origo mallin avaruudessa


static func enabled(look: Dictionary) -> bool:
	return bool(look.get("mpfb", true))


## Ruumiintyyppi: sukupuoli + vartalo (belly, bulk) ja ikä.
static func kind_for(look: Dictionary) -> String:
	if look.has("mpfb_kind"):
		return String(look.mpfb_kind)
	var sex := "f" if look.get("model", "male") == "female" else "m"
	var belly := float(look.get("belly", 0.0))
	var bulk := float(look.get("bulk", 0.0))
	var shape := "norm"
	if bool(look.get("old", false)) or look.has("perm_col"):
		shape = "old"
	elif belly >= 0.55 or bulk >= 0.45:
		shape = "heavy"
	elif belly <= 0.05 and bulk <= -0.2:
		shape = "slim"
	elif sex == "f" and bulk >= 0.3:
		shape = "heavy"
	return "%s_%s" % [sex, shape]


static func instantiate(kind: String) -> Node3D:
	var s: Node3D = load(DIR + kind + ".glb").instantiate()
	var sk: Skeleton3D = s.find_children("*", "Skeleton3D")[0]
	_fix_skeleton(sk)
	# MPFB-runko on origoon nähden eri syvyydessä kuin Quaterniuksen (lantio 6 cm edessä): siirretään luusto (ja sen verkot)
	# niin, että lantio on Quaterniuksen paikalla. Hahmon pyörähdys, istuinpaikat ja jalan asettelu pysyvät samoina.
	_load_source()
	var pel := sk.get_bone_global_rest(sk.find_bone("pelvis")).origin
	sk.position = Vector3(0.0, 0.0, (_src_origin["pelvis"] as Vector3).z - pel.z)
	return s


## Luunimet kuten Quaterniuksella (root, Head) ja lehtiluut (ball_leaf, sormien 04_leaf) kosketuslaskentaa varten.
static func _fix_skeleton(sk: Skeleton3D) -> void:
	for pair in [["Root", "root"], ["head", "Head"]]:
		var i := sk.find_bone(pair[0])
		if i >= 0:
			sk.set_bone_name(i, pair[1])
			# Skinin sidonnat viittaavat luuhun nimellä: päivitä ne, muuten verkko jää origoon.
			for mi in sk.get_children():
				if mi is MeshInstance3D and (mi as MeshInstance3D).skin != null:
					var skin: Skin = (mi as MeshInstance3D).skin
					for b in skin.get_bind_count():
						if skin.get_bind_name(b) == pair[0]:
							skin.set_bind_name(b, pair[1])
	for lr in ["_l", "_r"]:
		_add_leaf(sk, "ball" + lr, "ball_leaf" + lr, 0.075)
		for f in LEAF_FINGERS:
			var l3 := sk.find_bone("%s_03%s" % [f, lr])
			if l3 >= 0:
				var parent_len := sk.get_bone_rest(l3).origin.length()
				_add_leaf(sk, "%s_03%s" % [f, lr], "%s_04_leaf%s" % [f, lr], parent_len * 0.9)


static func _add_leaf(sk: Skeleton3D, parent: String, leaf: String, length: float) -> void:
	var p := sk.find_bone(parent)
	if p < 0 or sk.find_bone(leaf) >= 0:
		return
	sk.add_bone(leaf)
	var i := sk.find_bone(leaf)
	sk.set_bone_parent(i, p)
	sk.set_bone_rest(i, Transform3D(Basis(), Vector3(0, length, 0)))
	sk.set_bone_pose_position(i, Vector3(0, length, 0))


## UAL-animaatiot sovitettuna tämän tyypin luurankoon (kerran per tyyppi).
static func library(kind: String, model: Node3D, sk: Skeleton3D, base: AnimationLibrary) -> AnimationLibrary:
	if _libs.has(kind):
		return _libs[kind]
	_load_source()
	var skpath := str(model.get_path_to(sk))
	var n := sk.get_bone_count()
	# MPFB: rest-kierrot maailmassa (lehtiluut mukana, ne perivät vanhemmaltaan).
	var m_par: Array[int] = []
	var m_rest_local: Array[Quaternion] = []
	var m_rg: Array[Quaternion] = []
	var m_name: Array[String] = []
	for i in n:
		m_par.append(sk.get_bone_parent(i))
		m_rest_local.append(sk.get_bone_rest(i).basis.get_rotation_quaternion())
		m_name.append(sk.get_bone_name(i))
	for i in n:
		var p := m_par[i]
		m_rg.append((m_rg[p] if p >= 0 else Quaternion.IDENTITY) * m_rest_local[i])
	# Lähde: rest-kierrot maailmassa.
	var s_rg := {}
	for nm: String in _src_order:
		var info: Array = _src_rest[nm]
		var p: String = info[0]
		s_rg[nm] = (s_rg[p] if p != "" else Quaternion.IDENTITY) * (info[1] as Quaternion)
	# Pelvis-paikan siirtymä: lähteen lantio vs MPFB:n lantio (korkeuksien suhde).
	var pel_u: Vector3 = _src_rest["pelvis"][2]
	var pel_m := sk.get_bone_rest(sk.find_bone("pelvis")).origin
	var k_pos := pel_m.length() / maxf(pel_u.length(), 0.001)
	var root_u: Quaternion = s_rg["root"]
	var root_m: Quaternion = m_rg[sk.find_bone("root")]
	var lib := AnimationLibrary.new()
	for an in base.get_animation_list():
		var src: Animation = base.get_animation(an)
		var dst := Animation.new()
		dst.length = src.length
		dst.loop_mode = src.loop_mode
		var rot_track := {}
		var pos_track := -1
		for t in src.get_track_count():
			var path := str(src.track_get_path(t))
			var bn := path.get_slice(":", 1)
			if src.track_get_type(t) == Animation.TYPE_ROTATION_3D:
				rot_track[bn] = t
			elif src.track_get_type(t) == Animation.TYPE_POSITION_3D and bn == "pelvis":
				pos_track = t
		var steps := maxi(int(ceil(src.length * 30.0)), 1)
		var tracks: Array[int] = []
		var is_src: Array[bool] = []
		for i in n:
			var has: bool = s_rg.has(m_name[i])
			is_src.append(has)
			var ti := -1
			if has:
				ti = dst.add_track(Animation.TYPE_ROTATION_3D)
				dst.track_set_path(ti, "%s:%s" % [skpath, m_name[i]])
				dst.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
			tracks.append(ti)
		var ptrack := -1
		if pos_track >= 0:
			ptrack = dst.add_track(Animation.TYPE_POSITION_3D)
			dst.track_set_path(ptrack, "%s:pelvis" % skpath)
		for s in steps + 1:
			var tm := minf(float(s) / 30.0, src.length)
			# lähteen paikalliset kierrot -> maailman kierrot
			var gu := {}
			for nm: String in _src_order:
				var info: Array = _src_rest[nm]
				var lq: Quaternion = info[1]
				if rot_track.has(nm):
					lq = src.rotation_track_interpolate(rot_track[nm], tm)
				var p: String = info[0]
				gu[nm] = (gu[p] if p != "" else Quaternion.IDENTITY) * lq
			var gm: Array[Quaternion] = []
			for i in n:
				var q: Quaternion
				if is_src[i]:
					q = (gu[m_name[i]] as Quaternion) * (s_rg[m_name[i]] as Quaternion).inverse() * m_rg[i]
				else:
					q = (gm[m_par[i]] if m_par[i] >= 0 else Quaternion.IDENTITY) * m_rest_local[i]
				gm.append(q)
			for i in n:
				if tracks[i] < 0:
					continue
				var pq: Quaternion = gm[m_par[i]] if m_par[i] >= 0 else Quaternion.IDENTITY
				dst.rotation_track_insert_key(tracks[i], tm, (pq.inverse() * gm[i]).normalized())
			if ptrack >= 0:
				var pu := src.position_track_interpolate(pos_track, tm)
				# lähteen siirtymä lepopaikasta maailmaan, skaalaus jalkojen pituuden suhteessa, MPFB:n juuren kehykseen
				var d_world := root_u * (pu - pel_u)
				dst.position_track_insert_key(ptrack, tm, pel_m + root_m.inverse() * d_world * k_pos)
		lib.add_animation(an, dst)
	_libs[kind] = lib
	return lib


static func _load_source() -> void:
	if _src_lib != null:
		return
	var scene: Node = load(ANIM_FILE).instantiate()
	var usk: Skeleton3D = scene.find_children("*", "Skeleton3D")[0]
	for i in usk.get_bone_count():
		var p := usk.get_bone_parent(i)
		var nm := usk.get_bone_name(i)
		_src_order.append(nm)
		_src_rest[nm] = [usk.get_bone_name(p) if p >= 0 else "", usk.get_bone_rest(i).basis.get_rotation_quaternion(), usk.get_bone_rest(i).origin]
		_src_origin[nm] = usk.get_bone_global_rest(i).origin
	_src_lib = AnimationLibrary.new()
	scene.free()


## Näytä vain valitut osat: hius (HAIR-avain), kenkä, paita ja housut. Palauttaa {mesh-nimi: MeshInstance3D}.
static func meshes(sk: Skeleton3D) -> Dictionary:
	var out := {}
	for mi in sk.get_children():
		if mi is MeshInstance3D:
			out[String(mi.name).trim_prefix("Human_")] = mi
	return out


## Mesh-nimestä tekstuuri jaetusta kansiosta (glb:ssä ei ole kuvia).
static func texture_for(mesh_name: String, kind: String) -> Texture2D:
	var f := ""
	if mesh_name == "Body":
		f = "skin_%s.jpg" % kind
	elif mesh_name.begins_with("eyebrow"):
		f = "eyebrow001.png"
	elif mesh_name.begins_with("eyelashes"):
		f = "eyelashes02.png"
	elif mesh_name == "low-poly":
		f = "brown_eye.png"
	elif mesh_name.begins_with("shoes"):
		f = mesh_name + "_diffuse.jpg"
	elif mesh_name.begins_with("Shirt") or mesh_name.begins_with("Pants"):
		return null
	else:
		f = mesh_name + "_diffuse.png"
	var path := TEX + f
	return load(path) if ResourceLoader.exists(path) else null


static func mesh_key(mi: MeshInstance3D) -> String:
	return String(mi.name).trim_prefix("Human_")


## Pään ja kaulan asusteiden (lippis, lasit, hatut) mitat on sovitettu Quaterniuksen hahmomallin (male/female) luiden
## lepopaikkoihin; MPFB:n pääluu on eri korkeudella. Kohde on absoluuttinen (Quaterniuksen paikka), joten siirtymä on
## Q-luun paikka - M-luun paikka (luuston siirto mukana).
static var _model_origins := {}  # "male"/"female" -> {luu: origo}


static func _origins_for(sex: String) -> Dictionary:
	if _model_origins.has(sex):
		return _model_origins[sex]
	var s: Node = load("res://assets/characters/Superhero_%s_FullBody.gltf" % sex.capitalize()).instantiate()
	var usk: Skeleton3D = s.find_children("*", "Skeleton3D")[0]
	var d := {}
	for b in CORE_BONES:
		d[b] = usk.get_bone_global_rest(usk.find_bone(b)).origin
	s.free()
	_model_origins[sex] = d
	return d


static func attach_shift(sk: Skeleton3D, bone: String, kind: String) -> Vector3:
	if not bone in CORE_BONES:
		return Vector3.ZERO
	var i := sk.find_bone(bone)
	if i < 0:
		return Vector3.ZERO
	var q: Vector3 = _origins_for("female" if kind.begins_with("f") else "male")[bone]
	# Quaternius-hahmo on skaalattu look.height / 1,8 ja MPFB-hahmo look.height / runkopituus: Q-paikka muunnetaan MPFB:n mittakaavaan.
	q *= float(HEIGHT.get(kind, 1.8)) / 1.8
	return q - sk.transform * sk.get_bone_global_rest(i).origin
