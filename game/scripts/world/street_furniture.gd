class_name StreetFurniture
extends RefCounted
## Mobilier de rue posé automatiquement (agent 04) : lampadaires le long des routes carrossables, bancs, jardinières et
## bornes devant les commerces. Déterministe (aucun hasard non semé), instancié en MultiMesh : un appel de dessin par
## accessoire et par tuile.

const LAMP_SPACING := 46.0
const KINDS := ["secondary", "tertiary", "residential", "primary", "service"]

static var _kits := {}


static func kit(name: String) -> PropKit:
	if not _kits.has(name):
		_kits[name] = Callable(PropKit, name).call()
	return _kits[name]


static func _inside_building(p: Vector2, rings: Array) -> bool:
	for ring in rings:
		var poly: PackedVector2Array = ring
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	return false


## Points de pose des lampadaires d'une tuile : [Transform3D, ...] (cap vers la chaussée).
static func lamp_spots(data: Dictionary, height_at: Callable) -> Array:
	var rings := []
	for b in data.buildings:
		var ring := PackedVector2Array()
		for v in b.footprint:
			ring.append(Vector2(v[0], v[1]))
		rings.append(ring)
	var out := []
	var side := 1.0
	for r in data.roads:
		if not (r.kind in KINDS):
			continue
		var pts := PackedVector2Array()
		for v in r.points:
			pts.append(Vector2(v[0], v[1]))
		var carry := LAMP_SPACING * 0.5
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var seg := a.distance_to(b)
			if seg < 0.01:
				continue
			var dir := (b - a) / seg
			var normal := Vector2(-dir.y, dir.x)
			var d := carry
			while d < seg:
				var p := a + dir * d
				var off := normal * side * (float(r.width) / 2.0 + 1.1)
				var q := p + off
				var ok := not _inside_building(q, rings)
				for k in 4:
					var probe := q + Vector2.from_angle(k * PI / 2.0) * 0.9
					ok = ok and not _inside_building(probe, rings)
				if ok:
					var to_road := -off.normalized()
					var yaw := atan2(to_road.x, to_road.y)
					out.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, height_at.call(q.x, q.y), q.y)))
				side = -side
				d += LAMP_SPACING
			carry = d - seg
	return out


static func _multimesh(root: Node3D, name: String, k: PropKit, xfs: Array) -> void:
	if xfs.is_empty():
		return
	for pass_name in ["Corps", "Contour"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = k.mesh() if pass_name == "Corps" else k.outline_mesh()
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mi := MultiMeshInstance3D.new()
		mi.name = "%s_%s" % [name, pass_name]
		mi.multimesh = mm
		if pass_name == "Contour":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


## Mobilier d'une tuile : lampadaires. (Les commerces ont le leur : `shop_furniture`.)
static func build_tile(data: Dictionary, height_at: Callable) -> Node3D:
	var root := Node3D.new()
	root.name = "Mobilier"
	_multimesh(root, "Lampadaires", kit("lamp"), lamp_spots(data, height_at))
	return root


## Devant chaque commerce (POI portant `building` et `facing`, genre « shop ») : deux jardinières de part et d'autre de
## la porte, un banc pour un commerce sur trois et une borne à chaque extrémité.
static func shop_spots(pois: Array, height_at: Callable) -> Dictionary:
	var out := {"planter": [], "bench": [], "bollard": []}
	var n := 0
	for p in pois:
		if p.get("kind", "") != "shop" or not p.has("facing") or p.has("prop"):
			continue
		var x := float(p.position[0])
		var z := float(p.position[1])
		var f := float(p.facing)
		var fwd := Vector2(sin(f), cos(f))
		var side := Vector2(fwd.y, -fwd.x)
		var yaw := Basis(Vector3.UP, f)
		for s in [-1.0, 1.0]:
			var q: Vector2 = Vector2(x, z) + fwd * 0.45 + side * s * 1.7
			out.planter.append(Transform3D(yaw, Vector3(q.x, height_at.call(q.x, q.y), q.y)))
			var c: Vector2 = Vector2(x, z) + fwd * 1.0 + side * s * 3.4
			out.bollard.append(Transform3D(yaw, Vector3(c.x, height_at.call(c.x, c.y), c.y)))
		if n % 3 == 0:
			var q2 := Vector2(x, z) + fwd * 1.1 + side * 4.6
			out.bench.append(Transform3D(yaw, Vector3(q2.x, height_at.call(q2.x, q2.y), q2.y)))
		n += 1
	return out


static func build_shops(pois: Array, height_at: Callable) -> Node3D:
	var root := Node3D.new()
	root.name = "MobilierCommerces"
	var spots := shop_spots(pois, height_at)
	for name in spots:
		_multimesh(root, name.capitalize(), kit(name), spots[name])
	return root
