extends SceneTree
## Capture de l'écran « Touches et souris » (écran titre), à l'état normal puis en attente d'une touche.
## Usage : godot --path game -s ../qa/screenshots/capture_touches.gd -- --out=DIR   (Vulkan conseillé)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/touches"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	var bg := ColorRect.new()
	bg.color = Color(0.62, 0.78, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var holder := Control.new()
	holder.theme = load("res://ui/theme_util.gd").make_theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var menu = load("res://ui/controls_menu.gd").new()
	holder.add_child(menu)
	await frames(10)
	root.get_texture().get_image().save_png(out_dir.path_join("touches_1_liste.png"))
	menu._start("jump", "key")
	await frames(4)
	root.get_texture().get_image().save_png(out_dir.path_join("touches_2_attente.png"))
	print("[touches] ok")
	quit()
