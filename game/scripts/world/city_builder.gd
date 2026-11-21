class_name CityBuilder
extends RefCounted
## Construit la ville dans Godot à partir des tuiles du cartographe (contracts/tile.schema.json v1),
## sans aucune retouche manuelle : murs extrudés, toits à deux pans, routes, trottoirs, végétation.
## Repère : x vers l'est, z vers le sud, y vers le haut, en mètres.

const CITY_DIR := "res://assets/city"
const MAT_DIR := "res://assets/materials/"

const Y_VEGETATION := 0.03
const Y_TROTTOIR := 0.07
const Y_ROUTE := 0.1

## Matériaux de murs : façades peintes (fenêtres, volets, portes) sauf les annexes (remises, garages).
const WALL_MAT := {
	"colombages": "colombages", "brique": "facade_brique", "pavillon": "facade_crepi",
	"commerce": "facade_commerce", "public": "facade_pierre_public", "eglise": "facade_pierre_eglise", "annexe": "crepi_pavillon",
}
const VEG_MAT := {
	"grass": "vert_bocage", "park": "parc", "garden": "parc", "forest": "foret", "farmland": "champ", "water": "eau",
}
const SURFACE_MAT := {"asphalt": "route", "pavers": "paves", "gravel": "gravier", "grass": "vert_bocage"}

var _materials := {}
var _tools := {}   # nom de matériau -> SurfaceTool
## Couleur de sommet appliquée aux triangles émis (données de façade : voir facade_details.gdshaderinc).
var _cur_color := Color.WHITE
## Polylignes des routes de la tuile en cours : sert à choisir le mur de la porte (côté rue).
var _tile_roads: Array = []
var _collect_hull := false
var _hull_tris: Array = []   # triangles du bâti en cours : [a, b, c] (Vector3) pour le contour
## Grilles de relief des tuiles chargées : "x_y" -> { origin, size, res, heights }
var grids := {}
var bounds := Rect2()   # emprise couverte par les tuiles (repère local x, z)


static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Impossible d'ouvrir %s" % path)
		return null
	return JSON.parse_string(f.get_as_text())


static func load_manifest(dir: String = CITY_DIR) -> Dictionary:
	var m = read_json(dir.path_join("manifest.json"))
	return m if m is Dictionary else {}


## Enregistre la grille de relief d'une tuile (à faire pour toutes les tuiles avant de construire).
func register_tile(data: Dictionary) -> void:
	var size := float(data.size)
	var origin := Vector2(float(data.origin[0]), float(data.origin[1]))
	var g: Dictionary = data.get("ground", {})
	var res := int(g.get("resolution", 2))
	var heights: Array = g.get("heights", [0.0, 0.0, 0.0, 0.0])
	grids["%d_%d" % [int(data.tile.x), int(data.tile.y)]] = {"origin": origin, "size": size, "res": res, "heights": heights}
	var r := Rect2(origin, Vector2(size, size))
	bounds = r if bounds.size == Vector2.ZERO else bounds.merge(r)


## Hauteur du sol (m, relative à l'altitude de référence) en tout point.
## Hors des tuiles, le relief du bord le plus proche est prolongé.
func height_at(x: float, z: float) -> float:
	if grids.is_empty():
		return 0.0
	var p := Vector2(clampf(x, bounds.position.x, bounds.end.x - 0.001), clampf(z, bounds.position.y, bounds.end.y - 0.001))
	var any_g: Dictionary = grids.values()[0]
	var size: float = any_g.size
	var key := "%d_%d" % [int(floor(p.x / size)), int(floor(p.y / size))]
	if not grids.has(key):
		return 0.0
	var g: Dictionary = grids[key]
	var res: int = g.res
	var step: float = size / (res - 1)
	var gx := clampf((p.x - g.origin.x) / step, 0.0, res - 1.001)
	var gz := clampf((p.y - g.origin.y) / step, 0.0, res - 1.001)
	var i := int(gx)
	var j := int(gz)
	var fx := gx - i
	var fz := gz - j
	var hs: Array = g.heights
	var top := lerpf(float(hs[j * res + i]), float(hs[j * res + i + 1]), fx)
	var bot := lerpf(float(hs[(j + 1) * res + i]), float(hs[(j + 1) * res + i + 1]), fx)
	return lerpf(top, bot, fz)


