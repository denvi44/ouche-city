class_name MissionM01
extends MissionBase
## Mission 01 « Le Calva de Tonton Gégé » (agent 05), état à autorité serveur.
##
## Étapes jouables : caisses (4 sources) → route (camionnette, cargaison fragile) → barrage de
## l'avenue du Bosc-Tenney (choix d'équipe automatique : bluff) → stand de foire → médaille.
## Ce qui n'est pas encore là : cinématique d'intro, choix d'équipe votés, événements de route
## (nids-de-poule, tracteur, vaches), compagnons IA, livraison à pied (livrée à l'arrivée).
## Les paramètres viennent de missions/m01_calva_gege.json (copié dans res://assets/missions/).

const MISSION_FILE := "res://assets/missions/m01_calva_gege.json"
const PICK_RADIUS := 2.8
const VAN_RADIUS := 4.2
const ZONE_RADIUS := 9.0
const BREAK_THRESHOLD := 3.5       # perte de vitesse (m/s) à partir de laquelle ça casse
const SYNC_PERIOD := 0.25
const CHECKPOINT_TIME := 12.0       # s pour choisir avant que les compagnons décident
const DETOUR_COST := 45.0           # s perdues en contournant
const DIVERSION_FAIL_COST := 20.0
const BLUFF_BASE := 0.5
const BLUFF_WITH_GINETTE := 0.9
const NEAR_BARRAGE := 16.0          # distance (m) à laquelle Ginette est « sur place »
const NEAR_DIVERSION := 30.0        # distance (m) à laquelle Kévin peut faire diversion
const CONFISCATED := 3              # bouteilles saisies par le gendarme si le bluff rate
const OPTIONS := ["bluff", "detour", "diversion"]
# Événements de route (missions/m01 : "potholes", "slow_tractor", "cows").
const POTHOLE_FRACTIONS := [0.12, 0.28, 0.42, 0.66, 0.80]   # positions sur l'itinéraire (0 = départ, 1 = barrage)
const TRACTOR_FROM := 0.33
const TRACTOR_TO := 0.80
const COW_FRACTION_MIN := 0.48
const COW_FRACTION_MAX := 0.74
const POTHOLE_RADIUS := 1.3
const TRIGGER_DISTANCE := 50.0      # la camionnette « réveille » le tracteur / les vaches à cette distance
const HORN_RANGE := 60.0
const ID_GINETTE := -2
const ID_RADIO := -3
const ID_KEVIN := -4

const CRATE_POIS := ["cave_gege", "grange_pommiers", "poulailler_ginette", "fumier_tas"]
const CRATE_NAMES := {"cave_gege": "la cave de Gégé", "grange_pommiers": "la grange", "poulailler_ginette": "le poulailler", "fumier_tas": "le tas de fumier"}

# Paramètres issus du JSON.
var time_limit := 1110.0
var bottles_total := 24
var bottles_per_crate := 6
var min_delivered := 12
var medals := {"gold": 22, "silver": 16, "bronze": 12}
var money_per_bottle := 20
var rewards := {}
var mission_id := "m01_calva_gege"

# État répliqué.
var cargo := 0                  # bouteilles intactes dans la camionnette
var broken := 0
var medal := ""
var money := 0
var driver := 0
var crates := {}                # id -> {"state": ground|carried|loaded, "carrier": peer, "pos": Vector3, "bottles": int}
var barrage_passed := false
var checkpoint_left := 0.0      # s restantes pour choisir (étape « checkpoint »)
var failed_options: Array = []  # options déjà tentées en vain
var barrier_open := false

var zones := {}                 # "barrage" / "stand" -> Vector3
var zone_dirs := {}             # direction de la route (x, z) en chaque zone
var rng := RandomNumberGenerator.new()
## Tirage imposé (tests) : >= 0 remplace le hasard.
var test_roll := -1.0
var _spots := {}                # emplacements d'attente des compagnons (calculés à la demande)
var _barrier_body: StaticBody3D
var _barrier_bar: Node3D
var _radio_flags := {}

# Aléas de route.
var hazards_ready := false
var _hazards_tried := false
var route := PackedVector2Array()           # itinéraire de la camionnette au barrage (serveur)
var route_length := 0.0
var potholes: Array = []                    # Vector2 (x, z)
var tractor: Tractor
var cows: Array = []
var tractor_active := false
var tractor_done := false
var cows_active := false
var cows_done := false
var jolt_serial := 0
var horn_serial := 0
var tractor_start := Vector2.ZERO
var cow_center := Vector2.ZERO
var _hazard_payload := {}
var _tractor_path := PackedVector2Array()
var _pothole_cd := {}
var _pothole_nodes: Array = []
var _crate_nodes := {}
var _dirty := true
var _sync_t := 0.0


