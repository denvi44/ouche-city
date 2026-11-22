extends SceneTree
## Captures : piste de rythme (mission 3) et grande carte (touche M).
## Usage : xvfb-run -a godot --rendering-driver vulkan --path game -s ../qa/screenshots/capture_rythme.gd -- --out=DIR
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/rythme"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	root.get_node("Settings").cinematics = false
	root.get_node("Net").mission_id = "m03"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(90)
	var m = world.mission
	var player = world.players_root.get_node("1")
	player.global_position = m.zones.camp + Vector3(0, 0.8, 3.0)
	m.step = "round"
	m.round_idx = 2
	m.round_state = "play"
	m.playlist = "techno_foraine"
	m.play_t = 6.2
	m.last_hit = {"q": "perfect", "k": 12}
	m.set_physics_process(false)
	await frames(20)
	root.get_texture().get_image().save_png(out_dir.path_join("rythme.png"))
	var hud = world.find_child("Hud", true, false)
	if hud == null:
		for c in world.get_children():
			if c.get_script() and "_bigmap" in c:
				hud = c
	if hud:
		hud._bigmap.visible = true
		await frames(10)
		root.get_texture().get_image().save_png(out_dir.path_join("grande_carte.png"))
		hud._bigmap.zoom_by(4.0)
		await frames(10)
		root.get_texture().get_image().save_png(out_dir.path_join("grande_carte_zoom.png"))
	quit(0)
