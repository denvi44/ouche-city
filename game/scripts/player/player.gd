class_name Player
extends CharacterBody3D
## Joueur à pied (agent 05), répliqué par la couche réseau (agent 12).
##
## Autorité : le serveur simule tous les joueurs. Le client propriétaire prédit son propre
## mouvement avec le même code (`simulate`), envoie ses entrées numérotées, puis se réconcilie
## sur l'état serveur en rejouant les entrées non acquittées. Les autres joueurs sont
## interpolés 100 ms dans le passé.

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.5
const JUMP_VELOCITY := 5.2
const GRAVITY := 18.0
const ACCEL := 35.0
const STATE_EVERY_TICKS := 3          # 20 Hz
const INTERP_DELAY_MS := 100
const PALETTE := [Color(0.85, 0.3, 0.25), Color(0.25, 0.5, 0.8), Color(0.95, 0.75, 0.2), Color(0.35, 0.65, 0.35),
	Color(0.65, 0.4, 0.75), Color(0.95, 0.55, 0.25), Color(0.3, 0.7, 0.7), Color(0.8, 0.45, 0.6)]

var peer_id := 1
var display_name := "Normand"
var facing := 0.0

var visual: Node3D
var camera_rig: Node3D

var _seq := 0
var _ack := 0
var _pending: Array[Dictionary] = []
var _server_queue: Array[Dictionary] = []
var _last_received_seq := 0
var _last_yaw := 0.0
var _snapshots: Array = []
var _tick := 0
var _bot_t := 0.0
var _bot_yaw := 0.0
var _bot_stuck := 0.0


func _ready() -> void:
	peer_id = name.to_int()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	_build_visual()
	if is_local() and Net.has_local_player() and DisplayServer.get_name() != "headless":
		camera_rig = preload("res://scripts/player/camera_rig.gd").new()
		camera_rig.name = "Camera"
		camera_rig.target = self
		add_child(camera_rig)


func is_local() -> bool:
	return multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id()


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visuel"
	add_child(visual)
	var color: Color = PALETTE[absi(peer_id) % PALETTE.size()]
	_part(CapsuleMesh.new(), color, Vector3(0, 0.95, 0), func(m): m.radius = 0.33; m.height = 1.25; m.radial_segments = 10; m.rings = 3)
	_part(SphereMesh.new(), Color(0.96, 0.8, 0.66), Vector3(0, 1.78, 0), func(m): m.radius = 0.24; m.height = 0.48; m.radial_segments = 10; m.rings = 5)
	# Le béret : signe distinctif du Normand d'Ouche City.
	_part(CylinderMesh.new(), Color(0.15, 0.17, 0.25), Vector3(0.03, 2.0, 0), func(m): m.top_radius = 0.2; m.bottom_radius = 0.26; m.height = 0.08; m.radial_segments = 12)
	# Nez, pour savoir où l'on regarde.
	_part(SphereMesh.new(), Color(0.93, 0.65, 0.55), Vector3(0, 1.76, -0.24), func(m): m.radius = 0.06; m.height = 0.12; m.radial_segments = 6; m.rings = 3)
	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.4
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.004
	label.no_depth_test = false
	add_child(label)


func _part(mesh: PrimitiveMesh, color: Color, pos: Vector3, setup: Callable) -> void:
	setup.call(mesh)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("couleur", color)
	mat.next_pass = preload("res://assets/materials/contour_personnage.tres")
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	visual.add_child(mi)


# --- Entrées ------------------------------------------------------------------

func gather_input(delta: float) -> Dictionary:
	if Net.bot:
		# Bot de playtest : marche tout droit, tourne quand un mur le bloque, sprinte une seconde sur quatre.
		_bot_t += delta
		_bot_stuck = _bot_stuck + delta if Vector2(velocity.x, velocity.z).length() < 1.0 else 0.0
		if _bot_stuck > 0.4:
			_bot_yaw += PI * 0.5 + fmod(_bot_t, 1.0)
			_bot_stuck = 0.0
		return {"move": Vector2(0, -1), "yaw": _bot_yaw, "jump": false, "sprint": fmod(_bot_t, 4.0) < 1.0}
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var yaw: float = camera_rig.yaw if camera_rig else 0.0
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.get_connected_joypads().size() > 0
	if not captured:
		mv = Vector2.ZERO
	return {"move": mv, "yaw": yaw, "jump": captured and Input.is_action_pressed("jump"), "sprint": Input.is_action_pressed("sprint")}


