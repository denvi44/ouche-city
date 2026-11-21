extends SceneTree
## Captures des édifices détaillés (église, mairie, écoles, hôpital, distillerie de calva) : une vue de face et une vue de trois quarts.
## Usage : godot --path game -s ../qa/screenshots/capture_edifices.gd -- --out=DIR [--only=mairie]   (Vulkan conseillé)
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var world
var cam: Camera3D


func frames(n: int) -> void:
	for i in n:
		await process_frame


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/edifices"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	root.get_node("Settings").cinematics = false
	root.get_node("Net").mission_id = "m01"
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	cam = Camera3D.new()
	cam.fov = 58.0
	world.add_child(cam)
	cam.make_current()
	world.day_night.running = false
	world.day_night.hour = 14.0
	world.day_night.apply()
	for c in world.players_root.get_children():
		c.set_physics_process(false)
		c.global_position = Vector3(0, -300, 0)
	var hud = world.get_children().filter(func(n): return n is CanvasLayer)
	for h in hud:
		h.visible = false
	var poi: Dictionary = CityBuilder.read_json("res://assets/city/poi.json")
	var only := str(args.get("only", ""))
	for p in poi.pois:
		if not p.has("facility"):
			continue
		if only != "" and str(p.id) != only:
			continue
		var x := float(p.position[0])
		var z := float(p.position[1])
		var f := float(p.facing)
		var bas := Basis(Vector3.UP, f)
		var gy: float = world.builder.height_at(x, z)
		var big := maxf(float(p.rect[0]), float(p.rect[1]))
		var sets := [["face", Vector3(0, 0.12 * big + 3.0, big * 0.9 + 14.0), Vector3(0, 0.18 * big + 2.0, 0)],
			["trois_quarts", Vector3(big * 0.75 + 8.0, 0.2 * big + 5.0, big * 0.7 + 10.0), Vector3(0, 0.15 * big + 2.0, 0)]]
		for st in sets:
			var from: Vector3 = Vector3(x, gy, z) + bas * st[1]
			from.y = maxf(from.y, world.builder.height_at(from.x, from.z) + 2.0)
			cam.look_at_from_position(from, Vector3(x, gy, z) + bas * st[2], Vector3.UP)
			await frames(8)
			root.get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [p.id, st[0]]))
			print("[edifices] ", p.id, " ", st[0])
	# Carrière : vue depuis le bord (côté rampe) et vue plongeante ; forêt : vue basse sous les arbres ; verger.
	for p in poi.pois:
		if str(p.get("prop", "")) != "carriere":
			continue
		var cx := float(p.position[0])
		var cz := float(p.position[1])
		var bas2 := Basis(Vector3.UP, float(p.facing))
		var gyc: float = world.builder.height_at(cx, cz)
		var vues := [["rim", Vector3(-14, 18, 92), Vector3(0, -6, 0)], ["fond", Vector3(-8, 6, -34), Vector3(-6, 2, 4)], ["ramp", Vector3(30, 22, 80), Vector3(0, -3, 20)]]
		for v in vues:
			var fr: Vector3 = Vector3(cx, gyc, cz) + bas2 * v[1]
			fr.y = maxf(fr.y, world.builder.height_at(fr.x, fr.z) + 2.0)
			cam.look_at_from_position(fr, Vector3(cx, gyc, cz) + bas2 * v[2], Vector3.UP)
			await frames(8)
			root.get_texture().get_image().save_png(out_dir.path_join("carriere_%s.png" % v[0]))
			print("[edifices] carrière ", v[0])
	var forest := Vector2.ZERO
	var orchard := Vector2.ZERO
	for tf in DirAccess.get_files_at("res://assets/city/tiles"):
		var td = CityBuilder.read_json("res://assets/city/tiles/" + tf)
		if td is Dictionary:
			for tr in td.trees:
				if tr.size() > 2 and int(tr[2]) == 1 and forest == Vector2.ZERO:
					forest = Vector2(tr[0], tr[1])
				if tr.size() > 2 and int(tr[2]) == 2 and orchard == Vector2.ZERO:
					orchard = Vector2(tr[0], tr[1])
	for spec in [["foret", forest], ["verger", orchard]]:
		var c: Vector2 = spec[1]
		if c == Vector2.ZERO:
			continue
		var gy2: float = world.builder.height_at(c.x, c.y)
		cam.look_at_from_position(Vector3(c.x - 26, gy2 + 5.5, c.y - 26), Vector3(c.x, gy2 + 3.0, c.y), Vector3.UP)
		await frames(8)
		root.get_texture().get_image().save_png(out_dir.path_join("%s.png" % spec[0]))
		print("[edifices] ", spec[0])
	print("[edifices] terminé")
	quit()
