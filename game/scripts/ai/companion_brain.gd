class_name CompanionBrain
extends RefCounted
## Cerveau d'un compagnon IA (agent 06), exécuté par le serveur uniquement.
## Il produit, à chaque pas physique, la même « entrée » qu'un joueur (déplacement, lacet,
## sprint) : le compagnon est simulé par `Player.simulate`, comme un humain.
##
## Rôles (mission 02) : « mecano » (Kévin) attend au garage ; « ambianceur » (Gégé) prépare la sono au
## rendez-vous ; « chineuse » (Ginette) va marchander l'annonce du père Bernard (elle négocie mieux que tout le monde).
## Rôles (mission 01) :
##  - « arrimeur » (Tonton Gégé) : va chercher une caisse au sol, la rapporte à la camionnette et
##    la charge. N'essaie jamais de monter dedans ;
##  - « negociatrice » (Ginette) : se poste sur le trottoir au barrage ; sa présence rend le bluff sûr ;
##  - « diversion » (Kévin) : se planque près du barrage ; sans lui, la diversion échoue ;
##  - « guetteur » (Kévin Radio) : se poste près du stand de la foire et commente la route à la radio.

const ARRIVE_CRATE := 1.7           # distance de prise (la prise se fait à moins de 2,8 m)
const ARRIVE_VAN := 3.0
const WAYPOINT_RADIUS := 1.3
const REPLAN_PERIOD := 3.0
const STUCK_TIME := 0.7
const GIVE_UP_AFTER := 200.0        # s sans atteindre la caisse visée : on essaie une autre, puis on réessaie
const BLACKLIST_FOR := 90.0

var role := "arrimeur"
var status := "attend"              # texte lisible (HUD, tests)

var body: Player
var mission: MissionBase
var nav: RoadNav

var _target := Vector3.ZERO
var _path := PackedVector2Array()
var _wp := 0
var _replan_t := 0.0
var _stuck_t := 0.0
var _jitter_t := 0.0
var _jitter := 1.0
var _target_crate := ""
var _act_cooldown := 0.0
var _last_yaw := 0.0
var _skip_t := 0.0
var _errand_tries := 0
var _clock := 0.0
var _crate_since := 0.0
var _blacklist := {}                # id de caisse -> date (horloge du cerveau) de fin de mise à l'écart
var _stuck_count := 0
var _escape := Vector2.ZERO
var _back_t := 0.0                  # > 0 : on recule d'un pas pour se dégager d'un angle de mur
var _strict := 0.0                  # > 0 : pas de raccourcis, on suit les points du graphe
var _hist_t := 0.0
var _hist_pos := Vector2.ZERO


func _init(p_body: Player, p_mission: MissionBase, p_nav: RoadNav, p_role := "arrimeur") -> void:
	role = p_role
	body = p_body
	mission = p_mission
	nav = p_nav


func idle() -> Dictionary:
	return {"move": Vector2.ZERO, "yaw": _last_yaw, "jump": false, "sprint": false}


