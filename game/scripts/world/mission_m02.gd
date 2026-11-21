class_name MissionM02
extends MissionBase
## Mission 02 « Tuning du samedi soir » (agent 05), état à autorité serveur.
##
## Étapes (missions/m02_tuning_samedi.json) : parts (4 sources) → assembly (mini-jeux) →
## test_drive (course chronométrée + radar) → meet (jury) → drag (400 m contre Dylan, turbo unique).
## Ce qui n'est pas encore là : cinématique d'intro, répartition des rôles entre joueurs humains
## (pilote / chineur / mécano / ambianceur), mini-jeux de montage variés (un seul : le timing).
## Les paramètres viennent du JSON (copié dans res://assets/missions/).

const MISSION_FILE := "res://assets/missions/m02_tuning_samedi.json"
const SYNC_PERIOD := 0.25
const PARTS := ["jantes", "pot", "neons", "caisson", "aileron"]
const PART_NAMES := {"jantes": "Jantes", "pot": "Pot d'échappement", "neons": "Néons", "caisson": "Caisson de basses", "aileron": "Aileron"}
const PART_PRICE := {"jantes": 90, "pot": 120, "neons": 70, "caisson": 100, "aileron": 80}
const NEAR := {"casse": 7.0, "annonce": 4.5, "shop": 4.5, "dylan": 6.0, "garage": 6.0, "car": 4.5, "meet": 9.0, "start": 40.0}
const HAGGLE := [[0.4, 0.25], [0.6, 0.55], [0.8, 0.9]]     # [part du prix proposée, chance d'accord]
const GINETTE_BONUS := 0.3                                   # Ginette négocie mieux que quiconque
const SEARCH_TIME := 6.0
const SEARCH_COOLDOWN := 8.0
const HAGGLE_COOLDOWN := 10.0
const MINI_TIMEOUT := 7.0
const MINI_SPEED := 2.4
const MINI_ZONE := Vector2(0.38, 0.62)
const MECANO_SUCCESS := 0.7
const FLASH_FINE := 30
const FLASH_SPEED := 16.7                                    # 60 km/h
const TD_PAR_SPEED := 9.0                                    # m/s moyens attendus à l'essai
const COUNTDOWN := 3.0
const BOOST_TIME := 3.0
const BOOST_MIN_RATIO := 0.55                                # turbo avant 55 % de la vitesse max : moteur cassé
const RACE_TIMEOUT := 60.0
const START_HOUR := 15.0
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_KEVIN := -4
const WANTED_TIME := 90.0

# Paramètres du JSON.
var mission_id := "m02_tuning_samedi"
var budget_base := 400
var required_parts := 3
var jury_max := 10
var penalty_per_fail := 1
var drag_length := 400.0
var deadline_hour := 21.0
var rewards := {}

# État répliqué.
var budget := 0
var parts: Array = []
var sources: Dictionary = {"casse": false, "annonce": false, "auto_bling_27": false, "cour_dylan": false}
var wanted := 0
var wanted_left := 0.0
var flags: Array = []
var menu := ""                          # "" | "haggle" | "shop"
var menu_options: Array = []
var menu_peer := 0
var search_progress := -1.0             # -1 : pas de fouille ; 0..1 sinon
var assembly_idx := 0
var assembly_total := 0
var mini_t := 0.0
var mini_fails := 0
var cp_index := 0
var cp_total := 0
var flashed := false
var td_time := 0.0
var jury := {}                          # {look, son, presence, total}
var race_state := "idle"                # idle | countdown | go | finished
var race_count := 0.0
var race_sp := 0.0                      # progression du joueur sur la piste (m)
var race_sd := 0.0                      # progression de Dylan (m)
var race_time := 0.0
var boosts_left := 1
var times := {"player": 0.0, "dylan": 0.0}
var result := ""                        # "" | "win" | "lose"
var medal := ""
var test_roll := -1.0                   # tirage imposé (tests)
var rng := RandomNumberGenerator.new()

var zones := {}                         # name -> Vector3
var strip_dir := Vector2(0, 1)
var car: Car                            # = van (la Fusée)
var dylan: Car
var guard: Guard
var day_night: DayNight
var td_route := PackedVector2Array()
var td_points: Array = []               # points de contrôle (Vector2)
var td_radar := Vector2.ZERO
var td_par := 0.0
var _search_peer := 0
var _search_cd := 0.0
var _haggle_cd := 0.0
var _boost_left := 0.0
var _last_count := 0
var _spots := {}
var _td_nodes: Array = []
var _td_payload := {}
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _ground: Callable


func _ready() -> void:
	title = "Tuning du samedi soir"
	step = "parts"
	rng.seed = 20260102
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		budget_base = int(m.budget.solo)
		jury_max = int(m.steps[5].max) if m.steps.size() > 5 and m.steps[5].has("max") else 10
		for st in m.steps:
			if st.id == "assembly":
				penalty_per_fail = -int(st.penaltyPerFail)
			if st.id == "drag":
				drag_length = float(st.distanceM)
		var dl: PackedStringArray = str(m.deadline).split(":")
		deadline_hour = float(dl[0]) + float(dl[1]) / 60.0
		rewards = m.rewards


