class_name GooseModel
extends CharacterModel
## Oie jouable (mission 08) : même interface que le personnage humain (portage, saut, humeur…), mais corps d'oie articulé :
## cou et tête, deux ailes qui battent, deux pattes qui se balancent, dandinement du corps. Animation procédurale pilotée par la
## vitesse mesurée, donc valable aussi pour un corps que ce pair ne simule pas. Hauteur ≈ 1,0 m pour 1,6 m de long.
##  - marche / course : pas rapides, corps qui roule d'un côté à l'autre, tête qui oscille ;
##  - saut : ailes déployées qui battent, pattes en arrière ;
##  - « HONK ! » : cou tendu vers l'avant, bec ouvert, ailes à moitié ouvertes (`honk()`).

var _body_g: Node3D
var _neck_g: Node3D
var _wing_gl: Node3D
var _wing_gr: Node3D
var _leg_gl: Node3D
var _leg_gr: Node3D
var _honk_t := 0.0
var _gphase := 0.0
var _beak_g: Node3D


static func make_goose(variant := 0) -> GooseModel:
	var m := GooseModel.new()
	m.name = "Modele"
	m.scale = Vector3.ONE * 1.25
	m._build_goose(variant)
	return m


func _kit_node(k: PropKit) -> Node3D:
	return k.build()


func _build_goose(variant: int) -> void:
	var body := Color(0.97, 0.96, 0.92) if variant != 1 else Color(0.66, 0.64, 0.6)
	var wing := Color(0.9, 0.89, 0.84) if variant != 1 else Color(0.5, 0.48, 0.45)
	var orange := Color(0.96, 0.58, 0.12)
	# Corps + queue (pivot au centre de gravité).
	_body_g = Node3D.new()
	_body_g.name = "Corps"
	add_child(_body_g)
	var kb := PropKit.new()
	kb.add_sphere(0.24, Vector3(0, 0.5, 0), body, Vector3(0.85, 0.82, 1.45), 9)
	kb.add_sphere(0.17, Vector3(0, 0.55, -0.3), body, Vector3(0.9, 0.9, 1.1), 8)
	kb.add_box(Vector3(0.12, 0.05, 0.22), Vector3(0, 0.66, -0.52), body, Vector3(-0.35, 0, 0))
	if variant == 2:
		kb.add_cyl(0.085, 0.09, 0.07, Vector3(0, 0.78, 0.33), Color(0.85, 0.2, 0.2), Vector3(0.3, 0, 0), 8)
	_body_g.add_child(_kit_node(kb))
	# Cou, tête, bec (pivot à la base du cou).
	_neck_g = Node3D.new()
	_neck_g.name = "Cou"
	_neck_g.position = Vector3(0, 0.62, 0.28)
	_body_g.add_child(_neck_g)
	var kn := PropKit.new()
	kn.add_cyl(0.07, 0.1, 0.55, Vector3(0, 0.23, 0.0), body, Vector3(0.3, 0, 0), 7)
	kn.add_sphere(0.1, Vector3(0, 0.51, 0.12), body, Vector3(0.9, 0.95, 1.1), 8)
	for sx in [-1.0, 1.0]:
		kn.add_sphere(0.022, Vector3(sx * 0.07, 0.54, 0.17), Color(0.05, 0.04, 0.04), Vector3.ONE, 4)
	_neck_g.add_child(_kit_node(kn))
	_beak_g = Node3D.new()
	_beak_g.position = Vector3(0, 0.48, 0.24)
	_neck_g.add_child(_beak_g)
	var kk := PropKit.new()
	kk.add_box(Vector3(0.09, 0.05, 0.16), Vector3(0, 0.0, 0.05), orange)
	kk.add_box(Vector3(0.07, 0.03, 0.08), Vector3(0, 0.04, 0.0), orange)
	_beak_g.add_child(_kit_node(kk))
	# Ailes (pivots aux épaules).
	for side in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.2, 0.6, 0.0)
		_body_g.add_child(pivot)
		var kw := PropKit.new()
		kw.add_sphere(0.2, Vector3(side * 0.0, -0.08, -0.02), wing, Vector3(0.28, 0.6, 1.35), 7)
		pivot.add_child(_kit_node(kw))
		if side < 0.0:
			_wing_gl = pivot
		else:
			_wing_gr = pivot
	# Pattes (pivots aux hanches).
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(side * 0.09, 0.4, 0.0)
		add_child(hip)
		var kl := PropKit.new()
		kl.add_cyl(0.022, 0.03, 0.3, Vector3(0, -0.15, 0), orange, Vector3.ZERO, 5)
		kl.add_box(Vector3(0.1, 0.02, 0.15), Vector3(0, -0.38, 0.05), orange)
		hip.add_child(_kit_node(kl))
		if side < 0.0:
			_leg_gl = hip
		else:
			_leg_gr = hip
	detail_parts = 24


## Déclenche l'animation du cri.
func honk() -> void:
	_honk_t = 0.7


func _process(delta: float) -> void:
	var pos := global_position
	var measured := Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length() / maxf(delta, 0.0001)
	_last_pos = pos
	var target_speed: float = pose_override.get("speed", minf(measured, 12.0))
	airborne = pose_override.get("airborne", airborne)
	mood = pose_override.get("mood", mood)
	animate(delta, target_speed)


func animate(delta: float, speed: float) -> void:
	_t += delta
	_speed = lerpf(_speed, speed, clampf(12.0 * delta, 0.0, 1.0))
	_honk_t = maxf(_honk_t - delta, 0.0)
	var run := clampf(_speed / 5.0, 0.0, 1.0)
	var prev := _gphase
	_gphase += delta * (2.0 + _speed * 3.2) if _speed > 0.15 else 0.0
	if int(floor(_gphase / PI)) != int(floor(prev / PI)):
		step_taken.emit(int(floor(_gphase / PI)) % 2)
	var sw := sin(_gphase)
	# Pattes : balancement (en l'air, repliées vers l'arrière).
	var air := 1.0 if airborne else 0.0
	_air_blend = lerpf(_air_blend, air, clampf(14.0 * delta, 0.0, 1.0))
	_leg_gl.rotation.x = lerpf(sw * 0.7 * run, 0.9, _air_blend)
	_leg_gr.rotation.x = lerpf(-sw * 0.7 * run, 0.9, _air_blend)
	# Dandinement : le corps roule, la tête oscille à contretemps, un léger rebond.
	_body_g.rotation.z = sw * 0.13 * run
	_body_g.position.y = absf(sin(_gphase)) * 0.05 * run + (0.12 * _air_blend)
	var honk_k := clampf(_honk_t / 0.7, 0.0, 1.0)
	var honk_pose := sin(honk_k * PI)                  # 0 → 1 → 0 pendant le cri
	_neck_g.rotation.x = lerpf(-0.12 * run + sin(_t * 1.3) * 0.04, -1.0, honk_pose)    # cou tendu vers l'avant
	_neck_g.rotation.z = -sw * 0.12 * run
	_beak_g.rotation.x = honk_pose * 0.5                                               # bec ouvert
	# Ailes : battement en vol, à moitié ouvertes pendant le cri, repliées sinon.
	var flap := sin(_t * 22.0) * 0.9 * _air_blend
	var open := 0.15 + 0.9 * honk_pose + 0.55 * _air_blend
	_wing_gl.rotation.z = open + flap
	_wing_gr.rotation.z = -(open + flap)
