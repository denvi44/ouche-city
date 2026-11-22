class_name MissionM09
extends MissionBase
## Mission 09 « Le siège des Bretons » : des Bretons en ciré jaune débarquent sous la pluie et lancent du beurre salé sur les façades.
## Il faut porter DIX camemberts, des étals à la catapulte de la Saint-Camembert, avant que le village ne soit englouti (temps imparti),
## puis tirer : une cinématique montre les dégâts (épaisse fumée verte et jaunâtre) et les Bretons s'enfuient vers leurs terres sous la pluie.
##
## Étapes : defend (porter / charger) -> launch (le tir, la cinématique ; ~15 s) -> done | failed (village englouti).
## Tout l'état de jeu vit côté serveur (camemberts portés et chargés, temps restant). Les Bretons, le beurre et les flaques sont
## DÉTERMINISTES : chacun les calcule localement à partir du temps `elapsed` (synchronisé) — les fonctions `shot_*`, `slick_*` et
## `breton_pos` sont pures et testées. Seule la vitesse des joueurs dans une flaque de beurre (speed_cap) a un effet sur le jeu.

const MISSION_FILE := "res://assets/missions/m09_siege_des_bretons.json"
const SYNC_PERIOD := 0.25
const START_HOUR := 18.6                           # fin de journée, ciel sombre : sous la pluie
const NEAR_STOCK := 3.4
const NEAR_CATAPULT := 4.8
const NEAR_POST := 4.0
const SLICK_CAP := 1.6                             # m/s dans une flaque de beurre (marche normale : ~4,5)
const SLICK_FIRST := 5.0                           # s : première flaque
const SLICK_EVERY := 6.5
const SLICK_RADIUS := 2.6
const SHOT_FIRST := 3.0                            # s : premier tir de beurre
const FLIGHT := 1.5                                # s : vol d'un bloc de beurre
const SPLAT_LIFE := 12.0
const BRETON_COUNT := 12
const ADVANCE := 0.6                               # part du chemin vers les façades que les Bretons parcourent pendant le siège
# Chronologie du tir (s depuis le début de l'étape « launch », à vitesse 1) : le bras part, le camembert vole, impact, fuite.
const ARM_T0 := 0.35
const ARM_SWING := 0.9
const RELEASE_T := 0.95
const IMPACT_T := 4.2
const FLEE_T := 4.8
const FLEE_SPEED := 5.5
const LAUNCH_END := 15.0
const ARM_REST := -30.0                            # degrés
const ARM_END := 200.0
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_KEVIN := -4

# --- Paramètres lus dans le JSON ---
var mission_id := "m09_siege_des_bretons"
var needed := 10
var time_limit := 240.0
var butter_every := 2.4
var slick_life := 11.0
var thresholds := {"gold": 50, "silver": 25, "bronze": 1}
var rewards := {}

# --- État répliqué ---
var loaded := 0
var carriers: Dictionary = {}              # identifiant de joueur -> true (porte un camembert)
var time_left := 240.0
var launch_t := 0.0
var stop_t := -1.0                         # `elapsed` au moment où les Bretons cessent de lancer du beurre (-1 : ils lancent)
var result := ""                           # "" | "win" | "lose"
var medal := ""

var zones := {}                            # catapult, landing -> Vector3 ; stocks : Array de Vector3
var stocks: Array = []
var facing_catapult := 0.0
var targets: Array = []                    # [{pos: Vector3 (point sur la façade), out: Vector3 (normale), front: Vector3}]
var day_night: DayNight
var _ground: Callable
var _spots := {}
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _clock := 0.0
var _world: Node
var _catapult_node: Node3D
var _arm: Node3D
var _pile: Node3D
var _pile_count := 0
var _breton_nodes: Array = []
var _shot_nodes := {}                      # k -> {proj, splat, played}
var _slick_nodes := {}                     # i -> Node3D
var _smoke: SiegeSmoke
var _flying: Node3D
var _impact_done := false
var _lost_t := 0.0


# --- Fonctions pures (déterministes, testées) -------------------------------------------------------------------------------------------

