extends SceneTree
## Captures de gameplay de la mission 01 (agent 09), avec le vrai joueur, la vraie caméra et le HUD.
## Usage : godot --path game -s ../qa/screenshots/capture_m01.gd -- --out=DIR   (Vulkan conseillé)
## Le script joue la mission par ses propres fonctions serveur (comme qa/integration/m01_flow.gd)
## et photographie chaque moment clé.

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var mission
var van
var player
var out_dir := ""


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await frames(4)
	var path := out_dir.path_join("%s_%s.png" % [name, OS.get_name().to_lower()])
	root.get_texture().get_image().save_png(path)
	print("[m01-captures] ", path)


func look_at_point(p: Vector3) -> void:
	var d: Vector3 = p - player.global_position
	player.camera_rig.yaw = atan2(-d.x, -d.z)
	player.camera_rig.pitch = -0.22


func place(node, pos: Vector3) -> void:
	node.global_position = pos
	node.velocity = Vector3.ZERO


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[m01-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	out_dir = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m01"))
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
	player = world.players_root.get_node("1")
	await frames(20)

	# 1. À la cave : la caisse est prête.
	var crate: Dictionary = mission.crates["cave_gege"]
	var f: Vector3 = (crate.pos as Vector3)
	var from: Vector3 = f + Vector3(0, 0, 3.2)
	place(player, from)
	player.facing = PI
	await frames(10)
	look_at_point(f)
	await shot("m01_1_caisse_cave")

	# 2. Prise et portage.
	mission.interact(1)
	await frames(6)
	player.camera_rig.yaw += 0.6
	await shot("m01_2_portage")

	# 3. Chargement dans la camionnette.
	place(player, van.global_position + van.global_transform.basis.x * 3.0)
	await frames(8)
	look_at_point(van.global_position)
	await shot("m01_3_chargement")
	mission.interact(1)
	for id in mission.crates.keys():
		if mission.crates[id].state == "ground":
			mission.crates[id].state = "loaded"
			mission.cargo += mission.crates[id].bottles
	mission._mark()
	mission.step = "road"

	# 4. Au volant.
	place(player, van.global_position + van.global_transform.basis.x * 2.8)
	await frames(6)
	mission.interact(1)
	await frames(30)
	van.forced_input = {"move": Vector2(0, -1), "jump": false}
	await frames(110)
	await shot("m01_4_conduite")

	# 5. Un virage serré, puis le choc.
	van.forced_input = {"move": Vector2(0.7, -1), "jump": false}
	await frames(40)
	await shot("m01_5_virage")
	var space = van.get_world_3d().direct_space_state
	var base: Vector3 = van.global_position
	for k in 72:
		var yaw := TAU * k / 72.0
		var dir := Vector3(-sin(yaw), 0, -cos(yaw))
		var q = PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.2, 0), base + Vector3(0, 1.2, 0) + dir * 400.0)
		q.exclude = [van.get_rid(), player.get_rid()]
		var hit = space.intersect_ray(q)
		if hit and hit.normal.y < 0.3 and hit.normal.dot(-dir) > 0.93 and base.distance_to(hit.position) > 32.0:
			van.rotation.y = yaw
			place(van, hit.position - dir * 22.0 + Vector3(0, 0.6, 0))
			van.speed = 0.0
			break
	van.forced_input = {"move": Vector2(0, -1), "jump": false}
	await frames(60)
	await shot("m01_6_avant_choc")
	await frames(120)
	await shot("m01_7_apres_choc")

	# 6. Barrage, puis stand : médaille (cargaison remise à 21 pour une médaille d'argent).
	van.forced_input = {"move": Vector2.ZERO, "jump": true}
	await frames(30)
	place(van, mission.zones.barrage + van.global_transform.basis.z * 14.0 + Vector3(0, 0.6, 0))
	van.rotation.y = 0.0
	await frames(30)
	await shot("m01_8_barrage")
	mission.cargo = 21
	place(van, mission.zones.stand + Vector3(0, 0.6, 6.0))
	van.speed = 0.0
	await frames(40)
	await shot("m01_9_livraison_medaille")
	print("[m01-captures] terminé, étape finale : ", mission.step, " médaille : ", mission.medal)
	quit(0)
