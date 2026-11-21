extends SceneTree
## Audit du HUD des sept missions (agent 09) : à plusieurs moments de chaque mission, les jauges et les balises sont valides
## (identifiants uniques, valeurs 0..1, couleurs, libellés non vides, positions finies, plages cohérentes), la consigne existe.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/hud_audit.gd

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


func valid_gauges(gs: Array) -> String:
	var ids := {}
	for g in gs:
		if not (g is Dictionary) or not g.has("id") or not g.has("value") or not g.has("color") or not g.has("label"):
			return "jauge mal formée : %s" % str(g)
		if ids.has(g.id):
			return "identifiant en double : %s" % g.id
		ids[g.id] = true
		if not (float(g.value) >= 0.0 and float(g.value) <= 1.0) or is_nan(float(g.value)):
			return "valeur hors 0..1 : %s = %s" % [g.id, str(g.value)]
		if str(g.label) == "":
			return "libellé vide : %s" % g.id
		if g.has("zone") and not (g.zone.x >= 0.0 and g.zone.y <= 1.0 and g.zone.x <= g.zone.y):
			return "plage incohérente : %s %s" % [g.id, str(g.zone)]
	return ""


func valid_markers(ms: Array) -> String:
	for m in ms:
		if not (m is Dictionary) or not m.has("pos") or not m.has("label") or not m.has("color"):
			return "balise mal formée : %s" % str(m)
		var p: Vector3 = m.pos
		if is_nan(p.x) or is_nan(p.z) or absf(p.x) > 1e5 or absf(p.z) > 1e5:
			return "position invalide : %s" % str(m)
		if str(m.label) == "":
			return "libellé vide"
	return ""


func audit(key: String, id: String, mutate: Callable) -> void:
	var net = root.get_node("Net")
	net.mission_id = key
	var world = load(WORLD).instantiate()
	root.add_child(world)
	for i in 100:
		await physics_frame
	var m = world.mission
	check(m != null and m.dialogue_prefix() == key, "%s : mission chargée" % id)
	var seen_gauges := 0
	var seen_markers := 0
	for phase in 4:
		mutate.call(m, world, phase)
		for i in 20:
			await physics_frame
		var gs: Array = m.hud_gauges()
		var ms: Array = m.hud_markers()
		var e1 := valid_gauges(gs)
		var e2 := valid_markers(ms)
		check(e1 == "", "%s, phase %d : %d jauge(s) valides %s" % [id, phase, gs.size(), e1])
		check(e2 == "", "%s, phase %d : %d balise(s) valides %s" % [id, phase, ms.size(), e2])
		check(str(m.objective()) != "" or m.step in ["done", "failed"], "%s, phase %d : consigne présente (étape %s)" % [id, phase, m.step])
		check(m.hud_lines().size() >= 2, "%s, phase %d : titre et consigne dans hud_lines" % [id, phase])
		seen_gauges += gs.size()
		seen_markers += ms.size()
	check(seen_gauges >= 4 and seen_markers >= 2, "%s : jauges (%d) et balises (%d) présentes sur le parcours" % [id, seen_gauges, seen_markers])
	world.queue_free()
	for i in 5:
		await physics_frame


func _run() -> void:
	create_timer(500.0).timeout.connect(func(): printerr("ÉCHEC délai dépassé"); quit(2))
	await audit("m01", "m01", func(m, w, ph):
		if ph == 1:
			for id in m.crates:
				m.crates[id].state = "loaded"
			m.step = "road"
		if ph == 2:
			m.step = "checkpoint"
		if ph == 3:
			m.step = "fair")
	await audit("m02", "m02", func(m, w, ph):
		if ph == 1:
			m.parts = ["jantes", "pot", "aileron"]
			m.step = "assembly"
			m.assembly_total = 3
		if ph == 2:
			m.step = "test_drive"
			m.cp_total = 4
		if ph == 3:
			m.step = "drag"
			m.race_state = "go"
			m.race_sp = 120.0
			m.race_sd = 140.0)
	await audit("m03", "m03", func(m, w, ph):
		if ph == 1:
			for it in m.ITEMS:
				m.items_taken.append(it)
			m._begin_round(0)
			m._choose_playlist("musette_remix")
			m.count_left = 0.0
			m.round_state = "play"
		if ph == 2:
			m.nuisance = 0.8
			m.play_t = 3.3
			m.sab = {"kind": "poules", "left": 4.0}
		if ph == 3:
			m.step = "done")
	await audit("m04", "m04", func(m, w, ph):
		if ph == 1:
			for it in m.ITEMS:
				m.items_taken.append(it)
			m.step = "fire"
			m.heat = 0.6
			m.cook = 0.4
			m.burn = 0.2
		if ph == 2:
			m.step = "serve"
			m.served = [2, 1, 0, 0]
		if ph == 3:
			m.step = "bonfire")
	await audit("m05", "m05", func(m, w, ph):
		if ph == 1:
			m.cows[0].st = "pen"
			m.cows[1].st = "pen"
		if ph == 2:
			for c in m.cows:
				c.st = "pen"
			m.step = "gate"
		if ph == 3:
			m.step = "done")
	await audit("m06", "m06", func(m, w, ph):
		if ph == 1:
			m.items_got = ["baguette", "lait"]
			m.reading = {"peer": 1, "item": "cidre", "t": 1.0}
			m._spawn_customer()
			m.customers[0].imp = 0.6
		if ph == 2:
			m.reading = {}
			m.items_got = m.ITEMS.duplicate()
			m.step = "pay"
		if ph == 3:
			m.step = "exit")
	await audit("m07", "m07", func(m, w, ph):
		if ph == 1:
			m.victims[1].p = 0.75
			m.victims[1].cl = true
		if ph == 2:
			m.victims[1].fz = "queue"
			m.victims[1].ft = 5.0
		if ph == 3:
			m.victims[1].fz = ""
			m.victims[1].p = 0.9)
	print("--- hud_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
