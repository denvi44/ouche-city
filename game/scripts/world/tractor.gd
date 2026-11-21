class_name Tractor
extends ScriptedBody
## Tracteur lent de la mission 01 (événement « slow_tractor ») : il suit l'itinéraire à 3 m/s,
## devant la camionnette, puis quitte la route (il « rentre à la ferme »).

const SPEED := 3.0                  # 11 km/h : le tracteur de Monsieur Lepommier
const WAYPOINT_RADIUS := 2.0

## Itinéraire à suivre (x, z), serveur seulement.
var path := PackedVector2Array()
var _wp := 0
var finished := false
var _loop: AudioStreamPlayer3D


func _ready() -> void:
	radius = 1.3
	shape_node = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.2, 3.6)
	shape_node.shape = box
	shape_node.position.y = 1.2
	add_child(shape_node)
	_loop = Sfx.make_loop("tractor", -4.0)
	if _loop:
		add_child(_loop)
	super._ready()


func set_active(a: bool) -> void:
	super.set_active(a)
	if _loop:
		if a and not _loop.playing:
			_loop.play()
		elif not a:
			_loop.stop()


func start_route(p: PackedVector2Array) -> void:
	path = p
	_wp = 1
	finished = false


func script_input(_delta: float) -> Dictionary:
	if path.size() < 2 or finished:
		return {"speed": 0.0, "yaw": yaw}
	var here := Vector2(global_position.x, global_position.z)
	while _wp < path.size() - 1 and here.distance_to(path[_wp]) < WAYPOINT_RADIUS:
		_wp += 1
	if _wp >= path.size() - 1 and here.distance_to(path[path.size() - 1]) < WAYPOINT_RADIUS:
		finished = true
		return {"speed": 0.0, "yaw": yaw}
	var d := path[_wp] - here
	return {"speed": SPEED, "yaw": atan2(-d.x, -d.y)}


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visuel"
	add_child(visual)
	var tris := []
	var vert := Color(0.25, 0.55, 0.3)
	var rouge := Color(0.78, 0.22, 0.18)
	# Avant du tracteur = -Z.
	_part(visual, tris, Vector3(1.5, 1.0, 2.2), Vector3(0, 1.05, -0.8), vert, 0.5)         # capot
	_part(visual, tris, Vector3(1.7, 1.6, 1.3), Vector3(0, 1.8, 0.9), vert, 0.4)            # cabine
	_part(visual, tris, Vector3(1.5, 0.7, 0.06), Vector3(0, 2.0, 0.24), Color(0.2, 0.26, 0.32), 0.9)  # pare-brise
	_part(visual, tris, Vector3(1.9, 0.12, 1.5), Vector3(0, 2.65, 0.9), rouge, 0.2)         # toit
	_part(visual, tris, Vector3(0.14, 0.9, 0.14), Vector3(0.45, 2.0, -1.55), Color(0.3, 0.3, 0.32))  # échappement
	_part(visual, tris, Vector3(1.0, 0.5, 0.3), Vector3(0, 0.7, -1.95), rouge, 0.2)         # calandre
	_part(visual, tris, Vector3(1.2, 0.2, 1.0), Vector3(0, 0.75, 1.9), Color(0.35, 0.3, 0.28))  # attelage
	_finish_hull(visual, tris)
	# Roues : grandes à l'arrière, petites à l'avant.
	for spec in [[-1.0, 0.95, 0.75], [1.0, 0.95, 0.75], [-0.85, -1.3, 0.42], [0.85, -1.3, 0.42]]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = spec[2]
		cyl.bottom_radius = spec[2]
		cyl.height = 0.5 if spec[2] > 0.5 else 0.3
		cyl.radial_segments = 14
		var wm := _toon(Color(0.15, 0.13, 0.12))
		wm.next_pass = preload("res://assets/materials/contour_personnage.tres")
		cyl.material = wm
		var wi := MeshInstance3D.new()
		wi.mesh = cyl
		wi.rotation.z = PI / 2.0
		wi.position = Vector3(spec[0] * 1.05, spec[2], spec[1])
		visual.add_child(wi)
	# Le fermier, à son volant (béret, forcément).
	var farmer := CharacterModel.make(Color(0.3, 0.4, 0.62), Color(0.35, 0.3, 0.24), Color(0.4, 0.3, 0.2))
	farmer.position = Vector3(0, 1.15, 0.95)
	farmer.scale = Vector3.ONE * 0.8
	farmer.pose_override = {"speed": 0.0}
	visual.add_child(farmer)
