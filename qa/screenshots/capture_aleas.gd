extends SceneTree
## Captures des événements de route (agent 09) : nid-de-poule, tracteur lent, vaches, klaxon.
## Usage : godot --path game -s ../qa/screenshots/capture_aleas.gd -- --out=DIR --no-companions   (Vulkan conseillé)

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var mission
var van
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func wait(sec: float) -> void:
	await create_timer(sec).timeout


func place(node, pos: Vector3) -> void:
	node.global_position = pos
	node.velocity = Vector3.ZERO


func ground(p: Vector2, up := 0.6) -> Vector3:
	return Vector3(p.x, world.builder.height_at(p.x, p.y) + up, p.y)


func shot(out_dir: String, name: String) -> void:
	await frames(5)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[aleas-captures] ", name)


## Caméra derrière la camionnette, regardant dans le sens de la route.
func chase(target: Vector3, back := 9.0, up := 3.2) -> void:
	var f: Vector3 = van.forward()
	cam.look_at_from_position(van.global_position - f * back + Vector3(0, up, 0), target, Vector3.UP)


func face_van_along(p: Vector2, q: Vector2) -> void:
	van.rotation.y = atan2(-(q.x - p.x), -(q.y - p.y))


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[aleas-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/aleas"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	world.day_night.hour = 11.0
	mission = world.mission
	van = world.van
	cam = Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	for id in mission.crates.keys():
		mission.crates[id].state = "loaded"
	mission.cargo = 24
	mission.step = "road"
	mission._mark()
	await frames(20)
	var route: PackedVector2Array = mission.route
	# 1. Nid-de-poule : la camionnette approche (visible : disque sombre à rebord clair).
	var p0: Vector2 = mission.potholes[2]
	var r0: Dictionary = mission.route_at(mission.route_length * 0.42 - 12.0)
	face_van_along(r0.pos, p0)
	place(van, ground(r0.pos))
	van.speed = 0.0
	await frames(10)
	chase(ground(p0, 0.2), 7.0, 2.6)
	await shot(out_dir, "aleas_1_nid_de_poule")
	# La camionnette tombe dedans à 40 km/h : bouteilles perdues, secousse, message.
	place(van, ground(p0))
	van.speed = 11.0
	await frames(12)
	chase(ground(p0, 0.2), 7.0, 2.6)
	await shot(out_dir, "aleas_2_choc_nid_de_poule")
	# 2. Tracteur : réveillé à l'approche, il roule devant.
	var rt: Dictionary = mission.route_at(mission.route_length * mission.TRACTOR_FROM - 16.0)
	var rt2: Dictionary = mission.route_at(mission.route_length * mission.TRACTOR_FROM)
	face_van_along(rt.pos, rt2.pos)
	place(van, ground(rt.pos))
	van.speed = 0.0
	await wait(5.0)
	var tp: Vector3 = mission.tractor.global_position
	chase(tp + Vector3(0, 1.5, 0), 8.0, 3.0)
	await shot(out_dir, "aleas_3_tracteur_devant")
	# 3. Vaches : elles traversent, puis s'arrêtent au milieu.
	mission.tractor.finished = true
	var cp := Vector2.ZERO
	for rp in route:
		if rp.distance_to(mission.cow_center) >= 22.0 and rp.distance_to(mission.cow_center) < 30.0:
			cp = rp
			break
	face_van_along(cp, mission.cow_center)
	place(van, ground(cp))
	van.speed = 0.0
	await wait(12.0)
	chase(ground(mission.cow_center, 1.0), 9.0, 3.4)
	await shot(out_dir, "aleas_4_vaches_sur_la_route")
	# 4. Coup de klaxon : elles détalent.
	mission.horn()
	await wait(2.0)
	chase(ground(mission.cow_center, 1.0), 9.0, 3.4)
	await shot(out_dir, "aleas_5_klaxon")
	print("[aleas-captures] terminé : ", mission.messages.size(), " messages")
	quit(0)
