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

	# --- Progression sauvegardée (contrat save.schema.json) ---
	var PG = load("res://scripts/core/progress.gd")
	var pr = PG.new()
	pr.path = "user://test_progress.json"
	pr.persist = true
	pr.data = PG.fresh()
	check(PG.is_valid(pr.data), "sauvegarde neuve : clés du contrat présentes")
	check(not PG.is_valid({"money": 5}) and not PG.is_valid("x"), "sauvegarde incomplète refusée")
	pr.add_money(420)
	pr.complete("m01_calva_gege", "silver", {"comite_fetes": 1}, ["m02_tuning_samedi"], [])
	check(pr.money() == 420 and pr.is_done("m01_calva_gege") and pr.medal_of("m01_calva_gege") == "silver", "mission terminée : argent 420, médaille argent")
	check(pr.mission_state("m02_tuning_samedi") == "available" and pr.data.reputation.comite_fetes == 1, "mission 2 débloquée, réputation +1")
	pr.complete("m01_calva_gege", "bronze")
	check(pr.medal_of("m01_calva_gege") == "silver", "on garde la meilleure médaille")
	pr.complete("m01_calva_gege", "gold")
	check(pr.medal_of("m01_calva_gege") == "gold", "une meilleure médaille remplace l'ancienne")
	pr.add_money(-9999)
	check(pr.money() == 0, "l'argent ne devient jamais négatif")
	pr.add_money(420)
	pr.save()
	var pr2 = PG.new()
	pr2.path = "user://test_progress.json"
	pr2.persist = true
	pr2.load_save()
	check(pr2.money() == 420 and pr2.is_done("m01_calva_gege") and pr2.is_available("m02_tuning_samedi", ["m01_calva_gege"]), "sauvegarde relue à l'identique")
	var st_ok := true
	for k in pr2.data.missions:
		var ms: Dictionary = pr2.data.missions[k]
		st_ok = st_ok and ms.state in ["locked", "available", "in_progress", "done"] and (ms.medal == null or ms.medal in ["gold", "silver", "bronze"])
	check(st_ok and pr2.data.money is int or pr2.data.money is float, "états et médailles conformes au contrat")
	check(not pr2.is_available("m09_inconnue", ["m02_tuning_samedi"]), "mission dont les prérequis ne sont pas finis : verrouillée")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_progress.json"))
	pr.free()
	pr2.free()

	# --- Audio : synthèse ---
	var synth_names := ["klaxon", "engine_loop", "tractor_loop", "thud", "glass", "crate", "moo", "chime", "fail", "fanfare", "step", "radio_blip", "bell", "wind_loop", "bird", "bark", "sizzle", "firework", "whistle"]
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
	# Playlists de la battle de sono : 8 s, grosse caisse sur chaque temps, trois boucles différentes.
	var tracks := {}
	for id in Synth.TRACK_IDS:
		tracks[id] = Synth.track(id)
		check(absf(tracks[id].size() / 22050.0 - Synth.track_length()) < 0.05, "playlist %s : %.1f s" % [id, tracks[id].size() / 22050.0])
		var on_beat := 0.0
		var between := 0.0
		for tb in Synth.TRACK_BEATS:
			var i0 := int(tb * Synth.BEAT_T() * 22050.0)
			for k in 600:
				on_beat += absf(tracks[id][i0 + k])
				between += absf(tracks[id][i0 + int(0.3 * 22050.0) + k]) if i0 + int(0.3 * 22050.0) + k < tracks[id].size() else 0.0
		check(on_beat > between, "playlist %s : la grosse caisse tombe sur le temps" % id)
	check(tracks.musette_remix != tracks.techno_foraine and tracks.techno_foraine != tracks.tube_ete_2003, "les trois playlists sont différentes")
	var M3 = load("res://scripts/world/mission_m03.gd")
	check(is_equal_approx(M3.BEAT, 60.0 / Synth.TRACK_BPM), "rythme de la mission 3 = rythme des playlists (%.2f s)" % M3.BEAT)
	check(M3.PERFECT < M3.GOOD and M3.GOOD < M3.BEAT / 2.0, "fenêtres de timing : parfait < bon < demi-temps")
	check(is_equal_approx(M3.COUNT_TIME / M3.BEAT, round(M3.COUNT_TIME / M3.BEAT)), "le compte à rebours est un nombre entier de temps (boucle alignée)")
	# Atelier d'accessoires : chaque accessoire est détaillé (nombreuses parties), borné et sous le budget de triangles.
	var PK = load("res://scripts/world/prop_kit.gd")
	var SF = load("res://scripts/world/street_furniture.gd")
	var specs := {"lamp": [4.0, 5.2, 14], "bench": [0.8, 1.3, 11], "planter": [0.8, 1.1, 18], "bollard": [0.7, 1.0, 3], "well": [2.8, 3.4, 9],
		"hay_bale": [1.2, 1.6, 4], "barrel": [0.8, 1.1, 6], "chair": [0.9, 1.2, 9], "table": [0.7, 1.2, 27], "table_set": [0.9, 1.3, 45],
		"spit": [1.2, 1.9, 20], "brazier": [0.5, 0.8, 14], "pyre": [2.0, 3.6, 37], "flames": [2.0, 3.6, 3], "dog": [0.8, 1.2, 12],
		"lamb": [0.6, 1.0, 12], "cow": [1.4, 1.8, 24], "pen": [1.5, 1.8, 40], "gate_leaf": [1.0, 1.3, 6], "charcoal": [0.5, 0.9, 8]}
	var tri_total := 0
	for n in specs:
		var kit = Callable(PK, n).call()
		var bb: AABB = kit.bounds()
		var lim: Array = specs[n]
		check(kit.part_count() >= int(lim[2]) and bb.end.y >= float(lim[0]) and bb.end.y <= float(lim[1]), "accessoire %s : %d parties, hauteur %.2f m" % [n, kit.part_count(), bb.end.y])
		check(kit.mesh().get_surface_count() >= 1 and kit.triangle_count() < 4000, "accessoire %s : %d triangles" % [n, kit.triangle_count()])
		tri_total += kit.triangle_count()
	var lampk = PK.lamp()
	check(lampk.mesh().get_surface_count() >= 2 and lampk.outline_mesh().get_surface_count() == 1, "lampadaire : plusieurs couleurs, un seul contour")
	check(PK.table(4).part_count() > PK.table(0).part_count(), "table : les assiettes garnies ajoutent des parties")
	var tile_json = load("res://scripts/world/city_builder.gd").read_json("res://assets/city/tiles/%s.json" % load("res://scripts/world/city_builder.gd").load_manifest().tiles[0])
	var lamps: Array = SF.lamp_spots(tile_json, func(_x, _z): return 0.0)
	check(lamps.size() > 0 and lamps == SF.lamp_spots(tile_json, func(_x, _z): return 0.0), "lampadaires : %d sur la première tuile, placement déterministe" % lamps.size())
	# Navigation : un passage qui traverse un bâtiment est désactivé, le chemin contourne.
	var nv := RoadNav.new()
	nv.build([{"points": [[0, 0], [40, 0]], "kind": "residential"}, {"points": [[0, 0], [0, 20], [40, 20], [40, 0]], "kind": "residential"}])
	var blk := PackedVector2Array([Vector2(15, -4), Vector2(25, -4), Vector2(25, 4), Vector2(15, 4)])
	var nblocked: int = nv.block_buildings([blk])
	var detour2: PackedVector2Array = nv.find_path(Vector2(0, 0), Vector2(40, 0))
	var through := false
	for pt in detour2:
		through = through or Geometry2D.is_point_in_polygon(pt, blk)
	check(nblocked >= 2 and not through and RoadNav.length_of(detour2) > 60.0, "navigation : le passage sous un bâtiment est évité (%d points bloqués, détour %.0f m)" % [nblocked, RoadNav.length_of(detour2)])
	# Personnages détaillés : visage, vêtements et accessoires selon le style.
	var CMt = load("res://scripts/player/character_model.gd")
	var Pl = load("res://scripts/player/player.gd")
	var basic = CMt.make(Color(0.5, 0.5, 0.5))
	var gege = CMt.make(Pl.OUTFITS[-1].shirt, Pl.OUTFITS[-1].trousers, Pl.OUTFITS[-1].hat, Pl.OUTFITS[-1].style)
	var gin = CMt.make(Pl.OUTFITS[-2].shirt, Pl.OUTFITS[-2].trousers, Pl.OUTFITS[-2].hat, Pl.OUTFITS[-2].style)
	check(basic.detail_parts >= 25, "personnage de base : %d parties de détail (yeux, sourcils, bouche, oreilles, cheveux, ceinture, col, boutons, poches, manchettes, semelles…)" % basic.detail_parts)
	check(gege.detail_parts > basic.detail_parts and gin.detail_parts > basic.detail_parts, "Gégé (moustache, gilet) et Ginette (chignon, lunettes, tablier) ont plus de détails que le personnage de base")
	check(gege.find_child("Tete", true, false) != null and gege.find_child("Tronc", true, false) != null, "la hiérarchie articulée est conservée")
	var mats := {}
	for mi in gege.find_children("*", "MeshInstance3D", true, false):
		mats[(mi as MeshInstance3D).mesh.surface_get_material(0) if (mi as MeshInstance3D).mesh.get_surface_count() > 0 else null] = true
	check(mats.size() < gege.find_children("*", "MeshInstance3D", true, false).size(), "matériaux partagés entre parties de même couleur (%d pour %d parties)" % [mats.size(), gege.find_children("*", "MeshInstance3D", true, false).size()])
	gege.animate(0.5, 3.0)
	check(absf(gege.leg_angle_l) < 1.5, "l'animation de marche fonctionne toujours avec le modèle détaillé")
	for kind in ["cap", "cap_back", "headphones", "scarf", "straw", "kepi", "none", "beret"]:
		var mk = CMt.make(Color(0.5, 0.5, 0.5), Color(0.2, 0.2, 0.3), Color(0.3, 0.3, 0.3), {"headgear": kind})
		check(mk.find_child("Tete", true, false) != null, "couvre-chef « %s » construit" % kind) if kind in ["kepi", "straw", "none"] else null
	check(Pl.default_style(3) != Pl.default_style(4) and Pl.default_style(3) == Pl.default_style(3), "style des joueurs : déterministe, varié selon l'identifiant")
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
	# --- Détails d'architecture ---
	var BD = load("res://scripts/world/building_details.gd")
	var gable := {"id": "b_20", "footprint": [[10, 10], [10, 22], [30, 22], [30, 10]], "height": 7.5, "levels": 2, "roof": "gabled", "typology": "brique", "groundZ": 0.0}
	var ringd := PackedVector2Array([Vector2(10, 10), Vector2(10, 22), Vector2(30, 22), Vector2(30, 10)])
	var md: Dictionary = Builder.ridge_model(ringd, 7.5, "gabled")
	var chs: Array = BD.chimney_spots(ringd, md, 0.9, "brique")
	check(chs.size() == 2 and chs.all(func(p): return Geometry2D.is_point_in_polygon(p, ringd)), "cheminées : deux sur un long toit, dans le contour")
	check(BD.chimney_spots(ringd, md, 0.9, "annexe").is_empty() and BD.chimney_spots(ringd, Builder.ridge_model(ringd, 7.5, "flat"), 0.5, "brique").is_empty(), "cheminées : ni sur une annexe ni sur un toit plat")
	var dms: Array = BD.dormer_spots(ringd, md, 0.9, "brique", 2)
	check(dms.size() >= 2 and dms.all(func(d): return Geometry2D.is_point_in_polygon(d.pos, ringd)), "lucarnes : %d sur un grand toit à étage" % dms.size())
	check(BD.dormer_spots(ringd, md, 0.9, "brique", 1).is_empty() and BD.dormer_spots(ringd, md, 0.9, "commerce", 3).is_empty(), "lucarnes : aucune sans étage ni sur un commerce")
	check(BD.chimney_spots(ringd, md, 0.9, "brique") == BD.chimney_spots(ringd, md, 0.9, "brique"), "détails : placement déterministe")
	var bay: Vector2 = BD.bays(14.0)
	check(int(bay.x) == 5 and absf(bay.y * bay.x - 14.0) < 0.2, "travées : 14 m = 5 travées de %.2f m" % bay.y)
	var okc := true
	for sd in 256:
		okc = okc and BD.door_cell(sd / 255.0, 5) >= 0 and BD.door_cell(sd / 255.0, 5) < 5 and BD.door_cell(sd / 255.0, 1) == 0
	check(okc, "porte : la travée est toujours dans la façade")
	var off: float = BD.door_offset(0.4, 14.0)
	check(off > 0.0 and off < 14.0, "porte : décalage %.2f m le long du mur" % off)
	var tile3 := tile2.duplicate(true)
	tile3.buildings = [gable]
	var bd1 = Builder.new()
	bd1.register_tile(tile3)
	var with_n := ((bd1.build_tile(tile3).get_node("Batiments") as MeshInstance3D).mesh as ArrayMesh)
	var bd2 = Builder.new()
	bd2.details = false
	bd2.register_tile(tile3)
	var without_n := ((bd2.build_tile(tile3).get_node("Batiments") as MeshInstance3D).mesh as ArrayMesh)
	check(with_n.get_faces().size() > without_n.get_faces().size() * 2 and with_n.get_surface_count() > without_n.get_surface_count(), "bâtiment détaillé : %d triangles contre %d, %d surfaces contre %d" % [with_n.get_faces().size() / 3, without_n.get_faces().size() / 3, with_n.get_surface_count(), without_n.get_surface_count()])
	var col_n: ArrayMesh = Builder.collision_mesh(with_n)
	check(col_n.get_faces().size() == without_n.get_faces().size(), "collisions : les détails d'architecture n'y sont pas (%d triangles, comme sans détails)" % (col_n.get_faces().size() / 3))
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
