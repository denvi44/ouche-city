class_name MissionM05
extends MissionBase
## Mission 05 « Les vaches sont de sortie » (agent 05) : rabattre huit vaches dans l'enclos de Mémé Odette.
##
## Les vaches fuient les personnes proches (joueurs et compagnons), plus vite et plus loin quand on siffle ; elles broutent
## en troupeau sinon. Marguerite, la meneuse, est plus farouche. Les vaches ne traversent ni les bâtiments ni la clôture
## (sauf par la porte). Une fois huit vaches dedans (ou le temps écoulé), on ferme la barrière.
## Simulation à autorité serveur ; les clients reçoivent les positions (`_sync`) et prolongent le mouvement entre deux envois.

const MISSION_FILE := "res://assets/missions/m05_vaches_en_goguette.json"
const SYNC_PERIOD := 0.2
const START_HOUR := 4.0
const FLEE_RANGE := 10.0
const WHISTLE_RANGE := 16.0
const WHISTLE_COOLDOWN := 3.0
const WHISTLE_TIME := 1.4                          # s pendant lesquelles un sifflet effraie
const GRAZE_SPEED := 0.35
const WALK_SPEED := 1.1
const RUN_SPEED := 4.2
const COHESION := 0.25
const PEN_HALF := 6.0
const GATE_HALF := 2.2
const NEAR_GATE := 6.0
const CLOSE_DELAY := 2.0                            # s : Gégé ferme la barrière après ce délai
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_KEVIN := -4
const NEAR_POST := 4.0
const COW_NAMES := ["Marguerite", "Noiraude", "Pâquerette", "Biscotte", "Cunégonde", "Ficelle", "Rosalie", "Tulipe"]

var mission_id := "m05_vaches_en_goguette"
var cow_count := 8
var time_limit := 300.0
var flee_range := FLEE_RANGE
var whistle_range := WHISTLE_RANGE
var whistle_cd := WHISTLE_COOLDOWN
var marguerite_speed := 1.4
var marguerite_range := 1.3
var thresholds := {"gold": 8, "silver": 6, "bronze": 4}
var rewards := {}

# --- État répliqué ---
var cows: Array = []                        # {id, x, z, vx, vz, st: graze|flee|pen}
var time_left := 300.0
var whistles := 0
var whistle_left := 0.0
var whistler := Vector2.ZERO
var gate_closed := false
var result := ""                            # "" | "win" | "lose"
var medal := ""

var rng := RandomNumberGenerator.new()
var zones := {}                             # pen, pre -> Vector3
var facing_pen := 0.0
var day_night: DayNight
var _ground: Callable
var _grid := {}                             # (cx, cz) -> Array de PackedVector2Array
var _wander := {}                           # id -> cap de broutage (rad)
var _whistle_cd := 0.0
var _gate_t := 0.0
var _spots := {}
var _cow_nodes := {}
var _gate_node: Node3D
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _clock := 0.0


func _ready() -> void:
	title = "Les vaches sont de sortie"
	step = "herd"
	rng.seed = 20260105
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		cow_count = int(m.herd.cows)
		time_limit = float(m.herd.timeLimitSec)
		flee_range = float(m.herd.fleeRange)
		marguerite_speed = float(m.herd.marguerite.speedFactor)
		marguerite_range = float(m.herd.marguerite.rangeFactor)
		whistle_range = float(m.whistle.range)
		whistle_cd = float(m.whistle.cooldownSec)
		for k in ["gold", "silver", "bronze"]:
			thresholds[k] = int(m.medals[k].penned)
		rewards = m.rewards
	time_left = time_limit


# --- Mise en place -------------------------------------------------------------------------------------------

func setup(pois: Array, ground: Callable, _vehicle: Vehicle, players_root: Node3D) -> void:
	_ground = ground
	_players_root = players_root
	var w := get_parent()
	day_night = w.get("day_night")
	for p in pois:
		if p.id == "enclos_odette" or p.id == "pre_vaches":
			var x := float(p.position[0])
			var z := float(p.position[1])
			zones["pen" if p.id == "enclos_odette" else "pre"] = Vector3(x, ground.call(x, z), z)
			if p.id == "enclos_odette":
				facing_pen = float(p.get("facing", 0.0))
	_index_buildings(RoadNav.footprints())
	_spawn_herd()
	_build_visuals.call_deferred()


