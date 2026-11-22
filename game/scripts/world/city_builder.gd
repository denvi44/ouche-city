class_name CityBuilder
extends RefCounted
## Construit la ville dans Godot à partir des tuiles du cartographe (contracts/tile.schema.json v1),
## sans aucune retouche manuelle : murs extrudés, toits à deux pans, routes, trottoirs, végétation.
## Repère : x vers l'est, z vers le sud, y vers le haut, en mètres.

const CITY_DIR := "res://assets/city"
const MAT_DIR := "res://assets/materials/"

const Y_VEGETATION := 0.03
# Littoral : l'île s'arrête à SHORE_GROW mètres des tuiles (mur invisible, plage), le relief y plonge sous la mer.
const SHORE_START := 60.0
const SHORE_END := 260.0
const SHORE_GROW := 200.0
const SEA_DEPTH := 6.0
const SEA_EXTENT := 4000.0
const Y_TROTTOIR := 0.07
const Y_ROUTE := 0.1
## Pas maximal (m) des rubans de route et de trottoir : le ruban suit le relief tous les 2 m (sans cela, une longue arête reste plane et l'herbe affleure au travers).
const RIBBON_STEP := 2.0

## Matériaux de murs : façades peintes (fenêtres, volets, portes) sauf les annexes (remises, garages).
const WALL_MAT := {
	"colombages": "colombages", "brique": "facade_brique", "pavillon": "facade_crepi",
	"commerce": "facade_commerce", "public": "facade_pierre_public", "eglise": "facade_pierre_eglise", "annexe": "crepi_pavillon",
}
const VEG_MAT := {
	"grass": "vert_bocage", "park": "parc", "garden": "parc", "forest": "foret", "farmland": "champ", "water": "eau", "orchard": "vert_bocage",
}
const SURFACE_MAT := {"asphalt": "route", "pavers": "paves", "gravel": "gravier", "grass": "vert_bocage"}

var _materials := {}
var _tools := {}   # nom de matériau -> SurfaceTool
## Couleur de sommet appliquée aux triangles émis (données de façade : voir facade_details.gdshaderinc).
var _cur_color := Color.WHITE
## Polylignes des routes de la tuile en cours : sert à choisir le mur de la porte (côté rue).
var _tile_roads: Array = []
## Détails d'architecture (cheminées, lucarnes, corniches, auvents) : désactivables pour les mesures.
var details := true
var _collect_hull := false
var _hull_tris: Array = []   # triangles du bâti en cours : [a, b, c] (Vector3) pour le contour
## Grilles de relief des tuiles chargées : "x_y" -> { origin, size, res, heights }
var grids := {}
var bounds := Rect2()   # emprise couverte par les tuiles (repère local x, z)
## Routes carrossables (pour la vie ambiante) : [{"pts": PackedVector2Array, "width": float, "kind": String, "len": float}]
var road_lines: Array = []
## Contours des bâtiments (PackedVector2Array) : la vie ambiante n'y place personne.
var building_rings: Array = []
## Index spatial des bâtiments (cellules de 12 m -> contours) : sert aux trottoirs « jusqu'au mur ».
var _ring_grid := {}


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
func add_ground_grid(origin: Vector2, size: Vector2, step: float, mat: String, skip: Rect2 = Rect2(), hfun := Callable()) -> void:
	var st := _tool(mat)
	var hf: Callable = hfun if hfun.is_valid() else height_at
	var nx := int(ceil(size.x / step))
	var nz := int(ceil(size.y / step))
	for j in nz:
		for i in nx:
			var a := origin + Vector2(i * step, j * step)
			var c := a + Vector2(step, step)
			if skip.size != Vector2.ZERO and skip.encloses(Rect2(a, Vector2(step, step))):
				continue
			var p00 := Vector3(a.x, hf.call(a.x, a.y), a.y)
			var p10 := Vector3(c.x, hf.call(c.x, a.y), a.y)
			var p11 := Vector3(c.x, hf.call(c.x, c.y), c.y)
			var p01 := Vector3(a.x, hf.call(a.x, c.y), c.y)
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


## Surface de détail d'architecture : même matériau que `mat`, mais exclue des collisions (préfixe « ~ »).
func _dtool(mat: String) -> SurfaceTool:
	return _tool("~" + mat)


