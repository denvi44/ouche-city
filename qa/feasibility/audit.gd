extends SceneTree
## Audit de faisabilité des missions (agent 09) : un « joueur automate » joue les missions à pied avec la vraie physique, les vraies
## vitesses (marche, sprint, plafonds de mission) et des réflexes humains (délai de réaction), puis on compare au temps imparti.
## Les missions en véhicule et les jeux de timing sont évalués par des calculs sur les vraies données de la carte.
## Sortie : lignes « [faisabilité] mission | scénario | résultat | temps | limite | marge » + un échec par scénario infaisable.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/feasibility/audit.gd -- [--only=m06] [--companions] [--report=chemin.md]

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
const REACTION := 0.35                 # s : délai de réaction humain avant une action
var fails := 0
var rows: Array = []
var with_companions := false
var only := ""
var world
var mission
var player
var walker: Walker


## Pilote : va tout droit vers un point (allées, champs) ou suit le graphe routier (via le cerveau des compagnons).
class Walker:
	extends RefCounted
	var player: Node
	var brain
	var target := Vector3.ZERO
	var use_nav := false
	var sprint_far := true
	var sprint_force := -1               # -1 auto, 0 jamais, 1 toujours
	var look_at_override := Vector3.ZERO

	func input(delta: float) -> Dictionary:
		if target == Vector3.ZERO:
			return brain.idle()
		var pos: Vector3 = player.global_position
		var d := Vector2(target.x - pos.x, target.z - pos.z)
		if d.length() < 0.15:
			return brain.idle()
		var inp: Dictionary
		if use_nav:
			inp = brain._walk_to(target, delta)
		else:
			inp = {"move": Vector2(0, -1), "yaw": atan2(-d.x, -d.y), "jump": false, "sprint": sprint_far and d.length() > 8.0}
		if sprint_force == 0:
			inp.sprint = false
		elif sprint_force == 1:
			inp.sprint = true
		if look_at_override != Vector3.ZERO:
			var l := Vector2(look_at_override.x - pos.x, look_at_override.z - pos.z)
			inp.yaw = atan2(-l.x, -l.y)
		return inp

	func stop() -> void:
		target = Vector3.ZERO


func check(cond: bool, label: String) -> bool:
	if not cond:
		fails += 1
		printerr("ÉCHEC ", label)
	return cond


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func record(mission_id: String, scenario: String, ok: bool, result: String, t: float, limit: float, note := "") -> void:
	var margin := (limit - t) / limit * 100.0 if limit > 0.0 else 100.0
	rows.append({"mission": mission_id, "scenario": scenario, "ok": ok, "result": result, "time": t, "limit": limit, "margin": margin, "note": note})
	print("[faisabilité] %s | %s | %s | %s | %.0f s | limite %.0f s | marge %d %% %s" % [mission_id, scenario, "OK" if ok else "INFAISABLE", result, t, limit, int(margin), note])
	check(ok, "%s : %s (%s, %.0f s sur %.0f s)" % [mission_id, scenario, result, t, limit])


func boot(key: String, companions: bool) -> void:
	var net = root.get_node("Net")
	net.mission_id = key
	root.get_node("Settings").companions_help = companions      # « avec compagnons » = mode coéquipiers ; sinon ils ne font que guider
	world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(100)
	mission = world.mission
	player = world.players_root.get_node("1")
	player.collision_mask = 1                  # le bot ne contourne pas le mobilier de rue (un humain le fait) : il ne le heurte pas
	var BrainC = load("res://scripts/ai/companion_brain.gd")
	var nav = load("res://scripts/ai/road_nav.gd").load_default()
	walker = Walker.new()
	walker.player = player
	walker.brain = BrainC.new(player, mission, nav, "audit")
	player.bot_input = Callable(walker, "input")
	if not companions:
		for c in world.players_root.get_children():
			if c.peer_id < 0:
				c.brain = null
				c.global_position = Vector3(0, -500, 0)
				c.set_physics_process(false)
	await frames(10)


func shutdown() -> void:
	player.bot_input = Callable()
	world.queue_free()
	await frames(5)