## Nombre pseudo-aléatoire stable dans [0, 1[ pour (k, graine) : identique chez tous les pairs.
static func rnd(k: int, salt: int) -> float:
	var h := ((k + 1) * 73856093) ^ ((salt + 7) * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(absi(h) % 10000) / 10000.0


## Instant (s) du tir de beurre numéro k.
static func shot_time(k: int, every: float) -> float:
	return SHOT_FIRST + float(k) * every


## Indice du dernier tir lancé à l'instant t (-1 : aucun).
static func last_shot(t: float, every: float) -> int:
	return int(floor((t - SHOT_FIRST) / every)) if t >= SHOT_FIRST else -1


## Instant d'apparition de la flaque i et indice de l'étal d'où elle part.
static func slick_time(i: int) -> float:
	return SLICK_FIRST + float(i) * SLICK_EVERY


## Centre de la flaque i : entre un étal et la catapulte (là où l'on passe), décalé de côté.
static func slick_center(i: int, stock_pos: Vector3, catapult: Vector3) -> Vector3:
	var s := 0.25 + 0.5 * rnd(i, 1)
	var c := stock_pos.lerp(catapult, s)
	var along := (catapult - stock_pos)
	var side := Vector3(-along.z, 0.0, along.x).normalized()
	return c + side * (rnd(i, 2) * 6.0 - 3.0)


## Flaques actives à l'instant t : [{i, center}] (durée de vie `life`).
static func slicks_active(t: float, life: float, stock_list: Array, catapult: Vector3) -> Array:
	var out: Array = []
	if stock_list.is_empty():
		return out
	var last := int(floor((t - SLICK_FIRST) / SLICK_EVERY))
	for i in range(maxi(last - int(ceil(life / SLICK_EVERY)), 0), last + 1):
		var age := t - slick_time(i)
		if age >= 0.0 and age < life:
			out.append({"i": i, "center": slick_center(i, stock_list[i % stock_list.size()], catapult), "age": age})
	return out


## Facteur de vitesse maximal en (x, z) à l'instant t : SLICK_CAP dans une flaque, INF sinon.
static func cap_at(pos: Vector3, t: float, life: float, stock_list: Array, catapult: Vector3) -> float:
	for s in slicks_active(t, life, stock_list, catapult):
		var c: Vector3 = s.center
		if Vector2(pos.x - c.x, pos.z - c.z).length() < SLICK_RADIUS:
			return SLICK_CAP
	return INF


## Position du Breton b à l'instant t : il part du débarquement et avance vers sa façade (ADVANCE du chemin au bout du temps imparti).
static func breton_pos(b: int, t: float, limit: float, landing: Vector3, front_list: Array) -> Vector3:
	var a := TAU * float(b) / float(BRETON_COUNT)
	var start := landing + Vector3(cos(a), 0.0, sin(a)) * (3.0 + 7.0 * rnd(b, 3))
	var front: Vector3 = front_list[b % front_list.size()] if not front_list.is_empty() else landing
	var p := clampf(t / limit, 0.0, 1.0) * ADVANCE
	var sway := Vector3(sin(t * 0.7 + float(b)), 0.0, cos(t * 0.6 + float(b) * 1.7)) * 0.8
	return start.lerp(front, p) + sway


## Position d'arrivée du beurre du tir k (façade visée + petit décalage le long du mur).
static func shot_target(k: int, target_list: Array) -> Vector3:
	if target_list.is_empty():
		return Vector3.ZERO
	var tg: Dictionary = target_list[k % target_list.size()]
	var out_n: Vector3 = tg.out
	var along := Vector3(-out_n.z, 0.0, out_n.x)
	return (tg.pos as Vector3) + along * (rnd(k, 4) * 5.0 - 2.5) + Vector3(0, 1.4 + rnd(k, 5) * 1.8, 0)


## Angle du bras (degrés) à l'instant t de l'étape « launch » : repos, élan, puis léger rebond.
static func arm_angle(t: float) -> float:
	if t <= ARM_T0:
		return ARM_REST
	var u := clampf((t - ARM_T0) / ARM_SWING, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var a := lerpf(ARM_REST, ARM_END, e)
	if t > ARM_T0 + ARM_SWING:
		a += 6.0 * exp(-(t - ARM_T0 - ARM_SWING) * 2.5) * sin((t - ARM_T0 - ARM_SWING) * 9.0)
	return a


## Médaille d'après la part de village restante au moment du tir (0..1).
func medal_for(village_left: float) -> String:
	var pct := village_left * 100.0
	if pct >= float(thresholds.gold):
		return "gold"
	if pct >= float(thresholds.silver):
		return "silver"
	if pct >= float(thresholds.bronze):
		return "bronze"
	return ""


## Vitesse de lecture des cinématiques (réglage « dialogues lents ») : le tir est chorégraphié pour durer autant que la scène.
func pace() -> float:
	if DisplayServer.get_name() == "headless":
		return 1.0
	var st := get_node_or_null("/root/Settings")
	return float(st.dialogue_pace) if st and bool(st.cinematics) else 1.0


# --- Mise en place -------------------------------------------------------------------------------------------------------------------------

func _ready() -> void:
	title = "Le siège des Bretons"
	step = "defend"
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		needed = int(m.siege.camemberts)
		time_limit = float(m.siege.timeLimitSec)
		butter_every = float(m.siege.butterEverySec)
		slick_life = float(m.siege.slick.lifeSec)
		for k in ["gold", "silver", "bronze"]:
			thresholds[k] = int(m.medals[k].villageLeftPct)
		rewards = m.rewards
	time_left = time_limit


func setup(pois: Array, ground: Callable, _vehicle: Vehicle, players_root: Node3D) -> void:
	_ground = ground
	_players_root = players_root
	_world = get_parent()
	day_night = _world.get("day_night")
	var tmp := {}
	for p in pois:
		var id: String = p.id
		if id == "catapulte" or id == "debarquement_bretons" or id.begins_with("stock_fromage_"):
			var x := float(p.position[0])
			var z := float(p.position[1])
			tmp[id] = Vector3(x, ground.call(x, z), z)
			if id == "catapulte":
				facing_catapult = float(p.get("facing", 0.0))
	zones = {"catapult": tmp.get("catapulte", Vector3.ZERO), "landing": tmp.get("debarquement_bretons", Vector3.ZERO)}
	stocks = []
	for i in 3:
		if tmp.has("stock_fromage_%d" % (i + 1)):
			stocks.append(tmp["stock_fromage_%d" % (i + 1)])
	_pick_targets(RoadNav.footprints())
	_build_visuals.call_deferred()


## Façades visées : les bâtiments les plus proches de la catapulte (30 à 140 m), dispersés ; on vise le coin tourné vers le débarquement.
func _pick_targets(rings: Array) -> void:
	targets = []
	if not zones.has("catapult") or zones.catapult == Vector3.ZERO:
		return
	var cat := Vector2(zones.catapult.x, zones.catapult.z)
	var land := Vector2(zones.landing.x, zones.landing.z)
	var cands: Array = []
	for ring in rings:
		var r: PackedVector2Array = ring
		if r.size() < 3:
			continue
		var c := Vector2.ZERO
		for v in r:
			c += v
		c /= float(r.size())
		var d := c.distance_to(cat)
		if d > 30.0 and d < 140.0:
			cands.append({"d": d, "c": c, "r": r})
	cands.sort_custom(func(a, b): return a.d < b.d)
	var chosen: Array = []
	for cd in cands:
		var ok := true
		for o in chosen:
			if (o.c as Vector2).distance_to(cd.c) < 18.0:
				ok = false
				break
		if ok:
			chosen.append(cd)
		if chosen.size() >= 6:
			break
	for cd in chosen:
		var ring: PackedVector2Array = cd.r
		var best := ring[0]
		for v in ring:
			if v.distance_to(land) < best.distance_to(land):
				best = v
		var outn := (best - (cd.c as Vector2)).normalized()
		var wall := best + outn * 0.35
		var front := wall + (land - wall).normalized() * 16.0
		var gy := float(_ground.call(wall.x, wall.y)) if _ground.is_valid() else 0.0
		targets.append({"pos": Vector3(wall.x, gy, wall.y), "out": Vector3(outn.x, 0.0, outn.y),
			"front": Vector3(front.x, float(_ground.call(front.x, front.y)) if _ground.is_valid() else 0.0, front.y)})


func spawn_hint() -> Vector3:
	if not zones.has("catapult") or zones.catapult == Vector3.ZERO:
		return Vector3.ZERO
	return (zones.catapult as Vector3) + Basis(Vector3.UP, facing_catapult) * Vector3(7.0, 0.0, -9.0)


func companion_roles() -> Dictionary:
	return {ID_GEGE: "porteur", ID_KEVIN: "chargeur", ID_GINETTE: "guetteur"}


func look_target() -> Vector3:
	return zones.get("landing", Vector3.ZERO)


## Emplacements : « watch » (guetteuse, sur le côté de la catapulte), « catapult » (derrière le godet), « stock_N ».
func spot(name: String) -> Vector3:
	if _spots.has(name):
		return _spots[name]
	var base := Vector3.ZERO
	if not zones.has("catapult") or zones.catapult == Vector3.ZERO:
		return base
	match name:
		"watch":
			base = (zones.catapult as Vector3) + Basis(Vector3.UP, facing_catapult) * Vector3(7.0, 0.0, 3.0)
		"catapult":
			base = (zones.catapult as Vector3) + Basis(Vector3.UP, facing_catapult) * Vector3(0.0, 0.0, -3.4)
		_:
			if name.begins_with("stock_"):
				var i := int(name.substr(6)) - 1
				if i >= 0 and i < stocks.size():
					base = stocks[i]
	if base != Vector3.ZERO and _world and _world.has_method("find_free_spawn") and name == "watch":
		base = _world.find_free_spawn(base)
	_spots[name] = base
	return base


func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func at_post(id: int, name: String) -> bool:
	var a := actor(id)
	var s := spot(name)
	return a != null and s != Vector3.ZERO and _dist(a.global_position, s) < NEAR_POST


func humans() -> int:
	var n := 0
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai:
				n += 1
	return maxi(n, 1)


func nearest_stock(pos: Vector3) -> int:
	var best := -1
	var bd := INF
	for i in stocks.size():
		var d := _dist(pos, stocks[i])
		if d < bd:
			bd = d
			best = i
	return best


# --- Interaction ---------------------------------------------------------------------------------------------------------------------------

func resolve(peer: int, pos: Vector3) -> Dictionary:
	if step != "defend":
		return {}
	var near_cat: bool = zones.has("catapult") and _dist(pos, zones.catapult) < NEAR_CATAPULT
	if carriers.has(peer):
		if near_cat:
			return {"kind": "load", "label": "Charger le camembert dans la catapulte (%d/%d)" % [loaded, needed]}
		return {"kind": "none", "label": "Portez le camembert à la catapulte"}
	var i := nearest_stock(pos)
	if i >= 0 and _dist(pos, stocks[i]) < NEAR_STOCK:
		return {"kind": "take", "label": "Prendre un camembert (%d/%d dans la catapulte)" % [loaded, needed]}
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
		"take":
			carriers[peer] = true
			player.carrying = true
			_log("%s prend un camembert." % player.display_name)
			bark("m09_take", 25.0)
		"load":
			carriers.erase(peer)
			player.carrying = false
			loaded += 1
			_log("Camembert chargé : %d sur %d." % [loaded, needed])
			if loaded >= needed:
				_fire()
			elif loaded == needed / 2:
				bark("m09_half", 60.0)
			else:
				bark("m09_load", 25.0)
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


func _fire() -> void:
	stop_t = elapsed
	step = "launch"
	launch_t = 0.0
	medal = medal_for(time_left / time_limit)
	if medal == "":
		medal = "bronze"          # un village sauvé a toujours au moins le bronze
	_log("Dix camemberts à bord : FEU !")
	_mark()
	_push_state()


func _finish() -> void:
	result = "win"
	step = "done"
	_log("Les Bretons s'enfuient sous la pluie, dans la fumée verte : %s." % {"gold": "médaille d'or, le village est presque intact", "silver": "médaille d'argent", "bronze": "médaille de bronze, le village est très beurré", "": "village sauvé de justesse"}[medal])
	get_node("/root/Progress").complete(mission_id, medal if medal != "" else "bronze", rewards.get("reputation", {}), rewards.get("unlocks", []), [])
	_mark()
	_push_state()


func _fail() -> void:
	stop_t = elapsed
	result = "lose"
	step = "failed"
	time_left = 0.0
	_log("Le village est englouti sous le beurre salé : il faudra tout nettoyer au savon noir.")
	_mark()
	_push_state()


# --- Boucle serveur et horloge -----------------------------------------------------------------------------------------------------------

func _slick_t() -> float:
	return elapsed if stop_t < 0.0 else -1.0


func _apply_speed_caps() -> void:
	if _players_root == null:
		return
	var t := _slick_t()
	for p in _players_root.get_children():
		if p is Player:
			(p as Player).speed_cap = cap_at((p as Player).global_position, t, slick_life, stocks, zones.get("catapult", Vector3.ZERO)) if (t >= 0.0 and step == "defend") else INF


func _physics_process(delta: float) -> void:
	_apply_speed_caps()
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0:
			started = true
			get_node("/root/Progress").start(mission_id)
			if day_night:
				day_night.hour = START_HOUR
			_log("Il pleut des Bretons en ciré jaune, et du beurre salé sur les façades ! Dix camemberts dans la catapulte, vite.")
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	if step == "defend":
		time_left -= delta
		if time_left <= 0.0:
			_fail()
			return
	elif step == "launch":
		launch_t += delta
		if launch_t >= LAUNCH_END * pace():
			_finish()
			return
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD:
		_sync_t = 0.0
		_push_state()


func on_player_left(peer: int) -> void:
	carriers.erase(peer)
	_mark()


func _log(text: String) -> void:
	messages.append(text)
	if messages.size() > 6:
		messages.pop_front()


func _mark() -> void:
	_dirty = true
	changed.emit()


# --- Réplication -----------------------------------------------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"step": step, "started": started, "elapsed": elapsed, "loaded": loaded, "carriers": carriers, "tl": time_left, "lt": launch_t,
		"st": stop_t, "result": result, "medal": medal, "messages": messages}


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
	loaded = s.loaded
	carriers = s.carriers
	time_left = s.tl
	launch_t = s.lt
	stop_t = s.st
	result = s.result
	medal = s.medal
	messages = s.messages
	changed.emit()


# --- Rendu local : catapulte, étals, Bretons, beurre, flaques, fumée, pluie ---------------------------------------------------------------

func _build_visuals() -> void:
	if _world == null:
		return
	_catapult_node = _world.find_child("Lieu_catapulte", true, false) as Node3D
	if _catapult_node:
		_arm = _catapult_node.find_child("Bras", true, false) as Node3D
		_pile = Node3D.new()
		_pile.name = "PileCamemberts"
		_pile.position = Vector3(2.0, 0.0, -1.4)
		_catapult_node.add_child(_pile)
	for i in stocks.size():
		var stand := _world.find_child("Lieu_stock_fromage_%d" % (i + 1), true, false) as Node3D
		if stand == null:
			continue
		for k in 6:
			var c := PropKit.camembert().build()
			c.scale = Vector3.ONE * 2.2          # bien visibles de loin
			c.position = Vector3(-1.2 + float(k % 3) * 1.2, 1.0 + float(k / 3) * 0.2, 0.0)
			c.rotation.y = float(k) * 0.9
			stand.add_child(c)
	if DisplayServer.get_name() == "headless":
		return
	for b in BRETON_COUNT:
		var n := CharacterModel.make(Color(0.97, 0.8, 0.1), Color(0.12, 0.17, 0.35), Color(0.97, 0.82, 0.12),
			{"hair": Color(0.8, 0.8, 0.82), "hair_style": "bald" if b % 3 == 0 else "short", "headgear": "souwester", "scarf": Color(0.95, 0.95, 0.98), "glasses": b % 5 == 0})
		n.name = "Breton_%d" % b
		_world.add_child(n)
		_breton_nodes.append(n)
	if RainFx.is_available() and _world.get_node_or_null("Pluie") == null:
		_world.add_child(RainFx.new())
		var env: Environment = _world.get("env")
		if env:
			env.fog_enabled = true
			env.fog_density = maxf(env.fog_density, 0.004)
			env.fog_light_color = Color(0.62, 0.66, 0.7)


func _sx(i: int) -> Vector3:
	return stocks[i % stocks.size()] if not stocks.is_empty() else Vector3.ZERO


func _front_points() -> Array:
	var out: Array = []
	for t in targets:
		out.append(t.front)
	return out


func _view_launch_t() -> float:
	return launch_t / pace()


func _ground_y(p: Vector3) -> float:
	return float(_ground.call(p.x, p.z)) if _ground.is_valid() else p.y


func _butter_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.88, 0.32)
	m.roughness = 0.55
	return m


