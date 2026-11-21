extends SceneTree
## Test d'intégration des compagnons de la mission 05 (agent 09) : le joueur est immobile.
## Kévin rabat le troupeau (derrière les vaches, avec le sifflet), Ginette guette et décrit la vache la plus proche,
## Gégé tient la barrière et la ferme quand tout le monde est rentré.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m05_companions.gd -- --mission=m05

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
	create_timer(800.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	root.get_node("Settings").companions_help = true      # ces tests vérifient que les compagnons savent tenir leurs rôles (mode « coéquipiers »)
	var world = load(WORLD).instantiate()
	root.add_child(world)
	for i in 80:
		await physics_frame
	var mission = world.mission
	var ginette = world.players_root.get_node_or_null("-2")
	var kevin = world.players_root.get_node_or_null("-4")
	var gege = world.players_root.get_node_or_null("-1")
	if not check(ginette != null and kevin != null and gege != null, "3 compagnons en mission 5 (Kévin, Ginette, Gégé)"):
		quit(1)
		return
	check(mission.companion_roles() == {-4: "rabatteur", -2: "guetteur", -1: "barriere"}, "rôles : rabatteur, guetteur, barrière")
	mission.time_left = 900.0
	var seen_status := ""
	var t_gate := -1.0
	for i in 600 * 60:
		await physics_frame
		if i % 600 == 0 and seen_status == "":
			var st: String = mission.companion_status(ginette)
			if "vache" in st:
				seen_status = st
		if mission.step != "herd":
			t_gate = i / 60.0
			break
	print("  ", mission.messages)
	check(mission.penned() == 8, "Kévin a rentré les huit vaches seul (%d/8)" % mission.penned())
	check(mission.whistles >= 1, "Kévin a sifflé (%d fois)" % mission.whistles)
	check("vache" in seen_status, "Ginette décrit la vache la plus proche : « %s »" % seen_status)
	check(mission.at_post(-1, "gate") or mission.step != "herd", "Gégé gagne la barrière")
	if mission.step == "gate":
		for i in 10 * 60:
			await physics_frame
			if mission.step == "done":
				break
		check(mission.step == "done" and mission.gate_closed, "Gégé a fermé la barrière : tous les compagnons ont fini le travail (%.0f s)" % t_gate)
	else:
		print("  (troupeau pas entièrement rentré : %d/8)" % mission.penned())
	print("--- m05_companions : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
