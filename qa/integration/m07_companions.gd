extends SceneTree
## Test d'intégration des compagnons de la mission 07 (agent 09) : Ginette attend à la porte avec la clé (la porte s'ouvre
## sans fouille), Kévin occupe Mme Hubert (plus de causette forcée), Kévin Radio garde la file des toilettes (attente écourtée).
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m07_companions.gd -- --mission=m07

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
	var world = load(WORLD).instantiate()
	root.add_child(world)
	for i in 100:
		await physics_frame
	var m = world.mission
	var ginette = world.players_root.get_node_or_null("-2")
	var radio = world.players_root.get_node_or_null("-3")
	var kevin = world.players_root.get_node_or_null("-4")
	if not check(ginette != null and radio != null and kevin != null and world.players_root.get_node_or_null("-1") == null, "3 compagnons (Ginette, Kévin Radio, Kévin) ; Gégé reste au stand"):
		quit(1)
		return
	check(m.companion_roles() == {-2: "portier", -4: "diversion", -3: "file"}, "rôles : portier, diversion, file")
	var player = world.players_root.get_node("1")
	m.victims[1].p = 0.0
	# Les compagnons rejoignent leur poste (on arrête la pression pour que le joueur reste là où il est).
	var all := false
	for i in 200 * 60:
		await physics_frame
		m.victims[1].p = 0.1
		m._spasm_t = 9999.0
		if m.at_post(-2, "porte") and m.at_post(-4, "hubert") and m.at_post(-3, "wc"):
			all = true
			break
	check(all, "Ginette (%s), Kévin (%s) et Kévin Radio (%s) sont à leur poste" % [ginette.brain.status, kevin.brain.status, radio.brain.status])
	# Mme Hubert, distraite par Kévin : le joueur passe sans être retenu.
	var h: Vector3 = m.spot("hubert")
	player.global_position = h + Vector3(0.5, 0.6, 0.0)
	for i in 30:
		await physics_frame
		m.victims[1].p = 0.1
	check(m.victims[1].fz == "" and m.chat_done, "Kévin occupe Mme Hubert : pas de causette forcée")
	# La porte : Ginette l'ouvre sans fouille.
	player.global_position = m._front_point("door", 1.0) + Vector3(0, 0.6, 0)
	for i in 120:
		await physics_frame
		m.victims[1].p = 0.1
	check(m.door_open and m.resolve(1, player.global_position).kind == "enter", "Ginette a la clé : la porte s'ouvre toute seule")
	# La file : Kévin Radio la garde, l'attente est plus courte.
	var q = m.spot("wc")
	player.global_position = q + Vector3(0, 0.6, 0)
	await physics_frame
	m.interact(1, ["queue"])
	check(m.victims[1].fz == "queue" and absf(m.victims[1].ft - M7_QUEUE_FAST()) < 0.5, "file gardée par Kévin Radio : %.0f s au lieu de 15" % m.victims[1].ft)
	print("--- m07_companions : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)


func M7_QUEUE_FAST() -> float:
	return 7.0
