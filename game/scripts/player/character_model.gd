class_name CharacterModel
extends Node3D
## Personnage articulé en cel-shading (agent 03 / 05) : tronc, tête, béret, deux bras, deux jambes.
## Partagé par les joueurs et les compagnons IA. L'animation est procédurale :
##  - marche / course : les jambes et les bras oscillent en opposition, la fréquence et
##    l'amplitude suivent la vitesse réellement mesurée (fonctionne aussi sur un client qui ne
##    simule pas ce corps, puisqu'on mesure le déplacement de l'objet) ;
##  - portage : les deux bras se lèvent pour tenir la caisse au-dessus de la tête ;
##  - saut : jambes repliées, bras écartés ;
##  - repos : légère respiration.
## Hauteur totale ≈ 1,85 m (capsule de collision du joueur : 1,8 m).

signal step_taken(side: int)

const SHOULDER_Y := 1.4
const HIP_Y := 0.84
const THIGH := 0.43
const SHIN := 0.41
const UPPER_ARM := 0.35
const FOREARM := 0.35
const ARM_LENGTH := UPPER_ARM + FOREARM
const LEG_LENGTH := THIGH + SHIN
const SKIN := Color(0.96, 0.8, 0.66)

## Pose imposée (captures, tests) : {"speed": m/s, "carrying": bool, "airborne": bool}. Vide = automatique.
var pose_override := {}

var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _ankle_l: Node3D
var _ankle_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D
var _eyes: Array[Node3D] = []
var _blink_t := 3.0
var _was_air := false
var _land_t := 0.0
var _last_yaw_body := 0.0
var _turn_rate := 0.0
var _idle_t := 0.0
## Humeur : "normal", "clench" (jambes serrées, penché : mission 07), "hunched" ; tremblement 0..1 (pression, froid, peur).
var mood := "normal"
var tremble := 0.0
## Angles courants (lisibles par les tests) : cuisse, genou, bras, coude.
var knee_angle_l := 0.0
var elbow_angle_l := 0.0
var hips_height := HIP_Y
var _phase := 0.0
var _last_half := 0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _carry_blend := 0.0
var _air_blend := 0.0
var _t := 0.0
var leg_angle_l := 0.0
var arm_angle_l := 0.0
var carrying := false
var airborne := false


## `style` (tous les champs sont facultatifs) : hair (Color), hair_style ("short", "bun", "long", "bald"), moustache / beard (Color),
## glasses (bool), headgear ("beret", "cap", "cap_back", "headphones", "scarf", "straw", "kepi", "none"), apron / vest / scarf (Color),
## belt (Color), skin (Color).
static func make(shirt: Color, trousers: Color = Color(0.2, 0.22, 0.3), hat: Color = Color(0.15, 0.17, 0.25), style: Dictionary = {}) -> CharacterModel:
	var m := CharacterModel.new()
	m.name = "Modele"
	m.scale = Vector3.ONE * 0.93     # tête un peu grosse, mais pas plus haut qu'une porte
	m._style = style
	m._build(shirt, trousers, hat)
	return m


static var _mats := {}
var _style := {}
var detail_parts := 0               ## nombre de parties de détail (visage, vêtements, accessoires) : lisible par les tests


## Matériau toon partagé par couleur ; les petits détails (yeux, boutons) n'ont pas de contour.
func _mat(color: Color, outline := true) -> ShaderMaterial:
	var key := "%s|%s" % [color.to_html(false), outline]
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("couleur", color)
	mat.set_shader_parameter("rim_force", 0.15)
	if outline:
		mat.next_pass = preload("res://assets/materials/contour_personnage.tres")
	_mats[key] = mat
	return mat


func _mesh(parent: Node3D, mesh: PrimitiveMesh, color: Color, pos: Vector3, scale := Vector3.ONE, outline := true) -> MeshInstance3D:
	mesh.material = _mat(color, outline)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


