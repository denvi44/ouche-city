class_name MissionM07
extends MissionBase
## Mission 07 « Le jus de pomme de Tonton Gégé » (agent 05) : rentrer aux toilettes, de la fête de la pomme à la maison, à temps.
##
## Le jus « maison » de Gégé était un peu vif : la pression monte sans cesse (plus vite en courant, sur les pavés, aux crampes
## et aux frayeurs). On peut **serrer** (E : bascule) pour ralentir la montée au prix d'une marche de crabe (2 m/s) et d'une endurance
## qui s'épuise ; s'arrêter aux toilettes publiques (file d'attente) ; chez soi, la porte est fermée à clé (clé sous le pot de fleurs, ou
## Ginette qui l'a). À 100 %, c'est l'accident : mission ratée. Humour tendre : on ne montre rien, on entend un « PRRRT ! » et on rit.
## Chaque joueur humain a sa propre pression ; tout l'état vit côté serveur et est répliqué (`_sync`).

const MISSION_FILE := "res://assets/missions/m07_jus_de_pomme.json"
const SYNC_PERIOD := 0.2
const START_HOUR := 16.0
const NEAR := {"door": 2.4, "wc": 3.0, "hubert": 2.4, "dog": 7.0, "post": 3.0}
const BASE_RATE := 0.006                           # par seconde, à l'arrêt
const WALK_ADD := 0.002                            # au-dessus de 1 m/s
const RUN_ADD := 0.008                             # au-dessus de 5 m/s
const COBBLE_ADD := 0.012                          # sur les pavés, au-dessus de 2,5 m/s
const CLENCH_FACTOR := 0.4
const CLENCH_SPEED := 2.0                          # m/s : marche de crabe
const STAMINA_DRAIN := 0.05
const STAMINA_REGEN := 0.08
const RELEASE_TIME := 3.0                          # s sans pouvoir serrer quand l'endurance tombe à zéro
const RELEASE_SPIKE := 0.05
const SPASM_PRESSURE := 0.04
const SPASM_CLENCHED := 0.015
const SPASM_EVERY := Vector2(9.0, 13.0)
const DOG_SCARE := 0.08
const START_PRESSURE := 0.2
const CHAT_TIME := 6.0
const CHAT_CUT := 1.5
const QUEUE_TIME := 15.0
const QUEUE_TIME_FAST := 7.0                       # quand Kévin Radio garde la file
const WC_RELIEF := 0.55
const SEARCH_TIME := 5.0
const GOLD_PRESSURE := 0.7
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_RADIO := -3
const ID_KEVIN := -4
const ROUTE_FRACS := {"cobbles": 0.3, "hubert": 0.5, "dog": 0.78}
const COBBLE_RADIUS := 14.0

var mission_id := "m07_jus_de_pomme"
var time_limit := 150.0
var rewards := {}

# --- État répliqué ---
var victims := {}                           # pair -> {p: pression, st: endurance, cl: serre, rel: s sans serrer, fz: "", ft: s}
var time_left := 150.0
var spasms := 0
var chat_done := false
var dog_done := false
var door_open := false
var result := ""                            # "" | "home" | "wc" | "accident" | "late"
var medal := ""
var best_pressure := 0.0                    # pression à l'arrivée (bilan)

var rng := RandomNumberGenerator.new()
var zones := {}                             # stand, wc, door -> Vector3
var facings := {}
var route := PackedVector2Array()
var route_len := 0.0
var spots := {}
var test_speed := {}                        # pair -> vitesse imposée (tests)
var day_night: DayNight
var _ground: Callable
var _spasm_t := 10.0
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _nodes := {}
var _clock := 0.0
var _chat_peer := 0
var _chat_left := 0.0
var _queue_for := 0.0
var _search_for := 0.0
var _unlock_t := 0.0


func _ready() -> void:
	title = "Le jus de pomme de Tonton Gégé"
	step = "run"
	rng.seed = 20260107
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		time_limit = float(m.timeLimitSec)
		rewards = m.rewards
	time_left = time_limit


# --- Mise en place -------------------------------------------------------------------------------------------