# --- Mise en place -----------------------------------------------------------------------------------------

func setup(pois: Array, ground: Callable, vehicle: Vehicle, players_root: Node3D) -> void:
	_ground = ground
	van = vehicle
	car = vehicle as Car
	_players_root = players_root
	var w := get_parent()
	day_night = w.get("day_night")
	var info := {}
	for p in pois:
		info[p.id] = p
	var map := {"garage_kevin": "garage", "voiture_kevin": "car_spawn", "casse_dugenou": "casse", "annonce_vendeur": "annonce",
		"auto_bling_27": "shop", "cour_dylan": "dylan", "parc_rdv": "meet", "drag_depart": "start", "drag_arrivee": "finish"}
	for id in map:
		if info.has(id):
			var x := float(info[id].position[0])
			var z := float(info[id].position[1])
			zones[map[id]] = Vector3(x, ground.call(x, z), z)
	if info.has("drag_depart"):
		var a := float(info.drag_depart.get("facing", 0.0))
		strip_dir = Vector2(sin(a), cos(a))
	# Adversaire et gardien : présents sur tous les pairs (mêmes noms).
	dylan = Car.new()
	dylan.name = "Dylan"
	dylan.body_color = Color(0.2, 0.35, 0.8)
	dylan.max_speed = 28.9
	dylan.accel = 9.15
	dylan.vehicle_name = "La Subaru de Dylan"
	dylan.ai_script = Callable(self, "_dylan_ai")
	if zones.has("start"):
		var lane := _lane(1)
		dylan.position = Vector3(lane.x, ground.call(lane.x, lane.y) + 0.5, lane.y)
		dylan.rotation.y = atan2(-strip_dir.x, -strip_dir.y)
	w.add_child.call_deferred(dylan)
	guard = Guard.new()
	guard.name = "Gardien"
	if zones.has("casse"):
		var c := Vector2(zones.casse.x, zones.casse.z)
		var perp := Vector2(-strip_dir.y, strip_dir.x)
		guard.a = c + perp * 9.0
		guard.b = c - perp * 9.0 + strip_dir * 4.0
		guard.position = Vector3(guard.a.x, ground.call(guard.a.x, guard.a.y) + 0.3, guard.a.y)
	w.add_child.call_deferred(guard)
	_activate_deferred.call_deferred()
	var humans := 1
	required_parts = 3
	budget = budget_base


func _activate_deferred() -> void:
	if guard:
		guard.set_active(true)


## Voie de la grille : -1 = joueur, +1 = Dylan (perpendiculaire à la piste, 2,5 m du centre).
func _lane(side: int) -> Vector2:
	var perp := Vector2(-strip_dir.y, strip_dir.x)
	var s := Vector2(zones.start.x, zones.start.z)
	return s + perp * 2.5 * side


func companion_roles() -> Dictionary:
	return {ID_GEGE: "ambianceur", ID_GINETTE: "chineuse", ID_KEVIN: "mecano"}


func look_target() -> Vector3:
	return zones.get("car_spawn", Vector3.ZERO)


## Emplacement d'attente d'un compagnon (calculé à la demande, physique prête).
func spot(name: String) -> Vector3:
	if _spots.has(name):
		return _spots[name]
	var base := Vector3.ZERO
	match name:
		"garage_kevin":
			base = _near_zone("garage", 2.5)
		"meet_gege":
			base = _near_zone("meet", 3.0)
		"annonce":
			base = _near_zone("annonce", 1.5)
		_:
			return Vector3.ZERO
	var w := get_parent()
	if w and w.has_method("find_free_spawn"):
		base = w.find_free_spawn(base)
	_spots[name] = base
	return base


func _near_zone(zone: String, side: float) -> Vector3:
	if not zones.has(zone):
		return Vector3.ZERO
	return zones[zone] + Vector3(side, 0.0, side * 0.6)


# --- Interaction ---------------------------------------------------------------------------------------------

func _dist(pos: Vector3, zone: String) -> float:
	if not zones.has(zone):
		return INF
	return Vector2(pos.x - zones[zone].x, pos.z - zones[zone].z).length()


func _near(pos: Vector3, zone: String) -> bool:
	return _dist(pos, zone) < float(NEAR[zone])