## Petite pièce de détail : boîte, sphère ou cylindre sans contour (sauf `outline`), comptée dans `detail_parts`.
func _d(parent: Node3D, kind: String, size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO, outline := false) -> MeshInstance3D:
	var mesh: PrimitiveMesh
	match kind:
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = size.x
			sm.height = size.x * 2.0
			sm.radial_segments = 8
			sm.rings = 4
			mesh = sm
			var mi0 := _mesh(parent, mesh, color, pos, Vector3(1, size.y / maxf(size.x, 0.0001), size.z / maxf(size.x, 0.0001)), outline)
			mi0.rotation = rot
			detail_parts += 1
			return mi0
		"cyl":
			var cm := CylinderMesh.new()
			cm.top_radius = size.x
			cm.bottom_radius = size.z if size.z > 0.0 else size.x
			cm.height = size.y
			cm.radial_segments = 10
			cm.rings = 1
			mesh = cm
		"torus":
			var tm := TorusMesh.new()
			tm.inner_radius = size.x
			tm.outer_radius = size.y
			tm.rings = 12
			tm.ring_segments = 6
			mesh = tm
		_:
			var bm := BoxMesh.new()
			bm.size = size
			mesh = bm
	var mi := _mesh(parent, mesh, color, pos, Vector3.ONE, outline)
	mi.rotation = rot
	detail_parts += 1
	return mi


## Jambe à deux segments : pivot de hanche (cuisse), genou, cheville (pied) ; renvoie [hanche, genou, cheville].
func _leg(parent: Node3D, pivot: Vector3, color: Color, shoe: Color, cuff: Color) -> Array:
	var hip := Node3D.new()
	hip.position = pivot
	parent.add_child(hip)
	var thigh := CapsuleMesh.new()
	thigh.radius = 0.115
	thigh.height = THIGH
	thigh.radial_segments = 8
	thigh.rings = 2
	_mesh(hip, thigh, color, Vector3(0, -THIGH * 0.5, 0))
	var knee := Node3D.new()
	knee.position = Vector3(0, -THIGH, 0)
	hip.add_child(knee)
	_mesh(knee, _ball(0.105), color, Vector3.ZERO)
	var shin := CapsuleMesh.new()
	shin.radius = 0.1
	shin.height = SHIN
	shin.radial_segments = 8
	shin.rings = 2
	_mesh(knee, shin, color, Vector3(0, -SHIN * 0.5, 0))
	var ankle := Node3D.new()
	ankle.position = Vector3(0, -SHIN, 0)
	knee.add_child(ankle)
	_d(ankle, "cyl", Vector3(0.112, 0.07, 0.112), cuff, Vector3(0, 0.07, 0), Vector3.ZERO, true)
	var foot := SphereMesh.new()
	foot.radius = 0.126
	foot.height = 0.252
	foot.radial_segments = 8
	foot.rings = 4
	_mesh(ankle, foot, shoe, Vector3(0, -0.01, -0.06), Vector3(1.1, 0.78, 1.75))                 # basket épaisse (style « street »)
	_d(ankle, "box", Vector3(0.27, 0.06, 0.46), Color(0.96, 0.94, 0.88), Vector3(0, -0.095, -0.075), Vector3.ZERO, true)   # semelle blanche
	_d(ankle, "sphere", Vector3(0.1, 0.07, 0.1), shoe.lightened(0.35), Vector3(0, 0.02, -0.19))  # bout renforcé
	_d(ankle, "box", Vector3(0.235, 0.02, 0.07), shoe.lightened(0.45), Vector3(0, 0.01, -0.01))   # lacets
	return [hip, knee, ankle]