func setup(pois: Array, ground: Callable, _vehicle: Vehicle, players_root: Node3D) -> void:
	_ground = ground
	_players_root = players_root
	var w := get_parent()
	day_night = w.get("day_night")
	for p in pois:
		var key := ""
		match p.id:
			"fete_pomme":
				key = "stand"
			"wc_publics":
				key = "wc"
			"chez_soi":
				key = "door"
		if key != "":
			var x := float(p.position[0])
			var z := float(p.position[1])
			zones[key] = Vector3(x, ground.call(x, z), z)
			facings[key] = float(p.get("facing", 0.0))
	_compute_route()
	_build_visuals.call_deferred()


## Trajet à pied du stand à la porte (graphe routier des piétons) : sert à placer les événements sur le chemin.
func _compute_route() -> void:
	if not (zones.has("stand") and zones.has("door")):
		return
	var nav := RoadNav.load_default()
	var a := Vector2(zones.stand.x, zones.stand.z)
	var d := _front_point("door", 1.6)
	route = nav.find_path(a, Vector2(d.x, d.z))
	route_len = RoadNav.length_of(route)


func _front_point(zone: String, dist: float) -> Vector3:
	var f: float = facings.get(zone, 0.0)
	var base: Vector3 = zones.get(zone, Vector3.ZERO)
	return base + Vector3(sin(f), 0, cos(f)) * dist


## Point du trajet à la fraction `t` (0 = stand, 1 = porte), au sol.
func route_point(t: float) -> Vector3:
	if route.size() < 2:
		return zones.get("stand", Vector3.ZERO)
	var target := clampf(t, 0.0, 1.0) * route_len
	var acc := 0.0
	for i in route.size() - 1:
		var seg := route[i].distance_to(route[i + 1])
		if acc + seg >= target and seg > 0.0:
			var q := route[i].lerp(route[i + 1], (target - acc) / seg)
			return Vector3(q.x, _ground.call(q.x, q.y) if _ground.is_valid() else 0.0, q.y)
		acc += seg
	var l := route[route.size() - 1]
	return Vector3(l.x, _ground.call(l.x, l.y) if _ground.is_valid() else 0.0, l.y)


func spot(name: String) -> Vector3:
	if spots.has(name):
		return spots[name]
	var base := Vector3.ZERO
	match name:
		"porte":
			base = _front_point("door", 2.4)
		"hubert":
			base = route_point(ROUTE_FRACS.hubert)
		"wc":
			base = _front_point("wc", 2.6)
		"cobbles":
			base = route_point(ROUTE_FRACS.cobbles)
		"dog":
			base = route_point(ROUTE_FRACS.dog)
		"stand":
			base = _front_point("stand", 3.0)
		_:
			return Vector3.ZERO
	if base == Vector3.ZERO:
		return base
	var w := get_parent()
	if name in ["porte", "hubert", "wc", "stand"] and w and w.has_method("find_free_spawn"):
		base = w.find_free_spawn(base)
	spots[name] = base
	return base


func _build_visuals() -> void:
	var w := get_parent()
	if zones.is_empty():
		return
	# Tonton Gégé au stand ; Mme Hubert sur le trajet ; le chien du portail ; deux clients à la file des toilettes ; le pot de fleurs.
	var gege := CharacterModel.make(Color(0.72, 0.52, 0.3), Color(0.3, 0.38, 0.55), Color(0.6, 0.5, 0.35), Player.OUTFITS[-1].style)
	gege.name = "GegeStand"
	gege.pose_override = {"speed": 0.0}
	w.add_child(gege)
	var gs := _front_point("stand", 0.2)
	gege.global_position = Vector3(gs.x, gs.y, gs.z) + Vector3(0.8, 0.1, -0.3)
	gege.rotation.y = float(facings.stand)
	var hub := CharacterModel.make(Color(0.5, 0.65, 0.4), Color(0.4, 0.35, 0.3), Color(0.75, 0.7, 0.8), {"hair": Color(0.8, 0.8, 0.85), "hair_style": "bun", "headgear": "none", "glasses": true, "scarf": Color(0.85, 0.6, 0.3)})
	hub.name = "MmeHubert"
	hub.pose_override = {"speed": 0.0}
	w.add_child(hub)
	var hp := route_point(ROUTE_FRACS.hubert)
	hub.global_position = hp + Vector3(1.2, 0.1, 0.8)
	var dog := PropKit.dog().build()
	dog.name = "ChienDuPortail"
	var dp := route_point(ROUTE_FRACS.dog)
	dog.position = dp + Vector3(2.0, 0.05, 1.0)
	w.add_child(dog)
	for i in 2:
		var cl := CharacterModel.make([Color(0.3, 0.45, 0.8), Color(0.8, 0.35, 0.3)][i], Color(0.22, 0.24, 0.32), Color(0.2, 0.2, 0.25), Player.default_style(11 + i * 4))
		cl.name = "File_%d" % i
		cl.pose_override = {"speed": 0.0}
		w.add_child(cl)
		var q := _front_point("wc", 4.0 + float(i) * 1.1)
		cl.global_position = Vector3(q.x, q.y + 0.1, q.z)
		cl.rotation.y = float(facings.wc) + PI
	var pot := PropKit.flowerpot().build()
	pot.name = "PotDeFleurs"
	var pp := _front_point("door", 0.9)
	var f: float = facings.door
	pot.position = pp + Vector3(cos(f), 0, -sin(f)) * 1.5
	w.add_child(pot)


