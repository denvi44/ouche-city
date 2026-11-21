extends SceneTree
## Audit des mouvements et collisions du joueur : saut (hauteur, durée, saut en courant), mur, bordure, marche,
## obstacle haut, rampe, chute depuis un bord. Des blocs de test sont posés sur un sol plat près du joueur.
## Usage : godot --headless --fixed-fps 60 --path game -s ../qa/integration/movement_audit.gd

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"
var fails := 0
var player
var inp := {"move": Vector2.ZERO, "yaw": 0.0, "jump": false, "sprint": false}


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


func block(size: Vector3, center: Vector3) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	b.position = center
	player.get_parent().get_parent().add_child(b)
	return b


func bot(_d := 0.0) -> Dictionary:
	return inp


func place(p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	inp = {"move": Vector2.ZERO, "yaw": 0.0, "jump": false, "sprint": false}


func _run() -> void:
	create_timer(120.0).timeout.connect(func(): printerr("ÉCHEC délai"); quit(2))
	root.get_node("Net").mission_id = "m01"
	var world = load(WORLD).instantiate()
	root.add_child(world)
	await frames(100)
	player = world.players_root.get_node("1") if world.players_root.has_node("1") else world.players_root.get_child(0)
	player.bot_input = Callable(self, "bot")
	# Zone d'essai : sol plat artificiel haut dans le ciel, loin de tout.
	var base := Vector3(0, 400, 0)
	block(Vector3(80, 1, 80), base + Vector3(0, -0.5, 0))
	var floor_y := base.y
	# --- Saut sur place ---
	place(base + Vector3(0, 0.1, 0))
	await frames(20)
	var y0: float = player.global_position.y
	inp.jump = true
	var apex := 0.0
	var air := 0
	for i in 120:
		await physics_frame
		inp.jump = false
		apex = maxf(apex, player.global_position.y - y0)
		if not player.is_on_floor():
			air += 1
		elif i > 5:
			break
	print("  saut sur place : sommet %.2f m, %.2f s en l'air" % [apex, air / 60.0])
	check(apex > 0.6 and apex < 1.2, "hauteur du saut réaliste (0,6–1,2 m) : %.2f m" % apex)
	check(air / 60.0 > 0.4 and air / 60.0 < 1.0, "durée en l'air plausible : %.2f s" % (air / 60.0))
	# --- Saut tenu : un seul saut, pas de rebond infini ---
	place(base + Vector3(0, 0.1, 0))
	await frames(20)
	inp.jump = true
	var jumps := 0
	var was_floor := true
	for i in 240:
		await physics_frame
		var f: bool = player.is_on_floor()
		if was_floor and not f:
			jumps += 1
		was_floor = f
	print("  touche saut maintenue 4 s : %d sauts" % jumps)
	check(jumps >= 3, "saut répété si la touche reste appuyée (%d)" % jumps)
	# --- Saut en courant : distance ---
	place(base + Vector3(-20, 0.1, 0))
	await frames(20)
	inp.move = Vector2(0, -1)
	inp.yaw = -PI / 2.0         # vers +x
	inp.sprint = true
	await frames(40)
	var x0: float = player.global_position.x
	inp.jump = true
	var t := 0
	for i in 120:
		await physics_frame
		inp.jump = false
		t += 1
		if i > 5 and player.is_on_floor():
			break
	var dist: float = player.global_position.x - x0
	print("  saut en courant : %.2f m" % dist)
	check(dist > 2.5 and dist < 7.0, "saut en longueur plausible : %.2f m" % dist)
	# --- Mur plein : on ne le traverse pas, même en courant ---
	place(base + Vector3(-10, 0.1, 10))
	var wall := block(Vector3(0.5, 4, 10), base + Vector3(-5, 2, 10))
	await frames(10)
	inp.move = Vector2(0, -1)
	inp.yaw = -PI / 2.0
	inp.sprint = true
	await frames(180)
	check(player.global_position.x < -5.3, "le mur arrête le joueur (x = %.2f)" % player.global_position.x)
	# --- Bordure de 12 cm : franchie sans sauter ---
	wall.queue_free()
	place(base + Vector3(-10, 0.1, -10))
	block(Vector3(4, 0.12, 8), base + Vector3(-2, 0.06, -10))
	await frames(10)
	inp.move = Vector2(0, -1)
	inp.yaw = -PI / 2.0
	inp.sprint = false
	await frames(150)
	check(player.global_position.x > -1.0, "bordure de 12 cm franchie à pied (x = %.2f)" % player.global_position.x)
	# --- Marche de 60 cm : bloque à pied, franchie en sautant ---
	place(base + Vector3(-10, 0.1, -20))
	block(Vector3(4, 0.6, 8), base + Vector3(-2, 0.3, -20))
	await frames(10)
	inp.move = Vector2(0, -1)
	inp.yaw = -PI / 2.0
	await frames(150)
	check(player.global_position.x < -3.8, "marche de 60 cm : bloque à pied (x = %.2f)" % player.global_position.x)
	inp.jump = true
	await frames(150)
	check(player.global_position.x > -3.0, "…et se franchit en sautant (x = %.2f)" % player.global_position.x)
	inp.jump = false
	# --- Obstacle de 2 m : infranchissable en sautant ---
	place(base + Vector3(-10, 0.1, 20))
	block(Vector3(1, 2.0, 8), base + Vector3(-4, 1.0, 20))
	await frames(10)
	inp.move = Vector2(0, -1)
	inp.yaw = -PI / 2.0
	inp.sprint = true
	inp.jump = true
	await frames(240)
	check(player.global_position.x < -4.6, "mur de 2 m infranchissable (x = %.2f)" % player.global_position.x)
	inp.jump = false
	# --- Rampe à 25° : montée à pied ---
	place(base + Vector3(-12, 0.1, 30))
	var ramp := block(Vector3(10, 0.3, 6), base + Vector3(-6, 0.9, 30))
	ramp.rotation.z = deg_to_rad(25.0)
	await frames(10)
	inp.move = Vector2(0, -1)
	inp.yaw = -PI / 2.0
	inp.sprint = false
	await frames(200)
	check(player.global_position.y > base.y + 0.8, "rampe de 25° gravie (y = +%.2f)" % (player.global_position.y - base.y))
	# --- Chute du bord : pas de téléportation intempestive, atterrit au sol ---
	place(base + Vector3(36, 0.1, 0))
	await frames(10)
	inp.move = Vector2(0, -1)
	inp.yaw = -PI / 2.0
	await frames(180)
	check(player.global_position.y < base.y - 1.0, "tombe du bord de la plateforme (y = %.1f)" % (player.global_position.y - base.y))
	# --- Mobilier de rue : jardinière en bois (vraie scène : aucune traversée) ---
	var sf = load("res://scripts/world/street_furniture.gd")
	var shops := Node3D.new()
	world.add_child(shops)
	var fake := [{"kind": "shop", "facing": 0.0, "position": [0.0, 20.0], "id": "t"}]
	var built: Node3D = sf.build_shops(fake, func(_x, _z): return 0.0)
	built.position = base + Vector3(0, 0, 0)
	shops.add_child(built)
	await frames(5)
	# jardinière gauche à (-1.7, ·, 60.45) sur le sol d'essai : on la percute de face
	place(base + Vector3(-1.7, 0.1, 24.0))
	await frames(10)
	inp.move = Vector2(0, -1)
	inp.yaw = 0.0
	inp.sprint = false
	await frames(120)
	check(player.global_position.z > 20.8, "jardinière : le joueur ne la traverse pas (z = %.2f)" % player.global_position.z)
	print("--- movement_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