## Maillage de sol en grille régulière (tuile ou « tablier » autour de la ville).
func add_ground_grid(origin: Vector2, size: Vector2, step: float, mat: String, skip: Rect2 = Rect2()) -> void:
	var st := _tool(mat)
	var nx := int(ceil(size.x / step))
	var nz := int(ceil(size.y / step))
	for j in nz:
		for i in nx:
			var a := origin + Vector2(i * step, j * step)
			var c := a + Vector2(step, step)
			if skip.size != Vector2.ZERO and skip.encloses(Rect2(a, Vector2(step, step))):
				continue
			var p00 := Vector3(a.x, height_at(a.x, a.y), a.y)
			var p10 := Vector3(c.x, height_at(c.x, a.y), a.y)
			var p11 := Vector3(c.x, height_at(c.x, c.y), c.y)
			var p01 := Vector3(a.x, height_at(a.x, c.y), c.y)
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.y < 0.0:
					n = -n
				_tri(st, tri[0], tri[1], tri[2], n, Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z))


func material(name: String) -> Material:
	if not _materials.has(name):
		_materials[name] = load(MAT_DIR + name + ".tres")
	return _materials[name]


func _tool(mat: String) -> SurfaceTool:
	if not _tools.has(mat):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[mat] = st
	return _tools[mat]


## Ajoute un triangle en garantissant que sa face avant regarde du côté de `n`
## (Godot : faces avant dans le sens horaire).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b; b = c; c = t
		var tu := ub; ub = uc; uc = tu
	if _collect_hull:
		_hull_tris.append([a, b, c])
	st.set_color(_cur_color); st.set_normal(n); st.set_uv(ua); st.add_vertex(a)
	st.set_color(_cur_color); st.set_normal(n); st.set_uv(ub); st.add_vertex(b)
	st.set_color(_cur_color); st.set_normal(n); st.set_uv(uc); st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, n, ua, ub, uc)
	_tri(st, a, c, d, n, ua, uc, ud)