## Entrée de ce pas.
func think(delta: float) -> Dictionary:
	_act_cooldown = maxf(_act_cooldown - delta, 0.0)
	_clock += delta
	if mission == null or mission.step in ["done", "failed"] or (mission.van == null and not (mission is MissionM03 or mission is MissionM04 or mission is MissionM05)):
		status = "attend"
		return idle()
	match role:
		"negociatrice":
			return _hold("ginette", "se poste au barrage", "négocie avec le gendarme", delta)
		"diversion":
			return _hold("kevin", "se planque près du barrage", "est prêt à faire diversion", delta)
		"guetteur":
			return _hold("radio", "gagne son poste de guet", "guette depuis la place Carnot", delta)
		"mecano":
			return _hold("garage_kevin", "file au garage", "prépare le cric", delta)
		"ambianceur":
			return _hold("meet_gege", "gagne le rendez-vous", "installe la sono", delta)
		"chineuse":
			return _errand_haggle(delta)
		"electricien":
			return _post_m03("groupe", "gagne le groupe électrogène", "veille sur le groupe", delta)
		"videur":
			return _post_m03("videur", "gagne les portes", "tient les portes", delta)
		"saboteur":
			return _post_m03("clos", "file chez les rivaux", "sabote la sono rivale", delta)
		"cuisinier":
			return _post_m03("grill", "gagne le foyer", "tient le feu", delta)
		"gardien":
			return _post_m03("garde", "prend position", "garde le méchoui", delta)
		"serveur":
			return _serve_m04(delta)
		"rabatteur":
			return _herd_m05(delta)
		"guetteur" when mission is MissionM05:
			return _hold("watch", "gagne son poste de guet", "guette le troupeau", delta)
		"barriere":
			return _hold("gate", "gagne la barrière", "tient la barrière", delta)
	var me := body.peer_id
	var pos := body.global_position
	# 1. Une caisse sur l'épaule : direction la camionnette, puis chargement.
	if mission.carried_by(me) != "":
		_target_crate = ""
		status = "porte une caisse à la camionnette"
		var van_pos := mission.van.global_position
		if _horizontal(pos, van_pos) < ARRIVE_VAN:
			_try_interact(["load"])
			return idle()
		return _walk_to(van_pos, delta)
	# 2. Les mains libres : la caisse au sol la plus proche, tant qu'il en reste.
	if mission.step == "crates":
		var id := _pick_crate(pos)
		if id != "":
			status = "va chercher une caisse : %s" % MissionM01.CRATE_NAMES.get(id, id)
			var cp: Vector3 = mission.crates[id].pos
			if _horizontal(pos, cp) < ARRIVE_CRATE:
				_try_interact(["pickup"])
				return idle()
			return _walk_to(cp, delta)
	# 3. Plus rien à faire : il attend près de la camionnette, sans la gêner.
	status = "attend près de la camionnette"
	var spot := mission.van.global_position + mission.van.global_transform.basis.x * 3.4
	if _horizontal(pos, spot) > 2.0:
		return _walk_to(spot, delta)
	return idle()


## Rôles d'attente : va à son emplacement, puis y reste en regardant vers le barrage.
func _hold(spot_name: String, going: String, there: String, delta: float) -> Dictionary:
	var target := mission.spot(spot_name)
	if target == Vector3.ZERO:
		status = "attend"
		return idle()
	var pos := body.global_position
	if _horizontal(pos, target) > 2.0:
		status = going
		return _walk_to(target, delta)
	status = there if mission.step == "checkpoint" or role == "guetteur" else "attend en position"
	var focus: Vector3 = mission.look_target()
	if focus == Vector3.ZERO:
		focus = pos + Vector3(-sin(_last_yaw), 0.0, -cos(_last_yaw))
	var d := focus - pos
	_last_yaw = atan2(-d.x, -d.z)
	return {"move": Vector2.ZERO, "yaw": _last_yaw, "jump": false, "sprint": false}


## Mission 03 : d'abord son objet à rapporter (caisson, rallonge ou groupe), puis son poste.
func _post_m03(spot_name: String, going: String, there: String, delta: float) -> Dictionary:
	var m = mission
	var it: String = m.companion_item(body.peer_id)
	if m.step == m.ITEMS_STEP and it != "" and not m.item_taken(it):
		var target: Vector3 = m.item_pos.get(it, Vector3.ZERO)
		if target != Vector3.ZERO:
			status = "va chercher %s" % m.ITEM_NAMES[it]
			if _horizontal(body.global_position, target) < 2.2:
				_try_interact(["item"])
				return idle()
			return _walk_to(target, delta)
	return _hold(spot_name, going, there, delta)


