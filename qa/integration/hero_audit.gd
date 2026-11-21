extends SceneTree
## Le héros change selon la mission : le joueur prend le nom et la tenue du personnage prévu (missions/*.json, champ `hero`), son compagnon IA
## disparaît, les autres restent ; mission 8 : l'oie. Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/hero_audit.gd
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
const EXPECT := {"m01": -1, "m02": -4, "m03": -3, "m04": -2, "m05": -5, "m06": -1, "m07": -4, "m08": -5}
var fails := 0


func check(cond: bool, label: String) -> bool:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("ÉCHEC ", label)
	return cond


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(400.0).timeout.connect(func(): printerr("ÉCHEC délai"); quit(2))
	var H = load("res://scripts/core/heroes.gd")
	H.force = true
	check(H.hero_of("m01") == -1 and H.hero_of("m05") == -5 and H.hero_of("m99") == 0, "table des héros lue dans les missions")
	var world = null
	var seen := {}
	for m in EXPECT:
		if world:
			world.queue_free()
			await physics_frame
			await physics_frame
		root.get_node("Net").mission_id = m
		world = load(WORLD).instantiate()
		root.add_child(world)
		for i in 80:
			await physics_frame
		var me = world.players_root.get_node_or_null("1")
		if not check(me != null, "%s : le joueur est là" % m):
			continue
		var hid: int = EXPECT[m]
		check(me.hero_id == hid and me.display_name == H.name_of(hid), "%s : le joueur est %s (%s)" % [m, H.name_of(hid), me.display_name])
		check(world.players_root.get_node_or_null(str(hid)) == null, "%s : pas de double IA du héros" % m)
		var others := 0
		for c in world.players_root.get_children():
			if c.peer_id < 0:
				others += 1
		var roles: Dictionary = world.mission.companion_roles()
		var expected_others := roles.size() - (1 if roles.has(hid) else 0)
		check(others == expected_others, "%s : %d compagnons (attendu %d)" % [m, others, expected_others])
		if m == "m08":
			check(me.avatar == "oie", "m08 : l'héroïne est l'oie")
		else:
			var o = me.OUTFITS[hid]
			var sig := str(o.shirt)
			seen[hid] = sig
			check(me.model != null and me.model.detail_parts > 5, "%s : modèle de personnage détaillé" % m)
	check(seen.size() == 5, "cinq tenues humaines différentes au fil des missions (%d)" % seen.size())
	# Sans héros (tests, serveur dédié) : le joueur reste « Normand ».
	H.force = false
	check(H.hero_of("m01") == 0, "headless : pas de héros (les tests gardent leurs compagnons)")
	print("--- hero_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
