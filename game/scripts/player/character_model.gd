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
const ARM_LENGTH := 0.72
const LEG_LENGTH := 0.84
const STRIDE_FREQ := 1.15            # cycles de jambes par mètre parcouru
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
var _phase := 0.0
var _last_half := 0
var _last_pos := Vector3.ZERO
var _speed := 0.0
var _carry_blend := 0.0
var _air_blend := 0.0
var _t := 0.0
## Angles courants (lisibles par les tests).
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


func _limb(parent: Node3D, pivot: Vector3, length: float, radius: float, color: Color, end_color: Color, end_scale: Vector3, cuff := Color(0, 0, 0, 0)) -> Node3D:
	# Le pivot est en haut du membre ; le membre pend sous lui (-Y).
	var j := Node3D.new()
	j.position = pivot
	parent.add_child(j)
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	cap.radial_segments = 8
	cap.rings = 2
	_mesh(j, cap, color, Vector3(0, -length * 0.5, 0))
	# Extrémité : main (peau) ou chaussure (sombre, plus longue vers l'avant).
	var end := SphereMesh.new()
	end.radius = radius * 1.15
	end.height = radius * 2.3
	end.radial_segments = 8
	end.rings = 4
	_mesh(j, end, end_color, Vector3(0, -length + radius * 0.4, -0.06 if end_scale.z > 1.2 else 0.0), end_scale)
	var is_leg := end_scale.z > 1.2
	if cuff.a > 0.0:
		_d(j, "cyl", Vector3(radius * 1.12, 0.07, radius * 1.12), cuff, Vector3(0, -length + radius * 1.5, 0), Vector3.ZERO, true)
	if is_leg:
		_d(j, "box", Vector3(radius * 2.1, 0.035, radius * 3.9), Color(0.1, 0.08, 0.07), Vector3(0, -length - radius * 0.2, -0.07))
	else:
		_d(j, "sphere", Vector3(radius * 0.5, radius * 0.5, radius * 0.5), end_color, Vector3(radius * 0.9 * (1.0 if pivot.x > 0.0 else -1.0), -length + radius * 0.9, -radius * 0.7))
	return j


func _build(shirt: Color, trousers: Color, hat: Color) -> void:
	_hips = Node3D.new()
	_hips.name = "Bassin"
	_hips.position = Vector3(0, HIP_Y, 0)
	add_child(_hips)
	# Jambes (pivot à la hanche, relatif au monde du modèle : on les range sous le bassin).
	var skin: Color = _style.get("skin", SKIN)
	var shoes: Color = _style.get("shoes", Color(0.18, 0.12, 0.1))
	_leg_l = _limb(_hips, Vector3(-0.15, 0.0, 0), LEG_LENGTH, 0.11, trousers, shoes, Vector3(1.0, 0.7, 1.6), trousers.darkened(0.2))
	_leg_r = _limb(_hips, Vector3(0.15, 0.0, 0), LEG_LENGTH, 0.11, trousers, shoes, Vector3(1.0, 0.7, 1.6), trousers.darkened(0.2))
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
	_arm_l = _limb(_torso, Vector3(-0.33, SHOULDER_Y - HIP_Y, 0), ARM_LENGTH, 0.085, shirt, skin, Vector3.ONE, shirt.lightened(0.25))
	_arm_r = _limb(_torso, Vector3(0.33, SHOULDER_Y - HIP_Y, 0), ARM_LENGTH, 0.085, shirt, skin, Vector3.ONE, shirt.lightened(0.25))
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
		_d(_head, "sphere", Vector3(0.036, 0.04, 0.02), Color(0.97, 0.97, 0.95), Vector3(sx * 0.075, 0.035, -0.178))
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
	animate(delta, target_speed)


## Fait avancer l'animation (public pour les tests : pas de dépendance au temps réel).
func animate(delta: float, speed: float) -> void:
	_t += delta
	_speed = lerpf(_speed, speed, clampf(14.0 * delta, 0.0, 1.0))
	_carry_blend = move_toward(_carry_blend, 1.0 if carrying else 0.0, delta * 6.0)
	_air_blend = move_toward(_air_blend, 1.0 if airborne else 0.0, delta * 8.0)
	var moving := clampf(_speed / 1.2, 0.0, 1.0)
	_phase += _speed * delta * STRIDE_FREQ * TAU * 0.5
	var run := clampf((_speed - 4.5) / 3.0, 0.0, 1.0)            # 0 = marche, 1 = course
	var amp := moving * lerpf(0.55, 0.95, run)
	var swing := sin(_phase)
	# Un pas à chaque demi-cycle, si on marche vraiment : le pied touche le sol.
	var half := int(floorf(_phase / PI))
	if half != _last_half:
		_last_half = half
		if moving > 0.6 and _air_blend < 0.5:
			step_taken.emit(half % 2)
	# Jambes : opposées, repliées en l'air.
	var legs := swing * amp
	_leg_l.rotation.x = lerpf(legs, -0.7, _air_blend)
	_leg_r.rotation.x = lerpf(-legs, 0.25, _air_blend)
	leg_angle_l = _leg_l.rotation.x
	# Genou fléchi sur la jambe qui revient : le pied se lève (translation du pivot).
	# Bras : opposés aux jambes ; levés au-dessus de la tête quand on porte une caisse.
	var arms := -swing * amp * 0.85 * (1.0 - _carry_blend)
	var breath := sin(_t * 1.8) * 0.03 * (1.0 - moving)
	var raised := -PI + 0.18                                      # bras quasi verticaux
	_arm_l.rotation.x = lerpf(arms + breath, raised, _carry_blend)
	_arm_r.rotation.x = lerpf(-arms + breath, raised, _carry_blend)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, -0.2, _air_blend * (1.0 - _carry_blend))
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, -0.2, _air_blend * (1.0 - _carry_blend))
	_arm_l.rotation.z = lerpf(0.06, 0.55, _air_blend * (1.0 - _carry_blend)) * -1.0
	_arm_r.rotation.z = lerpf(0.06, 0.55, _air_blend * (1.0 - _carry_blend))
	_arm_l.rotation.z += 0.12 * _carry_blend
	_arm_r.rotation.z -= 0.12 * _carry_blend
	arm_angle_l = _arm_l.rotation.x
	# Bassin : rebond à chaque pas, torse penché en course, tête qui compense.
	_hips.position.y = HIP_Y + absf(cos(_phase)) * 0.05 * amp - _air_blend * 0.08
	_torso.rotation.x = -0.18 * run - 0.05 * _carry_blend + breath * 0.5
	_torso.rotation.z = sin(_phase) * 0.04 * amp
	_head.rotation.x = 0.18 * run
	_head.rotation.y = sin(_t * 0.6) * 0.05 * (1.0 - moving)
