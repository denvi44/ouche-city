class_name AmbientLife
extends Node3D
## Vie ambiante (décor) : des passants qui marchent sur les trottoirs et des voitures qui circulent lentement, pour que le village ne soit pas désert.
## Tout est LOCAL à chaque joueur et sans collision : rien n'est répliqué, rien n'influe sur une mission (le serveur n'en sait rien).
## Les figurants naissent et disparaissent autour du joueur (budget : PED_MAX passants et CAR_MAX voitures à la fois, jamais d'apparition à moins
## de PED_SPAWN_MIN / CAR_SPAWN_MIN mètres). Les voitures s'arrêtent (et klaxonnent) devant un joueur, la camionnette ou une autre voiture.
## Absent en headless (serveur dédié, tests) sauf `AmbientLife.force` ; désactivable (Settings.ambient_life).

const PED_MAX := 24
const CAR_MAX := 6
const PED_SPAWN_MIN := 28.0
const PED_SPAWN_MAX := 100.0
const PED_OUT := 135.0
const CAR_SPAWN_MIN := 70.0
const CAR_SPAWN_MAX := 170.0
const CAR_OUT := 230.0
const TICK := 0.5
const KINDS_PED := ["residential", "tertiary", "secondary", "unclassified", "living_street", "primary"]
const KINDS_CAR := ["residential", "tertiary", "secondary", "unclassified", "primary"]
const CAR_COLORS := [Color(0.62, 0.2, 0.18), Color(0.25, 0.4, 0.62), Color(0.82, 0.78, 0.66), Color(0.3, 0.45, 0.35), Color(0.75, 0.75, 0.78), Color(0.9, 0.7, 0.2), Color(0.35, 0.33, 0.38)]
const SHIRTS := [Color(0.75, 0.3, 0.25), Color(0.3, 0.45, 0.65), Color(0.85, 0.75, 0.4), Color(0.4, 0.6, 0.4), Color(0.6, 0.4, 0.6), Color(0.9, 0.9, 0.85), Color(0.5, 0.35, 0.25)]
const TROUSERS := [Color(0.2, 0.22, 0.3), Color(0.35, 0.3, 0.25), Color(0.25, 0.3, 0.25), Color(0.4, 0.4, 0.45)]

static var force := false

var world: Node
var builder: CityBuilder
var peds: Array = []
var cars: Array = []
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _ped_roads: Array = []
var _car_roads: Array = []
var enabled := true
var ped_serial := 0


static func is_available() -> bool:
	return force or DisplayServer.get_name() != "headless"


## Fonctions pures (testées) --------------------------------------------------------------------------------------------------------

## Triangle 0 → 1 → 0 de période 1 : va-et-vient sur un tronçon.
static func triangle(x: float) -> float:
	var f := fposmod(x, 1.0)
	return f * 2.0 if f < 0.5 else 2.0 - f * 2.0


## Point et direction (unitaire) à l'abscisse curviligne `s` d'une polyligne ; `s` est borné à [0, longueur].
static func sample(pts: PackedVector2Array, s: float) -> Array:
	var acc := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if seg < 1e-4:
			continue
		if acc + seg >= s or i == pts.size() - 2:
			var t := clampf((s - acc) / seg, 0.0, 1.0)
			return [pts[i].lerp(pts[i + 1], t), (pts[i + 1] - pts[i]) / seg]
		acc += seg
	return [pts[0], Vector2(1, 0)]