func _ready() -> void:
	title = "Le Calva de Tonton Gégé"
	step = "crates"
	rng.seed = 20260101        # mêmes tirages à chaque partie (reproductible) ; Ginette et la chance font le reste
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		title = m.title
		var t: PackedStringArray = str(m.timeLimit.solo).split(":")
		time_limit = float(t[0]) * 60.0 + float(t[1])
		bottles_total = int(m.cargo.total)
		bottles_per_crate = bottles_total / int(m.cargo.crates)
		min_delivered = int(m.cargo.minDelivered)
		medals = {"gold": int(m.medals.gold), "silver": int(m.medals.silver), "bronze": int(m.medals.bronze)}
		money_per_bottle = int(m.rewards.moneyPerBottle)
		rewards = m.rewards
		mission_id = m.id


## Pose les caisses et les zones d'après les POI du cartographe. `ground` : fonction hauteur du sol.
func setup(pois: Array, ground: Callable, vehicle: Vehicle, players_root: Node3D) -> void:
	van = vehicle
	_players_root = players_root
	if van:
		van.impact.connect(_on_impact)
	for p in pois:
		var pos2 := Vector2(float(p.position[0]), float(p.position[1]))
		var h: float = ground.call(pos2.x, pos2.y)
		if p.id in CRATE_POIS:
			var f := float(p.get("facing", 0.0))
			var dir := Vector2(sin(f), cos(f))
			var off := dir * 1.6
			if p.get("prop", "") == "fumier":
				off = Vector2(-dir.y, dir.x) * 2.6
			var cp := pos2 + off
			crates[p.id] = {"state": "ground", "carrier": 0, "bottles": bottles_per_crate,
				"pos": Vector3(cp.x, ground.call(cp.x, cp.y), cp.y)}
		elif p.id == "barrage_bosc_tenney":
			zones["barrage"] = Vector3(pos2.x, h, pos2.y)
			zone_dirs["barrage"] = Vector2(sin(float(p.get("facing", 0.0))), cos(float(p.get("facing", 0.0))))
		elif p.id == "stand_comite":
			zones["stand"] = Vector3(pos2.x, h, pos2.y)
			zone_dirs["stand"] = Vector2(sin(float(p.get("facing", 0.0))), cos(float(p.get("facing", 0.0))))
	var city = get_parent().get("city")
	if city:
		_barrier_body = city.get_node_or_null("LieuxDeMission/Lieu_barrage_bosc_tenney/Collision") as StaticBody3D
		_barrier_bar = city.get_node_or_null("LieuxDeMission/Lieu_barrage_bosc_tenney/Barre") as Node3D
	for id in crates:
		_crate_nodes[id] = _make_crate_node(id)
		get_parent().add_child.call_deferred(_crate_nodes[id])
	_refresh_nodes()


## Distance horizontale d'un acteur à une zone (INF si absent).
func distance_to_zone(id: int, zone: String) -> float:
	var a := actor(id)
	if a == null or not zones.has(zone):
		return INF
	return Vector2(a.global_position.x - zones[zone].x, a.global_position.z - zones[zone].z).length()


## Emplacement d'attente d'un compagnon : sur le trottoir, de part et d'autre de la route, à
## l'écart de la camionnette. Calculé à la demande (la physique doit être prête) puis mémorisé.
func spot(name: String) -> Vector3:
	if _spots.has(name):
		return _spots[name]
	var base := Vector3.ZERO
	match name:
		"ginette":
			base = _offset("barrage", 0.0, 5.0)
		"kevin":
			base = _offset("barrage", -18.0, -5.0)
		"radio":
			base = _offset("stand", -12.0, 5.0)
		_:
			return Vector3.ZERO
	var w := get_parent()
	if w and w.has_method("find_free_spawn"):
		base = w.find_free_spawn(base)
	_spots[name] = base
	return base


func _offset(zone: String, along: float, side: float) -> Vector3:
	if not zones.has(zone):
		return Vector3.ZERO
	var d: Vector2 = zone_dirs.get(zone, Vector2(0, 1))
	var perp := Vector2(-d.y, d.x)
	var o := Vector2(zones[zone].x, zones[zone].z) + d * along + perp * side
	return Vector3(o.x, zones[zone].y, o.y)


# --- Interaction (résolution partagée : indication HUD côté client, action côté serveur) -----

func nearest_ground_crate(pos: Vector3) -> String:
	var best := ""
	var best_d := PICK_RADIUS
	for id in crates:
		if crates[id].state == "ground":
			var d: float = (crates[id].pos as Vector3).distance_to(pos)
			if d < best_d:
				best_d = d
				best = id
	return best


func carried_by(peer: int) -> String:
	for id in crates:
		if crates[id].state == "carried" and crates[id].carrier == peer:
			return id
	return ""


