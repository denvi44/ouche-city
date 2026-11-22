extends SceneTree
## Test d'intégration de la mission 09 « Le siège des Bretons » (en solo headless, sans compagnons) :
## étals, catapulte et débarquement posés ; prise et chargement des camemberts ; flaques de beurre (vitesse limitée) ; dixième camembert -> tir,
## puis fin (médaille d'or) ; temps écoulé -> village englouti ; médaille selon la part de village restante.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m09_flow.gd -- --mission=m09 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var player
var M9


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
	await frames(90)
	mission = world.mission
	player = world.players_root.get_node_or_null("1")
	return mission != null and mission.get_script() == M9 and player != null


## Un aller-retour : prendre au premier étal, charger à la catapulte.
func carry_one() -> void:
	place(mission.stocks[0])
	await frames(2)
	mission.interact(1)
	await frames(2)
	place(mission.zones.catapult + Basis(Vector3.UP, mission.facing_catapult) * Vector3(0, 0, -3.0))
	await frames(2)
	mission.interact(1)
	await frames(2)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M9 = load("res://scripts/world/mission_m09.gd")
	if not check(await boot(), "monde de la mission 9 : mission et joueur, pas de véhicule"):
		quit(1)
		return
	check(mission.started and mission.step == "defend", "mission démarrée à l'étape « defend »")
	check(abs(world.day_night.hour - 18.6) < 0.1, "il est 18 h 36 (ciel sombre)")
	check(world.van == null, "la mission se joue à pied")
	check(mission.stocks.size() == 3 and mission.zones.catapult != Vector3.ZERO and mission.zones.landing != Vector3.ZERO, "catapulte, trois étals et débarquement posés")
	check(mission.targets.size() >= 3, "façades visées par le beurre (%d)" % mission.targets.size())
	check(mission.zones.catapult.distance_to(mission.zones.landing) > 100.0, "les Bretons débarquent loin de la catapulte")
	check(world.find_child("Lieu_catapulte", true, false) != null and world.find_child("Bras", true, false) != null, "la catapulte et son bras sont dans le décor")
	check(mission.needed == 10, "dix camemberts à charger")
	# --- Fonctions pures : déterminisme du beurre, des flaques, des Bretons --------------------------------------------------------------
	check(M9.rnd(5, 2) == M9.rnd(5, 2) and M9.rnd(5, 2) != M9.rnd(6, 2) and M9.rnd(3, 1) >= 0.0 and M9.rnd(3, 1) < 1.0, "hasard stable (identique chez tous les pairs)")
	check(M9.last_shot(2.0, 2.4) == -1 and M9.last_shot(M9.shot_time(4, 2.4), 2.4) == 4, "calendrier des tirs de beurre")
	var s_a: Vector3 = M9.shot_target(7, mission.targets)
	check(s_a == M9.shot_target(7, mission.targets), "cible du beurre déterministe")
	var sl: Array = M9.slicks_active(20.0, 11.0, mission.stocks, mission.zones.catapult)
	check(sl.size() >= 1 and sl.size() <= 3, "des flaques de beurre à t = 20 s (%d)" % sl.size())
	check(M9.cap_at(sl[0].center, 20.0, 11.0, mission.stocks, mission.zones.catapult) == M9.SLICK_CAP, "dans une flaque : vitesse limitée")
	check(M9.cap_at(mission.zones.landing, 20.0, 11.0, mission.stocks, mission.zones.catapult) == INF, "hors flaque : pas de limite")
	check(M9.arm_angle(0.0) == M9.ARM_REST and M9.arm_angle(M9.ARM_T0 + M9.ARM_SWING) > 150.0, "bras de la catapulte : repos puis élan")
	check(M9.breton_pos(0, 0.0, 330.0, mission.zones.landing, []).distance_to(mission.zones.landing) < 12.0, "les Bretons partent du débarquement")
	# --- Prise et chargement ----------------------------------------------------------------------------------------------------------------
	place(mission.stocks[0] + Vector3(30, 0, 0))
	await frames(2)
	check(mission.resolve(1, player.global_position).is_empty(), "loin d'un étal : rien à faire")
	place(mission.stocks[0])
	await frames(2)
	check(mission.resolve(1, player.global_position).get("kind") == "take", "à l'étal : on peut prendre un camembert")
	mission.interact(1)
	await frames(2)
	check(mission.carriers.has(1) and player.carrying, "camembert pris : le joueur le porte")
	check(mission.resolve(1, player.global_position).get("kind") == "none", "loin de la catapulte : « portez-le »")
	place(mission.zones.catapult + Basis(Vector3.UP, mission.facing_catapult) * Vector3(0, 0, -3.0))
	await frames(2)
	check(mission.resolve(1, player.global_position).get("kind") == "load", "près de la catapulte : on peut charger")
	mission.interact(1)
	await frames(2)
	check(mission.loaded == 1 and not mission.carriers.has(1) and not player.carrying, "premier camembert chargé")
	# --- Flaque de beurre : la vitesse est limitée pour de vrai ----------------------------------------------------------------------------
	mission.elapsed = 20.0
	var c: Vector3 = M9.slicks_active(20.0, 11.0, mission.stocks, mission.zones.catapult)[0].center
	place(c)
	await frames(3)
	check(player.speed_cap == M9.SLICK_CAP, "le joueur dans la flaque est ralenti")
	place(mission.zones.landing)
	await frames(3)
	check(player.speed_cap == INF, "hors flaque, il court de nouveau")
	# --- Les neuf autres : le tir ----------------------------------------------------------------------------------------------------------
	for i in 8:
		await carry_one()
	check(mission.loaded == 9 and mission.step == "defend", "neuf camemberts : pas encore de tir")
	check(mission.medal == "", "pas de médaille avant le tir")
	await carry_one()
	check(mission.loaded == 10 and mission.step == "launch", "dixième camembert : la catapulte tire")
	check(mission.medal == "gold", "village presque intact : médaille d'or")
	await frames(60 * 14)
	check(mission.step == "launch", "le tir dure (cinématique)")
	await frames(60 * 3)
	check(mission.step == "done" and mission.result == "win", "les Bretons ont fui : mission réussie")
	var prog = root.get_node("Progress")
	check(prog.mission_state("m09_siege_des_bretons") == "done", "progression : mission 9 terminée")
	world.queue_free()
	await frames(5)
	# --- Défaite : le temps s'écoule -------------------------------------------------------------------------------------------------------------
	check(await boot(), "second monde")
	mission.time_left = 0.5
	await frames(60)
	check(mission.step == "failed" and mission.result == "lose", "temps écoulé : village englouti")
	world.queue_free()
	await frames(5)
	# --- Médaille selon le village restant -------------------------------------------------------------------------------------------------
	check(await boot(), "troisième monde")
	check(mission.medal_for(0.9) == "gold" and mission.medal_for(0.4) == "silver" and mission.medal_for(0.1) == "bronze" and mission.medal_for(0.0) == "", "médailles : or, argent, bronze")
	world.queue_free()
	await frames(5)
	print("--- m09_flow : %s" % ("OK" if fails == 0 else "%d échec(s)" % fails))
	quit(1 if fails > 0 else 0)