func _process(delta: float) -> void:
	_clock += delta
	_audio_events()
	if not is_server():
		elapsed += delta if step != "done" and step != "failed" else 0.0
		if step == "defend":
			time_left = maxf(time_left - delta, 0.0)
		elif step == "launch":
			launch_t += delta
	for p in (_players_root.get_children() if _players_root else []):
		if p is Player:
			(p as Player).carrying = carriers.has((p as Player).peer_id)
	if DisplayServer.get_name() == "headless" or _world == null or zones.is_empty():
		return
	_update_pile()
	_update_arm_and_flight()
	_update_bretons()
	_update_butter()
	_update_slicks()


func _update_pile() -> void:
	if _pile == null:
		return
	var shown := loaded if step in ["defend"] else 0
	while _pile_count < shown:
		var c := PropKit.camembert().build()
		c.position = Vector3(float(_pile_count % 4) * 0.42 - 0.6, 0.04 + float(_pile_count / 4) * 0.08, float(_pile_count % 3) * 0.1)
		_pile.add_child(c)
		_pile_count += 1
	while _pile_count > shown and _pile.get_child_count() > 0:
		_pile.get_child(_pile.get_child_count() - 1).queue_free()
		_pile_count -= 1


func _update_arm_and_flight() -> void:
	if _arm == null:
		return
	var t := _view_launch_t() if step != "defend" else -1.0
	var angle := arm_angle(t) if step in ["launch", "done"] else ARM_REST
	if step == "done":
		angle = arm_angle(LAUNCH_END)
	_arm.rotation.x = deg_to_rad(angle)
	if step in ["launch", "done"]:
		var vt := _view_launch_t() if step == "launch" else LAUNCH_END
		if vt >= RELEASE_T and vt < IMPACT_T:
			if _flying == null:
				_flying = PropKit.camembert().build()
				_flying.scale = Vector3.ONE * 4.0
				_world.add_child(_flying)
			var u := (vt - RELEASE_T) / (IMPACT_T - RELEASE_T)
			var from := _catapult_node.to_global(Vector3(0, 4.2, 1.0)) if _catapult_node else Vector3.ZERO
			var to: Vector3 = zones.landing + Vector3(0, 1.5, 0)
			_flying.global_position = from.lerp(to, u) + Vector3(0, sin(u * PI) * 30.0, 0)
			_flying.rotation = Vector3(u * 14.0, u * 9.0, 0)
		elif _flying != null:
			_flying.queue_free()
			_flying = null
		if vt >= IMPACT_T and not _impact_done:
			_impact_done = true
			_smoke = SiegeSmoke.new()
			_world.add_child(_smoke)
			_smoke.global_position = (zones.landing as Vector3) + Vector3(0, 1.0, 0)
			Sfx.play_at("firework", zones.landing, 0.0, 0.7)