## Que se passerait-il si ce joueur appuyait sur « interagir » ?
func resolve(peer: int, pos: Vector3) -> Dictionary:
	if step in ["done", "failed"]:
		return {}
	if van and van.driver == peer:
		return {"kind": "exit", "label": "Descendre de la camionnette"}
	var near_van := van != null and van.global_position.distance_to(pos) < VAN_RADIUS
	var held := carried_by(peer)
	if held != "":
		if near_van:
			return {"kind": "load", "id": held, "label": "Charger la caisse dans la camionnette"}
		return {"kind": "none", "label": "Rapportez la caisse à la camionnette"}
	var c := nearest_ground_crate(pos)
	if c != "":
		return {"kind": "pickup", "id": c, "label": "Prendre la caisse (%s)" % CRATE_NAMES.get(c, c)}
	if near_van and van.driver == 0:
		return {"kind": "enter", "label": "Monter dans la camionnette"}
	return {}


## Exécute l'interaction (serveur uniquement).
## `allowed` : types d'action permis (vide = tous) ; un compagnon IA n'essaie jamais de conduire.
func interact(peer: int, allowed: Array = []) -> void:
	if not is_server():
		return
	var player := _players_root.get_node_or_null(str(peer)) as Player
	if player == null:
		return
	var r := resolve(peer, player.global_position)
	if not allowed.is_empty() and not (r.get("kind", "") in allowed):
		return
	match r.get("kind", ""):
		"pickup":
			crates[r.id].state = "carried"
			crates[r.id].carrier = peer
			player.carrying = true
			_log("%s prend une caisse (%s)." % [player.display_name, CRATE_NAMES.get(r.id, r.id)])
		"load":
			crates[r.id].state = "loaded"
			crates[r.id].carrier = 0
			cargo += int(crates[r.id].bottles)
			player.carrying = false
			_log("Caisse chargée : %d bouteilles à bord." % cargo)
			if _all_loaded() and step == "crates":
				step = "road"
				_log("Tout est chargé. Cap sur le barrage de l'avenue du Bosc-Tenney !")
				_radio("chargement", "Tout est à bord ? Alors roulez doux : chaque cahot coûte une bouteille.")
		"enter":
			van.driver = peer
			van.controller = peer
			driver = peer
		"exit":
			_exit_van(player)
	_mark()


func _exit_van(player: Player) -> void:
	var left := -van.global_transform.basis.x
	var spot := van.global_position + left * 2.4
	var world := get_parent()
	if world.has_method("find_free_spawn"):
		spot = world.find_free_spawn(spot)
	van.driver = 0
	van.controller = 0
	driver = 0
	player.global_position = spot
	player.velocity = Vector3.ZERO
	_mark()


func _all_loaded() -> bool:
	for id in crates:
		if crates[id].state != "loaded":
			return false
	return true


func on_player_left(peer: int) -> void:
	if not is_server():
		return
	var held := carried_by(peer)
	if held != "":
		crates[held].state = "ground"
		crates[held].carrier = 0
	if van and van.driver == peer:
		van.driver = 0
		van.controller = 0
		driver = 0
	_mark()


# --- Déroulé (serveur) --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0:
			started = true
			root_progress().start(mission_id)
			_log("C'est parti : %d bouteilles de calva à livrer à la foire !" % bottles_total)
			_mark()
		return
	if step in ["done", "failed"]:
		return
	if not hazards_ready and not _hazards_tried and step in ["crates", "road"]:
		_hazards_tried = true
		_build_hazards()
		_push_hazards()
	_tick_hazards(delta)
	elapsed += delta
	if elapsed >= time_limit:
		_finish(false, "Temps écoulé : la foire est finie, le calva reste à la cave.")
	elif step == "road" and van and zones.has("barrage"):
		var d := van.global_position.distance_to(zones.barrage)
		if d < 220.0:
			_radio("barrage_vu", "Barrage en vue plus loin : un gendarme et sa moustache. Ginette est en position, Kévin aussi.")
		if d < ZONE_RADIUS:
			step = "checkpoint"
			checkpoint_left = CHECKPOINT_TIME
			failed_options.clear()
			_log("Barrage ! [1] Bluffer · [2] Contourner (+%d s) · [3] Diversion de Kévin. Décidez vite." % int(DETOUR_COST))
			_radio("barrage", "Le barrage est devant vous ! Moi je dis : laissez parler Ginette.")
			_mark()
	elif step == "checkpoint":
		checkpoint_left -= delta
		if checkpoint_left <= 0.0:
			# Personne n'a tranché : Ginette bluffe si elle est sur place, sinon on contourne.
			if distance_to_zone(ID_GINETTE, "barrage") < NEAR_BARRAGE:
				_log("Personne ne dit rien : Ginette prend la parole.")
				choose("bluff")
			else:
				_log("Personne ne dit rien : on contourne par les chemins.")
				choose("detour")
	elif step == "fair" and van and zones.has("stand"):
		if van.global_position.distance_to(zones.stand) < ZONE_RADIUS and van.speed_kmh() < 12.0:
			_finish(true, "")
	if started and step in ["crates", "road", "checkpoint", "fair"] and time_limit - elapsed < 180.0:
		_radio("trois_minutes", "Plus que trois minutes avant la fin de la foire !")
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD and (_dirty or fmod(elapsed, 1.0) < delta):
		_sync_t = 0.0
		_push_state()