## Mission 05, rabatteur : se place derrière la vache libre la plus proche (côté opposé à l'enclos) et siffle quand il est près.
func _herd_m05(delta: float) -> Dictionary:
	var m = mission
	if m.step != "herd":
		return _hold("gate", "gagne la barrière", "se repose", delta)
	var pos := body.global_position
	var here := Vector2(pos.x, pos.z)
	var target: Vector3 = m.herd_target(here)
	if target == Vector3.ZERO:
		return idle()
	var stray: Dictionary = m.nearest_stray(Vector2(m.zones.pen.x, m.zones.pen.z))
	status = "rabat %s" % MissionM05.COW_NAMES[int(stray.id) % MissionM05.COW_NAMES.size()]
	if _horizontal(pos, target) < 3.0:
		# En place : on avance vers la vache pour la pousser, et on siffle si elle est loin.
		if here.distance_to(Vector2(stray.x, stray.z)) < float(m.whistle_range) - 2.0:
			_try_interact(["whistle"])
		var toward := Vector2(stray.x, stray.z) - here
		var yaw := atan2(-toward.x, -toward.y)
		_last_yaw = yaw
		return {"move": Vector2(0, -1), "yaw": yaw, "jump": false, "sprint": false}
	if _clear(here, Vector2(target.x, target.z)):
		var d := Vector2(target.x, target.z) - here
		var yaw2 := atan2(-d.x, -d.y)
		_last_yaw = yaw2
		return {"move": Vector2(0, -1), "yaw": yaw2, "jump": false, "sprint": d.length() > 8.0}
	return _walk_to(target, delta)


## Mission 04, serveuse : prend une assiette au foyer et la porte à la table qui en a le moins reçu.
func _serve_m04(delta: float) -> Dictionary:
	var m = mission
	if m.step != "serve":
		return _post_m03("pass", "gagne le foyer", "attend l'agneau doré", delta)
	var pos := body.global_position
	if m.is_carrying(body.peer_id):
		var best := -1
		var best_n := 99
		for i in 4:
			if int(m.served[i]) < m.per_table and int(m.served[i]) < best_n:
				best_n = int(m.served[i])
				best = i
		if best < 0:
			return idle()
		var tp: Vector3 = m.table_pos(best)
		status = "porte une assiette à la table %d" % (best + 1)
		if _horizontal(pos, tp) < 2.4:
			_try_interact(["serve"])
			return idle()
		return _walk_to(tp, delta)
	status = "va chercher une assiette"
	var st: Vector3 = m.station()
	if _horizontal(pos, st) < 3.2:
		_try_interact(["take"])
		return idle()
	return _walk_to(st, delta)


## Course de Ginette : aller chez le père Bernard, proposer 60 % du prix (deux essais au plus).
func _errand_haggle(delta: float) -> Dictionary:
	var m := mission as MissionM02
	if m == null or m.step != "parts" or m.sources.get("annonce", false) or _errand_tries >= 2:
		status = "a fini ses courses"
		return idle()
	var target := m.spot("annonce")
	if target == Vector3.ZERO:
		return idle()
	if _horizontal(body.global_position, target) > 2.4:
		status = "va chez le père Bernard"
		return _walk_to(target, delta)
	status = "marchande avec le père Bernard"
	if _act_cooldown <= 0.0 and m._haggle_cd <= 0.0:
		_act_cooldown = 2.0
		m.interact(body.peer_id, ["haggle"])
		m.choose_for(body.peer_id, "2")
		_errand_tries += 1
	return idle()


func _pick_crate(pos: Vector3) -> String:
	if _target_crate != "" and mission.crates.has(_target_crate) and mission.crates[_target_crate].state == "ground":
		if _clock - _crate_since < GIVE_UP_AFTER:
			return _target_crate
		_blacklist[_target_crate] = _clock + BLACKLIST_FOR     # inaccessible ? on passe à une autre
		_path = PackedVector2Array()
	var best := ""
	var best_d := INF
	for id in mission.crates:
		if mission.crates[id].state == "ground" and _blacklist.get(id, 0.0) <= _clock:
			var d := _horizontal(pos, mission.crates[id].pos)
			if d < best_d:
				best_d = d
				best = id
	if best != _target_crate:
		_crate_since = _clock
	_target_crate = best
	return best


func _try_interact(allowed: Array) -> void:
	if _act_cooldown <= 0.0:
		_act_cooldown = 0.6
		mission.interact(body.peer_id, allowed)