func companion_roles() -> Dictionary:
	return {ID_GINETTE: "portier", ID_KEVIN: "diversion", ID_RADIO: "file"}


func look_target() -> Vector3:
	return zones.get("door", Vector3.ZERO)


func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func at_post(id: int, name: String) -> bool:
	var a := actor(id)
	var s := spot(name)
	return a != null and s != Vector3.ZERO and _dist(a.global_position, s) < float(NEAR.post)


func humans() -> Array:
	var out := []
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai:
				out.append((p as Player).peer_id)
	return out


func victim(peer: int) -> Dictionary:
	return victims.get(peer, {})


func pressure_of(peer: int) -> float:
	return float(victim(peer).get("p", 0.0))


# --- Pression : fonctions pures (testées) -----------------------------------------------------------------------------------------------

## Vitesse de montée de la pression (par seconde) : à l'arrêt, au pas, en courant, sur les pavés ; divisée si l'on serre.
static func pressure_rate(speed: float, clenched: bool, on_cobbles: bool) -> float:
	var r := BASE_RATE
	if speed > 1.0:
		r += WALK_ADD
	if speed > 5.0:
		r += RUN_ADD
	if on_cobbles and speed > 2.5:
		r += COBBLE_ADD
	return r * (CLENCH_FACTOR if clenched else 1.0)


func medal_for(p: float, at_home: bool) -> String:
	if not at_home:
		return "bronze"
	return "gold" if p <= GOLD_PRESSURE else "silver"


func on_cobbles(pos: Vector3) -> bool:
	var c := spot("cobbles")
	return c != Vector3.ZERO and _dist(pos, c) < COBBLE_RADIUS


## Plafond de vitesse d'un joueur (m/s) : nul quand il est retenu (causette, file, recherche de la clé), 2 m/s s'il serre.
func cap_for(peer: int) -> float:
	if step in ["done", "failed"]:
		return INF
	var v := victim(peer)
	if v.is_empty():
		return INF
	if str(v.fz) != "":
		return 0.0
	if bool(v.cl):
		return CLENCH_SPEED
	return INF


# --- Interaction -------------------------------------------------------------------------------------------------------------------------

func resolve(peer: int, pos: Vector3) -> Dictionary:
	if step in ["done", "failed"] or zones.is_empty():
		return {}
	var v := victim(peer)
	if v.is_empty():
		return {}
	if str(v.fz) == "chat":
		return {"kind": "cut", "label": "Mme Hubert vous raconte sa hanche (E : couper court, poliment)"}
	if str(v.fz) != "":
		return {"kind": "none", "label": {"queue": "Vous faites la queue… (le verrou : OCCUPÉ)", "search": "Vous cherchez la clé sous le pot de fleurs…"}.get(str(v.fz), "…")}
	if _dist(pos, spot("wc")) < float(NEAR.wc) and step == "run":
		return {"kind": "queue", "label": "Faire la queue aux toilettes publiques (soulagement certain, mais c'est occupé)"}
	if _dist(pos, _front_point("door", 1.0)) < float(NEAR.door):
		if door_open or at_post(ID_GINETTE, "porte"):
			return {"kind": "enter", "label": "Entrer chez vous et courir aux toilettes !"}
		return {"kind": "search", "label": "La porte est fermée à clé : chercher sous le pot de fleurs"}
	return {"kind": "clench", "label": ("Relâcher (E)" if bool(v.cl) else "Serrer les fesses (E) : marche de crabe, la pression monte moins vite") if float(v.rel) <= 0.0 else "Vous ne tenez plus… (%d s)" % int(ceil(float(v.rel)))}