## Maillage de collision d'un bâti : toutes les surfaces sauf les détails (auvents, corniches, cheminées…).
static func collision_mesh(src: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		if not src.surface_get_name(i).begins_with("~"):
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
	return out


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
	if landmark_buildings.has(str(b.id)):
		return                      # remplacé par un modèle détaillé (Landmarks), posé par build_landmarks
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
	# Seuil à la hauteur de la porte (côté rue) : l'entrée reste de plain-pied avec la chaussée ; si le terrain est plus bas ailleurs, un soubassement
	# comble le vide ; s'il est plus haut (côté amont), le bâtiment est « adossé » à la pente au lieu d'être enterré par son point le plus bas.
	if door_edge >= 0:
		var dm := (full[door_edge] + full[(door_edge + 1) % full.size()]) * 0.5
		ground = maxf(ground, height_at(dm.x, dm.y))
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
		# Soubassement en pierre jusqu'au terrain (sans détails de façade).
		var yb_a := minf(ground, height_at(a.x, a.y)) - 0.05
		var yb_c := minf(ground, height_at(c.x, c.y)) - 0.05
		if ground - minf(yb_a, yb_c) > 0.12:
			_cur_color = Color(seed, 0.0, 0.0, 0.0)
			_quad(_tool("facade_pierre_public"), Vector3(a.x, yb_a, a.y), Vector3(c.x, yb_c, c.y), Vector3(c.x, ground + 0.02, c.y), Vector3(a.x, ground + 0.02, a.y), n,
				Vector2(0, 0), Vector2(seg_l, 0), Vector2(seg_l, ground - yb_c), Vector2(0, ground - yb_a))
			_cur_color = Color.WHITE
		if has_details and details:
			BuildingDetails.emit_bands(self, a, c, n2, ground, ha, hc, typo, i == door_edge)
			if i == door_edge:
				BuildingDetails.emit_door_feature(self, a, c, n2, ground, seed, typo, typo == "eglise")
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
		if details:
			BuildingDetails.emit_buttresses(self, ring, m, ground, h)
	elif details:
		BuildingDetails.emit_chimneys(self, ring, m, ground, seed, typo)
		BuildingDetails.emit_dormers(self, ring, m, ground, seed, typo, int(b.get("levels", 1)), roof_mat)


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
## Rééchantillonne une polyligne : aucun tronçon plus long que `step` (les sommets d'origine sont conservés).
static func densify(points: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size():
		out.append(points[i])
		if i < points.size() - 1:
			var seg := points[i].distance_to(points[i + 1])
			var n := int(ceil(seg / step))
			for k in range(1, n):
				out.append(points[i].lerp(points[i + 1], float(k) / float(n)))
	return out


## Altitude de base d'une section de route : le point le plus haut du terrain sur toute la largeur (`half` de part et d'autre de l'axe).
## Le ruban reste ainsi toujours au-dessus du sol (jamais de bande d'herbe qui coupe l'asphalte) et sans dévers ; chaussée et trottoir partagent ce profil.
func rung_height(center: Vector2, perp: Vector2, half: float) -> float:
	var h := height_at(center.x, center.y)
	for k in [-1.0, -0.5, 0.5, 1.0]:
		var q: Vector2 = center + perp * half * float(k)
		h = maxf(h, height_at(q.x, q.y))
	return h


## Décalage vertical (m) d'une chaussée selon son importance : à un carrefour, la plus grande route passe au-dessus (sinon les deux surfaces, quasi confondues,
## se disputent les pixels et leurs marquages « clignotent »).
static func road_rank_offset(kind: String) -> float:
	return {"primary": 0.05, "secondary": 0.04, "tertiary": 0.03, "residential": 0.02, "unclassified": 0.01, "living_street": 0.01}.get(kind, 0.0)


## Altitude de la surface de la chaussée au point `p` (x, z) : celle du ruban dessiné (et non celle du terrain) ; `fallback` hors route.
func road_surface_y(p: Vector2, fallback: float) -> float:
	var best := 2.5
	var res := fallback
	for r in road_lines:
		if str(r.kind) in ["footway", "track", "pedestrian", "steps"]:
			continue
		var pts: PackedVector2Array = r.pts
		for i in range(pts.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1])
			var d := q.distance_to(p)
			if d < best and d < float(r.width) * 0.5 + 1.0:
				best = d
				var seg := (pts[i + 1] - pts[i]).normalized()
				res = rung_height(q, Vector2(-seg.y, seg.x), float(r.width) * 0.5 + float(r.get("sw", 0.0))) + Y_ROUTE + road_rank_offset(str(r.kind))
	return res


func add_ribbon(points_in: PackedVector2Array, width: float, y: float, mat: String, cross_width := -1.0) -> void:
	if points_in.size() < 2:
		return
	var points := densify(points_in, RIBBON_STEP)
	var cross_half := (cross_width if cross_width > 0.0 else width) * 0.5
	var base := PackedFloat32Array()
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
		base.append(rung_height(points[i], perp, cross_half))
	_cur_color = Color(clampf(width / 16.0, 0.0, 1.0), 0.0, 0.0, 1.0)     # largeur de la route : le shader en déduit marquages et lignes de rive
	var v := 0.0
	for i in points.size() - 1:
		var seg_len := points[i].distance_to(points[i + 1])
		var l0 := Vector3(left[i].x, base[i] + y, left[i].y)
		var r0 := Vector3(right[i].x, base[i] + y, right[i].y)
		var r1 := Vector3(right[i + 1].x, base[i + 1] + y, right[i + 1].y)
		var l1 := Vector3(left[i + 1].x, base[i + 1] + y, left[i + 1].y)
		_quad(st, l0, r0, r1, l1, Vector3.UP,
			Vector2(0, v), Vector2(width, v), Vector2(width, v + seg_len), Vector2(0, v + seg_len))
		v += seg_len
	_cur_color = Color(0.0, 0.0, 0.0, 1.0)       # pastilles : largeur 0 = aucun marquage (leurs UV sont des coordonnées du monde)
	# Pastilles aux extrémités pour masquer les jonctions.
	for p in [points[0], points[points.size() - 1]]:
		_add_disc(st, p, half, y)
	_cur_color = Color.WHITE


func _add_disc(st: SurfaceTool, c: Vector2, r: float, y: float, segments: int = 10) -> void:
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var p0 := c + Vector2(cos(a0), sin(a0)) * r
		var p1 := c + Vector2(cos(a1), sin(a1)) * r
		_tri(st, Vector3(c.x, height_at(c.x, c.y) + y, c.y), Vector3(p0.x, height_at(p0.x, p0.y) + y, p0.y),
			Vector3(p1.x, height_at(p1.x, p1.y) + y, p1.y), Vector3.UP, c, p0, p1)


func _index_rings(tiles: Array) -> void:
	_ring_grid.clear()
	for data in tiles:
		for bd in data.buildings:
			var rg := PackedVector2Array()
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for v in bd.footprint:
				var q := Vector2(float(v[0]), float(v[1]))
				rg.append(q)
				lo = lo.min(q)
				hi = hi.max(q)
			for cx in range(int(floor(lo.x / 12.0)), int(floor(hi.x / 12.0)) + 1):
				for cz in range(int(floor(lo.y / 12.0)), int(floor(hi.y / 12.0)) + 1):
					var key := Vector2i(cx, cz)
					if not _ring_grid.has(key):
						_ring_grid[key] = []
					_ring_grid[key].append(rg)


func _in_building(p: Vector2) -> bool:
	var key := Vector2i(int(floor(p.x / 12.0)), int(floor(p.y / 12.0)))
	if not _ring_grid.has(key):
		return false
	for rg: PackedVector2Array in _ring_grid[key]:
		if Geometry2D.is_point_in_polygon(p, rg):
			return true
	return false


## Distance (m, ≤ max_gap) entre le bord du trottoir `edge` et le premier bâtiment dans la direction `dir` ; -1 s'il n'y en a pas.
func _gap_to_building(edge: Vector2, dir: Vector2, max_gap: float) -> float:
	var t := 0.0
	while t <= max_gap:
		if _in_building(edge + dir * t):
			return t
		t += 0.4
	return -1.0


## Dallage entre le trottoir et la façade quand un bâtiment borde la rue à moins de 6,5 m : plus de bande d'herbe entre la chaussée et les murs.
func _add_verge(pts_in: PackedVector2Array, half_total: float) -> void:
	if _ring_grid.is_empty() or pts_in.size() < 2:
		return
	var pts := densify(pts_in, 3.0)
	var st := _tool("trottoir")
	for side in [1.0, -1.0]:
		var inner := PackedVector2Array()
		var outer := PackedVector2Array()
		for i in pts.size() + 1:
			var ok := false
			if i < pts.size():
				var dir := Vector2.ZERO
				if i > 0:
					dir += (pts[i] - pts[i - 1]).normalized()
				if i < pts.size() - 1:
					dir += (pts[i + 1] - pts[i]).normalized()
				dir = dir.normalized()
				var perp := Vector2(-dir.y, dir.x) * float(side)
				var edge: Vector2 = pts[i] + perp * (half_total - 0.1)
				var gap := _gap_to_building(edge, perp, 6.5)
				if gap > 0.25:
					inner.append(edge)
					outer.append(edge + perp * (gap + 0.05))
					ok = true
			if not ok:
				for k in range(inner.size() - 1):
					var a0 := Vector3(inner[k].x, maxf(height_at(inner[k].x, inner[k].y), height_at(outer[k].x, outer[k].y)) + 0.05, inner[k].y)
					var b0 := Vector3(outer[k].x, a0.y, outer[k].y)
					var b1 := Vector3(outer[k + 1].x, maxf(height_at(inner[k + 1].x, inner[k + 1].y), height_at(outer[k + 1].x, outer[k + 1].y)) + 0.05, outer[k + 1].y)
					var a1 := Vector3(inner[k + 1].x, b1.y, inner[k + 1].y)
					_quad(st, a0, b0, b1, a1, Vector3.UP, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
				inner.clear()
				outer.clear()


func add_road(r: Dictionary) -> void:
	var pts := to_ring(r.points)
	var w := float(r.width)
	var sw := float(r.get("sidewalk", 0.0))
	if sw > 0.0:
		add_ribbon(pts, w + 2.0 * sw, Y_TROTTOIR, "trottoir")
		if r.kind in ["residential", "secondary", "tertiary", "primary", "unclassified", "living_street"]:
			_add_verge(pts, w * 0.5 + sw)
	var mat: String = SURFACE_MAT.get(r.get("surface", "asphalt"), "route")
	if r.kind in ["footway", "pedestrian"] and mat == "route":
		mat = "paves"
	add_ribbon(pts, w, Y_ROUTE + road_rank_offset(str(r.kind)), mat, w + 2.0 * sw)


func add_vegetation(v: Dictionary) -> void:
	var poly := to_ring(v.polygon)
	_add_polygon(_tool(VEG_MAT.get(v.kind, "vert_bocage")), poly, func(p): return height_at(p.x, p.y) + Y_VEGETATION, Vector3.ZERO)


## Centres des enseignes : les lampadaires s'en écartent (renseigné par `build_city`).
var sign_spots: Array = []
## Bâtiments remplacés par un édifice détaillé (POI portant `facility`) : id de bâtiment -> POI.
var landmark_buildings := {}


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
		_add_collision(body, collision_mesh(buildings_mesh))
		var hi := MeshInstance3D.new()
		hi.name = "Contours"
		hi.mesh = hull_mesh
		hi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(hi)
	var size := float(data.size)
	add_ground_grid(Vector2(float(data.origin[0]), float(data.origin[1])), Vector2(size, size), size / float(maxi(int(data.ground.resolution) - 1, 1)), "sol")
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
	root.add_child(StreetFurniture.build_tile(data, height_at, sign_spots))
	return root


func _build_hull(tris: Array) -> ArrayMesh:
	return HullOutline.build(tris)


func _add_collision(body: StaticBody3D, mesh: ArrayMesh) -> void:
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)


## Niveau de la mer : juste sous le point le plus bas du pourtour des tuiles (aucune terre du bord n'est noyée).
var _sea_y := NAN


func sea_level() -> float:
	if not is_nan(_sea_y):
		return _sea_y
	var low := INF
	var step := 50.0
	for t in range(0, int(bounds.size.x / step) + 1):
		var x := bounds.position.x + t * step
		low = minf(low, minf(height_at(x, bounds.position.y), height_at(x, bounds.end.y)))
	for t in range(0, int(bounds.size.y / step) + 1):
		var z := bounds.position.y + t * step
		low = minf(low, minf(height_at(bounds.position.x, z), height_at(bounds.end.x, z)))
	_sea_y = low - 0.5
	return _sea_y


## Distance (m) à l'emprise des tuiles ; 0 à l'intérieur.
func outside_distance(x: float, z: float) -> float:
	var dx := maxf(maxf(bounds.position.x - x, x - bounds.end.x), 0.0)
	var dz := maxf(maxf(bounds.position.y - z, z - bounds.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


## Relief du tablier : celui du bord prolongé, qui plonge en plage puis sous la mer entre SHORE_START et SHORE_END.
func apron_height(x: float, z: float) -> float:
	var t := smoothstep(SHORE_START, SHORE_END, outside_distance(x, z))
	return lerpf(height_at(x, z), sea_level() - SEA_DEPTH, t)


## Tablier de terrain autour de la ville, avec collisions : le village est une île (plage, mer, murs invisibles, routes barrées).
func build_apron(margin: float = 400.0, step: float = 25.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Tablier"
	_sea_y = NAN
	var origin := bounds.position - Vector2(margin, margin)
	add_ground_grid(origin, bounds.size + Vector2(margin, margin) * 2.0, step, "sol", bounds, apron_height)
	var mesh := _commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var body := StaticBody3D.new()
	_add_collision(body, mesh)
	root.add_child(body)
	root.add_child(_build_sea())
	root.add_child(_build_shore_walls())
	return root


## Mer : quatre grands rectangles autour des tuiles, au niveau de la mer (le relief de l'île les recouvre).
func _build_sea() -> Node3D:
	var sea := Node3D.new()
	sea.name = "Mer"
	var y := sea_level()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.72)
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.15, 0.25)
	var e := SEA_EXTENT
	var rects := [
		Rect2(bounds.position.x - e, bounds.position.y - e, bounds.size.x + 2.0 * e, e),
		Rect2(bounds.position.x - e, bounds.end.y, bounds.size.x + 2.0 * e, e),
		Rect2(bounds.position.x - e, bounds.position.y, e, bounds.size.y),
		Rect2(bounds.end.x, bounds.position.y, e, bounds.size.y),
	]
	for r in rects:
		var q := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		q.mesh = pm
		q.material_override = mat
		q.position = Vector3(r.get_center().x, y, r.get_center().y)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sea.add_child(q)
	return sea


## Murs invisibles à SHORE_GROW mètres des tuiles : on ne marche ni ne roule jusqu'à la mer, on ne tombe plus dans le vide.
func _build_shore_walls() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "MursDuLittoral"
	var g := SHORE_GROW
	var r := bounds.grow(g)
	var y := sea_level()
	var t := 6.0
	var h := 400.0
	var specs := [
		[Vector3(r.get_center().x, y, r.position.y - t * 0.5), Vector3(r.size.x + 2.0 * t, h, t)],
		[Vector3(r.get_center().x, y, r.end.y + t * 0.5), Vector3(r.size.x + 2.0 * t, h, t)],
		[Vector3(r.position.x - t * 0.5, y, r.get_center().y), Vector3(t, h, r.size.y)],
		[Vector3(r.end.x + t * 0.5, y, r.get_center().y), Vector3(t, h, r.size.y)],
	]
	for sp in specs:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sp[1]
		cs.shape = bs
		cs.position = sp[0]
		body.add_child(cs)
	return body


## Une barrière rouge et blanche en travers de chaque route qui sort des tuiles : « fin de route », on ne roule pas vers le vide.
func _build_road_barriers() -> Node3D:
	var root := Node3D.new()
	root.name = "BarrieresDeFinDeRoute"
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.15, 0.12)
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.92)
	for rl in road_lines:
		var pts: PackedVector2Array = rl.pts
		if pts.size() < 2:
			continue
		for end_i in [0, pts.size() - 1]:
			var p: Vector2 = pts[end_i]
			if outside_distance(p.x, p.y) > 0.0 or _edge_gap(p) > 14.0:
				continue
			var q: Vector2 = pts[1] if end_i == 0 else pts[pts.size() - 2]
			var dir := (p - q).normalized()
			var wd := maxf(float(rl.get("width", 6.0)), 4.0) + 1.0
			var yaw := atan2(dir.x, dir.y)
			var at := Vector3(p.x, height_at(p.x, p.y), p.y)
			var holder := Node3D.new()
			holder.position = at
			holder.rotation.y = yaw
			var n := 6
			for i in n:
				var m := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(wd / n, 0.3, 0.12)
				m.mesh = bm
				m.material_override = red if i % 2 == 0 else white
				m.position = Vector3(-wd * 0.5 + (i + 0.5) * wd / n, 1.0, 0.0)
				holder.add_child(m)
			for sx in [-wd * 0.5, wd * 0.5]:
				var post := MeshInstance3D.new()
				var pmz := BoxMesh.new()
				pmz.size = Vector3(0.12, 1.2, 0.12)
				post.mesh = pmz
				post.material_override = white
				post.position = Vector3(sx, 0.6, 0.0)
				holder.add_child(post)
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(wd, 1.6, 0.4)
			cs.shape = bs
			cs.position = Vector3(0, 0.8, 0)
			sb.add_child(cs)
			holder.add_child(sb)
			root.add_child(holder)
	return root


