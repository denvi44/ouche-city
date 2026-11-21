class_name ExhaustFx
extends CPUParticles3D
## Fumée d'échappement « dessin animé » : petites bouffées grises qui sortent du pot, gonflent, montent et s'effacent.
## Purement visuelle et locale (aucune réplication). `set_level(0..1)` : 0 = moteur coupé, 1 = plein régime (bouffées plus nombreuses).
## Usage : ExhaustFx.attach(parent, position_locale, direction_locale)

const GREY := Color(0.52, 0.52, 0.56)


static func attach(parent: Node3D, pos: Vector3, dir := Vector3(0, 0.25, 1)) -> ExhaustFx:
	var p := ExhaustFx.new()
	p.name = "Echappement"
	p.position = pos
	p.dir_local = dir
	parent.add_child(p)
	return p


var dir_local := Vector3(0, 0.25, 1)


func _ready() -> void:
	emitting = false
	local_coords = false                    # les bouffées restent dans le monde : elles traînent derrière le véhicule
	amount = 16
	lifetime = 1.1
	direction = dir_local.normalized()
	spread = 22.0
	initial_velocity_min = 0.6
	initial_velocity_max = 1.4
	gravity = Vector3(0, 0.45, 0)
	damping_min = 0.4
	damping_max = 0.9
	scale_amount_min = 0.07
	scale_amount_max = 0.15
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, 2.2))
	scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(GREY, 0.0))
	g.set_color(1, Color(GREY, 0.0))
	g.add_point(0.1, Color(GREY.lightened(0.1), 0.55))
	g.add_point(0.6, Color(GREY, 0.3))
	color_ramp = g
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.material = mat
	mesh = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Régime du moteur (0 : coupé). Plus il est haut, plus les bouffées se succèdent vite ; jamais plus de 16 particules par véhicule.
func set_level(level: float) -> void:
	var on := level > 0.04
	if emitting != on:
		emitting = on
	if on:
		speed_scale = clampf(0.6 + 1.0 * level, 0.6, 1.6)      # plus de régime = bouffées plus rapprochées
