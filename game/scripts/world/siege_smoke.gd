class_name SiegeSmoke
extends Node3D
## Fumée épaisse, verte puis jaunâtre, du camembert (mission 9) : un gros panache de bulles qui montent et s'étalent. Local, sans collision.

var _puffs: CPUParticles3D


static func is_available() -> bool:
	return DisplayServer.get_name() != "headless"


func _ready() -> void:
	name = "FumeeVerte"
	if not is_available():
		return
	_puffs = CPUParticles3D.new()
	_puffs.amount = 150
	_puffs.lifetime = 8.0
	_puffs.explosiveness = 0.15
	_puffs.local_coords = false
	_puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_puffs.emission_sphere_radius = 6.0
	_puffs.direction = Vector3(0, 0.2, 0)
	_puffs.spread = 180.0
	_puffs.initial_velocity_min = 1.5
	_puffs.initial_velocity_max = 4.5
	_puffs.gravity = Vector3(0, 0.1, 0)
	_puffs.damping_min = 0.9
	_puffs.damping_max = 1.4
	_puffs.scale_amount_min = 2.4
	_puffs.scale_amount_max = 5.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(0.5, 1.0))
	grow.add_point(Vector2(1, 1.5))
	_puffs.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(0.4, 0.8, 0.15, 0.0), Color(0.42, 0.85, 0.16, 0.5), Color(0.82, 0.85, 0.22, 0.42), Color(0.9, 0.88, 0.4, 0.0)])
	_puffs.color_ramp = ramp
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	_puffs.mesh = mesh
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_puffs)
	_puffs.emitting = true