## Ligne droite sans mur entre deux points (lancer de rayon à hauteur de poitrine ; les corps
## mobiles — joueurs, camionnette — ne bloquent pas).
func _clear(a: Vector2, b: Vector2) -> bool:
	var space := body.get_world_3d().direct_space_state
	var y := body.global_position.y + 0.9
	var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y))
	q.exclude = [body.get_rid()]
	for _i in 4:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit.collider is StaticBody3D:
			return false
		q.exclude.append(hit.collider.get_rid())   # un corps mobile : on regarde derrière
	return true


## Tire le chemin : à partir de chaque point, vise le plus lointain visible (borné à 14 points).
func _smooth(path: PackedVector2Array) -> PackedVector2Array:
	# Un premier point situé derrière nous (demi-tour net en ce point) est un détour : on le retire.
	while path.size() > 2 and (path[1] - path[0]).dot(path[2] - path[1]) < 0.0 and path[0].distance_to(path[1]) < 12.0:
		path.remove_at(1)
	if path.size() <= 2 or _strict > 0.0:
		return path
	var out := PackedVector2Array([path[0]])
	var i := 0
	while i < path.size() - 1:
		var j := mini(i + 14, path.size() - 1)
		while j > i + 1 and not _clear(path[i], path[j]):
			j -= 1
		out.append(path[j])
		i = j
	return out


static func _horizontal(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Marche vers `target` en suivant les rues ; contourne les blocages par un petit écart.
func _walk_to(target: Vector3, delta: float) -> Dictionary:
	var pos := body.global_position
	var here := Vector2(pos.x, pos.z)
	_replan_t -= delta
	if _path.is_empty() or _replan_t <= 0.0 or Vector2(target.x, target.z).distance_to(Vector2(_target.x, _target.z)) > 1.5:
		_target = target
		_path = _smooth(nav.find_path(here, Vector2(target.x, target.z)))
		_wp = 1
		_replan_t = REPLAN_PERIOD
	# Raccourci : si le point suivant est visible en ligne droite, on saute le point courant.
	_skip_t -= delta
	_strict = maxf(_strict - delta, 0.0)
	if _skip_t <= 0.0 and _strict <= 0.0:
		_skip_t = 0.25
		while _wp < _path.size() - 1 and _clear(here, _path[_wp + 1]):
			_wp += 1
	while _wp < _path.size() - 1 and here.distance_to(_path[_wp]) < WAYPOINT_RADIUS:
		_wp += 1
	var goal: Vector2 = _path[mini(_wp, _path.size() - 1)]
	var d := goal - here
	if d.length() < 0.05:
		return idle()
	var yaw := atan2(-d.x, -d.y)
	# Blocage : peu de vitesse, ou — plus sûr — presque aucun déplacement net en 2,5 s alors
	# qu'on marche (glissement contre un obstacle) => on dévie, on suit les points du graphe
	# à la lettre un moment, et on recalcule.
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	_stuck_t = _stuck_t + delta if speed < 0.8 else 0.0
	_hist_t += delta
	var stuck := _stuck_t > STUCK_TIME
	if _hist_t >= 2.5:
		_hist_t = 0.0
		if here.distance_to(_hist_pos) < 1.5:
			stuck = true
			_strict = 8.0
		_hist_pos = here
	if stuck:
		_stuck_t = 0.0
		_jitter_t = 0.9
		_jitter = -_jitter
		_replan_t = 0.0
		_stuck_count += 1
		if _stuck_count % 3 == 0:
			_back_t = 1.2           # plusieurs blocages de suite : on rejoint le sommet de route le plus proche, tout droit
			_escape = nav.closest_vertex(here)
		elif _wp < _path.size() - 1:
			_wp += 1
	if _back_t > 0.0:
		_back_t -= delta
		var ed := _escape - here
		var eyaw := atan2(-ed.x, -ed.y) if ed.length() > 0.3 else yaw
		_last_yaw = eyaw
		return {"move": Vector2(0, -1), "yaw": eyaw, "jump": false, "sprint": false}
	if _jitter_t > 0.0:
		_jitter_t -= delta
		yaw += 1.1 * _jitter
	_last_yaw = yaw
	var far := Vector2(_target.x, _target.z).distance_to(here) > 6.0
	return {"move": Vector2(0, -1), "yaw": yaw, "jump": false, "sprint": far}
