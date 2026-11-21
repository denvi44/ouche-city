extends SceneTree
## Captures des bâtiments détaillés (agent 09) : rue de maisons (cheminées, lucarnes, corniches, auvents), commerce à store, église.
## Usage : godot --path game -s ../qa/screenshots/capture_batiments.gd -- --out=DIR   (Vulkan conseillé)

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
	print("[batiments-captures] ", name)


func look(from: Vector3, to: Vector3) -> void:
	var gy: float = world.builder.height_at(from.x, from.z) + 1.7
	from.y = maxf(from.y, gy)
	cam.look_at_from_position(from, to, Vector3.UP)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): push_error("[batiments-captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var out_dir: String = args.get("out", ProjectSettings.globalize_path("res://").path_join("../qa/screenshots/out/batiments"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(root.size)
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(40)
	world.day_night.running = false
	world.day_night.hour = 16.0
	world.day_night.apply()
	cam = Camera3D.new()
	cam.fov = 60.0
	world.add_child(cam)
	cam.make_current()
	var player = world.players_root.get_node("1")
	var poi = CityBuilder.read_json("res://assets/city/poi.json")
	var BD = load("res://scripts/world/building_details.gd")
	# Un commerce (store rayé), la maison la plus détaillée (lucarnes + cheminées), l'église.
	var shop := {}
	var church := {}
	for p in poi.pois:
		if shop.is_empty() and p.get("kind", "") == "shop" and p.has("facing"):
			shop = p
		if church.is_empty() and p.id == "eglise":
			church = p
	var target := {}
	var best := 0
	for key in CityBuilder.load_manifest().tiles:
		var data = CityBuilder.read_json("res://assets/city/tiles/%s.json" % key)
		for b in data.buildings:
			if b.typology in ["brique", "colombages", "pavillon"] and b.roof == "gabled":
				var ring: PackedVector2Array = CityBuilder.to_ring(b.footprint)
				var m: Dictionary = CityBuilder.ridge_model(ring, float(b.height), "gabled")
				var n: int = BD.chimney_spots(ring, m, CityBuilder._hash01(str(b.id)), b.typology).size() + BD.dormer_spots(ring, m, CityBuilder._hash01(str(b.id)), b.typology, int(b.get("levels", 1))).size()
				if n > best:
					best = n
					target = {"c": ring[0], "ring": ring, "h": float(b.height)}
	if not target.is_empty():
		var c := Vector2.ZERO
		for p in target.ring:
			c += p
		c /= target.ring.size()
		for ang in [0.8, 3.0]:
			var from := Vector3(c.x + cos(ang) * 22.0, 0, c.y + sin(ang) * 22.0)
			player.global_position = Vector3(from.x, world.builder.height_at(from.x, from.z) + 1.0, from.z)
			await frames(25)
			look(Vector3(from.x, 0, from.z) + Vector3(0, 6.0, 0), Vector3(c.x, world.builder.height_at(c.x, c.y) + target.h * 0.8, c.y))
			await shot(out_dir, "bat_1_maison_%d" % int(ang))
	if not shop.is_empty():
		var sp := Vector3(float(shop.position[0]), 0, float(shop.position[1]))
		sp.y = world.builder.height_at(sp.x, sp.z)
		var sf := float(shop.facing)
		var sfr := Vector3(sin(sf), 0, cos(sf))
		player.global_position = sp + sfr * 10.0 + Vector3(0, 1.0, 0)
		await frames(25)
		look(sp + sfr * 9.0 + Vector3(sfr.z, 0, -sfr.x) * 3.5 + Vector3(0, 1.8, 0), sp + Vector3(0, 2.2, 0))
		await shot(out_dir, "bat_2_commerce")
	if not church.is_empty():
		var cp := Vector3(float(church.position[0]), 0, float(church.position[1]))
		cp.y = world.builder.height_at(cp.x, cp.z)
		var cf := float(church.get("facing", 0.0))
		var cfr := Vector3(sin(cf), 0, cos(cf))
		player.global_position = cp + cfr * 18.0 + Vector3(0, 1.0, 0)
		await frames(25)
		look(cp + cfr * 24.0 + Vector3(cfr.z, 0, -cfr.x) * 10.0 + Vector3(0, 5.0, 0), cp + Vector3(0, 8.0, 0))
		await shot(out_dir, "bat_3_eglise")
	print("[batiments-captures] terminé")
	quit(0)
