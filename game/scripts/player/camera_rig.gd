extends Node3D
## Caméra à la troisième personne : souris ou stick droit, bras à ressort contre les murs.

var target: Node3D
var yaw := 0.0
var pitch := -0.25
var camera: Camera3D
var _arm: SpringArm3D


var distance := 4.5


func _ready() -> void:
	top_level = true
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = 0.3
	_arm.add_excluded_object(target.get_rid())
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 1500.0
	_arm.add_child(camera)
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Change la cible suivie (joueur ↔ véhicule) et la distance du bras.
func set_target(node: Node3D, dist: float) -> void:
	target = node
	distance = dist
	if _arm:
		_arm.clear_excluded_objects()
		if node is CollisionObject3D:
			_arm.add_excluded_object((node as CollisionObject3D).get_rid())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_t = Time.get_ticks_msec() / 1000.0
		yaw -= event.relative.x * Settings.mouse_sensitivity
		var dy: float = event.relative.y * Settings.mouse_sensitivity
		pitch += dy if Settings.invert_y else -dy
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


var _mouse_t := -10.0


func _mouse_recent() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _mouse_t < 1.2


func _process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw -= stick.x * 2.5 * delta
	pitch += (stick.y if Settings.invert_y else -stick.y) * 2.0 * delta
	pitch = clampf(pitch, -1.2, 0.5)
	if _arm:
		_arm.spring_length = lerpf(_arm.spring_length, distance, clampf(4.0 * delta, 0.0, 1.0))
	# En voiture, la caméra se range doucement derrière le véhicule quand il avance.
	if target is Vehicle and absf((target as Vehicle).speed) > 2.0 and stick.length() < 0.2 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _mouse_recent():
		yaw = lerp_angle(yaw, target.rotation.y + (PI if (target as Vehicle).speed < 0.0 else 0.0), clampf(1.6 * delta, 0.0, 1.0))
		pitch = lerpf(pitch, -0.22, clampf(2.0 * delta, 0.0, 1.0))
	if target:
		global_position = target.global_position + Vector3(0, 1.7, 0)
	rotation = Vector3(pitch, yaw, 0)