func interact(peer: int, allowed: Array = []) -> void:
	if not is_server():
		return
	var player := actor(peer) as Player
	if player == null or not victims.has(peer):
		return
	var r := resolve(peer, player.global_position)
	var kind: String = r.get("kind", "")
	if kind == "" or kind == "none" or (not allowed.is_empty() and not (kind in allowed)):
		return
	var v: Dictionary = victims[peer]
	match kind:
		"clench":
			if float(v.rel) <= 0.0:
				v.cl = not bool(v.cl)
				if v.cl and float(v.st) <= 0.05:
					v.cl = false
				if v.cl:
					bark("m07_clench", 40.0)
		"cut":
			_chat_left = maxf(_chat_left - CHAT_CUT, 0.0)
			if _chat_left <= 0.0:
				_end_chat(peer)
		"queue":
			v.fz = "queue"
			v.ft = QUEUE_TIME_FAST if at_post(ID_RADIO, "wc") else QUEUE_TIME
			v.cl = false
			_log("%s fait la queue aux toilettes publiques… « Occupé ! » crie une voix." % player.display_name)
			bark("m07_queue", 20.0)
		"search":
			v.fz = "search"
			v.ft = SEARCH_TIME
			v.cl = false
		"enter":
			_arrive_home(peer, player.display_name)
	_mark()


func request_interact() -> void:
	if is_server():
		interact(multiplayer.get_unique_id())
	else:
		_request_interact.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if is_server():
		interact(multiplayer.get_remote_sender_id())


func _end_chat(peer: int) -> void:
	if victims.has(peer):
		victims[peer].fz = ""
		victims[peer].ft = 0.0
	_chat_peer = 0
	_log("« Bon, faut que j'y aille ! » Mme Hubert est vexée.")


# --- Fin de partie ----------------------------------------------------------------------------------------------------------------------

func _arrive_home(peer: int, name: String) -> void:
	var v: Dictionary = victims[peer]
	v.done = "home"
	best_pressure = maxf(best_pressure, float(v.p))
	_log("%s ouvre la porte, fonce, et… AAAAAH. Sauvé !" % name)
	_check_end()


func _check_end() -> void:
	for pr in humans():
		if str(victims[pr].get("done", "")) == "":
			return
	var at_home := true
	var worst := 0.0
	for pr in humans():
		worst = maxf(worst, float(victims[pr].p))
		if str(victims[pr].done) == "wc":
			at_home = false
	best_pressure = worst
	medal = medal_for(worst, at_home)
	result = "home" if at_home else "wc"
	step = "done"
	if at_home:
		_log("Chez vous avec %d %% de pression : %s." % [int(worst * 100.0), {"gold": "médaille d'or, dignité intacte", "silver": "médaille d'argent, à un cheveu"}[medal]])
	else:
		_log("Soulagé aux toilettes publiques : médaille de bronze, mais la dignité est sauve.")
	get_node("/root/Progress").complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), [])
	_mark()
	_push_state()


func _accident(peer: int, name: String) -> void:
	result = "accident"
	step = "failed"
	_log("%s n'a pas tenu. PRRRRRT ! On fera comme si de rien n'était (le voisin a tout vu)." % name)
	_mark()
	_push_state()


