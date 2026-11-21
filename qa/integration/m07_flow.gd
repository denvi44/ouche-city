extends SceneTree
## Test d'intégration de la mission 07 (agent 09), en solo headless, sans compagnons :
## pression (au pas, en courant, serrée, sur les pavés), crampes, endurance, causette de Mme Hubert, chien, toilettes publiques,
## porte fermée (clé sous le pot), arrivée chez soi (or / argent), accident, temps écoulé.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m07_flow.gd -- --mission=m07 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var player
var M7


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


func place(pos: Vector3) -> void:
	player.global_position = pos + Vector3(0, 0.6, 0)
	player.velocity = Vector3.ZERO


func boot() -> bool:
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(100)
	mission = world.mission
	player = world.players_root.get_node_or_null("1")
	return mission != null and mission.get_script() == M7 and player != null


## Pression gagnée en `sec` secondes à une vitesse imposée, sans crampes ni événements.
func gain(speed: float, clench: bool, sec: float, at: Vector3) -> float:
	mission.victims[1].p = 0.1
	mission.victims[1].cl = clench
	mission.victims[1].st = 1.0
	mission.test_speed[1] = speed
	mission._spasm_t = 9999.0
	place(at)
	var p0: float = mission.victims[1].p
	await frames(int(60.0 * sec))
	return float(mission.victims[1].p) - p0


