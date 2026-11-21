extends SceneTree
## Chaussées : le relief ne doit jamais affleurer à travers une route (bandes d'herbe qui coupent l'asphalte).
## Pour chaque route carrossable, on échantillonne la surface du ruban (plan entre les quatre coins de chaque tronçon) et on compare au terrain :
## on compte les points où le terrain dépasse la route de plus de 3 cm. Usage : godot --headless --path game -s ../qa/integration/roads_cover_audit.gd
const CITY := "res://assets/city"


func _initialize() -> void:
	_run.call_deferred()


func _measure(builder: CityBuilder, tiles: Array, step: float) -> Array:
	var bad := 0
	var total := 0
	var worst := 0.0
	for t in tiles:
		for r in t.roads:
			if str(r.kind) in ["footway", "track", "pedestrian", "steps"]:
				continue
			var pts := PackedVector2Array()
			for q in r.points:
				pts.append(Vector2(float(q[0]), float(q[1])))
			if step > 0.0:
				pts = CityBuilder.densify(pts, step)
			var half := float(r.width) * 0.5
			for i in pts.size() - 1:
				var a := pts[i]
				var b := pts[i + 1]
				var seg := a.distance_to(b)
				if seg < 0.05:
					continue
				var d := (b - a) / seg
				var perp := Vector2(-d.y, d.x)
				var corners: Array = []
				var sw := float(r.get("sidewalk", 0.0))
				for c in [[a, 1.0], [a, -1.0], [b, -1.0], [b, 1.0]]:
					var p: Vector2 = c[0] + perp * half * float(c[1])
					var hh: float = builder.height_at(p.x, p.y) if step <= 0.0 else builder.rung_height(c[0], perp, half + sw)
					corners.append(Vector3(p.x, hh + CityBuilder.Y_ROUTE, p.y))
				var n_t := maxi(int(seg), 1)
				for ti in range(n_t + 1):
					var tt := float(ti) / float(n_t)
					for ui in 5:
						var uu := float(ui) / 4.0
						# coins : 0 = a+perp, 1 = a-perp, 2 = b-perp, 3 = b+perp
						var pa: Vector3 = (corners[0] as Vector3).lerp(corners[1], uu)
						var pb: Vector3 = (corners[3] as Vector3).lerp(corners[2], uu)
						var plane: Vector3 = pa.lerp(pb, tt)
						total += 1
						var ter := builder.height_at(plane.x, plane.z)
						if ter - plane.y > 0.03:
							bad += 1
							worst = maxf(worst, ter - plane.y)
	return [bad, total, worst]


func _run() -> void:
	var builder := CityBuilder.new()
	builder.build_city(CITY, "")
	var manifest = CityBuilder.load_manifest()
	var tiles: Array = []
	for key in manifest.tiles:
		tiles.append(CityBuilder.read_json(CITY + "/tiles/%s.json" % key))
	var raw := _measure(builder, tiles, 0.0)
	print("ROADS brut (sans densification) : %d / %d points affleurent (pire %.2f m)" % [raw[0], raw[1], raw[2]])
	var dense := _measure(builder, tiles, CityBuilder.RIBBON_STEP)
	var pct := 100.0 * float(dense[0]) / maxf(float(dense[1]), 1.0)
	print("ROADS densifié (%.1f m) : %d / %d points affleurent (%.2f %%, pire %.2f m)" % [CityBuilder.RIBBON_STEP, dense[0], dense[1], pct, dense[2]])
	var ok: bool = pct < 0.3 and float(dense[2]) < 0.25
	print(("  ok  " if ok else "  ÉCHEC  ") + "le relief n'affleure pas à travers les chaussées")
	print("--- roads_cover_audit : ", "OK" if ok else "1 échec(s)")
	quit(0 if ok else 1)
