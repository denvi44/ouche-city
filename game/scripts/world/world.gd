extends Node3D
## Monde de jeu (scène témoin) : ville générée depuis les tuiles, ciel, soleil, joueurs.
## Le même script tourne sur le serveur (dédié ou local) et sur les clients.

const CITY_DIR := "res://assets/city"
const PlayerScript := preload("res://scripts/player/player.gd")

var players_root: Node3D
var day_night: DayNight
var spawn_point := Vector3(0, 1, 0)
var city: Node3D
var builder: CityBuilder
var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	_build_environment()
	builder = CityBuilder.new()
	city = builder.build_city(CITY_DIR)
	add_child(city)
	spawn_point = find_spawn(CITY_DIR)
	spawn_point.y = builder.height_at(spawn_point.x, spawn_point.z) + 1.0
	players_root = Node3D.new()
	players_root.name = "Joueurs"
	add_child(players_root)
	if DisplayServer.get_name() != "headless":
		add_child(preload("res://ui/hud.gd").new())

	if Net.mode == Net.Mode.NONE:
		# Scène lancée directement (éditeur, tests, captures) : solo local.
		Net.host_solo()
	Net.server_lost.connect(_back_to_menu)
	if Net.is_server():
		multiplayer.peer_disconnected.connect(_on_peer_left)
		if Net.has_local_player() and Net.arg("viewer") == null:
			await get_tree().physics_frame
			_spawn(1, Settings.player_name, find_free_spawn(spawn_point))
			Net.players[1].ready = true
		var t := Timer.new()
		t.wait_time = 1.0
		t.autostart = true
		t.timeout.connect(func():
			for id in Net.ready_peers():
				_set_hour.rpc_id(id, day_night.hour))
		add_child(t)
	else:
		_client_ready.rpc_id(1)
	var report = Net.arg("qa-report")
	if report != null:
		var rt := Timer.new()
		rt.wait_time = float(report)
		rt.autostart = true
		rt.timeout.connect(_qa_report)
		add_child(rt)
	var quit_after = Net.arg("quit-after")
	if quit_after != null:
		get_tree().create_timer(float(quit_after)).timeout.connect(_qa_quit)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/ciel_peint.gdshader")
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.86, 0.92)
	env.fog_density = 0.0015
	var we := WorldEnvironment.new()
	we.name = "Environnement"
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Soleil"
	sun.shadow_enabled = true
	sun.shadow_blur = 0.0
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	day_night = DayNight.new()
	day_night.name = "CycleJourNuit"
	day_night.sun = sun
	day_night.environment = env
	var start_hour = Net.arg("hour")
	day_night.hour = float(start_hour) if start_hour != null else 11.0
	add_child(day_night)


## Point d'apparition : POI « spawn » du cartographe, sinon centre du POC.
static func find_spawn(dir: String) -> Vector3:
	var poi = CityBuilder.read_json(dir.path_join("poi.json"))
	if poi is Dictionary:
		for p in poi.get("pois", []):
			if p.kind == "spawn":
				return Vector3(p.position[0], 1.0, p.position[1])
	var m := CityBuilder.load_manifest(dir)
	if m.has("pocCentre"):
		return Vector3(m.pocCentre[0], 1.0, m.pocCentre[1])
	return Vector3(0, 1, 0)


func _spawn(id: int, player_name: String, pos: Vector3) -> Player:
	if players_root.has_node(str(id)):
		return players_root.get_node(str(id))
	var p: Player = PlayerScript.new()
	p.name = str(id)
	p.display_name = player_name
	p.position = pos
	players_root.add_child(p)
	return p


## Point d'apparition libre le plus proche (spirale autour du point de base) :
## ni dans un mur, ni sur un autre joueur.
func find_free_spawn(base: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.7
	query.shape = capsule
	for ring in range(0, 12):
		var count := maxi(1, ring * 6)
		for k in count:
			var a := TAU * k / count
			var p := Vector3(base.x + cos(a) * ring * 1.2, 0.0, base.z + sin(a) * ring * 1.2)
			p.y = builder.height_at(p.x, p.z) + 0.15
			query.transform = Transform3D(Basis(), p + Vector3(0, 1.1, 0))
			if space.intersect_shape(query, 1).is_empty() and not _near_player(p) and _open_sky(space, p):
				return p + Vector3(0, 0.05, 0)
	return base


## Rien au-dessus (sinon on est dans un bâtiment : une capsule entièrement à l'intérieur
## d'un maillage concave ne touche aucune face).
func _open_sky(space: PhysicsDirectSpaceState3D, p: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(p + Vector3(0, 80, 0), p + Vector3(0, 0.3, 0))
	return space.intersect_ray(ray).is_empty()


func _near_player(p: Vector3) -> bool:
	for pl in players_root.get_children():
		if pl.global_position.distance_to(p) < 1.2:
			return true
	return false


@rpc("any_peer", "call_remote", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not Net.players.has(id):
		return
	var pos := find_free_spawn(spawn_point)
	var pname: String = Net.players[id].name
	_spawn(id, pname, pos)
	for child in players_root.get_children():
		_spawn_remote.rpc_id(id, child.peer_id, child.display_name, child.global_position)
	for other in Net.ready_peers():
		_spawn_remote.rpc_id(other, id, pname, pos)
	_set_hour.rpc_id(id, day_night.hour)
	Net.players[id].ready = true
	print("[monde] joueur %d (%s) apparu en %s" % [id, pname, pos])


@rpc("authority", "call_remote", "reliable")
func _spawn_remote(id: int, player_name: String, pos: Vector3) -> void:
	_spawn(id, player_name, pos)


@rpc("authority", "call_remote", "reliable")
func _despawn(id: int) -> void:
	if players_root.has_node(str(id)):
		players_root.get_node(str(id)).queue_free()


@rpc("authority", "call_remote", "unreliable_ordered")
func _set_hour(h: float) -> void:
	day_night.hour = h


func _on_peer_left(id: int) -> void:
	_despawn(id)
	for other in Net.ready_peers():
		_despawn.rpc_id(other, id)


func _back_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Bilan imprimé pour les tests d'intégration (qa/integration).
func _qa_report() -> void:
	var parts := []
	for p in players_root.get_children():
		parts.append("%d@%.1f,%.1f,%.1f" % [p.peer_id, p.global_position.x, p.global_position.y, p.global_position.z])
	print("[qa] mode=%s joueurs=%d positions=%s" % [Net.Mode.keys()[Net.mode], players_root.get_child_count(), " ".join(parts)])


func _qa_quit() -> void:
	_qa_report()
	Net.leave()
	get_tree().quit(0)