## Distance d'un point à l'intérieur des tuiles jusqu'au bord de l'emprise.
func _edge_gap(p: Vector2) -> float:
	return minf(minf(p.x - bounds.position.x, bounds.end.x - p.x), minf(p.y - bounds.position.y, bounds.end.y - p.y))


func _commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var keys := _tools.keys()
	keys.sort()
	for k in keys:
		var st: SurfaceTool = _tools[k]
		st.set_material(material(k.trim_prefix("~")))
		st.commit(mesh)
		mesh.surface_set_name(mesh.get_surface_count() - 1, k)
	_tools.clear()
	return mesh


func _build_trees(points: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Arbres"
	# Quatre espèces (0 chêne, 1 pin, 2 pommier, 3 peuplier), un MultiMesh par espèce et par tuile, masqué au-delà de 420 m.
	var kits := ["tree_oak", "tree_pine", "tree_apple", "tree_poplar"]
	var groups := [[], [], [], []]
	for p in points:
		var sp := clampi(int(p[2]) if p.size() > 2 else 0, 0, 3)
		var h1 := _hash01("%s_%s" % [p[0], p[1]])
		var h2 := _hash01("%s|%s" % [p[1], p[0]])
		var sc := 0.82 + h1 * 0.5
		var x := float(p[0])
		var z := float(p[1])
		groups[sp].append(Transform3D(Basis(Vector3.UP, h2 * TAU) * Basis.from_scale(Vector3.ONE * sc), Vector3(x, height_at(x, z) - 0.05, z)))
	for sp in 4:
		if groups[sp].is_empty():
			continue
		# La distance de visibilité se mesure à l'origine du nœud : on le place au centre du groupe et on recale les transformations.
		var centre := Vector3.ZERO
		for xf: Transform3D in groups[sp]:
			centre += xf.origin
		centre /= float(groups[sp].size())
		var rebased := []
		for xf: Transform3D in groups[sp]:
			rebased.append(Transform3D(xf.basis, xf.origin - centre))
		var holder := Node3D.new()
		holder.name = "Arbres_%d" % sp
		holder.position = centre
		root.add_child(holder)
		StreetFurniture._multimesh(holder, "Arbre_%d" % sp, StreetFurniture.kit(kits[sp]), rebased)
		for c in holder.get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).visibility_range_end = 420.0
				(c as GeometryInstance3D).visibility_range_end_margin = 40.0
				(c as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	return root


## Édifices détaillés (église, mairie, écoles, hôpital, distillerie) : un modèle `Landmarks` par POI portant `facility` et `rect`,
## posé sur l'emprise du bâtiment d'origine (omis du maillage des tuiles), avec une collision à la taille du volume principal.
func build_landmarks(pois: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Edifices"
	for p in pois:
		if str(p.get("prop", "")) == "carriere":
			var q := Node3D.new()
			q.name = "Carriere"
			q.position = Vector3(float(p.position[0]), height_at(float(p.position[0]), float(p.position[1])), float(p.position[1]))
			q.rotation.y = float(p.get("facing", 0.0))
			q.set_meta("poi", p)
			_add_carriere(q)
			root.add_child(q)
			continue
		if not p.has("facility") or not p.has("rect"):
			continue
		var x := float(p.position[0])
		var z := float(p.position[1])
		var w := float(p.rect[0])
		var d := float(p.rect[1])
		var m := Landmarks.build(str(p.facility), w, d, str(p.label))
		var n: Node3D = Node3D.new()
		n.name = "Edifice_" + str(p.id)
		# Posé au point le plus bas de l'emprise (le soubassement masque la pente).
		var gy := height_at(x, z)
		var f := float(p.get("facing", 0.0))
		var bas := Basis(Vector3.UP, f)
		for c: Vector2 in [Vector2(-w / 2, -d / 2), Vector2(w / 2, -d / 2), Vector2(w / 2, d / 2), Vector2(-w / 2, d / 2)]:
			var q: Vector3 = bas * Vector3(c.x, 0, c.y)
			gy = minf(gy, height_at(x + q.x, z + q.z))
		n.position = Vector3(x, gy, z)
		n.rotation.y = f
		n.add_child(m.node)
		var body := StaticBody3D.new()
		body.name = "Collision"
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var sz: Vector3 = m.size
		bs.size = sz
		cs.shape = bs
		cs.position = Vector3(0, sz.y / 2.0, 0)
		body.add_child(cs)
		n.add_child(body)
		root.add_child(n)
	return root


## Carrière de pierres (prop `carriere`) : clôture orange sur le bord (sauf à la rampe), panneaux « DANGER », et au fond une pelleteuse,
## un camion-benne, un concasseur à tapis, des tas de gravier, des blocs, une cabane de chantier et une mare. Repère : +Z = vers la rampe.
func _add_carriere(root: Node3D) -> void:
	var poi: Dictionary = root.get_meta("poi", {})
	var R := float(poi.get("radius", 62.0))
	var basis := Basis(Vector3.UP, root.rotation.y)
	var fence := []
	var n := int(floor(TAU * (R + 2.0) / 3.0))
	for i in n:
		var a := TAU * float(i) / float(n)
		# Pas de clôture dans l'axe de la rampe (a = 0 : +Z local).
		if absf(wrapf(a, -PI, PI)) < 0.2:
			continue
		var lp := Vector3(sin(a) * (R + 2.0), 0, cos(a) * (R + 2.0))
		var wp := root.position + basis * lp
		var yaw := a + PI / 2.0
		fence.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(lp.x, height_at(wp.x, wp.z) - root.position.y, lp.z)))
	StreetFurniture._multimesh(root, "Cloture", PropKit.quarry_fence_cached(), fence)
	for a in [0.9, 2.2, 3.6, 5.1]:
		var lp := Vector3(sin(a) * (R + 3.0), 0, cos(a) * (R + 3.0))
		var wp := root.position + basis * lp
		var sign := PropKit.warning_sign().build()
		sign.position = Vector3(lp.x, height_at(wp.x, wp.z) - root.position.y, lp.z)
		sign.rotation.y = a + PI
		root.add_child(sign)
	var fond := {"exc": Vector3(-14, 0, -10), "cam": Vector3(12, 0, -6), "conc": Vector3(-3, 0, 14), "cab": Vector3(16, 0, 10)}
	var kits := {"exc": [PropKit.excavator(), 0.6], "cam": [PropKit.dump_truck(), -1.2], "conc": [PropKit.crusher(), 2.6], "cab": [PropKit.gate_hut(), 2.0]}
	for key in fond:
		var lp: Vector3 = fond[key]
		var wp := root.position + basis * lp
		var node: Node3D = (kits[key][0] as PropKit).build()
		node.position = Vector3(lp.x, height_at(wp.x, wp.z) - root.position.y, lp.z)
		node.rotation.y = float(kits[key][1])
		root.add_child(node)
	for i in 9:
		var a2 := float(i) * 2.4
		var lp2 := Vector3(cos(a2) * (6.0 + float(i) * 1.7), 0, sin(a2) * (6.0 + float(i) * 1.7))
		var wp2 := root.position + basis * lp2
		var b := PropKit.boulder(0.8 + 0.5 * float(i % 3)).build()
		b.position = Vector3(lp2.x, height_at(wp2.x, wp2.z) - root.position.y, lp2.z)
		b.rotation.y = a2
		root.add_child(b)
	# Sol de roche : maillage de 5 m posé sur le relief creusé (gradins et fond), en gravier clair.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(material("gravier"))
	var step := 5.0
	var m := int(ceil((R + 6.0) / step))
	for gi in range(-m, m):
		for gj in range(-m, m):
			var c00 := Vector2(gi, gj) * step
			var c11 := Vector2(gi + 1, gj + 1) * step
			if (c00 + c11).length() / 2.0 > R + 3.0:
				continue
			var pts := []
			for q in [Vector2(gi, gj), Vector2(gi + 1, gj), Vector2(gi + 1, gj + 1), Vector2(gi, gj + 1)]:
				var lp := Vector3(q.x * step, 0, q.y * step)
				var wp := root.position + basis * lp
				pts.append(Vector3(lp.x, height_at(wp.x, wp.z) - root.position.y + 0.55, lp.z))
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for idx in tri:
					st.set_normal(Vector3.UP)
					st.add_vertex(pts[idx])
	var rock := MeshInstance3D.new()
	rock.name = "SolRoche"
	rock.mesh = st.commit()
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rock)
	var lake := PropKit.new().add_cyl(6.5, 6.5, 0.12, Vector3(0, 0.06, 0), Color(0.3, 0.55, 0.72), Vector3.ZERO, 16).build()
	var lw := root.position + basis * Vector3(-18, 0, 12)
	lake.position = Vector3(-18, height_at(lw.x, lw.z) - root.position.y + 0.02, 12)
	root.add_child(lake)
	var label := Label3D.new()
	label.text = "CARRIÈRE — ENTRÉE INTERDITE"
	label.font_size = 56
	label.pixel_size = 0.012
	label.modulate = Color(1.0, 0.85, 0.2)
	label.outline_size = 8
	label.position = Vector3(0, 10.0, R * 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)


