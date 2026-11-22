class_name RainFx
extends Node3D
## Pluie locale (décor de la mission 9) : un rideau de traînées qui suit la caméra. Rien n'est répliqué, rien n'est solide.
## Absent en headless (serveur dédié, tests).

const AMOUNT := 1400
const AREA := 46.0
const HEIGHT := 22.0

var _rain: CPUParticles3D


static func is_available() -> bool:
	return DisplayServer.get_name() != "headless"


func _ready() -> void:
	name = "Pluie"
	if not is_available():
		return
	_rain = CPUParticles3D.new()
	_rain.amount = AMOUNT
	_rain.lifetime = 0.9
	_rain.local_coords = false
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(AREA, 0.5, AREA)
	_rain.direction = Vector3(0.12, -1, 0.04)
	_rain.spread = 3.0
	_rain.initial_velocity_min = 26.0
	_rain.initial_velocity_max = 32.0
	_rain.gravity = Vector3.ZERO
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.7, 0.025)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.78, 0.86, 0.95, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_rain.mesh = mesh
	add_child(_rain)


func _process(_delta: float) -> void:
	if _rain == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam:
		_rain.global_position = cam.global_position + Vector3(0, HEIGHT, 0)
