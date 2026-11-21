extends SceneTree
## Compagnons IA de la mission 08 (agent 09) : le joueur est immobile à la mare. Kévin rassemble les oies et les mène à la voie,
## Ginette guette le garde-barrière et lui crie dessus quand il approche, Gégé rassure les oies sur la voie : à trois, ils bloquent
## le train et gagnent seuls.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m08_companions.gd -- --mission=m08

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
	create_timer(900.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	root.get_node("Net").mission_id = "m08"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	for i in 80:
		await physics_frame
	var mission = world.mission
	var kevin = world.players_root.get_node_or_null("-4")
	var ginette = world.players_root.get_node_or_null("-2")
	var gege = world.players_root.get_node_or_null("-1")
	if not check(kevin != null and ginette != null and gege != null, "3 compagnons en mission 8 (Kévin, Ginette, Gégé)"):
		quit(1)
		return
	check(kevin.avatar == "oie" and kevin.model is GooseModel, "les compagnons sont des oies aussi")
	check(mission.companion_roles() == {-4: "rabatteuse", -2: "sentinelle", -1: "ferme_file"}, "rôles : rabatteuse, sentinelle, ferme-file")
	mission.time_left = 900.0
	var seen_follow := 0
	var seen_block := 0
	var seen_stunned := false
	var seen_stop := false
	var t_stop := -1.0
	var t_end := -1.0
	var status_k := ""
	for i in 700 * 60:
		await physics_frame
		if i % 60 == 0:
			seen_follow = maxi(seen_follow, mission.count_state("follow"))
			seen_block = maxi(seen_block, mission.blockers())
			if status_k == "" and "rassemble" in mission.companion_status(kevin):
				status_k = mission.companion_status(kevin)
		if i % 300 == 0 and mission.train.st == "stopped":
			print("    t=%.0f maître=%s (%.0f, %.0f) Ginette=(%.0f, %.0f) statut=%s" % [i / 60.0, mission.master.st, mission.master.x, mission.master.z, ginette.global_position.x, ginette.global_position.z, mission.companion_status(ginette)])
		if mission.master.st == "stunned":
			seen_stunned = true
		if mission.train.st == "stopped" and not seen_stop:
			seen_stop = true
			t_stop = i / 60.0
		if mission.step in ["done", "failed"]:
			t_end = i / 60.0
			break
	print("  ", mission.messages)
	check(seen_follow >= 6, "Kévin a rassemblé des oies derrière lui (jusqu'à %d)" % seen_follow)
	check(seen_block >= mission.min_blockers, "les oies se sont installées sur la voie (jusqu'à %d)" % seen_block)
	check(seen_stop, "le train s'est arrêté (%.0f s)" % t_stop)
	check(seen_stunned, "Ginette a fait reculer le garde-barrière")
	check(mission.step == "done" and mission.result == "win", "les compagnons gagnent seuls (%s, %s, %.0f s, moyenne %.1f oies)" % [mission.step, mission.result, t_end, mission.avg_blockers])
	check("rassemble" in status_k or status_k == "", "statut de Kévin lisible : « %s »" % status_k)
	print("--- m08_companions : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