## Enseignes des lieux fictifs (POI v2 portant `building` et `facing`) : panneau crème bordé
## de bois, posé sur la façade côté rue, à 3 m du sol.
func build_signs(pois: Array, rings_by_id: Dictionary = {}) -> Node3D:
	var root := Node3D.new()
	root.name = "Enseignes"
	var board_mat := ShaderMaterial.new()
	board_mat.shader = preload("res://shaders/toon.gdshader")
	board_mat.set_shader_parameter("couleur", Color(0.96, 0.91, 0.78))
	for p in pois:
		if not p.has("building") or not p.has("facing") or p.has("facility"):
			continue
		# Un décor déplacé hors du mur (cuisine du méchoui, scène…) n'a plus de façade où accrocher son enseigne.
		if p.has("prop") and rings_by_id.has(str(p.building)):
			var ring: PackedVector2Array = rings_by_id[str(p.building)]
			var at := Vector2(float(p.position[0]), float(p.position[1]))
			var dmin := INF
			for i in ring.size():
				dmin = minf(dmin, Geometry2D.get_closest_point_to_segment(at, ring[i], ring[(i + 1) % ring.size()]).distance_to(at))
			if dmin > 0.8:
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
	"parts": Color(0.95, 0.75, 0.2), "assembly": Color(0.7, 0.5, 0.9), "test_drive": Color(0.3, 0.6, 0.9), "meet": Color(0.95, 0.5, 0.7), "drag": Color(0.85, 0.25, 0.2),
	"stage": Color(0.3, 0.8, 0.95), "rival": Color(0.9, 0.3, 0.6), "setup": Color(0.95, 0.75, 0.2),
	"fire": Color(0.95, 0.5, 0.15), "gather": Color(0.95, 0.75, 0.2), "bonfire": Color(0.9, 0.25, 0.2),
	"pen": Color(0.45, 0.8, 0.4), "herd": Color(0.95, 0.95, 0.9), "shop": Color(0.95, 0.35, 0.3),
	"start": Color(0.85, 0.7, 0.2), "home": Color(0.3, 0.7, 0.9), "wc": Color(0.3, 0.75, 0.45)}


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
		"fete":
			# Cuisine du méchoui : brasero, deux mâts à guirlande de fanions, tonneaux et bottes de paille.
			root.add_child(PropKit.brazier().build())
			for sx in [-4.0, 4.0]:
				_box(root, Vector3(0.14, 3.4, 0.14), Vector3(sx, 1.7, 0), Color(0.4, 0.28, 0.2))
			var flags := PropKit.bunting(8.0).build()
			flags.position = Vector3(-4.0, 3.2, 0)
			root.add_child(flags)
			for spec in [[PropKit.barrel(), Vector3(-3.2, 0, -1.4), 0.0], [PropKit.barrel(), Vector3(-2.4, 0, -1.9), 0.6], [PropKit.hay_bale(), Vector3(3.4, 0, -1.6), 0.4], [PropKit.hay_bale(), Vector3(4.6, 0, -1.2), -0.3]]:
				var n: Node3D = spec[0].build()
				n.position = spec[1]
				n.rotation.y = spec[2]
				root.add_child(n)
		"pyre":
			root.add_child(PropKit.pyre().build())
		"pen":
			root.add_child(PropKit.pen(6.0).build())
		"pressoir":
			root.add_child(PropKit.cider_press().build())
			var flags2 := PropKit.bunting(5.0).build()
			flags2.position = Vector3(-0.9, 3.0, -0.5)
			root.add_child(flags2)
		"wc":
			root.add_child(PropKit.wc_cabin().build())
		"supermarket":
			root.add_child(Supermarket.build(true, Supermarket.lift_for(height_at, root.position, root.rotation.y)))
		"strip":
			_add_strip(root)
		"stage":
			# Scène de sono : estrade, deux enceintes (HP_G, HP_D, qui pulsent au rythme), table de mixage, guirlande.
			_box(root, Vector3(7.0, 0.4, 3.6), Vector3(0, 0.2, 0), Color(0.5, 0.36, 0.26))
			for sx in [-1, 1]:
				var hp := _box(root, Vector3(1.2, 2.0, 1.1), Vector3(sx * 2.7, 1.4, -0.4), Color(0.14, 0.13, 0.16))
				hp.name = "HP_G" if sx < 0 else "HP_D"
				_box(hp, Vector3(0.7, 0.7, 0.05), Vector3(0, 0.35, 0.56), Color(0.9, 0.85, 0.7))
				_box(hp, Vector3(0.4, 0.4, 0.05), Vector3(0, -0.45, 0.56), Color(0.9, 0.85, 0.7))
			_box(root, Vector3(1.8, 0.9, 0.8), Vector3(0, 0.85, 0.4), Color(0.85, 0.25, 0.3))
			_box(root, Vector3(1.4, 0.06, 0.5), Vector3(0, 1.33, 0.4), Color(0.2, 0.9, 0.9)).name = "Pupitre"
			for i in 7:
				_box(root, Vector3(0.3, 0.3, 0.3), Vector3(-3.0 + i, 3.2, -0.6), [Color(0.95, 0.75, 0.2), Color(0.85, 0.25, 0.2), Color(0.3, 0.7, 0.9)][i % 3])
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
		"coop":
			var coop := PropKit.coop().build()
			coop.position = Vector3(2.8, 0, 0.3)   # sur le côté de la façade : le point d'enlèvement des caisses reste dégagé
			root.add_child(coop)
			var cbody := StaticBody3D.new()
			cbody.name = "Collision"
			var cshape := CollisionShape3D.new()
			var cbox := BoxShape3D.new()
			cbox.size = Vector3(1.7, 1.9, 1.4)
			cshape.shape = cbox
			cshape.position = Vector3(2.8, 0.95, 1.2)
			cbody.add_child(cshape)
			root.add_child(cbody)
		"rail":
			_add_rail(root)
		"pond":
			var pond := PropKit.goose_pond().build()
			root.add_child(pond)
		"gare":
			_add_gare(root)
		"fumier":
			var heap := SphereMesh.new()
			heap.radius = 1.6; heap.height = 1.8; heap.radial_segments = 8; heap.rings = 4
			heap.material = _toon(Color(0.4, 0.3, 0.18))
			var hi := MeshInstance3D.new()
			hi.mesh = heap
			hi.position.y = 0.2
			root.add_child(hi)


