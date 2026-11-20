extends SceneTree
## Captures automatiques de la scène témoin (agent 09).
## Usage : godot --path game -s ../qa/screenshots/capture.gd -- --viewer [--out=DIR] [--compat]
## Produit <viewpoint>_<HH>h_<os>[_compat].png en 1920×1080.

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"

var _world: Node3D
var _cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _qa_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()


func _run() -> void:
	print("[captures] démarrage")
	# Garde-fou : on ne bloque jamais la CI.
	create_timer(600.0).timeout.connect(func(): push_error("[captures] délai dépassé"); quit(2))
	var args: Dictionary = load("res://scripts/net/network_manager.gd").parse_args(OS.get_cmdline_user_args())
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_qa_path("qa/screenshots/viewpoints.json")))
	var date := Time.get_date_string_from_system()
	var out_dir: String = args.get("out", _qa_path("qa/screenshots/out/" + date))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var res: Array = cfg.resolution
	root.size = Vector2i(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(root.size)
	var compat := RenderingServer.get_current_rendering_method() != "forward_plus"
	var suffix := "_compat" if compat else ""
	var os_name := OS.get_name().to_lower()

	_world = load(WORLD).instantiate()
	root.add_child(_world)
	current_scene = _world
	await _frames(5)
	var dn: DayNight = _world.day_night
	dn.running = false
	_cam = Camera3D.new()
	_cam.fov = 65.0
	_cam.far = 2000.0
	_cam.add_child(load("res://scripts/player/camera_rig.gd").make_outline_quad())
	_world.add_child(_cam)
	_cam.make_current()

	var pois := {}
	var facings := {}
	var poi_data = CityBuilder.read_json("res://assets/city/poi.json")
	if poi_data is Dictionary:
		for p in poi_data.pois:
			pois[p.id] = Vector2(p.position[0], p.position[1])
			if p.has("facing"):
				facings[p.id] = float(p.facing)
	var builder: CityBuilder = _world.builder
	# Deux figurants dans la rue Sainte-Foy (contours des personnages, échelle).
	var street := _road_points("Rue Sainte-Foy")
	if street.size() >= 3:
		var k := mini(3, street.size() - 1)
		for i in 2:
			var p2: Vector2 = street[k].lerp(street[k + 1] if k + 1 < street.size() else street[k], 0.3) + Vector2(i * 1.6 - 0.8, 0)
			var fig = _world._spawn(100 + i, ["Gégé", "Ginette"][i], Vector3(p2.x, builder.height_at(p2.x, p2.y) + 0.05, p2.y))
			fig.facing = PI * 0.5 * (1 - 2 * i)
	await _frames(3)
	var done := 0
	for vp in cfg.viewpoints:
		var pose = _pose(vp, pois, builder, facings)
		if pose == null:
			print("[captures] %s ignoré : hors des tuiles chargées" % vp.id)
			continue
		_cam.look_at_from_position(pose[0], pose[1], Vector3.UP)
		for h in cfg.hours:
			dn.hour = float(h)
			dn.apply()
			await _frames(8)
			var img := root.get_texture().get_image()
			var path := out_dir.path_join("%s_%02dh_%s%s.png" % [vp.id, int(h), os_name, suffix])
			img.save_png(path)
			done += 1
			print("[captures] ", path)
	print("[captures] %d images" % done)
	root.get_node("Net").leave()
	quit(0 if done > 0 else 1)


func _pose(vp: Dictionary, pois: Dictionary, b: CityBuilder, facings: Dictionary = {}):
	if vp.type == "sign":
		if not pois.has(vp.anchor) or not facings.has(vp.anchor):
			return null
		var s: Vector2 = pois[vp.anchor]
		var f: float = facings[vp.anchor]
		var dir := Vector2(sin(f), cos(f))
		var eye: Vector2 = s + dir * float(vp.distance)
		return [Vector3(eye.x, b.height_at(eye.x, eye.y) + float(vp.eyeHeight), eye.y), Vector3(s.x, b.height_at(s.x, s.y) + float(vp.get("lookHeight", 3.0)), s.y)]
	if vp.type == "anchor":
		if not pois.has(vp.anchor) or not b.bounds.grow(-1.0).has_point(pois[vp.anchor]):
			return null
		var a: Vector2 = pois[vp.anchor]
		var base := Vector3(a.x, b.height_at(a.x, a.y), a.y)
		var o: Array = vp.offset
		var l: Array = vp.lookOffset
		return [base + Vector3(o[0], o[1], o[2]), base + Vector3(l[0], l[1], l[2])]
	if vp.type == "along_road":
		var pts := _road_points(vp.road)
		if pts.size() < 2:
			return null
		var start: Vector2 = pts[0]
		var ahead := start
		var dist := 0.0
		for i in range(1, pts.size()):
			dist += pts[i].distance_to(pts[i - 1])
			ahead = pts[i]
			if dist >= float(vp.lookAhead):
				break
		var eye := float(vp.eyeHeight)
		return [Vector3(start.x, b.height_at(start.x, start.y) + eye, start.y),
			Vector3(ahead.x, b.height_at(ahead.x, ahead.y) + eye, ahead.y)]
	return null


func _road_points(name: String) -> PackedVector2Array:
	var want := _norm(name)
	var best := PackedVector2Array()
	var manifest := CityBuilder.load_manifest()
	for key in manifest.get("tiles", []):
		var t = CityBuilder.read_json("res://assets/city/tiles/%s.json" % key)
		for r in t.roads:
			if r.name != null and _norm(r.name) == want and r.points.size() > best.size():
				best = CityBuilder.to_ring(r.points)
	return best


static func _norm(s: String) -> String:
	return s.to_lower().replace("-", " ").replace("é", "e").replace("è", "e").strip_edges()


func _frames(n: int) -> void:
	for i in n:
		await process_frame
