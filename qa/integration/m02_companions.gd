extends SceneTree
## Test d'intégration des compagnons de la mission 02 (agent 09) : le joueur est immobile, les compagnons agissent.
## Ginette marchande l'annonce, Kévin attend au garage et monte les pièces à la place du joueur,
## Gégé gagne le rendez-vous et fait monter la note de « présence » du jury.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m02_companions.gd -- --mission=m02

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


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	create_timer(400.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(80)
	var mission = world.mission
	var ginette = world.players_root.get_node_or_null("-2")
	var kevin = world.players_root.get_node_or_null("-4")
	var gege = world.players_root.get_node_or_null("-1")
	if not check(ginette != null and kevin != null and gege != null and world.players_root.get_node_or_null("-3") == null, "3 compagnons en mission 2 (Gégé, Ginette, Kévin), pas de Kévin Radio"):
		quit(1)
		return
	check(mission.companion_roles() == {-1: "ambianceur", -2: "chineuse", -4: "mecano"}, "rôles : ambianceur, chineuse, mécano")
	mission.test_roll = 0.2          # 0,2 < 0,85 : le marchandage de Ginette réussira

	# --- 150 s de jeu : les compagnons vont à leur poste ---------------------------------------------
	for i in 150 * 60:
		await physics_frame
		if "pot" in mission.parts and mission.spot("garage_kevin") != Vector3.ZERO and i > 100 * 60:
			break
	check("pot" in mission.parts and mission.sources.annonce, "Ginette a marchandé l'annonce : pot acheté (budget %d €)" % mission.budget)
	check(mission.budget == 400 - 72, "au prix de 72 € (60 % de 120)")
	check(ginette.brain.status == "a fini ses courses", "Ginette a fini ses courses")
	var sk: Vector3 = mission.spot("garage_kevin")
	var sg: Vector3 = mission.spot("meet_gege")
	var dk := Vector2(kevin.global_position.x - sk.x, kevin.global_position.z - sk.z).length()
	var dg := Vector2(gege.global_position.x - sg.x, gege.global_position.z - sg.z).length()
	for i in 60 * 40:
		if dg < 3.5:
			break
		await physics_frame
		dg = Vector2(gege.global_position.x - sg.x, gege.global_position.z - sg.z).length()
	check(dk < 3.5, "Kévin est au garage (%.1f m)" % dk)
	check(dg < 3.5, "Gégé est au rendez-vous (%.1f m) — %s" % [dg, gege.brain.status])

	# --- Montage : personne ne joue le mini-jeu, Kévin le fait à 70 % ------------------------------------
	mission.parts = ["pot", "jantes", "aileron"]
	var player = world.players_root.get_node("1")
	player.global_position = mission.zones.garage + Vector3(2.0, 0.6, 1.0)
	await frames(5)
	mission.interact(1)
	check(mission.step == "assembly" and mission.assembly_total == 3, "montage lancé : 3 pièces")
	mission.test_roll = 0.5
	for i in 60 * 30:
		await physics_frame
		if mission.step != "assembly":
			break
	check(mission.step == "test_drive" and mission.mini_fails == 0, "Kévin a monté les 3 pièces seul (aucun raté, %d)" % mission.mini_fails)
	check(world.van.has_part("pot") and world.van.has_part("jantes"), "la Fusée est équipée par Kévin")

	# --- Jury : Gégé est sur place, la présence est maximale -----------------------------------------------
	var car = world.van
	car.forced_input = {"move": Vector2.ZERO, "jump": true}
	for p in mission.td_points:
		car.global_position = Vector3(p.x, world.builder.height_at(p.x, p.y) + 0.6, p.y)
		car.velocity = Vector3.ZERO
		car.speed = 3.0 if p == mission.td_points[mission.td_points.size() - 1] else 6.0
		await frames(3)
	car.speed = 0.0
	await frames(5)
	check(mission.step == "drag", "arrivée au rendez-vous")
	check(mission.jury.presence == 10, "présence 10/10 : Gégé à son poste, pas de flash, dans les temps (%s)" % str(mission.jury))
	print("[m02-companions] %s" % ("ÉCHEC : %d vérification(s)" % fails if fails > 0 else "toutes les vérifications passent"))
	quit(1 if fails > 0 else 0)
