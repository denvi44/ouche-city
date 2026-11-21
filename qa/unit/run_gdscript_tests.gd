extends SceneTree
## Tests unitaires GDScript (agent 09). Usage : godot --headless --path game -s ../qa/unit/run_gdscript_tests.gd
## Les scripts du jeu sont chargés dynamiquement (load) pour que les autoloads soient déjà enregistrés.

var _fails := 0
var _count := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, label: String) -> void:
	_count += 1
	if not cond:
		_fails += 1
		printerr("ÉCHEC : ", label)


func _run() -> void:
	var NetScript = load("res://scripts/net/network_manager.gd")
	var Builder = load("res://scripts/world/city_builder.gd")
	var DN = load("res://scripts/world/day_night.gd")
	var Hud = load("res://ui/hud.gd")

	# --- Réseau : arguments et admission ---
	var a: Dictionary = NetScript.parse_args(PackedStringArray(["--server", "--port=9000", "--join=1.2.3.4:5", "x"]))
	check(a.get("server") == true and a.get("port") == "9000" and a.get("join") == "1.2.3.4:5" and a.size() == 3, "parse_args")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION, 1, true) == "", "admission ok")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION + 1, 1, true).begins_with("Version différente"), "refus version")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION, 1, false) != "", "refus solo fermé")
	check(NetScript.check_admission(NetScript.PROTOCOL_VERSION, 16, true) != "", "refus partie pleine")

	# --- Cycle jour/nuit ---
	var noon: Dictionary = DN.sample(12.0)
	var night: Dictionary = DN.sample(23.0)
	check(noon.sun_energy > night.sun_energy, "midi plus lumineux que minuit")
	check(DN.sample(24.0).sun_energy == DN.sample(0.0).sun_energy, "rampe cyclique")
	check(DN.sun_rotation(12.0).x < -0.5, "soleil haut à midi")

	# --- Géométrie de la ville ---
	var sq := PackedVector2Array([Vector2(0, 0), Vector2(0, 10), Vector2(20, 10), Vector2(20, 0)])
	check(absf(Builder.signed_area(sq)) == 200.0, "aire du rectangle")
	var m: Dictionary = Builder.ridge_model(sq, 6.0, "gabled")
	check(is_equal_approx(Builder.roof_height(m, Vector2(10, 5)), 6.0 + 6.0), "faîtage au milieu, pente 1,2")
	check(is_equal_approx(Builder.roof_height(m, Vector2(10, 0)), 6.0), "égout à la hauteur des murs")
	check(Builder.split_ring_at_ridge(sq, m).size() == 6, "deux points de faîtage insérés")
	var flat: Dictionary = Builder.ridge_model(sq, 6.0, "flat")
	check(flat.k == 0.0, "toit plat sans pente")

	var b = Builder.new()
	var tile := {"schemaVersion": 1, "tile": {"x": 0, "y": 0}, "origin": [0, 0], "size": 250,
		"ground": {"resolution": 2, "baseAltitude": 100.0, "heights": [0.0, 10.0, 0.0, 10.0]},
		"buildings": [{"id": "b_1", "footprint": [[10, 10], [10, 20], [30, 20], [30, 10]], "height": 7.0, "roof": "gabled", "typology": "colombages", "groundZ": 0.0},
			{"id": "b_2", "footprint": [[50, 50], [50, 70], [70, 70], [70, 50]], "height": 18.0, "roof": "spire", "typology": "eglise", "groundZ": 0.0}],
		"roads": [{"id": "r_1", "name": "Rue Test", "kind": "residential", "points": [[0, 100], [250, 100]], "width": 5.0, "sidewalk": 1.2}],
		"vegetation": [{"kind": "park", "polygon": [[100, 150], [100, 200], [150, 200], [150, 150]]}],
		"trees": [[120, 170]], "attribution": ["test"]}
	b.register_tile(tile)
	check(is_equal_approx(b.height_at(125.0, 50.0), 5.0), "relief bilinéaire au centre")
	check(absf(b.height_at(-50.0, 10.0)) < 0.05 and absf(b.height_at(400.0, 10.0) - 10.0) < 0.05, "relief prolongé hors tuile")
	var node: Node3D = b.build_tile(tile)
	var bat := node.get_node_or_null("Batiments") as MeshInstance3D
	check(bat != null and bat.mesh.get_surface_count() >= 3, "bâtiments : murs + toits par matériau")
	check(node.get_node_or_null("Collisions") != null and node.get_node("Collisions").get_child_count() >= 2, "collisions bâtiments + terrain")
	check(node.get_node_or_null("Sol") != null, "routes et végétation")
	check(node.get_node_or_null("Arbres") != null, "arbres")
	# Murs tournés vers l'extérieur : la normale d'un mur pointe hors de l'emprise.
	var arrays: Array = bat.mesh.surface_get_arrays(_surface(bat.mesh, "colombages"))
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var outward := true
	for i in verts.size():
		var c := Vector3(20, verts[i].y, 15)
		if normals[i].dot(verts[i] - c) <= 0.0:
			outward = false
	check(outward, "normales des murs vers l'extérieur")
	# Faces avant dans le sens horaire (convention Godot) vues depuis la normale.
	var cw := true
	for t in range(0, verts.size(), 3):
		if (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).dot(normals[t]) > 0.0:
			cw = false
	check(cw, "triangles des murs dans le sens horaire")
	node.free()

	# --- Ville réelle importée ---
	var manifest: Dictionary = Builder.load_manifest()
	check(manifest.get("tiles", []).size() > 0, "manifeste de la ville présent")
	var credit: String = Hud.map_credit(manifest)
	check("IGN" in credit or "OpenStreetMap" in credit, "mention des sources")

	# --- Personnage articulé ---
	var CM = load("res://scripts/player/character_model.gd")
	var cm = CM.make(Color(0.8, 0.2, 0.2))
	root.add_child(cm)
	var limbs := 0
	for n in ["Bassin"]:
		check(cm.get_node_or_null(n) != null, "bassin présent")
	var bassin: Node3D = cm.get_node("Bassin")
	for c in bassin.get_children():
		if c is Node3D and not (c is MeshInstance3D) and c.name != "Tronc":
			limbs += 1       # 2 jambes
	for c in bassin.get_node("Tronc").get_children():
		if c is Node3D and not (c is MeshInstance3D) and c.name != "Tete":
			limbs += 1       # 2 bras
	check(limbs == 4, "deux bras et deux jambes (%d membres)" % limbs)
	for i in 30:
		cm.animate(1.0 / 60.0, 0.0)
	check(absf(cm.leg_angle_l) < 0.05, "au repos : jambes droites")
	var max_leg := 0.0
	var arm_opposed := true
	for i in 120:
		cm.animate(1.0 / 60.0, 4.2)
		max_leg = maxf(max_leg, absf(cm.leg_angle_l))
		var leg_r: float = bassin.get_child(1).rotation.x
		if absf(cm.leg_angle_l) > 0.2 and cm.leg_angle_l * leg_r > 0.0:
			arm_opposed = false
	check(max_leg > 0.35, "marche : les jambes balancent (%.2f rad)" % max_leg)
	check(arm_opposed, "marche : les jambes sont en opposition")
	cm.carrying = true
	for i in 90:
		cm.animate(1.0 / 60.0, 0.0)
	check(cm.arm_angle_l < -2.8, "portage : bras levés (%.2f rad)" % cm.arm_angle_l)
	cm.carrying = false
	cm.airborne = true
	for i in 60:
		cm.animate(1.0 / 60.0, 3.0)
	check(cm.leg_angle_l < -0.5, "saut : jambe gauche repliée (%.2f rad)" % cm.leg_angle_l)
	cm.free()

	# --- Audio : synthèse ---
	var synth_names := ["klaxon", "engine_loop", "tractor_loop", "thud", "glass", "crate", "moo", "chime", "fail", "fanfare", "step", "radio_blip", "bell", "wind_loop", "bird"]
	for n in synth_names:
		var smp: PackedFloat32Array = Callable(Synth, n).call()
		var peak := 0.0
		var rms := 0.0
		for v in smp:
			peak = maxf(peak, absf(v))
			rms += v * v
		rms = sqrt(rms / smp.size())
		check(smp.size() > 100 and peak <= 1.0 and peak > 0.3 and rms > 0.02, "son « %s » : %.2f s, pic %.2f, rms %.2f" % [n, smp.size() / 22050.0, peak, rms])
	var kl: PackedFloat32Array = Synth.klaxon()
	var g392 := _goertzel(kl, 392.0)
	check(g392 > 4.0 * _goertzel(kl, 700.0) and _goertzel(kl, 494.0) > 4.0 * _goertzel(kl, 700.0), "klaxon : énergie à 392 et 494 Hz (tierce), pas à 700 Hz")
	var eng: PackedFloat32Array = Synth.engine_loop()
	check(absf(eng[0] - eng[eng.size() - 1]) < 0.1, "moteur : boucle sans clic (écart %.3f)" % absf(eng[0] - eng[eng.size() - 1]))
	var wd: PackedFloat32Array = Synth.wind_loop()
	check(absf(wd[0] - wd[wd.size() - 1]) < 0.1, "vent : boucle sans couture (écart %.3f)" % absf(wd[0] - wd[wd.size() - 1]))
	var mu: PackedFloat32Array = Synth.music_pommier()
	check(absf(mu.size() / 22050.0 - Synth.music_length()) < 0.05, "musique : %.1f s (8 mesures à 3 temps)" % (mu.size() / 22050.0))
	var bar_len := int(mu.size() / Synth.BARS)
	var quiet_bars := 0
	for bar in Synth.BARS:
		var e := 0.0
		for i in range(bar * bar_len, (bar + 1) * bar_len):
			e += mu[i] * mu[i]
		if sqrt(e / bar_len) < 0.05:
			quiet_bars += 1
	check(quiet_bars == 0, "musique : aucune mesure silencieuse")
	var wav: AudioStreamWAV = Synth.to_stream(eng, true)
	check(wav.data.size() == eng.size() * 2 and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.mix_rate == 22050, "flux WAV 16 bits mono, bouclé")
	var Amb = load("res://scripts/audio/ambiance.gd")
	check(Amb.strikes_for(3) == 3 and Amb.strikes_for(15) == 3 and Amb.strikes_for(12) == 4 and Amb.strikes_for(0) == 4, "cloches : un coup par heure, plafonné à 4")
	var caps := [["[Klaxon]", 5.0], ["[Meuglement]", 2.0]]
	check(Hud.caption_text(caps, 3.0) == "[Klaxon]" and Hud.caption_text(caps, 1.0) == "[Klaxon]\n[Meuglement]" and Hud.caption_text(caps, 9.0) == "", "sous-titres : expiration")
	var sfx = root.get_node("Sfx")
	var heard := []
	sfx.caption.connect(func(t, _d): heard.append(t))
	sfx.play("klaxon")
	check(sfx.counts.get("klaxon", 0) == 1 and heard == ["[Klaxon]"], "Sfx : le klaxon est journalisé et sous-titré")
	sfx.play("step")
	check(heard == ["[Klaxon]"], "Sfx : un pas n'a pas de sous-titre")
	check(sfx.stream_for("moo") is AudioStreamWAV and sfx.stream_for("inconnu") == null, "Sfx : flux synthétisés en cache")

	# --- Façades : portes et fenêtres peintes ---
	var tile2 := {"schemaVersion": 1, "tile": {"x": 0, "y": 0}, "origin": [0, 0], "size": 250,
		"ground": {"resolution": 2, "baseAltitude": 0.0, "heights": [0.0, 0.0, 0.0, 0.0]},
		"buildings": [
			{"id": "b_10", "footprint": [[10, 10], [10, 20], [30, 20], [30, 10]], "height": 7.0, "roof": "flat", "typology": "brique", "groundZ": 0.0},
			{"id": "b_11", "footprint": [[60, 10], [60, 14], [66, 14], [66, 10]], "height": 3.0, "roof": "flat", "typology": "annexe", "groundZ": 0.0},
			{"id": "b_12", "footprint": [[100, 10], [100, 20], [120, 20], [120, 10]], "height": 7.0, "roof": "flat", "typology": "commerce", "groundZ": 0.0}],
		"roads": [{"id": "r_1", "name": "Rue Test", "kind": "residential", "points": [[0, 100], [250, 100]], "width": 5.0, "sidewalk": 1.2}],
		"vegetation": [], "trees": [], "attribution": ["test"]}
	var b2 = Builder.new()
	b2.register_tile(tile2)
	var node2: Node3D = b2.build_tile(tile2)
	var bm := (node2.get_node("Batiments") as MeshInstance3D).mesh as ArrayMesh
	var info := {}
	for si in bm.get_surface_count():
		var nm := bm.surface_get_name(si)
		var arr: Array = bm.surface_get_arrays(si)
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var doors := 0
		var detail_walls := 0
		for t in range(0, cols.size() - 2, 3):
			if cols[t].a > 0.0 and cols[t].g > 0.0:
				detail_walls += 1
			if cols[t].b > 0.4:
				doors += 1
				info[nm + "_door_z"] = (vs[t].z + vs[t + 1].z + vs[t + 2].z) / 3.0
		info[nm + "_doors"] = doors / 2     # deux triangles par mur
		info[nm + "_detail"] = detail_walls / 2
	check(info.get("facade_brique_doors", 0) == 1, "maison : une seule porte")
	check(absf(info.get("facade_brique_door_z", -1.0) - 20.0) < 0.1, "maison : porte sur le mur côté rue (z = 20, rue à z = 100)")
	check(info.get("facade_brique_detail", 0) == 4, "maison : 4 murs avec fenêtres")
	check(info.get("facade_commerce_doors", 0) == 1, "commerce : porte + vitrine sur un mur")
	check(not info.has("crepi_pavillon_doors") or info.get("crepi_pavillon_doors", 0) == 0, "annexe : pas de porte")
	check(info.get("crepi_pavillon_detail", 0) == 0, "annexe : aucun détail de façade")
	node2.free()

	# --- Navigation piétonne (graphe routier) ---
	var RN = load("res://scripts/ai/road_nav.gd")
	var nav = RN.load_default()
	check(nav.point_count() > 5000, "graphe routier densifié (%d points)" % nav.point_count())
	var from_pt := Vector2(1399.0, 1462.0)       # rue Sainte-Foy
	var to_pt := Vector2(1419.7, 1564.5)       # camionnette
	var path: PackedVector2Array = nav.find_path(from_pt, to_pt)
	var straight := from_pt.distance_to(to_pt)
	var plen: float = RN.length_of(path)
	check(path.size() >= 3 and path[0] == from_pt and path[path.size() - 1] == to_pt, "chemin : départ, rues, arrivée (%d points)" % path.size())
	check(plen >= straight - 0.01 and plen < straight * 2.5, "chemin raisonnable : %.0f m pour %.0f m à vol d'oiseau" % [plen, straight])
	var gap := 0.0
	for i in range(path.size() - 1):
		gap = maxf(gap, path[i].distance_to(path[i + 1]))
	check(gap < 12.0, "pas de segment de plus de 12 m (%.1f m)" % gap)
	var empty = RN.new()
	var direct: PackedVector2Array = empty.find_path(from_pt, to_pt)
	check(direct.size() == 2, "sans graphe : ligne droite")

	print("%d tests, %d échec(s)" % [_count, _fails])
	quit(1 if _fails > 0 else 0)


## Énergie d'un échantillon à la fréquence `f` (algorithme de Goertzel, amplitude relative).
func _goertzel(a: PackedFloat32Array, f: float) -> float:
	var w := TAU * f / 22050.0
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for v in a:
		var s0 := v + c * s1 - s2
		s2 = s1
		s1 = s0
	return sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / a.size()


func _surface(mesh: ArrayMesh, name: String) -> int:
	for i in mesh.get_surface_count():
		if mesh.surface_get_name(i) == name:
			return i
	return 0
