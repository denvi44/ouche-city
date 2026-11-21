extends SceneTree
## Galerie des personnages détaillés (agent 09) : les quatre compagnons, deux joueurs, le gendarme et le fermier, en ligne ;
## puis gros plans de visages.
## Usage : godot --path game -s ../qa/screenshots/capture_galerie_personnages.gd -- --out=DIR   (Vulkan conseillé)

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(out_dir: String, name: String) -> void:
	await frames(6)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[galerie] ", name)


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): push_error("[galerie] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/personnages"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	world.day_night.hour = 15.0
	world.day_night.apply()
	for c in world.players_root.get_children():
		c.visible = false
	var P = load("res://scripts/player/player.gd")
	var CM = load("res://scripts/player/character_model.gd")
	var base: Vector3 = world.spawn_point + Vector3(0, 0, 0)
	var gallery := Node3D.new()
	world.add_child(gallery)
	var models := []
	for id in [-1, -2, -3, -4]:
		var o: Dictionary = P.OUTFITS[id]
		models.append(CM.make(o.shirt, o.trousers, o.hat, o.get("style", {})))
	models.append(CM.make(Color(0.85, 0.45, 0.25), Color(0.2, 0.22, 0.3), Color(0.15, 0.17, 0.25), P.default_style(3)))
	models.append(CM.make(Color(0.3, 0.55, 0.45), Color(0.2, 0.22, 0.3), Color(0.15, 0.17, 0.25), P.default_style(6)))
	models.append(CM.make(Color(0.3, 0.38, 0.55), Color(0.2, 0.24, 0.38), Color(0.2, 0.26, 0.45), {"headgear": "kepi", "hair": Color(0.2, 0.15, 0.1), "moustache": Color(0.22, 0.16, 0.1), "belt": Color(0.95, 0.95, 0.95), "scarf": Color(0.9, 0.9, 0.92), "shoes": Color(0.08, 0.08, 0.1)}))
	models.append(CM.make(Color(0.3, 0.4, 0.62), Color(0.35, 0.3, 0.24), Color(0.4, 0.3, 0.2), {"headgear": "straw", "hair": Color(0.6, 0.6, 0.58), "beard": Color(0.7, 0.7, 0.68), "vest": Color(0.45, 0.35, 0.22)}))
	var gy: float = world.builder.height_at(base.x, base.z)
	var parts := 0
	for i in models.size():
		var m: Node3D = models[i]
		m.position = Vector3(base.x + (i - 3.5) * 1.35, gy, base.z)
		m.pose_override = {"speed": 0.0}
		m.rotation.y = 0.0
		gallery.add_child(m)
		parts += m.detail_parts
	print("[galerie] parties de détail : ", parts)
	cam = Camera3D.new()
	cam.fov = 40.0
	world.add_child(cam)
	cam.make_current()
	await frames(20)
	cam.look_at_from_position(Vector3(base.x, gy + 1.5, base.z - 10.0), Vector3(base.x, gy + 0.95, base.z), Vector3.UP)
	await shot(out_dir, "perso_1_galerie")
	# Gros plans : Gégé et Ginette, puis Kévin et le gendarme.
	for pair in [[0, 1, "perso_2_gege_ginette"], [3, 6, "perso_3_kevin_gendarme"]]:
		var a: Node3D = models[pair[0]]
		var b: Node3D = models[pair[1]]
		var mid: Vector3 = (a.position + b.position) * 0.5 + Vector3(0, 1.45, 0)
		cam.fov = 26.0
		cam.look_at_from_position(mid + Vector3(0.0, 0.0, -2.2 - abs(a.position.x - b.position.x) * 0.4), mid, Vector3.UP)
		await shot(out_dir, pair[2])
	print("[galerie] terminé")
	quit(0)