## Marche jusqu'à un point (jusqu'à `radius` m) ; renvoie faux si le délai expire (bloqué).
func go(p: Vector3, radius := 0.8, timeout := 400.0, nav := false) -> bool:
	walker.target = p
	walker.use_nav = nav
	var t := 0.0
	while t < timeout:
		var d := Vector2(player.global_position.x - p.x, player.global_position.z - p.z).length()
		if d < radius:
			walker.stop()
			return true
		await physics_frame
		t += 1.0 / 60.0
		if mission.step in ["done", "failed"]:
			walker.stop()
			return false
	walker.stop()
	return false


func react() -> void:
	await frames(int(REACTION * 60.0 * randf_range(0.7, 1.3)))


# --- Mission 06 : les courses à 2 km/h ---------------------------------------------------------------------------------------

## Tournée optimisée (l'ordre qu'un client malin choisirait), en repère local du magasin.
const M6_TOUR := [
	["litiere", [Vector2(0, 6.5), Vector2(0, 4.0)]],
	["baguette", [Vector2(10.5, 3.5), Vector2(10.5, -6.6)]],
	["lait", []],
	["camembert", []],
	["cidre", [Vector2(-10.5, -6.6), Vector2(-10.5, -3.0)]],
	["palets", [Vector2(-10.5, -3.0), Vector2(-10.5, 0.25)]],
]


func m6_walk_local(pts: Array) -> void:
	for l in pts:
		await go(mission.to_world(l), 0.7, 120.0)


func scenario_m06() -> void:
	await boot("m06", false)
	var t0 := Time.get_ticks_msec()
	await m6_walk_local([Vector2(0, 9.5), Vector2(0, 6.5)])
	for step in M6_TOUR:
		await m6_walk_local(step[1])
		var spot: Vector3 = mission.item_world(step[0])
		await go(spot, 0.9, 120.0)
		await react()
		# La file : on laisse passer quand elle s'impatiente ; Mme Hubert : on coupe court.
		var guard := 0
		while not (step[0] in mission.items_got) and guard < 6000 and mission.step == "shop":
			guard += 1
			var r: Dictionary = mission.resolve(1, player.global_position)
			if r.get("kind") == "read" and mission.reading.is_empty():
				mission.interact(1)
			elif r.get("kind") == "cut":
				await react()
				mission.interact(1)
			await physics_frame
	if mission.step == "shop":
		# Vers la caisse : par le couloir ouest puis le hall.
		await m6_walk_local([Vector2(-10.5, 0.25), Vector2(-10.5, 3.5), Vector2(0, 4.6), mission.PAY_SPOT])
		await react()
		mission.interact(1, ["pay"])
		var guard2 := 0
		while mission.step == "pay" and guard2 < 6000:
			guard2 += 1
			var p: float = mission.mini_pos()
			# Un humain vise le centre avec une erreur de ±60 ms (écart-type) : on appuie dès que le curseur est à moins de δ du centre.
			if absf(p - 0.5) < absf(randfn(0.0, 0.085)) + 0.02:
				mission.interact(1)
				await frames(40)
			await physics_frame
		if mission.step == "exit":
			await m6_walk_local([Vector2(0, 4.6), Vector2(0, 6.5)])
			await go(mission.to_world(mission.DOOR_SPOT), 1.2, 60.0)
			mission.interact(1, ["leave"])
	await frames(5)
	var t := float(mission.elapsed)
	var gold_s: float = (mission.deadline.gold - mission.START_MIN) * mission.secs_per_min
	var bronze_s: float = (mission.deadline.bronze - mission.START_MIN) * mission.secs_per_min
	record("m06", "tournée optimisée, joueur seul, 2 km/h", mission.step == "done" and mission.result == "win", "médaille %s, %d incident(s), sortie à %s" % [mission.medal if mission.medal != "" else "aucune", mission.incidents, mission.clock_text(mission.clock_min)], t, bronze_s, "or avant %d s" % int(gold_s))
	record("m06", "médaille d'or atteignable", mission.medal == "gold", "médaille %s" % mission.medal, t, gold_s)
	await shutdown()


# --- Mission 05 : rabattre huit vaches --------------------------------------------------------------------------------------------------