func resolve(peer: int, pos: Vector3) -> Dictionary:
	if step in ["done", "failed"]:
		return {}
	if menu != "" and menu_peer == peer:
		return {"kind": "none", "label": "Choisissez avec les touches 1 à %d" % menu_options.size()}
	if van and van.driver == peer:
		if step == "drag" and race_state == "idle" and _dist(van.global_position, "start") < float(NEAR.start):
			return {"kind": "start_race", "label": "Se placer sur la grille et lancer le départ"}
		return {"kind": "exit", "label": "Descendre de la Fusée"}
	match step:
		"parts":
			if _search_peer == peer and search_progress >= 0.0:
				return {"kind": "none", "label": "Fouille en cours (%d %%) : ne bougez pas, évitez le gardien" % int(search_progress * 100.0)}
			if _near(pos, "casse") and not sources.casse and _search_cd <= 0.0 and _search_peer == 0:
				return {"kind": "search", "label": "Fouiller la casse (restez immobile, le gardien rôde)"}
			if _near(pos, "annonce") and not sources.annonce and _haggle_cd <= 0.0:
				return {"kind": "haggle", "label": "Marchander les pièces de l'annonce"}
			if _near(pos, "shop"):
				return {"kind": "shop", "label": "Acheter des pièces chez Auto Bling 27 (prix +50 %)"}
			if _near(pos, "dylan") and not sources.cour_dylan:
				return {"kind": "steal", "label": "Piquer les néons dans la cour de Dylan (il vous reconnaîtra)"}
			if _near(pos, "garage") and parts.size() >= required_parts:
				return {"kind": "assemble", "label": "Monter les %d pièces avec Kévin" % parts.size()}
			if _near(pos, "garage"):
				return {"kind": "none", "label": "Il faut %d pièces avant de monter (vous en avez %d)" % [required_parts, parts.size()]}
		"assembly":
			if _near(pos, "garage"):
				return {"kind": "press", "label": "Appuyez quand le curseur est dans la zone verte !"}
		"test_drive", "meet", "drag":
			if van and van.driver == 0 and van.global_position.distance_to(pos) < float(NEAR.car):
				return {"kind": "enter", "label": "Monter dans la Fusée"}
	return {}


func interact(peer: int, allowed: Array = []) -> void:
	if not is_server():
		return
	var player := actor(peer) as Player
	if player == null:
		return
	var r := resolve(peer, player.global_position)
	var kind: String = r.get("kind", "")
	if kind == "" or kind == "none" or (not allowed.is_empty() and not (kind in allowed)):
		return
	match kind:
		"search":
			_search_peer = peer
			search_progress = 0.0
			_log("%s fouille la casse en silence…" % player.display_name)
		"haggle":
			_open_menu("haggle", peer)
		"shop":
			_open_menu("shop", peer)
		"steal":
			_steal(peer, player)
		"assemble":
			_start_assembly()
		"press":
			_mini_press(peer)
		"enter":
			van.driver = peer
			van.controller = peer
		"exit":
			_exit_car(player)
		"start_race":
			_start_race()
	_mark()


func _exit_car(player: Player) -> void:
	var left := -van.global_transform.basis.x
	var spot2 := van.global_position + left * 2.4
	var w := get_parent()
	if w.has_method("find_free_spawn"):
		spot2 = w.find_free_spawn(spot2)
	van.driver = 0
	van.controller = 0
	player.global_position = spot2
	player.velocity = Vector3.ZERO


func request_interact() -> void:
	if is_server():
		interact(multiplayer.get_unique_id())
	else:
		_request_interact.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if is_server():
		interact(multiplayer.get_remote_sender_id())


func request_choice(option: String) -> void:
	if is_server():
		choose_for(multiplayer.get_unique_id(), option)
	else:
		_request_choice.rpc_id(1, option)


@rpc("any_peer", "call_remote", "reliable")
func _request_choice(option: String) -> void:
	if is_server():
		choose_for(multiplayer.get_remote_sender_id(), option)


func request_boost() -> void:
	if is_server():
		boost(multiplayer.get_unique_id())
	else:
		_request_boost.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_boost() -> void:
	if is_server():
		boost(multiplayer.get_remote_sender_id())


# --- Menus : marchandage et boutique ---------------------------------------------------------------------------

func price_of(part: String, shop := false) -> int:
	var p: int = PART_PRICE[part]
	return int(ceil(p * 1.5)) if shop else p


func _open_menu(kind: String, peer: int) -> void:
	menu = kind
	menu_peer = peer
	menu_options = []
	if kind == "haggle":
		for h in HAGGLE:
			menu_options.append("Offrir %d %% du prix (%d €)" % [int(h[0] * 100), int(PART_PRICE.pot * h[0])])
	else:
		for part in PARTS:
			var owned: bool = part in parts
			menu_options.append("%s — %d €%s" % [PART_NAMES[part], price_of(part, true), " (déjà acheté)" if owned else ""])


