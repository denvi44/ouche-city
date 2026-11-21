class_name MissionM08
extends MissionBase
## Mission 08 « Les oies font grève » (agent 05) : vous êtes l'oie meneuse. Rassemblez le troupeau de la mare d'un « HONK ! »,
## menez-le sur la voie ferrée et bloquez le Train des Vacances (17 h 42, Paris → Pays de Frouch) assez longtemps pour que les
## Parisiens descendent et s'attendrissent. Le garde-barrière tente de chasser les oies ; un « HONK ! » bien placé le fait reculer.
##
## Règles : le train freine toujours, sans exception (humour tendre : personne n'est blessé). Il s'arrête devant les oies et attend
## tant que `min_blockers` oies au moins tiennent la voie ; si elles lâchent trop longtemps, il repart et passe. Le klaxon du train
## effraie les oies que le meneur n'a pas rassurées d'un « HONK ! » récent. Simulation à autorité serveur ; les clients reçoivent
## les positions (`_sync`) et prolongent le mouvement entre deux envois.

const MISSION_FILE := "res://assets/missions/m08_oies_en_greve.json"
const SYNC_PERIOD := 0.2
const START_HOUR := 17.0
const GRAZE_SPEED := 0.4
const RUN_SPEED := 5.2
const BLOCK_SPEED := 2.2
const FLEE_SPEED := 4.8
const FLEE_TIME := 6.0
const CALM_TIME := 6.0                              # s pendant lesquelles un « HONK ! » rassure les oies sur la voie
const ZONE_U := Vector2(-12.0, 6.0)                 # zone de blocage : abscisse le long de la voie (m, 0 = passage à niveau)
const ZONE_V := 2.0                                 # demi-largeur (m)
const STOP_BEFORE := 16.0                           # m : le train s'arrête avant la première oie
const TRAIN_LEN := 52.0
const MASTER_SPEED := 1.7
const SHOO_RANGE := 5.0
const STUN_RANGE := 8.0
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_KEVIN := -4
const NEAR_POST := 3.0

var mission_id := "m08_oies_en_greve"
var goose_count := 12
var time_limit := 480.0
var arrival_sec := 120.0                            # instant où le train atteint le passage à niveau
var train_speed := 15.0
var hold_required := 30.0
var min_blockers := 5
var honk_range := 20.0
var honk_cd_max := 2.0
var master_delay := 25.0                            # s après l'arrêt du train avant que le garde-barrière sorte
var master_stun := 9.0
var thresholds := {"gold": 10.0, "silver": 8.0, "bronze": 5.0}      # moyenne d'oies sur la voie pendant la tenue
var rewards := {}

var geese: Array = []                               # {id, x, z, vx, vz, st: graze|follow|block|flee, lead, calm, t, slot}
var train := {"s": 0.0, "v": 0.0, "st": "wait", "hold": 0.0, "weak": 0.0, "horn": 0.0}
var master := {"x": 0.0, "z": 0.0, "vx": 0.0, "vz": 0.0, "st": "hut", "t": 0.0}
var time_left := 480.0
var honks := 0
var honker := 0                                     # dernier joueur à avoir crié
var honk_pos := Vector2.ZERO
var result := ""                                    # "" | "win" | "lose"
var medal := ""
var blk_sum := 0.0
var blk_n := 0
var avg_blockers := 0.0

var rng := RandomNumberGenerator.new()
var zones := {}                                     # crossing, pond -> Vector3
var facing_track := 0.0
var track_len := 360.0
var day_night: DayNight
var _ground: Callable
var _grid := {}
var _spots := {}
var _nodes := {}
var _train_node: Node3D
var _master_node: Node3D
var _honk_cd := {}                                 # pair -> recharge du cri (s), côté serveur
var _local_cd := 0.0                                # recharge du cri affichée par un client
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _clock := 0.0
var _wander := {}
var _train_started := false
var station_side := -1                              # côté de la voie où se trouve le quai (+1 : +X local, à droite)
var _visitors: Array = []                           # voyageurs sur le quai (visuel seulement)


func _ready() -> void:
	title = "Les oies font grève"
	step = "gather"
	rng.seed = 20260108
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		goose_count = int(m.flock.geese)
		time_limit = float(m.flock.timeLimitSec)
		honk_range = float(m.honk.range)
		honk_cd_max = float(m.honk.cooldownSec)
		arrival_sec = float(m.train.arrivalSec)
		train_speed = float(m.train.speedMs)
		hold_required = float(m.train.holdSec)
		min_blockers = int(m.train.minBlockers)
		master_delay = float(m.stationmaster.delaySec)
		master_stun = float(m.stationmaster.stunSec)
		for k in ["gold", "silver", "bronze"]:
			thresholds[k] = float(m.medals[k].avgGeese)
		rewards = m.rewards
	time_left = time_limit


