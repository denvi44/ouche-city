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


static func make(shirt: Color, trousers: Color = Color(0.2, 0.22, 0.3), hat: Color = Color(0.15, 0.17, 0.25)) -> CharacterModel:
	var m := CharacterModel.new()
	m.name = "Modele"
	m.scale = Vector3.ONE * 0.93     # tête un peu grosse, mais pas plus haut qu'une porte
	m._build(shirt, trousers, hat)
	return m


func _mat(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("couleur", color)
	mat.set_shader_parameter("rim_force", 0.15)
	mat.next_pass = preload("res://assets/materials/contour_personnage.tres")
	return mat


func _mesh(parent: Node3D, mesh: PrimitiveMesh, color: Color, pos: Vector3, scale := Vector3.ONE) -> MeshInstance3D:
	mesh.material = _mat(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


func _limb(parent: Node3D, pivot: Vector3, length: float, radius: float, color: Color, end_color: Color, end_scale: Vector3) -> Node3D:
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
	return j


func _build(shirt: Color, trousers: Color, hat: Color) -> void:
	_hips = Node3D.new()
	_hips.name = "Bassin"
	_hips.position = Vector3(0, HIP_Y, 0)
	add_child(_hips)
	# Jambes (pivot à la hanche, relatif au monde du modèle : on les range sous le bassin).
	_leg_l = _limb(_hips, Vector3(-0.15, 0.0, 0), LEG_LENGTH, 0.11, trousers, Color(0.18, 0.12, 0.1), Vector3(1.0, 0.7, 1.6))
	_leg_r = _limb(_hips, Vector3(0.15, 0.0, 0), LEG_LENGTH, 0.11, trousers, Color(0.18, 0.12, 0.1), Vector3(1.0, 0.7, 1.6))
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
	_arm_l = _limb(_torso, Vector3(-0.33, SHOULDER_Y - HIP_Y, 0), ARM_LENGTH, 0.085, shirt, SKIN, Vector3.ONE)
	_arm_r = _limb(_torso, Vector3(0.33, SHOULDER_Y - HIP_Y, 0), ARM_LENGTH, 0.085, shirt, SKIN, Vector3.ONE)
	_head = Node3D.new()
	_head.name = "Tete"
	_head.position = Vector3(0, 0.9, 0)
	_torso.add_child(_head)
	var skull := SphereMesh.new()
	skull.radius = 0.2
	skull.height = 0.4
	skull.radial_segments = 12
	skull.rings = 6
	_mesh(_head, skull, SKIN, Vector3.ZERO)
	var nose := SphereMesh.new()
	nose.radius = 0.05
	nose.height = 0.1
	nose.radial_segments = 6
	nose.rings = 3
	_mesh(_head, nose, Color(0.93, 0.65, 0.55), Vector3(0, -0.01, -0.2))
	# Béret : disque penché, signe distinctif des Normands d'Ouche City.
	var beret := CylinderMesh.new()
	beret.top_radius = 0.2
	beret.bottom_radius = 0.24
	beret.height = 0.09
	beret.radial_segments = 12
	var bi := _mesh(_head, beret, hat, Vector3(0.03, 0.19, 0.0))
	bi.rotation.z = -0.12
	_last_pos = global_position if is_inside_tree() else Vector3.ZERO


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