## Choix dans le menu ouvert par `peer` (touches 1 à 5, ou IA).
func choose_for(peer: int, option: String) -> void:
	if not is_server() or menu == "" or menu_peer != peer or not option.is_valid_int():
		return
	var idx := int(option) - 1
	if idx < 0 or idx >= menu_options.size():
		return
	var who := actor(peer) as Player
	var name := who.display_name if who else "Quelqu'un"
	if menu == "haggle":
		var share: float = HAGGLE[idx][0]
		var chance: float = HAGGLE[idx][1] + (GINETTE_BONUS if peer == ID_GINETTE else 0.0)
		var offer := int(PART_PRICE.pot * share)
		var roll := test_roll if test_roll >= 0.0 else rng.randf()
		if offer > budget:
			_log("%s n'a pas de quoi offrir %d €." % [name, offer])
		elif roll < chance:
			budget -= offer
			_add_part("pot", "annonce")
			_log("%s : « Tope là ! » Pot d'échappement acheté %d €." % [name, offer])
			bark("m02_haggle_ok", 10.0)
		else:
			_haggle_cd = HAGGLE_COOLDOWN
			_log("Le père Bernard refuse : « Pour ce prix-là, je le garde ! » (réessayez dans %d s)" % int(HAGGLE_COOLDOWN))
			bark("m02_haggle_no", 10.0)
	elif menu == "shop":
		var part: String = PARTS[idx]
		var price := price_of(part, true)
		if part in parts:
			_log("Vous avez déjà : %s." % PART_NAMES[part])
		elif price > budget:
			_log("Trop cher : %s coûte %d €, il vous reste %d €." % [PART_NAMES[part], price, budget])
		else:
			budget -= price
			_add_part(part, "auto_bling_27")
			_log("Achat chez Auto Bling 27 : %s pour %d €." % [PART_NAMES[part], price])
	menu = ""
	menu_peer = 0
	menu_options = []
	_mark()


func _add_part(part: String, source: String) -> void:
	if not (part in parts):
		parts.append(part)
	if source == "annonce" or source == "casse" or source == "cour_dylan":
		sources[source] = true


func _steal(peer: int, player: Player) -> void:
	sources.cour_dylan = true
	_add_part("neons", "cour_dylan")
	wanted = 1
	wanted_left = WANTED_TIME
	if not ("dylan_recognizes_parts" in flags):
		flags.append("dylan_recognizes_parts")
	_log("%s embarque les néons de Dylan ! Recherché niveau 1 : la gendarmerie rôde. Dylan reconnaîtra ses pièces." % player.display_name)
	bark("m02_steal", 30.0)


# --- Casse : fouille furtive -----------------------------------------------------------------------------------------

func _tick_search(delta: float) -> void:
	_search_cd = maxf(_search_cd - delta, 0.0)
	_haggle_cd = maxf(_haggle_cd - delta, 0.0)
	if search_progress < 0.0:
		return
	var p := actor(_search_peer) as Player
	if p == null or not _near(p.global_position, "casse"):
		_cancel_search("Vous vous éloignez de la casse : fouille abandonnée.")
		return
	if Vector2(p.velocity.x, p.velocity.z).length() > 0.8:
		_cancel_search("Vous avez bougé : le tas s'effondre, la fouille est à refaire.")
		return
	if guard and guard.active and guard.can_see(p.global_position):
		guard.alert_left = 4.0
		_cancel_search("Le gardien vous a repéré ! « Eh, vous là-bas ! » Attendez qu'il s'éloigne.")
		_search_cd = SEARCH_COOLDOWN
		return
	search_progress += delta / SEARCH_TIME
	if search_progress >= 1.0:
		search_progress = -1.0
		_search_peer = 0
		if "jantes" in parts:
			sources.casse = true
			_log("La casse ne contient rien d'autre d'intéressant : vous avez déjà des jantes.")
		else:
			_add_part("jantes", "casse")
			sources.casse = true
			_log("Bingo : un jeu de jantes presque neuves dans la casse ! Personne ne vous a vu.")
			bark("m02_casse_bingo", 30.0)
		_mark()


func _cancel_search(text: String) -> void:
	search_progress = -1.0
	_search_peer = 0
	_log(text)
	_mark()


# --- Montage : mini-jeux de timing ------------------------------------------------------------------------------------

func mini_pos() -> float:
	return 0.5 + 0.5 * sin(mini_t * MINI_SPEED)


func _start_assembly() -> void:
	step = "assembly"
	assembly_total = parts.size()
	assembly_idx = 0
	mini_t = 0.0
	mini_fails = 0
	_log("Kévin déroule le cric : %d pièces à monter. Appuyez quand le curseur est dans la zone verte !" % assembly_total)


func _mini_press(_peer: int) -> void:
	var pos := mini_pos()
	_mini_result(pos >= MINI_ZONE.x and pos <= MINI_ZONE.y, false)


func _mini_result(ok: bool, by_kevin: bool) -> void:
	var part: String = parts[assembly_idx] if assembly_idx < parts.size() else ""
	if ok:
		_log("%s monté%s : %s." % [PART_NAMES.get(part, part), " par Kévin" if by_kevin else "", "nickel"])
	else:
		mini_fails += 1
		_log("Raté ! %s monté de travers (−%d point au jury)." % [PART_NAMES.get(part, part), penalty_per_fail])
		bark("m02_assembly_fail", 10.0)
	assembly_idx += 1
	mini_t = 0.0
	if assembly_idx >= assembly_total:
		_finish_assembly()


func _tick_assembly(delta: float) -> void:
	mini_t += delta
	if mini_t >= MINI_TIMEOUT:
		# Personne n'a appuyé : le mécano s'en charge (70 % de réussite), sinon c'est raté.
		var kevin_here := actor(ID_KEVIN) != null
		var roll := test_roll if test_roll >= 0.0 else rng.randf()
		_mini_result(kevin_here and roll < MECANO_SUCCESS, kevin_here)
		_mark()