# --- Mise en place -------------------------------------------------------------------------------------------

func setup(pois: Array, ground: Callable, _vehicle: Vehicle, players_root: Node3D) -> void:
	_ground = ground
	_players_root = players_root
	var w := get_parent()
	day_night = w.get("day_night")
	for p in pois:
		if p.id == "gare_pays_frouch":
			station_side = int(p.get("side", -1))
			zones["station"] = Vector3(float(p.position[0]), ground.call(float(p.position[0]), float(p.position[1])), float(p.position[1]))
		if p.id == "passage_niveau" or p.id == "etang_oies":
			var x := float(p.position[0])
			var z := float(p.position[1])
			zones["crossing" if p.id == "passage_niveau" else "pond"] = Vector3(x, ground.call(x, z), z)
			if p.id == "passage_niveau":
				facing_track = float(p.get("facing", 0.0))
				track_len = float(p.get("length", 360.0))
	_index_buildings(RoadNav.footprints())
	_spawn_flock()
	var h := track_to_world(Vector2(-3.0, 14.0))        # maisonnette du garde-barrière : à 14 m de la voie, côté « droite »
	master.x = h.x
	master.z = h.z
	train.s = 0.0
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


func _spawn_flock() -> void:
	geese = []
	if not zones.has("pond"):
		return
	var c: Vector3 = zones.pond
	for i in goose_count:
		var r := 3.0 + 13.0 * sqrt((float(i) + 0.5) / float(goose_count))
		var a := float(i) * 2.399963
		var p := Vector2(c.x, c.z) + Vector2(cos(a), sin(a)) * r
		geese.append({"id": i, "x": p.x, "z": p.y, "vx": 0.0, "vz": 0.0, "st": "graze", "lead": 0, "calm": 0.0, "t": 0.0, "slot": -1})
		_wander[i] = a


func _build_visuals() -> void:
	var w := get_parent()
	for i in goose_count:
		var n := PropKit.goose(i % 2).build()
		n.name = "Oie_%d" % i
		w.add_child(n)
		_nodes[i] = n
	_train_node = PropKit.train().build()
	_train_node.name = "M8_Train"
	_train_node.visible = false
	w.add_child(_train_node)
	_master_node = _fallback_master()
	if zones.has("station"):
		_build_visitors(w)
	_master_node.name = "M8_GardeBarriere"
	w.add_child(_master_node)


## Voyageurs parisiens sur le quai : visibles quand le train est arrêté devant les oies (visuel seulement, positions fixes).
func _build_visitors(w: Node) -> void:
	var shirts := [Color(0.2, 0.2, 0.25), Color(0.85, 0.75, 0.6), Color(0.35, 0.5, 0.45), Color(0.15, 0.15, 0.18), Color(0.7, 0.35, 0.4), Color(0.9, 0.9, 0.85)]
	var cases := [Color(0.8, 0.25, 0.25), Color(0.25, 0.4, 0.75), Color(0.15, 0.15, 0.18), Color(0.85, 0.7, 0.2), Color(0.3, 0.6, 0.4), Color(0.6, 0.3, 0.6)]
	for i in 6:
		var n := Node3D.new()
		n.name = "Voyageur_%d" % i
		var model := CharacterModel.make(shirts[i], Color(0.18, 0.2, 0.28), Color(0.15, 0.15, 0.2), {"hair": Color(0.2 + 0.1 * float(i % 3), 0.15, 0.1), "scarf": Color(0.8, 0.2 + 0.1 * float(i), 0.3), "glasses": i % 2 == 0})
		model.scale = Vector3.ONE * 0.93
		n.add_child(model)
		var sc := PropKit.suitcase(cases[i]).build()
		sc.position = Vector3(0.55, 0.0, 0.0)
		n.add_child(sc)
		n.visible = false
		w.add_child(n)
		_visitors.append(n)


func _fallback_master() -> Node3D:
	var m := CharacterModel.make(Color(0.2, 0.3, 0.55), Color(0.15, 0.17, 0.25), Color(0.1, 0.15, 0.35), {"moustache": Color(0.5, 0.5, 0.48), "headgear": "cap_back"})
	m.scale = Vector3.ONE * 0.93
	return m


# --- Repère de la voie : u le long de la voie (+ vers le train qui s'en va), v à droite --------------------------------------------

