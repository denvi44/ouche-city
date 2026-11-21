class_name RoadNav
extends RefCounted
## Navigation des piétons sur le graphe routier du cartographe (agent 06).
## Chaque sommet de polyligne des arêtes de `road_graph.json` devient un point d'un AStar2D ;
## le chemin suit donc les rues, les trottoirs et les sentiers, et pas les bâtiments.
## Repère : x est, z sud (le Vector2 porte (x, z)).

const GRAPH_PATH := "res://assets/city/road_graph.json"
const KEY_SCALE := 2.0              # fusion des points à 0,5 m
const MAX_STEP := 5.0               # une arête est densifiée : jamais plus de 5 m entre deux points

var astar := AStar2D.new()
var _ids := {}


## `vehicles` : ne garde que les routes carrossables (ni sentiers, ni escaliers, ni voies piétonnes).
static func load_default(vehicles := false) -> RoadNav:
	var nav := RoadNav.new()
	var data = CityBuilder.read_json(GRAPH_PATH)
	if data is Dictionary:
		nav.build(data.get("edges", []), ["primary", "secondary", "tertiary", "residential", "service"] if vehicles else [])
		if not vehicles:
			nav.block_buildings(footprints())
	return nav


## Contours de tous les bâtiments de la zone (PackedVector2Array).
static func footprints() -> Array:
	var out := []
	for key in CityBuilder.load_manifest().get("tiles", []):
		var tile = CityBuilder.read_json("res://assets/city/tiles/%s.json" % key)
		if tile is Dictionary:
			for b in tile.get("buildings", []):
				var ring := PackedVector2Array()
				for v in b.footprint:
					ring.append(Vector2(float(v[0]), float(v[1])))
				out.append(ring)
	return out


## Désactive les points du graphe situés dans un bâtiment : certaines rues (passages sous porche) traversent un
## contour que les collisions rendent infranchissable, et les piétons s'y bloquaient.
func block_buildings(rings: Array) -> int:
	var grid := {}
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
				if not grid.has(key):
					grid[key] = []
				grid[key].append(r)
	var blocked := 0
	for id in astar.get_point_ids():
		var p := astar.get_point_position(id)
		for r in grid.get(Vector2i(int(floor(p.x / 40.0)), int(floor(p.y / 40.0))), []):
			if Geometry2D.is_point_in_polygon(p, r):
				astar.set_point_disabled(id, true)
				blocked += 1
				break
	return blocked


func build(edges: Array, kinds: Array = []) -> void:
	for e in edges:
		if not kinds.is_empty() and not (e.get("kind", "") in kinds):
			continue
		var prev := -1
		var last := Vector2.ZERO
		for i in e.points.size():
			var v := Vector2(float(e.points[i][0]), float(e.points[i][1]))
			var steps := 1
			if i > 0:
				steps = maxi(int(ceil(last.distance_to(v) / MAX_STEP)), 1)
			for k in range(1 if i > 0 else 0, steps + 1):
				var id := _id_for(last.lerp(v, float(k) / float(steps)) if i > 0 else v)
				if prev >= 0 and prev != id and not astar.are_points_connected(prev, id):
					astar.connect_points(prev, id, true)
				prev = id
			last = v


func _id_for(v: Vector2) -> int:
	var key := Vector2i(roundi(v.x * KEY_SCALE), roundi(v.y * KEY_SCALE))
	if not _ids.has(key):
		var id := astar.get_available_point_id()
		astar.add_point(id, v)
		_ids[key] = id
	return _ids[key]


func point_count() -> int:
	return astar.get_point_count()


## Chemin de `from` à `to` : départ, points du graphe, arrivée. Sans graphe ou sans lien : ligne droite.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array([from])
	if astar.get_point_count() > 0:
		var a := astar.get_closest_point(from)
		var b := astar.get_closest_point(to)
		if a >= 0 and b >= 0:
			var mid := astar.get_point_path(a, b)
			for p in mid:
				out.append(p)
	out.append(to)
	return out


## Sommet du graphe le plus proche de `p` (sortie d'un angle de mur) ; `p` si le graphe est vide.
func closest_vertex(p: Vector2) -> Vector2:
	if astar.get_point_count() == 0:
		return p
	return astar.get_point_position(astar.get_closest_point(p))


static func length_of(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total