func _run() -> void:
	create_timer(600.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M7 = load("res://scripts/world/mission_m07.gd")
	if not check(await boot(), "monde de la mission 7 : mission et joueur, pas de véhicule"):
		quit(1)
		return
	check(mission.started and mission.step == "run" and mission.victims.has(1), "mission démarrée, le joueur a sa pression")
	check(abs(world.day_night.hour - 16.0) < 0.2, "il est 16 h")
	for z in ["stand", "wc", "door"]:
		check(mission.zones.has(z), "lieu posé : %s" % z)
	check(mission.route.size() >= 2 and mission.route_len > 150.0 and mission.route_len < 600.0, "trajet du stand à la porte : %.0f m" % mission.route_len)
	for nm in ["GegeStand", "MmeHubert", "ChienDuPortail", "PotDeFleurs", "File_0"]:
		check(world.find_child(nm, true, false) != null, "décor : %s" % nm)
	check(world.find_child("Supermarche", true, false) == null, "pas de supermarché dans cette mission")
	var near_stand: Vector2 = Vector2(player.global_position.x - mission.zones.stand.x, player.global_position.z - mission.zones.stand.z)
	check(near_stand.length() < 6.0, "le joueur démarre au stand (%.1f m)" % near_stand.length())
	check(absf(mission.victims[1].p - M7.START_PRESSURE) < 0.05, "pression de départ : %d %%" % int(M7.START_PRESSURE * 100.0))

	# --- Fonctions pures et rythmes de montée ---------------------------------------------------------------------------------------------
	check(M7.pressure_rate(0.0, false, false) < M7.pressure_rate(4.0, false, false) and M7.pressure_rate(4.0, false, false) < M7.pressure_rate(7.0, false, false), "la pression monte plus vite en marchant puis en courant")
	check(M7.pressure_rate(4.0, true, false) < M7.pressure_rate(4.0, false, false) * 0.5, "serrer divise la montée par plus de deux")
	check(M7.pressure_rate(4.0, false, true) > M7.pressure_rate(4.0, false, false), "les pavés secouent")
	check(mission.medal_for(0.7, true) == "gold" and mission.medal_for(0.71, true) == "silver" and mission.medal_for(0.2, false) == "bronze", "médailles : or ≤ 70 %, argent, bronze aux toilettes publiques")
	var far: Vector3 = mission.route_point(0.0)
	var g_walk: float = await gain(4.2, false, 6.0, far)
	var g_run: float = await gain(7.5, false, 6.0, far)
	var g_clench: float = await gain(2.0, true, 6.0, far)
	var g_idle: float = await gain(0.0, false, 6.0, far)
	check(g_run > g_walk and g_walk > g_clench and g_walk > g_idle, "mesure : arrêt %.3f, serré %.3f, pas %.3f, course %.3f en 6 s" % [g_idle, g_clench, g_walk, g_run])
	var cobb: Vector3 = mission.spot("cobbles")
	var g_cob: float = await gain(4.2, false, 6.0, cobb)
	check(g_cob > g_walk, "sur les pavés : %.3f contre %.3f" % [g_cob, g_walk])

	# --- Serrer : bascule, marche de crabe, endurance -----------------------------------------------------------------------------------------
	mission.victims[1].p = 0.1
	mission.victims[1].cl = false
	mission.test_speed.clear()
	place(far)
	await frames(3)
	check(mission.resolve(1, player.global_position).get("kind") == "clench", "E : serrer les fesses")
	mission.interact(1)
	check(mission.victims[1].cl and mission.cap_for(1) == M7.CLENCH_SPEED, "serré : marche de crabe à 2 m/s")
	await frames(2)
	check(is_equal_approx(player.speed_cap, 2.0), "le plafond de vitesse du joueur suit (%.1f)" % player.speed_cap)
	mission.interact(1)
	check(not mission.victims[1].cl and mission.cap_for(1) == INF, "E de nouveau : relâché")
	mission.interact(1)
	mission.victims[1].st = 0.01
	mission.victims[1].p = 0.2
	await frames(30)
	check(not mission.victims[1].cl and mission.victims[1].rel > 0.0, "endurance épuisée : les muscles lâchent, impossible de serrer %.0f s" % mission.victims[1].rel)
	check(mission.victims[1].p > 0.2 + M7.RELEASE_SPIKE - 0.01, "…et la pression fait un bond")
	check(mission.resolve(1, player.global_position).label.begins_with("Vous ne tenez plus"), "le libellé le dit")
	await frames(60 * 4)
	check(mission.victims[1].rel == 0.0 and mission.victims[1].st > 0.0, "l'endurance revient")

	# --- Crampe -------------------------------------------------------------------------------------------------------------------------------------
	var sp0: int = mission.spasms
	var p0: float = mission.victims[1].p
	mission.victims[1].cl = false
	mission._spasm_t = 0.01
	await frames(5)
	check(mission.spasms == sp0 + 1 and mission.victims[1].p >= p0 + M7.SPASM_PRESSURE - 0.01, "crampe : +%d %%" % int(M7.SPASM_PRESSURE * 100.0))
	await frames(5)
	check(root.get_node("Sfx").counts.get("gurgle", 0) >= 1 and "GRRRBLOUP !" in root.get_node("Sfx").onoma_log, "gargouillis et onomatopée « GRRRBLOUP ! »")
	check(world.get_node("Dialogues").said_ids.has("m07_intro_01"), "dialogue d'introduction (Gégé et son jus « un peu vif »)")
	mission._spasm_t = 9999.0

	# --- Mme Hubert -------------------------------------------------------------------------------------------------------------------------------------
	mission.victims[1].p = 0.2
	place(mission.spot("hubert"))
	await frames(5)
	check(mission.victims[1].fz == "chat" and mission.cap_for(1) == 0.0 and mission.chat_done, "Mme Hubert retient : vitesse nulle")
	check(mission.resolve(1, player.global_position).kind == "cut", "on peut couper court")
	mission.interact(1)
	await frames(60 * 8)
	check(mission.victims[1].fz == "", "la causette s'achève")

	# --- Le chien -----------------------------------------------------------------------------------------------------------------------------------------
	mission.victims[1].p = 0.2
	place(mission.spot("dog"))
	await frames(5)
	check(mission.dog_done and mission.victims[1].p >= 0.2 + M7.DOG_SCARE - 0.02, "chien du portail : sursaut +%d %%" % int(M7.DOG_SCARE * 100.0))

	# --- Porte fermée : chercher la clé, puis entrer (or) ----------------------------------------------------------------------------------------------
	mission.victims[1].p = 0.5
	var door: Vector3 = mission._front_point("door", 1.0)
	place(door)
	await frames(5)
	check(mission.resolve(1, player.global_position).kind == "search", "porte fermée à clé : fouiller le pot de fleurs")
	mission.interact(1)
	check(mission.victims[1].fz == "search" and mission.cap_for(1) == 0.0, "recherche : vitesse nulle")
	await frames(int(60.0 * (M7.SEARCH_TIME + 1.0)))
	check(mission.door_open and mission.victims[1].fz == "", "la clé était sous le pot : porte ouverte")
	var p_before: float = mission.victims[1].p
	check(mission.resolve(1, player.global_position).kind == "enter", "entrer chez soi")
	mission.interact(1)
	await frames(10)
	check(mission.step == "done" and mission.result == "home", "chez soi : mission terminée")
	check(mission.medal in ["gold", "silver"] and (mission.medal == "gold") == (p_before <= M7.GOLD_PRESSURE), "médaille selon la pression à l'arrivée : %s (%d %%)" % [mission.medal, int(p_before * 100.0)])
	check(root.get_node("Progress").mission_state("m07_jus_de_pomme") == "done", "progression : mission 7 terminée")
	world.queue_free()
	await frames(5)

	# --- Toilettes publiques (bronze) -----------------------------------------------------------------------------------------------------------------
	check(await boot(), "second monde")
	mission.victims[1].p = 0.8
	mission._spasm_t = 9999.0
	place(mission.spot("wc"))
	await frames(5)
	check(mission.resolve(1, player.global_position).kind == "queue", "toilettes publiques : faire la queue")
	mission.interact(1)
	check(mission.victims[1].fz == "queue" and mission.cap_for(1) == 0.0, "la file : on ne bouge plus")
	await frames(int(60.0 * (M7.QUEUE_TIME + 1.5)))
	check(mission.step == "done" and mission.result == "wc" and mission.medal == "bronze", "soulagé au public : médaille de bronze")
	check(mission.best_pressure < 0.8, "la pression est retombée (%d %%)" % int(mission.best_pressure * 100.0))
	world.queue_free()
	await frames(5)

	# --- Accident ----------------------------------------------------------------------------------------------------------------------------------------------
	check(await boot(), "troisième monde")
	mission._spasm_t = 9999.0
	mission.victims[1].p = 0.995
	mission.test_speed[1] = 7.5
	await frames(60)
	check(mission.step == "failed" and mission.result == "accident", "pression à 100 % : accident")
	check("PRRRRT !" in mission.result_text() or mission.result_text() == "PRRRRT !", "texte final : « PRRRRT ! »")
	world.queue_free()
	await frames(5)

	# --- Temps écoulé ---------------------------------------------------------------------------------------------------------------------------------------------
	check(await boot(), "quatrième monde")
	mission._spasm_t = 9999.0
	mission.time_left = 0.3
	await frames(40)
	check(mission.step == "failed" and mission.result == "late", "temps écoulé : trop tard")

	print("--- m07_flow : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
