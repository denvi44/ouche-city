extends SceneTree
## Captures du compagnon IA (agent 09) : Tonton Gégé joue seul, la caméra le suit.
## Usage : godot --path game -s ../qa/screenshots/capture_companion.gd -- --out=DIR   (Vulkan conseillé)
## Le script accélère la simulation en sautant des images de rendu : on laisse tourner la
## physique, puis on photographie à des instants clés (en route, caisse portée, chargement).

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var gege
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func follow() -> void:
	var p: Vector3 = gege.global_position
	var f: float = gege.facing
	var behind := Vector3(sin(f), 0, cos(f))
	cam.look_at_from_position(p + behind * 4.8 + Vector3(0, 2.2, 0) + Vector3(cos(f), 0, -sin(f)) * 1.6, p + Vector3(0, 1.2, 0), Vector3.UP)


func shot(out_dir: String, name: String) -> void:
	follow()
	await frames(3)
	follow()
	await frames(2)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[companion-captures] ", name, "  ", gege.brain.status)


func wait_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		await process_frame
		follow()
		if cond.call():
			return true
	return false


func _run() -> void:
	create_timer(800.0).timeout.connect(func(): push_error("[companion-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/companion"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(30)
	world.day_night.running = false
	world.day_night.hour = 11.0
	gege = world.players_root.get_node("-1")
	cam = Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	for c in world.get_children():
		if c is CanvasLayer:
			c.layer = 10
	# 1. En route vers la caisse de la cave.
	await wait_until(func(): return gege.brain.status.begins_with("va chercher") and Vector2(gege.global_position.x - world.mission.crates["cave_gege"].pos.x, gege.global_position.z - world.mission.crates["cave_gege"].pos.z).length() < 16.0, 600)
	await shot(out_dir, "gege_1_en_route")
	# 2. Caisse sur les bras.
	await wait_until(func(): return gege.carrying, 900)
	await frames(25)
	await shot(out_dir, "gege_2_porte_la_caisse")
	# 3. Retour à la camionnette puis chargement.
	await wait_until(func(): return gege.carrying and Vector2(gege.global_position.x - world.van.global_position.x, gege.global_position.z - world.van.global_position.z).length() < 9.0, 1800)
	await shot(out_dir, "gege_3_arrive_a_la_camionnette")
	await wait_until(func(): return not gege.carrying, 300)
	await frames(10)
	await shot(out_dir, "gege_4_caisse_chargee")
	print("[companion-captures] terminé : bouteilles à bord ", world.mission.cargo)
	quit(0)
