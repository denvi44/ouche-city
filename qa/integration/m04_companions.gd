extends SceneTree
## Test d'intégration des compagnons de la mission 04 (agent 09) : le joueur est immobile, les compagnons font tout.
## Chacun rapporte son objet ; Gégé tient le feu dans la bande, Kévin chasse les chiens, Ginette sert les huit assiettes.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m04_companions.gd -- --mission=m04

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
	if not check(ginette != null and kevin != null and gege != null and world.players_root.get_node_or_null("-3") == null, "3 compagnons en mission 4 (Gégé, Ginette, Kévin)"):
		quit(1)
		return
	check(mission.companion_roles() == {-1: "cuisinier", -2: "serveur", -4: "gardien"}, "rôles : cuisinier, serveur, gardien")

	# --- Matériel -----------------------------------------------------------------------------------------------------
	for i in 240 * 60:
		await physics_frame
		if mission.step == "fire":
			break
	check(mission.step == "fire" and mission.items_taken.size() == 3, "les compagnons ont rapporté les 3 objets (%s)" % str(mission.items_taken))

	# --- Feu : Gégé tient la bande, Kévin chasse les chiens ------------------------------------------------------------------
	var min_heat := 1.0
	var max_heat := 0.0
	var settled := false
	var settled2 := false
	for i in 400 * 60:
		await physics_frame
		if mission.step != "fire":
			break
		if mission.at_post(-1, "grill"):
			settled = true
		if settled and mission.heat >= mission.band.x:
			settled2 = true
		if settled2:
			min_heat = minf(min_heat, mission.heat)
			max_heat = maxf(max_heat, mission.heat)
	check(mission.step == "serve", "l'agneau est cuit sans le joueur")
	check(settled and min_heat > 0.3 and max_heat < 0.85, "Gégé tient le feu entre %.2f et %.2f" % [min_heat, max_heat])
	check(mission.burn == 0.0, "rien n'a brûlé")
	check(mission.dog_seq == 3 and mission.shooed >= 1, "trois chiens, %d chassés (dont Kévin), %d gigots perdus" % [mission.shooed, mission.stolen])

	# --- Service : Ginette sert les huit assiettes -----------------------------------------------------------------------------
	for i in 160 * 60:
		await physics_frame
		if mission.step != "serve":
			break
	check(mission.step == "bonfire", "le service est terminé")
	check(mission._total_served() == 8, "Ginette a servi les 8 assiettes (%d)" % mission._total_served())
	print("--- m04_companions : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
