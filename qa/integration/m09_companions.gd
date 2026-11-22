extends SceneTree
## Compagnons IA de la mission 09 (mode « coéquipiers ») : le joueur est immobile près de la catapulte. Gégé et Kévin font la navette
## entre un étal et la catapulte, Ginette guette depuis son poste : à eux seuls ils chargent les dix camemberts et la catapulte tire.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m09_companions.gd -- --mission=m09

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
	root.get_node("Net").mission_id = "m09"
	root.get_node("Settings").companions_help = true      # ces tests vérifient que les compagnons savent tenir leurs rôles (mode « coéquipiers »)
	var world = load(WORLD).instantiate()
	root.add_child(world)
	for i in 80:
		await physics_frame
	var mission = world.mission
	var gege = world.players_root.get_node_or_null("-1")
	var ginette = world.players_root.get_node_or_null("-2")
	var kevin = world.players_root.get_node_or_null("-4")
	if not check(gege != null and ginette != null and kevin != null, "3 compagnons en mission 9 (Gégé, Ginette, Kévin)"):
		quit(1)
		return
	check(mission.companion_roles() == {-1: "porteur", -4: "chargeur", -2: "guetteur"}, "rôles : porteur, chargeur, guetteur")
	var player = world.players_root.get_node("1")
	player.global_position = mission.spot("watch") + Vector3(6, 0.6, 0)
	mission.time_left = 900.0
	var seen_carry := false
	var seen_post := false
	var status_g := ""
	var t_end := -1.0
	for i in 500 * 60:
		await physics_frame
		if i % 60 == 0:
			seen_carry = seen_carry or mission.carriers.has(-1) or mission.carriers.has(-4)
			if status_g == "" and "camembert" in mission.companion_status(gege):
				status_g = mission.companion_status(gege)
			seen_post = seen_post or mission.at_post(-2, "watch")
		if mission.step == "done":
			t_end = i / 60.0
			break
	check(seen_carry, "un compagnon porte un camembert (%s)" % status_g)
	check(seen_post, "Ginette gagne son poste de guet")
	check(mission.loaded >= mission.needed, "les compagnons ont chargé les dix camemberts (%d)" % mission.loaded)
	check(mission.step == "done" and mission.result == "win", "la catapulte a tiré : mission réussie (%.0f s)" % t_end)
	print("--- m09_companions : %s" % ("OK" if fails == 0 else "%d échec(s)" % fails))
	quit(1 if fails > 0 else 0)
