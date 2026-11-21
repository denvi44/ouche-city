extends SceneTree
## Captures de la mission 08 : l'oie meneuse, la mare et le troupeau, la voie et le passage à niveau, le train arrêté devant les oies.
## Usage : godot --path game -s ../qa/screenshots/capture_m08.gd -- --out=DIR   (Vulkan conseillé)
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var mission
var cam: Camera3D


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(out_dir: String, name: String) -> void:
	await frames(6)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[m08-captures] ", name)


func look(from: Vector3, to: Vector3, above := 0.0) -> void:
	from.y = maxf(from.y, world.builder.height_at(from.x, from.z) + above)
	cam.look_at_from_position(from, to, Vector3.UP)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m08"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	root.get_node("Net").mission_id = "m08"
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	mission = world.mission
	cam = Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	world.day_night.running = false
	world.day_night.hour = 17.5
	world.day_night.apply()
	mission.set_physics_process(false)
	var player = world.players_root.get_node("1")
	for c in world.players_root.get_children():
		if c.peer_id < 0:
			c.set_physics_process(false)
			c.global_position = Vector3(0, -200, 0)
	var dlg: DialoguePlayer = world.get_node("Dialogues")
	dlg.skip()
	var pond: Vector3 = mission.zones.pond
	var cross: Vector3 = mission.zones.crossing
	# 1. L'oie meneuse, de face, et le troupeau à la mare.
	var pp: Vector3 = player.global_position
	player.facing = 0.8
	await frames(30)
	look(pp + Vector3(2.2, 1.0, 3.5), pp + Vector3(0, 0.6, 0), 0.8)
	await shot(out_dir, "m08_1_oie_meneuse")
	look(pond + Vector3(-18, 5, -16), pond + Vector3(0, 0.5, 0), 3.0)
	await shot(out_dir, "m08_2_la_mare")
	# 2. La voie et le passage à niveau (garde-barrière, croix de Saint-André).
	look(mission.track_to_world(Vector2(-22, 12)) + Vector3(0, 3.5, 0), mission.track_to_world(Vector2(0, 3)) + Vector3(0, 1.2, 0), 2.5)
	await shot(out_dir, "m08_3_le_passage_a_niveau")
	# 3. Le train arrêté devant douze oies sur la voie.
	for g in mission.geese:
		g.st = "block"
		g.slot = int(g.id)
		var sp: Vector2 = mission.slot_to_world(int(g.slot))
		g.x = sp.x
		g.z = sp.y
		g.vx = 0.0
		g.vz = 0.0
	mission.train.st = "stopped"
	mission.train.v = 0.0
	mission.train.s = mission.train_start_u() * -1.0 + (mission.ZONE_U.x - mission.STOP_BEFORE + 4.0) - mission.train_start_u() * 0.0 - 0.0
	mission.train.s = (mission.ZONE_U.x - mission.STOP_BEFORE + 4.0) - mission.train_start_u()
	await frames(20)
	look(mission.track_to_world(Vector2(-30, 11)) + Vector3(0, 2.6, 0), mission.track_to_world(Vector2(-14, 0)) + Vector3(0, 1.4, 0), 2.0)
	await shot(out_dir, "m08_4_le_train_bloque")
	look(mission.track_to_world(Vector2(-2, 9)) + Vector3(0, 2.2, 0), mission.track_to_world(Vector2(-6, 0)) + Vector3(0, 0.7, 0), 1.8)
	await shot(out_dir, "m08_5_les_oies_sur_la_voie")
	print("[m08-captures] terminé")
	quit()