func _update_bretons() -> void:
	if _breton_nodes.is_empty():
		return
	var fronts := _front_points()
	var t_ref: float = elapsed if stop_t < 0.0 else stop_t
	var away: Vector3 = (zones.landing - zones.catapult)
	away.y = 0.0
	away = away.normalized()
	var flee := 0.0
	if step in ["launch", "done"]:
		flee = maxf((_view_launch_t() if step == "launch" else LAUNCH_END) - FLEE_T, 0.0)
	for b in _breton_nodes.size():
		var n: Node3D = _breton_nodes[b]
		var p := breton_pos(b, t_ref, time_limit, zones.landing, fronts)
		if flee > 0.0:
			p += away * (FLEE_SPEED * flee + float(b % 4) * 1.5)
		var prev := n.global_position
		p.y = _ground_y(p)
		n.global_position = p
		n.visible = flee * FLEE_SPEED < 90.0
		var dir := p - prev
		dir.y = 0.0
		var face := Vector3.ZERO
		if flee > 0.0:
			face = away
		elif dir.length() > 0.001:
			face = dir
		elif not targets.is_empty():
			face = ((targets[b % targets.size()].pos as Vector3) - p)
		if face.length() > 0.01:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(face.x, face.z), clampf(8.0 * get_process_delta_time(), 0.0, 1.0))


