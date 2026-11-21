extends SceneTree
## Captures des cinématiques : un cadre par plan (avancement 50 %), avec bandes noires, légende et carton de titre.
## Usage : godot --path game -s ../qa/screenshots/capture_cinematiques.gd -- --out=DIR [--only=m01_intro]   (Vulkan conseillé)
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
const DEFAULT := ["m01_intro", "m04_intro", "m06_intro", "m07_intro", "m07_failed", "m05_done"]


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/cinematiques"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var ids: Array = [str(args.only)] if args.has("only") else DEFAULT
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	var last_mission := ""
	var world = null
	for id in ids:
		var mission: String = id.substr(0, 3)
		if mission != last_mission:
			if world:
				world.queue_free()
				await frames(3)
			root.get_node("Net").mission_id = mission
			world = load(WORLD).instantiate()
			root.add_child(world)
			await frames(50)
			world.day_night.running = false
			world.day_night.hour = 15.0
			world.day_night.apply()
			for c in world.players_root.get_children():
				if c.peer_id < 0:
					c.set_physics_process(false)
					c.global_position = Vector3(0, -200, 0)
			last_mission = mission
		var d := CinematicPlayer.load_def(id)
		var poi: Dictionary = CityBuilder.read_json("res://assets/city/poi.json")
		var anchors := CinematicPlayer.anchors_from_pois(poi.pois, world.builder.height_at)
		for i in d.shots.size():
			var p := CinematicPlayer.new()
			world.add_child(p)
			p.start(d, anchors)
			paused = false
			p._shot = i - 1
			p._next_shot()
			p._t = 2.0
			p._shot_t = float(d.shots[i].dur) * 0.5
			p._apply(0.5)
			await frames(6)
			p._shot_t = float(d.shots[i].dur) * 0.5       # figé
			root.get_texture().get_image().save_png(out_dir.path_join("%s_plan%d.png" % [id, i + 1]))
			print("[cine] ", id, " plan ", i + 1)
			p.skip()
			await frames(2)
	quit()