func _index_buildings(rings: Array) -> void:
	for ring in rings:
		var r := ring as PackedVector2Array
		var lo := r[0]
		var hi := r[0]
		for v in r:
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
		for cx in range(int(floor(lo.x / 40.0)), int(floor(hi.x / 40.0)) + 1):
			for cz in range(int(floor(lo.y / 40.0)), int(floor(hi.y / 40.0)) + 1):
				var key := Vector2i(cx, cz)
				if not _grid.has(key):
					_grid[key] = []
				_grid[key].append(r)


## Place le troupeau dans le pré : positions déterministes (spirale de tournesol), hors bâtiments. Marguerite d'abord.
func _spawn_herd() -> void:
	cows = []
	if not zones.has("pre"):
		return
	var c: Vector3 = zones.pre
	for i in cow_count:
		var r := 4.0 + 17.0 * sqrt((float(i) + 0.5) / float(cow_count))
		var a := float(i) * 2.399963
		var p := Vector2(c.x, c.z) + Vector2(cos(a), sin(a)) * r
		cows.append({"id": i, "x": p.x, "z": p.y, "vx": 0.0, "vz": 0.0, "st": "graze"})
		_wander[i] = a


func _build_visuals() -> void:
	var w := get_parent()
	for i in cow_count:
		var n := PropKit.cow(1 if i == 0 else 0).build()
		n.name = "Vache_%d" % i
		var label := Label3D.new()
		label.text = COW_NAMES[i % COW_NAMES.size()]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.pixel_size = 0.01
		label.outline_size = 10
		label.position.y = 2.2
		label.no_depth_test = true
		n.add_child(label)
		w.add_child(n)
		_cow_nodes[i] = n
	_gate_node = Node3D.new()
	_gate_node.name = "M5_Porte"
	for s in [-1.0, 1.0]:
		var leaf := PropKit.gate_leaf().build()
		leaf.name = "Vantail_%d" % int(s)
		leaf.scale.x = -s
		_gate_node.add_child(leaf)
	w.add_child(_gate_node)
	_place_gate()


func _front(local: Vector3) -> Vector3:
	if not zones.has("pen"):
		return Vector3.ZERO
	return zones.pen + Basis(Vector3.UP, facing_pen) * local


func _place_gate() -> void:
	if _gate_node == null or not zones.has("pen"):
		return
	var g := _front(Vector3(0, 0, PEN_HALF))
	_gate_node.position = Vector3(g.x, _ground.call(g.x, g.z) if _ground.is_valid() else g.y, g.z)
	_gate_node.rotation.y = facing_pen
	# Les vantaux s'ouvrent vers l'intérieur : charnières aux poteaux ; ouverts = perpendiculaires, fermés = face à face.
	var open := 0.0 if gate_closed else PI / 2.0
	for s in [-1, 1]:
		var leaf := _gate_node.get_node_or_null("Vantail_%d" % s) as Node3D
		if leaf:
			leaf.position = Vector3(s * GATE_HALF, 0, 0)
			leaf.rotation.y = -float(s) * open


func companion_roles() -> Dictionary:
	return {ID_KEVIN: "rabatteur", ID_GINETTE: "guetteur", ID_GEGE: "barriere"}


func look_target() -> Vector3:
	return zones.get("pre", Vector3.ZERO)


func spot(name: String) -> Vector3:
	if _spots.has(name):
		return _spots[name]
	var base := Vector3.ZERO
	match name:
		"gate":
			base = _front(Vector3(-13.0, 0, PEN_HALF + 1.0))     # sur le côté : ne pas effrayer les vaches qui entrent
		"watch":
			base = _front(Vector3(13.0, 0, PEN_HALF + 3.0))
		_:
			return Vector3.ZERO
	if base == Vector3.ZERO:
		return base
	var w := get_parent()
	if w and w.has_method("find_free_spawn"):
		base = w.find_free_spawn(base)
	_spots[name] = base
	return base


func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func at_post(id: int, name: String) -> bool:
	var a := actor(id)
	var s := spot(name)
	return a != null and s != Vector3.ZERO and _dist(a.global_position, s) < NEAR_POST


# --- Géométrie : clôture, bâtiments ---------------------------------------------------------------------------------------

## Coordonnées d'un point (x, z) dans le repère de l'enclos : x = droite, y = devant (vers la porte).
func to_pen(p: Vector2) -> Vector2:
	var c := Vector2(zones.pen.x, zones.pen.z)
	var d := p - c
	var s := sin(facing_pen)
	var co := cos(facing_pen)
	# +Z local = (sin f, cos f) ; +X local = (cos f, -sin f)
	return Vector2(d.x * co - d.y * s, d.x * s + d.y * co)