# --- Boucle serveur ------------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0 and not zones.is_empty():
			started = true
			get_node("/root/Progress").start(mission_id)
			if day_night:
				day_night.hour = START_HOUR
			for pr in humans():
				victims[pr] = {"p": START_PRESSURE, "st": 1.0, "cl": false, "rel": 0.0, "fz": "", "ft": 0.0, "done": ""}
			_teleport_to_stand()
			_log("Fête de la pomme, seize heures. Le jus de Gégé était « un peu vif » : ça gargouille. Les toilettes, c'est chez vous, tout là-bas !")
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	time_left -= delta
	# Crampes : toutes les 9 à 13 s.
	_spasm_t -= delta
	var spasm_now := false
	if _spasm_t <= 0.0:
		_spasm_t = rng.randf_range(SPASM_EVERY.x, SPASM_EVERY.y)
		spasm_now = true
		spasms += 1
		bark("m07_spasm", 25.0)
		_dirty = true
	for pr in victims.keys():
		var v: Dictionary = victims[pr]
		if str(v.done) != "":
			continue
		var node := actor(pr) as Player
		if node == null:
			continue
		var speed := float(test_speed[pr]) if test_speed.has(pr) else Vector2(node.velocity.x, node.velocity.z).length()
		var cob := on_cobbles(node.global_position)
		var clenched := bool(v.cl)
		v.p = float(v.p) + pressure_rate(speed, clenched, cob) * delta
		if spasm_now:
			v.p = float(v.p) + (SPASM_CLENCHED if clenched else SPASM_PRESSURE)
		# Endurance : serrer fatigue, relâcher repose.
		if clenched:
			v.st = float(v.st) - STAMINA_DRAIN * delta
			if float(v.st) <= 0.0:
				v.st = 0.0
				v.cl = false
				v.rel = RELEASE_TIME
				v.p = float(v.p) + RELEASE_SPIKE
				_log("Les muscles lâchent ! Impossible de serrer pendant %d s." % int(RELEASE_TIME))
				bark("m07_released", 12.0)
		else:
			v.st = minf(float(v.st) + (STAMINA_REGEN * delta if float(v.rel) <= 0.0 else 0.0), 1.0)
		v.rel = maxf(float(v.rel) - delta, 0.0)
		# Événements du trajet.
		_tick_events(pr, v, node, delta)
		if float(v.p) >= 1.0:
			_accident(pr, node.display_name)
			return
	if time_left <= 0.0:
		result = "late"
		step = "failed"
		_log("Le temps est écoulé : la nuit tombe sur la fête de la pomme, et sur vos bonnes résolutions. PRRRT.")
		_mark()
		_push_state()
		return
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD:
		_sync_t = 0.0
		_push_state()


func _tick_events(pr: int, v: Dictionary, node: Player, delta: float) -> void:
	var pos := node.global_position
	# Retenu : causette, file des toilettes, recherche de la clé.
	var fz := str(v.fz)
	if fz == "chat":
		_chat_left = maxf(_chat_left - delta, 0.0)
		if _chat_left <= 0.0:
			_end_chat(pr)
		return
	if fz == "queue":
		v.ft = float(v.ft) - delta
		if float(v.ft) <= 0.0:
			v.p = maxf(float(v.p) - WC_RELIEF, 0.0)
			v.fz = ""
			v.done = "wc"
			_log("Le verrou passe au vert : soulagement.")
			_check_end()
		return
	if fz == "search":
		v.ft = float(v.ft) - delta
		if float(v.ft) <= 0.0:
			v.fz = ""
			door_open = true
			_log("La clé était sous le pot de fleurs, évidemment. La porte s'ouvre !")
			bark("m07_door_open", 20.0)
			_dirty = true
		return
	if not door_open and at_post(ID_GINETTE, "porte") and _dist(pos, _front_point("door", 1.0)) < float(NEAR.door):
		_unlock_t += delta
		if _unlock_t >= 1.0:
			door_open = true
			_log("Ginette : « J'ai la clé ! » Elle ouvre la porte à la volée.")
			bark("m07_door_open", 20.0)
			_dirty = true
	# Mme Hubert : la causette n'a lieu qu'une fois, sauf si Kévin la distrait.
	if not chat_done and _dist(pos, spot("hubert")) < float(NEAR.hubert):
		if at_post(ID_KEVIN, "hubert"):
			chat_done = true
			_log("Kévin occupe Mme Hubert : « Dites donc, ma tante, vous avez vu mon fanion ? » Vous passez.")
			bark("m07_hubert_diverted", 20.0)
		else:
			chat_done = true
			v.fz = "chat"
			v.cl = false
			_chat_left = CHAT_TIME
			_chat_peer = pr
			_log("Mme Hubert : « Ah, mais c'est vous ! Je vous raconte pour ma hanche… »")
			bark("m07_hubert", 20.0)
		_dirty = true
	# Le chien du portail : une frayeur.
	if not dog_done and _dist(pos, spot("dog")) < float(NEAR.dog):
		dog_done = true
		v.p = float(v.p) + DOG_SCARE
		_log("Le chien du portail aboie : sursaut ! (+%d %%)" % int(DOG_SCARE * 100.0))
		bark("m07_dog", 20.0)
		_dirty = true


