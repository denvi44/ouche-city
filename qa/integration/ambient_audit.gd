extends SceneTree
## Vie ambiante : des passants et des voitures apparaissent autour du joueur dans la limite du budget, jamais dans un bâtiment, les voitures s'arrêtent devant
## le joueur, tout disparaît et renaît quand on s'éloigne, et les véhicules ont leur fumée d'échappement.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/ambient_audit.gd
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var rings: Array = []


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


func _in_building(p: Vector2) -> bool:
	for ring: PackedVector2Array in rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
	return false


func _run() -> void:
	create_timer(500.0).timeout.connect(func(): printerr("ÉCHEC délai"); quit(2))
	var AL = load("res://scripts/world/ambient_life.gd")
	AL.force = true
	# Pures
	check(is_equal_approx(AL.triangle(0.25), 0.5) and is_equal_approx(AL.triangle(0.5), 1.0) and is_equal_approx(AL.triangle(1.0), 0.0) and is_equal_approx(AL.triangle(1.75), 0.5), "va-et-vient : triangle 0 → 1 → 0")
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var sm: Array = AL.sample(pts, 15.0)
	check((sm[0] as Vector2).distance_to(Vector2(10, 5)) < 1e-4 and (sm[1] as Vector2).distance_to(Vector2(0, 1)) < 1e-4, "polyligne : point et direction à 15 m")
	var ns: Vector2 = AL.nearest_s(pts, Vector2(4, 3))
	check(absf(ns.x - 4.0) < 1e-4 and absf(ns.y - 3.0) < 1e-4, "polyligne : point le plus proche (s = 4, d = 3)")
	# Monde
	var manifest = CityBuilder.read_json("res://assets/city/manifest.json")
	for key in manifest.tiles:
		var t = CityBuilder.read_json("res://assets/city/tiles/%s.json" % key)
		for b in t.buildings:
			var ring := PackedVector2Array()
			for q in b.footprint:
				ring.append(Vector2(float(q[0]), float(q[1])))
			rings.append(ring)
	root.get_node("Settings").ambient_life = true
	root.get_node("Net").mission_id = "m01"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(60)
	var life = world.get_node_or_null("VieAmbiante")
	if not check(life != null, "la vie ambiante est présente"):
		quit(1)
		return
	for c in world.players_root.get_children():
		if c.peer_id < 0:
			c.brain = null
			c.global_position = Vector3(0, -500, 0)
			c.set_physics_process(false)
	await frames(60 * 10)
	check(life.peds.size() >= 6 and life.peds.size() <= life.PED_MAX, "passants : %d (budget %d)" % [life.peds.size(), life.PED_MAX])
	check(life.cars.size() >= 1 and life.cars.size() <= life.CAR_MAX, "voitures : %d (budget %d)" % [life.cars.size(), life.CAR_MAX])
	# Jamais dans un bâtiment (échantillons répétés pendant 30 s).
	var dans := 0
	var total := 0
	for k in 30:
		await frames(60)
		for p in life.peds:
			total += 1
			var q: Vector2 = life._ped_pos(p)
			if _in_building(q):
				dans += 1
		for c in life.cars:
			total += 1
			if _in_building(life._car_pos(c)[0]):
				dans += 1
	check(total > 100 and dans <= int(total * 0.01), "aucun figurant dans un bâtiment (%d sur %d échantillons)" % [dans, total])
	# Les passants marchent vraiment (leur position change).
	var group: Array = life.peds.slice(0, 6)
	var before: Array = group.map(func(q): return life._ped_pos(q))
	await frames(120)
	var moved := 0.0
	for i in group.size():
		moved += life._ped_pos(group[i]).distance_to(before[i])
	check(moved / group.size() > 1.0, "les passants avancent (%.1f m en 2 s en moyenne)" % (moved / group.size()))
	# Une voiture s'arrête devant le joueur.
	var car = life.cars[0]
	var player = world.players_root.get_node("1")
	var pd: Array = life._car_pos(car)
	var ahead: Vector2 = (pd[0] as Vector2) + (pd[1] as Vector2) * 6.0
	player.global_position = Vector3(ahead.x, world.builder.height_at(ahead.x, ahead.y) + 1.0, ahead.y)
	player.velocity = Vector3.ZERO
	await frames(60 * 4)
	check(float(car.speed) < 0.5 or not life.cars.has(car), "la voiture s'arrête devant le joueur (%.1f m/s)" % float(car.speed))
	# Éloignement : tout renaît autour du joueur.
	player.global_position = world.spawn_point + Vector3(0, 0, 600)
	player.velocity = Vector3.ZERO
	await frames(60 * 12)
	var f := Vector2(player.global_position.x, player.global_position.z)
	var near := 0
	for p in life.peds:
		if life._ped_pos(p).distance_to(f) < life.PED_OUT:
			near += 1
	check(life.peds.size() == 0 or near == life.peds.size(), "après un grand déplacement, les passants sont autour du joueur (%d)" % life.peds.size())
	# Fumée d'échappement : camionnette moteur allumé.
	var van = world.van
	var ex = van.get_node_or_null("Visuel/Caisse/Echappement")
	check(ex != null and ex is ExhaustFx, "la camionnette a un pot d'échappement")
	van.engine_on = true
	van.speed = 6.0
	await frames(20)
	check(ex.emitting, "le pot fume quand le moteur tourne")
	van.engine_on = false
	van.speed = 0.0
	await frames(20)
	check(not ex.emitting, "le pot ne fume plus moteur coupé")
	# Désactivation.
	life.set_enabled(false)
	await frames(5)
	check(life.peds.is_empty() and life.cars.is_empty(), "désactivée : plus aucun figurant")
	print("--- ambient_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