static func to_ring(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in arr:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func signed_area(ring: PackedVector2Array) -> float:
	var s := 0.0
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func _hash01(s: String) -> float:
	return float(s.hash() & 0xFFFF) / 65536.0


## Indice de l'arête de `ring` qui porte la porte : la plus proche d'une rue, d'au moins 2,6 m.
func _door_edge(ring: PackedVector2Array, typo: String) -> int:
	if typo == "annexe":
		return -1
	var best := -1
	var best_d := INF
	for i in ring.size():
		var a := ring[i]
		var c := ring[(i + 1) % ring.size()]
		if a.distance_to(c) < 2.6:
			continue
		var mid := (a + c) * 0.5
		var d := INF
		for road in _tile_roads:
			for k in range(road.size() - 1):
				d = minf(d, seg_distance(mid, road[k], road[k + 1]))
		if d < best_d:
			best_d = d
			best = i
	return best


static func seg_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Modèle de toit à deux pans : faîtage parallèle au plus long côté.
## Renvoie { c, n, o, half, k } pour h(p) = hauteur + k * (half - |(p - c)·n - o|).
static func ridge_model(ring: PackedVector2Array, wall_h: float, roof: String) -> Dictionary:
	var best := 0.0
	var axis := Vector2.RIGHT
	for i in ring.size():
		var e := ring[(i + 1) % ring.size()] - ring[i]
		if e.length() > best:
			best = e.length()
			axis = e.normalized()
	var c := Vector2.ZERO
	for p in ring:
		c += p
	c /= ring.size()
	var n := Vector2(-axis.y, axis.x)
	var lo := INF
	var hi := -INF
	for p in ring:
		var s := (p - c).dot(n)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	var half := maxf((hi - lo) * 0.5, 0.01)
	var rise := 0.0
	if roof in ["gabled", "hipped", "spire"]:
		# Pente normande raide (~50°), plafonnée pour les grands volumes.
		rise = minf(half * 1.2, 7.0)
	return {"c": c, "n": n, "o": (lo + hi) * 0.5, "half": half, "k": rise / half, "h": wall_h, "axis": axis}


static func roof_height(m: Dictionary, p: Vector2) -> float:
	var s: float = (p - m.c).dot(m.n) - m.o
	return m.h + m.k * maxf(m.half - absf(s), 0.0)


static func _side(m: Dictionary, p: Vector2) -> float:
	return (p - m.c).dot(m.n) - m.o


## Insère dans l'anneau les points où il croise la ligne de faîtage.
static func split_ring_at_ridge(ring: PackedVector2Array, m: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		out.append(a)
		var sa := _side(m, a)
		var sb := _side(m, b)
		if sa * sb < 0.0:
			out.append(a + (b - a) * (sa / (sa - sb)))
	return out


func add_building(b: Dictionary) -> void:
	var ring := to_ring(b.footprint)
	if ring.size() < 3:
		return
	var h := float(b.height)
	var typo: String = b.get("typology", "brique")
	var roof: String = b.get("roof", "gabled")
	var ground := float(b.get("groundZ", 0.0))
	var m := ridge_model(ring, h, roof)
	var full := split_ring_at_ridge(ring, m) if m.k > 0.0 else ring
	var ccw_xz := signed_area(full) > 0.0
	var wall := _tool(WALL_MAT.get(typo, "facade_brique"))
	var seed := _hash01(str(b.id))
	var door_edge := _door_edge(full, typo)
	var has_details := typo != "annexe"
	for i in full.size():
		var a := full[i]
		var c := full[(i + 1) % full.size()]
		var d := c - a
		var seg_l := d.length()
		if seg_l < 0.01:
			continue
		var n2 := Vector2(d.y, -d.x) / seg_l if ccw_xz else Vector2(-d.y, d.x) / seg_l
		var n := Vector3(n2.x, 0.0, n2.y)
		var ha := roof_height(m, a)
		var hc := roof_height(m, c)
		# Données de façade : graine, longueur, porte (0 / 0,5 / 1 avec vitrine), hauteur d'égout.
		var door_flag := 0.0
		if i == door_edge:
			door_flag = 1.0 if typo == "commerce" else 0.5
		_cur_color = Color(seed, minf(seg_l / 100.0, 1.0), door_flag, minf(h / 40.0, 1.0)) if has_details else Color(seed, 0.0, 0.0, 0.0)
		_quad(wall,
			Vector3(a.x, ground, a.y), Vector3(c.x, ground, c.y),
			Vector3(c.x, ground + hc, c.y), Vector3(a.x, ground + ha, a.y), n,
			Vector2(0, 0), Vector2(seg_l, 0), Vector2(seg_l, hc), Vector2(0, ha))
		_cur_color = Color.WHITE
	# Toit
	var roof_mat := "ardoise"
	if typo in ["brique", "annexe"] or (typo in ["colombages", "pavillon"] and _hash01(b.id) < 0.45):
		roof_mat = "tuile"
	var st := _tool(roof_mat)
	if m.k <= 0.0:
		_add_polygon(st, full, func(_p): return ground + h, Vector3.UP)
	else:
		for side in [1.0, -1.0]:
			var half_poly := PackedVector2Array()
			for p in full:
				if _side(m, p) * side >= -0.001:
					half_poly.append(p)
			if half_poly.size() >= 3:
				_add_polygon(st, half_poly, func(p): return ground + roof_height(m, p), Vector3.ZERO)
	if typo == "eglise":
		_add_church_tower(ring, m, h, ground)


## Triangule un polygone horizontal ou incliné ; `up` nul = normale calculée par triangle, orientée vers le haut.
func _add_polygon(st: SurfaceTool, poly: PackedVector2Array, height: Callable, up: Vector3) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		idx = Geometry2D.triangulate_delaunay(poly)
	for t in range(0, idx.size() - 2, 3):
		var p0 := poly[idx[t]]
		var p1 := poly[idx[t + 1]]
		var p2 := poly[idx[t + 2]]
		var a := Vector3(p0.x, height.call(p0), p0.y)
		var b := Vector3(p1.x, height.call(p1), p1.y)
		var c := Vector3(p2.x, height.call(p2), p2.y)
		var n := up
		if n == Vector3.ZERO:
			n = (b - a).cross(c - a).normalized()
			if n.y < 0.0:
				n = -n
			if n == Vector3.ZERO:
				continue
		_tri(st, a, b, c, n, p0, p1, p2)


## Clocher carré surmonté d'une flèche, à l'extrémité ouest du faîtage.
func _add_church_tower(ring: PackedVector2Array, m: Dictionary, h: float, ground: float) -> void:
	var axis: Vector2 = m.axis
	if axis.x > 0.0:
		axis = -axis
	var far := -INF
	for p in ring:
		far = maxf(far, (p - m.c).dot(axis))
	var center: Vector2 = m.c + axis * (far - 3.5) + m.n * m.o
	var s := 3.0
	var top := h + 12.0
	var corners := [center + Vector2(-s, -s), center + Vector2(s, -s), center + Vector2(s, s), center + Vector2(-s, s)]
	var wall := _tool(WALL_MAT["eglise"])
	_cur_color = Color(0.0, 0.0, 0.0, 0.0)      # le clocher : mur nu, sans fenêtres ni porte
	for i in 4:
		var a: Vector2 = corners[i]
		var c: Vector2 = corners[(i + 1) % 4]
		var mid := (a + c) * 0.5 - center
		var n := Vector3(mid.x, 0, mid.y).normalized()
		_quad(wall, Vector3(a.x, ground, a.y), Vector3(c.x, ground, c.y), Vector3(c.x, ground + top, c.y), Vector3(a.x, ground + top, a.y),
			n, Vector2(0, 0), Vector2(2 * s, 0), Vector2(2 * s, top), Vector2(0, top))
	_cur_color = Color.WHITE
	var spire := _tool("ardoise")
	var apex := Vector3(center.x, ground + top + 13.0, center.y)
	for i in 4:
		var a: Vector2 = corners[i]
		var c: Vector2 = corners[(i + 1) % 4]
		var va := Vector3(a.x, ground + top, a.y)
		var vc := Vector3(c.x, ground + top, c.y)
		var n := (vc - va).cross(apex - va).normalized()
		var mid := (a + c) * 0.5 - center
		if n.dot(Vector3(mid.x, 0, mid.y)) < 0.0:
			n = -n
		_tri(spire, va, vc, apex, n, a, c, center)


## Ruban le long d'une polyligne (routes, trottoirs).
func add_ribbon(points: PackedVector2Array, width: float, y: float, mat: String) -> void:
	if points.size() < 2:
		return
	var st := _tool(mat)
	var half := width * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in points.size():
		var dir := Vector2.ZERO
		if i > 0:
			dir += (points[i] - points[i - 1]).normalized()
		if i < points.size() - 1:
			dir += (points[i + 1] - points[i]).normalized()
		dir = dir.normalized()
		var perp := Vector2(-dir.y, dir.x)
		# Onglet limité pour éviter les pointes dans les virages serrés.
		var scale := 1.0
		if i > 0 and i < points.size() - 1:
			var seg := (points[i] - points[i - 1]).normalized()
			scale = clampf(1.0 / maxf(absf(perp.dot(Vector2(-seg.y, seg.x))), 0.01), 1.0, 2.0)
		left.append(points[i] + perp * half * scale)
		right.append(points[i] - perp * half * scale)
	var v := 0.0
	for i in points.size() - 1:
		var seg_len := points[i].distance_to(points[i + 1])
		var l0 := Vector3(left[i].x, height_at(left[i].x, left[i].y) + y, left[i].y)
		var r0 := Vector3(right[i].x, height_at(right[i].x, right[i].y) + y, right[i].y)
		var r1 := Vector3(right[i + 1].x, height_at(right[i + 1].x, right[i + 1].y) + y, right[i + 1].y)
		var l1 := Vector3(left[i + 1].x, height_at(left[i + 1].x, left[i + 1].y) + y, left[i + 1].y)
		_quad(st, l0, r0, r1, l1, Vector3.UP,
			Vector2(0, v), Vector2(width, v), Vector2(width, v + seg_len), Vector2(0, v + seg_len))
		v += seg_len
	# Pastilles aux extrémités pour masquer les jonctions.
	for p in [points[0], points[points.size() - 1]]:
		_add_disc(st, p, half, y)


func _add_disc(st: SurfaceTool, c: Vector2, r: float, y: float, segments: int = 10) -> void:
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		_tri(st, Vector3(c.x, height_at(c.x, c.y) + y, c.y), Vector3(p0.x, height_at(p0.x, p0.y) + y, p0.y),
			Vector3(p1.x, height_at(p1.x, p1.y) + y, p1.y), Vector3.UP, c, p0, p1)


func add_road(r: Dictionary) -> void:
	var pts := to_ring(r.points)
	var w := float(r.width)
	var sw := float(r.get("sidewalk", 0.0))
	if sw > 0.0:
		add_ribbon(pts, w + 2.0 * sw, Y_TROTTOIR, "trottoir")
	var mat: String = SURFACE_MAT.get(r.get("surface", "asphalt"), "route")
	if r.kind in ["footway", "pedestrian"] and mat == "route":
		mat = "paves"
	add_ribbon(pts, w, Y_ROUTE, mat)


func add_vegetation(v: Dictionary) -> void:
	var poly := to_ring(v.polygon)
	_add_polygon(_tool(VEG_MAT.get(v.kind, "vert_bocage")), poly, func(p): return height_at(p.x, p.y) + Y_VEGETATION, Vector3.ZERO)


## Construit une tuile : un MeshInstance3D par tuile (une surface par matériau),
## un StaticBody3D de collision pour les bâtiments, des arbres en MultiMesh.
func build_tile(data: Dictionary) -> Node3D:
	_tools.clear()
	var root := Node3D.new()
	root.name = "Tuile_%d_%d" % [int(data.tile.x), int(data.tile.y)]
	if not grids.has("%d_%d" % [int(data.tile.x), int(data.tile.y)]):
		register_tile(data)
	var body := StaticBody3D.new()
	body.name = "Collisions"
	root.add_child(body)
	_tile_roads.clear()
	for r in data.roads:
		if r.kind not in ["footway", "track"]:
			_tile_roads.append(to_ring(r.points))
	_collect_hull = true
	_hull_tris.clear()
	for b in data.buildings:
		add_building(b)
	_collect_hull = false
	var hull_mesh := _build_hull(_hull_tris)
	_hull_tris.clear()
	var buildings_mesh := _commit()
	if buildings_mesh.get_surface_count() > 0:
		var mi := MeshInstance3D.new()
		mi.name = "Batiments"
		mi.mesh = buildings_mesh
		root.add_child(mi)
		_add_collision(body, buildings_mesh)
		var hi := MeshInstance3D.new()
		hi.name = "Contours"
		hi.mesh = hull_mesh
		hi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(hi)
	var size := float(data.size)
	add_ground_grid(Vector2(float(data.origin[0]), float(data.origin[1])), Vector2(size, size), size / 20.0, "sol")
	var terrain := _commit()
	var ti := MeshInstance3D.new()
	ti.name = "Terrain"
	ti.mesh = terrain
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ti)
	_add_collision(body, terrain)
	for v in data.vegetation:
		add_vegetation(v)
	for r in data.roads:
		add_road(r)
	var ground_mesh := _commit()
	if ground_mesh.get_surface_count() > 0:
		var gi := MeshInstance3D.new()
		gi.name = "Sol"
		gi.mesh = ground_mesh
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(gi)
	if data.get("trees", []).size() > 0:
		root.add_child(_build_trees(data.trees))
	return root


func _build_hull(tris: Array) -> ArrayMesh:
	return HullOutline.build(tris)


func _add_collision(body: StaticBody3D, mesh: ArrayMesh) -> void:
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)


