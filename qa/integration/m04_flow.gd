extends SceneTree
## Test d'intégration de la mission 04 (agent 09), en solo headless, sans compagnons :
## matériel → feu tenu dans la bande (un chien laissé passer, les autres chassés) → huit assiettes servies → bûcher → médaille d'or ;
## puis trois fins : agneau carbonisé, matériel en retard, fête médiocre (défaite).
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m04_flow.gd -- --mission=m04 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var player
var M4


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
	return mission != null and mission.get_script() == M4 and player != null


func take_all_items() -> void:
	for it in M4.ITEMS:
		place(mission.item_pos[it] + Vector3(0.5, 0, 0.5))
		await frames(2)
		mission.interact(1)
		await frames(2)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M4 = load("res://scripts/world/mission_m04.gd")
	if not check(await boot(), "monde de la mission 4 : mission et joueur, pas de véhicule"):
		quit(1)
		return
	check(mission.started and mission.step == "gather", "mission démarrée à l'étape matériel")
	check(abs(world.day_night.hour - 19.0) < 0.1, "il est 19 h")
	check(world.van == null, "le méchoui se prépare à pied")
	for z in ["fete", "bucher"]:
		check(mission.zones.has(z), "lieu posé : %s" % z)
	for it in M4.ITEMS:
		check(mission.item_pos.has(it), "objet posé : %s" % it)
	check(M4.cook_rate(0.6, 0.45) == 1.0 and M4.cook_rate(0.35, 0.45) == M4.LUKEWARM_RATE and M4.cook_rate(0.2, 0.45) == 0.0, "cuisson : pleine dans la bande, lente entre froid et bande, nulle en dessous")
	check(is_equal_approx(M4.satisfaction_of(0.0, 8, 8, 0), 100.0) and is_equal_approx(M4.satisfaction_of(1.0, 0, 8, 3), 0.0), "satisfaction : 100 pour un sans-faute, 0 pour un désastre")
	check(is_equal_approx(M4.satisfaction_of(0.0, 4, 8, 3), 60.0), "satisfaction : moitié des convives, trois gigots volés = 60")
	check(mission.medal_for(85.0) == "gold" and mission.medal_for(65.0) == "silver" and mission.medal_for(40.0) == "bronze" and mission.medal_for(39.9) == "", "seuils de médaille 85 / 65 / 40")

	# --- Matériel ------------------------------------------------------------------------------------------------
	place(mission.station())
	check(mission.resolve(1, player.global_position).get("kind", "") == "", "au foyer, avant le matériel : rien à faire")
	place(mission.item_pos.agneau + Vector3(0.5, 0, 0.5))
	check(mission.resolve(1, player.global_position).get("kind") == "item", "près de l'agneau : on peut le prendre")
	mission.interact(1)
	check(mission.item_taken("agneau") and mission.step == "gather", "agneau pris, il manque la broche et le charbon")
	await frames(4)
	check(not world.find_child("Objet_agneau", true, false).visible, "l'agneau disparaît du décor")
	await take_all_items()
	check(mission.step == "fire" and mission._dog_queue.size() == 3, "matériel complet : le feu, trois chiens attendus")
	for i in 4:
		check(world.find_child("M4_Table_%d" % i, true, false) != null, "table %d posée" % i)

	# --- Feu : on garde la chaleur dans la bande ; le premier chien passe, les suivants sont chassés -----------------------
	place(mission.station() + Vector3(0.5, 0, 0.5))
	var first_dog_seen := false
	var guard := 0
	var in_band := 0
	var frames_fire := 0
	while mission.step == "fire" and guard < 12000:
		guard += 1
		frames_fire += 1
		place(mission.station() + Vector3(0.5, 0, 0.5))
		var r: Dictionary = mission.resolve(1, player.global_position)
		if r.get("kind") == "shoo" and (mission.dog_seq > 1 or mission.stolen >= 1):
			mission.interact(1)
		elif mission.heat < 0.55 and r.get("kind") != "shoo":
			mission.interact(1)
		elif mission.heat < 0.55 and r.get("kind") == "shoo" and mission.dog_seq <= 1:
			pass      # premier chien : on le laisse voler (le chien à portée a priorité sur le soufflet)
		if mission.heat >= mission.band.x and mission.heat <= mission.band.y + 0.1:
			in_band += 1
		first_dog_seen = first_dog_seen or mission.dog_seq >= 1
		await physics_frame
	check(mission.step == "serve", "l'agneau est cuit : étape de service (%d images)" % frames_fire)
	check(first_dog_seen and mission.dog_seq == 3, "trois chiens sont venus (%d)" % mission.dog_seq)
	check(mission.stolen >= 1 and mission.shooed >= 1, "un gigot volé (%d), des chiens chassés (%d)" % [mission.stolen, mission.shooed])
	check(mission.burn < 0.2, "l'agneau n'a presque pas brûlé (%.2f)" % mission.burn)
	check(frames_fire >= 3500, "il faut environ 60 s pour cuire (%d images)" % frames_fire)
	await frames(10)
	check(world.find_child("M4_Broche", true, false) != null, "la broche et l'agneau sont posés")
	check(mission.plates_left == 8 and not mission.is_carrying(1), "huit assiettes au foyer")

	# --- Service -----------------------------------------------------------------------------------------------------------
	for n in 8:
		place(mission.station())
		await frames(2)
		check(mission.resolve(1, player.global_position).get("kind") == "take", "assiette %d : on peut la prendre" % (n + 1))
		mission.interact(1)
		check(mission.is_carrying(1), "assiette %d : portée" % (n + 1))
		check(mission.resolve(1, player.global_position).get("kind") != "take", "mains prises : pas de seconde assiette")
		var t: int = n / 2
		place(mission.table_pos(t))
		await frames(2)
		var rr: Dictionary = mission.resolve(1, player.global_position)
		check(rr.get("kind") == "serve", "assiette %d : service possible à la table %d" % [n + 1, t + 1])
		mission.interact(1)
	await frames(8)
	check(mission.step == "bonfire" and mission._total_served() == 8, "huit convives servis : le bûcher")
	var tb = world.find_child("M4_Table_0", true, false)
	check(tb != null and mission._table_plates[0] == 4, "la table 1 montre ses assiettes")

	# --- Bûcher ----------------------------------------------------------------------------------------------------------------------
	place(mission.station())
	check(mission.resolve(1, player.global_position).get("kind", "") == "", "loin du bûcher : rien à allumer")
	place(mission.zones.bucher + Vector3(1.5, 0, 1.5))
	check(mission.resolve(1, player.global_position).get("kind") == "light", "près du bûcher : on peut l'allumer")
	var fw: int = root.get_node("Sfx").counts.get("firework", 0)
	mission.interact(1)
	await frames(150)
	check(mission.step == "done" and mission.result == "win" and mission.lit, "bûcher allumé : victoire")
	check(mission.medal == "gold" and mission.satisfaction > 85.0, "médaille d'or (satisfaction %.0f %%)" % mission.satisfaction)
	check(root.get_node("Sfx").counts.get("firework", 0) >= fw + 3, "trois salves de feu d'artifice")
	check(world.find_child("M4_FlammesBucher", true, false).visible, "les flammes du bûcher brûlent")
	var prog = root.get_node("Progress")
	check(prog.mission_state("m04_mechoui_saint_jean") == "done" and prog.data.reputation.get("comite_fetes", 0) >= 1, "progression : mission 4 terminée, réputation Comité des fêtes")
	world.queue_free()
	await frames(5)

	# --- Fin ratée : agneau carbonisé ---------------------------------------------------------------------------------------
	check(await boot(), "second monde")
	await take_all_items()
	place(mission.station() + Vector3(0.5, 0, 0.5))
	var g2 := 0
	while mission.step == "fire" and g2 < 4000:
		g2 += 1
		place(mission.station() + Vector3(0.5, 0, 0.5))
		mission.interact(1)      # on attise sans cesse : la chaleur reste au maximum
		await physics_frame
	check(mission.step == "failed" and mission.result == "burnt", "attiser sans cesse : agneau carbonisé (%d images)" % g2)
	world.queue_free()
	await frames(5)

	# --- Fin ratée : en retard ---------------------------------------------------------------------------------------------------
	check(await boot(), "troisième monde")
	mission.setup_left = 0.2
	await frames(30)
	check(mission.step == "failed" and mission.result == "late", "matériel en retard : échec")
	world.queue_free()
	await frames(5)

	# --- Défaite : fête médiocre -------------------------------------------------------------------------------------------------------
	check(await boot(), "quatrième monde")
	await take_all_items()
	mission.cook = 0.999
	mission.burn = 0.9
	mission.heat = 0.6
	await frames(10)
	check(mission.step == "serve", "agneau (très) brûlé mais cuit : le service")
	mission.serve_left = 0.1
	await frames(20)
	check(mission.step == "bonfire", "temps écoulé : direction le bûcher")
	place(mission.zones.bucher + Vector3(1.5, 0, 1.5))
	mission.interact(1)
	await frames(5)
	check(mission.step == "done" and mission.result == "lose" and mission.medal == "", "fête médiocre : défaite sans médaille (%.0f %%)" % mission.satisfaction)

	print("--- m04_flow : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