## Abscisse curviligne du point de la polyligne le plus proche de `p`, et sa distance.
static func nearest_s(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var acc := 0.0
	var best := Vector2(0.0, INF)
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 1e-4:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_to(p)
		if d < best.y:
			best = Vector2(acc + a.distance_to(q), d)
		acc += seg
	return best


## Mise en place ---------------------------------------------------------------------------------------------------------------------

func setup(p_world: Node, p_builder: CityBuilder) -> void:
	name = "VieAmbiante"
	world = p_world
	builder = p_builder
	_rng.seed = 20261121
	for r in builder.road_lines:
		if float(r.len) < 45.0:
			continue
		if str(r.kind) in KINDS_PED:
			_ped_roads.append(r)
		if str(r.kind) in KINDS_CAR and float(r.width) >= 4.0 and float(r.len) >= 70.0:
			_car_roads.append(r)
	enabled = bool(get_node("/root/Settings").ambient_life)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		clear()


func clear() -> void:
	for p in peds:
		if is_instance_valid(p.node):
			p.node.queue_free()
	for c in cars:
		if is_instance_valid(c.node):
			c.node.queue_free()
	peds.clear()
	cars.clear()


func _focus() -> Vector3:
	var pr = world.get("players_root")
	if pr:
		var me = pr.get_node_or_null(str(multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1))
		if me:
			return (me as Node3D).global_position
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam else Vector3.ZERO


## Le point (2D) est-il dans un bâtiment (ou à moins de `margin` m de ses murs) ?
func _blocked(p: Vector2, margin := 0.3) -> bool:
	for ring: PackedVector2Array in builder.building_rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
		if margin > 0.0:
			for i in ring.size():
				if Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()]).distance_to(p) < margin:
					return true
	return false


func _process(delta: float) -> void:
	if not enabled:
		return
	_tick += delta
	if _tick >= TICK:
		_tick = 0.0
		_maintain()
	_update_peds(delta)
	_update_cars(delta)


## Naissance / disparition autour du joueur -------------------------------------------------------------------------------------------

func _maintain() -> void:
	var f3 := _focus()
	var f := Vector2(f3.x, f3.z)
	for i in range(peds.size() - 1, -1, -1):
		var pos2 := _ped_pos(peds[i])
		if pos2.distance_to(f) > PED_OUT:
			peds[i].node.queue_free()
			peds.remove_at(i)
	for i in range(cars.size() - 1, -1, -1):
		var pos2: Vector2 = _car_pos(cars[i])[0]
		if pos2.distance_to(f) > CAR_OUT:
			cars[i].node.queue_free()
			cars.remove_at(i)
	var tries := 0
	while peds.size() < PED_MAX and tries < 6:
		tries += 1
		_spawn_ped(f)
	tries = 0
	while cars.size() < CAR_MAX and tries < 4:
		tries += 1
		_spawn_car(f)


## Route tirée au hasard dont un point est à [dmin, dmax] m du joueur ; renvoie [route, abscisse] ou [].
func _pick_road(roads: Array, f: Vector2, dmin: float, dmax: float) -> Array:
	var cand: Array = []
	for r in roads:
		var ns := nearest_s(r.pts, f)
		if ns.y > dmin and ns.y < dmax + 40.0:
			cand.append([r, ns.x])
	if cand.is_empty():
		return []
	return cand[_rng.randi() % cand.size()]


func _spawn_ped(f: Vector2) -> void:
	var pick := _pick_road(_ped_roads, f, PED_SPAWN_MIN, PED_SPAWN_MAX)
	if pick.is_empty():
		return
	var r: Dictionary = pick[0]
	var length := minf(_rng.randf_range(40.0, 95.0), float(r.len))
	var s0 := clampf(float(pick[1]) - length * 0.5, 0.0, float(r.len) - length)
	var ped := {"road": r, "s0": s0, "len": length, "side": 1.0 if _rng.randf() < 0.5 else -1.0, "speed": _rng.randf_range(1.0, 1.5),
		"phase": _rng.randf(), "t": 0.0, "node": null, "id": ped_serial}
	ped_serial += 1
	if _ped_pos(ped).distance_to(f) < PED_SPAWN_MIN:
		return
	# Tout le parcours doit être libre (aucun mur sur le trottoir) ; sinon on essaie l'autre côté de la rue.
	if not _path_free(ped):
		ped.side = -float(ped.side)
		if not _path_free(ped):
			return
	var style := {"hair": Color(_rng.randf_range(0.1, 0.8), _rng.randf_range(0.1, 0.6), _rng.randf_range(0.1, 0.5)), "hair_style": ["short", "bun", "long"][_rng.randi() % 3],
		"headgear": ["none", "none", "beret", "cap"][_rng.randi() % 4], "glasses": _rng.randf() < 0.2}
	var m := CharacterModel.make(SHIRTS[_rng.randi() % SHIRTS.size()], TROUSERS[_rng.randi() % TROUSERS.size()], SHIRTS[_rng.randi() % SHIRTS.size()].darkened(0.3), style)
	m.pose_override = {"speed": float(ped.speed)}
	m.name = "Passant%d" % ped.id
	add_child(m)
	ped.node = m
	peds.append(ped)
	_place_ped(ped)