func _finish_assembly() -> void:
	step = "test_drive"
	if car:
		car.set_parts(parts)
	_build_test_drive()
	_log("La Fusée est prête ! Essai routier : passez tous les points de contrôle, et levez le pied devant le radar.")


# --- Essai routier ------------------------------------------------------------------------------------------------------

func _build_test_drive() -> void:
	if not zones.has("car_spawn") or not zones.has("meet"):
		return
	var nav := RoadNav.load_default(true)
	td_route = nav.find_path(Vector2(zones.car_spawn.x, zones.car_spawn.z), Vector2(zones.meet.x, zones.meet.z))
	var total := RoadNav.length_of(td_route)
	var pts := []
	for f in [0.25, 0.5, 0.75]:
		pts.append(_route_point(total * f))
	pts.append(Vector2(zones.meet.x, zones.meet.z))
	td_points = pts
	td_radar = _route_point(total * 0.4)
	td_par = total / TD_PAR_SPEED + 20.0
	cp_index = 0
	cp_total = pts.size()
	td_time = 0.0
	flashed = false
	_td_payload = {"points": pts.map(func(p): return [p.x, p.y]), "radar": [td_radar.x, td_radar.y]}
	_make_td_nodes(_td_payload)
	for id in Net.ready_peers():
		_set_td.rpc_id(id, _td_payload)


func _route_point(dist: float) -> Vector2:
	var acc := 0.0
	for i in range(td_route.size() - 1):
		var seg := td_route[i].distance_to(td_route[i + 1])
		if acc + seg >= dist:
			return td_route[i].lerp(td_route[i + 1], clampf((dist - acc) / maxf(seg, 0.001), 0.0, 1.0))
		acc += seg
	return td_route[td_route.size() - 1]


@rpc("authority", "call_remote", "reliable")
func _set_td(h: Dictionary) -> void:
	_td_payload = h
	td_points = h.points.map(func(p): return Vector2(p[0], p[1]))
	td_radar = Vector2(h.radar[0], h.radar[1])
	cp_total = td_points.size()
	_make_td_nodes(h)


## Balises des points de contrôle et un radar (poteau et boîtier), identiques sur tous les pairs.
func _make_td_nodes(h: Dictionary) -> void:
	for n in _td_nodes:
		n.queue_free()
	_td_nodes.clear()
	var w := get_parent()
	for i in h.points.size():
		var p: Array = h.points[i]
		_td_nodes.append(_beacon(w, Vector2(p[0], p[1]), Color(0.3, 0.8, 0.95) if i < h.points.size() - 1 else Color(0.95, 0.75, 0.2), "Contrôle %d" % (i + 1) if i < h.points.size() - 1 else "Rendez-vous"))
	var r: Array = h.radar
	var radar := _beacon(w, Vector2(r[0], r[1]), Color(0.85, 0.25, 0.2), "Radar : 60 km/h")
	_td_nodes.append(radar)


func _beacon(w: Node, p: Vector2, color: Color, text: String) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(p.x, w.builder.height_at(p.x, p.y), p.y)
	var beam := CylinderMesh.new()
	beam.top_radius = 0.5
	beam.bottom_radius = 0.5
	beam.height = 18.0
	beam.radial_segments = 10
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(color, 0.32)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material = bm
	var mi := MeshInstance3D.new()
	mi.mesh = beam
	mi.position.y = 9.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var label := Label3D.new()
	label.text = text
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.pixel_size = 0.01
	label.outline_size = 12
	label.modulate = color.lightened(0.5)
	label.no_depth_test = true
	label.position.y = 6.0
	n.add_child(label)
	w.add_child(n)
	return n


func _tick_test_drive(delta: float) -> void:
	if car == null or td_points.is_empty():
		return
	td_time += delta
	var cp := Vector2(car.global_position.x, car.global_position.z)
	if cp_index < cp_total - 1 and cp.distance_to(td_points[cp_index]) < 12.0:
		cp_index += 1
		_log("Point de contrôle %d/%d franchi." % [cp_index, cp_total - 1])
		_mark()
	if not flashed and cp.distance_to(td_radar) < 10.0 and absf(car.speed) > FLASH_SPEED:
		flashed = true
		budget = maxi(budget - FLASH_FINE, 0)
		_log("FLASH ! %d km/h au radar : amende de %d €." % [int(absf(car.speed) * 3.6), FLASH_FINE])
		bark("m02_flash", 20.0)
		_mark()
	if cp_index >= cp_total - 1 and cp.distance_to(td_points[cp_total - 1]) < float(NEAR.meet) and absf(car.speed) < 3.0:
		_do_jury()


# --- Rendez-vous : le jury ---------------------------------------------------------------------------------------------------

