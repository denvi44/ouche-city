class_name MissionM01
extends Node
## Mission 01 « Le Calva de Tonton Gégé » (agent 05), état à autorité serveur.
##
## Étapes jouables : caisses (4 sources) → route (camionnette, cargaison fragile) → barrage de
## l'avenue du Bosc-Tenney (choix d'équipe automatique : bluff) → stand de foire → médaille.
## Ce qui n'est pas encore là : cinématique d'intro, choix d'équipe votés, événements de route
## (nids-de-poule, tracteur, vaches), compagnons IA, livraison à pied (livrée à l'arrivée).
## Les paramètres viennent de missions/m01_calva_gege.json (copié dans res://assets/missions/).

signal changed          ## État mis à jour (client et serveur) : le HUD se rafraîchit.

const MISSION_FILE := "res://assets/missions/m01_calva_gege.json"
const PICK_RADIUS := 2.8
const VAN_RADIUS := 4.2
const ZONE_RADIUS := 9.0
const BREAK_THRESHOLD := 3.5       # perte de vitesse (m/s) à partir de laquelle ça casse
const SYNC_PERIOD := 0.25

const CRATE_POIS := ["cave_gege", "grange_pommiers", "poulailler_ginette", "fumier_tas"]
const CRATE_NAMES := {"cave_gege": "la cave de Gégé", "grange_pommiers": "la grange", "poulailler_ginette": "le poulailler", "fumier_tas": "le tas de fumier"}

# Paramètres issus du JSON.
var title := "Le Calva de Tonton Gégé"
var time_limit := 1110.0
var bottles_total := 24
var bottles_per_crate := 6
var min_delivered := 12
var medals := {"gold": 22, "silver": 16, "bronze": 12}
var money_per_bottle := 20

# État répliqué.
var step := "crates"            # crates | road | fair | done | failed
var started := false
var elapsed := 0.0
var cargo := 0                  # bouteilles intactes dans la camionnette
var broken := 0
var medal := ""
var money := 0
var driver := 0
var crates := {}                # id -> {"state": ground|carried|loaded, "carrier": peer, "pos": Vector3, "bottles": int}
var messages: Array = []        # derniers événements (texte)
var barrage_passed := false

var van: Vehicle
var zones := {}                 # "barrage" / "stand" -> Vector3
var _crate_nodes := {}
var _dirty := true
var _sync_t := 0.0
var _players_root: Node3D


func _ready() -> void:
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
		elif p.id == "stand_comite":
			zones["stand"] = Vector3(pos2.x, h, pos2.y)
	for id in crates:
		_crate_nodes[id] = _make_crate_node(id)
		get_parent().add_child.call_deferred(_crate_nodes[id])
	_refresh_nodes()


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


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
func interact(peer: int) -> void:
	if not is_server():
		return
	var player := _players_root.get_node_or_null(str(peer)) as Player
	if player == null:
		return
	var r := resolve(peer, player.global_position)
	match r.get("kind", ""):
		"pickup":
			crates[r.id].state = "carried"
			crates[r.id].carrier = peer
			player.carrying = true
			_log("%s prend la caisse de %s." % [player.display_name, CRATE_NAMES.get(r.id, r.id)])
		"load":
			crates[r.id].state = "loaded"
			crates[r.id].carrier = 0
			cargo += int(crates[r.id].bottles)
			player.carrying = false
			_log("Caisse chargée : %d bouteilles à bord." % cargo)
			if _all_loaded() and step == "crates":
				step = "road"
				_log("Tout est chargé. Cap sur le barrage de l'avenue du Bosc-Tenney !")
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
			_log("C'est parti : %d bouteilles de calva à livrer à la foire !" % bottles_total)
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	if elapsed >= time_limit:
		_finish(false, "Temps écoulé : la foire est finie, le calva reste à la cave.")
	elif step == "road" and van and zones.has("barrage"):
		if van.global_position.distance_to(zones.barrage) < ZONE_RADIUS:
			barrage_passed = true
			step = "fair"
			_log("Barrage : le gendarme croit à votre bluff (« c'est pour la bonne cause »).")
			_mark()
	elif step == "fair" and van and zones.has("stand"):
		if van.global_position.distance_to(zones.stand) < ZONE_RADIUS and van.speed_kmh() < 12.0:
			_finish(true, "")
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD and (_dirty or fmod(elapsed, 1.0) < delta):
		_sync_t = 0.0
		_push_state()


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


func _finish(ok: bool, why: String) -> void:
	if ok and cargo >= min_delivered:
		medal = medal_for(cargo)
		money = cargo * money_per_bottle
		step = "done"
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
		"medal": medal, "money": money, "driver": driver, "crates": cs, "messages": messages, "barrage": barrage_passed}


func _push_state() -> void:
	_dirty = false
	var s := state()
	for id in Net.ready_peers():
		_sync.rpc_id(id, s)


## Un nouveau joueur reçoit l'état courant.
func send_full_state(peer: int) -> void:
	if is_server():
		_sync.rpc_id(peer, state())


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


func _process(_delta: float) -> void:
	# Une caisse portée suit son porteur.
	for id in crates:
		if crates[id].state == "carried" and _crate_nodes.has(id):
			var p := _players_root.get_node_or_null(str(crates[id].carrier)) if _players_root else null
			if p:
				(_crate_nodes[id] as Node3D).global_position = p.global_position + Vector3(0, 2.15, 0)
	# Les clients prolongent le chronomètre entre deux synchronisations.
	if not is_server() and started and step in ["crates", "road", "fair"]:
		elapsed += _delta
	# Le drapeau « porte une caisse » vient de l'état de mission, côté client aussi.
	if _players_root:
		for p in _players_root.get_children():
			if p is Player:
				(p as Player).carrying = carried_by((p as Player).peer_id) != ""


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
			return "Conduisez, avec douceur : ça casse ! Direction le barrage de l'avenue du Bosc-Tenney."
		"fair":
			return "Le barrage est passé. Rendez-vous au stand du Comité des fêtes, place Carnot."
		"done":
			return "Mission accomplie."
		"failed":
			return "Mission échouée."
	return ""
