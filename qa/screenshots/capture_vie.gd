extends SceneTree
## Captures de la vie ambiante : rue Sainte-Foy avec passants et voitures, et un gros plan sur l'échappement de la camionnette.
## Usage : godot --path game -s ../qa/screenshots/capture_vie.gd -- --out=DIR   (Vulkan requis)
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/vie"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	root.get_node("Settings").cinematics = false
	root.get_node("Net").mission_id = "m01"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	world.day_night.running = false
	world.day_night.hour = 15.0
	for c in world.players_root.get_children():
		if c.peer_id < 0:
			c.global_position = Vector3(0, -300, 0)
			c.set_physics_process(false)
	var player = world.players_root.get_node("1")
	var cam := Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	await frames(60 * 20)                       # le temps que passants et voitures arrivent
	var sp: Vector3 = player.global_position
	cam.global_position = sp + Vector3(0, 14, 26)
	cam.look_at(sp + Vector3(0, 1, -20), Vector3.UP)
	await frames(10)
	root.get_texture().get_image().save_png(out_dir.path_join("rue.png"))
	# Échappement de la camionnette : moteur allumé, en roulant.
	var van = world.van
	van.engine_on = true
	van.speed = 8.0
	var f: Vector3 = van.global_transform.basis.z
	cam.global_position = van.global_position + f * 7.0 + Vector3(3.5, 2.0, 0)
	cam.look_at(van.global_position + f * 2.0 + Vector3(0, 0.6, 0), Vector3.UP)
	await frames(60)
	root.get_texture().get_image().save_png(out_dir.path_join("echappement.png"))
	print("[capture] passants %d, voitures %d" % [world.get_node("VieAmbiante").peds.size(), world.get_node("VieAmbiante").cars.size()])
	quit(0)
