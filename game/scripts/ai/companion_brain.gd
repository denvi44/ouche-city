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
var _rp := 0                         # indice du prochain point d'un parcours fixe (missions 04-06)
var _rk := ""                        # clé du parcours en cours
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
	if mission == null or mission.step in ["done", "failed"] or (mission.van == null and not (mission is MissionM03 or mission is MissionM04 or mission is MissionM05 or mission is MissionM06 or mission is MissionM07 or mission is MissionM08 or mission is MissionM09)):
		status = "attend"
		return idle()
	if not mission.companions_help():
		return _guide(delta)             # solo par défaut : les compagnons guident, ils ne font pas les tâches du joueur
	match role:
		"negociatrice":
			return _hold("ginette", "se poste au barrage", "négocie avec le gendarme", delta)
		"diversion" when not (mission is MissionM07):
			return _hold("kevin", "se planque près du barrage", "est prêt à faire diversion", delta)
		"guetteur" when mission is MissionM09:
			return _watch_m09(delta)
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
		"rabatteuse":
			return _goose_gather(delta)
		"sentinelle":
			return _goose_sentry(delta)
		"ferme_file":
			return _goose_line(delta)
		"portier":
			return _hold("porte", "file ouvrir la porte", "attend à la porte, la clé à la main", delta)
		"diversion" when mission is MissionM07:
			return _hold("hubert", "gagne le chemin de Mme Hubert", "tient la jambe à Mme Hubert", delta)
		"file":
			return _hold("wc", "file aux toilettes publiques", "garde la file des toilettes", delta)
		"caddie":
			return _shop_m06(delta)
		"bavarde":
			return _chat_m06(delta)
		"chauffeur":
			status = "attend au volant, moteur au ralenti"
			return idle()
		"porteur", "chargeur":
			return _siege_m09(delta)
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


## Indice du point de parcours le plus proche (hors point d'arrivée) : on reprend le trajet là où l'on est.
func _nearest_point(pts: Array) -> int:
	var here := Vector2(body.global_position.x, body.global_position.z)
	var best := -1
	var bd := INF
	# Le point le plus proche DONT la ligne droite est dégagée (un rayon de gondole ne compte pas) : sinon un compagnon
	# qui sort d'une allée peut viser le point d'à côté, de l'autre côté du rayon, et rester collé contre.
	for i in maxi(pts.size() - 1, 1):
		var pv := Vector2(pts[i].x, pts[i].z)
		var d := here.distance_to(pv)
		if d < bd and _clear(here, pv):
			bd = d
			best = i
	if best >= 0:
		return best
	for i in maxi(pts.size() - 1, 1):
		var d2 := here.distance_to(Vector2(pts[i].x, pts[i].z))
		if d2 < bd or best < 0:
			bd = d2
			best = i
	return maxi(best, 0)


## Suit une liste de points monde en ligne droite (parcours dans les allées du supermarché) ; renvoie true à l'arrivée.
func _follow_points(pts: Array, delta: float) -> Dictionary:
	var pos := body.global_position
	var here := Vector2(pos.x, pos.z)
	while _rp < pts.size() - 1 and here.distance_to(Vector2(pts[_rp].x, pts[_rp].z)) < 0.9:
		_rp += 1
	var tgt: Vector3 = pts[mini(_rp, pts.size() - 1)]
	var d := Vector2(tgt.x, tgt.z) - here
	if d.length() < 0.25:
		return {}
	var yaw := atan2(-d.x, -d.y)
	_last_yaw = yaw
	return {"move": Vector2(0, -1), "yaw": yaw, "jump": false, "sprint": false}


