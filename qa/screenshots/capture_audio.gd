extends SceneTree
## Capture de l'interface audio (agent 09) : sous-titres sonores et radio, camionnette au volant.
## Usage : godot --path game -s ../qa/screenshots/capture_audio.gd -- --out=DIR --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	create_timer(400.0).timeout.connect(func(): push_error("[audio-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/audio"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	world.day_night.hour = 11.0
	var mission = world.mission
	var van = world.van
	var player = world.players_root.get_node("1")
	var sfx = root.get_node("Sfx")
	print("[audio-captures] audio actif : ", sfx.enabled)
	# Au volant, radio allumée, un coup de klaxon, un nid-de-poule.
	player.global_position = van.global_position + van.global_transform.basis.x * 2.8
	await frames(6)
	mission.interact(1)
	await frames(30)
	sfx.set_radio(true)
	await frames(40)
	van.forced_input = {"move": Vector2(0, -1), "jump": false}
	await frames(60)
	mission.step = "road"
	sfx.set_radio(false)
	sfx.set_radio(true)       # sous-titre « Radio Pommiers »
	mission.horn()            # sous-titre « Klaxon » (les sous-titres durent ~3 s : on photographie tout de suite)
	await frames(2)
	root.get_texture().get_image().save_png(out_dir.path_join("audio_1_sous_titres_radio.png"))
	print("[audio-captures] terminé : ", sfx.counts)
	quit(0)
