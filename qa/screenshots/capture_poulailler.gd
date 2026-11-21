extends SceneTree
## Capture du poulailler de Mémère Ginette (mission 01), de face et de trois quarts.
## Usage : godot --path game -s ../qa/screenshots/capture_poulailler.gd -- --out=DIR   (Vulkan conseillé)

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(300.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/poulailler"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	var poi := {}
	for p in world.builder.read_json("res://assets/city/poi.json").pois:
		if p.id == "poulailler_ginette":
			poi = p
	var x := float(poi.position[0])
	var z := float(poi.position[1])
	var f := float(poi.facing)
	var fwd := Vector3(sin(f), 0, cos(f))
	var right := Vector3(fwd.z, 0, -fwd.x)
	var gy: float = world.builder.height_at(x, z)
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.make_current()
	world.day_night.running = false
	world.day_night.hour = 15.0
	world.day_night.apply()
	for c in world.players_root.get_children():
		if c.peer_id < 0:
			c.set_physics_process(false)
			c.global_position = Vector3(0, -200, 0)
		else:
			c.global_position = Vector3(x, gy + 0.3, z) + fwd * 3.0 + right * 0.0
	var local := Basis(Vector3.UP, f)
	var coop := Vector3(x, gy, z) + local * Vector3(2.8, 1.0, 2.2)
	var target := coop
	for spec in [["poulailler_1_face", local * Vector3(3.2, 2.4, 5.6), 0.0], ["poulailler_2_trois_quarts", local * Vector3(-0.8, 2.2, 4.6), 0.0]]:
		cam.look_at_from_position(Vector3(x, gy, z) + spec[1], target, Vector3.UP)
		await frames(8)
		root.get_texture().get_image().save_png(out_dir.path_join(spec[0] + ".png"))
		print("[poulailler] ", spec[0])
	quit()