## Voie ferrée de la mission 08 : traverses, rails et ballast tous les mètres sur toute la longueur du POI (cap de la voie = +Z local),
## posés sur le relief ; croix de Saint-André au passage à niveau et maisonnette du garde-barrière.
func _add_rail(root: Node3D) -> void:
	var poi: Dictionary = root.get_meta("poi", {})
	var length := float(poi.get("length", 360.0))
	var basis := Basis(Vector3.UP, root.rotation.y)
	var xfs := []
	var z := -length / 2.0
	while z <= length / 2.0:
		var w0 := root.position + basis * Vector3(0, 0, z - 1.0)
		var w1 := root.position + basis * Vector3(0, 0, z + 1.0)
		var wm := root.position + basis * Vector3(0, 0, z)
		var y0 := height_at(w0.x, w0.z)
		var y1 := height_at(w1.x, w1.z)
		var ym := height_at(wm.x, wm.z)
		var pitch := -atan2(y1 - y0, 2.0)
		xfs.append(Transform3D(Basis.from_euler(Vector3(pitch, 0, 0)), Vector3(0, ym - root.position.y + 0.02, z)))
		z += 1.0
	StreetFurniture._multimesh(root, "Voie", StreetFurniture.kit("rail_tie"), xfs)
	root.add_child(PropKit.crossing_signs().build())
	var hut := PropKit.gate_hut().build()
	hut.position = Vector3(16.0, 0.0, -3.0)
	hut.rotation.y = -PI / 2.0
	root.add_child(hut)