## Tablier de terrain autour de la ville (relief du bord prolongé), avec collisions.
func build_apron(margin: float = 400.0, step: float = 25.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Tablier"
	var origin := bounds.position - Vector2(margin, margin)
	add_ground_grid(origin, bounds.size + Vector2(margin, margin) * 2.0, step, "sol", bounds)
	var mesh := _commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var body := StaticBody3D.new()
	_add_collision(body, mesh)
	root.add_child(body)
	return root


func _commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys := _tools.keys()
	keys.sort()
	for k in keys:
		var st: SurfaceTool = _tools[k]
		st.set_material(material(k))
		st.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, k)
	_tools.clear()
	return mesh


func _build_trees(points: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Arbres"
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18; trunk.bottom_radius = 0.25; trunk.height = 2.6; trunk.radial_segments = 6; trunk.rings = 1
	trunk.material = material("tronc")
	var crown := SphereMesh.new()
	crown.radius = 2.2; crown.height = 3.8; crown.radial_segments = 8; crown.rings = 4
	crown.material = material("feuillage")
	for spec in [[trunk, 1.3], [crown, 4.2]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[0]
		mm.instance_count = points.size()
		for i in points.size():
			var p: Array = points[i]
			var s := 0.8 + _hash01("%s_%s" % [p[0], p[1]]) * 0.5
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(p[0], height_at(p[0], p[1]) + spec[1] * s, p[1])))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)
	return root


