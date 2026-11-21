class_name CompanionBrain
extends RefCounted
## Cerveau d'un compagnon IA (agent 06), exécuté par le serveur uniquement.
## Il produit, à chaque pas physique, la même « entrée » qu'un joueur (déplacement, lacet,
## sprint) : le compagnon est simulé par `Player.simulate`, comme un humain.
##
## Rôle « arrimeur » (Tonton Gégé, mission 01) : il va chercher une caisse au sol, la rapporte
## à la camionnette et la charge. Il n'essaie jamais de monter dans la camionnette.

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
var mission: MissionM01
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
var _clock := 0.0
var _crate_since := 0.0
var _blacklist := {}                # id de caisse -> date (horloge du cerveau) de fin de mise à l'écart
var _strict := 0.0                  # > 0 : pas de raccourcis, on suit les points du graphe
var _hist_t := 0.0
var _hist_pos := Vector2.ZERO


func _init(p_body: Player, p_mission: MissionM01, p_nav: RoadNav) -> void:
	body = p_body
	mission = p_mission
	nav = p_nav


func idle() -> Dictionary:
	return {"move": Vector2.ZERO, "yaw": _last_yaw, "jump": false, "sprint": false}


## Entrée de ce pas.
func think(delta: float) -> Dictionary:
	_act_cooldown = maxf(_act_cooldown - delta, 0.0)
	_clock += delta
	if mission == null or mission.van == null or mission.step in ["done", "failed"]:
		status = "attend"
		return idle()
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
		if _wp < _path.size() - 1:
			_wp += 1
	if _jitter_t > 0.0:
		_jitter_t -= delta
		yaw += 1.1 * _jitter
	_last_yaw = yaw
	var far := Vector2(_target.x, _target.z).distance_to(here) > 6.0
	return {"move": Vector2(0, -1), "yaw": yaw, "jump": false, "sprint": far}