## (u, v) -> monde (x, z). Le passage à niveau est l'origine ; +u suit le cap de la voie.
func track_to_world(l: Vector2) -> Vector3:
	if not zones.has("crossing"):
		return Vector3.ZERO
	var c: Vector3 = zones.crossing
	var d := Vector2(sin(facing_track), cos(facing_track))
	var r := Vector2(d.y, -d.x)
	var p := Vector2(c.x, c.z) + d * l.x + r * l.y
	return Vector3(p.x, _ground.call(p.x, p.y) if _ground.is_valid() else c.y, p.y)


func to_track(p: Vector2) -> Vector2:
	if not zones.has("crossing"):
		return Vector2.ZERO
	var c: Vector3 = zones.crossing
	var d := Vector2(sin(facing_track), cos(facing_track))
	var r := Vector2(d.y, -d.x)
	var q := p - Vector2(c.x, c.z)
	return Vector2(q.dot(d), q.dot(r))


## Fonction pure (testée) : un point (u, v) est-il dans la zone de blocage ?
static func in_zone(l: Vector2) -> bool:
	return l.x >= ZONE_U.x and l.x <= ZONE_U.y and absf(l.y) <= ZONE_V


## Position du nez du train (u le long de la voie) pour l'abscisse curviligne `s` (0 = point de départ).
func train_u(s: float) -> float:
	return s - track_len / 2.0 + 10.0


func train_start_u() -> float:
	return -track_len / 2.0 + 10.0


## Les joueurs apparaissent à 7 m de la mare, côté voie.
func spawn_hint() -> Vector3:
	if not zones.has("pond") or not zones.has("crossing"):
		return Vector3.ZERO
	var p: Vector3 = zones.pond
	var c: Vector3 = zones.crossing
	var d := Vector2(c.x - p.x, c.z - p.z).normalized() * 11.0
	return Vector3(p.x + d.x, 0.0, p.z + d.y)


func companion_roles() -> Dictionary:
	return {ID_KEVIN: "rabatteuse", ID_GINETTE: "sentinelle", ID_GEGE: "ferme_file"}


func look_target() -> Vector3:
	return zones.get("crossing", Vector3.ZERO)


func spot(name: String) -> Vector3:
	if _spots.has(name):
		return _spots[name]
	var base := Vector3.ZERO
	match name:
		"pond":
			base = zones.get("pond", Vector3.ZERO)
		"crossing":
			base = track_to_world(Vector2(-1.0, 0.0))
		"hut_side":
			base = track_to_world(Vector2(-4.0, 6.0))
		"line_side":
			base = track_to_world(Vector2(-14.0, 4.0))
		_:
			return Vector3.ZERO
	if base == Vector3.ZERO:
		return base
	_spots[name] = base
	return base


func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func at_post(id: int, name: String) -> bool:
	var a := actor(id)
	var s := spot(name)
	return a != null and s != Vector3.ZERO and _dist(a.global_position, s) < NEAR_POST


func _in_building(p: Vector2) -> bool:
	for r in _grid.get(Vector2i(int(floor(p.x / 40.0)), int(floor(p.y / 40.0))), []):
		if Geometry2D.is_point_in_polygon(p, r):
			return true
	return false


# --- Troupeau (serveur) -------------------------------------------------------------------------------------------------------------

func _sources() -> Array:
	var out := []
	if _players_root:
		for p in _players_root.get_children():
			if p is Player:
				out.append(p)
	return out


func followers_of(peer: int) -> Array:
	var out := []
	for g in geese:
		if g.st == "follow" and int(g.lead) == peer:
			out.append(g)
	return out


func count_state(st: String) -> int:
	var n := 0
	for g in geese:
		if g.st == st:
			n += 1
	return n


func blockers() -> int:
	return count_state("block")


## Oie libre (ni suiveuse ni sur la voie) la plus proche de `pos`.
func nearest_free(pos: Vector2) -> Dictionary:
	var best := {}
	var bd := 1e9
	for g in geese:
		if g.st == "graze" or g.st == "flee":
			var d := Vector2(g.x, g.z).distance_to(pos)
			if d < bd:
				bd = d
				best = g
	return best


func free_count() -> int:
	return count_state("graze") + count_state("flee")