func scenario_m05(companions: bool) -> void:
	await boot("m05", companions)
	var real_limit: float = mission.time_limit
	mission.time_left = 1500.0          # on mesure la durée réelle, puis on la compare à la limite du JSON
	await frames(30)
	var pen: Vector3 = mission.zones.pen
	var whistle_t := 0.0
	var guard := 0
	while mission.step == "herd" and guard < 60 * 475:
		guard += 1
		whistle_t -= 1.0 / 60.0
		var here := Vector2(player.global_position.x, player.global_position.z)
		var tgt: Vector3 = mission.herd_target(here)
		if tgt == Vector3.ZERO:
			await physics_frame
			continue
		var stray: Dictionary = mission.nearest_stray(Vector2(pen.x, pen.z))
		var near := Vector2(player.global_position.x - tgt.x, player.global_position.z - tgt.z).length() < 3.0
		if near:
			walker.target = Vector3(stray.x, tgt.y, stray.z)
			walker.sprint_force = 0
		else:
			walker.target = tgt
			walker.sprint_force = -1
		if whistle_t <= 0.0 and Vector2(stray.x, stray.z).distance_to(here) < mission.whistle_range - 2.0:
			await react()
			mission.interact(1, ["whistle"])
			whistle_t = 3.2
		await physics_frame
	walker.stop()
	if mission.step == "gate":
		await go(mission._front(Vector3(0, 0, mission.PEN_HALF + 1.0)), 1.5, 60.0)
		mission.interact(1, ["close"])
	await frames(5)
	var t: float = 1500.0 - mission.time_left
	record("m05", "joueur %s : 8 vaches rabattues à la main" % ("avec compagnons" if companions else "seul"), mission.penned() >= 8 and t <= real_limit, "%d/8 vaches en %.0f s" % [mission.penned(), t], t, real_limit, "or = 8 vaches avant la limite")
	await shutdown()


# --- Mission 07 : jusqu'aux toilettes ------------------------------------------------------------------------------------------------------

func scenario_m07(policy: String, companions: bool) -> void:
	await boot("m07", companions)
	await frames(30)
	var door: Vector3 = mission._front_point("door", 1.0)
	var guard := 0
	var m7: Dictionary = {}
	while mission.step == "run" and guard < 60 * 200:
		guard += 1
		var v: Dictionary = mission.victims[1]
		# Politique : « courir » (sprint permanent), « marcher », « malin » (serrer quand la pression dépasse 55 %, relâcher à 35 %).
		walker.sprint_force = 1 if policy in ["courir", "malin"] else 0
		if policy == "malin":
			if not bool(v.cl) and float(v.p) > 0.55 and float(v.st) > 0.3 and float(v.rel) <= 0.0:
				mission.interact(1, ["clench"])
			elif bool(v.cl) and (float(v.p) < 0.35 or float(v.st) < 0.1):
				mission.interact(1, ["clench"])
		# Retenu ou arrivé : on agit.
		var r: Dictionary = mission.resolve(1, player.global_position)
		if r.get("kind") == "cut":
			await react()
			mission.interact(1, ["cut"])
		elif r.get("kind") == "search":
			mission.interact(1, ["search"])
		elif r.get("kind") == "enter":
			mission.interact(1, ["enter"])
		elif str(v.fz) == "":
			walker.target = door if mission.door_open or at_door() else door
			walker.use_nav = true
		await physics_frame
	walker.stop()
	var t := float(mission.elapsed)
	var ok: bool = mission.step == "done" and mission.result == "home"
	record("m07", "politique « %s »%s" % [policy, ", avec compagnons" if companions else ", seul"], ok, "%s, pression à l'arrivée %d %%, médaille %s" % [mission.result if mission.result != "" else mission.step, int(mission.best_pressure * 100.0), mission.medal if mission.medal != "" else "aucune"], t, mission.time_limit, "trajet %d m" % int(mission.route_len))
	m7["ok"] = ok
	await shutdown()


func at_door() -> bool:
	return Vector2(player.global_position.x - mission.zones.door.x, player.global_position.z - mission.zones.door.z).length() < 3.0


# --- Mission 04 : le méchoui seul -----------------------------------------------------------------------------------------------------------------

