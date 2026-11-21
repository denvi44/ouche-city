extends Node3D
## Monde de jeu (scène témoin) : ville générée depuis les tuiles, ciel, soleil, joueurs.
## Le même script tourne sur le serveur (dédié ou local) et sur les clients.

const CITY_DIR := "res://assets/city"
const MISSION_IDS := {"m01": "m01_calva_gege", "m02": "m02_tuning_samedi", "m03": "m03_battle_sono", "m04": "m04_mechoui_saint_jean", "m05": "m05_vaches_en_goguette", "m06": "m06_courses_de_8h", "m07": "m07_jus_de_pomme"}
const PlayerScript := preload("res://scripts/player/player.gd")

var players_root: Node3D
var day_night: DayNight
var spawn_point := Vector3(0, 1, 0)
var city: Node3D
var builder: CityBuilder
var env: Environment
var sun: DirectionalLight3D
var van: Vehicle
var mission: MissionBase
var mission_key := "m01"


func _ready() -> void:
	_build_environment()
	builder = CityBuilder.new()
	mission_key = str(Net.arg("mission", Net.mission_id))
	city = builder.build_city(CITY_DIR, MISSION_IDS.get(mission_key, "m01_calva_gege"))
	add_child(city)
	spawn_point = find_spawn(CITY_DIR)
	spawn_point.y = builder.height_at(spawn_point.x, spawn_point.z) + 1.0
	players_root = Node3D.new()
	players_root.name = "Joueurs"
	add_child(players_root)
	# Dialogues, bulles de paroles et onomatopées : mêmes nœuds sur tous les pairs.
	var dialogues := DialoguePlayer.new()
	add_child(dialogues)
	var bubbles := SpeechBubbles.new()
	add_child(bubbles)
	bubbles.bind(dialogues)
	add_child(OnomaLayer.new())
	_build_van_and_mission()
	var amb := Ambiance.new()
	amb.name = "Ambiance"
	amb.day_night = day_night
	for poi in (CityBuilder.read_json(CITY_DIR.path_join("poi.json")) as Dictionary).get("pois", []):
		if poi.id == "eglise":
			amb.church_pos = Vector3(float(poi.position[0]), builder.height_at(float(poi.position[0]), float(poi.position[1])), float(poi.position[1]))
			amb.has_church = true
	add_child(amb)
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
			_spawn_companions()
		var t := Timer.new()
		t.wait_time = 1.0
		t.autostart = true
		t.timeout.connect(func():
			for id in Net.ready_peers():
				_set_hour.rpc_id(id, day_night.hour))
		add_child(t)
	else:
		_client_ready.rpc_id(1)
	var qa_say = Net.arg("qa-say")
	if qa_say != null and Net.is_server():
		# Test réseau : la réplique est redite toutes les 1,5 s pour que les clients lents (CI) la reçoivent aussi.
		var qt := Timer.new()
		qt.wait_time = 1.5
		qt.autostart = true
		qt.timeout.connect(func(): mission.say(str(qa_say)))
		add_child(qt)
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


## La camionnette et la mission existent sur tous les pairs (mêmes noms, même place) ;
## seul le serveur décide, les clients reçoivent l'état par `MissionM01._sync` et `NetBody._state`.
func _build_van_and_mission() -> void:
	var poi = CityBuilder.read_json(CITY_DIR.path_join("poi.json"))
	var pois: Array = poi.get("pois", []) if poi is Dictionary else []
	var van_poi := {}
	var van_id := "voiture_kevin" if mission_key == "m02" else "van_gege"
	for p in pois:
		if p.id == van_id:
			van_poi = p
	if not van_poi.is_empty() and not (mission_key in ["m03", "m04", "m05", "m06", "m07"]):      # ces missions se jouent à pied
		van = Car.new() if mission_key == "m02" else Vehicle.new()
		van.name = "Fusee" if mission_key == "m02" else "Van"
		var x := float(van_poi.position[0])
		var z := float(van_poi.position[1])
		van.position = Vector3(x, builder.height_at(x, z) + 0.4, z)
		van.rotation.y = float(van_poi.facing) + PI
		add_child(van)
	match mission_key:
		"m02":
			mission = MissionM02.new()
		"m03":
			mission = MissionM03.new()
		"m04":
			mission = MissionM04.new()
		"m05":
			mission = MissionM05.new()
		"m06":
			mission = MissionM06.new()
		"m07":
			mission = MissionM07.new()
		_:
			mission = MissionM01.new()
	mission.name = "Mission"
	add_child(mission)
	mission.setup(pois, builder.height_at, van, players_root)