func _teleport_to_stand() -> void:
	var k := 0
	var s := spot("stand")
	for p in _players_root.get_children():
		if p is Player:
			var off := Vector3(float(k) * 1.0 - 1.0, 0.6, float(k % 2) * 0.8)
			(p as Player).global_position = s + off
			(p as Player).velocity = Vector3.ZERO
			k += 1


func on_player_left(peer: int) -> void:
	if not is_server():
		return
	victims.erase(peer)
	_mark()


func _log(text: String) -> void:
	messages.append(text)
	if messages.size() > 6:
		messages.pop_front()


func _mark() -> void:
	_dirty = true
	changed.emit()


# --- Réplication -----------------------------------------------------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"step": step, "started": started, "elapsed": elapsed, "v": victims, "tl": time_left, "sp": spasms, "cd": chat_done, "dd": dog_done,
		"door": door_open, "result": result, "medal": medal, "bp": best_pressure, "messages": messages}


func _push_state() -> void:
	_dirty = false
	var s := state()
	for id in Net.ready_peers():
		_sync.rpc_id(id, s)


func send_full_state(peer: int) -> void:
	if is_server():
		_sync.rpc_id(peer, state())


@rpc("authority", "call_remote", "reliable")
func _sync(s: Dictionary) -> void:
	step = s.step
	started = s.started
	elapsed = s.elapsed
	victims = s.v
	time_left = s.tl
	spasms = s.sp
	chat_done = s.cd
	dog_done = s.dd
	door_open = s.door
	result = s.result
	medal = s.medal
	best_pressure = s.bp
	messages = s.messages
	changed.emit()


# --- Sons, rendu, HUD ----------------------------------------------------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"sp": spasms, "dog": dog_done, "door": door_open, "step": step, "chat": chat_done}
	if _snd.is_empty():
		_snd = now
		return
	if now.sp > _snd.sp:
		Sfx.play("gurgle")
	if now.dog and not _snd.dog:
		Sfx.play("bark")
	if now.door and not _snd.door:
		Sfx.play("crate")
	if now.step != _snd.step:
		if now.step == "done":
			Sfx.play("fanfare")
		elif now.step == "failed":
			Sfx.play("fail")
	_snd = now


func _process(delta: float) -> void:
	_clock += delta
	_audio_events()
	if not is_server() and step == "run":
		time_left = maxf(time_left - delta, 0.0)
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai:
				(p as Player).speed_cap = cap_for((p as Player).peer_id)
			elif p is Player:
				(p as Player).carrying = false


func objective() -> String:
	match step:
		"run":
			return "Rentrez chez vous (flèche : la maison, là-bas) avant l'accident. Courez, serrez (E), ou tentez les toilettes publiques."
		"done":
			return "Soulagement."
		"failed":
			return "Accident."
	return ""


func bar(value: float, n := 20, mark := -1.0) -> String:
	var f := int(round(clampf(value, 0.0, 1.0) * n))
	var s := ""
	for i in n:
		s += "█" if i < f else "·"
	return "[" + s + "]"


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	var v := victim(me)
	if step == "run" and not v.is_empty():
		lines.append("Pression %s %d %%   ·   Endurance %s   ·   %s" % [bar(float(v.p)), int(float(v.p) * 100.0), bar(float(v.st), 10), "SERRÉ" if bool(v.cl) else "relâché"])
		lines.append("Temps restant : %s   ·   Distance à la maison : %d m" % [MissionBase.format_time(time_left), int(distance_home(me))])
	if step in ["done", "failed"]:
		lines.append("Pression à l'arrivée : %d %%   ·   crampes : %d" % [int(best_pressure * 100.0), spasms])
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_status(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func distance_home(peer: int) -> float:
	var a := actor(peer)
	return _dist(a.global_position, zones.get("door", Vector3.ZERO)) if a and zones.has("door") else 0.0


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	match role:
		"portier":
			return "attend à la porte, la clé à la main" if at_post(c.peer_id, "porte") else "file ouvrir la porte"
		"diversion":
			return "tient la jambe à Mme Hubert" if at_post(c.peer_id, "hubert") else "gagne le chemin de Mme Hubert"
		"file":
			return "garde la file des toilettes" if at_post(c.peer_id, "wc") else "file aux toilettes publiques"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "%s — médaille : %s" % ["Sauvé !" if result == "home" else "Soulagé au public", {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")]
	if step == "failed":
		return {"accident": "PRRRRT !", "late": "Trop tard"}.get(result, "Accident")
	return ""
