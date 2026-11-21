class_name Player
extends NetBody
## Joueur à pied (agent 05). La prédiction et la réplication viennent de `NetBody`.
## Quand le joueur conduit, il n'a plus de contrôleur propre : il suit le véhicule (invisible,
## sans collision) et les entrées vont au véhicule.

const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.5
const CARRY_FACTOR := 0.7             # une caisse de calva, ça pèse
const JUMP_VELOCITY := 5.2
const GRAVITY := 18.0
const ACCEL := 35.0
const PALETTE := [Color(0.85, 0.3, 0.25), Color(0.25, 0.5, 0.8), Color(0.95, 0.75, 0.2), Color(0.35, 0.65, 0.35),
	Color(0.65, 0.4, 0.75), Color(0.95, 0.55, 0.25), Color(0.3, 0.7, 0.7), Color(0.8, 0.45, 0.6)]

var peer_id := 1
var display_name := "Normand"
var facing := 0.0
## Porte une caisse (replicated par la mission).
var carrying := false
var vehicle: Vehicle = null

var camera_rig: Node3D
var model: CharacterModel

var _shape: CollisionShape3D
var _last_yaw := 0.0
var _bot_t := 0.0
var _bot_yaw := 0.0
var _bot_stuck := 0.0
var _was_driving := false


func _ready() -> void:
	peer_id = name.to_int()
	controller = peer_id
	_shape = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	_shape.shape = capsule
	_shape.position.y = 0.9
	add_child(_shape)
	_build_visual()
	if is_local() and Net.has_local_player() and DisplayServer.get_name() != "headless":
		camera_rig = preload("res://scripts/player/camera_rig.gd").new()
		camera_rig.name = "Camera"
		camera_rig.target = self
		add_child(camera_rig)


func is_local() -> bool:
	return multiplayer.has_multiplayer_peer() and peer_id == multiplayer.get_unique_id()


func is_driving() -> bool:
	return vehicle != null and vehicle.driver == peer_id


func get_facing() -> float:
	return facing


func set_facing(f: float) -> void:
	facing = f


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visuel"
	add_child(visual)
	var color: Color = PALETTE[absi(peer_id) % PALETTE.size()]
	model = CharacterModel.make(color)
	visual.add_child(model)
	var label := Label3D.new()
	label.text = display_name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.5
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.004
	label.no_depth_test = false
	add_child(label)


# --- Entrées ------------------------------------------------------------------------

var _bot_interacted := false


## Bot « conducteur » (QA) : va jusqu'à la camionnette, monte, puis Vehicle conduit tout droit.
func _bot_drive_input() -> Dictionary:
	var d := vehicle.global_position - global_position
	d.y = 0.0
	if d.length() < 3.2:
		if not _bot_interacted:
			_bot_interacted = true
			get_tree().current_scene.mission.request_interact()
		return neutral_input()
	d = d.normalized()
	return {"move": Vector2(0, -1), "yaw": atan2(-d.x, -d.z), "jump": false, "sprint": false}


func gather_input(delta: float) -> Dictionary:
	if Net.bot and Net.arg("bot-drive") != null and vehicle:
		return _bot_drive_input()
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


func neutral_input() -> Dictionary:
	return {"move": Vector2.ZERO, "yaw": _last_yaw, "jump": false, "sprint": false}


func pack_input(inp: Dictionary) -> PackedFloat32Array:
	return PackedFloat32Array([inp.move.x, inp.move.y, inp.yaw, 1.0 if inp.jump else 0.0, 1.0 if inp.sprint else 0.0])


func unpack_input(a: PackedFloat32Array) -> Dictionary:
	if a.size() < 5:
		return neutral_input()
	return {"move": Vector2(a[0], a[1]).limit_length(1.0), "yaw": a[2], "jump": a[3] > 0.5, "sprint": a[4] > 0.5}


func on_input_consumed(inp: Dictionary) -> void:
	_last_yaw = inp.yaw


## Simulation déterministe d'un pas de mouvement, partagée client/serveur.
func simulate(inp: Dictionary, delta: float) -> void:
	var mv: Vector2 = (inp.move as Vector2).limit_length(1.0)
	var dir := Vector3(mv.x, 0.0, mv.y).rotated(Vector3.UP, float(inp.yaw))
	var speed := SPRINT_SPEED if inp.sprint else WALK_SPEED
	if carrying:
		speed *= CARRY_FACTOR
	velocity.x = move_toward(velocity.x, dir.x * speed, ACCEL * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, ACCEL * delta)
	if is_on_floor():
		if inp.jump and not carrying:
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
	var driving := is_driving()
	if driving != _was_driving:
		_was_driving = driving
		_shape.disabled = driving
		visual.visible = not driving
		velocity = Vector3.ZERO
		if camera_rig:
			camera_rig.call("set_target", vehicle if driving else self, 7.5 if driving else 4.5)
	if driving:
		controller = 0
		global_position = vehicle.global_position + Vector3(0, 0.6, 0)
		return
	controller = peer_id
	super._physics_process(delta)


func _process(delta: float) -> void:
	if is_driving():
		return
	if model:
		model.carrying = carrying
		model.airborne = not is_on_floor() and absf(velocity.y) > 1.0
	super._process(delta)
	visual.rotation.y = lerp_angle(visual.rotation.y, facing, clampf(12.0 * delta, 0.0, 1.0))