## Mission 09, guetteuse : rejoint en ligne droite son poste près de la catapulte (terrain nu, hors du graphe routier), puis regarde les Bretons.
func _watch_m09(delta: float) -> Dictionary:
	var target: Vector3 = mission.spot("watch")
	if target == Vector3.ZERO:
		status = "attend"
		return idle()
	var pos := body.global_position
	if _horizontal(pos, target) > 1.5:
		status = "gagne son poste de guet"
		var inp := _follow_points([target], delta)
		return inp if not inp.is_empty() else idle()
	status = "guette les Bretons"
	var d: Vector3 = mission.look_target() - pos
	_last_yaw = atan2(-d.x, -d.z)
	return {"move": Vector2.ZERO, "yaw": _last_yaw, "jump": false, "sprint": false}


## Mission 09, porteur / chargeur : navette entre l'étal le plus proche et la catapulte (mode « coéquipiers »).
func _siege_m09(delta: float) -> Dictionary:
	var m = mission
	var me := body.peer_id
	var pos := body.global_position
	if m.carriers.has(me):
		var cat: Vector3 = m.zones.catapult
		status = "porte un camembert à la catapulte"
		if _horizontal(pos, cat) < m.NEAR_CATAPULT - 1.0:
			_try_interact(["load"])
			return idle()
		return _walk_to(cat, delta)
	var i: int = m.nearest_stock(pos)
	if i < 0:
		status = "attend"
		return idle()
	var st: Vector3 = m.stocks[(i + (1 if body.peer_id == ID_KEVIN_BRAIN else 0)) % m.stocks.size()]
	status = "file chercher un camembert à l'étal"
	if _horizontal(pos, st) < m.NEAR_STOCK - 1.0:
		_try_interact(["take"])
		return idle()
	return _walk_to(st, delta)


## Mission 06, caddie : va chercher ses articles (à 2 à l'heure) en suivant les allées.
func _shop_m06(delta: float) -> Dictionary:
	var m = mission
	for it in m.companion_items(body.peer_id):
		if it in m.items_got:
			continue
		var pts: Array = m.route_to(it)
		if _rk != it:
			_rk = it
			_rp = _nearest_point(pts)
		var goal: Vector3 = pts[pts.size() - 1]
		status = "va chercher %s" % m.ITEM_NAMES[it]
		if _horizontal(body.global_position, goal) < 1.3:
			_try_interact(["read"])
			return idle()
		var inp := _follow_points(pts, delta)
		return inp if not inp.is_empty() else idle()
	status = "a rempli sa part du cabas"
	return idle()


## Mission 06, bavarde : file dire bonjour à Mme Hubert et ne la lâche plus.
func _chat_m06(delta: float) -> Dictionary:
	var m = mission
	var pts: Array = m.route_to_chat()
	if _horizontal(body.global_position, pts[pts.size() - 1]) < 1.0:
		status = "papote avec Mme Hubert dans l'allée"
		return idle()
	status = "va dire bonjour à Mme Hubert"
	if _rk != "chat":
		_rk = "chat"
		_rp = 0
	var inp := _follow_points(pts, delta)
	return inp if not inp.is_empty() else idle()


## Mission 05, rabatteur : se place derrière la vache libre la plus proche (côté opposé à l'enclos) et siffle quand il est près.
var _herd_cow := -1
var _human_last := Vector2.ZERO
var _human_active := 0.0


func _herd_m05(delta: float) -> Dictionary:
	var m = mission
	if m.step != "herd":
		return _hold("gate", "gagne la barrière", "se repose", delta)
	var pos := body.global_position
	var here := Vector2(pos.x, pos.z)
	# Kévin prend la vache la plus éloignée du joueur (les retardataires) pour ne pas gêner celui qui rentre les plus proches.
	# La vache choisie est gardée jusqu'à son entrée dans l'enclos (sinon la cible oscille au fil des déplacements).
	# Un joueur immobile ne rabat rien : Kévin ne se réserve les retardataires que si un humain est actif.
	var hp: Vector2 = m.human_pos()
	if hp.distance_to(_human_last) > 0.5:
		_human_active = 12.0
		_human_last = hp
	_human_active = maxf(0.0, _human_active - delta)
	var far: bool = m.humans() > 0 and _human_active > 0.0
	var stray: Dictionary = {}
	if _herd_cow >= 0:
		for c in m.cows:
			if int(c.id) == _herd_cow and c.st != "pen":
				stray = c
	if stray.is_empty():
		stray = m.farthest_stray(m.human_pos()) if far else m.nearest_stray(Vector2(m.zones.pen.x, m.zones.pen.z))
		_herd_cow = int(stray.id) if not stray.is_empty() else -1
	if stray.is_empty():
		return idle()
	var cow_p := Vector2(stray.x, stray.z)
	var goal: Vector2 = m.push_goal(cow_p)
	var away: Vector2 = (cow_p - goal).normalized()
	var tp: Vector2 = cow_p + away * 7.0
	var target := Vector3(tp.x, 0.0, tp.y)
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


