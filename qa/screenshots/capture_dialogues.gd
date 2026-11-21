extends SceneTree
## Captures des dialogues et des onomatopées (agent 09) : bulles de paroles au-dessus des compagnons, sous-titre de la réplique,
## onomatopées de ton « loud / soft / good / bad ».
## Usage : godot --path game -s ../qa/screenshots/capture_dialogues.gd -- --out=DIR   (Vulkan conseillé)

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await process_frame


func shot(out_dir: String, name: String) -> void:
	await frames(8)
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("[dialogues-captures] ", name)


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): push_error("[dialogues-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/dialogues"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	world.day_night.running = false
	world.day_night.hour = 15.0
	world.day_night.apply()
	world.mission.set_physics_process(false)
	var dlg: DialoguePlayer = world.get_node("Dialogues")
	dlg.skip()
	var bub: SpeechBubbles = world.get_node("Bulles")
	var ono: OnomaLayer = world.get_node("Onomatopees")
	# Les compagnons en ligne devant la caméra, le joueur derrière.
	var base: Vector3 = world.spawn_point
	var gy: float = world.builder.height_at(base.x, base.z)
	var who := {"-1": -2.2, "-2": 0.0, "-4": 2.2}
	for id in who:
		var c = world.players_root.get_node(id)
		c.global_position = Vector3(base.x + who[id], gy + 0.6, base.z)
		c.set_physics_process(false)
		if c.brain:
			c.brain = null
	var me = world.players_root.get_node("1")
	me.global_position = Vector3(base.x, gy + 0.6, base.z - 4.0)
	await frames(30)
	cam = Camera3D.new()
	cam.fov = 48.0
	world.add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(base.x, gy + 2.2, base.z - 11.0), Vector3(base.x, gy + 2.4, base.z), Vector3.UP)
	# 1. Conversation : trois bulles, sous-titre de la dernière réplique.
	bub.show_bubble("Gégé", "Mon p'tit, vingt-quatre bouteilles de calva de dix-huit ans d'âge !", world.players_root.get_node("-1"), 30.0)
	bub.show_bubble("Ginette", "Et pas une de cassée, hein !", world.players_root.get_node("-2"), 30.0)
	bub.show_bubble("Kévin", "Moi je fais diversion. J'ai un fanion.", world.players_root.get_node("-4"), 30.0)
	dlg.line_started.emit("Kévin", "Moi je fais diversion. J'ai un fanion.", "m01_intro_03", 30.0, {})
	await shot(out_dir, "dial_1_bulles")
	# 2. Onomatopées des quatre tons, autour des compagnons.
	Engine.time_scale = 0.08          # le rendu logiciel est lent : on ralentit les animations pour les voir
	for pair in [["POUET POUET !", "loud", -3.0, 2.8], ["MEUUUH !", "soft", 3.2, 3.2], ["DING !", "good", -1.0, 4.4], ["CRAAAC !", "bad", 1.4, 4.6]]:
		ono.spawn(pair[0], Vector3(base.x + pair[2], gy + pair[3], base.z + 0.5), pair[1])
	await frames(6)
	await shot(out_dir, "dial_2_onomatopees")
	Engine.time_scale = 1.0
	print("[dialogues-captures] terminé")
	quit(0)
