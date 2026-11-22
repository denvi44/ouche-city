extends SceneTree
## Captures de la mission 9 : l'étal, la catapulte, les Bretons et le beurre sous la pluie, le tir, la fumée verte.
## Usage : xvfb-run -a godot --rendering-driver vulkan --path game -s ../qa/screenshots/capture_m09.gd -- --out=DIR
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m09"))
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
	var cam := Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	var cat: Vector3 = m.zones.catapult
	var fwd: Vector3 = Basis(Vector3.UP, m.facing_catapult) * Vector3(0, 0, 1)
	var right: Vector3 = Basis(Vector3.UP, m.facing_catapult) * Vector3(1, 0, 0)
	# 1. Catapulte et joueur, beurre en l'air et sur les façades (t = 60 s).
	m.elapsed = 60.0
	m.time_left = 270.0
	m.loaded = 4
	player.global_position = cat - fwd * 6.0 + right * 3.0 + Vector3(0, 1, 0)
	await frames(30)
	cam.global_position = cat - fwd * 14.0 + right * 7.0 + Vector3(0, 5, 0)
	cam.look_at(cat + fwd * 8.0 + Vector3(0, 2, 0), Vector3.UP)
	await frames(10)
	root.get_texture().get_image().save_png(out_dir.path_join("01_catapulte.png"))
	# 2. Les Bretons au débarquement.
	var land: Vector3 = m.zones.landing
	cam.global_position = land - fwd * 40.0 + right * 10.0 + Vector3(0, 6, 0)
	cam.look_at(land + Vector3(0, 1.5, 0), Vector3.UP)
	await frames(10)
	root.get_texture().get_image().save_png(out_dir.path_join("02_bretons.png"))
	# 3. Un étal de camembert.
	var st: Vector3 = m.stocks[0]
	var tow: Vector3 = (cat - st).normalized()
	cam.global_position = st - tow * 6.0 + Vector3(0, 2.5, 0)
	cam.look_at(st + Vector3(0, 1, 0), Vector3.UP)
	await frames(10)
	root.get_texture().get_image().save_png(out_dir.path_join("03_etal.png"))
	# 4. Le tir : bras en l'air, camembert en vol.
	m.step = "launch"
	m.stop_t = m.elapsed
	m.launch_t = 1.6
	await frames(5)
	cam.global_position = cat - fwd * 12.0 + right * 6.0 + Vector3(0, 6, 0)
	cam.look_at(cat + fwd * 4.0 + Vector3(0, 6, 0), Vector3.UP)
	await frames(10)
	root.get_texture().get_image().save_png(out_dir.path_join("04_tir.png"))
	# 5. La fumée verte et jaunâtre, les Bretons qui fuient.
	m.launch_t = 9.0
	await frames(240)
	cam.global_position = land - fwd * 26.0 + right * 14.0 + Vector3(0, 9, 0)
	cam.look_at(land + Vector3(0, 4, 0), Vector3.UP)
	await frames(10)
	root.get_texture().get_image().save_png(out_dir.path_join("05_fumee.png"))
	quit(0)