## Compagnons IA : en solo, ils tiennent les rôles que le joueur ne tient pas (conducteur) :
## Gégé arrimeur, Ginette négociatrice, Kévin Radio guetteur, Kévin diversion.
## `--no-companions` les désactive (tests) ; `--companions=gege,ginette` en choisit.
func _spawn_companions() -> void:
	if Net.mode != Net.Mode.SOLO or Net.arg("no-companions") != null or mission == null:
		return
	var roles: Dictionary = mission.companion_roles()
	var allowed: PackedStringArray = str(Net.arg("companions", "gege,ginette,radio,kevin")).split(",")
	var names := {-1: "gege", -2: "ginette", -3: "radio", -4: "kevin"}
	var nav := RoadNav.load_default()
	var k := 0
	for id in roles:
		if not (names[id] in allowed):
			continue
		var angle := TAU * k / 4.0
		var pos := find_free_spawn(spawn_point + Vector3(cos(angle) * 3.0, 0.0, sin(angle) * 3.0))
		var c := _spawn(id, Player.OUTFITS[id].nom, pos)
		c.brain = CompanionBrain.new(c, mission, nav, roles[id])
		k += 1


func _unhandled_input(event: InputEvent) -> void:
	if mission and Net.has_local_player() and DisplayServer.get_name() != "headless":
		for i in 5:
			if event.is_action_pressed("choose_%d" % (i + 1)):
				if mission is MissionM01:
					if i < MissionM01.OPTIONS.size():
						mission.request_choice(MissionM01.OPTIONS[i])
				else:
					mission.request_choice(str(i + 1))
		if event.is_action_pressed("sprint") and van and van.driver == multiplayer.get_unique_id():
			mission.request_boost()
	if event.is_action_pressed("dialogue_skip") and mission and Net.has_local_player():
		mission.request_skip()
	if event.is_action_pressed("radio_toggle") and van and van.driver == multiplayer.get_unique_id():
		Sfx.toggle_radio()
	if event.is_action_pressed("horn") and mission and van and van.driver == multiplayer.get_unique_id():
		mission.request_horn()
	if event.is_action_pressed("interact") and mission and Net.has_local_player() and DisplayServer.get_name() != "headless":
		mission.request_interact()


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
	env.ambient_light_energy = 0.8
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
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
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
	p.vehicle = van
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
	var base := spawn_point
	if Net.arg("spawn-at") == "van" and van:   # option QA : apparaître près de la camionnette
		base = van.global_position + Vector3(2.6, 0, 0)
	var pos := find_free_spawn(base)
	var pname: String = Net.players[id].name
	_spawn(id, pname, pos)
	for child in players_root.get_children():
		_spawn_remote.rpc_id(id, child.peer_id, child.display_name, child.global_position)
	for other in Net.ready_peers():
		_spawn_remote.rpc_id(other, id, pname, pos)
	_set_hour.rpc_id(id, day_night.hour)
	mission.send_full_state(id)      # aléas (tracteur, vaches, nids-de-poule) puis état, avant « prêt »
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
	mission.on_player_left(id)
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
	var vinfo := "van=-"
	if van and mission is MissionM01:
		vinfo = "van=%.1f,%.1f,%.1f conducteur=%d etape=%s nids=%d tracteur=%s" % [van.global_position.x, van.global_position.y, van.global_position.z, van.driver, mission.step, mission.potholes.size(), mission.tractor != null]
	elif van:
		vinfo = "van=%.1f,%.1f,%.1f conducteur=%d etape=%s nids=0 tracteur=false" % [van.global_position.x, van.global_position.y, van.global_position.z, van.driver, mission.step]
	elif mission is MissionM07:
		vinfo = "van=- etape=%s pression=%d porte=%s" % [mission.step, int(mission.pressure_of(multiplayer.get_unique_id()) * 100.0), mission.door_open]
	elif mission is MissionM06:
		vinfo = "van=- etape=%s cabas=%d clients=%d" % [mission.step, mission.items_got.size(), mission.customers.size()]
	elif mission is MissionM05:
		vinfo = "van=- etape=%s vaches=%d enclos=%d" % [mission.step, mission.cows.size(), mission.penned()]
	elif mission is MissionM04:
		vinfo = "van=- etape=%s objets=%d cuisson=%d" % [mission.step, mission.items_taken.size(), int(mission.cook * 100.0)]
	elif mission is MissionM03:
		vinfo = "van=- etape=%s manche=%d objets=%d" % [mission.step, mission.round_idx, mission.items_taken.size()]
	var dlg := get_node_or_null("Dialogues") as DialoguePlayer
	print("[qa] mode=%s joueurs=%d %s dial=%d positions=%s" % [Net.Mode.keys()[Net.mode], players_root.get_child_count(), vinfo, dlg.said_ids.size() if dlg else 0, " ".join(parts)])


func _qa_quit() -> void:
	_qa_report()
	Net.leave()
	get_tree().quit(0)
