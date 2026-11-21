extends SceneTree
## Captures du barrage et des compagnons (agent 09) : choix d'équipe, barrière relevée, radio.
## Usage : godot --path game -s ../qa/screenshots/capture_barrage.gd -- --out=DIR   (Vulkan conseillé)
## Les compagnons sont posés d'office à leur poste (le trajet à pied est testé par qa/integration).

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


func place(node, pos: Vector3) -> void:
	node.global_position = pos
	node.velocity = Vector3.ZERO


func shot(out_dir: String, name: String) -> void:
	await frames(6)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[barrage-captures] ", name)


func _run() -> void:
	create_timer(800.0).timeout.connect(func(): push_error("[barrage-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/barrage"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(30)
	world.day_night.running = false
	world.day_night.hour = 11.0
	mission = world.mission
	van = world.van
	cam = Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	# État : tout est chargé, route vers le barrage ; les compagnons sont à leur poste.
	for id in mission.crates.keys():
		mission.crates[id].state = "loaded"
	mission.cargo = 24
	mission.step = "road"
	mission._mark()
	var gin = world.players_root.get_node("-2")
	var kev = world.players_root.get_node("-4")
	var rad = world.players_root.get_node("-3")
	var g = mission.spot("ginette")
	var k = mission.spot("kevin")
	var r = mission.spot("radio")
	place(gin, g + Vector3(0, 0.3, 0))
	place(kev, k + Vector3(0, 0.3, 0))
	place(rad, r + Vector3(0, 0.3, 0))
	var player = world.players_root.get_node("1")
	place(player, mission.zones.barrage + Vector3(0, 0.5, 40.0))
	for c in world.players_root.get_children():
		if c.peer_id == -1:
			place(c, mission.zones.barrage + Vector3(8, 0.5, 40.0))     # Gégé n'est pas dans le cadre
	await frames(30)
	var b: Vector3 = mission.zones.barrage
	var d: Vector2 = mission.zone_dirs.barrage
	# La camionnette arrive à 7 m du barrage : le choix s'ouvre.
	van.rotation.y = atan2(-d.x, -d.y)
	place(van, b - Vector3(d.x, 0, d.y) * 7.0 + Vector3(0, 0.6, 0))
	van.speed = 0.0
	await frames(25)
	# Plan 1 : derrière la camionnette, barrière, Ginette sur le trottoir, Kévin en retrait.
	var behind: Vector3 = b - Vector3(d.x, 0, d.y) * 17.0 + Vector3(0, 3.4, 0)
	cam.look_at_from_position(behind, b + Vector3(0, 1.2, 0), Vector3.UP)
	await shot(out_dir, "barrage_1_choix_d_equipe")
	# Plan 2 : Ginette bluffe (tirage chanceux), la barre se relève.
	mission.test_roll = 0.1
	mission.choose("bluff")
	await frames(10)
	var side: Vector3 = b + Vector3(-d.y, 0, d.x) * 9.0 + Vector3(0, 2.0, 0)
	cam.look_at_from_position(side - Vector3(d.x, 0, d.y) * 3.0, b + Vector3(0, 1.4, 0), Vector3.UP)
	await shot(out_dir, "barrage_2_bluff_reussi")
	# Plan 3 : Kévin Radio à son poste, près du stand.
	var rp: Vector3 = rad.global_position
	cam.look_at_from_position(rp + Vector3(3.0, 1.8, 5.0), rp + Vector3(0, 1.1, 0), Vector3.UP)
	await shot(out_dir, "barrage_3_kevin_radio")
	# Plan 4 : les quatre compagnons côte à côte (portrait de groupe).
	var row: Vector3 = b + Vector3(-d.y, 0, d.x) * 12.0
	var ids := [-1, -2, -3, -4]
	for i in 4:
		var c = world.players_root.get_node(str(ids[i]))
		place(c, row + Vector3(d.x, 0, d.y) * (i - 1.5) * 1.5 + Vector3(0, 0.5, 0))
		c.brain = null
	await frames(20)
	cam.look_at_from_position(row + Vector3(-d.y, 0, d.x) * 6.0 + Vector3(0, 1.5, 0), row + Vector3(0, 1.1, 0), Vector3.UP)
	await shot(out_dir, "barrage_4_les_compagnons")
	print("[barrage-captures] terminé : ", mission.step)
	quit(0)
