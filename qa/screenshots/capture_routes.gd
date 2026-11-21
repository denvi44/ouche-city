extends SceneTree
## Vues de dessus des routes (herbe qui coupe la chaussée ?) : quatre points du village, caméra à 70 m de haut.
## Usage : godot --path game -s ../qa/screenshots/capture_routes.gd -- --out=DIR   (Vulkan requis)
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
const POINTS := [Vector2(1296, 1358), Vector2(1210, 1856), Vector2(1190, 1460), Vector2(1034, 1212)]


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/routes"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	root.get_node("Settings").cinematics = false
	root.get_node("Settings").ambient_life = false
	root.get_node("Net").mission_id = "m01"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	world.day_night.running = false
	world.day_night.hour = 13.0
	world.day_night.apply()
	for c in world.players_root.get_children():
		c.set_physics_process(false)
		c.global_position = Vector3(0, -300, 0)
	var hud = world.get_children().filter(func(n): return n is CanvasLayer)
	for h in hud:
		h.visible = false
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.make_current()
	var i := 0
	for p in POINTS:
		var y: float = world.builder.height_at(p.x, p.y)
		cam.global_position = Vector3(p.x, y + 70.0, p.y + 30.0)
		cam.look_at(Vector3(p.x, y, p.y), Vector3.UP)
		await frames(6)
		root.get_texture().get_image().save_png(out_dir.path_join("routes_%d.png" % i))
		i += 1
	# Vues à hauteur d'homme le long de routes tirées au hasard (déterministe).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lines: Array = world.builder.road_lines.filter(func(r): return float(r.len) > 80.0 and str(r.kind) in ["residential", "secondary", "tertiary", "unclassified"])
	for k in 0:
		var r: Dictionary = lines[rng.randi() % lines.size()]
		var s := rng.randf_range(10.0, float(r.len) - 40.0)
		var sm: Array = AmbientLife.sample(r.pts, s)
		var q: Vector2 = sm[0]
		var d: Vector2 = sm[1]
		var yy: float = world.builder.height_at(q.x, q.y)
		cam.global_position = Vector3(q.x, yy + 2.2, q.y)
		cam.look_at(Vector3(q.x + d.x * 20.0, yy + 1.0, q.y + d.y * 20.0), Vector3.UP)
		await frames(6)
		root.get_texture().get_image().save_png(out_dir.path_join("sol_%d.png" % k))
		print("[capture] sol_%d : route %s à %s" % [k, r.kind, q])
	quit(0)
