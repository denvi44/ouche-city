extends Node3D
## Caméra à la troisième personne : souris ou stick droit, bras à ressort contre les murs.

var target: Node3D
var yaw := 0.0
var pitch := -0.25
var camera: Camera3D
var _arm: SpringArm3D


func _ready() -> void:
	top_level = true
	_arm = SpringArm3D.new()
	_arm.spring_length = 4.5
	_arm.margin = 0.3
	_arm.add_excluded_object(target.get_rid())
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 1500.0
	_arm.add_child(camera)
	camera.add_child(make_outline_quad())
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Quad plein écran portant le post-process de contours du décor.
## Forward+ uniquement (Vulkan/Metal) : le rendu Compatibility de Godot 4.4 n'expose pas
## la texture de profondeur ; les captures « _compat » de la CI sont donc sans contours de décor.
static func make_outline_quad() -> Node3D:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		var none := Node3D.new()
		none.name = "ContoursEcran_Indisponible"
		return none
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/contour_ecran.gdshader")
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "ContoursEcran"
	mi.mesh = quad
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * Settings.mouse_sensitivity
		var dy: float = event.relative.y * Settings.mouse_sensitivity
		pitch += dy if Settings.invert_y else -dy
	elif event is InputEventMouseButton and event.pressed and not get_tree().paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw -= stick.x * 2.5 * delta
	pitch += (stick.y if Settings.invert_y else -stick.y) * 2.0 * delta
	pitch = clampf(pitch, -1.2, 0.5)
	if target:
		global_position = target.global_position + Vector3(0, 1.7, 0)
	rotation = Vector3(pitch, yaw, 0)
