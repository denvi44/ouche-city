extends SceneTree
## Test d'intégration de la mission 08 (agent 09), solo headless, sans compagnons : le troupeau est à la mare ; un « HONK ! » le
## rassemble ; les oies suivent le meneur jusqu'à la voie et s'y installent ; le train freine et s'arrête devant elles ; le
## garde-barrière sort et recule sous un « HONK ! » ; le klaxon effraie les oies non rassurées ; tenue de 30 s → médaille ;
## puis une partie où personne ne vient : le train passe (défaite).
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m08_flow.gd -- --mission=m08 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var player
var M8


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
	return mission != null and mission.get_script() == M8 and player != null


## Mène le joueur de la mare à la voie, pas à pas (les suiveuses le suivent), et s'y arrête.
func walk_to(target: Vector3, speed := 5.0, max_s := 40.0) -> void:
	var t := 0.0
	while t < max_s:
		var d := Vector2(target.x - player.global_position.x, target.z - player.global_position.z)
		if d.length() < 1.0:
			break
		var step := d.normalized() * minf(speed / 60.0, d.length())
		player.facing = atan2(-step.x, -step.y)
		player.global_position += Vector3(step.x, 0, step.y)
		player.velocity = Vector3.ZERO
		await physics_frame
		t += 1.0 / 60.0


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M8 = load("res://scripts/world/mission_m08.gd")
	if not check(await boot(), "monde de la mission 8 : mission et joueur"):
		quit(1)
		return
	check(mission.started and mission.step == "gather", "mission démarrée à l'étape rassemblement")
	check(abs(world.day_night.hour - 17.0) < 0.1, "il est 17 h")
	check(world.van == null, "la mission se joue à pied (pas de véhicule)")
	check(player.avatar == "oie" and player.model is GooseModel, "le joueur est une oie")
	check(mission.zones.has("pond") and mission.zones.has("crossing"), "mare et passage à niveau posés")
	check(mission.geese.size() == 12 and mission.count_state("graze") == 12, "douze oies broutent à la mare")
	check(mission.train.st == "wait" and mission.blockers() == 0, "le train n'est pas encore parti")
	check(mission.companion_roles().size() == 3, "trois rôles de compagnons")
	# Géométrie de la voie.
	check(M8.in_zone(Vector2(-3.0, 0.5)) and not M8.in_zone(Vector2(-3.0, 3.5)) and not M8.in_zone(Vector2(20.0, 0.0)), "zone de blocage : sur la voie seulement")
	var c: Vector3 = mission.zones.crossing
	check(mission.to_track(Vector2(c.x, c.z)).length() < 0.01, "le passage à niveau est l'origine du repère de la voie")
	check(mission.spawn_hint() != Vector3.ZERO and Vector2(mission.spawn_hint().x - mission.zones.pond.x, mission.spawn_hint().z - mission.zones.pond.z).length() < 14.0, "les joueurs apparaissent près de la mare")
	# HONK ! trop loin : rien. Puis à la mare : tout le monde suit.
	place(c + Vector3(0, 0, 0) + Vector3(0, 0, 200))
	await frames(2)
	check(mission.resolve(1, player.global_position).get("kind") == "honk", "E : HONK ! proposé")
	mission.interact(1)
	await frames(2)
	check(mission.count_state("follow") == 0 and mission.honks == 1, "loin de la mare, le cri ne rassemble personne")
	await frames(130)       # recharge du cri
	check(mission.resolve(1, player.global_position).get("kind") == "honk", "le cri est de nouveau disponible après %.0f s" % mission.honk_cd_max)
	place(mission.zones.pond + Vector3(2, 0, 2))
	await frames(2)
	mission.interact(1)
	await frames(2)
	check(mission.count_state("follow") >= 10, "un HONK ! rassemble la basse-cour (%d suiveuses)" % mission.count_state("follow"))
	check(mission.resolve(1, player.global_position).get("kind") == "none", "cri en recharge : bouton grisé")
	# On les mène sur la voie.
	var in_hut: Vector3 = mission.track_to_world(Vector2(-3.0, 0.0))
	await walk_to(mission.zones.pond + Vector3(14, 0, 14), 4.0, 8.0)
	await walk_to(in_hut, 4.2, 60.0)
	await frames(240)
	var b: int = mission.blockers()
	check(b >= 8, "les oies suivent le meneur et s'installent sur la voie (%d sur la voie)" % b)
	var slots := {}
	var dup := false
	for g in mission.geese:
		if g.st == "block":
			if slots.has(int(g.slot)):
				dup = true
			slots[int(g.slot)] = true
	check(not dup, "chaque oie a sa case sur la voie")
	# Le train part et s'arrête.
	check(mission.train.st == "wait", "le train attend son heure")
	mission.elapsed = mission.arrival_sec - absf(mission.train_start_u()) / mission.train_speed - 0.5
	await frames(90)
	check(mission.train.st in ["run", "brake"], "le train est parti (%s)" % mission.train.st)
	var nose0: float = mission.train_nose_u()
	var guard := 0
	while mission.train.st != "stopped" and guard < 60 * 60:
		await physics_frame
		guard += 1
	check(mission.train.st == "stopped", "le train s'arrête devant les oies (%.0f s)" % (guard / 60.0))
	var stop_u: float = mission.train_nose_u()
	check(stop_u < M8.ZONE_U.x and M8.ZONE_U.x - stop_u > 8.0, "il s'arrête à %.0f m de la première oie : jamais de choc" % (M8.ZONE_U.x - stop_u))
	check(mission.step == "block", "étape : tenir la voie")
	# Tenue : le garde-barrière sort, on le fait reculer.
	var hold0: float = mission.train.hold
	await frames(60 * 4)
	check(float(mission.train.hold) > hold0 + 2.0, "la tenue avance quand assez d'oies sont sur la voie (%.0f s)" % mission.train.hold)
	mission.elapsed = 1000.0       # force la sortie du garde-barrière (délai écoulé)
	mission.train.stopped_at = 0.0
	var seen_walk := false
	for i in 60 * 30:
		await physics_frame
		if mission.master.st in ["walk", "shoo"]:
			seen_walk = true
			break
	check(seen_walk, "le garde-barrière sort de sa maisonnette")
	# Il s'approche : on le fait reculer d'un HONK !
	var mp := Vector3(mission.master.x, 0, mission.master.z)
	for i in 60 * 40:
		await physics_frame
		mp = Vector3(mission.master.x, 0, mission.master.z)
		if Vector2(mp.x, mp.z).distance_to(Vector2(c.x, c.z)) < 12.0:
			break
	mission._honk_cd.clear()
	place(Vector3(mp.x + 3.0, c.y, mp.z))
	await frames(2)
	mission.interact(1)
	await frames(3)
	check(mission.master.st == "stunned", "un HONK ! à moins de %d m fait sursauter le garde-barrière" % int(M8.STUN_RANGE))
	await frames(60 * 12)
	check(mission.master.st in ["back", "hut"], "il bat en retraite vers sa maisonnette (%s)" % mission.master.st)
	# Le klaxon du train effraie les oies non rassurées.
	for g in mission.geese:
		g.calm = 0.0
	var before: int = mission.blockers()
	mission.rng.seed = 7
	mission._train_horn()
	var after: int = mission.blockers()
	check(after < before, "le klaxon du train effraie des oies (%d → %d)" % [before, after])
	for g in mission.geese:
		if g.st == "block":
			g.calm = 6.0
	var keep: int = mission.blockers()
	mission._train_horn()
	check(mission.blockers() == keep, "les oies rassurées par un HONK ! ne bougent pas")
	# Les oies en fuite reviennent si le meneur recrie.
	place(mission.zones.crossing + Vector3(0, 0, -6.0))
	mission._honk_cd.clear()
	await frames(30)
	mission.interact(1)
	await frames(2)
	# Gagner : on force la tenue.
	for g in mission.geese:
		if g.st != "block":
			g.st = "block"
			g.slot = 0
	mission.train.hold = mission.hold_required - 0.5
	await frames(90)
	check(mission.step == "done" and mission.result == "win", "tenue de %d s : le train est bloqué, victoire (%s)" % [int(mission.hold_required), mission.result])
	check(mission.medal != "", "médaille : %s (moyenne %.1f oies)" % [mission.medal, mission.avg_blockers])
	check(M8.new().medal_for(10.0) == "gold" and M8.new().medal_for(8.5) == "silver" and M8.new().medal_for(5.0) == "bronze" and M8.new().medal_for(4.0) == "", "barème : or ≥ 10, argent ≥ 8, bronze ≥ 5 oies en moyenne")
	check(get_root().get_node("Progress").is_done("m08_oies_en_greve"), "progression enregistrée")
	check(mission.hud_lines().size() >= 2 and str(mission.result_text()) != "", "texte de fin")
	# Défaite : personne sur la voie, le train passe.
	world.queue_free()
	await frames(3)
	if not check(await boot(), "seconde partie"):
		quit(1)
		return
	mission.elapsed = mission.arrival_sec - absf(mission.train_start_u()) / mission.train_speed - 0.5
	var g2 := 0
	while mission.step != "failed" and g2 < 60 * 90:
		await physics_frame
		g2 += 1
	check(mission.step == "failed" and mission.result == "lose", "sans oies sur la voie, le train passe : défaite (%.0f s)" % (g2 / 60.0))
	# Le temps qui s'écoule seul.
	world.queue_free()
	await frames(3)
	if not check(await boot(), "troisième partie"):
		quit(1)
		return
	mission.time_left = 1.0
	await frames(120)
	check(mission.step == "failed", "temps écoulé : défaite")
	print("--- m08_flow : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
