extends SceneTree
## Test d'intégration des compagnons de la mission 03 (agent 09) : le joueur est immobile, les compagnons agissent.
## Chacun rapporte son objet (Kévin le caisson, Ginette la rallonge, Gégé le groupe), puis gagne son poste :
## Gégé veille sur le groupe (rebranche vite), Ginette tient les portes, Kévin sabote la sono rivale.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m03_companions.gd -- --mission=m03

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


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	create_timer(500.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(80)
	var mission = world.mission
	var ginette = world.players_root.get_node_or_null("-2")
	var kevin = world.players_root.get_node_or_null("-4")
	var gege = world.players_root.get_node_or_null("-1")
	if not check(ginette != null and kevin != null and gege != null and world.players_root.get_node_or_null("-3") == null, "3 compagnons en mission 3 (Gégé, Ginette, Kévin)"):
		quit(1)
		return
	check(mission.companion_roles() == {-1: "electricien", -2: "videur", -4: "saboteur"}, "rôles : électricien, videur, saboteur")

	# --- Matériel : chacun rapporte son objet ---------------------------------------------------------------------
	for i in 240 * 60:
		await physics_frame
		if mission.step == "round":
			break
	check(mission.step == "round" and mission.items_taken.size() == 3, "les compagnons ont rassemblé les 3 objets (%s)" % str(mission.items_taken))
	var heard := " ".join(mission.messages)
	check("Kévin" in heard or "Ginette" in heard or "Gégé" in heard, "les prises sont annoncées")
	print("  ", heard)

	# --- Postes : on tient la manche au choix de playlist, le temps qu'ils arrivent ----------------------------------------
	var posts := {"groupe": -1, "videur": -2, "clos": -4}
	for i in 240 * 60:
		mission.pick_left = 9999.0
		await physics_frame
		var all := true
		for s in posts:
			all = all and mission.at_post(posts[s], s)
		if all:
			break
	for s in posts:
		check(mission.at_post(posts[s], s), "poste tenu : %s (%s)" % [s, world.players_root.get_node(str(posts[s])).brain.status])
	check(mission.companion_status(kevin) == "sabote la sono du Clos Fleuri", "statut de Kévin lisible dans le HUD")
	var max_p: float = mission.max_points(0)
	check(is_equal_approx(mission.rival_goal(), max_p * (mission.RIVAL_RATIO[0] - mission.SABOTEUR_CUT)), "Kévin réduit l'objectif du rival (%.1f)" % mission.rival_goal())

	# --- Manche 1 : Gégé rebranche, Ginette gagne des points d'ambiance ------------------------------------------------------
	mission.choose_for(1, "1")
	await frames(60 * 3 + 10)
	check(mission.round_state == "play", "manche en cours")
	mission.sab = {"kind": "unplug", "left": mission.SABOTAGE_TIME}
	await frames(60 * 2)
	check(mission.sab.kind == "" and mission.sab_blocked == 1 and mission.mute_left == 0.0, "Gégé a rebranché la rallonge seul")
	for i in 60 * 40:
		await physics_frame
		if mission.round_state == "result":
			break
	var bonus: float = mission.VIDEUR_BONUS * max_p
	check(mission.results.size() == 1 and mission.results[0].p >= bonus - 0.1, "Ginette a tenu les portes : +%d points d'ambiance sans que le joueur joue (%s)" % [int(bonus), str(mission.results[0])])
	print("--- m03_companions : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
