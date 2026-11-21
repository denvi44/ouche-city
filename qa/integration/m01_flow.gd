extends SceneTree
## Test d'intégration de la mission 01 (agent 09), en solo headless, sans souris ni clavier.
## Usage : godot --headless --path game -s ../qa/integration/m01_flow.gd -- --no-companions
## Déroulé : 4 caisses → camionnette → conduite → descente/remontée → choc (bouteilles cassées)
## → barrage → stand → médaille. Chaque étape est vérifiée ; code de sortie 1 au premier échec.

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var van
var player
var heard_captions: Array = []


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


func _run() -> void:
	create_timer(120.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	world = load(WORLD).instantiate()
	root.add_child(world)
	root.get_node("Sfx").caption.connect(func(t, _d): heard_captions.append(t))
	await frames(40)
	mission = world.mission
	van = world.van
	player = world.players_root.get_node_or_null("1")
	if not (check(mission != null and van != null and player != null, "monde, mission, camionnette et joueur créés")):
		quit(1)
		return
	await frames(60)
	check(van.is_on_floor(), "la camionnette repose sur le sol")
	check(mission.started and mission.step == "crates", "mission démarrée à l'étape caisses")
	check(mission.crates.size() == 4, "4 caisses posées (cave, grange, poulailler, fumier)")

	# --- Caisses -------------------------------------------------------------------
	for id in mission.crates.keys():
		var c = mission.crates[id]
		place(player, c.pos + Vector3(0, 0.1, 0))
		var r = mission.resolve(1, player.global_position)
		if not check(r.get("kind") == "pickup" and r.id == id, "caisse %s : prise possible" % id):
			continue
		mission.interact(1)
		await frames(3)
		check(c.state == "carried" and player.carrying, "caisse %s portée (joueur ralenti)" % id)
		var far = c.pos + Vector3(30, 0, 0)
		check(mission.resolve(1, far).get("kind") == "none", "loin de la camionnette : consigne « rapportez »")
		place(player, van.global_position + van.global_transform.basis.x * 2.6)
		check(mission.resolve(1, player.global_position).get("kind") == "load", "caisse %s : chargement possible" % id)
		mission.interact(1)
		await frames(3)
		check(c.state == "loaded" and not player.carrying, "caisse %s chargée" % id)
	check(mission.cargo == 24 and mission.step == "road", "24 bouteilles à bord, étape route")

	# --- Monter, conduire ---------------------------------------------------------
	place(player, van.global_position + van.global_transform.basis.x * 2.6)
	check(mission.resolve(1, player.global_position).get("kind") == "enter", "monter possible")
	mission.interact(1)
	await frames(3)
	check(van.driver == 1 and player.is_driving() and van.controller == 1, "joueur au volant")
	check(not player.visual.visible, "joueur masqué pendant la conduite")
	var start: Vector3 = van.global_position
	van.forced_input = {"move": Vector2(0, -1), "jump": false}
	await frames(150)
	var moved: float = van.global_position.distance_to(start)
	check(van.speed > 8.0, "accélération : %.1f m/s" % van.speed)
	check(moved > 15.0, "la camionnette avance (%.0f m)" % moved)
	check(van.speed <= van.MAX_SPEED + 0.01, "vitesse plafonnée")
	check(van.is_on_floor(), "reste collée au sol")
	check(player.global_position.distance_to(van.global_position) < 1.5, "le joueur suit la camionnette")
	var yaw0: float = van.rotation.y
	van.forced_input = {"move": Vector2(1, -1), "jump": false}
	await frames(60)
	check(van.rotation.y < yaw0 - 0.05, "braquage à droite : le lacet diminue")
	van.forced_input = {"move": Vector2(0, 0), "jump": true}
	await frames(120)
	check(absf(van.speed) < 0.5, "frein à main : arrêt")

	# --- Descendre / remonter ---------------------------------------------------------
	check(mission.resolve(1, player.global_position).get("kind") == "exit", "descendre possible")
	mission.interact(1)
	await frames(5)
	check(van.driver == 0 and not player.is_driving(), "joueur à pied")
	check(player.global_position.distance_to(van.global_position) > 1.8 and player.global_position.distance_to(van.global_position) < 6.0, "descendu à côté")
	mission.interact(1)
	await frames(3)
	check(van.driver == 1, "remonté au volant")

	# --- Choc : cargaison fragile ----------------------------------------------------------
	var space = van.get_world_3d().direct_space_state
	var found := false
	var base: Vector3 = van.global_position
	for k in 72:
		var yaw := TAU * k / 72.0
		var dir := Vector3(-sin(yaw), 0, -cos(yaw))
		var q = PhysicsRayQueryParameters3D.create(base + Vector3(0, 1.2, 0), base + Vector3(0, 1.2, 0) + dir * 400.0)
		q.exclude = [van.get_rid(), player.get_rid()]
		var hit = space.intersect_ray(q)
		if hit and hit.normal.y < 0.3 and hit.normal.dot(-dir) > 0.93 and base.distance_to(hit.position) > 32.0:
			# 28 m avant le mur, cap dessus : la camionnette a le temps de monter en vitesse.
			van.rotation.y = yaw
			place(van, hit.position - dir * 30.0 + Vector3(0, 0.6, 0))
			van.speed = 0.0
			found = true
			break
	if check(found, "un mur à percuter a été trouvé"):
		await frames(10)
		var bottles_before: int = mission.cargo
		var broken_before: int = mission.broken
		van.forced_input = {"move": Vector2(0, -1), "jump": false}
		await frames(240)
		check(mission.broken > broken_before and mission.cargo < bottles_before, "choc frontal : %d bouteille(s) cassée(s) en plus, %d intacte(s)" % [mission.broken - broken_before, mission.cargo])
		check(mission.messages.size() > 0, "événement consigné pour le HUD")
	van.forced_input = {"move": Vector2.ZERO, "jump": true}
	await frames(60)

	# --- Événements de route : nids-de-poule, tracteur, vaches ---------------------------------------
	mission.step = "road"
	mission.cargo = 20
	van.forced_input = {"move": Vector2.ZERO, "jump": true}
	check(mission.hazards_ready and mission.potholes.size() == 5, "5 nids-de-poule posés sur l'itinéraire")
	check(mission.route_length > 150.0 and mission.route_length < 800.0, "itinéraire de la camionnette au barrage : %.0f m" % mission.route_length)
	var ground_y := func(p: Vector2) -> float: return world.builder.height_at(p.x, p.y) + 0.6
	# On repart d'un état propre (la camionnette a pu réveiller le tracteur pendant les essais de conduite).
	mission.tractor_active = false
	mission.tractor_done = false
	mission.tractor.set_active(false)
	mission.tractor.teleport(Vector3(mission.tractor_start.x, mission.tractor.global_position.y, mission.tractor_start.y), mission.tractor.yaw)
	mission.tractor.start_route(mission._tractor_path)
	check(not mission.cows_active, "vaches endormies avant l'approche")
	# Au départ de l'itinéraire, le tracteur dort encore.
	place(van, Vector3(mission.route[0].x, ground_y.call(mission.route[0]), mission.route[0].y))
	van.speed = 0.0
	await frames(5)
	check(not mission.tractor_active and not mission.tractor.visible, "tracteur inactif et invisible tant qu'on est loin")
	# Nid-de-poule pris vite : 12 m/s => 2 bouteilles de moins et une secousse.
	var jolts0: int = mission.jolt_serial
	var p0: Vector2 = mission.potholes[0]
	place(van, Vector3(p0.x, ground_y.call(p0), p0.y))
	van.speed = 12.0
	await frames(3)
	check(mission.cargo == 18, "nid-de-poule à 43 km/h : 2 bouteilles perdues (%d → %d)" % [20, mission.cargo])
	check(mission.jolt_serial == jolts0 + 1, "secousse de la caisse signalée")
	# Pris doucement : rien de cassé.
	var p1: Vector2 = mission.potholes[1]
	place(van, Vector3(p1.x, ground_y.call(p1), p1.y))
	van.speed = 2.0
	await frames(3)
	check(mission.cargo == 18, "nid-de-poule à 7 km/h : rien de cassé")
	var soft := false
	for m in mission.messages:
		soft = soft or m.contains("doucement")
	check(soft, "message : « vous passez doucement »")
	# Le même nid-de-poule ne frappe pas deux fois de suite (délai de 2,5 s).
	place(van, Vector3(p1.x, ground_y.call(p1), p1.y))
	van.speed = 12.0
	await frames(3)
	check(mission.cargo == 18, "même nid-de-poule, 3 images plus tard : pas de double peine")

	# Tracteur : se réveille à l'approche, roule à ~3 m/s, rentre à la ferme.
	var t_pos: Vector2 = mission.route_at(mission.route_length * mission.TRACTOR_FROM - 40.0).pos
	place(van, Vector3(t_pos.x, ground_y.call(t_pos), t_pos.y))
	van.speed = 0.0
	await frames(5)
	check(mission.tractor_active and mission.tractor.visible, "tracteur réveillé à 40 m")
	var tr0: Vector3 = mission.tractor.global_position
	await frames(300)
	var tr_d := Vector2(mission.tractor.global_position.x - tr0.x, mission.tractor.global_position.z - tr0.z).length()
	check(tr_d > 10.0 and tr_d < 18.0, "le tracteur avance de %.1f m en 5 s (≈ 3 m/s)" % tr_d)
	check(mission.tractor.speed_now > 2.5 and mission.tractor.speed_now < 3.2, "vitesse du tracteur : %.1f m/s" % mission.tractor.speed_now)
	mission.tractor.finished = true
	await frames(5)
	check(not mission.tractor_active and mission.tractor_done and not mission.tractor.visible, "le tracteur quitte la route")

	# Vaches : traversée, arrêt au milieu, klaxon.
	var cp: Vector2 = Vector2.ZERO
	for rp in mission.route:
		if rp.distance_to(mission.cow_center) >= 35.0 and rp.distance_to(mission.cow_center) < 48.0:
			cp = rp
			break
	check(cp != Vector2.ZERO, "un point de l'itinéraire à ~40 m des vaches")
	place(van, Vector3(cp.x, ground_y.call(cp), cp.y))
	van.speed = 0.0
	await frames(5)
	check(mission.cows_active and mission.cows.size() == 3, "3 vaches se mettent à traverser")
	await frames(780)
	var grazing := 0
	var in_place := true
	for cw in mission.cows:
		if cw.state == "grazing":
			grazing += 1
		var off: float = (Vector2(cw.global_position.x, cw.global_position.z) - cw.origin).dot(cw.across)
		in_place = in_place and absf(off - cw.rest_offset) < 1.0
	check(grazing == 3, "les 3 vaches broutent au milieu de la route")
	check(in_place, "chacune à sa place (barrent la chaussée en zigzag)")
	mission.horn()
	await frames(10)
	var startled := true
	for cw in mission.cows:
		startled = startled and cw.state == "leaving"
	check(startled, "le klaxon les fait partir")
	check(mission.messages[-1].contains("détalent"), "message : « Les vaches détalent »")
	await frames(900)
	var gone := true
	for cw in mission.cows:
		gone = gone and cw.state == "gone"
	check(gone and mission.cows_done, "les vaches ont dégagé la route")
	mission.cargo = 18

	# --- Barrage : choix d'équipe (sans compagnons : ni Ginette ni Kévin sur place) ---------------------
	var barrier = world.city.get_node_or_null("LieuxDeMission/Lieu_barrage_bosc_tenney/Collision")
	check(barrier != null and barrier.collision_layer == 1, "la barrière du barrage est solide")
	var to_barrage := func():
		mission.step = "road"
		mission.barrier_open = false
		place(van, mission.zones.barrage + Vector3(0, 0.6, 0) + van.forward() * -6.0)
		van.speed = 0.0
	van.forced_input = {"move": Vector2.ZERO, "jump": true}
	await frames(30)
	var cargo0: int = mission.cargo
	# 1. Détour : +45 s, aucune perte.
	to_barrage.call()
	await frames(10)
	check(mission.step == "checkpoint" and mission.checkpoint_left > 11.0, "barrage : choix ouvert (12 s)")
	check(mission.objective().contains("Bluffer") and mission.objective().contains("Diversion"), "consigne : les trois options sont affichées")
	var t0: float = mission.elapsed
	mission.choose("detour")
	check(mission.step == "fair" and mission.elapsed - t0 >= 44.9 and mission.cargo == cargo0, "détour : +45 s, cargaison intacte")
	await frames(2)
	check(barrier.collision_layer == 0, "barrière ouverte une fois le barrage franchi")
	# 2. Bluff raté, sans Ginette : le gendarme saisit 3 bouteilles.
	to_barrage.call()
	await frames(10)
	check(barrier.collision_layer == 1, "barrière refermée au nouveau passage")
	mission.test_roll = 0.99
	mission.choose("bluff")
	check(mission.step == "fair" and mission.cargo == cargo0 - 3, "bluff raté : 3 bouteilles saisies (%d → %d)" % [cargo0, mission.cargo])
	# 3. Bluff réussi (tirage chanceux) : rien de perdu.
	var cargo1: int = mission.cargo
	to_barrage.call()
	await frames(10)
	mission.test_roll = 0.05
	mission.choose("bluff")
	check(mission.step == "fair" and mission.cargo == cargo1, "bluff réussi : cargaison intacte")
	mission.test_roll = -1.0
	# 4. Diversion sans Kévin : échec, +20 s, on reste au barrage.
	to_barrage.call()
	await frames(10)
	t0 = mission.elapsed
	mission.choose("diversion")
	check(mission.step == "checkpoint" and "diversion" in mission.failed_options and mission.elapsed - t0 >= 19.9, "diversion sans Kévin : échec (+20 s), choix rouvert")
	# 5. Personne ne tranche : sans Ginette, on contourne automatiquement.
	mission.checkpoint_left = 0.01
	t0 = mission.elapsed
	await frames(10)
	check(mission.step == "fair" and mission.elapsed - t0 >= 44.9, "délai écoulé sans Ginette : contournement automatique")
	# 6. Ordres invalides ignorés.
	mission.choose("detour")
	check(mission.step == "fair", "un choix hors barrage est ignoré")
	# 7. Arrivée au stand avec trop peu de bouteilles (8 < 12) : la mission échoue.
	mission.cargo = 8
	place(van, mission.zones.stand + Vector3(0, 0.6, 0))
	van.speed = 0.0
	await frames(10)

	var intact: int = mission.cargo
	if intact < mission.min_delivered:
		check(mission.step == "failed" and mission.medal == "", "moins de %d bouteilles (%d) : mission échouée" % [mission.min_delivered, intact])
	else:
		check(mission.step == "done" and mission.medal == mission.medal_for(intact), "livraison au stand, médaille %s" % mission.medal)
	await frames(3)
	# Seconde issue : on remet 20 bouteilles intactes (hook de test) et on relivre.
	mission.step = "fair"
	mission.cargo = 20
	mission.medal = ""
	mission.money = 0
	place(van, mission.zones.barrage + Vector3(0, 0.6, 0))
	await frames(5)
	place(van, mission.zones.stand + Vector3(0, 0.6, 0))
	van.speed = 0.0
	await frames(10)
	check(mission.step == "done", "livraison réussie avec 20 bouteilles")
	check(mission.medal == "silver", "médaille d'argent (16 à 21)")
	check(mission.money == 20 * mission.money_per_bottle, "récompense %d €" % mission.money)

	# --- Barème des médailles (fonction pure) ---------------------------------------------------
	check(mission.medal_for(24) == "gold" and mission.medal_for(22) == "gold", "or à partir de 22")
	check(mission.medal_for(16) == "silver" and mission.medal_for(21) == "silver", "argent de 16 à 21")
	check(mission.medal_for(12) == "bronze" and mission.medal_for(15) == "bronze", "bronze de 12 à 15")
	check(mission.medal_for(11) == "", "rien sous 12")

	# --- Progression : la livraison réussie est enregistrée ---------------------------------------------
	var prog = root.get_node("Progress")
	check(prog.is_done("m01_calva_gege") and prog.medal_of("m01_calva_gege") == "silver", "progression : mission 1 terminée, médaille d'argent")
	check(prog.money() == 20 * mission.money_per_bottle, "progression : %d € gagnés" % prog.money())
	check(prog.mission_state("m02_tuning_samedi") == "available", "progression : la mission 2 est débloquée")
	check(prog.data.reputation.get("comite_fetes", 0) == 1, "progression : réputation du Comité des fêtes +1")

	# --- Sons déclenchés par les événements (journalisés même sans carte son) ----------------------------
	var sfx = root.get_node("Sfx")
	check(sfx.counts.get("crate", 0) >= 4, "son : 4 prises de caisse (%d)" % sfx.counts.get("crate", 0))
	check(sfx.counts.get("chime", 0) >= 4, "son : 4 chargements validés (%d)" % sfx.counts.get("chime", 0))
	check(sfx.counts.get("thud", 0) >= 2, "son : chocs de nids-de-poule (%d)" % sfx.counts.get("thud", 0))
	check(sfx.counts.get("glass", 0) >= 1, "son : verre brisé (%d)" % sfx.counts.get("glass", 0))
	check(sfx.counts.get("klaxon", 0) >= 1, "son : klaxon (%d)" % sfx.counts.get("klaxon", 0))
	check(sfx.counts.get("fail", 0) >= 1, "son : échec quand moins de 12 bouteilles arrivent")
	check(sfx.counts.get("fanfare", 0) >= 1, "son : fanfare à la médaille")
	check("[Klaxon]" in heard_captions and "[Verre brisé]" in heard_captions and "[Fanfare de victoire]" in heard_captions, "sous-titres sonores émis : %s" % str(heard_captions.size()))

	print("[m01] %s" % ("ÉCHEC : %d vérification(s)" % fails if fails > 0 else "toutes les vérifications passent"))
	quit(1 if fails > 0 else 0)