func scenario_m04() -> void:
	await boot("m04", false)
	for it in mission.ITEMS:
		await go(mission.item_pos[it] + Vector3(0.6, 0, 0.6), 1.5, 120.0, true)
		await react()
		mission.interact(1, ["item"])
		await frames(5)
	var st: Vector3 = mission.station()
	await go(st + Vector3(0.8, 0, 0.8), 1.5, 120.0, true)
	var guard := 0
	var pump_t := 0.0
	while mission.step == "fire" and guard < 60 * 475:
		guard += 1
		pump_t -= 1.0 / 60.0
		var r: Dictionary = mission.resolve(1, player.global_position)
		if r.get("kind") == "shoo":
			await frames(int(REACTION * 60.0 * 0.7))
			mission.interact(1, ["shoo"])
		elif float(mission.heat) < 0.55 and pump_t <= 0.0:
			mission.interact(1, ["pump"])
			pump_t = 0.35 + randf() * 0.25
		await physics_frame
	# Service : huit allers-retours foyer → tables.
	var served_guard := 0
	while mission.step == "serve" and served_guard < 60 * 200:
		served_guard += 1
		if not mission.is_carrying(1) and mission.plates_left > 0:
			await go(st + Vector3(0, 0, 0.5), 2.5, 30.0, false)
			mission.interact(1, ["take"])
		elif mission.is_carrying(1):
			var tbl := -1
			for i in 4:
				if int(mission.served[i]) < mission.per_table:
					tbl = i
					break
			if tbl >= 0:
				await go(mission.table_pos(tbl), 2.5, 30.0, false)
				mission.interact(1, ["serve"])
		else:
			break
		await physics_frame
	if mission.step == "bonfire":
		await go(mission.zones.bucher + Vector3(1.5, 0, 1.5), 3.0, 120.0, true)
		mission.interact(1, ["light"])
	await frames(5)
	record("m04", "joueur seul : matériel, feu (réflexes humains), chiens, service, bûcher", mission.step == "done" and mission.result == "win", "satisfaction %d %%, médaille %s, gigots volés %d, brûlé %d %%" % [int(mission.satisfaction), mission.medal if mission.medal != "" else "aucune", mission.stolen, int(mission.burn * 100.0)], float(mission.elapsed), mission.SETUP_TIME + 60.0 + mission.SERVE_TIME + 120.0, "durée totale")
	await shutdown()



# --- Missions 01, 02, 03 : calculs sur les vraies données de la carte --------------------------------------------------------------------

func nav_len(nav, a: Vector3, b: Vector3) -> float:
	return load("res://scripts/ai/road_nav.gd").length_of(nav.find_path(Vector2(a.x, a.z), Vector2(b.x, b.z)))


func numeric_m01() -> void:
	await boot("m01", false)
	await frames(60)
	var nav = load("res://scripts/ai/road_nav.gd").load_default()
	var vnav = load("res://scripts/ai/road_nav.gd").load_default(true)
	var van: Vector3 = mission.van.global_position
	# Caisses : un aller-retour à pied par caisse, en sprintant les deux tiers du temps (6 m/s à vide, 70 % de cela chargé), 2 s de chargement.
	var crates_t := 0.0
	for id in mission.crates:
		var d: float = nav_len(nav, van, mission.crates[id].pos)
		crates_t += d / 6.0 + d / (6.0 * 0.7) + 2.0
	var to_barrage: float = nav_len(vnav, van, mission.zones.barrage)
	var to_stand: float = nav_len(vnav, mission.zones.barrage, mission.zones.stand)
	var drive_t := (to_barrage + to_stand) / 7.0                 # 25 km/h de moyenne : conduite douce, cargaison fragile
	var total := crates_t + drive_t + 20.0 + 15.0                # barrage (choix) + remise au stand
	record("m01", "caisses à pied + conduite douce (25 km/h) + barrage + stand", total < mission.time_limit * 0.8, "caisses %.0f s, route %d m = %.0f s" % [crates_t, int(to_barrage + to_stand), drive_t], total, mission.time_limit, "joueur seul, sans compagnon")
	var amax: float = mission.van.max_speed
	record("m01", "vitesse maximale de la camionnette ≥ 15 m/s", amax >= 15.0, "%.1f m/s (%d km/h)" % [amax, int(amax * 3.6)], 0.0, 1.0)
	await shutdown()