# --- Événements de route ------------------------------------------------------------------------

## Point et direction de l'itinéraire à la distance `dist` (m depuis le départ).
func route_at(dist: float) -> Dictionary:
	var d := clampf(dist, 0.0, route_length)
	var acc := 0.0
	for i in range(route.size() - 1):
		var seg := route[i].distance_to(route[i + 1])
		if acc + seg >= d or i == route.size() - 2:
			var t := 0.0 if seg < 0.001 else clampf((d - acc) / seg, 0.0, 1.0)
			return {"pos": route[i].lerp(route[i + 1], t), "dir": (route[i + 1] - route[i]).normalized()}
		acc += seg
	return {"pos": route[route.size() - 1], "dir": Vector2.UP}


func _space_free(p: Vector2) -> bool:
	var w := get_parent()
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.1
	q.shape = sph
	q.transform = Transform3D(Basis(), Vector3(p.x, w.builder.height_at(p.x, p.y) + 1.4, p.y))
	return w.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Calcule l'itinéraire et place les événements (serveur, une fois la physique prête).
func _build_hazards() -> void:
	if van == null or not zones.has("barrage"):
		return
	var nav := RoadNav.load_default(true)
	route = nav.find_path(Vector2(van.global_position.x, van.global_position.z), Vector2(zones.barrage.x, zones.barrage.z))
	route_length = RoadNav.length_of(route)
	if route.size() < 4 or route_length < 80.0:
		return
	var h := {"potholes": [], "tractor": [], "cows": {}}
	# Nids-de-poule : sur la chaussée, un peu décalés pour qu'on puisse en éviter certains.
	for i in POTHOLE_FRACTIONS.size():
		var r := route_at(route_length * POTHOLE_FRACTIONS[i])
		var perp := Vector2(-r.dir.y, r.dir.x)
		var off := (-1.0 if i % 2 == 0 else 1.0) * (0.4 + 0.6 * float((i * 37) % 3) / 2.0)
		var p: Vector2 = r.pos + perp * off
		potholes.append(p)
		h.potholes.append([p.x, p.y])
	# Tracteur : de TRACTOR_FROM à TRACTOR_TO, il suit l'itinéraire à 3 m/s.
	var rs := route_at(route_length * TRACTOR_FROM)
	tractor_start = rs.pos
	_tractor_path = PackedVector2Array()
	var step_m := 4.0
	var dist := route_length * TRACTOR_FROM
	while dist < route_length * TRACTOR_TO:
		_tractor_path.append(route_at(dist).pos)
		dist += step_m
	_tractor_path.append(route_at(route_length * TRACTOR_TO).pos)
	h.tractor = [rs.pos.x, rs.pos.y, atan2(-rs.dir.x, -rs.dir.y)]
	# Vaches : une traversée où des deux côtés il y a de la place (sinon on se rabat sur le trottoir).
	var best := {}
	var frac := COW_FRACTION_MIN
	while frac <= COW_FRACTION_MAX and best.is_empty():
		var rc := route_at(route_length * frac)
		var across := Vector2(-rc.dir.y, rc.dir.x)
		for half in [7.0, 4.5, 3.2]:
			if _space_free(rc.pos - across * half) and _space_free(rc.pos + across * half):
				best = {"origin": rc.pos, "across": across, "dir": rc.dir, "half": half}
				break
		frac += 0.02
	if best.is_empty():
		var rc := route_at(route_length * 0.55)
		var across := Vector2(-rc.dir.y, rc.dir.x)
		best = {"origin": rc.pos, "across": across, "dir": rc.dir, "half": 3.2}
	cow_center = best.origin
	h.cows = {"origin": [best.origin.x, best.origin.y], "across": [best.across.x, best.across.y],
		"dir": [best.dir.x, best.dir.y], "half": best.half}
	_hazard_payload = h
	_make_hazard_nodes(h)
	tractor.start_route(_tractor_path)
	hazards_ready = true
	print("[mission] aléas : itinéraire %.0f m, %d nids-de-poule, tracteur dès %.0f m, vaches à %.0f m" % [route_length, potholes.size(), route_length * TRACTOR_FROM, route_length * 0.55])


