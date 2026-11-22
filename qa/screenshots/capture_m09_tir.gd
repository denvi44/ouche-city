extends SceneTree
## Cinématique du tir (mission 9) : plans 2, 3 et 4 avec la fumée, tels que le joueur les voit (ancres vivantes « bretons »).
## Usage : xvfb-run -a godot --rendering-driver vulkan --path game -s ../qa/screenshots/capture_m09_tir.gd -- --out=DIR [--t=110]
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", "/tmp/m9tir")
	var fire_t := float(args.get("t", "110"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1600, 900)
	DisplayServer.window_set_size(root.size)
	root.get_node("Settings").cinematics = false
	root.get_node("Net").mission_id = "m09"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(90)
	var m = world.mission
	for c in world.players_root.get_children():
		if c.peer_id < 0:
			c.global_position = Vector3(0, -300, 0)
			c.set_physics_process(false)
	var player = world.players_root.get_node("1")
	player.global_position = m.zones.catapult + Vector3(0, 5, 0)
	m.elapsed = fire_t
	m.time_left = 240.0 - fire_t
	m.loaded = 10
	m._fire()
	m.launch_t = 4.4                       # l'impact vient d'avoir lieu : la fumée naît
	await frames(10)
	var d := CinematicPlayer.load_def("m09_launch")
	var poi: Dictionary = CityBuilder.read_json("res://assets/city/poi.json")
	var anchors := CinematicPlayer.anchors_from_pois(poi.pois, world.builder.height_at)
	await create_timer(7.0).timeout        # la fumée s'installe pendant que le tir se déroule
	var plan := [[1, 5.2, 0.5], [2, 8.0, 0.25], [2, 9.6, 0.75], [3, 12.5, 0.5]]
	for q in plan:
		m.launch_t = q[1]
		var p := CinematicPlayer.new()
		world.add_child(p)
		p.live_anchors = Callable(m, "cinematic_anchors")
		p.start(d, anchors)
		paused = false
		p._shot = int(q[0]) - 1
		p._next_shot()
		p._t = 2.0
		p._shot_t = float(d.shots[int(q[0])].dur) * float(q[2])
		p._apply(float(q[2]))
		await frames(4)
		p._shot_t = float(d.shots[int(q[0])].dur) * float(q[2])
		root.get_texture().get_image().save_png(out_dir.path_join("plan%d_%d.png" % [int(q[0]) + 1, int(q[1] * 10)]))
		p.queue_free()
		await frames(2)
	quit(0)