## Bras à deux segments : épaule (bras), coude, poignet (main) ; renvoie [épaule, coude].
func _arm(parent: Node3D, pivot: Vector3, color: Color, skin: Color, cuff: Color) -> Array:
	var sh := Node3D.new()
	sh.position = pivot
	parent.add_child(sh)
	_mesh(sh, _ball(0.095), color, Vector3.ZERO)
	var up := CapsuleMesh.new()
	up.radius = 0.085
	up.height = UPPER_ARM
	up.radial_segments = 8
	up.rings = 2
	_mesh(sh, up, color, Vector3(0, -UPPER_ARM * 0.5, 0))
	var elbow := Node3D.new()
	elbow.position = Vector3(0, -UPPER_ARM, 0)
	sh.add_child(elbow)
	_mesh(elbow, _ball(0.08), color, Vector3.ZERO)
	var fore := CapsuleMesh.new()
	fore.radius = 0.075
	fore.height = FOREARM
	fore.radial_segments = 8
	fore.rings = 2
	_mesh(elbow, fore, color, Vector3(0, -FOREARM * 0.5, 0))
	_d(elbow, "cyl", Vector3(0.085, 0.07, 0.085), cuff, Vector3(0, -FOREARM + 0.06, 0), Vector3.ZERO, true)
	_mesh(elbow, _ball(0.09), skin, Vector3(0, -FOREARM - 0.03, 0))
	var side := 1.0 if pivot.x > 0.0 else -1.0
	_d(elbow, "sphere", Vector3(0.04, 0.04, 0.04), skin, Vector3(side * 0.07, -FOREARM - 0.04, -0.06))
	return [sh, elbow]


