extends SceneTree
## Île : le village est entouré de mer et de murs invisibles, les routes qui sortent des tuiles sont barrées, la grande carte (M) existe.
## Usage : godot --headless --path game -s ../qa/integration/island_audit.gd
const CITY := "res://assets/city"
const B := preload("res://scripts/core/input_bindings.gd")
var fails := 0


func check(ok: bool, msg: String) -> void:
	print(("OK    " if ok else "ÉCHEC ") + msg)
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var b := CityBuilder.new()
	var city := b.build_city(CITY, "")
	root.add_child(city)
	var apron := city.get_node_or_null("Tablier")
	check(apron != null, "le tablier existe")
	var sea := b.sea_level()
	# Le relief plonge sous la mer au-delà de SHORE_END, sans saut depuis le bord.
	var far := b.apron_height(b.bounds.end.x + CityBuilder.SHORE_END + 10.0, b.bounds.get_center().y)
	check(far < sea - 3.0, "le relief du large est sous la mer (%.1f < %.1f)" % [far, sea])
	var edge := b.apron_height(b.bounds.end.x, b.bounds.get_center().y)
	check(absf(edge - b.height_at(b.bounds.end.x - 0.01, b.bounds.get_center().y)) < 0.05, "pas de marche au bord des tuiles")
	check(edge > sea, "la terre du bord reste au-dessus de la mer")
	# Murs : un rayon horizontal vers le large doit les toucher à SHORE_GROW du bord.
	var space := root.get_world_3d().direct_space_state
	await physics_frame
	await physics_frame
	var c := b.bounds.get_center()
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var from := Vector3(c.x, sea + 2.0, c.y)
		var half := b.bounds.size * 0.5
		var start: Vector3 = from + dir * (half.x - 5.0 if absf(dir.x) > 0.0 else half.y - 5.0)
		var q := PhysicsRayQueryParameters3D.create(start, start + dir * (CityBuilder.SHORE_GROW + 80.0))
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		var ok := false
		if not hit.is_empty():
			ok = true
		check(ok, "un mur ou le relief arrête le rayon vers %s" % str(dir))
	check(city.get_node_or_null("BarrieresDeFinDeRoute") != null, "les barrières de fin de route existent")
	if city.get_node_or_null("BarrieresDeFinDeRoute"):
		var n := city.get_node("BarrieresDeFinDeRoute").get_child_count()
		check(n >= 4, "des routes sont barrées en bordure de carte (%d)" % n)
	check(InputMap.has_action("map_toggle"), "la touche de grande carte est déclarée")
	check(B.ids().has("map_toggle"), "la grande carte est remappable")
	print("RÉSULTAT : %d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
