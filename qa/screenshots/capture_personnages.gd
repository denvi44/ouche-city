extends SceneTree
## Captures des personnages articulés (agent 09) : poses de repos, marche, course, saut, portage.
## Usage : godot --path game -s ../qa/screenshots/capture_personnages.gd -- --out=DIR

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
const POSES := [
	{"nom": "Repos", "speed": 0.0, "carrying": false, "airborne": false},
	{"nom": "Marche", "speed": 3.2, "carrying": false, "airborne": false},
	{"nom": "Course", "speed": 7.5, "carrying": false, "airborne": false},
	{"nom": "Saut", "speed": 4.0, "carrying": false, "airborne": true},
	{"nom": "Portage", "speed": 2.8, "carrying": true, "airborne": false},
]
var world


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/personnages"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(25)
	world.day_night.running = false
	world.day_night.hour = 11.0
	var base: Vector3 = world.spawn_point + Vector3(0, 0, 0)
	for c in world.get_children():
		if c is CanvasLayer:
			c.visible = false          # pas de HUD sur les portraits
	var cam := Camera3D.new()
	cam.fov = 55.0
	world.add_child(cam)
	cam.make_current()
	# Rangée le long de la rue (axe Z) : tous marchent vers -Z, la caméra les voit de profil depuis +X.
	for i in POSES.size():
		var pos: Vector3 = base + Vector3(0, 0.05, (i - 2) * 1.35)
		var fig = world._spawn(200 + i, POSES[i].nom, pos)
		fig.model.pose_override = {"speed": POSES[i].speed, "carrying": POSES[i].carrying, "airborne": POSES[i].airborne}
	for p in world.players_root.get_children():
		if p.name == "1":
			p.queue_free()
	await frames(40)
	cam.look_at_from_position(base + Vector3(3.6, 1.15, 0), base + Vector3(0, 0.95, 0), Vector3.UP)
	await frames(20)
	root.get_texture().get_image().save_png(out_dir.path_join("personnages_profil.png"))
	# De face : on supprime la rangée et on aligne les figurants côte à côte, la caméra devant eux.
	for i in POSES.size():
		var fig = world.players_root.get_node(str(200 + i))
		fig.global_position = base + Vector3((i - 2) * 1.3, 0.05, 0)
	await frames(20)
	cam.fov = 40.0
	cam.look_at_from_position(base + Vector3(0, 1.3, -6.5), base + Vector3(0, 0.95, 0), Vector3.UP)
	await frames(20)
	root.get_texture().get_image().save_png(out_dir.path_join("personnages_face.png"))
	print("[personnages] terminé")
	quit(0)