## Gare du Pays de Frouch (POI `gare_pays_frouch`, prop `gare`) : quai, auvent, bâtiment des voyageurs avec horloge et enseigne, mobilier du quai
## (bancs, lampadaires, panneaux), chemin de gravier jusqu'à la route. Repère du POI : +Z le long de la voie ; `side` (+1 / -1) donne le côté.
func _add_gare(root: Node3D) -> void:
	var poi: Dictionary = root.get_meta("poi", {})
	var side := float(poi.get("side", 1))
	var gare := Node3D.new()
	gare.name = "Gare"
	if side < 0.0:
		gare.rotation.y = PI                    # le bâtiment passe de l'autre côté de la voie
	root.add_child(gare)
	var gy := height_at(root.position.x, root.position.z)
	gare.position.y = 0.0
	gare.add_child(PropKit.station_platform().build())
	gare.add_child(PropKit.station_canopy().build())
	gare.add_child(PropKit.station_building().build())
	# Enseignes (face quai et face parvis) et numéro de quai.
	for spec in [[Vector3(10.0, 5.6, 0.0), -PI / 2.0, "GARE DU PAYS DE FROUCH"], [Vector3(19.1, 5.6, 0.0), PI / 2.0, "GARE DU PAYS DE FROUCH"]]:
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.12, 0.9, 7.0)
		bm.material = _toon(Color(0.16, 0.3, 0.45))
		board.mesh = bm
		board.position = spec[0] - Vector3(0.0 if spec[1] < 0.0 else 0.0, 0, 0)
		gare.add_child(board)
		var label := Label3D.new()
		label.text = spec[2]
		label.font_size = 64
		label.pixel_size = 0.0095
		label.modulate = Color(0.98, 0.96, 0.88)
		label.outline_size = 0
		label.double_sided = false
		label.position = spec[0] + Vector3(-0.08 if spec[1] < 0.0 else 0.08, 0.0, 0.0)
		label.rotation.y = spec[1]
		gare.add_child(label)
	var quai := Label3D.new()
	quai.text = "QUAI 1"
	quai.font_size = 56
	quai.pixel_size = 0.008
	quai.modulate = Color(1.0, 0.95, 0.6)
	quai.position = Vector3(6.0, 3.0, -24.0)
	quai.rotation.y = -PI / 2.0
	gare.add_child(quai)
	# Mobilier de quai : bancs contre la façade, lampadaires au bord de l'auvent.
	for z in [-14.0, 0.0, 14.0]:
		var bench := PropKit.bench().build()
		bench.position = Vector3(9.4, QUAI_H_VISUAL, z)
		bench.rotation.y = -PI / 2.0 + PI
		gare.add_child(bench)
	for z in [-30.0, -10.0, 10.0, 30.0]:
		var lamp := PropKit.lamp().build()
		lamp.position = Vector3(3.2, QUAI_H_VISUAL, z)
		lamp.rotation.y = -PI / 2.0
		gare.add_child(lamp)
	# Collisions : quai (marchable par les rampes), bâtiment.
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shapes := [
		[Vector3(4.2, 0.8, 80.0), Vector3(4.3, 0.4, 0.0), 0.0],
		[Vector3(4.2, 0.15, 4.2), Vector3(4.3, 0.4, 42.0), -0.2],
		[Vector3(4.2, 0.15, 4.2), Vector3(4.3, 0.4, -42.0), 0.2],
		[Vector3(9.0, 6.5, 24.0), Vector3(14.5, 3.25, 0.0), 0.0],
	]
	for sp in shapes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sp[0]
		cs.shape = bs
		cs.position = sp[1]
		cs.rotation.x = sp[2]
		body.add_child(cs)
	gare.add_child(body)
	# Chemin d'accès : dalles de gravier posées sur le relief du parvis à la route (points du POI en coordonnées monde).
	var path: Array = poi.get("path", [])
	if path.size() >= 2:
		var xfs := []
		for i in path.size() - 1:
			var a := Vector2(float(path[i][0]), float(path[i][1]))
			var b := Vector2(float(path[i + 1][0]), float(path[i + 1][1]))
			var n := maxi(int(ceil(a.distance_to(b) / 3.0)), 1)
			var yaw := atan2(b.x - a.x, b.y - a.y)
			for k in n:
				var q := a.lerp(b, (float(k) + 0.5) / float(n))
				var q0 := a.lerp(b, float(k) / float(n))
				var q1 := a.lerp(b, float(k + 1) / float(n))
				var pitch := -atan2(height_at(q1.x, q1.y) - height_at(q0.x, q0.y), q0.distance_to(q1))
				var local := Vector3(q.x - root.position.x, height_at(q.x, q.y) - root.position.y, q.y - root.position.z)
				local = Basis(Vector3.UP, -root.rotation.y) * local
				xfs.append(Transform3D(Basis(Vector3.UP, yaw - root.rotation.y) * Basis.from_euler(Vector3(pitch, 0, 0)), local))
		StreetFurniture._multimesh(root, "CheminGare", StreetFurniture.kit("path_tile"), xfs)