## Crée les nœuds des aléas (identique sur tous les pairs, d'après la charge utile).
func _make_hazard_nodes(h: Dictionary) -> void:
	var w := get_parent()
	potholes.clear()
	for pn in _pothole_nodes:
		pn.queue_free()
	_pothole_nodes.clear()
	for pp in h.potholes:
		var v := Vector2(pp[0], pp[1])
		potholes.append(v)
		_pothole_nodes.append(_make_pothole(v))
	tractor_start = Vector2(h.tractor[0], h.tractor[1])
	if tractor == null:
		tractor = Tractor.new()
		tractor.name = "Tracteur"
		w.add_child(tractor)
	tractor.teleport(Vector3(tractor_start.x, w.builder.height_at(tractor_start.x, tractor_start.y) + 0.4, tractor_start.y), float(h.tractor[2]))
	var o := Vector2(h.cows.origin[0], h.cows.origin[1])
	var across := Vector2(h.cows.across[0], h.cows.across[1])
	var dir := Vector2(h.cows.dir[0], h.cows.dir[1])
	var half := float(h.cows.half)
	cow_center = o
	var rests := [-1.5, 0.1, 1.6]
	for i in 3:
		var cw: Cow
		if cows.size() > i:
			cw = cows[i]
		else:
			cw = Cow.new()
			cw.name = "Vache_%d" % i
			w.add_child(cw)
			cows.append(cw)
		cw.origin = o
		cw.across = across
		cw.rest_offset = rests[i]
		cw.exit_offset = half
		cw.state = "waiting"
		var cp := o + dir * (i - 1) * 2.4 - across * half
		cw.teleport(Vector3(cp.x, w.builder.height_at(cp.x, cp.y) + 0.4, cp.y), atan2(-across.x, -across.y))
	hazards_ready = true


## Nid-de-poule : disque sombre à rebord clair posé sur la chaussée.
func _make_pothole(p: Vector2) -> Node3D:
	var w := get_parent()
	var n := Node3D.new()
	n.name = "NidDePoule_%d" % _pothole_nodes.size()
	n.position = Vector3(p.x, w.builder.height_at(p.x, p.y) + 0.13, p.y)
	for spec in [[0.95, Color(0.55, 0.53, 0.5), 0.0], [0.72, Color(0.1, 0.08, 0.08), 0.012]]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = spec[0]
		cyl.bottom_radius = spec[0]
		cyl.height = 0.02
		cyl.radial_segments = 14
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/toon.gdshader")
		m.set_shader_parameter("couleur", spec[1])
		cyl.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = cyl
		mi.position.y = spec[2]
		mi.scale = Vector3(1.0, 1.0, 0.8)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
	w.add_child(n)
	return n


func _hit_pothole(i: int) -> void:
	var spd := absf(van.speed)
	var lost := clampi(int(ceil((spd - 3.0) / 5.0)), 0, mini(3, cargo))
	_pothole_cd[i] = 2.5
	jolt_serial += 1
	van.jolt()
	if lost > 0:
		cargo -= lost
		broken += lost
		_log("Nid-de-poule à %d km/h : %d bouteille%s de moins !" % [int(spd * 3.6), lost, "s" if lost > 1 else ""])
	else:
		_log("Nid-de-poule : vous passez doucement, rien de cassé.")
	_mark()


func _tick_hazards(delta: float) -> void:
	if not hazards_ready or van == null or step in ["done", "failed"]:
		return
	var vp := Vector2(van.global_position.x, van.global_position.z)
	var on_road := step == "road"
	if on_road:
		_radio("evenements", "Sur la route : des nids-de-poule, un tracteur et, paraît-il, des vaches. Klaxonnez [H] !")
	# Nids-de-poule : seule la vitesse compte (en dessous de 3 m/s on passe sans casse).
	for i in potholes.size():
		_pothole_cd[i] = maxf(_pothole_cd.get(i, 0.0) - delta, 0.0)
		if on_road and _pothole_cd[i] <= 0.0 and vp.distance_to(potholes[i]) < POTHOLE_RADIUS and absf(van.speed) > 0.5:
			_hit_pothole(i)
	# Tracteur : se réveille quand la camionnette approche, rentre à la ferme au bout du chemin.
	if on_road and not tractor_active and not tractor_done and vp.distance_to(tractor_start) < TRIGGER_DISTANCE:
		tractor_active = true
		tractor.set_active(true)
		_log("Un tracteur s'engage sur la route, devant vous. Doublez prudemment… ou prenez votre mal en patience.")
		_radio("tracteur", "Tracteur devant ! Il fait du 11 à l'heure, c'est Lepommier, il ne s'arrête jamais.")
		_mark()
	if tractor_active and tractor.finished:
		tractor_active = false
		tractor_done = true
		tractor.set_active(false)
		_log("Le tracteur tourne dans un champ : la route est libre.")
		_mark()
	# Vaches : elles traversent, s'arrêtent au milieu, repartent d'elles-mêmes ou au klaxon.
	if on_road and not cows_active and not cows_done and vp.distance_to(cow_center) < TRIGGER_DISTANCE:
		cows_active = true
		for cw in cows:
			cw.set_active(true)
			cw.state = "to_road"
		_log("Des vaches traversent la route ! Freinez, ou klaxonnez [H] pour les presser.")
		_radio("vaches", "Les vaches ! Elles sont trois, elles broutent le bitume. Un coup de klaxon et elles décampent.")
		_mark()
	if cows_active and not cows_done:
		var all_gone := true
		for cw in cows:
			all_gone = all_gone and cw.state == "gone"
		if all_gone:
			cows_done = true
			_log("Les vaches ont dégagé la route. Bonne continuation !")
			_mark()


