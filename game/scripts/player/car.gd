class_name Car
extends Vehicle
## La Fusée de Kévin (mission 02) : une petite voiture de sport tuning, plus vive que la camionnette.
## Les pièces posées (pot, jantes, néons, caisson, aileron) changent son aspect, son son et ses
## performances ; le turbo est à usage unique et casse le moteur s'il est lancé trop tôt.

const BASE_MAX_SPEED := 27.0        # 97 km/h
const BASE_ACCEL := 8.8
const BOOST_SPEED := 5.0            # m/s en plus pendant le turbo
const BOOST_ACCEL := 1.6           # multiplicateur de poussée pendant le turbo
const BROKEN_SPEED := 12.0          # plafond quand le moteur a lâché
const PARTS := ["jantes", "pot", "neons", "caisson", "aileron"]

var installed: Array = []           # pièces posées
var boosting := false               # turbo en cours (répliqué par la mission)
var engine_broken := false          # moteur cassé (répliqué par la mission)
var body_color := Color(0.95, 0.5, 0.12)

var _part_nodes := {}
var _rim_nodes: Array = []          # belles jantes (une par roue), cachées tant que la pièce n'est pas posée
var _neon_light: OmniLight3D


func _init() -> void:
	max_speed = BASE_MAX_SPEED
	accel = BASE_ACCEL
	brake_force = 19.0
	coast_decel = 2.0
	wheelbase = 2.6
	max_steer = 0.55
	max_reverse = 6.0
	vehicle_name = "La Fusée de Kévin"


func has_part(name: String) -> bool:
	return name in installed


func current_max_speed() -> float:
	var m := max_speed
	if boosting:
		m += BOOST_SPEED
	if engine_broken:
		m = minf(m, BROKEN_SPEED)
	return m


func current_accel() -> float:
	var a := accel
	if boosting:
		a *= BOOST_ACCEL
	if engine_broken:
		a *= 0.35
	return a


## Pose exactement ces pièces : change les performances et affiche les accessoires.
func set_parts(parts: Array) -> void:
	installed = parts.duplicate()
	max_speed = BASE_MAX_SPEED * (1.06 if has_part("pot") else 1.0) * (1.012 if has_part("jantes") else 1.0)
	accel = BASE_ACCEL * (1.12 if has_part("pot") else 1.0)
	max_steer = 0.55 * (1.08 if has_part("aileron") else 1.0) * (1.04 if has_part("jantes") else 1.0)
	engine_pitch_mult = 1.22 if has_part("pot") else 1.0
	for n in PARTS:
		if _part_nodes.has(n):
			(_part_nodes[n] as Node3D).visible = has_part(n)
	for r in _rim_nodes:
		(r as Node3D).visible = has_part("jantes")
	if _neon_light:
		_neon_light.visible = has_part("neons")


## Performance globale (pour calibrer l'adversaire et les tests).
func perf() -> float:
	return max_speed * accel


# --- Carrosserie -----------------------------------------------------------------------------------------

