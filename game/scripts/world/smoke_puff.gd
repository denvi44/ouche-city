extends CPUParticles3D
## Nuage de fumée « dessin animé » (agent 03) : bouffées rondes, vert-beige pâle, qui gonflent, montent et s'effacent.
## Purement visuel, déclenché côté client par les événements répliqués de la mission (rien n'est simulé sur le serveur).
## Usage : SmokePuff.spawn(parent, position, taille) — 0,5 = petite fuite, 1 = crampe, 2,2 = accident.

const GREEN := Color(0.72, 0.8, 0.45)


static func spawn(parent: Node, pos: Vector3, size := 1.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.set_script(preload("res://scripts/world/smoke_puff.gd"))
	parent.add_child(p)
	p.global_position = pos
	p.setup(size)
	return p


func setup(size: float) -> void:
	one_shot = true
	explosiveness = 0.85
	amount = clampi(int(6.0 + 7.0 * size), 6, 28)
	lifetime = 1.2 + 0.5 * size
	direction = Vector3(0, 0.5, 0)
	spread = 70.0
	initial_velocity_min = 0.5 * size
	initial_velocity_max = 1.8 * size
	gravity = Vector3(0, 0.5, 0)            # la fumée monte
	damping_min = 1.2
	damping_max = 2.0
	scale_amount_min = 0.35 * size
	scale_amount_max = 0.7 * size
	var curve := Curve.new()                # gonfle puis se tasse
	curve.add_point(Vector2(0.0, 0.3))
	curve.add_point(Vector2(0.35, 1.0))
	curve.add_point(Vector2(1.0, 1.5))
	scale_amount_curve = curve
	var g := Gradient.new()                 # opaque puis transparent
	g.set_color(0, Color(GREEN.lightened(0.15), 0.0))
	g.set_color(1, Color(GREEN, 0.0))
	g.add_point(0.12, Color(GREEN.lightened(0.15), 0.8))
	g.add_point(0.6, Color(GREEN, 0.55))
	color_ramp = g
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color.WHITE
	mesh.material = mat
	self.mesh = mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitting = true
	get_tree().create_timer(lifetime + 0.5).timeout.connect(queue_free)