## Klaxon (serveur) : les vaches à portée filent de l'autre côté.
func horn() -> void:
	if not is_server() or van == null or van.driver == 0:
		return
	var scared := 0
	for cw in cows:
		if cw.active and cw.state in ["to_road", "grazing"] and cw.global_position.distance_to(van.global_position) < HORN_RANGE:
			cw.startle()
			scared += 1
	horn_serial += 1
	_log("Pouet pouet !" + (" Les vaches détalent." if scared > 0 else ""))
	_mark()


func request_horn() -> void:
	if is_server():
		horn()
	else:
		_request_horn.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_horn() -> void:
	if is_server() and van and van.driver == multiplayer.get_remote_sender_id():
		horn()


@rpc("authority", "call_remote", "reliable")
func _set_hazards(h: Dictionary) -> void:
	_make_hazard_nodes(h)


# --- Barrage : choix d'équipe ---------------------------------------------------------------

## Tranche le barrage (serveur). `option` : bluff | detour | diversion.
func choose(option: String) -> void:
	if not is_server() or step != "checkpoint" or not (option in OPTIONS):
		return
	match option:
		"bluff":
			var ginette_here := distance_to_zone(ID_GINETTE, "barrage") < NEAR_BARRAGE
			var p := BLUFF_WITH_GINETTE if ginette_here else BLUFF_BASE
			var roll := test_roll if test_roll >= 0.0 else rng.randf()
			if ginette_here:
				_log("Ginette s'avance : « Bonjour mon p'tit gars, c'est pour la bonne cause ! »")
			else:
				_log("Vous tentez le bluff, sans Ginette pour amadouer le gendarme…")
			if roll < p:
				_log("Ça passe : le gendarme lève la barrière en souriant.")
			else:
				var lost := mini(CONFISCATED, cargo)
				cargo -= lost
				_log("Raté ! Le gendarme « goûte pour vérifier » : %d bouteilles saisies." % lost)
			_open_barrier()
		"detour":
			elapsed += DETOUR_COST
			_log("Détour par les chemins de terre : +%d s au compteur." % int(DETOUR_COST))
			_open_barrier()
		"diversion":
			if distance_to_zone(ID_KEVIN, "barrage") < NEAR_DIVERSION:
				_log("Kévin hurle « Au feu ! » en agitant un fanion : tous les gendarmes courent. La voie est libre !")
				_open_barrier()
			else:
				elapsed += DIVERSION_FAIL_COST
				failed_options.append("diversion")
				checkpoint_left = CHECKPOINT_TIME
				_log("Pas de Kévin à portée : la diversion tombe à plat (+%d s). Choisissez autre chose." % int(DIVERSION_FAIL_COST))
	_mark()


func _open_barrier() -> void:
	barrage_passed = true
	barrier_open = true
	step = "fair"
	checkpoint_left = 0.0
	_radio("foire", "La voie est libre ! Le stand du Comité est place Carnot, je vous vois d'ici.")


func _radio(key: String, text: String) -> void:
	if _radio_flags.has(key) or actor(ID_RADIO) == null:
		return
	_radio_flags[key] = true
	_log("Kévin Radio : " + text)
	_mark()


func request_choice(option: String) -> void:
	if is_server():
		choose(option)
	else:
		_request_choice.rpc_id(1, option)


@rpc("any_peer", "call_remote", "reliable")
func _request_choice(option: String) -> void:
	if is_server():
		choose(option)


func _on_impact(strength: float) -> void:
	if not is_server() or cargo <= 0 or step in ["done", "failed"]:
		return
	if strength < BREAK_THRESHOLD:
		return
	var lost := clampi(int((strength - BREAK_THRESHOLD) * 0.9) + 1, 1, cargo)
	cargo -= lost
	broken += lost
	_log("Aïe ! %d bouteille%s cassée%s (choc à %d km/h)." % [lost, "s" if lost > 1 else "", "s" if lost > 1 else "", int(strength * 3.6)])
	_mark()


func medal_for(bottles: int) -> String:
	if bottles >= medals.gold:
		return "gold"
	if bottles >= medals.silver:
		return "silver"
	if bottles >= medals.bronze:
		return "bronze"
	return ""


func root_progress() -> Node:
	return get_node("/root/Progress")


func _finish(ok: bool, why: String) -> void:
	if ok and cargo >= min_delivered:
		medal = medal_for(cargo)
		money = cargo * money_per_bottle
		step = "done"
		if is_server():
			var prog := root_progress()
			prog.add_money(money)
			prog.complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), rewards.get("vehicles", []))
		_log("Livré ! %d bouteilles au stand du Comité des fêtes. Médaille : %s. +%d €." % [cargo, {"gold": "or", "silver": "argent", "bronze": "bronze"}.get(medal, "aucune"), money])
	else:
		step = "failed"
		if ok:
			why = "Seulement %d bouteilles arrivées : il en fallait %d. Le Comité fait la moue." % [cargo, min_delivered]
		_log(why)
	_mark()
	_push_state()