func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visuel"
	add_child(visual)
	_body_visual = Node3D.new()
	_body_visual.name = "Caisse"
	visual.add_child(_body_visual)
	var tris := []
	var blanc := Color(0.96, 0.94, 0.9)
	# Avant de la voiture = -Z.
	var parts := [
		[Vector3(1.8, 0.55, 4.2), Vector3(0, 0.62, 0), body_color, 0.6],            # caisse basse
		[Vector3(1.55, 0.5, 2.0), Vector3(0, 1.1, 0.35), body_color, 0.5],          # habitacle
		[Vector3(1.4, 0.4, 0.06), Vector3(0, 1.12, -0.67), Color(0.2, 0.26, 0.32), 0.9],   # pare-brise
		[Vector3(1.4, 0.38, 0.06), Vector3(0, 1.12, 1.37), Color(0.2, 0.26, 0.32), 0.9],   # lunette arrière
		[Vector3(0.22, 0.04, 3.4), Vector3(0, 0.91, 0.0), blanc, 0.3],              # bandeau blanc sur le capot et le toit
		[Vector3(1.9, 0.2, 0.3), Vector3(0, 0.38, -2.15), Color(0.88, 0.86, 0.82), 0.4],   # pare-chocs avant
		[Vector3(1.9, 0.2, 0.3), Vector3(0, 0.38, 2.15), Color(0.88, 0.86, 0.82), 0.4],    # pare-chocs arrière
		[Vector3(0.34, 0.16, 0.08), Vector3(-0.62, 0.68, -2.12), Color(1.0, 0.93, 0.55), 0.0],
		[Vector3(0.34, 0.16, 0.08), Vector3(0.62, 0.68, -2.12), Color(1.0, 0.93, 0.55), 0.0],
		[Vector3(0.3, 0.14, 0.08), Vector3(-0.66, 0.7, 2.12), Color(0.8, 0.15, 0.12), 0.0],
		[Vector3(0.3, 0.14, 0.08), Vector3(0.66, 0.7, 2.12), Color(0.8, 0.15, 0.12), 0.0],
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
	# Roues (jante d'origine : terne ; « jantes » ajoute les belles).
	for wx in [-1.0, 1.0]:
		for wz in [-1.3, 1.3]:
			var pivot := Node3D.new()
			pivot.position = Vector3(wx * 0.92, 0.34, wz)
			_body_visual.add_child(pivot)
			var spin := Node3D.new()
			pivot.add_child(spin)
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.34
			cyl.bottom_radius = 0.34
			cyl.height = 0.26
			cyl.radial_segments = 14
			var wm := _toon(Color(0.14, 0.13, 0.12), 0.0)
			wm.next_pass = preload("res://assets/materials/contour_personnage.tres")
			cyl.material = wm
			var wi := MeshInstance3D.new()
			wi.mesh = cyl
			wi.rotation.z = PI / 2.0
			spin.add_child(wi)
			var hub := BoxMesh.new()
			hub.size = Vector3(0.28, 0.1, 0.1)
			hub.material = _toon(Color(0.6, 0.6, 0.58), 0.0)
			var hi := MeshInstance3D.new()
			hi.mesh = hub
			spin.add_child(hi)
			# Belle jante (pièce) : disque chromé large, caché tant qu'elle n'est pas posée.
			var rim := CylinderMesh.new()
			rim.top_radius = 0.27
			rim.bottom_radius = 0.27
			rim.height = 0.29
			rim.radial_segments = 10
			rim.material = _toon(Color(0.92, 0.93, 0.96), 0.9)
			var ri := MeshInstance3D.new()
			ri.mesh = rim
			ri.rotation.z = PI / 2.0
			ri.visible = false
			ri.name = "Jante"
			spin.add_child(ri)
			_wheels.append(pivot)
			if wz < 0.0:
				_front_wheels.append(pivot)
			_rim_nodes.append(ri)
	# Pièces visibles.
	_part_nodes["pot"] = _make_exhaust()
	_part_nodes["neons"] = _make_neons()
	_part_nodes["caisson"] = _make_subwoofer()
	_part_nodes["aileron"] = _make_spoiler()
	for n in ["pot", "neons", "caisson", "aileron"]:
		(_part_nodes[n] as Node3D).visible = false
		_body_visual.add_child(_part_nodes[n])
	_neon_light = OmniLight3D.new()
	_neon_light.light_color = Color(0.2, 0.9, 1.0)
	_neon_light.omni_range = 5.0
	_neon_light.light_energy = 1.4
	_neon_light.position = Vector3(0, 0.25, 0)
	_neon_light.shadow_enabled = false
	_neon_light.visible = false
	_body_visual.add_child(_neon_light)


func _unlit(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	return m


func _make_exhaust() -> Node3D:
	var n := Node3D.new()
	n.name = "Part_pot"
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.1
	pipe.bottom_radius = 0.1
	pipe.height = 0.9
	pipe.material = _toon(Color(0.82, 0.83, 0.86), 0.9)
	var pi := MeshInstance3D.new()
	pi.mesh = pipe
	pi.rotation.x = PI / 2.0
	pi.position = Vector3(0.5, 0.32, 2.05)
	n.add_child(pi)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.14
	tip.bottom_radius = 0.14
	tip.height = 0.18
	tip.material = _toon(Color(0.45, 0.45, 0.48), 0.9)
	var ti := MeshInstance3D.new()
	ti.mesh = tip
	ti.rotation.x = PI / 2.0
	ti.position = Vector3(0.5, 0.32, 2.5)
	n.add_child(ti)
	return n


func _make_neons() -> Node3D:
	var n := Node3D.new()
	n.name = "Part_neons"
	for sx in [-0.85, 0.85]:
		var bar := BoxMesh.new()
		bar.size = Vector3(0.07, 0.05, 3.4)
		bar.material = _unlit(Color(0.2, 0.95, 1.0))
		var bi := MeshInstance3D.new()
		bi.mesh = bar
		bi.position = Vector3(sx, 0.25, 0)
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(bi)
	return n


func _make_subwoofer() -> Node3D:
	var n := Node3D.new()
	n.name = "Part_caisson"
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.55, 0.5)
	box.material = _toon(Color(0.12, 0.12, 0.14), 0.2)
	var bi := MeshInstance3D.new()
	bi.mesh = box
	bi.position = Vector3(0, 1.0, 1.05)
	n.add_child(bi)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.2
	cone.bottom_radius = 0.12
	cone.height = 0.1
	cone.material = _toon(Color(0.7, 0.7, 0.72), 0.5)
	var ci := MeshInstance3D.new()
	ci.mesh = cone
	ci.rotation.x = PI / 2.0
	ci.position = Vector3(0, 1.0, 0.78)
	n.add_child(ci)
	return n


func _make_spoiler() -> Node3D:
	var n := Node3D.new()
	n.name = "Part_aileron"
	for sx in [-0.55, 0.55]:
		var post := BoxMesh.new()
		post.size = Vector3(0.08, 0.35, 0.12)
		post.material = _toon(Color(0.1, 0.1, 0.12))
		var pi := MeshInstance3D.new()
		pi.mesh = post
		pi.position = Vector3(sx, 1.05, 1.9)
		n.add_child(pi)
	var wing := BoxMesh.new()
	wing.size = Vector3(1.9, 0.07, 0.5)
	wing.material = _toon(Color(0.12, 0.12, 0.14), 0.5)
	var wi := MeshInstance3D.new()
	wi.mesh = wing
	wi.position = Vector3(0, 1.28, 1.95)
	n.add_child(wi)
	return n
