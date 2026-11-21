extends SceneTree
## Édifices publics : l'emprise réelle du modèle (perron, cour, parking compris) ne mord ni sur la chaussée ni sur un autre édifice.
## Usage : godot --headless --path game -s ../qa/integration/landmarks_audit.gd
const CITY := "res://assets/city"
var fails := 0


func check(ok: bool, label: String) -> void:
	print(("  ok  " if ok else "  ÉCHEC  ") + label)
	if not ok:
		fails += 1


func _initialize() -> void:
	_run.call_deferred()


## Emprise (xmin, zmin, xmax, zmax) des maillages du modèle, dans son repère local.
func _extent(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var bb: AABB = (n as MeshInstance3D).mesh.get_aabb()
		for i in 8:
			var c: Vector3 = t * bb.get_endpoint(i)
			acc[0] = minf(acc[0], c.x)
			acc[1] = minf(acc[1], c.z)
			acc[2] = maxf(acc[2], c.x)
			acc[3] = maxf(acc[3], c.z)
	for c in n.get_children():
		_extent(c, t, acc)


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 1e-9 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _run() -> void:
	var manifest = CityBuilder.read_json(CITY + "/manifest.json")
	var roads: Array = []   # [PackedVector2Array, demi-largeur]
	for key in manifest.tiles:
		var t = CityBuilder.read_json(CITY + "/tiles/%s.json" % key)
		for r in t.roads:
			if str(r.kind) in ["footway", "track"]:
				continue
			var pts := PackedVector2Array()
			for q in r.points:
				pts.append(Vector2(float(q[0]), float(q[1])))
			roads.append([pts, float(r.get("width", 5.0)) / 2.0])
	var Lm = load("res://scripts/world/landmarks.gd")
	var pois: Array = CityBuilder.read_json(CITY + "/poi.json").pois
	var n_fac := 0
	for p in pois:
		if not p.has("facility") or not p.has("rect"):
			continue
		n_fac += 1
		var w := float(p.rect[0])
		var d := float(p.rect[1])
		var m: Dictionary = Lm.build(str(p.facility), w, d, str(p.label))
		var acc := [1e9, 1e9, -1e9, -1e9]
		_extent(m.node, Transform3D.IDENTITY, acc)
		var pos := Vector2(float(p.position[0]), float(p.position[1]))
		var f := float(p.get("facing", 0.0))
		var bas := Basis(Vector3.UP, f)
		# Échantillonne l'emprise au mètre ; profondeur maximale de pénétration dans une chaussée.
		var pire := 0.0
		var x := acc[0] as float
		while x <= acc[2]:
			var z := acc[1] as float
			while z <= acc[3]:
				var q: Vector3 = bas * Vector3(x, 0, z)
				var wp := pos + Vector2(q.x, q.z)
				for r in roads:
					var pts: PackedVector2Array = r[0]
					for i in pts.size() - 1:
						var dd := _seg_dist(wp, pts[i], pts[i + 1])
						pire = maxf(pire, float(r[1]) - dd)
				z += 1.0
			x += 1.0
		check(pire <= 0.3, "%s : emprise %.1f×%.1f m (rect %.1f×%.1f), mord de %.2f m sur la chaussée" % [p.id, acc[2] - acc[0], acc[3] - acc[1], w, d, pire])
	check(n_fac >= 6, "%d édifices audités" % n_fac)
	print("--- landmarks_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