func _log(text: String) -> void:
	messages.append(text)
	if messages.size() > 5:
		messages.pop_front()


func _mark() -> void:
	_dirty = true
	_refresh_nodes()
	changed.emit()


# --- Réplication ----------------------------------------------------------------------------

func state() -> Dictionary:
	var cs := {}
	for id in crates:
		cs[id] = [crates[id].state, crates[id].carrier]
	return {"step": step, "started": started, "elapsed": elapsed, "cargo": cargo, "broken": broken,
		"medal": medal, "money": money, "driver": driver, "crates": cs, "messages": messages, "barrage": barrage_passed,
		"cp_left": checkpoint_left, "failed": failed_options, "open": barrier_open,
		"tractor": tractor_active, "cows": cows_active, "jolt": jolt_serial, "horn": horn_serial}


func _push_state() -> void:
	_dirty = false
	var s := state()
	for id in Net.ready_peers():
		_sync.rpc_id(id, s)


## Un nouveau joueur reçoit l'état courant.
func send_full_state(peer: int) -> void:
	if is_server():
		if not _hazard_payload.is_empty():
			_set_hazards.rpc_id(peer, _hazard_payload)
		_sync.rpc_id(peer, state())


func _push_hazards() -> void:
	if _hazard_payload.is_empty():
		return
	for id in Net.ready_peers():
		_set_hazards.rpc_id(id, _hazard_payload)


@rpc("authority", "call_remote", "reliable")
func _sync(s: Dictionary) -> void:
	step = s.step
	started = s.started
	elapsed = s.elapsed
	cargo = s.cargo
	broken = s.broken
	medal = s.medal
	money = s.money
	driver = s.driver
	messages = s.messages
	barrage_passed = s.barrage
	checkpoint_left = s.cp_left
	failed_options = s.failed
	barrier_open = s.open
	if tractor and s.tractor != tractor_active:
		tractor_active = s.tractor
		tractor.set_active(tractor_active)
	if s.cows != cows_active:
		cows_active = s.cows
		for cw in cows:
			cw.set_active(cows_active)
	horn_serial = s.horn
	if s.jolt != jolt_serial:
		jolt_serial = s.jolt
		if van:
			van.jolt()
	for id in s.crates:
		if crates.has(id):
			crates[id].state = s.crates[id][0]
			crates[id].carrier = s.crates[id][1]
	if van:
		van.driver = driver
		van.controller = driver
	_refresh_nodes()
	changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if is_server():
		interact(multiplayer.get_remote_sender_id())


## Appelé par le joueur local (touche « interagir »).
func request_interact() -> void:
	if is_server():
		interact(multiplayer.get_unique_id())
	else:
		_request_interact.rpc_id(1)


# --- Caisses visibles --------------------------------------------------------------------------

