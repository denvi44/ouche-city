extends SceneTree
## Test d'intégration de la mission 02 (agent 09), en solo headless, sans compagnons :
## marchandage → boutique → casse (furtif) → vol chez Dylan → montage → essai routier (radar) → jury → drag.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m02_flow.gd -- --mission=m02 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var car
var player
var M2
var CarS


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


func place(node, pos: Vector3) -> void:
	node.global_position = pos
	node.velocity = Vector3.ZERO


func near_zone(zone: String, dx := 1.5, dz := 1.0) -> Vector3:
	return mission.zones[zone] + Vector3(dx, 0.6, dz)


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M2 = load("res://scripts/world/mission_m02.gd")
	CarS = load("res://scripts/player/car.gd")
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	mission = world.mission
	car = world.van
	player = world.players_root.get_node_or_null("1")
	if not check(mission.get_script() == M2 and car.get_script() == CarS and player != null, "monde de la mission 2 : mission, Fusée et joueur"):
		quit(1)
		return
	await frames(60)
	check(mission.started and mission.step == "parts", "mission démarrée à l'étape pièces")
	check(mission.budget == 400 and mission.required_parts == 3, "budget 400 € (solo), 3 pièces à trouver")
	check(abs(world.day_night.hour - 15.0) < 0.1, "il est 15 h")
	for z in ["garage", "casse", "annonce", "shop", "dylan", "car_spawn", "meet", "start", "finish"]:
		check(mission.zones.has(z), "lieu posé : %s" % z)
	check(mission.dylan != null and mission.guard != null, "Dylan et le gardien de la casse existent")

	# --- Annonce : marchandage -----------------------------------------------------------------------
	place(player, near_zone("annonce"))
	check(mission.resolve(1, player.global_position).get("kind") == "haggle", "annonce : marchandage possible")
	mission.interact(1)
	check(mission.menu == "haggle" and mission.menu_options.size() == 3, "menu de marchandage à 3 offres")
	mission.test_roll = 0.99
	mission.choose_for(1, "2")
	check(mission.parts.is_empty() and mission.budget == 400 and mission._haggle_cd > 5.0, "offre refusée : rien acheté, délai avant de réessayer")
	check(mission.resolve(1, player.global_position).get("kind") != "haggle", "pendant le délai, plus de marchandage")
	mission._haggle_cd = 0.0
	mission.interact(1)
	mission.test_roll = 0.1
	mission.choose_for(1, "2")
	check("pot" in mission.parts and mission.budget == 400 - 72 and mission.sources.annonce, "offre acceptée : pot à 72 € (60 % de 120)")
	check(mission.resolve(1, player.global_position).get("kind") != "haggle", "annonce épuisée")
	mission.test_roll = -1.0

	# --- Boutique Auto Bling 27 (prix ×1,5) --------------------------------------------------------------
	place(player, near_zone("shop"))
	check(mission.resolve(1, player.global_position).get("kind") == "shop", "boutique : achat possible")
	mission.interact(1)
	check(mission.menu == "shop" and mission.menu_options.size() == 5, "menu de la boutique : 5 pièces")
	var b0: int = mission.budget
	mission.budget = 10
	mission.choose_for(1, "2")
	check(not ("pot" in mission.parts and mission.parts.count("pot") > 1) and mission.budget == 10, "fonds insuffisants : achat refusé")
	mission.budget = b0
	mission.interact(1)
	mission.choose_for(1, "5")
	check("aileron" in mission.parts and mission.budget == b0 - 120, "aileron acheté 120 € (80 × 1,5)")
	check(mission.price_of("caisson", true) == 150 and mission.price_of("caisson") == 100, "prix boutique = ×1,5")

	# --- Casse : fouille furtive ------------------------------------------------------------------------------
	var g = mission.guard
	g._wait = 1000.0
	place(g, mission.zones.casse + Vector3(90, 0.5, 90))
	place(player, near_zone("casse", 2.0, 1.0))
	await frames(5)
	check(mission.resolve(1, player.global_position).get("kind") == "search", "casse : fouille possible")
	mission.interact(1)
	check(mission.search_progress >= 0.0, "fouille commencée")
	await frames(400)
	check("jantes" in mission.parts and mission.sources.casse, "fouille réussie sans être vu : jantes")
	# Même fouille, gardien qui regarde droit vers nous : repéré.
	mission.parts.erase("jantes")
	mission.sources.casse = false
	mission._search_cd = 0.0
	place(g, player.global_position + Vector3(0, 0, 6.0))
	g.yaw = 0.0
	g.rotation.y = 0.0                   # regarde vers -Z, donc vers le joueur
	await frames(5)
	check(g.can_see(player.global_position), "le gardien voit le joueur à 6 m, de face")
	mission.interact(1)
	await frames(30)
	check(mission.search_progress < 0.0 and mission._search_cd > 3.0 and mission.messages[-1].contains("repéré"), "gardien : fouille interrompue, « vous a repéré »")
	g.yaw = PI
	g.rotation.y = PI                     # tourne le dos
	check(not g.can_see(player.global_position), "le gardien ne voit pas quelqu'un dans son dos")
	place(g, mission.zones.casse + Vector3(90, 0.5, 90))
	mission.parts.append("jantes")
	mission.sources.casse = true

	# --- Cour de Dylan : vol ---------------------------------------------------------------------------------------
	place(player, near_zone("dylan", 2.0, 1.0))
	check(mission.resolve(1, player.global_position).get("kind") == "steal", "cour de Dylan : on peut voler")
	var money_before: int = mission.budget
	mission.interact(1)
	check("neons" in mission.parts and mission.wanted == 1 and "dylan_recognizes_parts" in mission.flags and mission.budget == money_before, "néons volés : gratuit, recherché 1, Dylan reconnaît les pièces")

	# --- Garage : montage en mini-jeux ----------------------------------------------------------------------------
	check(mission.parts.size() == 4, "4 pièces : jantes, pot, aileron, néons")
	place(player, near_zone("garage", 2.0, 1.0))
	check(mission.resolve(1, player.global_position).get("kind") == "assemble", "garage : montage possible (≥ 3 pièces)")
	mission.interact(1)
	check(mission.step == "assembly" and mission.assembly_total == 4, "montage de 4 pièces")
	check(absf(mission.mini_pos() - 0.5) < 0.01, "curseur du mini-jeu au centre au départ")
	for i in 3:
		mission.mini_t = 0.0                       # curseur au centre : dans la zone
		mission.interact(1)
	check(mission.assembly_idx == 3 and mission.mini_fails == 0, "3 pièces montées sans raté")
	mission.mini_t = (PI / 2.0) / mission.MINI_SPEED   # curseur au bout : hors zone
	check(mission.mini_pos() > 0.95, "curseur hors zone")
	mission.interact(1)
	check(mission.step == "test_drive" and mission.mini_fails == 1, "4e pièce ratée : −1 au jury, montage fini")
	check(car.has_part("pot") and car.has_part("jantes") and car.has_part("aileron") and car.has_part("neons") and not car.has_part("caisson"), "la Fusée porte ses 4 pièces")
	check(car.accel > CarS.BASE_ACCEL and car.max_speed > CarS.BASE_MAX_SPEED, "le pot améliore l'accélération et la vitesse (%.1f / %.1f)" % [car.accel, car.max_speed])
	check(car._part_nodes.pot.visible and car._part_nodes.aileron.visible and car._part_nodes.neons.visible and not car._part_nodes.caisson.visible, "accessoires visibles selon les pièces")

	# --- Essai routier : radar, contrôles ---------------------------------------------------------------------------
	check(mission.td_points.size() == 4 and mission.cp_total == 4, "essai : 3 contrôles + le rendez-vous")
	place(player, car.global_position + car.global_transform.basis.x * 2.4)
	check(mission.resolve(1, player.global_position).get("kind") == "enter", "on peut monter dans la Fusée")
	mission.interact(1)
	await frames(3)
	check(car.driver == 1 and player.is_driving(), "joueur au volant de la Fusée")
	car.forced_input = {"move": Vector2.ZERO, "jump": true}
	var ground := func(p: Vector2) -> Vector3: return Vector3(p.x, world.builder.height_at(p.x, p.y) + 0.6, p.y)
	var budget0: int = mission.budget
	# Radar : lent = rien, vite = amende.
	place(car, ground.call(mission.td_radar))
	car.speed = 8.0
	await frames(3)
	check(not mission.flashed and mission.budget == budget0, "radar : 29 km/h, pas d'amende")
	place(car, ground.call(mission.td_radar))
	car.speed = 20.0
	await frames(3)
	check(mission.flashed and mission.budget == budget0 - 30, "radar : 72 km/h, FLASH, amende de 30 €")
	for i in 3:
		place(car, ground.call(mission.td_points[i]))
		car.speed = 5.0
		await frames(3)
	check(mission.cp_index == 3, "3 points de contrôle franchis")
	place(car, ground.call(mission.td_points[3]))
	car.speed = 0.0
	await frames(5)
	check(mission.step == "drag", "arrivée au rendez-vous : jury, puis drag")
	check(mission.jury.look == 10 and mission.jury.son == 6 and mission.jury.presence == 5, "notes : look 10, son 6, présence 5 (%s)" % str(mission.jury))
	check(mission.jury.total == 5, "note finale 5 : moyenne 7, −1 raté, −1 Dylan reconnaît ses néons")
	var pure = M2.jury_scores(["jantes", "neons", "aileron", "pot", "caisson"], true, false, true, 0, false, 1, 10)
	check(pure.total == 10 and pure.look == 10 and pure.son == 10 and pure.presence == 10, "jury : voiture parfaite avec Gégé, note 10/10")
	var nul = M2.jury_scores([], false, true, false, 3, true, 1, 10)
	check(nul.total == 0 and nul.look == 2 and nul.son == 2 and nul.presence == 3, "jury : voiture nue, notes basses et plancher à 0")

	# --- Drag : 400 m ------------------------------------------------------------------------------------------------------------
	var start2 := Vector2(mission.zones.start.x, mission.zones.start.z)
	place(car, ground.call(start2 - mission.strip_dir * 20.0))
	car.speed = 0.0
	await frames(3)
	check(mission.resolve(1, player.global_position).get("kind") == "start_race", "sur la grille : départ possible")
	mission.interact(1)
	check(mission.race_state == "countdown" and car.hold and mission.dylan.hold, "compte à rebours : les deux voitures retenues")
	var lane_gap := Vector2(car.global_position.x - mission.dylan.global_position.x, car.global_position.z - mission.dylan.global_position.z).length()
	check(abs(lane_gap - 5.0) < 0.3, "les voitures sont côte à côte, à 5 m d'écart")
	car.forced_input = {"move": Vector2(0, -1), "jump": false}
	await frames(60)
	check(car.speed < 0.5 and mission.race_state == "countdown", "faux départ impossible : la Fusée reste immobile")
	await frames(140)
	check(mission.race_state == "go" and not car.hold, "PARTEZ !")
	var boosted := false
	var guard_t := 0
	while mission.race_state == "go" and guard_t < 3600:
		await frames(1)
		guard_t += 1
		if not boosted and car.speed >= 0.6 * car.max_speed:
			boosted = true
			mission.boost(1)
	check(boosted and mission.boosts_left == 0, "turbo lancé une fois, moteur lancé")
	check(mission.race_state == "finished" and mission.step == "done", "course terminée (%.1f s)" % mission.race_time)
	check(mission.result == "win" and mission.race_sd < mission.race_sp, "VICTOIRE contre Dylan (vous %d m, lui %d m)" % [int(mission.race_sp), int(mission.race_sd)])
	check(mission.medal == "silver", "médaille d'argent : victoire, jury 5 < 8")
	var prog = root.get_node("Progress")
	check(prog.is_done("m02_tuning_samedi") and prog.medal_of("m02_tuning_samedi") == "silver", "progression : mission 2 terminée, argent")
	check("fusee_kevin" in prog.data.vehicles, "récompense : la Fusée de Kévin débloquée")
	check(prog.money() == mission.budget and mission.budget < 400, "l'argent restant est conservé (%d €)" % prog.money())
	check("m03_battle_sono" in prog.data.unlocks and prog.data.reputation.get("jeunesse", 0) == 1, "mission 3 débloquée, réputation Jeunesse +1")

	# --- Seconde course : turbo trop tôt = moteur cassé = défaite --------------------------------------------------------------------
	mission.step = "drag"
	mission.race_state = "idle"
	car.forced_input = {"move": Vector2(0, -1), "jump": false}
	place(car, ground.call(start2 - mission.strip_dir * 20.0))
	car.speed = 0.0
	mission.interact(1)
	await frames(200)
	check(mission.race_state == "go", "seconde course lancée")
	await frames(40)
	mission.boost(1)
	check(car.engine_broken and not car.boosting, "turbo à %d km/h : trop tôt, moteur cassé" % int(car.speed * 3.6))
	guard_t = 0
	while mission.race_state == "go" and guard_t < 4200:
		await frames(1)
		guard_t += 1
	check(mission.result == "lose" and mission.medal == "bronze", "moteur cassé : Dylan gagne, médaille de bronze (présentée)")
	check(prog.medal_of("m02_tuning_samedi") == "silver", "la meilleure médaille (argent) est conservée")

	# --- Délai de 21 h ---------------------------------------------------------------------------------------------------------------------------
	mission.step = "assembly"
	world.day_night.hour = 21.2
	await frames(3)
	check(mission.step == "failed", "21 h passées avant le drag : samedi soir raté")

	var sfx = root.get_node("Sfx")
	check(sfx.counts.get("chime", 0) >= 3 and sfx.counts.get("thud", 0) >= 1 and sfx.counts.get("radio_blip", 0) >= 1 and sfx.counts.get("klaxon", 0) >= 1, "sons : carillons, raté, radar et départ (%s)" % str(sfx.counts))
	print("[m02] %s" % ("ÉCHEC : %d vérification(s)" % fails if fails > 0 else "toutes les vérifications passent"))
	quit(1 if fails > 0 else 0)