func _move_goose(g: Dictionary, target: Vector2, speed: float, delta: float) -> void:
	var here := Vector2(g.x, g.z)
	var d := target - here
	var v := Vector2.ZERO
	if d.length() > 0.15:
		v = d.normalized() * minf(speed, d.length() / maxf(delta, 0.001))
	var moved := here + v * delta
	if _in_building(moved):
		var sx := here + Vector2(v.x * delta, 0.0)
		var sz := here + Vector2(0.0, v.y * delta)
		if not _in_building(sx):
			moved = sx
		elif not _in_building(sz):
			moved = sz
		else:
			moved = here
	var real := (moved - here) / maxf(delta, 0.0001)
	g.vx = real.x
	g.vz = real.y
	g.x = moved.x
	g.z = moved.y


func _tick_flock(delta: float) -> void:
	var srcs := _sources()
	var pond := Vector2(zones.pond.x, zones.pond.z) if zones.has("pond") else Vector2.ZERO
	var slot_taken := {}
	for g in geese:
		if g.st == "block" and int(g.slot) >= 0:
			slot_taken[int(g.slot)] = true
	for g in geese:
		g.calm = maxf(float(g.calm) - delta, 0.0)
		g.t = maxf(float(g.t) - delta, 0.0)
		var here := Vector2(g.x, g.z)
		match g.st:
			"graze", "flee":
				if g.st == "flee":
					var away := Vector2(g.vx, g.vz)
					if away.length() < 0.1:
						away = (here - Vector2(master.x, master.z))
					_move_goose(g, here + away.normalized() * 6.0, FLEE_SPEED, delta)
					if float(g.t) <= 0.0:
						g.st = "graze"
				else:
					var a: float = _wander.get(g.id, 0.0) + rng.randf_range(-0.6, 0.6) * delta * 3.0
					_wander[g.id] = a
					var tgt := here + Vector2(cos(a), sin(a)) * 2.0
					if here.distance_to(pond) > 18.0:
						tgt = here + (pond - here).normalized() * 2.0
					_move_goose(g, tgt, GRAZE_SPEED, delta)
			"follow":
				var leader := actor(int(g.lead)) as Player
				if leader == null:
					g.st = "graze"
					continue
				var lp := Vector2(leader.global_position.x, leader.global_position.z)
				if here.distance_to(lp) > 45.0:
					g.st = "graze"
					g.lead = 0
					continue
				var mine := followers_of(int(g.lead))
				var k := 0
				for i in mine.size():
					if int(mine[i].id) == int(g.id):
						k = i
				var f := leader.facing
				var back := Vector2(sin(f), cos(f))
				var side := Vector2(back.y, -back.x)
				var row := k / 3 + 1
				var col := k % 3 - 1
				var slot := lp + back * (1.8 + 1.4 * float(row)) + side * float(col) * 1.5      # derrière le meneur (back = -sens de marche)
				var dist := here.distance_to(slot)
				_move_goose(g, slot, clampf(dist * 2.2, 0.0, RUN_SPEED), delta)
				# Sur la voie : l'oie s'y installe, ou dès que le meneur est sur la voie et qu'elle est près de lui.
				var on_track := in_zone(to_track(Vector2(g.x, g.z)))
				var leader_on := in_zone(to_track(lp)) and here.distance_to(lp) < 9.0
				if (on_track or leader_on) and train.st != "leave":
					g.st = "block"
					g.lead = 0
					g.slot = _free_slot(slot_taken)
					slot_taken[int(g.slot)] = true
			"block":
				if int(g.slot) >= 0:
					var sp := slot_to_world(int(g.slot))
					_move_goose(g, sp, BLOCK_SPEED, delta)
				else:
					g.vx = 0.0
					g.vz = 0.0


## Case de la zone de blocage (2 colonnes × 6 rangées) : les oies s'alignent sur la voie au lieu de se superposer.
func _free_slot(taken: Dictionary) -> int:
	for i in 12:
		if not taken.has(i):
			return i
	return 0


func slot_to_world(i: int) -> Vector2:
	var u := ZONE_U.x + 1.5 + float(i / 2) * ((ZONE_U.y - ZONE_U.x - 3.0) / 5.0)
	var v := -0.8 if i % 2 == 0 else 0.8
	var w := track_to_world(Vector2(u, v))
	return Vector2(w.x, w.z)


# --- Train et garde-barrière ------------------------------------------------------------------------------------------------------

func train_nose_u() -> float:
	return train_u(float(train.s))


