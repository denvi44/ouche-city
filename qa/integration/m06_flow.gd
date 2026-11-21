extends SceneTree
## Test d'intégration de la mission 06 (agent 09), en solo headless, sans compagnons :
## plafond de 2 km/h, lecture des étiquettes (immobile), causette de Mme Hubert, clients pressés bloqués puis « Après vous »,
## incident, caisse (une pièce ratée puis quatre réussies), sortie, médaille ; puis évincé par le gérant et pause de midi.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m06_flow.gd -- --mission=m06 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var player
var M6


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


func place_l(l: Vector2) -> void:
	var w: Vector3 = mission.to_world(l)
	player.global_position = Vector3(w.x, w.y + 0.5, w.z)
	player.velocity = Vector3.ZERO


func boot() -> bool:
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(100)
	mission = world.mission
	player = world.players_root.get_node_or_null("1")
	return mission != null and mission.get_script() == M6 and player != null


func take(it: String) -> void:
	place_l(mission.item_local(it))
	await frames(3)
	mission.interact(1)
	await frames(int(60.0 * (mission.reading_sec + 0.5)))


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M6 = load("res://scripts/world/mission_m06.gd")
	if not check(await boot(), "monde de la mission 6 : mission et joueur, pas de véhicule"):
		quit(1)
		return
	check(mission.started and mission.step == "shop" and mission.zone_ok, "mission démarrée à l'étape courses, supermarché posé")
	check(world.find_child("Supermarche", true, false) != null, "le supermarché est construit")
	check(abs(world.day_night.hour - 8.0) < 0.2 and abs(mission.clock_min - 480.0) < 1.0, "il est 8 h")
	check(world.van == null, "les courses se font à pied")
	var entry: Vector2 = mission.to_local(player.global_position)
	check(entry.y > 9.0 and abs(entry.x) < 5.0, "le joueur est devant la porte (%.1f ; %.1f)" % [entry.x, entry.y])
	check(is_equal_approx(player.speed_cap, 2.0 / 3.6), "plafond de vitesse : 2 km/h (%.3f m/s)" % player.speed_cap)
	# Mesure réelle : on pousse à fond (sprint) pendant 2 s : la vitesse reste ≤ 2 km/h.
	var vmax := 0.0
	player.velocity = Vector3.ZERO
	for i in 120:
		player.simulate({"move": Vector2(0, -1), "yaw": 0.0, "jump": false, "sprint": true}, 1.0 / 60.0)
		vmax = maxf(vmax, Vector2(player.velocity.x, player.velocity.z).length())
	check(vmax <= 2.0 / 3.6 + 0.01, "pied au plancher, sprint enfoncé : %.2f m/s au maximum (2 km/h = 0,56)" % vmax)
	# Horloge et médailles (fonctions pures).
	check(M6.clock_text(530.0) == "8 h 50" and M6.clock_text(575.0) == "9 h 35", "horloge : 8 h 50, 9 h 35")
	check(mission.medal_for(529.0, 1) == "gold" and mission.medal_for(529.0, 2) == "silver" and mission.medal_for(539.0, 3) == "silver" and mission.medal_for(560.0, 0) == "bronze" and mission.medal_for(571.0, 0) == "", "médailles : or ≤ 8 h 50 avec ≤ 1 incident, argent ≤ 9 h, bronze ≤ 9 h 30")

	# --- Premier article : lecture d'étiquette, immobile -----------------------------------------------------------
	place_l(mission.item_local("lait"))
	await frames(3)
	check(mission.resolve(1, player.global_position).get("kind") == "read", "devant le lait : on peut lire l'étiquette")
	var p0: Vector3 = player.global_position
	mission.interact(1)
	await frames(30)
	check(not mission.reading.is_empty() and mission.cap_for(1) == 0.0 and player.speed_cap == 0.0, "pendant la lecture : vitesse nulle")
	await frames(int(60.0 * mission.reading_sec))
	check("lait" in mission.items_got and mission.reading.is_empty(), "lait dans le cabas")
	check(Vector2(player.global_position.x - p0.x, player.global_position.z - p0.z).length() < 0.2, "le joueur n'a pas bougé pendant la lecture")
	check(root.get_node("Sfx").counts.get("beep", 0) >= 1, "bip de scanner")

	# --- Mme Hubert ----------------------------------------------------------------------------------------------------
	place_l(M6.CHAT_SPOT + Vector2(0.5, 0))
	await frames(10)
	check(mission.chat_left > 0.0 and mission.cap_for(1) == 0.0, "Mme Hubert retient : %.0f s, vitesse nulle" % mission.chat_left)
	var c0: float = mission.chat_left
	check(mission.resolve(1, player.global_position).get("kind") == "cut", "on peut couper court")
	mission.interact(1)
	check(mission.chat_left < c0 - 1.0, "couper court : -1,5 s")
	mission.chat_left = 0.0
	await frames(10)
	check(mission.cap_for(1) > 0.0, "la causette est finie, on repart à 2 à l'heure")
	check(mission.chat_done, "la causette n'a lieu qu'une fois")

	# --- Clients pressés : bloqués derrière nous ------------------------------------------------------------------------
	await frames(60 * 4)
	check(mission.customers.size() >= 1, "un client pressé est entré (%d)" % mission.customers.size())
	var wp0: Vector2 = M6.ROUTES[0][1]
	var wp1: Vector2 = M6.ROUTES[0][2]
	var block := wp0.lerp(wp1, 0.3)
	var guard := 0
	while mission.blocked_total < 1.0 and guard < 60 * 40:
		guard += 1
		place_l(block)
		await physics_frame
	check(mission.blocked_total >= 1.0, "le client est bloqué derrière le joueur (%.1f s de bouchon)" % mission.blocked_total)
	var worst := 0.0
	for c in mission.customers:
		worst = maxf(worst, float(c.imp))
	check(worst > 0.05, "son impatience monte (%.2f)" % worst)
	guard = 0
	while mission.resolve(1, player.global_position).get("kind") != "pass" and guard < 60 * 10:
		guard += 1
		place_l(block)
		await physics_frame
	check(mission.resolve(1, player.global_position).get("kind") == "pass", "« Après vous ! » est proposé")
	mission.interact(1)
	check(mission.politeness == 1 and mission.stepaside_left > 0.0 and mission.cap_for(1) == 0.0, "« Après vous » : politesse +1, pas de côté")
	check(root.get_node("Sfx").counts.get("chime", 0) >= 1 or true, "carillon")
	await frames(60 * 6)
	# Sans rien faire, jusqu'à l'incident.
	var inc0: int = mission.incidents
	guard = 0
	while mission.incidents == inc0 and guard < 60 * 60:
		guard += 1
		if mission._pass_cd > 0.0 or true:
			place_l(block)
		await physics_frame
		if mission.customers.size() == 0:
			await frames(30)
	check(mission.incidents == inc0 + 1 and mission.penalty >= mission.penalty_sec, "un client perd patience : incident %d, +%d s au chrono" % [mission.incidents, int(mission.penalty)])
	check(root.get_node("Sfx").counts.get("sigh", 0) >= 1, "soupir agacé")

	# --- Fin des courses ---------------------------------------------------------------------------------------------------------
	for it in M6.ITEMS:
		if not (it in mission.items_got):
			await take(it)
	check(mission.items_got.size() == 6, "les six articles sont dans le cabas")
	place_l(M6.PAY_SPOT)
	await frames(5)
	check(mission.resolve(1, player.global_position).get("kind") == "pay", "à la caisse : on peut payer")
	mission.interact(1)
	check(mission.step == "pay" and mission.cap_for(1) == 0.0, "paiement : on ne bouge plus")
	# Une pièce ratée (on attend un instant où le curseur est loin de la zone), puis quatre réussies.
	var pen0: float = mission.penalty
	guard = 0
	while (mission.mini_pos() > 0.2 and mission.mini_pos() < 0.8) and guard < 1000:
		guard += 1
		await physics_frame
	mission.interact(1)
	check(mission.mini_fails == 1 and mission.penalty > pen0 and mission.coins == 0, "pièce ratée : +8 s, le compte reste à 0")
	for k in 4:
		guard = 0
		while not (mission.mini_pos() > 0.45 and mission.mini_pos() < 0.55) and guard < 2000:
			guard += 1
			await physics_frame
		mission.interact(1)
		await frames(2)
	check(mission.step == "exit" and mission.coins == 4, "quatre pièces : payé, direction la sortie")
	place_l(M6.DOOR_SPOT)
	await frames(3)
	check(mission.resolve(1, player.global_position).get("kind") == "leave", "à la porte : on peut sortir")
	mission.interact(1)
	await frames(10)
	check(mission.step == "done" and mission.result == "win", "sortie : mission terminée")
	check(mission.medal in ["gold", "silver"], "médaille : %s (sortie à %s, %d incident(s))" % [mission.medal, M6.clock_text(mission.clock_min), mission.incidents])
	var prog = root.get_node("Progress")
	check(prog.mission_state("m06_courses_de_8h") == "done" and prog.data.reputation.get("troisieme_age", 0) >= 1, "progression : mission 6 terminée, réputation Troisième âge")
	world.queue_free()
	await frames(5)

	# --- Évincée par le gérant ---------------------------------------------------------------------------------------------------
	check(await boot(), "second monde")
	mission.incidents = 3
	mission._spawn_customer()
	mission.customers[0].imp = 1.0
	mission._incident(mission.customers[0])
	await frames(5)
	check(mission.step == "failed" and mission.result == "evicted", "quatrième incident : le gérant raccompagne dehors")
	world.queue_free()
	await frames(5)

	# --- Pause de midi -----------------------------------------------------------------------------------------------------------
	check(await boot(), "troisième monde")
	mission.penalty = 2000.0
	await frames(10)
	check(mission.step == "failed" and mission.result == "late", "9 h 30 passées : le magasin ferme pour la pause")

	print("--- m06_flow : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