func _ball(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m


func _build(shirt: Color, trousers: Color, hat: Color) -> void:
	_hips = Node3D.new()
	_hips.name = "Bassin"
	_hips.position = Vector3(0, HIP_Y, 0)
	add_child(_hips)
	# Jambes (pivot à la hanche, relatif au monde du modèle : on les range sous le bassin).
	var skin: Color = _style.get("skin", SKIN)
	var shoes: Color = _style.get("shoes", Color(0.18, 0.12, 0.1))
	var ll := _leg(_hips, Vector3(-0.15, 0.0, 0), trousers, shoes, trousers.darkened(0.2))
	var lr := _leg(_hips, Vector3(0.15, 0.0, 0), trousers, shoes, trousers.darkened(0.2))
	_leg_l = ll[0]
	_knee_l = ll[1]
	_ankle_l = ll[2]
	_leg_r = lr[0]
	_knee_r = lr[1]
	_ankle_r = lr[2]
	# Tronc, tête et bras pivotent ensemble (penché en course).
	_torso = Node3D.new()
	_torso.name = "Tronc"
	_hips.add_child(_torso)
	var body := CapsuleMesh.new()
	body.radius = 0.25
	body.height = 0.84
	body.radial_segments = 10
	body.rings = 3
	_mesh(_torso, body, shirt, Vector3(0, 0.31, 0), Vector3(1.0, 1.0, 0.78))
	var al := _arm(_torso, Vector3(-0.33, SHOULDER_Y - HIP_Y, 0), shirt, skin, shirt.lightened(0.25))
	var ar := _arm(_torso, Vector3(0.33, SHOULDER_Y - HIP_Y, 0), shirt, skin, shirt.lightened(0.25))
	_arm_l = al[0]
	_elbow_l = al[1]
	_arm_r = ar[0]
	_elbow_r = ar[1]
	_head = Node3D.new()
	_head.name = "Tete"
	_head.position = Vector3(0, 0.9, 0)
	_torso.add_child(_head)
	var skull := SphereMesh.new()
	skull.radius = 0.2
	skull.height = 0.4
	skull.radial_segments = 12
	skull.rings = 6
	_mesh(_head, skull, skin, Vector3.ZERO)
	var nose := SphereMesh.new()
	nose.radius = 0.05
	nose.height = 0.1
	nose.radial_segments = 6
	nose.rings = 3
	_mesh(_head, nose, Color(0.93, 0.65, 0.55), Vector3(0, -0.01, -0.2))
	_face(skin)
	_headgear(str(_style.get("headgear", "beret")), hat)
	_dress(shirt, trousers)
	_last_pos = global_position if is_inside_tree() else Vector3.ZERO


## Visage : yeux (blanc + pupille), sourcils, bouche, oreilles, cheveux, moustache, barbe, lunettes.
func _face(skin: Color) -> void:
	var hair: Color = _style.get("hair", Color(0.32, 0.22, 0.14))
	var hs: String = str(_style.get("hair_style", "short"))
	for sx in [-1.0, 1.0]:
		_eyes.append(_d(_head, "sphere", Vector3(0.036, 0.04, 0.02), Color(0.97, 0.97, 0.95), Vector3(sx * 0.075, 0.035, -0.178)))
		_d(_head, "sphere", Vector3(0.018, 0.02, 0.012), Color(0.1, 0.09, 0.1), Vector3(sx * 0.075, 0.035, -0.194))
		_d(_head, "box", Vector3(0.08, 0.014, 0.012), hair.darkened(0.15), Vector3(sx * 0.075, 0.095, -0.182), Vector3(0, 0, sx * -0.12))
		_d(_head, "sphere", Vector3(0.035, 0.05, 0.02), skin.darkened(0.06), Vector3(sx * 0.195, 0.0, 0.0))
	_d(_head, "box", Vector3(0.07, 0.014, 0.012), Color(0.62, 0.3, 0.3), Vector3(0, -0.085, -0.185))
	if hs != "bald":
		# Calotte de cheveux, légèrement en arrière du front.
		_d(_head, "sphere", Vector3(0.205, 0.17, 0.205), hair, Vector3(0, 0.055, 0.025))
		if hs == "bun":
			_d(_head, "sphere", Vector3(0.09, 0.09, 0.09), hair, Vector3(0, 0.2, 0.1))
		elif hs == "long":
			_d(_head, "box", Vector3(0.36, 0.34, 0.07), hair, Vector3(0, -0.1, 0.17))
	var mo = _style.get("moustache")
	if mo is Color:
		for sx in [-1.0, 1.0]:
			_d(_head, "sphere", Vector3(0.05, 0.022, 0.025), mo, Vector3(sx * 0.04, -0.06, -0.2), Vector3(0, 0, sx * -0.35))
	var beard = _style.get("beard")
	if beard is Color:
		_d(_head, "sphere", Vector3(0.12, 0.1, 0.11), beard, Vector3(0, -0.12, -0.08))
	if bool(_style.get("glasses", false)):
		for sx in [-1.0, 1.0]:
			_d(_head, "torus", Vector3(0.034, 0.05, 0.0), Color(0.15, 0.13, 0.12), Vector3(sx * 0.075, 0.035, -0.2), Vector3(PI / 2, 0, 0))
		_d(_head, "box", Vector3(0.04, 0.01, 0.01), Color(0.15, 0.13, 0.12), Vector3(0, 0.04, -0.2))


## Couvre-chef : béret (par défaut, signe distinctif des Normands), casquette (visière devant ou derrière), casque audio,
## foulard noué, chapeau de paille, képi de gendarme.
func _headgear(kind: String, color: Color) -> void:
	match kind:
		"none":
			pass
		"cap", "cap_back":
			_d(_head, "sphere", Vector3(0.215, 0.14, 0.215), color, Vector3(0, 0.1, 0.0), Vector3.ZERO, true)
			var vz := -0.2 if kind == "cap" else 0.2
			_d(_head, "box", Vector3(0.2, 0.025, 0.14), color.darkened(0.1), Vector3(0, 0.095, vz), Vector3(0.1 if kind == "cap" else -0.1, 0, 0), true)
		"headphones":
			_d(_head, "torus", Vector3(0.2, 0.225, 0.0), Color(0.15, 0.15, 0.18), Vector3(0, 0.02, 0), Vector3(0, 0, PI / 2), true)
			for sx in [-1.0, 1.0]:
				_d(_head, "cyl", Vector3(0.08, 0.05, 0.08), color, Vector3(sx * 0.21, 0.0, 0.0), Vector3(0, 0, PI / 2), true)
		"scarf":
			_d(_head, "sphere", Vector3(0.215, 0.15, 0.215), color, Vector3(0, 0.1, 0.02), Vector3.ZERO, true)
			_d(_head, "sphere", Vector3(0.07, 0.06, 0.07), color, Vector3(0, 0.04, 0.2), Vector3.ZERO, true)
		"straw":
			_d(_head, "cyl", Vector3(0.36, 0.025, 0.36), Color(0.88, 0.76, 0.4), Vector3(0, 0.15, 0.0), Vector3.ZERO, true)
			_d(_head, "cyl", Vector3(0.18, 0.13, 0.2), Color(0.9, 0.78, 0.42), Vector3(0, 0.22, 0.0), Vector3.ZERO, true)
			_d(_head, "cyl", Vector3(0.205, 0.03, 0.205), color, Vector3(0, 0.18, 0.0))
		"kepi":
			_d(_head, "cyl", Vector3(0.2, 0.12, 0.21), color, Vector3(0, 0.2, 0.0), Vector3.ZERO, true)
			_d(_head, "cyl", Vector3(0.25, 0.03, 0.25), color.darkened(0.1), Vector3(0, 0.27, 0.0), Vector3.ZERO, true)
			_d(_head, "box", Vector3(0.2, 0.02, 0.1), Color(0.1, 0.1, 0.12), Vector3(0, 0.165, -0.2), Vector3(0.12, 0, 0))
			_d(_head, "sphere", Vector3(0.03, 0.03, 0.01), Color(0.95, 0.8, 0.25), Vector3(0, 0.21, -0.21))
		_:
			var beret := CylinderMesh.new()
			beret.top_radius = 0.2
			beret.bottom_radius = 0.24
			beret.height = 0.09
			beret.radial_segments = 12
			var bi := _mesh(_head, beret, color, Vector3(0.03, 0.19, 0.0))
			bi.rotation.z = -0.12
			_d(_head, "sphere", Vector3(0.02, 0.02, 0.02), color.darkened(0.25), Vector3(0.03, 0.245, 0.0))   # la queue du béret


## Vêtements : col, boutons, poches, ceinture à boucle, gilet, tablier, foulard.
func _dress(shirt: Color, trousers: Color) -> void:
	var belt: Color = _style.get("belt", Color(0.22, 0.15, 0.1))
	_d(_torso, "cyl", Vector3(0.26, 0.07, 0.205), belt, Vector3(0, 0.03, 0.0), Vector3.ZERO, true).scale = Vector3(1.0, 1.0, 0.8)
	_d(_torso, "box", Vector3(0.07, 0.06, 0.02), Color(0.88, 0.78, 0.35), Vector3(0, 0.03, -0.2))
	_d(_torso, "box", Vector3(0.24, 0.05, 0.12), shirt.lightened(0.3), Vector3(0, 0.76, -0.05), Vector3(0.25, 0, 0))   # col
	for k in 3:
		_d(_torso, "sphere", Vector3(0.018, 0.018, 0.012), shirt.darkened(0.45), Vector3(0, 0.15 + k * 0.17, -0.195))
	for sx in [-1.0, 1.0]:
		_d(_torso, "box", Vector3(0.11, 0.1, 0.02), shirt.darkened(0.12), Vector3(sx * 0.12, 0.2, -0.19))
	var vest = _style.get("vest")
	if vest is Color:
		# Gilet : une coque autour du torse (sans les épaules), ouverte devant sur une bande de chemise.
		var shell := CapsuleMesh.new()
		shell.radius = 0.262
		shell.height = 0.56
		shell.radial_segments = 10
		shell.rings = 3
		_mesh(_torso, shell, vest, Vector3(0, 0.22, 0), Vector3(1.0, 1.0, 0.79))
		detail_parts += 1
		_d(_torso, "box", Vector3(0.07, 0.5, 0.02), shirt.lightened(0.15), Vector3(0, 0.24, -0.208))
		for sx in [-1.0, 1.0]:
			_d(_torso, "box", Vector3(0.09, 0.14, 0.03), vest.darkened(0.2), Vector3(sx * 0.13, 0.1, -0.2))
	var apron = _style.get("apron")
	if apron is Color:
		_d(_torso, "box", Vector3(0.36, 0.6, 0.025), apron, Vector3(0, 0.2, -0.205), Vector3.ZERO, true)
		_d(_torso, "box", Vector3(0.26, 0.2, 0.025), apron, Vector3(0, 0.62, -0.2))
		_d(_torso, "box", Vector3(0.28, 0.12, 0.03), apron.darkened(0.1), Vector3(0, 0.05, -0.21))
		for sx in [-1.0, 1.0]:
			_d(_torso, "box", Vector3(0.04, 0.3, 0.02), apron.darkened(0.15), Vector3(sx * 0.12, 0.8, -0.14), Vector3(0, 0, sx * -0.4))
	var sc = _style.get("scarf")
	if sc is Color:
		_d(_torso, "torus", Vector3(0.12, 0.19, 0.0), sc, Vector3(0, 0.78, 0.0), Vector3.ZERO, true)
		_d(_torso, "box", Vector3(0.1, 0.3, 0.03), sc, Vector3(0.08, 0.62, -0.2))


func _process(delta: float) -> void:
	var pos := global_position
	var measured := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / maxf(delta, 0.0001)
	_last_pos = pos
	var target_speed: float = pose_override.get("speed", minf(measured, 12.0))
	carrying = pose_override.get("carrying", carrying)
	airborne = pose_override.get("airborne", airborne)
	mood = pose_override.get("mood", mood)
	tremble = pose_override.get("tremble", tremble)
	var yaw := global_transform.basis.get_euler().y
	_turn_rate = lerpf(_turn_rate, wrapf(yaw - _last_yaw_body, -PI, PI) / maxf(delta, 0.0001), clampf(10.0 * delta, 0.0, 1.0))
	_last_yaw_body = yaw
	animate(delta, target_speed)


## Longueur d'un cycle de marche complet (deux pas) en mètres, selon la vitesse : pas minuscules à 2 km/h, foulée ample en course.
static func stride_for(speed: float) -> float:
	return clampf(0.5 + 0.5 * speed, 0.45, 3.2)


## Amplitude de la cuisse (rad) qui fait avancer le pied exactement de la vitesse du sol pendant l'appui : pas de patinage.
## Excursion du pied sur un appui = stride / 2 = 2 · L · sin(A)  =>  A = asin(stride / 4L).
static func thigh_amplitude(stride: float, leg_len := LEG_LENGTH) -> float:
	return minf(asin(clampf(stride / (4.0 * leg_len), 0.0, 0.97)), 0.95)


## Angle de la cuisse (rad, + = vers l'avant) selon la phase : appui à vitesse angulaire **constante** (le pied recule à la vitesse du sol,
## sans patiner), balancement avant en cosinus. Phase 0 = cuisse à la verticale au milieu de l'appui précédent ; π/2 = pied avant au maximum.
static func thigh_curve(phase: float, amp: float) -> float:
	var psi := fposmod(phase + PI / 2.0, TAU)          # 0 : cuisse au plus en arrière
	if psi < PI:
		return -amp * cos(psi)                         # balancement avant (de -amp à +amp)
	return amp * (1.0 - 2.0 * (psi - PI) / PI)         # appui : de +amp à -amp, linéaire


## Flexion du genou (rad) selon la phase de la jambe : maximale au milieu du balancement avant (le pied se lève), faible à l'appui.
static func knee_flex(phase: float, run: float) -> float:
	var swing := maxf(cos(phase), 0.0)
	var stance := maxf(-cos(phase), 0.0)
	return lerpf(0.95, 1.7, run) * pow(swing, 1.3) + 0.14 * stance * stance


## Fait avancer l'animation (public pour les tests : pas de dépendance au temps réel).
func animate(delta: float, speed: float) -> void:
	_t += delta
	_speed = lerpf(_speed, speed, clampf(14.0 * delta, 0.0, 1.0))
	_carry_blend = move_toward(_carry_blend, 1.0 if carrying else 0.0, delta * 6.0)
	_air_blend = move_toward(_air_blend, 1.0 if airborne else 0.0, delta * 8.0)
	if _was_air and not airborne:
		_land_t = 0.2
	_was_air = airborne
	_land_t = maxf(_land_t - delta, 0.0)
	var clench := mood == "clench"
	var moving := clampf(_speed / 0.35, 0.0, 1.0)
	var stride := stride_for(_speed)
	if clench:
		stride = minf(stride, 0.9)
	var amp := thigh_amplitude(stride) * moving
	var run := clampf((_speed - 4.5) / 3.0, 0.0, 1.0)
	_phase += _speed * delta / stride * TAU
	# Un pas à chaque appui du pied : cuisse gauche au maximum vers l'avant (π/2), puis la droite (3π/2).
	var half := int(floorf((_phase - PI / 2.0) / PI))
	if half != _last_half:
		_last_half = half
		if moving > 0.6 and _air_blend < 0.5:
			step_taken.emit(half % 2)
	var sl := sin(_phase)
	var sr := -sl
	var thigh_l := thigh_curve(_phase, amp)
	var thigh_r := thigh_curve(_phase + PI, amp)
	var knee_l := knee_flex(_phase, run) * moving
	var knee_r := knee_flex(_phase + PI, run) * moving
	# Repos : poids sur une jambe, l'autre fléchie ; tout s'estompe quand on marche.
	_idle_t += delta * (1.0 - moving)
	var idle := 1.0 - moving
	var shift := sin(_idle_t * 0.55)
	thigh_l += idle * 0.03 * shift
	thigh_r -= idle * 0.03 * shift
	knee_l += idle * 0.08 * maxf(shift, 0.0)
	knee_r += idle * 0.08 * maxf(-shift, 0.0)
	# Saut : cuisses vers l'avant, genoux repliés.
	thigh_l = lerpf(thigh_l, 0.55, _air_blend)
	thigh_r = lerpf(thigh_r, 0.15, _air_blend)
	knee_l = lerpf(knee_l, 1.1, _air_blend)
	knee_r = lerpf(knee_r, 0.7, _air_blend)
	# Jambes serrées : genoux rentrés, un peu fléchis.
	var squeeze := 0.0
	if clench:
		squeeze = 0.13
		knee_l += 0.3
		knee_r += 0.3
	_leg_l.rotation.x = thigh_l
	_leg_r.rotation.x = thigh_r
	_leg_l.rotation.z = squeeze
	_leg_r.rotation.z = -squeeze
	_knee_l.rotation.x = -knee_l
	_knee_r.rotation.x = -knee_r
	# Cheville : le pied reste à plat à l'appui, se relève au balancement, pointe au décollage.
	_ankle_l.rotation.x = clampf(-(thigh_l - knee_l) * 0.75 + 0.15 * maxf(-sl, 0.0) * moving, -0.9, 0.9)
	_ankle_r.rotation.x = clampf(-(thigh_r - knee_r) * 0.75 + 0.15 * maxf(-sr, 0.0) * moving, -0.9, 0.9)
	leg_angle_l = thigh_l
	knee_angle_l = knee_l
	# Bras : en opposition aux jambes, coudes pliés d'autant plus qu'on court.
	var arm_amp := lerpf(0.32, 0.8, run) * moving * clampf(_speed / 1.5, 0.3, 1.0)
	var arms_l := -arm_amp * sl
	var arms_r := -arm_amp * sr
	var elbow_base := lerpf(0.18, 1.5, run)
	var el_l := elbow_base * (0.55 + 0.45 * maxf(-sl, 0.0))
	var el_r := elbow_base * (0.55 + 0.45 * maxf(-sr, 0.0))
	var breath := sin(_t * 1.8) * 0.03 * idle
	var raised := -PI + 0.18
	_arm_l.rotation.x = lerpf(arms_l + breath, raised, _carry_blend)
	_arm_r.rotation.x = lerpf(arms_r + breath, raised, _carry_blend)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.2, _air_blend * (1.0 - _carry_blend))
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.2, _air_blend * (1.0 - _carry_blend))
	_arm_l.rotation.z = lerpf(0.06, 0.55, _air_blend * (1.0 - _carry_blend)) * -1.0 + 0.12 * _carry_blend
	_arm_r.rotation.z = lerpf(0.06, 0.55, _air_blend * (1.0 - _carry_blend)) - 0.12 * _carry_blend
	_elbow_l.rotation.x = lerpf(el_l, 0.25, _carry_blend)
	_elbow_r.rotation.x = lerpf(el_r, 0.25, _carry_blend)
	if clench:
		_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.25, 0.8 * (1.0 - _carry_blend))
		_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.25, 0.8 * (1.0 - _carry_blend))
		_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, 1.0, 0.8)
		_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, 1.0, 0.8)
		_arm_l.rotation.z = -0.3
		_arm_r.rotation.z = 0.3
	arm_angle_l = _arm_l.rotation.x
	elbow_angle_l = _elbow_l.rotation.x
	# Bassin : s'abaisse à chaque appui (double soutien), roule et pivote avec les jambes ; atterrissage amorti.
	var bob := (0.028 + 0.03 * run) * moving
	var land := 0.12 * sin(PI * (1.0 - _land_t / 0.2)) if _land_t > 0.0 else 0.0
	hips_height = HIP_Y - bob * sl * sl - _air_blend * 0.06 - land - (0.06 if clench else 0.0)
	_hips.position.y = hips_height
	_hips.position.x = 0.022 * sl * moving + idle * 0.02 * shift
	_hips.rotation.z = 0.045 * sl * moving + idle * 0.015 * shift
	_hips.rotation.y = 0.13 * sl * moving * minf(1.0, amp * 1.5)
	# Torse : contre-rotation, inclinaison en course, penché quand on serre, tremblement, virage.
	_torso.rotation.y = -0.7 * _hips.rotation.y
	_torso.rotation.x = -0.2 * run - 0.05 * _carry_blend + breath * 0.5 + (-0.3 if clench else 0.0) - 0.05 * moving
	var lean := clampf(-_turn_rate * clampf(_speed, 0.0, 6.0) * 0.012, -0.18, 0.18)
	_torso.rotation.z = -0.5 * _hips.rotation.z + lean
	_torso.scale.y = 1.0 + 0.012 * sin(_t * 1.8) * idle
	if tremble > 0.0:
		_torso.rotation.z += tremble * 0.035 * sin(_t * 41.0)
		_torso.rotation.x += tremble * 0.02 * sin(_t * 33.0 + 1.0)
		_hips.position.y += tremble * 0.012 * sin(_t * 57.0)
	# Tête : stabilisée (compense le torse), regarde autour au repos, cligne des yeux.
	_head.rotation.x = 0.2 * run + 0.4 * (0.3 if clench else 0.0) - 0.4 * _torso.rotation.x
	_head.rotation.y = sin(_t * 0.6) * 0.18 * idle + sin(_t * 0.23) * 0.2 * idle - _torso.rotation.y
	_head.rotation.z = -_torso.rotation.z * 0.6
	_blink_t -= delta
	var closed := _blink_t < 0.0
	for e in _eyes:
		e.scale.y = 0.12 if closed else 1.0
	if _blink_t < -0.13:
		_blink_t = randf_range(2.5, 5.5)