## Simulation déterministe d'un pas de mouvement, partagée client/serveur.
func simulate(inp: Dictionary, delta: float) -> void:
	var mv: Vector2 = (inp.move as Vector2).limit_length(1.0)
	var dir := Vector3(mv.x, 0.0, mv.y).rotated(Vector3.UP, float(inp.yaw))
	var speed := SPRINT_SPEED if inp.sprint else WALK_SPEED
	velocity.x = move_toward(velocity.x, dir.x * speed, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, ACCEL * delta)
	if is_on_floor():
		if inp.jump:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -50.0)
	move_and_slide()
	if dir.length_squared() > 0.01:
		facing = atan2(-dir.x, -dir.z)
	# Filet de sécurité : retour au point de départ si l'on tombe sous la carte.
	if global_position.y < -30.0:
		global_position = Vector3(global_position.x, 2.0, global_position.z)
		velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if is_local():
		var inp := gather_input(delta)
		_seq += 1
		inp["seq"] = _seq
		simulate(inp, delta)
		if multiplayer.is_server():
			_ack = _seq
		else:
			_pending.append(inp)
			if _pending.size() > 120:
				_pending.pop_front()
			_submit_input.rpc_id(1, _seq, inp.move, inp.yaw, inp.jump, inp.sprint)
	elif multiplayer.is_server():
		if _server_queue.is_empty():
			simulate({"move": Vector2.ZERO, "yaw": _last_yaw, "jump": false, "sprint": false}, delta)
		else:
			# Rattrapage doux si des paquets arrivent groupés.
			var n := 1 if _server_queue.size() <= 3 else 2
			for i in mini(n, _server_queue.size()):
				var inp: Dictionary = _server_queue.pop_front()
				simulate(inp, delta)
				_ack = inp.seq
				_last_yaw = inp.yaw
	if multiplayer.is_server():
		_tick += 1
		if _tick % STATE_EVERY_TICKS == 0:
			for id in Net.ready_peers():
				_state.rpc_id(id, global_position, velocity, facing, _ack)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(seq: int, move: Vector2, yaw: float, jump: bool, sprint: bool) -> void:
	if not multiplayer.is_server() or multiplayer.get_remote_sender_id() != peer_id:
		return
	if seq <= _last_received_seq:
		return
	_last_received_seq = seq
	if _server_queue.size() > 30:
		_server_queue.pop_front()
	_server_queue.append({"seq": seq, "move": move.limit_length(1.0), "yaw": yaw, "jump": jump, "sprint": sprint})


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(pos: Vector3, vel: Vector3, face: float, ack: int) -> void:
	if is_local():
		_reconcile(pos, vel, ack)
	else:
		_snapshots.append([Time.get_ticks_msec(), pos, face])
		if _snapshots.size() > 20:
			_snapshots.pop_front()


func _reconcile(pos: Vector3, vel: Vector3, ack: int) -> void:
	var before := global_position
	global_position = pos
	velocity = vel
	_pending = _pending.filter(func(i): return i.seq > ack)
	for inp in _pending:
		simulate(inp, 1.0 / Engine.physics_ticks_per_second)
	# L'écart est absorbé visuellement plutôt que téléporté.
	var err := before - global_position
	if err.length() < 2.0:
		visual.position += err


func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not is_local() and not multiplayer.is_server():
		_interpolate()
	visual.position = visual.position.lerp(Vector3.ZERO, clampf(12.0 * delta, 0.0, 1.0))
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, clampf(12.0 * delta, 0.0, 1.0))


func _interpolate() -> void:
	if _snapshots.is_empty():
		return
	var t := Time.get_ticks_msec() - INTERP_DELAY_MS
	var last: Array = _snapshots[-1]
	if t >= last[0]:
		global_position = last[1]
		facing = last[2]
		return
	for i in range(_snapshots.size() - 1, 0, -1):
		var a: Array = _snapshots[i - 1]
		var b: Array = _snapshots[i]
		if t >= a[0]:
			var k := float(t - a[0]) / maxf(b[0] - a[0], 1.0)
			global_position = (a[1] as Vector3).lerp(b[1], k)
			facing = lerp_angle(a[2], b[2], k)
			return
