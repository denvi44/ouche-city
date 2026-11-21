extends SceneTree
## Captures de la mission 04 et des accessoires détaillés (agent 09) : cuisine du méchoui, chien, tables servies, bûcher,
## planche-contact des accessoires, mobilier de rue devant un commerce et le long d'une route.
## Usage : godot --path game -s ../qa/screenshots/capture_m04.gd -- --out=DIR --mission=m04 --no-companions   (Vulkan conseillé)

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
	print("[m04-captures] ", name)


func look(from: Vector3, to: Vector3, min_above := 2.0) -> void:
	var gy: float = world.builder.height_at(from.x, from.z) + min_above
	from.y = maxf(from.y, gy)
	cam.look_at_from_position(from, to, Vector3.UP)


func front() -> Vector3:
	var f: float = mission.facings["fete"]
	return Vector3(sin(f), 0, cos(f))


func ground(p: Vector3, up := 0.0) -> Vector3:
	return Vector3(p.x, world.builder.height_at(p.x, p.z) + up, p.z)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[m04-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/m04"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	world.day_night.hour = 19.0
	world.day_night.apply()
	mission = world.mission
	player = world.players_root.get_node("1")
	cam = Camera3D.new()
	cam.fov = 62.0
	world.add_child(cam)
	cam.make_current()
	var st: Vector3 = mission.station()
	var fr := front()
	var right := Vector3(fr.z, 0, -fr.x)
	# 1. La cuisine du méchoui : l'agneau tourne sur la broche, feu dans la bonne plage.
	for it in mission.ITEMS:
		mission.items_taken.append(it)
	mission.step = "fire"
	mission.heat = 0.6
	mission.cook = 0.55
	mission.burn = 0.0
	mission.stolen = 1
	mission.shooed = 2
	mission.messages.append("Un chien errant flaire le méchoui !")
	mission.set_physics_process(false)
	for c in world.players_root.get_children():
		if c.peer_id < 0:
			c.global_position = mission.spot("grill" if c.peer_id == -1 else "pass") + Vector3(0, 0.6, 0)
	player.global_position = st + fr * 3.5 + Vector3(0, 0.8, 0)
	await frames(40)
	look(st + fr * 6.5 + right * 3.5 + Vector3(0, 2.0, 0), st + Vector3(0, 1.2, 0))
	await shot(out_dir, "m04_1_la_broche")
	# 2. Un chien errant approche.
	mission.dogs = [{"id": 7, "x": st.x + fr.x * 7.0 + right.x * 3.0, "z": st.z + fr.z * 7.0 + right.z * 3.0, "vx": -fr.x * 3.2, "vz": -fr.z * 3.2, "st": "run", "t": 0.0}]
	mission.dog_seq = 7
	await frames(10)
	look(st + fr * 14.0 - right * 4.0 + Vector3(0, 2.4, 0), st + fr * 5.0 + right * 2.0 + Vector3(0, 0.6, 0))
	await shot(out_dir, "m04_2_le_chien")
	mission.dogs = []
	# 3. Les tables : service en cours.
	mission.step = "serve"
	mission.cook = 1.0
	mission.plates_left = 3
	mission.served = [2, 2, 1, 0]
	mission.carry = {1: true}
	mission.serve_left = 71.0
	await frames(20)
	look(st + fr * 5.0 + Vector3(0, 4.2, 0) - right * 13.0, mission.table_pos(0) + fr * 4.0 + Vector3(0, 0.9, 0))
	await shot(out_dir, "m04_3_les_tables")
	# 4. Le bûcher allumé, de nuit.
	mission.step = "bonfire"
	mission.served = [2, 2, 2, 2]
	mission.carry = {}
	await frames(4)
	mission.lit = true
	world.day_night.hour = 20.2
	world.day_night.apply()
	var pz: Vector3 = mission.zones.bucher
	var pf: float = mission.facings["bucher"]
	var pfr := Vector3(sin(pf), 0, cos(pf))
	player.global_position = pz + pfr * 8.0 + Vector3(0, 0.8, 0)
	await frames(30)
	look(pz + pfr * 8.0 + Vector3(pfr.z, 0, -pfr.x) * 6.0, pz + Vector3(0, 1.8, 0), 8.0)
	var fl = world.find_child("M4_FlammesBucher", true, false)
	print("[m04-captures] flammes ", fl, " visible=", fl.visible if fl else "-", " pos=", fl.global_position if fl else "-", " bucher=", pz)
	await shot(out_dir, "m04_4_le_bucher")
	mission.step = "done"
	mission.result = "win"
	mission.medal = "gold"
	mission.satisfaction = 93.0
	await shot(out_dir, "m04_5_bilan")
	# 5. Planche-contact des accessoires détaillés, alignés au sol près de la cuisine.
	world.day_night.hour = 12.0
	world.day_night.apply()
	mission.step = "gather"
	mission.lit = false
	var names := ["lamp", "bench", "planter", "bollard", "well", "hay_bale", "barrel", "chair", "table_set", "spit", "brazier", "dog", "lamb", "charcoal"]
	var base := st + fr * 26.0 - right * 20.0
	var gallery := Node3D.new()
	world.add_child(gallery)
	var kit_script = load("res://scripts/world/prop_kit.gd")
	for i in names.size():
		var kit = Callable(kit_script, names[i]).call()
		var n: Node3D = kit.build()
		var p := base + right * (i * 3.1)
		n.position = ground(p, 0.0)
		n.rotation.y = atan2(-fr.x, -fr.z) + 0.5
		gallery.add_child(n)
	var mid := base + right * (names.size() * 3.1 / 2.0)
	look(ground(mid, 0.0) + fr * 17.0 + Vector3(0, 5.0, 0), ground(mid, 0.0) + Vector3(0, 1.1, 0))
	cam.fov = 50.0
	await shot(out_dir, "m04_6_accessoires")
	gallery.queue_free()
	cam.fov = 62.0
	# 6. Mobilier de rue : devant un commerce, puis un lampadaire le long d'une route.
	var poi = CityBuilder.read_json("res://assets/city/poi.json")
	var shop := {}
	for p in poi.pois:
		if p.get("kind", "") == "shop" and p.has("facing"):
			shop = p
			break
	if not shop.is_empty():
		var sp := Vector3(float(shop.position[0]), 0, float(shop.position[1]))
		sp.y = world.builder.height_at(sp.x, sp.z)
		var sf := float(shop.facing)
		var sfr := Vector3(sin(sf), 0, cos(sf))
		player.global_position = sp + sfr * 9.0 + Vector3(0, 0.8, 0)
		await frames(30)
		look(sp + sfr * 7.5 + Vector3(sfr.z, 0, -sfr.x) * 3.0 + Vector3(0, 1.8, 0), sp + Vector3(0, 1.5, 0))
		await shot(out_dir, "m04_7_devant_un_commerce")
	var tiles: Array = world.builder.grids.keys()
	var SF = load("res://scripts/world/street_furniture.gd")
	var spot: Transform3D = Transform3D.IDENTITY
	for key in CityBuilder.load_manifest().tiles:
		var data = CityBuilder.read_json("res://assets/city/tiles/%s.json" % key)
		var lamps: Array = SF.lamp_spots(data, world.builder.height_at)
		if lamps.size() > 6:
			spot = lamps[3]
			break
	var lp: Vector3 = spot.origin
	var lf: Vector3 = spot.basis * Vector3(0, 0, 1)
	player.global_position = lp + lf * 6.0 + Vector3(0, 0.8, 0)
	await frames(30)
	look(lp + lf * 9.0 + Vector3(lf.z, 0, -lf.x) * 4.0 + Vector3(0, 2.6, 0), lp + Vector3(0, 2.8, 0))
	await shot(out_dir, "m04_8_lampadaire")
	print("[m04-captures] terminé")
	quit(0)
