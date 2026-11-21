extends SceneTree
## Véhicule sur les pentes : montée, crête, descente, creux (8° puis 14°). Mesures : le véhicule reste collé au route (pas de saut
## aux changements de pente), sa vitesse le long de la chaussée ne s'effondre pas en montée, il ne dévie pas.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/vehicle_slope_audit.gd
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


func block(parent: Node, size: Vector3, pos: Vector3, rot_z := 0.0) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = pos
	b.rotation.z = rot_z
	parent.add_child(b)


## Profil le long de +X : plat 30 m, rampe montante 30 m, plat 20 m, rampe descendante 30 m, plat 30 m. Renvoie l'abscisse de départ.
func build_profile(parent: Node, base: Vector3, angle: float) -> void:
	var t := 0.4
	var x := 0.0
	var y := 0.0
	var segs := [[30.0, 0.0], [30.0, angle], [20.0, 0.0], [30.0, -angle], [40.0, 0.0]]
	for s in segs:
		var L: float = s[0]
		var a: float = s[1]
		var cx := x + cos(a) * L / 2.0
		var cy := y + sin(a) * L / 2.0
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(L, t, 10.0)
		cs.shape = bs
		b.add_child(cs)
		b.position = base + Vector3(cx, cy - t / 2.0 * cos(a), 0.0)
		b.rotation.z = a
		parent.add_child(b)
		x += cos(a) * L
		y += sin(a) * L


func run_angle(world, van, player, mission, deg: float, base: Vector3) -> void:
	var angle := deg_to_rad(deg)
	var holder := Node3D.new()
	world.add_child(holder)
	build_profile(holder, base, angle)
	van.global_position = base + Vector3(-15.0, 1.3, 0.0)
	van.rotation.y = -PI / 2.0
	van.velocity = Vector3.ZERO
	van.speed = 0.0
	await frames(30)
	van.forced_input = {"move": Vector2(0, -1), "jump": false}
	var air := 0
	var n := 0
	var top_speed := 0.0
	var min_after := 99.0
	var max_yaw_dev := 0.0
	var z0: float = van.global_position.z
	var reached := false
	for i in 60 * 14:
		await physics_frame
		n += 1
		if not van.is_on_floor():
			air += 1
		var s: float = Vector2(van.velocity.x, van.velocity.z).length() if false else van.velocity.length()
		top_speed = maxf(top_speed, van.speed)
		if van.global_position.x > base.x + 35.0 and van.global_position.x < base.x + 100.0:
			min_after = minf(min_after, van.speed)
		max_yaw_dev = maxf(max_yaw_dev, absf(van.global_position.z - z0))
		if van.global_position.x > base.x + 120.0:
			reached = true
			break
	print("  pente %.0f° (%.0f %%) : %d images en l'air sur %d, vitesse max %.1f m/s, mini en pente %.1f m/s, dérive latérale %.2f m" % [deg, tan(angle) * 100.0, air, n, top_speed, min_after, max_yaw_dev])
	check(reached, "%.0f° : la camionnette franchit la montée, la crête et la descente" % deg)
	check(air <= 12, "%.0f° : reste collée à la route (%d images en l'air)" % [deg, air])
	check(min_after > 0.55 * top_speed, "%.0f° : ne s'effondre pas en montée (%.1f sur %.1f m/s)" % [deg, min_after, top_speed])
	check(max_yaw_dev < 0.5, "%.0f° : ne dérive pas sur le côté (%.2f m)" % [deg, max_yaw_dev])
	van.forced_input = {"move": Vector2.ZERO, "jump": true}
	await frames(60)
	holder.queue_free()


func _run() -> void:
	create_timer(240.0).timeout.connect(func(): printerr("ÉCHEC délai"); quit(2))
	root.get_node("Net").mission_id = "m01"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(100)
	var mission = world.mission
	var van = mission.van
	var player = world.players_root.get_node("1")
	for c in world.players_root.get_children():       # les compagnons (guides) ne doivent pas se retrouver sur la rampe d'essai
		if c.peer_id < 0:
			c.brain = null
			c.global_position = Vector3(0, -500, 0)
			c.set_physics_process(false)
	for id in mission.crates:
		mission.crates[id].state = "loaded"
	mission.step = "road"
	player.global_position = van.global_position + van.global_transform.basis.x * 2.6
	await frames(3)
	mission.interact(1)
	await frames(3)
	check(van.driver == 1, "au volant")
	var base := Vector3(0, 600, 0)
	var floor_b := StaticBody3D.new()
	var fc := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(600, 1, 100)
	fc.shape = fb
	floor_b.add_child(fc)
	floor_b.position = base + Vector3(100, -0.5, 0)
	world.add_child(floor_b)
	await run_angle(world, van, player, mission, 8.0, base)
	await run_angle(world, van, player, mission, 14.0, base)
	print("--- vehicle_slope_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
