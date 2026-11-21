class_name TitleBackdrop
extends SubViewportContainer
## Fond animé de l'écran titre : le village vu par un drone qui enchaîne les plans (DroneShots) avec des fondus.
## La ville est construite dans un SubViewport à part (own_world_3d) : rien n'est partagé avec la partie.
## Absent en mode headless (serveur dédié, tests) : le menu garde alors son fond uni.

const CITY_DIR := "res://assets/city"
const FADE := 0.9
const SHIFT := 0.2           # part de la largeur de l'image dont le sujet est décalé vers la droite
const HOUR := 17.3          # lumière dorée de fin d'après-midi

var shots: Array = []
var _builder: CityBuilder
var _cam: Camera3D
var _veil: ColorRect
var _caption: Label
var _index := 0
var _t := 0.0
var _ready_3d := false
var _ready_cb: Callable


static func available() -> bool:
	return DisplayServer.get_name() != "headless"


func _init() -> void:
	stretch = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = 0.0


## Construit la ville (quelques secondes) puis lance le premier plan. Appelé après l'affichage du menu.
func start() -> void:
	if not available() or _ready_3d:
		return
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.handle_input_locally = false
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/ciel_peint.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.82, 0.78)
	env.fog_density = 0.0011
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 400.0
	vp.add_child(sun)
	var dn := DayNight.new()
	dn.sun = sun
	dn.environment = env
	dn.hour = HOUR
	dn.running = false
	vp.add_child(dn)
	_builder = CityBuilder.new()
	var city := _builder.build_city(CITY_DIR, "")
	# Une affiche, pas un plan de mission : ni faisceaux, ni étiquettes de lieux.
	# On garde les décors (gare, mare, enclos, camionnette…), on retire seulement faisceaux et étiquettes.
	var marks := city.get_node_or_null("LieuxDeMission")
	if marks:
		for lieu in marks.get_children():
			for c in lieu.get_children():
				if c is Label3D or (c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh):
					c.free()
	vp.add_child(city)
	_cam = Camera3D.new()
	_cam.far = 1800.0
	_cam.current = true
	vp.add_child(_cam)
	shots = DroneShots.shots(_lieux(), _centre())
	# Voile noir (fondus entre plans) et légende, par-dessus l'image 3D.
	_veil = ColorRect.new()
	_veil.color = Color(0.05, 0.04, 0.06)
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_ready_3d = true
	_index = 0
	_t = 0.0
	_apply(0.0)
	create_tween().tween_property(self, "modulate:a", 1.0, 1.2)


func caption() -> String:
	return str(shots[_index].nom) if _ready_3d and not shots.is_empty() else ""


func _lieux() -> Dictionary:
	var out := {}
	var poi = CityBuilder.read_json(CITY_DIR.path_join("poi.json"))
	if poi is Dictionary:
		for p in poi.get("pois", []):
			out[str(p.id)] = Vector2(float(p.position[0]), float(p.position[1]))
	return out


func _centre() -> Vector2:
	var m := CityBuilder.load_manifest(CITY_DIR)
	if m.has("pocCentre"):
		return Vector2(float(m.pocCentre[0]), float(m.pocCentre[1]))
	return Vector2(1400, 1400)


func _process(delta: float) -> void:
	if not _ready_3d or shots.is_empty():
		return
	_t += delta
	var dur: float = float(shots[_index].duree)
	if _t >= dur:
		_t = 0.0
		_index = (_index + 1) % shots.size()
		dur = float(shots[_index].duree)
	_apply(_t / dur)
	# Fondu au noir en début et en fin de plan.
	var edge := minf(_t, dur - _t)
	_veil.color.a = clampf(1.0 - edge / FADE, 0.0, 1.0)
	if _caption:
		_caption.text = caption()


func _apply(u: float) -> void:
	var p: Dictionary = DroneShots.pose(shots[_index], u, _builder.height_at)
	_cam.fov = p.fov
	_cam.global_position = p.pos
	_cam.look_at(p.cible, Vector3.UP)
	# La carte couvre le tiers gauche : on décale le cadrage pour que le sujet reste dans la partie visible.
	_cam.h_offset = -SHIFT * _cam.global_position.distance_to(p.cible) * tan(deg_to_rad(p.fov * 0.5)) * 2.0


## Étiquette de plan (« chip » Material) alimentée par le fond ; le menu la place où il veut.
func bind_caption(label: Label) -> void:
	_caption = label