# --- Mode « guide » (solo par défaut) --------------------------------------------------------------------------------------------------
# Les compagnons accompagnent le joueur sans jamais agir sur la mission : pas d'objet pris, pas de bête rabattue, pas de service.
# Le premier d'entre eux passe devant, vers la balise d'objectif, et attend le joueur ; les autres restent à proximité.
const GUIDE_AHEAD := 11.0         # m : le guide marche à cette distance devant le joueur, en direction de la balise
const GUIDE_WAIT := 20.0          # m : au-delà, le guide s'arrête et attend
const GUIDE_NEAR := 6.5           # m : les accompagnateurs ne bougent pas tant que le joueur est plus près
const GUIDE_TELEPORT := 90.0      # m : très loin (le joueur a pris le volant) : le compagnon se retrouve près de lui
var _hint_t := 0.0
const ID_KEVIN_BRAIN := -4


func _human_node() -> Node3D:
	return mission.actor(mission.local_peer())


func _guide_slot() -> int:
	# 0 = le guide (le compagnon d'identifiant le plus proche de 0), 1.. = accompagnateurs.
	var ids: Array = []
	for c in mission.companions():
		ids.append(absi((c as Player).peer_id))
	ids.sort()
	return maxi(ids.find(absi(body.peer_id)), 0)


func _guide(delta: float) -> Dictionary:
	var m = mission
	var hp := _human_node()
	if hp == null:
		status = "attend"
		return idle()
	var pp := hp.global_position
	var hv := Vector2(pp.x, pp.z)
	var here := Vector2(body.global_position.x, body.global_position.z)
	var d_me := here.distance_to(hv)
	var slot := _guide_slot()
	if d_me > GUIDE_TELEPORT:
		var a := float(slot) * 2.1
		body.global_position = pp + Vector3(cos(a) * 8.0, 0.5, sin(a) * 8.0)
		body.velocity = Vector3.ZERO
		return idle()
	var marks: Array = m.focus_markers()
	var goal := Vector3.ZERO
	var label := ""
	if not marks.is_empty():
		goal = marks[0].pos
		label = str(marks[0].label)
	var gv := Vector2(goal.x, goal.z)
	var d_goal := gv.distance_to(hv) if goal != Vector3.ZERO else 0.0
	# Un petit mot toutes les 45 s tant que le joueur est loin de son but.
	if d_goal > 14.0:
		_hint_t += delta
		if _hint_t > 45.0 and slot == 0:
			_hint_t = 0.0
			m.bark("%s_guide" % m.dialogue_prefix(), 45.0)
	else:
		_hint_t = 0.0
	if slot == 0 and goal != Vector3.ZERO and d_goal > 14.0:
		if d_me > GUIDE_WAIT:
			status = "t'attend (suis la balise : %s)" % label
			return _face(hv, here)
		var dir := (gv - hv).normalized()
		var ahead := hv + dir * minf(GUIDE_AHEAD, d_goal - 8.0)
		status = "te montre le chemin : %s" % label
		return _walk_to(Vector3(ahead.x, pp.y, ahead.y), delta)
	# Accompagnateur (ou guide arrivé) : reste à proximité, sur une couronne propre à chaque compagnon.
	status = "reste près de toi"
	if d_me < GUIDE_NEAR:
		return _face(hv, here)
	var ang := float(slot) * 2.1 + 0.6
	var spot := hv + Vector2(cos(ang), sin(ang)) * 4.0
	return _walk_to(Vector3(spot.x, pp.y, spot.y), delta)


