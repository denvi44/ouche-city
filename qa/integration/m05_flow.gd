extends SceneTree
## Test d'intégration de la mission 05 (agent 09), en solo headless, sans compagnons :
## le troupeau est dans le pré ; le joueur se place derrière chaque vache et siffle ; les huit entrent dans l'enclos ; on ferme la
## barrière → médaille d'or ; puis une seconde partie où le temps s'écoule sans rien faire (défaite).
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m05_flow.gd -- --mission=m05 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var player
var M5


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
	return mission != null and mission.get_script() == M5 and player != null


func ground(x: float, z: float) -> float:
	return world.builder.height_at(x, z)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M5 = load("res://scripts/world/mission_m05.gd")
	if not check(await boot(), "monde de la mission 5 : mission et joueur, pas de véhicule"):
		quit(1)
		return
	check(mission.started and mission.step == "herd", "mission démarrée à l'étape rabattage")
	check(abs(world.day_night.hour - 4.0) < 0.1, "il est 4 h du matin")
	check(world.van == null, "la mission se joue à pied")
	check(mission.zones.has("pen") and mission.zones.has("pre"), "enclos et pré posés")
	check(mission.cows.size() == 8 and mission.penned() == 0, "huit vaches dans le pré, aucune à l'enclos")
	for i in 8:
		check(world.find_child("Vache_%d" % i, true, false) != null, "vache %d : modèle posé" % i) if i < 2 else null
	# Pures : fuite, clôture, médailles.
	check(M5.flee_speed(0.0, 1.0) < M5.flee_speed(1.0, 1.0) and is_equal_approx(M5.flee_speed(1.0, 1.4), M5.RUN_SPEED * 1.4), "fuite : plus vite sous pression, Marguerite ×1,4")
	check(M5.on_fence(Vector2(-6.0, 0.0), false) and M5.on_fence(Vector2(0.0, -6.0), false) and not M5.on_fence(Vector2(0.0, 0.0), false), "clôture : côtés et fond bloquent, l'intérieur est libre")
	check(not M5.on_fence(Vector2(0.0, 6.0), false) and M5.on_fence(Vector2(0.0, 6.0), true) and M5.on_fence(Vector2(4.0, 6.0), false), "porte : ouverte au milieu, fermée sinon")
	check(mission.medal_for(8) == "gold" and mission.medal_for(6) == "silver" and mission.medal_for(4) == "bronze" and mission.medal_for(3) == "", "médailles : 8 / 6 / 4 vaches")
	mission.time_left = 5000.0

	# --- Sifflet ----------------------------------------------------------------------------------------------------
	var pen: Vector3 = mission.zones.pen
	var pre: Vector3 = mission.zones.pre
	place(Vector3(pre.x, ground(pre.x, pre.z), pre.z) + Vector3(30, 0, 30))
	check(mission.resolve(1, player.global_position).get("kind") == "whistle", "on peut siffler")
	var w0: int = mission.whistles
	mission.interact(1)
	check(mission.whistles == w0 + 1 and mission.resolve(1, player.global_position).get("kind") == "none", "sifflet lancé, puis délai de 3 s")
	await frames(200)
	check(mission.resolve(1, player.global_position).get("kind") == "whistle", "le sifflet est de nouveau prêt")

	# --- Rabattage ---------------------------------------------------------------------------------------------------
	var guard := 0
	var frames_herd := 0
	var pen2 := Vector2(pen.x, pen.z)
	while mission.step == "herd" and guard < 30000:
		guard += 1
		frames_herd += 1
		var c: Dictionary = mission.nearest_stray(Vector2(player.global_position.x, player.global_position.z))
		if c.is_empty():
			await physics_frame
			continue
		var cp := Vector2(c.x, c.z)
		var away := (cp - pen2).normalized()
		var spot := cp + away * 5.5
		place(Vector3(spot.x, ground(spot.x, spot.y), spot.y))
		if frames_herd % 90 == 0:
			mission.interact(1)
		await physics_frame
	check(mission.step == "gate" and mission.penned() == 8, "les huit vaches sont dans l'enclos en %.0f s (%d images)" % [frames_herd / 60.0, frames_herd])
	print("  ", mission.messages)
	var inside := true
	for c in mission.cows:
		inside = inside and mission.in_pen(Vector2(c.x, c.z), 0.0)
	check(inside, "toutes les vaches sont bien dans la clôture")

	# --- Barrière ----------------------------------------------------------------------------------------------------------
	place(pen + Vector3(0, 0, 0) + Vector3(sin(mission.facing_pen), 0, cos(mission.facing_pen)) * 20.0)
	check(mission.resolve(1, player.global_position).get("kind", "") == "", "loin de la barrière : rien à fermer")
	var gp: Vector3 = mission._front(Vector3(0, 0, M5.PEN_HALF + 2.0))
	place(Vector3(gp.x, ground(gp.x, gp.z), gp.z))
	check(mission.resolve(1, player.global_position).get("kind") == "close", "près de la barrière : on peut la fermer")
	mission.interact(1)
	await frames(30)
	check(mission.step == "done" and mission.result == "win" and mission.gate_closed, "barrière fermée : victoire")
	check(mission.medal == "gold", "médaille d'or : huit vaches")
	var prog = root.get_node("Progress")
	check(prog.mission_state("m05_vaches_en_goguette") == "done" and prog.data.reputation.get("campagne", 0) >= 1, "progression : mission 5 terminée, réputation Campagne")
	check(root.get_node("Sfx").counts.get("whistle", 0) >= 2 and root.get_node("Sfx").counts.get("fanfare", 0) >= 1, "sifflets et fanfare")
	world.queue_free()
	await frames(5)

	# --- Défaite : le temps s'écoule -----------------------------------------------------------------------------------------
	check(await boot(), "second monde")
	mission.time_left = 0.3
	await frames(60)
	check(mission.step == "done" and mission.result == "lose" and mission.medal == "", "temps écoulé, aucune vache rentrée : défaite sans médaille")

	print("--- m05_flow : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
