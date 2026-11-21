extends SceneTree
## Décors de mission et mobilier de commerce : rien ne traverse un mur ni ne bloque la chaussée.
## Pour chaque décor (POI portant `prop`) : l'emprise réelle de ses maillages (jusqu'à 4 m de haut) est échantillonnée au pas de 40 cm ;
## on compte les points dans un bâtiment et ceux sur la chaussée. Même contrôle pour les bancs, jardinières et bornes devant les commerces.
## Usage : godot --headless --path game -s ../qa/integration/props_audit.gd [-- --verbose]
const CITY := "res://assets/city"
const ON_ROAD_OK := ["barrier", "strip", "rail", "van", "car", "gare", "pond", "carriere", "pen"]   # décors faits pour la chaussée ou hors village
var fails := 0
var rings: Array = []
var roads: Array = []      # [PackedVector2Array, demi-largeur]


func check(ok: bool, label: String) -> void:
	if ok and OS.get_cmdline_user_args().has("--verbose") == false:
		return
	print(("  ok  " if ok else "  ÉCHEC  ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


func _in_building(p: Vector2, margin: float) -> bool:
	for ring: PackedVector2Array in rings:
		if Geometry2D.is_point_in_polygon(p, ring):
			return true
		if margin > 0.0:
			for i in ring.size():
				var a := ring[i]
				var b := ring[(i + 1) % ring.size()]
				if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < margin:
					return true
	return false


func _on_road(p: Vector2, slack: float) -> bool:
	for r in roads:
		var pts: PackedVector2Array = r[0]
		for i in pts.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p) < float(r[1]) - slack:
				return true
	return false


func _boxes(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var bb: AABB = (n as MeshInstance3D).mesh.get_aabb()
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for i in 8:
			var c: Vector3 = t * bb.get_endpoint(i)
			lo = lo.min(c)
			hi = hi.max(c)
		if lo.y < 4.0 and hi.y > 0.15:
			acc.append(AABB(lo, hi - lo))
	for c in n.get_children():
		_boxes(c, t, acc)


func _run() -> void:
	var manifest = CityBuilder.read_json(CITY + "/manifest.json")
	for key in manifest.tiles:
		var t = CityBuilder.read_json(CITY + "/tiles/%s.json" % key)
		for b in t.buildings:
			var ring := PackedVector2Array()
			for q in b.footprint:
				ring.append(Vector2(float(q[0]), float(q[1])))
			rings.append(ring)
		for r in t.roads:
			if str(r.kind) in ["footway", "track"]:
				continue
			var pts := PackedVector2Array()
			for q in r.points:
				pts.append(Vector2(float(q[0]), float(q[1])))
			roads.append([pts, float(r.get("width", 5.0)) / 2.0])
	var builder := CityBuilder.new()
	builder.build_city(CITY, "")
	var pois: Array = CityBuilder.read_json(CITY + "/poi.json").pois
	var n_props := 0
	for p in pois:
		if not p.has("prop") or str(p.prop) in ["carriere", "gare", "rail", "pond", "supermarket"]:
			continue
		n_props += 1
		var node := Node3D.new()
		builder._add_prop(node, str(p.prop))
		var acc: Array = []
		_boxes(node, Transform3D.IDENTITY, acc)
		var pos := Vector2(float(p.position[0]), float(p.position[1]))
		var bas := Basis(Vector3.UP, float(p.get("facing", 0.0)))
		var hit_b := 0
		var hit_r := 0
		var total := 0
		for bb: AABB in acc:
			var x := bb.position.x
			while x <= bb.end.x + 0.001:
				var z := bb.position.z
				while z <= bb.end.z + 0.001:
					var q: Vector3 = bas * Vector3(x, 0, z)
					var w := pos + Vector2(q.x, q.z)
					total += 1
					if _in_building(w, 0.0):
						hit_b += 1
					if not (str(p.prop) in ON_ROAD_OK) and _on_road(w, 0.3):
						hit_r += 1
					z += 0.4
				x += 0.4
		check(hit_b == 0 and hit_r == 0, "décor %s (%s) : %d points dans un bâtiment, %d sur la chaussée (sur %d)" % [p.id, p.prop, hit_b, hit_r, total])
		node.free()
	# Mobilier de commerce.
	var spots: Dictionary = StreetFurniture.shop_spots(pois, builder.height_at, rings, roads)
	for kind in spots:
		var bad := 0
		for xf: Transform3D in spots[kind]:
			var c := Vector2(xf.origin.x, xf.origin.z)
			var side := Vector2(xf.basis.x.x, xf.basis.x.z).normalized()
			var half := 0.9 if kind == "bench" else 0.5
			for s in [-1.0, 0.0, 1.0]:
				var q: Vector2 = c + side * s * half
				if _in_building(q, 0.2) or _on_road(q, 0.1):
					bad += 1
					break
		check(bad == 0, "mobilier « %s » : %d sur %d dans un mur ou sur la chaussée" % [kind, bad, spots[kind].size()])
	check(n_props >= 12, "%d décors audités" % n_props)
	print("--- props_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