func _tick_train(delta: float) -> void:
	var t: Dictionary = train
	var u0 := train_start_u()
	match t.st:
		"wait":
			# Le train part pour arriver au passage à niveau à `arrival_sec` (15 m/s : il lui faut |u0|/vitesse secondes).
			var lead := absf(u0) / train_speed
			if elapsed >= arrival_sec - lead:
				t.st = "run"
				t.v = train_speed
				_log("Le Train des Vacances de 17 h 42 approche ! Les oies sur la voie, vite !")
				_mark()
		"run", "brake":
			var nose := train_nose_u()
			var b := blockers()
			var stop_u := ZONE_U.x - STOP_BEFORE + 4.0
			if b >= 1 and nose < stop_u:
				# Freinage doux : décélération qui amène le nez à l'arrêt à `stop_u` (jamais de choc).
				var d := maxf(stop_u - nose, 0.5)
				var a := clampf(t.v * t.v / (2.0 * d), 1.2, 25.0)       # freinage d'urgence si les oies arrivent tard
				t.v = maxf(float(t.v) - a * delta, 0.0)
				if float(t.v) < 0.3 and d < 4.0:
					t.v = 0.0
				t.st = "brake"
			elif t.st == "brake" and b == 0 and nose < stop_u:
				t.st = "run"
			if t.st == "run":
				t.v = move_toward(float(t.v), train_speed, 3.0 * delta)
			t.s = float(t.s) + float(t.v) * delta
			if t.st == "brake" and float(t.v) <= 0.05:
				t.v = 0.0
				t.st = "stopped"
				t.horn = 0.0
				_log("Le train s'arrête devant les oies ! Tenez la voie pendant %d secondes." % int(hold_required))
				bark("m08_train_stops", 120.0)
				_mark()
			# Passé devant tout le monde sans s'arrêter.
			if train_nose_u() > ZONE_U.y + 30.0:
				_lose("Le train est passé. Les vacanciers saluent depuis les fenêtres, un peu surpris.")
		"stopped":
			var b2 := blockers()
			t.horn = float(t.horn) + delta
			if float(t.horn) >= 9.0:
				t.horn = 0.0
				_train_horn()
			if b2 >= min_blockers:
				t.hold = float(t.hold) + delta
				t.weak = 0.0
				blk_sum += float(b2) * delta
				blk_n += 1
				if float(t.hold) >= hold_required:
					_win()
					return
			else:
				t.weak = float(t.weak) + delta
				if float(t.weak) >= 7.0:
					t.st = "run"
					t.v = 1.0
					_log("Trop peu d'oies sur la voie : le train redémarre !")
					_mark()


## Le klaxon du train effraie les oies sur la voie que le meneur n'a pas rassurées d'un « HONK ! » récent.
func _train_horn() -> void:
	train.horn_snd = int(train.get("horn_snd", 0)) + 1
	for g in geese:
		if g.st == "block" and float(g.calm) <= 0.0 and rng.randf() < 0.45:
			g.st = "flee"
			g.t = FLEE_TIME
			g.slot = -1
			var away := Vector2(g.x, g.z) - Vector2(master.x, master.z)
			g.vx = away.normalized().x
			g.vz = away.normalized().y
	_dirty = true


func _tick_master(delta: float) -> void:
	var m: Dictionary = master
	var hut := track_to_world(Vector2(-3.0, 14.0))
	var here := Vector2(m.x, m.z)
	m.t = float(m.t) - delta
	match m.st:
		"hut":
			m.vx = 0.0
			m.vz = 0.0
			if float(m.t) <= 0.0 and train.st == "stopped" and elapsed >= float(train.get("stopped_at", 1.0e9)):
				m.st = "walk"
		"walk", "shoo":
			var target_w := track_to_world(Vector2(-6.0, 3.0))
			var target := Vector2(target_w.x, target_w.z)
			var d := target - here
			var v := d.normalized() * MASTER_SPEED if d.length() > 1.5 else Vector2.ZERO
			m.vx = v.x
			m.vz = v.y
			m.x += v.x * delta
			m.z += v.y * delta
			# Il chasse l'oie la plus proche (toutes les 2,5 s) tant qu'il est à portée.
			if float(m.t) <= 0.0:
				var best := {}
				var bd := SHOO_RANGE
				for g in geese:
					if g.st == "block":
						var dd := Vector2(g.x, g.z).distance_to(here)
						if dd < bd:
							bd = dd
							best = g
				if not best.is_empty():
					best.st = "flee"
					best.t = FLEE_TIME + 2.0
					best.slot = -1
					var away := Vector2(best.x, best.z) - here
					best.vx = away.normalized().x
					best.vz = away.normalized().y
					m.t = 2.5
					m.st = "shoo"
					_dirty = true
		"stunned":
			m.vx = 0.0
			m.vz = 0.0
			if float(m.t) <= 0.0:
				m.st = "back"
		"back":
			var d2 := Vector2(hut.x, hut.z) - here
			var v2 := d2.normalized() * (MASTER_SPEED * 1.4) if d2.length() > 1.0 else Vector2.ZERO
			m.vx = v2.x
			m.vz = v2.y
			m.x += v2.x * delta
			m.z += v2.y * delta
			if d2.length() <= 1.0:
				m.st = "hut"
				m.t = 15.0


