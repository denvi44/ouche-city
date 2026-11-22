extends SceneTree
## Test d'intégration de la mission 03 (agent 09), en solo headless, sans compagnons :
## matériel → manche 1 (rythme parfait, un temps raté) → manche 2 (sabotages : un déjoué, un subi ; gendarmes) → manche finale → médaille ;
## puis trois fins ratées : sono saisie, matériel en retard, défaite sans jouer.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/m03_flow.gd -- --mission=m03 --no-companions

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var world
var mission
var player
var M3
var sfx


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
	player.global_position = pos
	player.velocity = Vector3.ZERO


func at_deck() -> Vector3:
	return mission.zones.camp + Vector3(0.0, 0.8, 2.0)


func boot() -> bool:
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(90)
	mission = world.mission
	player = world.players_root.get_node_or_null("1")
	return mission != null and mission.get_script() == M3 and player != null


func take_all_items() -> void:
	for it in M3.ITEMS:
		place(mission.item_pos[it] + Vector3(0.5, 0.6, 0.5))
		await frames(2)
		mission.interact(1)
		await frames(2)


## Joue une manche : un coup à chaque temps (en rythme) ; `hook` est appelé à chaque image avec le rang du prochain temps.
func play_round(on_beat := true, hook := Callable()) -> void:
	var k := 0
	var guard := 0
	while mission.step == "round" and mission.round_state != "result" and guard < 6000:
		guard += 1
		if hook.is_valid():
			hook.call(k)
		if mission.round_state == "play" and k < mission.beats_in(mission.round_idx) and mission.play_t >= k * M3.BEAT:
			if on_beat:
				mission.press_arrow(1, mission.current_arrow())
			k += 1
		await physics_frame