func _path_free(p: Dictionary) -> bool:
	var save := float(p.t)
	var ok := true
	var steps := int(float(p.len) / 3.0) + 1
	for i in steps + 1:
		var s := float(p.s0) + float(p.len) * float(i) / float(steps)
		var sm := sample(p.road.pts, s)
		var q: Vector2 = (sm[0] as Vector2) + Vector2(-(sm[1] as Vector2).y, (sm[1] as Vector2).x) * float(p.side) * (float(p.road.width) * 0.5 + 0.6)
		if _blocked(q):
			ok = false
			break
	p.t = save
	return ok


func _ped_pos(p: Dictionary) -> Vector2:
	var u := triangle(float(p.phase) + float(p.t) * float(p.speed) / maxf(float(p.len), 1.0))
	var sm := sample(p.road.pts, float(p.s0) + u * float(p.len))
	var pos: Vector2 = sm[0]
	var dir: Vector2 = sm[1]
	return pos + Vector2(-dir.y, dir.x) * float(p.side) * (float(p.road.width) * 0.5 + 0.6)


func _place_ped(p: Dictionary) -> void:
	var u := triangle(float(p.phase) + float(p.t) * float(p.speed) / maxf(float(p.len), 1.0))
	var u2 := triangle(float(p.phase) + float(p.t) * float(p.speed) / maxf(float(p.len), 1.0) + 0.002)
	var sm := sample(p.road.pts, float(p.s0) + u * float(p.len))
	var dir: Vector2 = sm[1] * (1.0 if u2 >= u else -1.0)
	var pos := _ped_pos(p)
	var node: Node3D = p.node
	node.global_position = Vector3(pos.x, builder.height_at(pos.x, pos.y), pos.y)
	node.rotation.y = atan2(-dir.x, -dir.y)


func _update_peds(delta: float) -> void:
	for p in peds:
		p.t += delta
		_place_ped(p)


## Voitures ---------------------------------------------------------------------------------------------------------------------------

func _spawn_car(f: Vector2) -> void:
	var pick := _pick_road(_car_roads, f, CAR_SPAWN_MIN, CAR_SPAWN_MAX)
	if pick.is_empty():
		return
	var r: Dictionary = pick[0]
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	var car := {"road": r, "s": clampf(float(pick[1]), 6.0, float(r.len) - 6.0), "dir": dir, "speed": 0.0, "cruise": _rng.randf_range(5.0, 8.5),
		"node": null, "honk": 0.0, "level": 0.0}
	var posdir: Array = _car_pos(car)
	if (posdir[0] as Vector2).distance_to(f) < CAR_SPAWN_MIN:
		return
	for o in cars:        # pas deux voitures l'une sur l'autre
		if (_car_pos(o)[0] as Vector2).distance_to(posdir[0]) < 12.0:
			return
	for dd in [-1.0, 1.0]:                # la file de la voiture ne traverse aucun mur sur 30 m dans les deux sens
		for st in 11:
			var sm := sample(r.pts, clampf(float(car.s) + dd * float(st) * 3.0, 0.0, float(r.len)))
			var qq: Vector2 = (sm[0] as Vector2) + Vector2(-(sm[1] as Vector2).y, (sm[1] as Vector2).x) * float(dir) * float(r.width) * 0.25
			if _blocked(qq, 0.0):
				return
	var kind := _rng.randi() % 3
	var k := PropKit.traffic_car(CAR_COLORS[_rng.randi() % CAR_COLORS.size()], kind)
	var holder := Node3D.new()
	holder.name = "Voiture%d" % ped_serial
	ped_serial += 1
	var body := k.build()
	body.rotation.y = PI                      # le gabarit a l'avant en +Z ; ici l'avant est -Z comme les véhicules du jeu
	holder.add_child(body)
	ExhaustFx.attach(holder, Vector3(0.55, 0.3, 2.1), Vector3(0, 0.25, 1))
	add_child(holder)
	car.node = holder
	cars.append(car)
	_place_car(car)


