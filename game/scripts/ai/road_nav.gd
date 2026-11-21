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
	return nav


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


static func length_of(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(path.size() - 1):
		total += path[i].distance_to(path[i + 1])
	return total