func in_pen(p: Vector2, margin := 0.8) -> bool:
	if not zones.has("pen"):
		return false
	var l := to_pen(p)
	return absf(l.x) < PEN_HALF - margin and absf(l.y) < PEN_HALF - margin


## Fonction pure (testée) : un point (repère de l'enclos) est-il dans la clôture ? La porte est ouverte sur +Y quand `closed` est faux.
static func on_fence(l: Vector2, closed: bool) -> bool:
	var t := 0.6
	var inside_x := absf(l.x) <= PEN_HALF + t
	var inside_y := l.y >= -PEN_HALF - t and l.y <= PEN_HALF + t
	if not (inside_x and inside_y):
		return false
	var on_back := absf(l.y + PEN_HALF) <= t
	var on_side := absf(absf(l.x) - PEN_HALF) <= t
	var on_front := absf(l.y - PEN_HALF) <= t and (closed or absf(l.x) > GATE_HALF)
	return on_back or on_side or on_front


func _in_building(p: Vector2) -> bool:
	for r in _grid.get(Vector2i(int(floor(p.x / 40.0)), int(floor(p.y / 40.0))), []):
		if Geometry2D.is_point_in_polygon(p, r):
			return true
	return false


func _blocked(p: Vector2) -> bool:
	if zones.has("pen") and on_fence(to_pen(p), gate_closed):
		return true
	return _in_building(p)


# --- Troupeau (serveur) -------------------------------------------------------------------------------------------------------------

## Vitesse de fuite d'une vache (fonction pure, testée) : `pressure` 0..1.
static func flee_speed(pressure: float, factor: float) -> float:
	return lerpf(WALK_SPEED, RUN_SPEED, clampf(pressure, 0.0, 1.0)) * factor


func _sources() -> Array:
	var out := []
	if _players_root:
		for p in _players_root.get_children():
			if p is Player:
				out.append(Vector2((p as Player).global_position.x, (p as Player).global_position.z))
	return out


func _tick_herd(delta: float) -> void:
	var srcs := _sources()
	var centroid := Vector2.ZERO
	var n := 0
	for c in cows:
		if c.st != "pen":
			centroid += Vector2(c.x, c.z)
			n += 1
	if n > 0:
		centroid /= float(n)
	var pen_c := Vector2(zones.pen.x, zones.pen.z) if zones.has("pen") else Vector2.ZERO
	for c in cows:
		var here := Vector2(c.x, c.z)
		if c.st == "pen":
			# Dans l'enclos : elle se calme et dérive vers un point de son rang.
			var slot := pen_c + Vector2(sin(facing_pen), cos(facing_pen)) * -2.0 + Vector2(cos(float(c.id)), sin(float(c.id))) * 2.5
			var d := slot - here
			var v := d.normalized() * minf(d.length(), 0.6) if d.length() > 0.2 else Vector2.ZERO
			c.vx = v.x
			c.vz = v.y
			c.x += v.x * delta
			c.z += v.y * delta
			continue
		var factor := marguerite_speed if int(c.id) == 0 else 1.0
		var range_f := marguerite_range if int(c.id) == 0 else 1.0
		var flee := Vector2.ZERO
		for s in srcs:
			var d2: Vector2 = here - s
			var dist: float = d2.length()
			var r := flee_range * range_f
			if dist < r and dist > 0.01:
				flee += d2.normalized() * (1.0 - dist / r)
		if whistle_left > 0.0:
			var dw := here - whistler
			var dd := dw.length()
			var rw := whistle_range * range_f
			if dd < rw and dd > 0.01:
				flee += dw.normalized() * (1.0 - dd / rw) * 1.6
		var dir := Vector2.ZERO
		var speed := 0.0
		if flee.length() > 0.05:
			c.st = "flee"
			dir = flee.normalized()
			speed = flee_speed(flee.length(), factor)
		else:
			c.st = "graze"
			var a: float = _wander.get(c.id, 0.0) + rng.randf_range(-0.6, 0.6) * delta * 3.0
			_wander[c.id] = a
			dir = Vector2(cos(a), sin(a))
			if n > 1 and here.distance_to(centroid) > 6.0:
				dir = (dir + (centroid - here).normalized() * COHESION * 4.0).normalized()
			speed = GRAZE_SPEED
		var step_v := dir * speed * delta
		var moved := here + step_v
		if _blocked(moved):
			var sx := here + Vector2(step_v.x, 0.0)
			var sz := here + Vector2(0.0, step_v.y)
			if not _blocked(sx):
				moved = sx
			elif not _blocked(sz):
				moved = sz
			else:
				moved = here
				_wander[c.id] = float(_wander.get(c.id, 0.0)) + PI * 0.5
		var real := (moved - here) / maxf(delta, 0.0001)
		c.vx = real.x
		c.vz = real.y
		c.x = moved.x
		c.z = moved.y
		if in_pen(moved):
			c.st = "pen"
			c.vx = 0.0
			c.vz = 0.0
			_log("%s est dans l'enclos ! (%d/%d)" % [COW_NAMES[int(c.id) % COW_NAMES.size()], penned() , cow_count])
			_dirty = true