## [position 2D, direction de marche 2D] d'une voiture (décalée dans sa file, à droite de son sens de marche).
func _car_pos(c: Dictionary) -> Array:
	var sm := sample(c.road.pts, float(c.s))
	var dir: Vector2 = (sm[1] as Vector2) * float(c.dir)
	var right := Vector2(-dir.y, dir.x)
	return [(sm[0] as Vector2) + right * float(c.road.width) * 0.25, dir]


func _place_car(c: Dictionary) -> void:
	var pd := _car_pos(c)
	var pos: Vector2 = pd[0]
	var dir: Vector2 = pd[1]
	var node: Node3D = c.node
	node.global_position = Vector3(pos.x, builder.height_at(pos.x, pos.y), pos.y)
	node.rotation.y = atan2(-dir.x, -dir.y)


## Points (2D) devant lesquels une voiture doit s'arrêter : joueurs, camionnette, autres voitures.
func _obstacles(except: Dictionary) -> Array:
	var out: Array = []
	var pr = world.get("players_root")
	if pr:
		for p in pr.get_children():
			if p is Node3D and (p as Node3D).global_position.y > -400.0:
				out.append(Vector3((p as Node3D).global_position.x, 0.0, (p as Node3D).global_position.z))
	var van = world.get("van")
	if van != null and is_instance_valid(van):
		out.append(Vector3(van.global_position.x, 1.0, van.global_position.z))
	for o in cars:
		if o != except:
			var q: Vector2 = _car_pos(o)[0]
			out.append(Vector3(q.x, 2.0, q.y))
	return out


func _update_cars(delta: float) -> void:
	for c in cars:
		var pd := _car_pos(c)
		var pos: Vector2 = pd[0]
		var dir: Vector2 = pd[1]
		var right := Vector2(-dir.y, dir.x)
		var blocked_by := -1
		var gap := 99.0
		for o: Vector3 in _obstacles(c):
			var rel := Vector2(o.x, o.z) - pos
			var ahead := rel.dot(dir)
			if ahead > 0.5 and ahead < 11.0 and absf(rel.dot(right)) < 2.3 and ahead < gap:
				gap = ahead
				blocked_by = int(o.y)
		var target := float(c.cruise)
		if blocked_by >= 0:
			target = 0.0 if gap < 10.0 else float(c.cruise) * 0.4
		var len := float(c.road.len)
		var to_end := (len - float(c.s)) if float(c.dir) > 0.0 else float(c.s)
		if to_end < 14.0:
			target = minf(target, 2.5)
		var rate := 3.0 if target > float(c.speed) else 10.0
		c.speed = move_toward(float(c.speed), target, rate * delta)
		c.s = float(c.s) + float(c.dir) * float(c.speed) * delta
		if float(c.s) <= 1.0 or float(c.s) >= len - 1.0:
			c.dir = -float(c.dir)            # demi-tour au bout de la route (l'autre file)
			c.s = clampf(float(c.s), 1.5, len - 1.5)
		c.honk = maxf(float(c.honk) - delta, 0.0)
		if blocked_by == 0 and float(c.speed) < 0.3 and gap < 7.0 and float(c.honk) <= 0.0:
			c.honk = 14.0
			var sfx = get_node_or_null("/root/Sfx")
			if sfx:
				sfx.play_at("honk", (c.node as Node3D).global_position, -2.0)
		_place_car(c)
		for ch in (c.node as Node3D).get_children():
			if ch is ExhaustFx:
				(ch as ExhaustFx).set_level(0.15 + 0.85 * clampf(float(c.speed) / 8.0, 0.0, 1.0))
