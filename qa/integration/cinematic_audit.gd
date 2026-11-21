extends SceneTree
## Cinématiques : chaque plan se résout (lieux connus), la caméra n'est jamais dans un mur ni derrière un bâtiment qui masque
## le sujet, le lecteur joue réellement une scène complète (travelling, légendes, fondus, passage, rétablissement de la caméra
## et du jeu). Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/cinematic_audit.gd
const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
const IDS := ["intro", "done", "failed"]
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


func _run() -> void:
	create_timer(300.0).timeout.connect(func(): printerr("ÉCHEC délai"); quit(2))
	var world = null
	var anchors := {}
	var space: PhysicsDirectSpaceState3D
	var count := 0
	for m in ["m01", "m02", "m03", "m04", "m05", "m06", "m07", "m08"]:
		# Un monde par mission : les décors de mission (supermarché, scène, enclos…) ne sont construits que pour la mission active.
		if world:
			world.queue_free()
			await process_frame
		root.get_node("Net").mission_id = m
		world = load(WORLD).instantiate()
		root.add_child(world)
		for i in 40:
			await physics_frame
		var poi: Dictionary = CityBuilder.read_json("res://assets/city/poi.json")
		anchors = CinematicPlayer.anchors_from_pois(poi.pois, world.builder.height_at)
		space = world.get_world_3d().direct_space_state
		for w in IDS:
			var d := CinematicPlayer.load_def("%s_%s" % [m, w])
			if d.is_empty():
				check(w == "failed", "%s_%s : absente (seul « failed » est facultatif)" % [m, w])
				continue
			count += 1
			var ok := true
			var why := ""
			var shots: Array = d.shots
			for i in shots.size():
				for u in [0.0, 0.5, 1.0]:
					var st = CinematicPlayer.shot_state(shots[i], u, anchors)
					if st == null:
						ok = false
						why = "plan %d : lieu inconnu" % (i + 1)
						break
					var cam: Vector3 = st.cam
					var look: Vector3 = st.look
					var q := PhysicsPointQueryParameters3D.new()
					q.position = cam
					if not space.intersect_point(q, 1).is_empty():
						ok = false
						why = "plan %d (u=%.1f) : caméra dans un mur, en %s" % [i + 1, u, str(cam.round())]
						break
					var r := PhysicsRayQueryParameters3D.create(cam, look)
					var hit := space.intersect_ray(r)
					if not hit.is_empty() and hit.collider is StaticBody3D and (hit.collider.collision_layer & 1) != 0 and cam.distance_to(hit.position) < 0.8 * cam.distance_to(look):
						ok = false
						why = "plan %d (u=%.1f) : sujet masqué à %.0f m par %s" % [i + 1, u, cam.distance_to(hit.position), "%s/%s à %s" % [hit.collider.get_parent().name, hit.collider.name, str(hit.position.round())]]
						break
				if not ok:
					break
			check(ok, "%s_%s : %d plans, %.0f s%s" % [m, w, shots.size(), CinematicPlayer.total_duration(d), "" if ok else " — " + why])
	check(count >= 14, "au moins 14 cinématiques (%d)" % count)
	# --- Lecture complète dans le monde (tolérante : les murs ont déjà été vérifiés) ---
	var cam0 := root.get_viewport().get_camera_3d()
	var d1 := CinematicPlayer.load_def("m01_done")
	var p := CinematicPlayer.new()
	world.add_child(p)
	p.start(d1, anchors)
	check(CinematicPlayer.active, "la cinématique est active pendant la lecture")
	check(root.get_viewport().get_camera_3d().name == "CameraCinematique", "la caméra de la scène est la caméra courante")
	var seen_text := false
	var t := 0.0
	var fin := [false]
	p.finished.connect(func(_id): fin[0] = true)
	while not fin[0] and t < 40.0:
		await process_frame
		t += 1.0 / 60.0
		if is_instance_valid(p) and p._text and p._text.text != "":
			seen_text = true
	check(fin[0], "la scène se termine d'elle-même (%.1f s pour %.1f s annoncées)" % [t, CinematicPlayer.total_duration(d1)])
	check(seen_text, "une légende a été affichée")
	await process_frame
	check(not CinematicPlayer.active, "le jeu reprend : le joueur peut bouger")
	check(cam0 == null or root.get_viewport().get_camera_3d() == cam0, "la caméra du joueur est rétablie")
	check(not paused, "le jeu n'est plus en pause")
	# Passage de la scène
	var p2 := CinematicPlayer.new()
	world.add_child(p2)
	p2.start(CinematicPlayer.load_def("m07_intro"), anchors)
	await create_timer(0.3).timeout
	p2.skip()
	await process_frame
	check(not CinematicPlayer.active and not paused, "on peut passer la scène")
	print("--- cinematic_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
