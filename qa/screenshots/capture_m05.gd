extends SceneTree
## Captures de la mission 05 (agent 09) : le pré à l'aube, une vache de près, le troupeau fuyant, l'enclos, la barrière fermée.
## Usage : godot --path game -s ../qa/screenshots/capture_m05.gd -- --out=DIR --mission=m05 --no-companions   (Vulkan conseillé)

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
	print("[m05-captures] ", name)


func look(from: Vector3, to: Vector3, min_above := 1.8) -> void:
	var gy: float = world.builder.height_at(from.x, from.z) + min_above
	from.y = maxf(from.y, gy)
	cam.look_at_from_position(from, to, Vector3.UP)


func g(p: Vector2, up := 0.0) -> Vector3:
	return Vector3(p.x, world.builder.height_at(p.x, p.y) + up, p.y)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[m05-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m05"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	world.day_night.hour = 6.2
	world.day_night.apply()
	mission = world.mission
	player = world.players_root.get_node("1")
	cam = Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	mission.set_physics_process(false)
	var pre := Vector2(mission.zones.pre.x, mission.zones.pre.z)
	var pen := Vector2(mission.zones.pen.x, mission.zones.pen.z)
	var to_pen := (pen - pre).normalized()
	var side := Vector2(-to_pen.y, to_pen.x)
	# 1. Le pré à l'aube : le troupeau broute.
	player.global_position = g(pre - to_pen * 28.0, 0.8)
	await frames(30)
	look(g(pre - to_pen * 30.0 + side * 8.0, 3.0), g(pre, 1.0))
	await shot(out_dir, "m05_1_le_pre")
	# 2. Une vache de près : Marguerite et ses voisines.
	var c0: Dictionary = mission.cows[0]
	var cp := Vector2(c0.x, c0.z)
	look(g(cp - to_pen * 5.5 + side * 3.0, 1.6), g(cp, 1.0), 1.4)
	await shot(out_dir, "m05_2_marguerite")
	# 3. Rabattage : le troupeau fuit vers l'enclos, le berger siffle derrière.
	for i in mission.cows.size():
		var c: Dictionary = mission.cows[i]
		var t := 0.25 + 0.5 * float(i) / 7.0
		var p := pre.lerp(pen, t) + side * (float(i % 3) - 1.0) * 4.0
		c.x = p.x
		c.z = p.y
		c.vx = to_pen.x * 4.0
		c.vz = to_pen.y * 4.0
		c.st = "flee"
	player.global_position = g(pre.lerp(pen, 0.08), 0.8)
	mission.whistle_left = 1.0
	mission.whistles += 1
	await frames(20)
	look(g(pre.lerp(pen, 0.05) + side * 14.0, 6.0), g(pre.lerp(pen, 0.5), 1.0), 3.0)
	await shot(out_dir, "m05_3_le_rabattage")
	# 4. L'enclos : six vaches dedans, la barrière ouverte.
	for i in 6:
		var c: Dictionary = mission.cows[i]
		var p := pen + Vector2(cos(float(i)), sin(float(i))) * 2.5
		c.x = p.x
		c.z = p.y
		c.vx = 0.0
		c.vz = 0.0
		c.st = "pen"
	await frames(10)
	look(g(pen + to_pen * 17.0 + side * 6.0, 4.5), g(pen, 1.0), 3.5)
	await shot(out_dir, "m05_4_l_enclos")
	# 5. Les huit sont rentrées : la barrière est fermée.
	for i in 8:
		var c: Dictionary = mission.cows[i]
		var p := pen + Vector2(cos(float(i) * 0.8), sin(float(i) * 0.8)) * 3.0
		c.x = p.x
		c.z = p.y
		c.vx = 0.0
		c.vz = 0.0
		c.st = "pen"
	mission.gate_closed = true
	mission.step = "done"
	mission.result = "win"
	mission.medal = "gold"
	await frames(10)
	look(g(pen + to_pen * 14.0 + side * 3.0, 3.0), g(pen + to_pen * 4.0, 1.2), 2.2)
	await shot(out_dir, "m05_5_barriere_fermee")
	print("[m05-captures] terminé")
	quit(0)