## Notes du jury (0 à `jury_max`), fonction pure : testée.
static func jury_scores(installed: Array, gege_present: bool, flashed_radar: bool, on_time: bool, fails: int, dylan_flag: bool, penalty: int, maxi_score := 10) -> Dictionary:
	var look := clampi(2 + (3 if "jantes" in installed else 0) + (3 if "neons" in installed else 0) + (2 if "aileron" in installed else 0), 0, maxi_score)
	var son := clampi(2 + (4 if "pot" in installed else 0) + (4 if "caisson" in installed else 0), 0, maxi_score)
	var presence := clampi(3 + (4 if gege_present else 0) + (0 if flashed_radar else 1) + (2 if on_time else 0), 0, maxi_score)
	var avg := int(round((look + son + presence) / 3.0))
	var total := clampi(avg - fails * penalty - (1 if dylan_flag else 0), 0, maxi_score)
	return {"look": look, "son": son, "presence": presence, "total": total}


func _do_jury() -> void:
	var gege_here := actor(ID_GEGE) != null and Vector2(actor(ID_GEGE).global_position.x - zones.meet.x, actor(ID_GEGE).global_position.z - zones.meet.z).length() < 25.0
	jury = jury_scores(parts, gege_here, flashed, td_time <= td_par, mini_fails, "dylan_recognizes_parts" in flags, penalty_per_fail, jury_max)
	step = "drag"
	_log("Le jury délibère : look %d, son %d, présence %d. Note finale : %d/%d%s" % [jury.look, jury.son, jury.presence, jury.total, jury_max,
		"  (Dylan a reconnu ses néons : −1)" if "dylan_recognizes_parts" in flags else ""])
	bark("m02_jury", 30.0)
	_log("Place au drag : rendez-vous sur la ligne de départ, 400 m contre Dylan. Un seul turbo, à lancer quand le moteur est lancé !")
	_mark()


# --- Drag : 400 m contre Dylan ----------------------------------------------------------------------------------------------

func progress_on_strip(pos: Vector3) -> float:
	return (Vector2(pos.x, pos.z) - Vector2(zones.start.x, zones.start.z)).dot(strip_dir)


func _dylan_ai(c: Car, _delta: float) -> Dictionary:
	if race_state != "go":
		return {"move": Vector2.ZERO, "jump": false}
	var target := atan2(-strip_dir.x, -strip_dir.y)
	var diff := wrapf(target - c.rotation.y, -PI, PI)
	return {"move": Vector2(-clampf(diff * 2.0, -1.0, 1.0), -1.0), "jump": false}


func _start_race() -> void:
	race_state = "countdown"
	race_count = COUNTDOWN
	_last_count = int(ceil(COUNTDOWN))
	race_sp = 0.0
	race_sd = 0.0
	race_time = 0.0
	boosts_left = 1
	_boost_left = 0.0
	result = ""
	car.boosting = false
	car.engine_broken = false
	var yaw := atan2(-strip_dir.x, -strip_dir.y)
	var lp := _lane(-1)
	var ld := _lane(1)
	var w := get_parent()
	car.global_position = Vector3(lp.x, w.builder.height_at(lp.x, lp.y) + 0.5, lp.y)
	car.rotation.y = yaw
	car.velocity = Vector3.ZERO
	car.speed = 0.0
	dylan.global_position = Vector3(ld.x, w.builder.height_at(ld.x, ld.y) + 0.5, ld.y)
	dylan.rotation.y = yaw
	dylan.velocity = Vector3.ZERO
	dylan.speed = 0.0
	car.hold = true
	dylan.hold = true
	dylan.engine_on = true
	_log("Les moteurs rugissent ! Départ dans 3…")
	_push_state()


func boost(peer: int) -> void:
	if not is_server() or race_state != "go" or boosts_left <= 0 or van == null or van.driver != peer:
		return
	boosts_left -= 1
	if absf(car.speed) < BOOST_MIN_RATIO * car.max_speed:
		car.engine_broken = true
		_log("TURBO TROP TÔT ! Le moteur a surchauffé : plus que %d km/h." % int(Car.BROKEN_SPEED * 3.6))
		bark("m02_turbo_early", 30.0)
	else:
		car.boosting = true
		_boost_left = BOOST_TIME
		_log("TURBO ! Accrochez-vous !")
	_mark()
	_push_state()


func _tick_race(delta: float) -> void:
	match race_state:
		"countdown":
			race_count -= delta
			var c := int(ceil(race_count))
			if c != _last_count and c > 0:
				_last_count = c
				_log("%d…" % c)
				_mark()
			if race_count <= 0.0:
				race_state = "go"
				car.hold = false
				dylan.hold = false
				_log("PARTEZ !")
				_mark()
				_push_state()
		"go":
			race_time += delta
			race_sp = progress_on_strip(car.global_position)
			race_sd = progress_on_strip(dylan.global_position)
			if _boost_left > 0.0:
				_boost_left -= delta
				if _boost_left <= 0.0:
					car.boosting = false
					_mark()
			if race_sp >= drag_length or race_sd >= drag_length or race_time >= RACE_TIMEOUT:
				_finish_race()