const QUAI_H_VISUAL := 0.8


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


## Décors posés au sol d'un seul point : rayon de leur emprise (m). Sur une pente l'amont serait enterré : on les soulève (voir `_seat_on_slope`).
const LIFT_PROPS := {"fete": 5.5, "stage": 4.5, "pyre": 3.0, "pressoir": 2.5, "wc": 1.8, "stand": 3.0}


## Soulève `n` à la plus haute altitude du terrain sous son emprise (rayon `radius`) et lui donne un socle de terre pour combler le vide en aval.
func _seat_on_slope(n: Node3D, radius: float) -> void:
	var hc := height_at(n.position.x, n.position.z)
	var hmax := hc
	var hmin := hc
	for i in 12:
		var a := TAU * float(i) / 12.0
		for r in [0.5, 1.0]:
			var h := height_at(n.position.x + cos(a) * radius * r, n.position.z + sin(a) * radius * r)
			hmax = maxf(hmax, h)
			hmin = minf(hmin, h)
	var lift := hmax - hc
	if lift < 0.03:
		return
	n.position.y += lift
	n.set_meta("lift", lift)
	# Socle : cylindre de terre sous le décor, qui plonge jusqu'au point le plus bas de l'emprise.
	var depth := (hmax - hmin) + 0.5
	# (un parallélépipède, pas un cylindre : les faisceaux de lieux sont des cylindres et le système de focus les masque)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 1.8, depth, radius * 1.8)
	box.material = _toon(Color(0.55, 0.47, 0.34))
	var mi := MeshInstance3D.new()
	mi.name = "Socle"
	mi.mesh = box
	mi.position.y = -depth * 0.5 + 0.02
	n.add_child(mi)


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
			n.set_meta("poi", p)
			_add_prop(n, p.prop)   # camionnette et voiture sont de vrais véhicules, pas des accessoires
			if LIFT_PROPS.has(str(p.prop)):
				_seat_on_slope(n, float(LIFT_PROPS[str(p.prop)]))
		var color: Color = STEP_COLOR.get(p.step, Color.WHITE)
		# Balise : cylindre translucide visible de loin.
		var beam := CylinderMesh.new()
		beam.top_radius = 0.8; beam.bottom_radius = 0.8; beam.height = 80.0; beam.radial_segments = 12
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(color, 0.45)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam.material = bm
		var bi := MeshInstance3D.new()
		bi.mesh = beam
		bi.position.y = 40.0
		bi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(bi)
		var label := Label3D.new()
		label.text = str(p.label)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.add_to_group("etiquettes")
		label.set_meta("prio", 1)       # un lieu de mission passe avant les noms de passants
		label.fixed_size = true                 # taille constante à l'écran : lisible de loin
		label.font_size = 48
		label.pixel_size = 0.0007
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
	var poi0 = read_json(dir.path_join("poi.json"))
	sign_spots = []
	landmark_buildings = {}
	if poi0 is Dictionary:
		for p in poi0.get("pois", []):
			if p.has("facility") and p.has("building"):
				landmark_buildings[str(p.building)] = p
			if (p.has("building") and p.has("facing")) or p.has("prop"):
				sign_spots.append(Vector2(float(p.position[0]), float(p.position[1])))
	var tiles: Array[Dictionary] = []
	for key in manifest.get("tiles", []):
		var data = read_json(dir.path_join("tiles/%s.json" % key))
		if data is Dictionary:
			register_tile(data)
			tiles.append(data)
	_index_rings(tiles)
	for data in tiles:
		root.add_child(build_tile(data))
	if not tiles.is_empty():
		root.add_child(build_apron())
	var poi = read_json(dir.path_join("poi.json"))
	if poi is Dictionary:
		# Contours de bâtiments et chaussées : le mobilier de commerce ne se pose ni dans un mur ni sur la route.
		var all_rings: Array = []
		var all_roads: Array = []
		var ring_by_id := {}
		for data in tiles:
			for bd in data.buildings:
				var rg := PackedVector2Array()
				for v in bd.footprint:
					rg.append(Vector2(float(v[0]), float(v[1])))
				all_rings.append(rg)
				building_rings.append(rg)
				ring_by_id[str(bd.id)] = rg
			for rd in data.roads:
				if str(rd.kind) in ["footway", "track"]:
					continue
				var pl := PackedVector2Array()
				for v in rd.points:
					pl.append(Vector2(float(v[0]), float(v[1])))
				all_roads.append([pl, float(rd.get("width", 5.0)) / 2.0])
				var ln := 0.0
				for k in range(pl.size() - 1):
					ln += pl[k].distance_to(pl[k + 1])
				road_lines.append({"pts": pl, "width": float(rd.get("width", 5.0)), "kind": str(rd.kind), "len": ln, "sw": float(rd.get("sidewalk", 0.0))})
		root.add_child(_build_road_barriers())
		root.add_child(build_signs(poi.get("pois", []), ring_by_id))
		root.add_child(build_landmarks(poi.get("pois", [])))
		root.add_child(StreetFurniture.build_shops(poi.get("pois", []), height_at, all_rings, all_roads))
		root.add_child(build_mission_markers(poi.get("pois", []), mission_id))
	return root
