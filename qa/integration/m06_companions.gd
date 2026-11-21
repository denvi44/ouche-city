extends SceneTree
## Test d'intégration des compagnons de la mission 06 (agent 09) : le joueur est immobile devant la porte.
## Gégé va chercher le cidre et les palets (à 2 à l'heure, par les allées), Ginette file papoter avec Mme Hubert (qui ne peut
## plus retenir le joueur), Kévin attend au volant.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m06_companions.gd -- --mission=m06

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


func _run() -> void:
	create_timer(700.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	root.get_node("Settings").companions_help = true      # ces tests vérifient que les compagnons savent tenir leurs rôles (mode « coéquipiers »)
	var world = load(WORLD).instantiate()
	root.add_child(world)
	for i in 100:
		await physics_frame
	var mission = world.mission
	var ginette = world.players_root.get_node_or_null("-2")
	var kevin = world.players_root.get_node_or_null("-4")
	var gege = world.players_root.get_node_or_null("-1")
	if not check(ginette != null and kevin != null and gege != null, "3 compagnons en mission 6 (Gégé, Ginette, Kévin)"):
		quit(1)
		return
	check(mission.companion_roles() == {-2: "bavarde", -1: "caddie", -4: "chauffeur"}, "rôles : bavarde, caddie, chauffeur")
	check(is_equal_approx(gege.speed_cap, 2.0 / 3.6) and is_equal_approx(ginette.speed_cap, 2.0 / 3.6), "les compagnons marchent aussi à 2 km/h")
	var start_l: Vector2 = mission.to_local(gege.global_position)
	check(start_l.y > 9.0, "Gégé part de devant la porte")
	var got := false
	for i in 330 * 60:
		await physics_frame
		if "cidre" in mission.items_got and "palets" in mission.items_got:
			got = true
			break
	check(got, "Gégé a rapporté le cidre et les palets (%s)" % str(mission.items_got))
	check(mission.items_got.size() == 2 and mission.companion_status(gege) == "a rempli sa part du cabas", "Gégé a fini sa part : 2 articles sur 6")
	for i in 120 * 60:
		await physics_frame
		if mission.at_post(-2, "chat"):
			break
	check(mission.at_post(-2, "chat"), "Ginette papote avec Mme Hubert (%s)" % mission.companion_status(ginette))
	# Ginette occupe Mme Hubert : le joueur peut passer sans être retenu.
	var player = world.players_root.get_node("1")
	var w: Vector3 = mission.to_world(mission.CHAT_SPOT + Vector2(1.6, 0))
	player.global_position = Vector3(w.x, w.y + 0.5, w.z)
	for i in 60:
		await physics_frame
	check(mission.chat_left == 0.0 and not mission.chat_done, "Mme Hubert, occupée par Ginette, ne retient pas le joueur")
	var kl: Vector2 = mission.to_local(kevin.global_position)
	check(kl.distance_to(Vector2(6.0, 13.0)) < 4.0, "Kévin attend au volant sur le parking")
	print("--- m06_companions : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