# --- Interaction : « HONK ! » -------------------------------------------------------------------------------------------------

func resolve(_peer: int, _pos: Vector3) -> Dictionary:
	if step in ["done", "failed"]:
		return {}
	var cd := float(_honk_cd.get(_peer, 0.0)) if is_server() else _local_cd
	if cd > 0.0:
		return {"kind": "none", "label": "HONK : encore %.1f s" % cd}
	return {"kind": "honk", "label": "HONK ! (rassemble les oies à moins de %d m)" % int(honk_range)}


func interact(peer: int, allowed: Array = []) -> void:
	if not is_server():
		return
	var player := actor(peer) as Player
	if player == null:
		return
	var r := resolve(peer, player.global_position)
	var kind: String = r.get("kind", "")
	if kind != "honk" or (not allowed.is_empty() and not (kind in allowed)):
		return
	_honk(peer, player)
	_mark()


func _honk(peer: int, player: Player) -> void:
	_honk_cd[peer] = honk_cd_max
	honks += 1
	honker = peer
	var hp := Vector2(player.global_position.x, player.global_position.z)
	honk_pos = hp
	var taken := {}
	for g in geese:
		if g.st == "block" and int(g.slot) >= 0:
			taken[int(g.slot)] = true
	var recruited := 0
	for g in geese:
		var d := Vector2(g.x, g.z).distance_to(hp)
		if d > honk_range:
			continue
		if g.st == "graze" or g.st == "flee":
			g.st = "follow"
			g.lead = peer
			recruited += 1
		elif g.st == "block":
			g.calm = CALM_TIME                 # rassurées : le klaxon du train et le garde-barrière n'ont plus de prise un moment
	# Le garde-barrière recule si l'on crie dans ses oreilles.
	var mp := Vector2(master.x, master.z)
	if mp.distance_to(hp) <= STUN_RANGE and master.st in ["walk", "shoo"]:
		master.st = "stunned"
		master.t = master_stun
		_log("« HONK ! » : le garde-barrière a sursauté, il bat en retraite.")
		bark("m08_master", 30.0)
	if recruited > 0:
		bark("m08_honk_recruit", 12.0)


func request_interact() -> void:
	if is_server():
		interact(multiplayer.get_unique_id())
	elif _local_cd <= 0.0:
		_local_cd = honk_cd_max
		_request_interact.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if is_server():
		interact(multiplayer.get_remote_sender_id())


## Bilan (fonction pure, testée) : médaille d'après le nombre moyen d'oies sur la voie pendant la tenue.
func medal_for(avg: float) -> String:
	if avg >= float(thresholds.gold):
		return "gold"
	if avg >= float(thresholds.silver):
		return "silver"
	if avg >= float(thresholds.bronze):
		return "bronze"
	return ""


func _win() -> void:
	avg_blockers = blk_sum / maxf(float(blk_n) * (1.0 / 60.0), 0.001) if blk_n > 0 else 0.0
	# `blk_sum` cumule (oies × secondes) : on divise par la durée de tenue.
	avg_blockers = blk_sum / maxf(float(train.hold), 0.001)
	medal = medal_for(avg_blockers)
	result = "win" if medal != "" else "lose"
	step = "done"
	if result == "win":
		_log("Le train est bloqué ! %s Les Parisiens descendent, sortent leurs téléphones et… se laissent attendrir." % {"gold": "Médaille d'or : toute la basse-cour est là.", "silver": "Médaille d'argent.", "bronze": "Médaille de bronze."}[medal])
		get_node("/root/Progress").complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), [])
	else:
		_log("Trop peu d'oies pour impressionner le train : il repartira dès qu'on aura le dos tourné.")
	_mark()
	_push_state()


func _lose(text: String) -> void:
	result = "lose"
	step = "failed"
	_log(text)
	_mark()
	_push_state()