func _face(target: Vector2, here: Vector2) -> Dictionary:
	var d := target - here
	if d.length() > 0.1:
		_last_yaw = atan2(-d.x, -d.y)
	return {"move": Vector2.ZERO, "yaw": _last_yaw, "jump": false, "sprint": false}


## Mission 08, rabatteuse : va vers l'oie libre la plus proche, crie quand elle est à portée, puis mène la file jusqu'à la voie.
func _goose_gather(delta: float) -> Dictionary:
	var m = mission
	var pos := body.global_position
	var here := Vector2(pos.x, pos.z)
	var mine: Array = m.followers_of(body.peer_id)
	var free: Dictionary = m.nearest_free(here)
	if not mine.is_empty() and (free.is_empty() or mine.size() >= 6):
		status = "mène les oies jusqu'à la voie"
		return _walk_to(m.spot("crossing"), delta)
	if not free.is_empty() and m.train.st in ["wait", "run"]:
		var fp := Vector3(float(free.x), 0.0, float(free.z))
		status = "va chercher une oie égarée"
		if _horizontal(pos, fp) < 9.0:
			_try_interact(["honk"])
			status = "crie pour rassembler les oies"
			return idle()
		return _walk_to(fp, delta)
	status = "tient la voie avec les autres"
	return _hold("line_side", "gagne la voie", "tient la voie avec les autres", delta)


## Mission 08, sentinelle : attend près de la maisonnette ; quand le garde-barrière approche, elle fonce et lui crie dans les oreilles.
func _goose_sentry(delta: float) -> Dictionary:
	var m = mission
	var pos := body.global_position
	var mp := Vector3(float(m.master.x), 0.0, float(m.master.z))
	if m.master.st in ["walk", "shoo"]:
		status = "fonce sur le garde-barrière"
		if _horizontal(pos, mp) < 6.0:
			_try_interact(["honk"])
			return idle()
		return _walk_to(mp, delta)
	return _hold("hut_side", "gagne la maisonnette du garde-barrière", "guette le garde-barrière", delta)


## Mission 08, ferme-file : se poste au bord de la voie et crie à intervalles réguliers pour rassurer les oies qui y sont.
func _goose_line(delta: float) -> Dictionary:
	var m = mission
	var out := _hold("line_side", "gagne le bord de la voie", "rassure les oies sur la voie", delta)
	if m.blockers() > 0 and m.train.st in ["brake", "stopped"] and at_post_goose():
		_try_interact(["honk"])
	return out


func at_post_goose() -> bool:
	var s: Vector3 = mission.spot("line_side")
	return s != Vector3.ZERO and _horizontal(body.global_position, s) < 3.5


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
	# Deux hauteurs : bas (jardinières, bancs, bornes) et poitrine (murs, mâts).
	return _clear_at(a, b, 0.9)


func _clear_at(a: Vector2, b: Vector2, h: float) -> bool:
	var space := body.get_world_3d().direct_space_state
	var y := body.global_position.y + h
	var from := Vector3(a.x, y, a.y)
	var to := Vector3(b.x, y, b.y)
	var dir := (to - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [body.get_rid()]
	q.collision_mask = 1                 # le mobilier de rue (couche 2) ne gêne pas les compagnons
	for _i in 10:
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit.collider is StaticBody3D:
			# Une pente douce du terrain (valleys jusqu'à −48 m) n'est pas un obstacle : on la franchit, on ne s'arrête que sur un mur ou un talus raide.
			# Seulement pour le sol des tuiles (« …/Tuile_x_y/Collisions ») : les meubles et comptoirs restent des obstacles.
			if absf((hit.normal as Vector3).y) < 0.6 or not str((hit.collider as Node).get_path()).contains("/Tuile_"):
				return false
			q.from = (hit.position as Vector3) + dir * 0.1
			continue
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