func _update_butter() -> void:
	if targets.is_empty() or _breton_nodes.is_empty():
		return
	var t: float = elapsed if stop_t < 0.0 else stop_t
	var hi := last_shot(elapsed if stop_t < 0.0 else stop_t + FLIGHT + SPLAT_LIFE, butter_every)
	var stop_k := last_shot(t, butter_every)
	var lo := maxi(last_shot(elapsed - FLIGHT - SPLAT_LIFE, butter_every), 0)
	for k in range(lo, mini(hi, stop_k) + 1):
		var age := elapsed - shot_time(k, butter_every)
		if age < 0.0 or age > FLIGHT + SPLAT_LIFE:
			continue
		var entry: Dictionary = _shot_nodes.get(k, {})
		var tgt := shot_target(k, targets)
		if age < FLIGHT:
			var shooter := breton_pos(k % BRETON_COUNT, shot_time(k, butter_every), time_limit, zones.landing, _front_points()) + Vector3(0, 1.7, 0)
			if not entry.has("proj"):
				var pm := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.5, 0.3, 0.35)
				bm.material = _butter_mat()
				pm.mesh = bm
				_world.add_child(pm)
				entry["proj"] = pm
			var u := age / FLIGHT
			var pn: MeshInstance3D = entry.proj
			pn.global_position = shooter.lerp(tgt, u) + Vector3(0, sin(u * PI) * 7.0, 0)
			pn.rotation = Vector3(u * 8.0, u * 5.0, 0)
		else:
			if entry.has("proj"):
				(entry.proj as Node3D).queue_free()
				entry.erase("proj")
			if not entry.has("splat"):
				var sm := MeshInstance3D.new()
				var sp := SphereMesh.new()
				sp.radius = 0.6
				sp.height = 1.2
				sp.radial_segments = 8
				sp.rings = 4
				sp.material = _butter_mat()
				sm.mesh = sp
				sm.scale = Vector3(1.4, 1.0, 0.3)
				_world.add_child(sm)
				sm.global_position = tgt
				var outn: Vector3 = targets[k % targets.size()].out
				sm.rotation.y = atan2(outn.x, outn.z)
				entry["splat"] = sm
				if _world.get("players_root") != null:
					var me := actor(local_peer())
					if me != null and me.global_position.distance_to(tgt) < 70.0:
						Sfx.play_at("crate", tgt, -3.0, 0.8)
			if age > FLIGHT + SPLAT_LIFE - 1.5:
				(entry.splat as Node3D).scale *= 0.985
		_shot_nodes[k] = entry
	for k in _shot_nodes.keys():
		if elapsed - shot_time(int(k), butter_every) > FLIGHT + SPLAT_LIFE or int(k) < lo:
			for key in ["proj", "splat"]:
				if _shot_nodes[k].has(key) and is_instance_valid(_shot_nodes[k][key]):
					(_shot_nodes[k][key] as Node3D).queue_free()
			_shot_nodes.erase(k)


