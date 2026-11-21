class_name ScriptedBody
extends NetBody
## Corps animé par le serveur selon un script (tracteur, vaches) : agent 06.
## Aucun contrôleur humain : le serveur appelle `script_input` à chaque pas et simule avec
## `simulate`, la réplication (état à 20 Hz, interpolation côté clients) vient de `NetBody`.
## Entrée : {"speed": m/s, "yaw": rad}. Le corps avance dans la direction du lacet.

const GRAVITY := 20.0
const TURN_RATE := 3.0               # rad/s : les virages sont progressifs

var active := false : set = set_active
var yaw := 0.0
var speed_now := 0.0
var shape_node: CollisionShape3D
var radius := 0.6


func _ready() -> void:
	floor_snap_length = 0.6
	_build_visual()
	set_active(false)


func _build_visual() -> void:
	pass


func get_facing() -> float:
	return yaw


func set_facing(f: float) -> void:
	yaw = f
	rotation.y = f


func neutral_input() -> Dictionary:
	return {"speed": 0.0, "yaw": yaw}


func server_input(delta: float) -> Dictionary:
	return script_input(delta) if active else neutral_input()


## À surcharger : décision du pas (serveur).
func script_input(_delta: float) -> Dictionary:
	return neutral_input()


func simulate(inp: Dictionary, delta: float) -> void:
	if not active:
		return
	var target: float = inp.yaw
	yaw = lerp_angle(yaw, target, clampf(TURN_RATE * delta, 0.0, 1.0))
	rotation.y = yaw
	speed_now = move_toward(speed_now, float(inp.speed), 6.0 * delta)
	velocity.x = -sin(yaw) * speed_now
	velocity.z = -cos(yaw) * speed_now
	if is_on_floor():
		velocity.y = -2.0
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -40.0)
	move_and_slide()


func set_active(a: bool) -> void:
	active = a
	visible = a
	if is_inside_tree() or shape_node:
		_apply_collision()


func _apply_collision() -> void:
	if shape_node:
		shape_node.set_deferred("disabled", not active)


## Place le corps (tous les pairs) : position, cap, vitesse nulle.
func teleport(pos: Vector3, heading: float) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	speed_now = 0.0
	set_facing(heading)
	_snapshots.clear()


func _toon(color: Color, reflet := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/toon.gdshader")
	m.set_shader_parameter("couleur", color)
	m.set_shader_parameter("reflet_force", reflet)
	return m


## Boîte colorée posée dans `parent`, ajoutée aux triangles de contour `tris`.
func _part(parent: Node3D, tris: Array, size: Vector3, pos: Vector3, color: Color, reflet := 0.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _toon(color, reflet)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	tris.append_array(HullOutline.tris_of(mesh, Transform3D(Basis.from_euler(rot), pos)))
	return mi


func _finish_hull(parent: Node3D, tris: Array) -> void:
	var hull := MeshInstance3D.new()
	hull.name = "Contours"
	hull.mesh = HullOutline.build(tris)
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(hull)