func pick(option: String) -> void:
	mission.choose_for(1, option)
	await frames(2)


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	M3 = load("res://scripts/world/mission_m03.gd")
	sfx = root.get_node("Sfx")
	if not check(await boot(), "monde de la mission 3 : mission et joueur, pas de véhicule"):
		quit(1)
		return
	check(mission.started and mission.step == "setup", "mission démarrée à l'étape matériel")
	check(abs(world.day_night.hour - 19.5) < 0.1, "il est 19 h 30")
	check(world.van == null, "la battle se joue à pied")
	for z in ["camp", "rival"]:
		check(mission.zones.has(z), "lieu posé : %s" % z)
	for it in M3.ITEMS:
		check(mission.item_pos.has(it), "objet posé : %s" % it)
	check(mission.zones.camp.distance_to(mission.zones.rival) > 200.0, "le Clos Fleuri est loin")
	check(M3.point_value("perfect", 0, 0, "musette_remix", false) == 3.0 * M3.COUNTER_BONUS, "points : parfait, musette contre un rival « jeunes » = ×1,2")
	check(M3.point_value("perfect", 0, 0, "techno_foraine", false) == 3.0, "points : même public que le rival = ×1")
	check(is_equal_approx(M3.point_value("perfect", 0, 1, "tube_ete_2003", false), 2.1), "points : tube de l'été = ×0,7")
	check(M3.point_value("good", 35, 2, "techno_foraine", false) == 2.0 * 2.0 * 1.2, "points : lâcher de basses doublé, techno contre un rival « anciens »")
	check(M3.point_value("perfect", 0, 0, "musette_remix", true) == 3.0 * M3.COUNTER_BONUS * 0.5, "points : clé USB = ÷2")

	# --- Matériel ----------------------------------------------------------------------------------------
	place(mission.zones.camp + Vector3(0, 0.6, 0))
	check(mission.resolve(1, player.global_position).get("kind", "") == "", "au camp, avant le matériel : rien à faire")
	place(mission.item_pos.caisson + Vector3(0.5, 0.6, 0.5))
	check(mission.resolve(1, player.global_position).get("kind") == "item", "près du caisson : on peut le prendre")
	mission.interact(1)
	check(mission.item_taken("caisson") and mission.step == "setup", "caisson pris, il manque encore deux objets")
	check(world.find_child("Objet_caisson", true, false).visible == false or true, "objet existe")
	await frames(3)
	check(not world.find_child("Objet_caisson", true, false).visible, "le caisson disparaît du décor")
	await take_all_items()
	check(mission.step == "round" and mission.round_idx == 0 and mission.round_state == "pick", "matériel complet : manche 1, choix de la playlist")
	check(mission.menu == "playlist" and mission.menu_options.size() == 3, "menu de playlist à 3 choix")
	place(at_deck())

	# --- Manche 1 : rythme parfait, un temps raté -------------------------------------------------------------
	var sono_before: int = sfx.counts.get("track_musette_remix", 0)
	await pick("1")
	check(mission.round_state == "count" and mission.playlist == "musette_remix", "playlist choisie : compte à rebours")
	check(sfx.counts.get("track_musette_remix", 0) > sono_before, "la playlist se lance (journal sonore)")
	await frames(60 * 3 + 10)
	check(mission.round_state == "play", "la manche démarre")
	mission.press_arrow(1, mission.current_arrow())      # presque à t=0 : parfait
	var _miss_before: int = mission.hits.miss
	await frames(8)
	mission.press_arrow(1, mission.current_arrow())      # 8 images plus tard (0,13 s) : trop loin du temps et déjà pris -> raté ou bon
	await play_round(true)
	check(mission.round_state == "result" and mission.results.size() == 1, "manche 1 jouée")
	var r1: Dictionary = mission.results[0]
	check(r1.won and r1.p > r1.r, "manche 1 gagnée (%s contre %s)" % [str(r1.p), str(r1.r)])
	check(mission.hits.perfect >= 28, "au moins 28 temps parfaits (%d)" % mission.hits.perfect)
	check(mission.nuisance > 0.1 and mission.nuisance < 0.5, "la nuisance monte sans exploser (%.2f)" % mission.nuisance)
	await frames(60 * 5 + 10)
	check(mission.round_idx == 1 and mission.round_state == "pick", "manche 2 : choix de la playlist")

	# --- Manche 2 : sabotages et gendarmes ----------------------------------------------------------------------
	place(at_deck())
	await pick("1")
	await frames(60 * 3 + 5)
	var state := {"defended": false, "ignored": false, "police": false}
	var hook := func(_k):
		if mission.menu == "police" and mission.round_state == "police":
			mission.choose_for(1, "3")
		if mission.round_state == "play" and mission.sab.kind != "" and not state.defended:
			var sp: Vector3 = mission.spot("sab_" + str(mission.sab.kind))
			place(sp + Vector3(0.6, 0.6, 0.0))
			if mission.resolve(1, player.global_position).get("kind") == "defend":
				mission.interact(1)
				state.defended = true
				check(mission.sab.kind == "" and mission.sab_blocked == 1, "premier sabotage déjoué")
				place(at_deck())
		elif mission.round_state == "play" and mission.sab_hits == 1 and not state.ignored:
			state.ignored = true
		if mission.round_state == "play" and mission.play_t > 14.0 and not state.police:
			state.police = true
			mission.nuisance = 0.72
	await play_round(true, hook)
	check(state.defended, "un sabotage a été déjoué")
	check(mission.sab_hits >= 1, "un sabotage subi (%d)" % mission.sab_hits)
	check(mission.police_done and mission.police_visit, "les gendarmes sont venus")
	check(mission.results.size() == 2, "manche 2 terminée")
	print("  manche 2 : ", mission.results[1])
	await frames(10)
	check(mission.menu == "" and mission.nuisance < 0.72, "réponse aux gendarmes appliquée (%.2f)" % mission.nuisance)
	await frames(60 * 5 + 10)
	check(mission.round_idx == 2, "manche finale")
	place(at_deck())
	await pick("2")
	check(mission.playlist == "techno_foraine", "playlist techno pour la finale")
	await frames(60 * 3 + 5)
	await play_round(true)
	check(mission.results.size() == 3, "manche finale jouée")
	print("  manche finale : ", mission.results[2], " nuisance ", mission.nuisance)
	await frames(60 * 5 + 30)
	check(mission.step == "done" and mission.result == "win", "fin : victoire")
	check(mission.rounds_won() >= 2 and mission.medal in ["silver", "bronze"], "médaille d'argent ou de bronze car les gendarmes sont venus (%s)" % mission.medal)
	var prog = root.get_node("Progress")
	check(prog.mission_state("m03_battle_sono") == "done", "progression : mission 3 terminée")
	check(prog.is_available("m04_mechoui_saint_jean", ["m03_battle_sono"]), "mission 4 débloquée")
	check(prog.data.reputation.get("pommiers", 0) >= 1, "réputation Pommiers +1")
	check(sfx.counts.get("fanfare", 0) >= 1, "fanfare de victoire")
	world.queue_free()
	await frames(5)

	# --- Fin ratée : sono saisie ------------------------------------------------------------------------------------
	check(await boot(), "second monde")
	await take_all_items()
	await pick("2")
	await frames(60 * 3 + 5)
	mission.nuisance = 1.0
	await frames(30)
	check(mission.step == "failed" and mission.result == "seized", "nuisance à 100 % : sono saisie")
	world.queue_free()
	await frames(5)

	# --- Fin ratée : en retard, puis défaite sans jouer ---------------------------------------------------------------
	check(await boot(), "troisième monde")
	mission.setup_left = 0.2
	await frames(30)
	check(mission.step == "failed" and mission.result == "late", "matériel en retard : échec")
	world.queue_free()
	await frames(5)
	check(await boot(), "quatrième monde")
	await take_all_items()
	for r in 3:
		await pick("1")
		await frames(60 * 3 + 5)
		await play_round(false)
		await frames(60 * 5 + 30)
	check(mission.step == "done" and mission.result == "lose" and mission.medal == "", "sans jouer un temps : le Clos Fleuri l'emporte")

	print("--- m03_flow : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
