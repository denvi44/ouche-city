extends SceneTree
## Captures de la mission 02 (agent 09) : garage, voiture tunée, casse et gardien, piste de drag, départ.
## Usage : godot --path game -s ../qa/screenshots/capture_m02.gd -- --out=DIR --mission=m02 --no-companions   (Vulkan conseillé)

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var mission
var car
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func ground(p: Vector2, up := 0.0) -> Vector3:
	return Vector3(p.x, world.builder.height_at(p.x, p.y) + up, p.y)


func shot(out_dir: String, name: String) -> void:
	await frames(6)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[m02-captures] ", name)


func look(from: Vector3, to: Vector3) -> void:
	cam.look_at_from_position(from, to, Vector3.UP)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[m02-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m02"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	world.day_night.hour = 11.0
	mission = world.mission
	mission.deadline_hour = 99.0      # on joue avec l'heure pour le plan de nuit : pas d'échec « 21 h » pendant les captures
	car = world.van
	cam = Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	var player = world.players_root.get_node("1")
	# 1. Le garage de Kévin et la Fusée d'origine (aucune pièce).
	player.global_position = ground(Vector2(mission.zones.garage.x + 6, mission.zones.garage.z + 6), 0.6)
	await frames(30)
	var g: Vector3 = mission.zones.garage
	look(car.global_position + Vector3(5.5, 2.2, 4.5), car.global_position + Vector3(0, 0.9, 0))
	await shot(out_dir, "m02_1_fusee_d_origine")
	# 2. La Fusée tunée : toutes les pièces, de nuit (néons).
	world.day_night.hour = 21.5
	world.day_night.apply()
	car.set_parts(["jantes", "pot", "neons", "caisson", "aileron"])
	await frames(10)
	look(car.global_position + Vector3(5.0, 1.6, 3.8), car.global_position + Vector3(0, 0.7, 0.2))
	await shot(out_dir, "m02_2_fusee_tunee_de_nuit")
	world.day_night.hour = 11.0
	world.day_night.apply()
	look(car.global_position + Vector3(5.5, 2.0, -4.5), car.global_position + Vector3(0, 0.8, 0.8))
	await shot(out_dir, "m02_3_fusee_tunee_de_jour")
	# 3. La casse et son gardien.
	var c: Vector3 = mission.zones.casse
	var gd = mission.guard
	gd.global_position = c + Vector3(-5, 0.5, 6)
	player.global_position = c + Vector3(2.0, 0.6, 1.0)
	await frames(30)
	look(c + Vector3(-9, 5.0, 12), c + Vector3(-1, 1.0, 1.5))
	await shot(out_dir, "m02_4_la_casse_et_le_gardien")
	# 4. HUD du marchandage.
	player.global_position = mission.zones.annonce + Vector3(1.5, 0.6, 1.0)
	await frames(20)
	mission.interact(1)
	await frames(10)
	var poi = CityBuilder.read_json("res://assets/city/poi.json")
	var af := 0.0
	for p in poi.pois:
		if p.id == "annonce_vendeur":
			af = float(p.facing)
	var front := Vector3(sin(af), 0, cos(af))        # côté rue : là où s'ouvre la façade
	look(mission.zones.annonce + front * 9.0 + Vector3(0, 3.0, 0), mission.zones.annonce + Vector3(0, 1.6, 0))
	await shot(out_dir, "m02_5_marchandage")
	mission.menu = ""
	# 5. La piste de drag : vue d'ensemble, puis la grille de départ.
	var s: Vector3 = mission.zones.start
	var d := Vector3(mission.strip_dir.x, 0, mission.strip_dir.y)
	look(s - d * 30.0 + Vector3(0, 14.0, 0) + Vector3(-d.z, 0, d.x) * 18.0, s + d * 130.0)
	await shot(out_dir, "m02_6_piste_de_drag")
	# Grille : la Fusée et Dylan côte à côte, compte à rebours.
	for id in ["jantes", "pot", "aileron", "neons"]:
		if not (id in mission.parts):
			mission.parts.append(id)
	car.set_parts(mission.parts)
	mission.step = "drag"
	player.global_position = ground(Vector2(s.x, s.z), 0.6) - d * 30.0
	car.driver = 1
	car.controller = 1
	mission._start_race()
	await frames(5)
	look(s - d * 9.0 + Vector3(-d.z, 0, d.x) * 7.0 + Vector3(0, 2.2, 0), s + d * 4.0 + Vector3(0, 0.8, 0))
	await shot(out_dir, "m02_7_la_grille")
	print("[m02-captures] terminé")
	quit(0)
