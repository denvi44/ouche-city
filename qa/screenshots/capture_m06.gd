extends SceneTree
## Captures de la mission 06 (agent 09) : façade du supermarché, vue de dessus des rayons avec la file derrière le joueur,
## la lecture d'une étiquette, Mme Hubert, la caisse, le bilan.
## Usage : godot --path game -s ../qa/screenshots/capture_m06.gd -- --out=DIR --mission=m06   (Vulkan conseillé)

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
	print("[m06-captures] ", name)


func look_l(from_l: Vector3, to_l: Vector2, to_y := 1.0) -> void:
	var f: Vector3 = mission.to_world(Vector2(from_l.x, from_l.z))
	var t: Vector3 = mission.to_world(to_l)
	cam.look_at_from_position(Vector3(f.x, mission.origin.y + from_l.y, f.z), Vector3(t.x, mission.origin.y + to_y, t.z), Vector3.UP)


func place_l(n: Node3D, l: Vector2) -> void:
	var w: Vector3 = mission.to_world(l)
	n.global_position = Vector3(w.x, w.y + 0.5, w.z)
	if "velocity" in n:
		n.velocity = Vector3.ZERO


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[m06-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m06"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	mission = world.mission
	player = world.players_root.get_node("1")
	cam = Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	world.day_night.running = false
	world.day_night.hour = 8.0
	world.day_night.apply()
	mission.set_physics_process(false)
	# 1. La façade, vue de la route : enseigne, auvent, portes ouvertes.
	look_l(Vector3(-6.0, 3.2, 26.0), Vector2(0, 9.0), 2.6)
	await shot(out_dir, "m06_1_la_facade")
	# 2. Vue de dessus : le joueur lit une étiquette, la file de clients pressés s'allonge derrière lui.
	var lait: Vector2 = mission.item_local("cidre")
	place_l(player, lait + Vector2(-1.0, 0))
	for k in 5:
		mission._spawn_customer()
	for i in mission.customers.size():
		var c: Dictionary = mission.customers[i]
		c.route = 0
		c.x = lait.x - 3.0 - float(i) * 1.4
		c.z = -3.0
		c.vx = 0.0
		c.vz = 0.0
		c.imp = 0.25 + 0.15 * float(i)
	mission.reading = {"peer": 1, "item": "cidre", "t": 1.6}
	mission.items_got = ["baguette", "lait"]
	mission.incidents = 1
	mission.messages.append("Un client : « Dites donc, vous allez bouger ?! »")
	mission.clock_min = 497.0
	await frames(30)
	look_l(Vector3(-2.0, 11.0, -12.0), Vector2(-2.0, -3.0), 0.0)
	await shot(out_dir, "m06_2_la_file_derriere")
	# 3. Au ras des rayons : la file vue de derrière.
	look_l(Vector3(lait.x + 4.0, 1.7, -3.0), Vector2(lait.x - 4.0, -3.0), 1.4)
	await shot(out_dir, "m06_3_au_ras_des_rayons")
	# 4. Mme Hubert et Ginette dans l'allée de la hanche.
	mission.reading = {}
	mission.chat_left = 6.0
	place_l(player, mission.CHAT_SPOT + Vector2(1.9, 0))
	await frames(20)
	look_l(Vector3(5.0, 2.2, 3.2), mission.CHAT_SPOT, 1.4)
	await shot(out_dir, "m06_4_mme_hubert")
	# 5. La caisse : on compte la monnaie, Josette sourit.
	mission.chat_left = 0.0
	mission.items_got = mission.ITEMS.duplicate()
	mission.step = "pay"
	mission.coins = 2
	mission.mini_t = 0.4
	place_l(player, mission.PAY_SPOT)
	await frames(20)
	look_l(Vector3(7.5, 2.4, 0.5), Vector2(8.5, 6.2), 1.2)
	await shot(out_dir, "m06_5_la_caisse")
	# 6. Bilan.
	mission.step = "done"
	mission.result = "win"
	mission.medal = "silver"
	mission.blocked_total = 74.0
	mission.politeness = 3
	mission.clock_min = 538.0
	look_l(Vector3(0.0, 2.4, 14.5), Vector2(0, 8.0), 1.6)
	await shot(out_dir, "m06_6_bilan")
	print("[m06-captures] terminé")
	quit(0)