func numeric_m02() -> void:
	await boot("m02", false)
	await frames(60)
	var nav = load("res://scripts/ai/road_nav.gd").load_default()
	var vnav = load("res://scripts/ai/road_nav.gd").load_default(true)
	var z: Dictionary = mission.zones
	# Tournée des pièces à pied (sprint 7 m/s) : garage → casse (fouille 6 s) → annonce (marchandage ~10 s) → cour de Dylan → garage.
	var walk := nav_len(nav, z.garage, z.casse) + nav_len(nav, z.casse, z.annonce) + nav_len(nav, z.annonce, z.dylan) + nav_len(nav, z.dylan, z.garage)
	var parts_t := walk / 7.0 + 6.0 + 10.0 + 8.0
	var assembly_t: float = 3.0 * (mission.MINI_TIMEOUT * 0.5) + 6.0
	var td: float = load("res://scripts/ai/road_nav.gd").length_of(mission.td_route) / 11.0 + 6.0
	var race := 17.0 + 12.0
	var total := parts_t + assembly_t + td + race
	var limit: float = (mission.deadline_hour - mission.START_HOUR) * 60.0 / 0.5          # 1 h de jeu = 120 s réelles
	record("m02", "pièces + montage + essai + drag avant 21 h", total < limit * 0.7, "pièces %.0f s, montage %.0f s, essai %.0f s, drag %.0f s" % [parts_t, assembly_t, td, race], total, limit, "6 h de jeu = 12 min réelles")
	var strip_len: float = mission.drag_length
	record("m02", "piste de drag de 400 m libre (test des données)", mission.zones.has("start") and mission.zones.has("finish") and absf(Vector2(z.start.x - z.finish.x, z.start.z - z.finish.z).length() - strip_len) < 1.0, "%.0f m" % Vector2(z.start.x - z.finish.x, z.start.z - z.finish.z).length(), 0.0, 1.0)
	await shutdown()


func numeric_m03() -> void:
	await boot("m03", false)
	await frames(60)
	var nav = load("res://scripts/ai/road_nav.gd").load_default()
	var spawn: Vector3 = player.global_position
	var pts := [spawn]
	for it in mission.ITEMS:
		pts.append(mission.item_pos[it])
	pts.append(mission.zones.camp)
	var walk := 0.0
	for i in pts.size() - 1:
		walk += nav_len(nav, pts[i], pts[i + 1])
	var setup_t := walk / 6.0 + 3.0 * 3.0
	record("m03", "matériel (3 objets) à pied, sprint partiel (6 m/s)", setup_t < mission.setup_left * 0.75, "%d m" % int(walk), setup_t, mission.setup_left, "joueur seul, sans compagnon")
	# Jeu de rythme : Monte-Carlo, l'écart de timing du joueur suit une loi normale de σ ms ; playlists musette / techno / tube.
	var M3 = load("res://scripts/world/mission_m03.gd")
	seed(777)
	for sigma_ms in [40.0, 70.0, 110.0]:
		var wins := 0
		var gold := 0
		var trials := 400
		var worst_nuis := 0.0
		for tr in trials:
			var rounds_won := 0
			var nuis := 0.0
			for r in 3:
				var score := 0.0
				var n: int = M3.ROUND_BEATS[r]
				var best_pl: String = ["musette_remix", "techno_foraine", "musette_remix"][r]    # le public que le rival ne vise pas
				for k in n:
					var err := absf(randfn(0.0, sigma_ms / 1000.0))
					if err <= M3.PERFECT:
						score += M3.point_value("perfect", k, r, best_pl, false)
						nuis += M3.NUISANCE_HIT * 0.75
					elif err <= M3.GOOD:
						score += M3.point_value("good", k, r, best_pl, false)
						nuis += M3.NUISANCE_HIT * 0.75
				nuis += M3.NUISANCE_RATE * (1.3 if best_pl == "techno_foraine" else 1.0) * 0.75 * n * M3.BEAT
				var goal: float = mission.max_points(r) * M3.RIVAL_RATIO[r]
				if score >= goal:
					rounds_won += 1
			if rounds_won >= 2:
				wins += 1
			if rounds_won == 3 and nuis < M3_POLICE():
				gold += 1
			worst_nuis = maxf(worst_nuis, nuis)
		record("m03", "rythme : joueur à ±%d ms, 400 parties simulées" % int(sigma_ms), wins >= trials * (0.5 if sigma_ms >= 100.0 else 0.8), "victoire %d %%, or %d %%, nuisance max %d %%" % [100 * wins / trials, 100 * gold / trials, int(worst_nuis * 100.0)], 0.0, 1.0)
	await shutdown()