# --- Boucle serveur ------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0:
			started = true
			get_node("/root/Progress").start(mission_id)
			if day_night:
				day_night.hour = START_HOUR
			_log("Vendredi, 17 h : le Train des Vacances ramène les Parisiens à 17 h 42. Rassemblez la basse-cour d'un « HONK ! » et barrez la voie !")
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	for k in _honk_cd.keys():
		_honk_cd[k] = maxf(float(_honk_cd[k]) - delta, 0.0)
	_tick_flock(delta)
	_tick_train(delta)
	if step in ["done", "failed"]:
		return
	_tick_master(delta)
	if train.st == "stopped" and not train.has("stopped_at"):
		train.stopped_at = elapsed + master_delay
	if step == "gather" and train.st in ["run", "brake", "stopped"]:
		step = "block"
		_mark()
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		_lose("Le temps est écoulé : le train repart, les oies rentrent dîner.")
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


# --- Réplication ---------------------------------------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"step": step, "started": started, "elapsed": elapsed, "geese": geese, "train": train, "master": master, "tl": time_left,
		"honks": honks, "honker": honker, "hp": honk_pos, "result": result, "medal": medal, "avg": avg_blockers, "messages": messages}


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
	geese = s.geese
	train = s.train
	master = s.master
	time_left = s.tl
	honks = s.honks
	honker = s.honker
	honk_pos = s.hp
	result = s.result
	medal = s.medal
	avg_blockers = s.avg
	messages = s.messages
	changed.emit()


# --- Sons et rendu ---------------------------------------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"hk": honks, "step": step, "tr": train.st, "horn": int(train.get("horn_snd", 0)), "ms": master.st}
	if _snd.is_empty():
		_snd = now
		return
	if now.hk > _snd.hk:
		var who := actor(honker) as Player
		Sfx.play_at("honk", who.global_position if who else Vector3.ZERO)
		if who and who.model and who.model.has_method("honk"):
			who.model.call("honk")
	if now.tr != _snd.tr and now.tr == "run":
		Sfx.play("train_horn")
	if now.horn > _snd.horn:
		Sfx.play("train_horn")
	if now.step != _snd.step:
		if now.step == "done":
			Sfx.play("fanfare" if result == "win" else "chime")
		elif now.step == "failed":
			Sfx.play("fail")
	_snd = now


func _ground_y(x: float, z: float) -> float:
	return _ground.call(x, z) if _ground.is_valid() else 0.0


func _process(delta: float) -> void:
	_clock += delta
	_audio_events()
	_local_cd = maxf(_local_cd - delta, 0.0)
	if not is_server():
		if step in ["gather", "block"]:
			time_left = maxf(time_left - delta, 0.0)
		for g in geese:
			g.x += g.vx * delta
			g.z += g.vz * delta
		if train.st in ["run", "brake"]:
			train.s = float(train.s) + float(train.v) * delta
		master.x += master.vx * delta
		master.z += master.vz * delta
	for g in geese:
		var n: Node3D = _nodes.get(int(g.id))
		if n == null:
			continue
		var moving: bool = absf(float(g.vx)) + absf(float(g.vz)) > 0.4
		var bob := absf(sin(_clock * 10.0 + float(g.id))) * 0.05 if moving else 0.0
		n.position = Vector3(float(g.x), _ground_y(float(g.x), float(g.z)) + bob, float(g.z))
		n.rotation.z = sin(_clock * 9.0 + float(g.id)) * 0.1 if moving else 0.0
		if moving:
			n.rotation.y = lerp_angle(n.rotation.y, atan2(float(g.vx), float(g.vz)), clampf(8.0 * delta, 0.0, 1.0))
		elif g.st == "block" or g.st == "follow":
			n.rotation.y = lerp_angle(n.rotation.y, facing_track + PI * 0.5, clampf(3.0 * delta, 0.0, 1.0)) if g.st == "block" else n.rotation.y
	_place_train()
	_place_visitors()
	if _master_node:
		_master_node.position = Vector3(float(master.x), _ground_y(float(master.x), float(master.z)), float(master.z))
		var mv := Vector2(float(master.vx), float(master.vz))
		if mv.length() > 0.1:
			_master_node.rotation.y = lerp_angle(_master_node.rotation.y, atan2(mv.x, mv.y), clampf(8.0 * delta, 0.0, 1.0))
		_master_node.visible = master.st != "hut" or true
	for comp in companions():
		(comp as Player).carrying = false


func _place_visitors() -> void:
	if _visitors.is_empty():
		return
	var out: bool = train.st == "stopped" or step == "done"
	var r := Vector2(cos(facing_track), -sin(facing_track))         # « droite » de la voie
	for i in _visitors.size():
		var n: Node3D = _visitors[i]
		n.visible = out and (step == "done" or float(train.hold) > 1.0 + 0.8 * float(i))
		if not n.visible:
			continue
		var w := track_to_world(Vector2(-70.0 + 7.0 * float(i) + 2.0 * sin(float(i)), float(station_side) * 3.7))
		n.position = Vector3(w.x, w.y + 0.8, w.z)
		var toward := r * float(-station_side)                   # vers l'axe de la voie
		n.rotation.y = atan2(toward.x, toward.y) + 0.35 * sin(float(i) * 1.7 + _clock * 0.3)


