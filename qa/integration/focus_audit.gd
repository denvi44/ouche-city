extends SceneTree
## Un objectif à la fois : seul le lieu de l'objectif en cours garde son faisceau et son libellé dans le monde, et la liste des
## balises suit l'ordre de la tournée (mission 1 : cave, poulailler, grange, fumier ; la camionnette quand on porte une caisse).
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/focus_audit.gd
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, label: String) -> bool:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("ÉCHEC ", label)
	return cond


## Lieux dont le faisceau est visible.
func visible_places(world) -> Array:
	var out := []
	var places: Node = world.city.get_node("LieuxDeMission")
	for lieu in places.get_children():
		for c in lieu.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh and (c as MeshInstance3D).visible:
				out.append(str(lieu.name).trim_prefix("Lieu_"))
	out.sort()
	return out


func total_places(world) -> int:
	return world.city.get_node("LieuxDeMission").get_child_count()


func world_for(key: String):
	root.get_node("Net").mission_id = key
	var w = load(WORLD).instantiate()
	root.add_child(w)
	return w


func _run() -> void:
	create_timer(240.0).timeout.connect(func(): printerr("ÉCHEC délai"); quit(2))
	# --- Mission 1 ---
	var world = world_for("m01")
	for i in 60:
		await physics_frame
	var m = world.mission
	world._update_place_focus()
	check(total_places(world) >= 6, "la mission 1 compte %d lieux au total" % total_places(world))
	check(visible_places(world) == ["cave_gege"], "au départ, un seul faisceau : la cave (%s)" % str(visible_places(world)))
	m.crates["cave_gege"].state = "carried"
	m.crates["cave_gege"].carrier = 1
	await physics_frame
	world._update_place_focus()
	check(visible_places(world) == ["van_gege"], "caisse en main : la camionnette seule (%s)" % str(visible_places(world)))
	m.crates["cave_gege"].state = "loaded"
	m.crates["cave_gege"].carrier = 0
	world._update_place_focus()
	check(visible_places(world) == ["poulailler_ginette"], "caisse chargée : le poulailler (%s)" % str(visible_places(world)))
	m.crates["poulailler_ginette"].state = "loaded"
	world._update_place_focus()
	check(visible_places(world) == ["grange_pommiers"], "puis la grange (%s)" % str(visible_places(world)))
	m.crates["grange_pommiers"].state = "loaded"
	world._update_place_focus()
	check(visible_places(world) == ["fumier_tas"], "puis le tas de fumier (%s)" % str(visible_places(world)))
	m.crates["fumier_tas"].state = "loaded"
	m.step = "road"
	world._update_place_focus()
	check(visible_places(world) == ["barrage_bosc_tenney"], "sur la route : le barrage seul (%s)" % str(visible_places(world)))
	m.step = "fair"
	world._update_place_focus()
	check(visible_places(world) == ["stand_comite"], "à la foire : le stand seul (%s)" % str(visible_places(world)))
	m.step = "done"
	world._update_place_focus()
	check(visible_places(world).is_empty(), "mission finie : plus aucun faisceau")
	world.queue_free()
	await process_frame
	# --- Mission 7 : un seul but ---
	world = world_for("m07")
	for i in 60:
		await physics_frame
	world._update_place_focus()
	check(visible_places(world) == ["chez_soi"], "mission 7 : seule la maison est balisée (%s)" % str(visible_places(world)))
	world.queue_free()
	await process_frame
	# --- Mission 3 : un objet à la fois ---
	world = world_for("m03")
	for i in 60:
		await physics_frame
	world._update_place_focus()
	var v3 := visible_places(world)
	check(v3.size() == 1, "mission 3 : un seul lieu à la fois en préparation (%s)" % str(v3))
	world.queue_free()
	await process_frame
	# --- Mission 6 : un article à la fois ---
	world = world_for("m06")
	for i in 60:
		await physics_frame
	world._update_place_focus()
	check(visible_places(world).size() <= 1, "mission 6 : au plus un faisceau (%s)" % str(visible_places(world)))
	print("--- focus_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