func _update_slicks() -> void:
	var t := _slick_t()
	var active: Array = slicks_active(t, slick_life, stocks, zones.catapult) if (t >= 0.0 and step == "defend") else []
	var live := {}
	for s in active:
		live[int(s.i)] = s
	for i in live.keys():
		var node: Node3D = _slick_nodes.get(i)
		var s: Dictionary = live[i]
		if node == null:
			node = MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = SLICK_RADIUS
			cm.bottom_radius = SLICK_RADIUS
			cm.height = 0.05
			cm.radial_segments = 14
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.9, 0.35, 0.85)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.2
			cm.material = mat
			(node as MeshInstance3D).mesh = cm
			_world.add_child(node)
			_slick_nodes[i] = node
		var c: Vector3 = s.center
		node.global_position = Vector3(c.x, _ground_y(c) + 0.07, c.z)
		var grow := minf(float(s.age) / 0.6, 1.0)
		node.scale = Vector3(grow, 1.0, grow) * (1.0 - clampf((float(s.age) - (slick_life - 1.5)) / 1.5, 0.0, 1.0) * 0.8)
	for i in _slick_nodes.keys():
		if not live.has(i):
			(_slick_nodes[i] as Node3D).queue_free()
			_slick_nodes.erase(i)


# --- Sons -----------------------------------------------------------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"loaded": loaded, "step": step, "carry": carriers.size()}
	if _snd.is_empty():
		_snd = now
		return
	if now.loaded > _snd.loaded:
		Sfx.play("chime")
	elif now.carry > _snd.carry:
		Sfx.play("crate")
	if now.step != _snd.step:
		match now.step:
			"launch":
				Sfx.play("thud")
			"done":
				Sfx.play("fanfare")
			"failed":
				Sfx.play("fail")
	_snd = now