func _place_train() -> void:
	if _train_node == null or not zones.has("crossing"):
		return
	_train_node.visible = train.st != "wait"
	if not _train_node.visible:
		return
	var nose := train_nose_u()
	var wnose := track_to_world(Vector2(nose, 0.0))
	var wtail := track_to_world(Vector2(nose - 30.0, 0.0))
	var hmid := (wnose.y + wtail.y) / 2.0
	# Le modèle a son nez à +9,1 m de l'origine : on recule l'origine d'autant.
	var d := Vector2(sin(facing_track), cos(facing_track))
	var org := Vector2(wnose.x, wnose.z) - d * 9.1
	_train_node.position = Vector3(org.x, hmid + 0.3, org.y)
	_train_node.rotation.y = facing_track
	_train_node.rotation.x = -atan2(wnose.y - wtail.y, 30.0)


# --- HUD -----------------------------------------------------------------------------------------------------------------------------------

func objective() -> String:
	match step:
		"gather":
			return "Vous êtes l'oie meneuse : criez « HONK ! » (E) près des oies de la mare pour qu'elles vous suivent, puis menez-les sur la voie ferrée."
		"block":
			if train.st == "stopped":
				return "Le train est arrêté : gardez au moins %d oies sur la voie pendant %d s. Criez pour les rassurer et pour faire reculer le garde-barrière !" % [min_blockers, int(hold_required)]
			return "Le train arrive : installez les oies sur la voie, devant lui !"
		"done":
			return "Le train est arrêté : les Parisiens descendent."
		"failed":
			return "Le train est passé."
	return ""


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	if step in ["gather", "block"]:
		lines.append("Oies : %d à vous · %d sur la voie · %d à la mare   ·   Temps : %s" % [count_state("follow"), blockers(), free_count(), MissionBase.format_time(time_left)])
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_status(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	match role:
		"rabatteuse":
			return "rassemble les oies de la mare" if free_count() > 0 else "tient la voie avec les autres"
		"sentinelle":
			return "guette le garde-barrière" if master.st != "stunned" else "vient de faire reculer le garde-barrière"
		"ferme_file":
			return "rassure les oies sur la voie"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "%s — médaille : %s" % ["Train bloqué" if result == "win" else "Train reparti", {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")]
	if step == "failed":
		return "Le train est passé"
	return ""


func hud_gauges() -> Array:
	var out := []
	if step in ["gather", "block"]:
		out.append(gauge("voie", "Oies sur la voie", float(blockers()) / float(maxi(goose_count, 1)), C_OK, "%d / %d" % [blockers(), goose_count]))
		if train.st == "stopped":
			out.append(gauge("tenue", "Tenue du blocage", float(train.hold) / hold_required, C_GOAL, "%d s" % int(float(train.hold)), {"zone": Vector2(0.0, 1.0)}))
		else:
			var eta := maxf(arrival_sec - elapsed, 0.0)
			out.append(gauge("train", "Arrivée du train", 1.0 - eta / arrival_sec, C_DANGER, MissionBase.format_time(eta) if train.st == "wait" else "il arrive !"))
		out.append(gauge("temps", "Temps", time_left / time_limit, C_PLACE, MissionBase.format_time(time_left), {"low_is_bad": true}))
	return out


func hud_markers() -> Array:
	var out := []
	if step not in ["gather", "block"] or not zones.has("crossing"):
		return out
	var me := actor(local_peer())
	var from := Vector2(me.global_position.x, me.global_position.z) if me else Vector2.ZERO
	var need := count_state("follow") + blockers() < mini(goose_count, min_blockers + 3)
	var free := nearest_free(from)
	if need and not free.is_empty() and train.st != "stopped":
		out.append(marker(Vector3(float(free.x), _ground_y(float(free.x), float(free.z)), float(free.z)), "Oie à rassembler", C_ITEM))
	out.append(marker(spot("crossing"), "La voie ferrée", C_GOAL))
	if master.st in ["walk", "shoo"]:
		out.append(marker(Vector3(float(master.x), _ground_y(float(master.x), float(master.z)), float(master.z)), "Garde-barrière", C_DANGER, true))
	return out
