extends SceneTree
## Captures de la mission 03 (agent 09) : la sono des Pommiers, le camp du Clos Fleuri, la manche, le sabotage, les gendarmes, le bilan.
## Usage : godot --path game -s ../qa/screenshots/capture_m03.gd -- --out=DIR --mission=m03   (Vulkan conseillé)

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
	print("[m03-captures] ", name)


func look(from: Vector3, to: Vector3) -> void:
	cam.look_at_from_position(from, to, Vector3.UP)


func front(zone: String) -> Vector3:
	var f: float = mission.facings[zone]
	return Vector3(sin(f), 0, cos(f))


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[m03-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m03"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	mission = world.mission
	player = world.players_root.get_node("1")
	cam = Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	var camp: Vector3 = mission.zones.camp
	var fc := front("camp")
	var right := Vector3(fc.z, 0, -fc.x)
	# 1. La sono des Pommiers, à la tombée du jour, avant la manche : les compagnons à leur poste.
	world.day_night.hour = 19.5
	world.day_night.apply()
	for pair in [["-1", "groupe"], ["-2", "videur"]]:
		var c = world.players_root.get_node_or_null(pair[0])
		if c:
			c.global_position = mission.spot(pair[1]) + Vector3(0, 0.6, 0)
	player.global_position = camp + fc * 6.0 + Vector3(0, 0.8, 0)
	await frames(30)
	look(camp + fc * 12.0 + right * 6.0 + Vector3(0, 3.2, 0), camp + Vector3(0, 1.6, 0))
	await shot(out_dir, "m03_1_la_sono_des_pommiers")
	# 2. Le camp rival.
	var rv: Vector3 = mission.zones.rival
	var fr := front("rival")
	look(rv + fr * 13.0 + Vector3(fr.z, 0, -fr.x) * 5.0 + Vector3(0, 3.4, 0), rv + Vector3(0, 1.6, 0))
	await shot(out_dir, "m03_2_le_clos_fleuri")
	# 3. Matériel rassemblé, première manche en cours (HUD : rythme, nuisance, scores).
	for it in mission.ITEMS:
		mission.items_taken.append(it)
	mission._begin_round(0)
	mission._choose_playlist("musette_remix")
	mission.count_left = 0.0
	await frames(4)
	world.day_night.hour = 21.0
	world.day_night.apply()
	player.global_position = camp + fc * 5.0 + Vector3(0, 0.8, 0)
	mission.play_t = 8.0
	mission.score_p = 31.0
	mission.nuisance = 0.45
	mission.messages.append("Ginette tient les portes.")
	look(camp + fc * 10.0 + right * 7.0 + Vector3(0, 2.4, 0), camp + Vector3(0, 1.8, 0))
	mission.set_physics_process(false)
	await frames(2)
	await shot(out_dir, "m03_3_manche_en_cours")
	# 4. Sabotage : les poules sur la scène.
	mission.sab = {"kind": "poules", "left": 5.0}
	mission.messages.append("Le rival lâche des poules sur la scène !")
	var ps: Vector3 = mission.spot("sab_poules")
	player.global_position = ps + Vector3(0.5, 0.6, 0)
	look(camp + fc * 11.0 - right * 6.0 + Vector3(0, 2.6, 0), ps + Vector3(0, 1.0, 0))
	await shot(out_dir, "m03_4_sabotage")
	mission.sab = {"kind": "", "left": 0.0}
	# 5. Les gendarmes.
	mission.nuisance = 0.72
	mission.police_done = true
	mission.police_visit = true
	mission.round_state = "police"
	mission.police_left = 9.0
	mission._open_menu("police")
	look(camp + fc * 10.0 + right * 7.0 + Vector3(0, 2.4, 0), camp + Vector3(0, 1.8, 0))
	await shot(out_dir, "m03_5_les_gendarmes")
	# 6. Bilan : victoire, médaille d'argent.
	mission.menu = ""
	mission.menu_options = []
	mission.results = [{"won": true, "p": 111.6, "r": 52.8, "playlist": "musette_remix"}, {"won": true, "p": 139.2, "r": 74.4, "playlist": "musette_remix"}, {"won": true, "p": 170.4, "r": 97.9, "playlist": "techno_foraine"}]
	mission.result = "win"
	mission.medal = "silver"
	mission.step = "done"
	mission.round_state = "result"
	await shot(out_dir, "m03_6_bilan")
	print("[m03-captures] terminé")
	quit(0)