# --- HUD -------------------------------------------------------------------------------------------------------------------------------------------

func objective() -> String:
	match step:
		"defend":
			if carriers.has(local_peer()):
				return "Portez votre camembert à la catapulte (marqueur) et chargez-le (E) : %d sur %d." % [loaded, needed]
			return "Prenez un camembert à un étal (E), portez-le à la catapulte, chargez-le : %d sur %d. Fuyez les flaques de beurre !" % [loaded, needed]
		"launch":
			return "Feu ! Regardez la fumée verte faire fuir les Bretons."
		"done":
			return "Les Bretons sont repartis sous la pluie. Frouch est sauvée."
		"failed":
			return "Le village est englouti sous le beurre salé."
	return ""


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_line(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	match companion_roles().get(c.peer_id, ""):
		"porteur", "chargeur":
			if carriers.has(c.peer_id):
				return "porte un camembert à la catapulte"
			return "file chercher un camembert à l'étal"
		"guetteur":
			return "guette les Bretons depuis la catapulte" if at_post(c.peer_id, "watch") else "gagne son poste de guet"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "Village sauvé — médaille : %s" % {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE", "": "aucune"}.get(medal, "aucune")
	if step == "failed":
		return "Village englouti sous le beurre"
	return ""


func hud_gauges() -> Array:
	var out := []
	if step in ["defend", "launch"]:
		out.append(gauge("village", "Le village tient", time_left / time_limit, C_DANGER if time_left < time_limit * 0.25 else C_GOAL, format_time(time_left), {"low_is_bad": true}))
		out.append(gauge("camemberts", "Camemberts dans la catapulte", float(loaded) / float(needed), C_OK, "%d / %d" % [loaded, needed]))
	return out


func hud_markers() -> Array:
	var out := []
	if step != "defend":
		return out
	var me := actor(local_peer())
	if carriers.has(local_peer()):
		if zones.has("catapult"):
			out.append(marker(zones.catapult, "Catapulte : charger", C_GOAL))
	elif me != null:
		var i := nearest_stock(me.global_position)
		if i >= 0:
			out.append(marker(stocks[i], "Étal de camembert", C_ITEM))
	if zones.has("landing") and zones.landing != Vector3.ZERO:
		out.append(marker(zones.landing, "Bretons", C_DANGER, true))
	return out