## Enseignes des lieux fictifs (POI v2 portant `building` et `facing`) : panneau crème bordé
## de bois, posé sur la façade côté rue, à 3 m du sol.
func build_signs(pois: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Enseignes"
	var board_mat := ShaderMaterial.new()
	board_mat.shader = preload("res://shaders/toon.gdshader")
	board_mat.set_shader_parameter("couleur", Color(0.96, 0.91, 0.78))
	for p in pois:
		if not p.has("building") or not p.has("facing"):
			continue
		var label_text: String = p.label
		var x := float(p.position[0])
		var z := float(p.position[1])
		var sign := Node3D.new()
		sign.name = "Enseigne_" + str(p.id)
		sign.position = Vector3(x, height_at(x, z) + 3.0, z)
		sign.rotation.y = float(p.facing)
		var width := clampf(label_text.length() * 0.16 + 0.4, 1.4, 5.5)
		var frame := BoxMesh.new()
		frame.size = Vector3(width + 0.12, 0.62, 0.06)
		frame.material = material("tronc")
		var fi := MeshInstance3D.new()
		fi.mesh = frame
		sign.add_child(fi)
		var board := BoxMesh.new()
		board.size = Vector3(width, 0.5, 0.08)
		board.material = board_mat
		var bi := MeshInstance3D.new()
		bi.mesh = board
		bi.position.z = 0.01
		sign.add_child(bi)
		var label := Label3D.new()
		label.text = label_text
		label.font_size = 64
		label.pixel_size = 0.0045
		label.modulate = Color(0.27, 0.18, 0.12)
		label.outline_size = 0
		label.position.z = 0.06
		label.width = width / label.pixel_size
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		if label_text.length() * 0.16 + 0.4 > width:
			label.pixel_size = 0.0045 * width / (label_text.length() * 0.16 + 0.4)
		sign.add_child(label)
		root.add_child(sign)
	return root


## Blockout des lieux de mission (POI v3 portant `step`) : balise lumineuse, libellé,
## et accessoire simple (`prop`). Aplats toon, aucun asset externe.
const STEP_COLOR := {"crates": Color(0.95, 0.75, 0.2), "vehicle": Color(0.3, 0.6, 0.9), "checkpoint": Color(0.85, 0.25, 0.2), "fair": Color(0.4, 0.75, 0.35),
	"parts": Color(0.95, 0.75, 0.2), "assembly": Color(0.7, 0.5, 0.9), "test_drive": Color(0.3, 0.6, 0.9), "meet": Color(0.95, 0.5, 0.7), "drag": Color(0.85, 0.25, 0.2)}


func _toon(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/toon.gdshader")
	m.set_shader_parameter("couleur", color)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot_y: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _toon(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)
	return mi


func _add_prop(root: Node3D, prop: String) -> void:
	match prop:
		"van":
			_box(root, Vector3(2.0, 1.5, 4.6), Vector3(0, 1.0, 0), Color(0.93, 0.9, 0.82))
			_box(root, Vector3(1.9, 0.9, 1.5), Vector3(0, 1.0, -1.7), Color(0.55, 0.7, 0.85))
			for sx in [-1.0, 1.0]:
				for sz in [-1.4, 1.5]:
					var w := CylinderMesh.new()
					w.top_radius = 0.38; w.bottom_radius = 0.38; w.height = 0.3
					w.material = _toon(Color(0.15, 0.13, 0.12))
					var wi := MeshInstance3D.new()
					wi.mesh = w
					wi.rotation.z = PI / 2.0
					wi.position = Vector3(sx * 1.0, 0.38, sz)
					root.add_child(wi)
		"barrier":
			# Barrage de gendarmerie : deux plots rayés et une barre en travers de la route.
			for sx in [-3.0, 3.0]:
				_box(root, Vector3(0.3, 1.1, 0.3), Vector3(sx, 0.55, 0), Color(0.95, 0.95, 0.95))
				_box(root, Vector3(0.32, 0.3, 0.32), Vector3(sx, 0.9, 0), Color(0.85, 0.2, 0.18))
			_box(root, Vector3(6.2, 0.25, 0.12), Vector3(0, 1.0, 0), Color(0.85, 0.2, 0.18)).name = "Barre"
			_box(root, Vector3(1.0, 0.25, 0.14), Vector3(-1.5, 1.0, 0), Color(0.97, 0.97, 0.97))
			_box(root, Vector3(1.0, 0.25, 0.14), Vector3(1.5, 1.0, 0), Color(0.97, 0.97, 0.97))
			# Collision réelle : la camionnette doit s'arrêter (ou casser des bouteilles).
			var body := StaticBody3D.new()
			body.name = "Collision"
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(6.4, 1.4, 0.5)
			shape.shape = box
			shape.position.y = 0.7
			body.add_child(shape)
			root.add_child(body)
		"stand":
			# Stand de foire : comptoir, quatre poteaux, toit rayé.
			_box(root, Vector3(3.6, 1.0, 1.2), Vector3(0, 0.5, 0), Color(0.62, 0.42, 0.28))
			for sx in [-1.7, 1.7]:
				_box(root, Vector3(0.12, 2.6, 0.12), Vector3(sx, 1.3, -0.5), Color(0.38, 0.26, 0.18))
				_box(root, Vector3(0.12, 2.6, 0.12), Vector3(sx, 1.3, 0.5), Color(0.38, 0.26, 0.18))
			for i in 6:
				_box(root, Vector3(0.62, 0.1, 1.5), Vector3(-1.55 + i * 0.62, 2.65, 0), Color(0.85, 0.22, 0.2) if i % 2 == 0 else Color(0.97, 0.95, 0.88))
		"strip":
			_add_strip(root)
		"junkyard":
			# Tas de ferraille : carcasses rouillées, pneus, une porte de frigo.
			for spec in [[Vector3(3.2, 1.0, 1.8), Vector3(-2.5, 0.5, 1.5), Color(0.55, 0.3, 0.2), 0.3], [Vector3(2.6, 0.8, 1.6), Vector3(2.8, 0.4, 2.8), Color(0.45, 0.5, 0.55), -0.5],
					[Vector3(1.8, 1.6, 0.4), Vector3(0.0, 0.8, 4.0), Color(0.85, 0.85, 0.82), 0.1], [Vector3(2.0, 0.6, 2.0), Vector3(-1.0, 1.3, 1.8), Color(0.4, 0.28, 0.2), 0.8]]:
				_box(root, spec[0], spec[1], spec[2], spec[3])
			for k in 4:
				var tire := CylinderMesh.new()
				tire.top_radius = 0.45
				tire.bottom_radius = 0.45
				tire.height = 0.3
				tire.material = _toon(Color(0.12, 0.11, 0.1))
				var ti := MeshInstance3D.new()
				ti.mesh = tire
				ti.position = Vector3(4.5 + (k % 2) * 0.9, 0.15 + (k / 2) * 0.32, 0.8 + (k % 2) * 0.4)
				root.add_child(ti)
		"garage":
			# Pile de pneus et caisse à outils devant le garage de Kévin.
			for k in 3:
				var tire := CylinderMesh.new()
				tire.top_radius = 0.42
				tire.bottom_radius = 0.42
				tire.height = 0.28
				tire.material = _toon(Color(0.12, 0.11, 0.1))
				var ti := MeshInstance3D.new()
				ti.mesh = tire
				ti.position = Vector3(2.4, 0.14 + k * 0.3, 1.0)
				root.add_child(ti)
			_box(root, Vector3(0.9, 0.6, 0.5), Vector3(3.5, 0.3, 1.4), Color(0.75, 0.2, 0.18))
		"fumier":
			var heap := SphereMesh.new()
			heap.radius = 1.6; heap.height = 1.8; heap.radial_segments = 8; heap.rings = 4
			heap.material = _toon(Color(0.4, 0.3, 0.18))
			var hi := MeshInstance3D.new()
			hi.mesh = heap
			hi.position.y = 0.2
			root.add_child(hi)


## Piste de drag : bitume de 14 m de large sur 400 m (axe +Z local), bandes latérales, lignes de
## départ et d'arrivée en damier. Le dessus s'aligne sur le point le plus haut du terrain (≤ 0,5 m d'écart).
func _add_strip(root: Node3D) -> void:
	var length := 400.0
	var width := 14.0
	var h0 := root.position.y
	var top := h0
	var f := root.rotation.y
	for k in range(0, 21):
		var d := length * k / 20.0
		var x := root.position.x + sin(f) * d
		var z := root.position.z + cos(f) * d
		top = maxf(top, height_at(x, z))
	var thick := 1.0
	var cy := (top - h0) + 0.08 - thick * 0.5
	var asphalt := _box(root, Vector3(width, thick, length), Vector3(0, cy, length * 0.5), Color(0.3, 0.3, 0.34))
	asphalt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(width, thick, length)
	shape.shape = bx
	shape.position = Vector3(0, cy, length * 0.5)
	body.add_child(shape)
	root.add_child(body)
	var y := cy + thick * 0.5 + 0.02
	for sx in [-width * 0.5 + 0.3, width * 0.5 - 0.3]:
		_box(root, Vector3(0.25, 0.04, length), Vector3(sx, y, length * 0.5), Color(0.95, 0.95, 0.92))
	for z in [0.0, length]:
		for i in 7:
			for j in 2:
				var c := Color(0.97, 0.97, 0.95) if (i + j) % 2 == 0 else Color(0.1, 0.1, 0.1)
				_box(root, Vector3(width / 7.0, 0.05, 0.8), Vector3(-width * 0.5 + (i + 0.5) * width / 7.0, y + 0.01, z + (j - 0.5) * 0.8), c)


func build_mission_markers(pois: Array, mission_id := "") -> Node3D:
	var root := Node3D.new()
	root.name = "LieuxDeMission"
	for p in pois:
		if not p.has("step"):
			continue
		# Seuls les lieux de la mission active sont affichés (les lieux de l'autre n'ont pas de sens ici).
		if mission_id != "" and not (mission_id in p.get("missions", [])):
			continue
		var x := float(p.position[0])
		var z := float(p.position[1])
		var n := Node3D.new()
		n.name = "Lieu_" + str(p.id)
		n.position = Vector3(x, height_at(x, z), z)
		n.rotation.y = float(p.get("facing", 0.0))
		if p.has("prop") and p.prop != "van" and p.prop != "car":
			_add_prop(n, p.prop)   # camionnette et voiture sont de vrais véhicules, pas des accessoires
		var color: Color = STEP_COLOR.get(p.step, Color.WHITE)
		# Balise : cylindre translucide visible de loin.
		var beam := CylinderMesh.new()
		beam.top_radius = 0.6; beam.bottom_radius = 0.6; beam.height = 30.0; beam.radial_segments = 12
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(color, 0.35)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material = bm
		var bi := MeshInstance3D.new()
		bi.mesh = beam
		bi.position.y = 15.0
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(bi)
		var label := Label3D.new()
		label.text = "%s\n(%s)" % [p.label, p.step]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 56
		label.pixel_size = 0.012
		label.outline_size = 16
		label.modulate = color.lightened(0.5)
		label.outline_modulate = Color(0.12, 0.09, 0.08)
		label.no_depth_test = true
		label.position.y = 8.0
		n.add_child(label)
		root.add_child(n)
	return root


## Construit toute la ville listée dans le manifeste. Renvoie le nœud racine.
func build_city(dir: String = CITY_DIR, mission_id := "") -> Node3D:
	var root := Node3D.new()
	root.name = "Ville"
	var manifest := load_manifest(dir)
	var tiles: Array[Dictionary] = []
	for key in manifest.get("tiles", []):
		var data = read_json(dir.path_join("tiles/%s.json" % key))
		if data is Dictionary:
			register_tile(data)
			tiles.append(data)
	for data in tiles:
		root.add_child(build_tile(data))
	if not tiles.is_empty():
		root.add_child(build_apron())
	var poi = read_json(dir.path_join("poi.json"))
	if poi is Dictionary:
		root.add_child(build_signs(poi.get("pois", [])))
		root.add_child(build_mission_markers(poi.get("pois", []), mission_id))
	return root