func _finish_race() -> void:
	race_state = "finished"
	var player_first := race_sp >= race_sd
	times.player = race_time
	times.dylan = race_time
	result = "win" if player_first and race_sp >= drag_length else "lose"
	if race_time >= RACE_TIMEOUT:
		result = "lose"
	car.hold = true
	dylan.hold = true
	dylan.engine_on = false
	if result == "win":
		medal = "gold" if int(jury.get("total", 0)) >= 8 else "silver"
		_log("VICTOIRE ! Vous passez la ligne en %.1f s, Dylan est derrière." % race_time)
	else:
		medal = "bronze"          # « presented » : la voiture a été présentée au jury
		_log("Perdu : Dylan passe en premier. Mais la Fusée a été présentée !")
	step = "done"
	if is_server():
		var prog := get_node("/root/Progress")
		prog.data.money = maxi(budget, 0)           # ce qui reste du budget est conservé
		prog.complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), rewards.get("vehicle", "") if rewards.get("vehicle", "") is Array else [rewards.get("vehicle", "")])
	_mark()
	_push_state()


# --- Boucle serveur ----------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0:
			started = true
			get_node("/root/Progress").start(mission_id)
			budget = budget_base + get_node("/root/Progress").money()
			if day_night:
				day_night.hour = START_HOUR
			_log("Samedi, 15 h. Budget : %d € (400 € + vos gains précédents). Trouvez %d pièces avant 21 h !" % [budget, required_parts])
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	wanted_left = maxf(wanted_left - delta, 0.0)
	if wanted > 0 and wanted_left <= 0.0:
		wanted = 0
		_log("La gendarmerie vous a oublié (recherché : 0).")
		_mark()
	_tick_search(delta)
	if step == "assembly":
		_tick_assembly(delta)
	elif step == "test_drive":
		_tick_test_drive(delta)
	elif step == "drag":
		_tick_race(delta)
	if day_night and day_night.hour >= deadline_hour and step in ["parts", "assembly", "test_drive"]:
		step = "failed"
		_log("Il est 21 h : le samedi soir est fini, la Fusée reste au garage.")
		_mark()
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD and (_dirty or step == "drag" or step == "assembly"):
		_sync_t = 0.0
		_push_state()


func on_player_left(peer: int) -> void:
	if not is_server():
		return
	if _search_peer == peer:
		search_progress = -1.0
		_search_peer = 0
	if menu_peer == peer:
		menu = ""
		menu_peer = 0
	if van and van.driver == peer:
		van.driver = 0
		van.controller = 0
	_mark()


func _log(text: String) -> void:
	messages.append(text)
	if messages.size() > 6:
		messages.pop_front()


func _mark() -> void:
	_dirty = true
	changed.emit()


# --- Réplication -------------------------------------------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"step": step, "started": started, "elapsed": elapsed, "budget": budget, "parts": parts, "sources": sources,
		"wanted": wanted, "flags": flags, "menu": menu, "menu_options": menu_options, "menu_peer": menu_peer,
		"search": search_progress, "ai": assembly_idx, "at": assembly_total, "mt": mini_t, "mf": mini_fails,
		"cp": cp_index, "cpt": cp_total, "fl": flashed, "tdt": td_time, "jury": jury,
		"rs": race_state, "rc": race_count, "rsp": race_sp, "rsd": race_sd, "rt": race_time, "bl": boosts_left,
		"boost": car.boosting if car else false, "broken": car.engine_broken if car else false,
		"result": result, "medal": medal, "messages": messages, "driver": van.driver if van else 0, "par": td_par}


func _push_state() -> void:
	_dirty = false
	var s := state()
	for id in Net.ready_peers():
		_sync.rpc_id(id, s)


func send_full_state(peer: int) -> void:
	if is_server():
		if not _td_payload.is_empty():
			_set_td.rpc_id(peer, _td_payload)
		_sync.rpc_id(peer, state())


@rpc("authority", "call_remote", "reliable")
func _sync(s: Dictionary) -> void:
	step = s.step
	started = s.started
	elapsed = s.elapsed
	budget = s.budget
	var old_parts := parts.size()
	parts = s.parts
	sources = s.sources
	wanted = s.wanted
	flags = s.flags
	menu = s.menu
	menu_options = s.menu_options
	menu_peer = s.menu_peer
	search_progress = s.search
	assembly_idx = s.ai
	assembly_total = s.at
	mini_t = s.mt
	mini_fails = s.mf
	cp_index = s.cp
	cp_total = s.cpt
	flashed = s.fl
	td_time = s.tdt
	jury = s.jury
	race_state = s.rs
	race_count = s.rc
	race_sp = s.rsp
	race_sd = s.rsd
	race_time = s.rt
	boosts_left = s.bl
	result = s.result
	medal = s.medal
	messages = s.messages
	td_par = s.par
	if car:
		if parts.size() != car.installed.size() and step in ["test_drive", "drag", "done"]:
			car.set_parts(parts)
		car.boosting = s.boost
		car.engine_broken = s.broken
		car.driver = s.driver
		car.controller = s.driver
		car.hold = race_state == "countdown" or race_state == "finished"
	if dylan:
		dylan.hold = race_state == "countdown" or race_state == "finished"
		dylan.engine_on = race_state in ["countdown", "go"]
	changed.emit()


