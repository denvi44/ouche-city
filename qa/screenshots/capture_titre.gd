extends SceneTree
## Captures de l'écran titre : un cadre par plan de drone (avancement 45 %), avec la carte Material par-dessus.
## Usage : godot --path game -s ../qa/screenshots/capture_titre.gd -- --out=DIR [--only=2]   (Vulkan requis : xvfb + lavapipe en CI)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/titre"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	var menu = load("res://scenes/main.tscn").instantiate()
	root.add_child(menu)
	await frames(30)
	var bd = menu._backdrop
	if bd == null:
		printerr("ÉCHEC : pas de fond drone (rendu headless ?)")
		quit(1)
		return
	await frames(60)
	var n: int = bd.shots.size()
	var ids: Array = [int(args.only)] if args.has("only") else range(n)
	for i in ids:
		bd._index = i
		bd._t = float(bd.shots[i].duree) * 0.45
		await frames(8)
		var img := root.get_texture().get_image()
		var path := out_dir.path_join("titre_%02d.png" % i)
		img.save_png(path)
		print("[capture] %s : %s" % [path, bd.caption()])
	quit(0)
