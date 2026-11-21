class_name Vehicle
extends NetBody
## Véhicule arcade (agent 05) : la camionnette de Tonton Gégé.
##
## Modèle « vélo » simplifié : accélération conique, freinage, frein à main, braquage qui se
## ferme avec la vitesse, aucune dérive. Corps cinématique (`move_and_slide`) : mêmes règles
## que le joueur, donc même prédiction / réconciliation (`NetBody`).
## Les chocs (perte de vitesse brutale) sont signalés côté serveur : la cargaison fragile
## de la mission en dépend.

## Perte de vitesse (m/s) lors d'un choc ; émis seulement par le serveur, hors rejeu client.
signal impact(strength: float)

const MAX_SPEED := 17.0          # 61 km/h : on transporte du calva, pas un record
const MAX_REVERSE := 5.0
const ACCEL := 8.5
const BRAKE := 16.0
const COAST_DECEL := 2.6
const HANDBRAKE_DECEL := 24.0
const WHEELBASE := 2.9
const MAX_STEER := 0.6           # rad aux roues, à l'arrêt
const GRAVITY := 22.0
const SEAT_OFFSET := Vector3(-1.9, 0.0, -0.4)   # côté conducteur, pour descendre

var driver := 0
var speed := 0.0                 # vitesse signée le long de l'axe avant (m/s)
var vehicle_name := "Camionnette de Gégé"

var _body_visual: Node3D
var _wheels: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _steer_visual := 0.0
var _last_input := {"move": Vector2.ZERO, "jump": false}
## Entrée imposée (tests QA) : remplace celle du clavier.
var forced_input := {}
var _engine: AudioStreamPlayer3D
var _last_pos := Vector3.ZERO
## Vitesse mesurée sur le déplacement visible (utile aux pairs qui ne simulent pas ce véhicule).
var measured_speed := 0.0
var _jolt := 0.0                 # secousse visuelle (nid-de-poule), décroît seule


func _ready() -> void:
	add_to_group("vehicles")
	floor_snap_length = 0.7
	floor_max_angle = deg_to_rad(50.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 1.5, 4.4)
	shape.shape = box
	shape.position.y = 0.95
	add_child(shape)
	_build_visual()
	_engine = Sfx.make_loop("engine", -9.0)
	if _engine:
		add_child(_engine)


func forward() -> Vector3:
	return Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))


func speed_kmh() -> float:
	return absf(speed) * 3.6


# --- Entrées -------------------------------------------------------------------------

func gather_input(_delta: float) -> Dictionary:
	if not forced_input.is_empty():
		return forced_input.duplicate()
	if Net.bot and Net.arg("bot-drive") != null:
		return {"move": Vector2(0, -1), "jump": false}   # bot conducteur (QA) : tout droit
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.get_connected_joypads().size() > 0
	if not active:
		mv = Vector2.ZERO
	return {"move": mv, "jump": active and Input.is_action_pressed("jump")}


func neutral_input() -> Dictionary:
	return {"move": Vector2.ZERO, "jump": false}


func pack_input(inp: Dictionary) -> PackedFloat32Array:
	return PackedFloat32Array([inp.move.x, inp.move.y, 1.0 if inp.jump else 0.0])


func unpack_input(a: PackedFloat32Array) -> Dictionary:
	if a.size() < 3:
		return neutral_input()
	return {"move": Vector2(a[0], a[1]).limit_length(1.0), "jump": a[2] > 0.5}


