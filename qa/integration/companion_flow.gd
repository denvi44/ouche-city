extends SceneTree
## Test d'intégration du compagnon IA (agent 09) : le joueur ne fait rien, Tonton Gégé doit
## aller chercher des caisses et les charger dans la camionnette, sans rester bloqué.
## Usage : godot --headless --path game -s ../qa/integration/companion_flow.gd
## Paramètres (après --) : --sec=180 durée de jeu simulée ; --need=2 caisses attendues.

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
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var seconds := float(args.get("sec", 180))
	create_timer(seconds + 120.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	var need := int(args.get("need", 2))
	var world = load(WORLD).instantiate()
	root.add_child(world)
	for i in 40:
		await physics_frame
	var mission = world.mission
	var gege = world.players_root.get_node_or_null("-1")
	var player = world.players_root.get_node_or_null("1")
	if not (check(gege != null and gege.is_ai and gege.brain != null, "Tonton Gégé est un compagnon IA avec un cerveau")
			and check(player != null, "le joueur est là")):
		quit(1)
		return
	check(gege.model != null and gege.display_name.begins_with("Tonton"), "Gégé a un corps articulé et un nom")
	var nav = gege.brain.nav
	check(nav.point_count() > 500, "graphe routier chargé (%d points)" % nav.point_count())

	var frames_total := int(seconds * 60.0)
	var last_check_pos: Vector3 = gege.global_position
	var longest_still := 0.0
	var still := 0.0
	var loaded_at := {}
	var walked := 0.0
	var last: Vector3 = gege.global_position
	for f in frames_total:
		await physics_frame
		walked += Vector2(gege.global_position.x - last.x, gege.global_position.z - last.z).length()
		last = gege.global_position
		if f % 60 == 59:
			# Immobile en dehors des échanges (prise, chargement) ?
			var moved: float = Vector2(gege.global_position.x - last_check_pos.x, gege.global_position.z - last_check_pos.z).length()
			last_check_pos = gege.global_position
			still = still + 1.0 if moved < 0.3 else 0.0
			longest_still = maxf(longest_still, still)
			var n := 0
			for id in mission.crates:
				if mission.crates[id].state == "loaded":
					n += 1
					if not loaded_at.has(id):
						loaded_at[id] = f / 60.0
						print("  [%3d s] caisse %s chargée par Gégé (%d/4) — %s" % [f / 60, id, n, gege.brain.status])
			if n >= 4:
				break
	var loaded := 0
	for id in mission.crates:
		if mission.crates[id].state == "loaded":
			loaded += 1
	print("  Gégé a marché %.0f m ; état final : %s ; plus longue immobilité : %.0f s" % [walked, gege.brain.status, longest_still])
	check(loaded >= need, "au moins %d caisse(s) chargée(s) par Gégé (%d)" % [need, loaded])
	check(mission.cargo == loaded * mission.bottles_per_crate, "cargaison cohérente (%d bouteilles)" % mission.cargo)
	check(longest_still < 12.0, "jamais bloqué plus de 12 s (%.0f s)" % longest_still)
	check(not gege.carrying or mission.carried_by(-1) != "", "porteur cohérent avec l'état de la mission")
	# --- Les autres compagnons sont à leur poste ---------------------------------------------------------
	for entry in [[-2, "ginette", "Ginette"], [-3, "radio", "Kévin Radio"], [-4, "kevin", "Kévin"]]:
		var c = world.players_root.get_node_or_null(str(entry[0]))
		if check(c != null and c.is_ai and c.brain != null, "%s est un compagnon IA" % entry[2]):
			var spot: Vector3 = mission.spot(entry[1])
			var dist := Vector2(c.global_position.x - spot.x, c.global_position.z - spot.z).length()
			check(dist < 3.5, "%s est à son poste (%.1f m) — %s" % [entry[2], dist, c.brain.status])
	if loaded >= 4:
		check(mission.step == "road", "toutes les caisses chargées : étape route")
		check(gege.brain.status.begins_with("attend"), "Gégé attend près de la camionnette (ne monte pas)")
		check(mission.van.driver == 0, "la camionnette reste libre pour le joueur")
	if loaded >= 4:
		# --- Barrage avec Ginette et Kévin sur place -------------------------------------------------------
		var van = mission.van
		var to_barrage := func():
			mission.step = "road"
			mission.barrier_open = false
			van.global_position = mission.zones.barrage + Vector3(0, 0.6, 0) + van.forward() * -6.0
			van.velocity = Vector3.ZERO
			van.speed = 0.0
		var cargo0: int = mission.cargo
		to_barrage.call()
		for i in 10:
			await physics_frame
		check(mission.step == "checkpoint", "la camionnette arrive au barrage : choix d'équipe")
		check(mission._radio_flags.has("chargement") and mission._radio_flags.has("barrage"), "Kévin Radio commente la route (%d messages)" % mission._radio_flags.size())
		mission.test_roll = 0.5          # 0,5 < 0,9 : le bluff passe avec Ginette (il aurait raté à 50 % sans elle)
		mission.choose("bluff")
		check(mission.step == "fair" and mission.cargo == cargo0, "bluff avec Ginette sur place : ça passe")
		to_barrage.call()
		for i in 10:
			await physics_frame
		mission.choose("diversion")
		check(mission.step == "fair" and mission.cargo == cargo0, "diversion avec Kévin sur place : ça marche")
		to_barrage.call()
		for i in 10:
			await physics_frame
		mission.checkpoint_left = 0.01
		for i in 10:
			await physics_frame
		check(mission.step == "fair", "délai écoulé : Ginette prend la parole")
		var said := false
		for m in mission.messages:
			if "Ginette prend la parole" in m or "Ginette s'avance" in m:
				said = true
		check(said, "le journal consigne l'intervention de Ginette")
		mission.test_roll = -1.0
	print("[companion] %s" % ("ÉCHEC : %d vérification(s)" % fails if fails > 0 else "toutes les vérifications passent"))
	quit(1 if fails > 0 else 0)