func penned() -> int:
	var n := 0
	for c in cows:
		if c.st == "pen":
			n += 1
	return n


## Vache libre la plus proche de `pos` (Vector2) ; {} si toutes sont dans l'enclos.
func nearest_stray(pos: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for c in cows:
		if c.st != "pen":
			var d := Vector2(c.x, c.z).distance_to(pos)
			if d < bd:
				bd = d
				best = c
	return best


## Là où se placer pour pousser la vache libre la plus proche vers l'enclos : derrière elle, à 7 m, côté opposé à l'enclos.
func herd_target(_from: Vector2) -> Vector3:
	var c := nearest_stray(Vector2(zones.pen.x, zones.pen.z) if zones.has("pen") else _from)    # la plus proche de l'enclos : la plus facile à rentrer
	if c.is_empty() or not zones.has("pen"):
		return Vector3.ZERO
	var cow_p := Vector2(c.x, c.z)
	var away := (cow_p - Vector2(zones.pen.x, zones.pen.z)).normalized()
	var p := cow_p + away * 7.0
	var y: float = _ground.call(p.x, p.y) if _ground.is_valid() else 0.0
	return Vector3(p.x, y, p.y)


func stray_count() -> int:
	return cow_count - penned()


# --- Interaction ------------------------------------------------------------------------------------------------------------------------

func resolve(_peer: int, pos: Vector3) -> Dictionary:
	if step in ["done", "failed"]:
		return {}
	if step == "herd":
		if _whistle_cd > 0.0:
			return {"kind": "none", "label": "Sifflet : encore %d s" % int(ceil(_whistle_cd))}
		return {"kind": "whistle", "label": "Siffler (les vaches à moins de %d m s'écartent de vous)" % int(whistle_range)}
	if step == "gate" and zones.has("pen") and _dist(pos, _front(Vector3(0, 0, PEN_HALF))) < NEAR_GATE:
		return {"kind": "close", "label": "Fermer la barrière de l'enclos"}
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
		"whistle":
			_whistle_cd = whistle_cd
			whistle_left = WHISTLE_TIME
			whistler = Vector2(player.global_position.x, player.global_position.z)
			whistles += 1
		"close":
			_close_gate(player.display_name)
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


func _close_gate(name: String) -> void:
	gate_closed = true
	_log("%s ferme la barrière." % name)
	_finish()


## Bilan (fonction pure, testée) : médaille d'après le nombre de vaches rentrées.
func medal_for(n: int) -> String:
	if n >= thresholds.gold:
		return "gold"
	if n >= thresholds.silver:
		return "silver"
	if n >= thresholds.bronze:
		return "bronze"
	return ""


func _finish() -> void:
	var n := penned()
	medal = medal_for(n)
	result = "win" if medal != "" else "lose"
	step = "done"
	if result == "win":
		_log("%d vache(s) sur %d à l'abri : %s." % [n, cow_count, {"gold": "médaille d'or, pas une seule égarée", "silver": "médaille d'argent", "bronze": "médaille de bronze"}[medal]])
		get_node("/root/Progress").complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), [])
	else:
		_log("Seulement %d vache(s) sur %d : Mémé Odette ira chercher les autres en pantoufles." % [n, cow_count])
	_mark()
	_push_state()


# --- Boucle serveur ------------------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0:
			started = true
			get_node("/root/Progress").start(mission_id)
			if day_night:
				day_night.hour = START_HOUR
			_log("Quatre heures du matin : la barrière de Mémé Odette est restée ouverte ! Rabattez les huit vaches dans l'enclos.")
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	_whistle_cd = maxf(_whistle_cd - delta, 0.0)
	whistle_left = maxf(whistle_left - delta, 0.0)
	_tick_herd(delta)
	if step == "herd":
		time_left -= delta
		if penned() >= cow_count:
			step = "gate"
			_log("Les huit vaches sont rentrées ! Fermez la barrière avant qu'elles ne changent d'avis.")
			_mark()
		elif time_left <= 0.0:
			time_left = 0.0
			_log("Le laitier arrive : le temps est écoulé.")
			_finish()
			return
	elif step == "gate":
		if at_post(ID_GEGE, "gate"):
			_gate_t += delta
			if _gate_t >= CLOSE_DELAY:
				_close_gate("Gégé")
				return
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD:
		_sync_t = 0.0
		_push_state()