## Pas de conduite déterministe. move.y < 0 = avant (même convention que la marche).
func simulate(inp: Dictionary, delta: float) -> void:
	var mv: Vector2 = inp.move
	var throttle := -mv.y
	var steer := mv.x
	var handbrake: bool = inp.jump
	_last_input = inp
	# Longitudinal : poussée conique, freinage si on inverse, ralentissement moteur sinon.
	if absf(throttle) > 0.05:
		if throttle * speed >= -0.1:
			var limit := MAX_SPEED if throttle > 0.0 else MAX_REVERSE
			speed += throttle * ACCEL * delta * clampf(1.0 - absf(speed) / limit, 0.12, 1.0)
		else:
			speed += throttle * BRAKE * delta
	else:
		speed = move_toward(speed, 0.0, COAST_DECEL * delta)
	if handbrake:
		speed = move_toward(speed, 0.0, HANDBRAKE_DECEL * delta)
	speed = clampf(speed, -MAX_REVERSE, MAX_SPEED)
	# Direction : braquage réduit avec la vitesse, modèle vélo.
	var steer_angle := steer * MAX_STEER * lerpf(1.0, 0.3, clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
	rotation.y -= (speed / WHEELBASE) * tan(steer_angle) * delta
	_steer_visual = steer_angle
	var f := forward()
	velocity.x = f.x * speed
	velocity.z = f.z * speed
	if is_on_floor():
		velocity.y = -2.0
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
	var before := speed
	move_and_slide()
	# La vitesse réelle après collision : un mur coupe l'élan.
	var after := Vector3(velocity.x, 0.0, velocity.z).dot(f)
	if get_slide_collision_count() > 0 or absf(after - before) > 0.01:
		speed = after
	var loss := absf(before) - absf(speed)
	if loss > 1.5 and multiplayer.has_multiplayer_peer() and multiplayer.is_server() and get_slide_collision_count() > 0:
		impact.emit(loss)
	if global_position.y < -30.0:
		global_position = Vector3(global_position.x, 3.0, global_position.z)
		velocity = Vector3.ZERO
		speed = 0.0


## Le moteur ronronne quand quelqu'un conduit ; la hauteur suit la vitesse (réelle ou mesurée).
func _update_engine_sound() -> void:
	if _engine == null:
		return
	var running := driver != 0
	if running and not _engine.playing:
		_engine.play()
	elif not running and _engine.playing:
		_engine.stop()
	var spd := absf(speed) if (is_local_controller() or (multiplayer.has_multiplayer_peer() and multiplayer.is_server())) else measured_speed
	var k := clampf(spd / MAX_SPEED, 0.0, 1.0)
	_engine.pitch_scale = lerpf(0.75, 2.1, k)
	_engine.volume_db = lerpf(-12.0, -5.0, k)


## Secousse de la caisse (nid-de-poule) : visuel seulement.
func jolt() -> void:
	_jolt = 1.0


func _process(delta: float) -> void:
	super._process(delta)
	var dp := global_position - _last_pos
	_last_pos = global_position
	measured_speed = lerpf(measured_speed, Vector2(dp.x, dp.z).length() / maxf(delta, 0.0001), clampf(8.0 * delta, 0.0, 1.0))
	_update_engine_sound()
	if _body_visual:
		_jolt = maxf(_jolt - delta * 2.5, 0.0)
		_body_visual.position.y = sin(Time.get_ticks_msec() * 0.045) * 0.13 * _jolt
	# Roues avant braquées, roues qui tournent (cosmétique).
	for w in _front_wheels:
		w.rotation.y = lerp_angle(w.rotation.y, -_steer_visual, clampf(10.0 * delta, 0.0, 1.0))
	for w in _wheels:
		w.get_child(0).rotation.x += speed * delta / 0.38
	# Assiette : la caisse suit la pente (visuel seulement) et se penche un peu en virage / freinage.
	if _body_visual:
		var target_pitch := 0.0
		var target_roll := 0.0
		if is_on_floor():
			var n := get_floor_normal()
			var local := global_transform.basis.inverse() * n
			target_pitch = atan2(-local.z, local.y) * 0.9
			target_roll = atan2(local.x, local.y) * 0.9
		target_roll += _steer_visual * absf(speed) / MAX_SPEED * 0.12
		_body_visual.rotation.x = lerp_angle(_body_visual.rotation.x, target_pitch, clampf(8.0 * delta, 0.0, 1.0))
		_body_visual.rotation.z = lerp_angle(_body_visual.rotation.z, target_roll, clampf(8.0 * delta, 0.0, 1.0))


# --- Carrosserie ----------------------------------------------------------------------

func _toon(color: Color, reflet := 0.55) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/toon.gdshader")
	m.set_shader_parameter("couleur", color)
	m.set_shader_parameter("reflet_force", reflet)
	m.set_shader_parameter("reflet_taille", 0.035)
	return m


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visuel"
	add_child(visual)
	_body_visual = Node3D.new()
	_body_visual.name = "Caisse"
	visual.add_child(_body_visual)
	var tris := []
	# Pièces : [taille, position, couleur, reflet]. Avant du véhicule = -Z.
	var parts := [
		[Vector3(2.0, 0.8, 4.3), Vector3(0, 0.75, 0), Color(0.27, 0.47, 0.72), 0.55],       # soubassement
		[Vector3(2.0, 1.25, 2.55), Vector3(0, 1.78, 0.75), Color(0.96, 0.9, 0.76), 0.35],   # caisse arrière
		[Vector3(1.9, 1.0, 1.55), Vector3(0, 1.62, -1.35), Color(0.27, 0.47, 0.72), 0.6],   # cabine
		[Vector3(1.78, 0.5, 0.06), Vector3(0, 1.78, -2.14), Color(0.2, 0.26, 0.32), 0.9],   # pare-brise
		[Vector3(2.1, 0.22, 0.3), Vector3(0, 0.45, -2.2), Color(0.88, 0.86, 0.82), 0.4],    # pare-chocs avant
		[Vector3(2.1, 0.22, 0.3), Vector3(0, 0.45, 2.2), Color(0.88, 0.86, 0.82), 0.4],     # pare-chocs arrière
		[Vector3(0.34, 0.24, 0.08), Vector3(-0.7, 0.9, -2.17), Color(1.0, 0.93, 0.55), 0.0],  # phare gauche
		[Vector3(0.34, 0.24, 0.08), Vector3(0.7, 0.9, -2.17), Color(1.0, 0.93, 0.55), 0.0],   # phare droit
		[Vector3(0.28, 0.2, 0.08), Vector3(-0.8, 0.95, 2.17), Color(0.8, 0.15, 0.12), 0.0],   # feu gauche
		[Vector3(0.28, 0.2, 0.08), Vector3(0.8, 0.95, 2.17), Color(0.8, 0.15, 0.12), 0.0],    # feu droit
	]
	for p in parts:
		var mesh := BoxMesh.new()
		mesh.size = p[0]
		mesh.material = _toon(p[2], p[3])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = p[1]
		_body_visual.add_child(mi)
		tris.append_array(HullOutline.tris_of(mesh, Transform3D(Basis(), p[1])))
	var hull := MeshInstance3D.new()
	hull.name = "Contours"
	hull.mesh = HullOutline.build(tris)
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_visual.add_child(hull)
	# Enseigne peinte sur les flancs de la caisse arrière.
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = "Gégé & Fils\nCalva du Pays d'Ouche"
		l.font_size = 40
		l.pixel_size = 0.0038
		l.modulate = Color(0.45, 0.17, 0.12)
		l.outline_size = 0
		l.double_sided = false
		l.position = Vector3(side * 1.011, 1.82, 0.75)
		l.rotation.y = side * PI / 2.0
		_body_visual.add_child(l)
	# Roues : cylindre sombre, contour par coque classique (normales lisses).
	for wx in [-1.0, 1.0]:
		for wz in [-1.45, 1.45]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx * 1.0, 0.38, wz)
			_body_visual.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.38
			cyl.bottom_radius = 0.38
			cyl.height = 0.3
			cyl.radial_segments = 14
			var wm := _toon(Color(0.16, 0.14, 0.13), 0.0)
			wm.next_pass = preload("res://assets/materials/contour_personnage.tres")
			cyl.material = wm
			var wi := MeshInstance3D.new()
			wi.mesh = cyl
			wi.rotation.z = PI / 2.0
			spin.add_child(wi)
			# Moyeu clair : permet de voir la roue tourner.
			var hub := BoxMesh.new()
			hub.size = Vector3(0.32, 0.12, 0.12)
			hub.material = _toon(Color(0.85, 0.83, 0.78), 0.0)
			var hi := MeshInstance3D.new()
			hi.mesh = hub
			spin.add_child(hi)
			_wheels.append(pivot)
			if wz < 0.0:
				_front_wheels.append(pivot)