func _make_crate_node(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Caisse_" + id
	var tris := []
	var box := BoxMesh.new()
	box.size = Vector3(0.75, 0.5, 0.55)
	var wood := ShaderMaterial.new()
	wood.shader = preload("res://shaders/toon.gdshader")
	wood.set_shader_parameter("couleur", Color(0.72, 0.5, 0.3))
	box.material = wood
	var bi := MeshInstance3D.new()
	bi.mesh = box
	bi.position.y = 0.25
	n.add_child(bi)
	tris.append_array(HullOutline.tris_of(box, Transform3D(Basis(), bi.position)))
	var bottle_mat := ShaderMaterial.new()
	bottle_mat.shader = preload("res://shaders/toon.gdshader")
	bottle_mat.set_shader_parameter("couleur", Color(0.85, 0.55, 0.15))
	bottle_mat.set_shader_parameter("reflet_force", 0.6)
	for i in 6:
		var b := CylinderMesh.new()
		b.top_radius = 0.045
		b.bottom_radius = 0.07
		b.height = 0.34
		b.radial_segments = 8
		b.material = bottle_mat
		var m := MeshInstance3D.new()
		m.mesh = b
		m.position = Vector3(-0.24 + (i % 3) * 0.24, 0.62, -0.1 + (i / 3) * 0.2)
		n.add_child(m)
	var hull := MeshInstance3D.new()
	hull.mesh = HullOutline.build(tris)
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(hull)
	n.position = crates[id].pos
	return n


func _refresh_nodes() -> void:
	var open := barrier_open or step in ["fair", "done"]
	if _barrier_body:
		_barrier_body.collision_layer = 0 if open else 1
	if _barrier_bar:
		_barrier_bar.position.y = 3.2 if open else 1.0       # la barre se relève
	for id in _crate_nodes:
		var n: Node3D = _crate_nodes[id]
		var c: Dictionary = crates[id]
		n.visible = c.state != "loaded"
		if c.state == "ground":
			n.position = c.pos
		elif c.state == "carried":
			var p := _players_root.get_node_or_null(str(c.carrier)) if _players_root else null
			if p:
				n.global_position = p.global_position + Vector3(0, 2.15, 0)


## Sons des événements : on compare l'état d'une image à la précédente (serveur et clients
## suivent donc le même chemin), sans rien rejouer au moment de la connexion.
var _snd := {}


func _crate_count(state_name: String) -> int:
	var n := 0
	for id in crates:
		if crates[id].state == state_name:
			n += 1
	return n


func _audio_events() -> void:
	var now := {"jolt": jolt_serial, "horn": horn_serial, "broken": broken, "loaded": _crate_count("loaded"),
		"carried": _crate_count("carried"), "step": step, "last": messages[-1] if messages.size() > 0 else ""}
	if _snd.is_empty():
		_snd = now
		return
	var at := van.global_position + Vector3(0, 1.0, 0) if van else Vector3.ZERO
	if now.jolt != _snd.jolt:
		Sfx.play_at("thud", at)
	if now.horn != _snd.horn:
		Sfx.play_at("klaxon", at)
	if now.broken > _snd.broken:
		Sfx.play_at("glass", at)
	if now.carried > _snd.carried:
		Sfx.play("crate")
	if now.loaded > _snd.loaded:
		Sfx.play("chime")
	if now.step != _snd.step:
		if now.step == "done":
			Sfx.play("fanfare" if medal != "" else "chime")
		elif now.step == "failed":
			Sfx.play("fail")
	if now.last != _snd.last and String(now.last).begins_with("Kévin Radio"):
		Sfx.play("radio_blip")
	_snd = now


func _process(_delta: float) -> void:
	_audio_events()
	# Une caisse portée suit son porteur.
	for id in crates:
		if crates[id].state == "carried" and _crate_nodes.has(id):
			var p := _players_root.get_node_or_null(str(crates[id].carrier)) if _players_root else null
			if p:
				(_crate_nodes[id] as Node3D).global_position = p.global_position + Vector3(0, 2.15, 0)
	# Les clients prolongent le chronomètre entre deux synchronisations.
	if not is_server() and started and step in ["crates", "road", "checkpoint", "fair"]:
		elapsed += _delta
		if step == "checkpoint":
			checkpoint_left = maxf(checkpoint_left - _delta, 0.0)
	# Le drapeau « porte une caisse » vient de l'état de mission, côté client aussi.
	if _players_root:
		for p in _players_root.get_children():
			if p is Player:
				(p as Player).carrying = carried_by((p as Player).peer_id) != ""


func companion_roles() -> Dictionary:
	return {-1: "arrimeur", -2: "negociatrice", -3: "guetteur", -4: "diversion"}


func result_text() -> String:
	if step == "done":
		return "Médaille : %s" % {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")
	if step == "failed":
		return "Mission ratée"
	return ""


## Panneau de mission du HUD.
func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	if step in ["crates", "road", "checkpoint", "fair"]:
		lines.append("Bouteilles intactes : %d / %d   (cassées : %d)   ·   Temps restant : %s" % [cargo, bottles_total, broken, format_time(time_limit - elapsed)])
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_status(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	match role:
		"arrimeur":
			if c.carrying:
				return "porte une caisse à la camionnette"
			return "s'occupe des caisses" if step == "crates" else "attend près de la camionnette"
		"negociatrice":
			return "négocie avec le gendarme" if step == "checkpoint" else "se tient prête au barrage"
		"diversion":
			return "prêt à faire diversion" if step == "checkpoint" else "se planque près du barrage"
		"guetteur":
			return "guette et commente à la radio"
	return "attend"


## Consignes affichées par le HUD.
func objective() -> String:
	match step:
		"crates":
			var left := 0
			for id in crates:
				if crates[id].state != "loaded":
					left += 1
			return "Récupérez les %d caisses (cave, grange, poulailler, fumier) et chargez-les dans la camionnette. Reste : %d." % [crates.size(), left]
		"road":
			return "Conduisez avec douceur : nids-de-poule, tracteur et vaches font casser ! Klaxon [H]. Direction le barrage de l'avenue du Bosc-Tenney."
		"checkpoint":
			var opts := "[1] Bluffer (Ginette)  ·  [2] Contourner (+%d s)  ·  [3] Diversion (Kévin)%s" % [int(DETOUR_COST), "  — diversion ratée" if "diversion" in failed_options else ""]
			return "Barrage de gendarmes ! %s. Décision dans %d s, sinon Ginette s'en charge." % [opts, int(ceil(checkpoint_left))]
		"fair":
			return "Le barrage est passé. Rendez-vous au stand du Comité des fêtes, place Carnot."
		"done":
			return "Mission accomplie."
		"failed":
			return "Mission échouée."
	return ""