func on_player_left(_peer: int) -> void:
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
	return {"step": step, "started": started, "elapsed": elapsed, "cows": cows, "tl": time_left, "wh": whistles, "wl": whistle_left,
		"wp": whistler, "gate": gate_closed, "result": result, "medal": medal, "messages": messages}


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
	cows = s.cows
	time_left = s.tl
	whistles = s.wh
	whistle_left = s.wl
	whistler = s.wp
	gate_closed = s.gate
	result = s.result
	medal = s.medal
	messages = s.messages
	changed.emit()


# --- Sons et rendu ---------------------------------------------------------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"wh": whistles, "pen": penned(), "gate": gate_closed, "step": step}
	if _snd.is_empty():
		_snd = now
		return
	if now.wh > _snd.wh:
		Sfx.play("whistle")
	if now.pen > _snd.pen:
		Sfx.play("moo")
		Sfx.play("chime")
	if now.gate and not _snd.gate:
		Sfx.play("crate")
	if now.step != _snd.step:
		if now.step == "done":
			Sfx.play("fanfare" if result == "win" else "chime")
		elif now.step == "failed":
			Sfx.play("fail")
	_snd = now


func _process(delta: float) -> void:
	_clock += delta
	_audio_events()
	if not is_server():
		if step == "herd":
			time_left = maxf(time_left - delta, 0.0)
		whistle_left = maxf(whistle_left - delta, 0.0)
		for c in cows:
			c.x += c.vx * delta
			c.z += c.vz * delta
	for c in cows:
		var n: Node3D = _cow_nodes.get(int(c.id))
		if n == null:
			continue
		var gy: float = _ground.call(float(c.x), float(c.z)) if _ground.is_valid() else 0.0
		var bob := absf(sin(_clock * 8.0 + float(c.id))) * 0.07 if (absf(float(c.vx)) + absf(float(c.vz))) > 0.5 else 0.0
		n.position = Vector3(float(c.x), gy + bob, float(c.z))
		if absf(float(c.vx)) + absf(float(c.vz)) > 0.1:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(float(c.vx), float(c.vz)), clampf(6.0 * delta, 0.0, 1.0))
	if _gate_node:
		_place_gate()
	for comp in companions():
		(comp as Player).carrying = false


# --- HUD -----------------------------------------------------------------------------------------------------------------------------------------------------

func objective() -> String:
	match step:
		"herd":
			return "Rabattez les vaches dans l'enclos : elles fuient les gens, placez-vous derrière elles. Sifflez (E) pour les pousser de loin."
		"gate":
			return "Toutes les vaches sont dedans : fermez la barrière de l'enclos !"
		"done":
			return "Les vaches sont rentrées."
		"failed":
			return "Les vaches courent toujours."
	return ""


func compass(from: Vector3, to: Vector3) -> String:
	var d := Vector2(to.x - from.x, to.z - from.z)
	var names := ["est", "sud-est", "sud", "sud-ouest", "ouest", "nord-ouest", "nord", "nord-est"]
	var idx := int(round(fposmod(atan2(d.y, d.x), TAU) / (TAU / 8.0))) % 8
	return "%d m vers le %s" % [int(d.length()), names[idx]]


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	if step in ["herd", "gate"]:
		lines.append("À l'enclos : %d/%d   ·   Temps : %s   ·   Sifflet : %s" % [penned(), cow_count, MissionBase.format_time(time_left), "prêt" if _whistle_cd <= 0.0 else "%d s" % int(ceil(_whistle_cd))])
		if not cows.is_empty() and int(cows[0].id) == 0 and cows[0].st != "pen":
			lines.append("Marguerite, la meneuse, est la plus farouche.")
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_status(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	match role:
		"rabatteur":
			return "rabat les vaches vers l'enclos" if step == "herd" else "se repose"
		"guetteur":
			var s := nearest_stray(Vector2(c.global_position.x, c.global_position.z))
			if step == "herd" and not s.is_empty():
				return "voit une vache à %s" % compass(c.global_position, Vector3(s.x, 0, s.z))
			return "n'a plus rien à guetter"
		"barriere":
			return "tient la barrière" if at_post(c.peer_id, "gate") else "gagne la barrière"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "%s — médaille : %s" % ["Troupeau rentré" if result == "win" else "Troupeau en fuite", {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")]
	return ""