# --- Mission 08 : l'oie meneuse, seule ---------------------------------------------------------------------------------------------

## Joueur seul : un cri à la mare, on mène la basse-cour sur la voie et on crie toutes les 2,5 s (rassurer les oies, faire reculer le
## garde-barrière) jusqu'à la fin de la tenue. Les temps de réaction humains sont simulés.
func scenario_m08(companions: bool) -> void:
	await boot("m08", companions)
	var real_limit: float = mission.time_limit
	mission.time_left = 1500.0
	await react()
	mission.interact(1, ["honk"])
	await react()
	var c: Vector3 = mission.spot("crossing")
	# On mène la file : on avance par étapes pour que les oies suivent.
	await go(mission.zones.pond + Vector3(10, 0, 10), 2.0, 30.0)
	await go(c, 1.2, 90.0)
	var t0: float = 1500.0 - mission.time_left
	var guard := 0
	var next_honk := 0.0
	while mission.step in ["gather", "block"] and guard < 60 * 420:
		guard += 1
		next_honk -= 1.0 / 60.0
		if next_honk <= 0.0:
			await react()
			mission.interact(1, ["honk"])
			next_honk = 2.5
		await physics_frame
	var t: float = 1500.0 - mission.time_left
	var ok: bool = mission.step == "done" and mission.result == "win" and t <= real_limit
	record("m08", "joueur %s : oies rassemblées, train bloqué, tenue de %d s" % ["avec compagnons" if companions else "seul", int(mission.hold_required)], ok, "%s, médaille %s, moyenne %.1f oies, cris %d" % [mission.result if mission.result != "" else mission.step, mission.medal if mission.medal != "" else "aucune", mission.avg_blockers, mission.honks], t, real_limit, "tenue %d s" % int(mission.hold_required))
	await shutdown()


func scenario_m09(companions: bool) -> void:
	await boot("m09", companions)
	var real_limit: float = mission.time_limit
	mission.time_left = 1500.0           # le test mesure le temps réel de la tâche ; la limite est celle du JSON
	await react()
	var t_start: float = mission.elapsed
	var guard := 0
	while mission.step == "defend" and guard < 40:
		guard += 1
		var i: int = mission.nearest_stock(player.global_position)
		await go(mission.stocks[i], 1.8, 90.0)
		await react()
		mission.interact(1, ["take"])
		await react()
		await go(mission.spot("catapult"), 0.9, 90.0)
		await react()
		mission.interact(1, ["load"])
	var t: float = mission.elapsed - t_start
	var ok: bool = mission.loaded >= mission.needed and t <= real_limit
	record("m09", "joueur %s : dix camemberts, tir, village sauvé" % ["avec compagnons" if companions else "seul"], ok, "%d camemberts, %d aller-retour" % [mission.loaded, guard], t, real_limit, "flaques de beurre comprises")
	await shutdown()


func want(id: String) -> bool:
	return only == "" or id in only.split(",")


func M3_POLICE() -> float:
	return 0.7


func _run() -> void:
	create_timer(3000.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a == "--companions":
			with_companions = true
	seed(20260108)
	if want("m01"):
		await numeric_m01()
	if want("m02"):
		await numeric_m02()
	if want("m03"):
		await numeric_m03()
	if want("m04"):
		await scenario_m04()
	if want("m05"):
		await scenario_m05(false)
		if with_companions:
			await scenario_m05(true)
	if want("m06"):
		await scenario_m06()
	if want("m07"):
		for pol in ["courir", "marcher", "malin"]:
			await scenario_m07(pol, false)
		if with_companions:
			await scenario_m07("malin", true)
	if want("m08"):
		await scenario_m08(false)
		if with_companions:
			await scenario_m08(true)
	if want("m09"):
		await scenario_m09(false)
	print("--- faisabilité : ", "OK" if fails == 0 else "%d scénario(s) infaisable(s)" % fails)
	quit(1 if fails > 0 else 0)


func _initialize() -> void:
	_run.call_deferred()
