extends SceneTree
## Captures de la mission 07 (agent 09) : le stand de jus de pomme, la rue (HUD pression), Mme Hubert, les toilettes publiques, la porte fermée, le bilan.
## Usage : godot --path game -s ../qa/screenshots/capture_m07.gd -- --out=DIR --mission=m07   (Vulkan conseillé)

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var mission
var cam: Camera3D
var player


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(out_dir: String, name: String) -> void:
	await frames(6)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[m07-captures] ", name)


func look(from: Vector3, to: Vector3, above := 1.7) -> void:
	var gy: float = world.builder.height_at(from.x, from.z) + above
	from.y = maxf(from.y, gy)
	cam.look_at_from_position(from, to, Vector3.UP)


func front(zone: String) -> Vector3:
	var f: float = mission.facings[zone]
	return Vector3(sin(f), 0, cos(f))


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): push_error("[m07-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m07"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	mission = world.mission
	player = world.players_root.get_node("1")
	cam = Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	world.day_night.running = false
	world.day_night.hour = 16.0
	world.day_night.apply()
	mission.set_physics_process(false)
	mission._spasm_t = 9999.0
	for c in world.players_root.get_children():
		if c.peer_id < 0:
			c.set_physics_process(false)
			c.global_position = Vector3(0, -200, 0)
	var dlg: DialoguePlayer = world.get_node("Dialogues")
	dlg.skip()
	var st: Vector3 = mission.zones.stand
	var fr := front("stand")
	var right := Vector3(fr.z, 0, -fr.x)
	# 1. Le stand : pressoir, gobelets, cruche, Tonton Gégé.
	player.global_position = st + fr * 5.0 + Vector3(0, 0.6, 0)
	mission.victims[1].p = 0.3
	await frames(30)
	look(st + fr * 7.5 + right * 3.0, st + Vector3(0, 1.4, 0))
	await shot(out_dir, "m07_1_le_stand")
	# 2. La rue : la pression monte, on serre (HUD), crampe en onomatopée.
	var r1: Vector3 = mission.route_point(0.12)
	var r2: Vector3 = mission.route_point(0.22)
	player.global_position = r1 + Vector3(0, 0.6, 0)
	mission.victims[1].p = 0.58
	mission.victims[1].cl = true
	mission.victims[1].st = 0.55
	mission.time_left = 112.0
	await frames(30)
	var dirn := (r2 - r1).normalized()
	look(r1 - dirn * 6.0, r1 + dirn * 3.0 + Vector3(0, 1.4, 0), 3.0)
	world.get_node("Onomatopees").spawn("GRRRBLOUP !", r1 + Vector3(0, 2.6, 0), "bad")
	Engine.time_scale = 0.1
	await shot(out_dir, "m07_2_la_pression")
	Engine.time_scale = 1.0
	# 3. Mme Hubert et la causette.
	var hb: Vector3 = mission.spot("hubert")
	player.global_position = hb + Vector3(0, 0.6, 0)
	mission.victims[1].fz = "chat"
	mission.victims[1].p = 0.66
	mission._chat_left = 5.0
	await frames(30)
	look(hb + front("stand") * 6.0 + Vector3(2, 0, 2), hb + Vector3(0, 1.4, 0), 2.4)
	await shot(out_dir, "m07_3_mme_hubert")
	mission.victims[1].fz = ""
	# 4. Les toilettes publiques et leur file.
	var wc: Vector3 = mission.zones.wc
	var wf := front("wc")
	player.global_position = mission.spot("wc") + Vector3(0, 0.6, 0)
	await frames(20)
	look(wc + wf * 8.0 + Vector3(wf.z, 0, -wf.x) * 3.0, wc + Vector3(0, 1.4, 0), 2.2)
	await shot(out_dir, "m07_4_toilettes_publiques")
	# 5. La porte fermée à clé, le pot de fleurs.
	var dr: Vector3 = mission.zones.door
	var df := front("door")
	player.global_position = mission._front_point("door", 1.0) + Vector3(0, 0.6, 0)
	mission.victims[1].p = 0.83
	mission.victims[1].fz = "search"
	mission.victims[1].ft = 3.0
	await frames(20)
	look(dr + df * 6.0 + Vector3(df.z, 0, -df.x) * 2.5, dr + Vector3(0, 1.3, 0), 2.2)
	await shot(out_dir, "m07_5_la_porte")
	# 6. Bilan.
	mission.victims[1].fz = ""
	mission.step = "done"
	mission.result = "home"
	mission.medal = "silver"
	mission.best_pressure = 0.83
	mission.spasms = 6
	look(dr + df * 7.0, dr + Vector3(0, 1.5, 0), 2.4)
	await shot(out_dir, "m07_6_bilan")
	print("[m07-captures] terminé")
	quit(0)
