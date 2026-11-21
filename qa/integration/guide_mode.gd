extends SceneTree
## Compagnons guides (solo par défaut) : ils accompagnent le joueur immobile sans jamais agir sur la mission (aucun objet pris, aucune vache
## rabattue, aucun feu tenu), restent près de lui, et le guide se met en route vers la balise d'objectif puis attend.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/guide_mode.gd
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0


func check(cond: bool, label: String) -> bool:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("ÉCHEC ", label)
	return cond


func _initialize() -> void:
	_run.call_deferred()


func frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	create_timer(900.0).timeout.connect(func(): printerr("ÉCHEC délai"); quit(2))
	root.get_node("Settings").companions_help = false
	var world = null
	for m in ["m01", "m03", "m04", "m05"]:
		if world:
			world.queue_free()
			await frames(5)
		root.get_node("Net").mission_id = m
		world = load(WORLD).instantiate()
		root.add_child(world)
		await frames(80)
		var mission = world.mission
		var player = world.players_root.get_node("1")
		var comps: Array = mission.companions()
		if not check(comps.size() >= 3, "%s : %d compagnons présents" % [m, comps.size()]):
			continue
		var start_step: String = mission.step
		var before: Dictionary = _snapshot(m, mission)
		var p0: Vector3 = player.global_position
		var goal_d0 := _goal_dist(mission, comps[0], p0)
		await frames(75 * 60)                 # 75 s de jeu, le joueur reste immobile
		check(player.global_position.distance_to(p0) < 1.0, "%s : le joueur n'a pas bougé" % m)
		check(_snapshot(m, mission) == before and mission.step == start_step, "%s : les compagnons n'ont rien fait dans la mission (%s)" % [m, str(_snapshot(m, mission))])
		var far := 0
		for c in comps:
			if c.global_position.distance_to(player.global_position) > 30.0:
				far += 1
		check(far <= 1, "%s : les compagnons restent près du joueur (%d trop loin)" % [m, far])
		var statuses: Array = comps.map(func(c): return str(c.brain.status))
		check(statuses.all(func(s): return s.begins_with("te montre") or s.begins_with("t'attend") or s.begins_with("reste près") or s == "attend"), "%s : ils disent qu'ils guident (%s)" % [m, str(statuses)])
		var goal_d1 := _goal_dist(mission, comps[0], p0)
		check(goal_d1 <= goal_d0 + 1.0, "%s : le guide ne s'éloigne pas de la balise (%.0f m → %.0f m)" % [m, goal_d0, goal_d1])
	print("--- guide_mode : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)


## Ce que la mission a enregistré de l'action des compagnons : objets pris, vaches rentrées, sifflets, caisses.
func _snapshot(m: String, mission) -> Dictionary:
	match m:
		"m01":
			return {"charge": mission.step}
		"m03":
			return {"objets": mission.items_taken.size()}
		"m04":
			return {"objets": mission.items_taken.size(), "cuisson": int(mission.cook * 100.0)}
		"m05":
			return {"enclos": mission.penned(), "sifflets": mission.whistles}
	return {}


## Distance du guide (premier compagnon) à la première balise d'objectif.
func _goal_dist(mission, _guide, _p0: Vector3) -> float:
	var marks: Array = mission.focus_markers()
	if marks.is_empty():
		return 0.0
	var g: Vector3 = marks[0].pos
	var best := INF
	for c in mission.companions():
		best = minf(best, Vector2(c.global_position.x - g.x, c.global_position.z - g.z).length())
	return best