# --- Sons (mêmes déclencheurs sur tous les pairs) --------------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"parts": parts.size(), "fails": mini_fails, "flash": flashed, "rs": race_state, "step": step, "cp": cp_index,
		"assembly": assembly_idx, "count": int(ceil(race_count)) if race_state == "countdown" else 0}
	if _snd.is_empty():
		_snd = now
		return
	if now.parts > _snd.parts:
		Sfx.play("chime")
	if now.assembly > _snd.assembly and now.fails == _snd.fails:
		Sfx.play("crate")
	if now.fails > _snd.fails:
		Sfx.play("thud")
	if now.flash and not _snd.flash:
		Sfx.play("radio_blip")
	if now.cp > _snd.cp:
		Sfx.play("chime")
	if now.count != _snd.count and now.count > 0:
		Sfx.play("radio_blip")
	if now.rs == "go" and _snd.rs != "go":
		Sfx.play("klaxon")
	if now.step != _snd.step:
		if now.step == "done":
			Sfx.play("fanfare" if result == "win" else "chime")
		elif now.step == "failed":
			Sfx.play("fail")
	_snd = now


func _process(delta: float) -> void:
	_audio_events()
	if not is_server():
		if started and step == "assembly":
			mini_t += delta
		if started and step in ["test_drive"]:
			td_time += delta
		if race_state == "countdown":
			race_count = maxf(race_count - delta, 0.0)
		elif race_state == "go":
			race_time += delta
	for c in companions():
		(c as Player).carrying = false


# --- HUD ----------------------------------------------------------------------------------------------------------------------------------------

func hour_text() -> String:
	var h := day_night.hour if day_night else START_HOUR
	return "%d h %02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


func objective() -> String:
	match step:
		"parts":
			return "Trouvez %d pièces avant 21 h : la casse (furtif, gratuit), l'annonce (marchandage), Auto Bling 27 (cher) ou la cour de Dylan (volé). Puis direction le garage de Kévin." % required_parts
		"assembly":
			return "Montage : appuyez sur E quand le curseur est dans la zone verte (pièce %d/%d)." % [mini(assembly_idx + 1, assembly_total), assembly_total]
		"test_drive":
			return "Essai routier : montez dans la Fusée, passez les %d contrôles jusqu'au parking du rendez-vous. Radar : 60 km/h !" % maxi(cp_total - 1, 0)
		"drag":
			match race_state:
				"idle":
					return "Jury passé (%d/%d). Rendez-vous sur la ligne de départ du drag : E pour lancer. Turbo : Maj (une seule fois, moteur lancé !)." % [int(jury.get("total", 0)), jury_max]
				"countdown":
					return "Prêt ? %d…" % int(ceil(race_count))
				"go":
					return "400 m ! Turbo [Maj] quand le moteur est lancé (%s)." % ("disponible" if boosts_left > 0 else "utilisé")
		"done":
			return "Samedi soir terminé."
		"failed":
			return "Samedi soir raté."
	return ""


func mini_bar() -> String:
	var n := 24
	var pos := int(round(mini_pos() * (n - 1)))
	var z0 := int(round(MINI_ZONE.x * (n - 1)))
	var z1 := int(round(MINI_ZONE.y * (n - 1)))
	var s := ""
	for i in n:
		if i == pos:
			s += "█"
		elif i >= z0 and i <= z1:
			s += "▒"
		else:
			s += "·"
	return "[" + s + "]"


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	var owned: PackedStringArray = []
	for p in parts:
		owned.append(PART_NAMES[p])
	lines.append("Heure : %s (avant 21 h)   ·   Budget : %d €   ·   Pièces : %d/%d%s   ·   Recherché : %d" % [hour_text(), budget, parts.size(), required_parts, (" (" + ", ".join(owned) + ")") if not owned.is_empty() else "", wanted])
	if menu != "":
		lines.append("Menu :")
		for i in menu_options.size():
			lines.append("  [%d] %s" % [i + 1, menu_options[i]])
	if search_progress >= 0.0:
		lines.append("Fouille : %d %%" % int(search_progress * 100.0))
	if step == "assembly":
		lines.append("Montage %d/%d   %s   Ratés : %d" % [mini(assembly_idx + 1, assembly_total), assembly_total, mini_bar(), mini_fails])
	if step == "test_drive":
		lines.append("Contrôles : %d/%d   ·   Temps : %s (objectif %s)" % [cp_index, maxi(cp_total - 1, 0), MissionBase.format_time(td_time), MissionBase.format_time(td_par)])
	if step == "drag" and race_state in ["go", "finished"]:
		lines.append("Course : vous %d m   ·   Dylan %d m   ·   %.1f s" % [int(race_sp), int(race_sd), race_time])
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_status(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	match role:
		"mecano":
			return "monte les pièces avec vous" if step == "assembly" else "prépare le garage"
		"ambianceur":
			return "installe la sono au rendez-vous"
		"chineuse":
			return "marchande avec le père Bernard" if not sources.annonce else "a fini ses courses"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "%s — médaille : %s" % ["Victoire" if result == "win" else "Défaite", {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")]
	if step == "failed":
		return "Samedi soir raté"
	if step == "drag" and race_state == "countdown":
		return str(int(ceil(race_count)))
	return ""
