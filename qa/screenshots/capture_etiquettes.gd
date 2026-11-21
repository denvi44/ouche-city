extends SceneTree
## Captures des noms flottants vus de haut : avec l'anti-superposition (LabelDeclutter) puis sans.
## Usage : godot --path game -s ../qa/screenshots/capture_etiquettes.gd -- --out=DIR [--mission=m02]   (Vulkan requis)
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/etiquettes"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	root.get_node("Settings").cinematics = false
	root.get_node("Net").mission_id = str(args.get("mission", "m02"))
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	var cam := Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	world.day_night.running = false
	world.day_night.hour = 14.0
	for c in world.players_root.get_children():
		c.set_physics_process(false)
		c.global_position = Vector3(0, -300, 0)
	var spawn: Vector3 = world.spawn_point
	cam.global_position = spawn + Vector3(0, 120, 160)
	cam.look_at(spawn + Vector3(0, 0, -40), Vector3.UP)
	var ld = world.get_children().filter(func(n): return n is LabelDeclutter)
	await frames(30)
	root.get_texture().get_image().save_png(out_dir.path_join("avec.png"))
	for n in ld:
		n.set_process(false)
	for l in get_nodes_in_group("etiquettes"):
		l.visible = true
	await frames(5)
	root.get_texture().get_image().save_png(out_dir.path_join("sans.png"))
	print("[capture] %d étiquettes" % get_nodes_in_group("etiquettes").size())
	quit(0)
