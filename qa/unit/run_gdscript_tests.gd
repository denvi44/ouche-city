extends SceneTree
## Tests unitaires GDScript (agent 09). Usage : godot --headless --path game -s ../qa/unit/run_gdscript_tests.gd
## Les scripts du jeu sont chargés dynamiquement (load) pour que les autoloads soient déjà enregistrés.

var _fails := 0
var _count := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, label: String) -> void:
	_count += 1
	if not cond:
		_fails += 1
		printerr("ÉCHEC : ", label)


func _run() -> void:
	var NetScript = load("res://scripts/net/network_manager.gd")
	var Builder = load("res://scripts/world/city_builder.gd")
	var DN = load("res://scripts/world/day_night.gd")
	var Hud = load("res://ui/hud.gd")

	# --- Réseau : arguments et admission ---
	var a: Dictionary = NetScript.parse_args(PackedStringArray(["--server", "--port=9000", "--join=1.2.3.4:5", "x"]))
	check(a.get("server") == true and a.get("port") == "9000" and a.get("join") == "1.2.3.4:5" and a.size() == 3, "parse_args")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION, 1, true) == "", "admission ok")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION + 1, 1, true).begins_with("Version différente"), "refus version")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION, 1, false) != "", "refus solo fermé")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION, 16, true) != "", "refus partie pleine")

	# --- Cycle jour/nuit ---
	var noon: Dictionary = DN.sample(12.0)
	var night: Dictionary = DN.sample(23.0)
	check(noon.sun_energy > night.sun_energy, "midi plus lumineux que minuit")
	check(DN.sample(24.0).sun_energy == DN.sample(0.0).sun_energy, "rampe cyclique")
	check(DN.sun_rotation(12.0).x < -0.5, "soleil haut à midi")

	# --- Géométrie de la ville ---
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(20, 10), Vector2(20, 0)])
	check(absf(Builder.signed_area(sq)) == 200.0, "aire du rectangle")
	var m: Dictionary = Builder.ridge_model(sq, 6.0, "gabled")
	check(is_equal_approx(Builder.roof_height(m, Vector2(10, 5)), 6.0 + 6.0), "faîtage au milieu, pente 1,2")
	check(is_equal_approx(Builder.roof_height(m, Vector2(10, 0)), 6.0), "égout à la hauteur des murs")
	check(Builder.split_ring_at_ridge(sq, m).size() == 6, "deux points de faîtage insérés")
	var flat: Dictionary = Builder.ridge_model(sq, 6.0, "flat")
	check(flat.k == 0.0, "toit plat sans pente")

	var b = Builder.new()
	var tile := {"schemaVersion": 1, "tile": {"x": 0, "y": 0}, "origin": [0, 0], "size": 250,
		"ground": {"resolution": 2, "baseAltitude": 100.0, "heights": [0.0, 10.0, 0.0, 10.0]},
		"buildings": [{"id": "b_1", "footprint": [[10, 10], [10, 20], [30, 20], [30, 10]], "height": 7.0, "roof": "gabled", "typology": "colombages", "groundZ": 0.0},
			{"id": "b_2", "footprint": [[50, 50], [50, 70], [70, 70], [70, 50]], "height": 18.0, "roof": "spire", "typology": "eglise", "groundZ": 0.0}],
		"roads": [{"id": "r_1", "name": "Rue Test", "kind": "residential", "points": [[0, 100], [250, 100]], "width": 5.0, "sidewalk": 1.2}],
		"vegetation": [{"kind": "park", "polygon": [[100, 150], [100, 200], [150, 200], [150, 150]]}],
		"trees": [[120, 170]], "attribution": ["test"]}
	b.register_tile(tile)
	check(is_equal_approx(b.height_at(125.0, 50.0), 5.0), "relief bilinéaire au centre")
	check(absf(b.height_at(-50.0, 10.0)) < 0.05 and absf(b.height_at(400.0, 10.0) - 10.0) < 0.05, "relief prolongé hors tuile")
	var node: Node3D = b.build_tile(tile)
	var bat := node.get_node_or_null("Batiments") as MeshInstance3D
	check(bat != null and bat.mesh.get_surface_count() >= 3, "bâtiments : murs + toits par matériau")
	check(node.get_node_or_null("Collisions") != null and node.get_node("Collisions").get_child_count() >= 2, "collisions bâtiments + terrain")
	check(node.get_node_or_null("Sol") != null, "routes et végétation")
	check(node.get_node_or_null("Arbres") != null, "arbres")
	# Murs tournés vers l'extérieur : la normale d'un mur pointe hors de l'emprise.
	var arrays: Array = bat.mesh.surface_get_arrays(_surface(bat.mesh, "colombages"))
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward := true
	for i in verts.size():
		var c := Vector3(20, verts[i].y, 15)
		if normals[i].dot(verts[i] - c) <= 0.0:
			outward = false
	check(outward, "normales des murs vers l'extérieur")
	# Faces avant dans le sens horaire (convention Godot) vues depuis la normale.
	var cw := true
	for t in range(0, verts.size(), 3):
		if (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).dot(normals[t]) > 0.0:
			cw = false
	check(cw, "triangles des murs dans le sens horaire")
	node.free()

	# --- Ville réelle importée ---
	var manifest: Dictionary = Builder.load_manifest()
	check(manifest.get("tiles", []).size() > 0, "manifeste de la ville présent")
	var credit: String = Hud.map_credit(manifest)
	check("IGN" in credit or "OpenStreetMap" in credit, "mention des sources")

	print("%d tests, %d échec(s)" % [_count, _fails])
	quit(1 if _fails > 0 else 0)


func _surface(mesh: ArrayMesh, name: String) -> int:
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == name:
			return i
	return 0
