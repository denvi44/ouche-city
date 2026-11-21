class_name Landmarks
extends RefCounted
## Édifices détaillés de Frouch City (agent 04) : église, mairie, écoles, hôpital, distillerie de calva. Modèles procéduraux (primitives
## fusionnées par PropKit, contours « inverted hull »), aucun fichier binaire : identiques sous Windows et macOS, sans Git LFS.
## Repère : origine au centre de l'emprise, au sol ; +Z = devant (côté rue) ; `w` = largeur le long de la façade (X), `d` = profondeur (Z).
## Les dimensions du modèle suivent l'emprise (bornées) ; la collision est une boîte à la taille du volume principal.

const STONE := Color(0.84, 0.8, 0.7)
const STONE_DARK := Color(0.62, 0.58, 0.52)
const CREAM := Color(0.95, 0.91, 0.78)
const BRICK := Color(0.7, 0.34, 0.26)
const SLATE := Color(0.3, 0.33, 0.4)
const TILE_RED := Color(0.78, 0.32, 0.22)
const WOOD := Color(0.42, 0.28, 0.18)
const GLASS := Color(0.45, 0.62, 0.78)
const WHITE := Color(0.96, 0.96, 0.94)
const COPPER := Color(0.78, 0.46, 0.26)
const IRON := Color(0.2, 0.21, 0.24)

const NAMES := {"eglise": "Église", "mairie": "Mairie", "ecole": "École", "hopital": "Hôpital", "usine": "Distillerie"}


## Modèle d'un édifice. `label` : nom affiché sur l'enseigne. Renvoie {"node": Node3D, "size": Vector3 (volume de collision), "label_pos": Vector3}.
static func build(facility: String, w: float, d: float, label := "") -> Dictionary:
	match facility:
		"eglise":
			return _eglise(w, d)
		"mairie":
			return _mairie(w, d, label)
		"ecole":
			return _ecole(w, d, label)
		"hopital":
			return _hopital(w, d, label)
		"usine":
			return _usine(w, d, label)
	return {"node": Node3D.new(), "size": Vector3(w, 6.0, d)}


static func _sign(parent: Node3D, text: String, pos: Vector3, yaw: float, size := 0.012, color := Color(0.98, 0.96, 0.88)) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size
	l.modulate = color
	l.outline_size = 6
	l.outline_modulate = Color(0.1, 0.08, 0.06)
	l.double_sided = false
	l.position = pos
	l.rotation.y = yaw
	parent.add_child(l)


static func _flag(k: PropKit, x: float, y: float, z: float, h := 6.0) -> void:
	k.add_cyl(0.05, 0.07, h, Vector3(x, y + h / 2.0, z), Color(0.85, 0.85, 0.85), Vector3.ZERO, 6)
	for i in 3:
		var c: Color = [Color(0.1, 0.25, 0.7), Color(0.97, 0.97, 0.97), Color(0.8, 0.12, 0.15)][i]
		k.add_box(Vector3(0.45, 0.9, 0.04), Vector3(x + 0.25 + 0.45 * float(i), y + h - 0.55, z), c)


# --- Église : nef, abside, contreforts, vitraux, clocher à flèche et horloge, portail, rosace -----------------------------------------------

static func _eglise(w_in: float, d_in: float) -> Dictionary:
	var long_x := w_in > d_in
	var L := clampf(maxf(w_in, d_in), 22.0, 38.0)
	var W := clampf(minf(w_in, d_in), 9.0, 15.0)
	var k := PropKit.new()
	var T := 6.4
	var nz0 := -L / 2.0
	var nz1 := L / 2.0 - T
	var zc := (nz0 + nz1) / 2.0
	var ln := nz1 - nz0
	var wall_h := 9.0
	k.add_box(Vector3(W, wall_h, ln), Vector3(0, wall_h / 2.0, zc), STONE)
	k.add_box(Vector3(W + 0.4, 0.8, ln + 0.4), Vector3(0, 0.4, zc), STONE_DARK)                     # soubassement
	var ang := 0.72
	var half := (W / 2.0 + 0.6) / cos(ang)
	for s in [-1.0, 1.0]:
		k.add_box(Vector3(half, 0.26, ln + 1.0), Vector3(s * (W / 4.0 + 0.1), wall_h + tan(ang) * W / 4.0 + 0.15, zc), SLATE, Vector3(0, 0, -s * ang))
	k.add_box(Vector3(0.4, 0.3, ln + 1.0), Vector3(0, wall_h + tan(ang) * W / 2.0 + 0.2, zc), IRON)       # faîtage
	# Abside en demi-cylindre et sa toiture conique.
	var ra := W / 2.4
	k.add_cyl(ra, ra, wall_h, Vector3(0, wall_h / 2.0, nz0 - ra * 0.35), STONE, Vector3.ZERO, 10)
	k.add_cyl(0.0, ra + 0.5, 5.0, Vector3(0, wall_h + 2.5, nz0 - ra * 0.35), SLATE, Vector3.ZERO, 10)
	# Contreforts et vitraux, à chaque travée (4,6 m).
	var bays := int(floor(ln / 4.6))
	var cols := [Color(0.2, 0.35, 0.78), Color(0.78, 0.2, 0.2), Color(0.92, 0.76, 0.2), Color(0.25, 0.62, 0.38)]
	for i in bays + 1:
		var z := nz0 + 1.2 + float(i) * (ln - 2.4) / float(maxi(bays, 1))
		for s in [-1.0, 1.0]:
			k.add_box(Vector3(0.8, 7.6, 1.0), Vector3(s * (W / 2.0 + 0.3), 3.8, z), STONE_DARK)
			if i < bays:
				var zw := z + (ln - 2.4) / float(maxi(bays, 1)) / 2.0
				k.add_box(Vector3(0.12, 4.4, 1.3), Vector3(s * (W / 2.0 + 0.03), 4.9, zw), cols[(i + (0 if s < 0.0 else 2)) % 4])
				k.add_box(Vector3(0.16, 4.7, 1.55), Vector3(s * (W / 2.0 + 0.01), 4.9, zw), CREAM)
	# Clocher : fût, angles, abat-sons, quatre cadrans, flèche en ardoise et croix à coq.
	var tz := L / 2.0 - T / 2.0
	k.add_box(Vector3(T, 20.0, T), Vector3(0, 10.0, tz), STONE)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.add_box(Vector3(0.7, 20.0, 0.7), Vector3(sx * T / 2.0, 10.0, tz + sz * T / 2.0), STONE_DARK)
	k.add_box(Vector3(T + 0.6, 0.6, T + 0.6), Vector3(0, 20.2, tz), STONE_DARK)
	for face in 4:
		var yaw := float(face) * PI / 2.0
		var n := Vector3(sin(yaw), 0, cos(yaw))
		k.add_box(Vector3(2.2 if face % 2 == 0 else 0.14, 3.0, 0.14 if face % 2 == 0 else 2.2), Vector3(0, 17.4, tz) + n * (T / 2.0 + 0.02), IRON)  # abat-sons
		k.add_cyl(0.95, 0.95, 0.1, Vector3(0, 13.4, tz) + n * (T / 2.0 + 0.05), WHITE, Vector3(PI / 2.0, 0, 0) if face % 2 == 0 else Vector3(0, 0, PI / 2.0), 20)
		k.add_box(Vector3(0.08, 0.7, 0.1) if face % 2 == 0 else Vector3(0.1, 0.7, 0.08), Vector3(0, 13.6, tz) + n * (T / 2.0 + 0.12), IRON)
	k.add_cyl(0.0, T * 0.78, 10.5, Vector3(0, 25.8, tz), SLATE, Vector3(0, PI / 4.0, 0), 4)
	k.add_box(Vector3(0.14, 1.8, 0.14), Vector3(0, 31.9, tz), IRON)
	k.add_box(Vector3(0.9, 0.14, 0.14), Vector3(0, 31.5, tz), IRON)
	k.add_sphere(0.22, Vector3(0.45, 32.2, tz), IRON, Vector3(1.4, 1.0, 0.8), 6)                  # coq
	# Portail : encadrement, vantaux, marches, rosace.
	k.add_box(Vector3(3.6, 4.8, 0.3), Vector3(0, 2.4, L / 2.0 + 0.05), STONE_DARK)
	k.add_box(Vector3(2.8, 4.1, 0.34), Vector3(0, 2.05, L / 2.0 + 0.08), WOOD)
	k.add_box(Vector3(0.1, 4.1, 0.38), Vector3(0, 2.05, L / 2.0 + 0.1), IRON)
	for i in 3:
		k.add_box(Vector3(4.4 + float(i) * 0.8, 0.2, 0.7), Vector3(0, 0.1 + 0.0 * float(i), L / 2.0 + 0.5 + float(2 - i) * 0.55), STONE_DARK)
	k.add_cyl(1.4, 1.4, 0.2, Vector3(0, 9.2, L / 2.0 + 0.08), Color(0.78, 0.25, 0.3), Vector3(PI / 2.0, 0, 0), 16)
	k.add_cyl(0.9, 0.9, 0.24, Vector3(0, 9.2, L / 2.0 + 0.1), Color(0.95, 0.8, 0.25), Vector3(PI / 2.0, 0, 0), 16)
	k.add_cyl(0.4, 0.4, 0.28, Vector3(0, 9.2, L / 2.0 + 0.12), Color(0.2, 0.35, 0.78), Vector3(PI / 2.0, 0, 0), 12)
	# Croix sur le pignon de la nef et enclos : murets et cimetière symbolique.
	k.add_box(Vector3(0.12, 1.5, 0.12), Vector3(0, wall_h + tan(ang) * W / 2.0 + 1.0, nz1 + 0.2), IRON)
	k.add_box(Vector3(0.7, 0.12, 0.12), Vector3(0, wall_h + tan(ang) * W / 2.0 + 1.3, nz1 + 0.2), IRON)
	var root := Node3D.new()
	var node := k.build()
	root.add_child(node)
	var out := Node3D.new()
	if long_x:
		root.rotation.y = PI / 2.0
	out.add_child(root)
	return {"node": out, "size": Vector3(W, 12.0, L - 2.0) if not long_x else Vector3(L - 2.0, 12.0, W)}


# --- Mairie : façade symétrique, pavillon à fronton et horloge, toit mansardé, drapeaux, perron -------------------------------------------

static func _mairie(w_in: float, d_in: float, label: String) -> Dictionary:
	var w := clampf(w_in, 14.0, 26.0)
	var d := clampf(d_in, 9.0, 15.0)
	var k := PropKit.new()
	k.add_box(Vector3(w, 3.2, d), Vector3(0, 1.6, 0), STONE_DARK)                                   # rez-de-chaussée en pierre
	k.add_box(Vector3(w, 6.6, d), Vector3(0, 6.5, 0), CREAM)                                        # deux étages
	k.add_box(Vector3(w + 0.5, 0.4, d + 0.5), Vector3(0, 9.9, 0), STONE)                            # corniche
	for sx in [-1.0, 1.0]:
		for i in 6:
			k.add_box(Vector3(0.7, 0.5, 0.2), Vector3(sx * (w / 2.0 - 0.3), 1.0 + float(i) * 1.5, d / 2.0 + 0.02), STONE)    # chaînage d'angle
	# Pavillon central en saillie avec fronton triangulaire.
	var pw := w * 0.32
	k.add_box(Vector3(pw, 10.4, 2.4), Vector3(0, 5.2, d / 2.0 + 1.2), CREAM)
	k.add_box(Vector3(pw + 0.6, 0.4, 2.8), Vector3(0, 10.6, d / 2.0 + 1.2), STONE)
	for s in [-1.0, 1.0]:
		k.add_box(Vector3(pw / 2.0 / cos(0.35) + 0.2, 0.3, 2.9), Vector3(s * pw / 4.0, 11.0 + tan(0.35) * pw / 4.0, d / 2.0 + 1.2), STONE, Vector3(0, 0, -s * 0.35))
	k.add_cyl(0.8, 0.8, 0.12, Vector3(0, 11.4, d / 2.0 + 2.45), WHITE, Vector3(PI / 2.0, 0, 0), 20)    # horloge
	k.add_box(Vector3(0.07, 0.55, 0.06), Vector3(0, 11.6, d / 2.0 + 2.55), IRON)
	k.add_box(Vector3(0.45, 0.07, 0.06), Vector3(0.18, 11.4, d / 2.0 + 2.55), IRON)
	# Perron, porte, balcon.
	for i in 4:
		k.add_box(Vector3(pw * 0.8 + float(3 - i) * 0.5, 0.18, 0.7), Vector3(0, 0.09 + 0.0 * float(i), d / 2.0 + 2.7 + float(3 - i) * 0.5), STONE_DARK)
	k.add_box(Vector3(2.4, 3.0, 0.2), Vector3(0, 1.5, d / 2.0 + 2.45), WOOD)
	k.add_box(Vector3(2.4, 0.8, 0.22), Vector3(0, 3.4, d / 2.0 + 2.46), GLASS)
	k.add_box(Vector3(pw * 0.7, 0.12, 1.0), Vector3(0, 6.2, d / 2.0 + 2.9), STONE)
	k.add_box(Vector3(pw * 0.7, 0.9, 0.08), Vector3(0, 6.7, d / 2.0 + 3.4), IRON)
	# Fenêtres : trois rangées sur les ailes, façade avant et arrière.
	var cols := int(floor((w - pw) / 2.0 / 2.6))
	for r in 3:
		var y := 2.0 + float(r) * 3.2 if r > 0 else 2.0
		for face in [-1.0, 1.0]:
			for i in cols:
				for s in [-1.0, 1.0]:
					var x: float = s * (pw / 2.0 + 1.6 + float(i) * 2.6)
					if absf(x) > w / 2.0 - 1.0:
						continue
					k.add_box(Vector3(1.1, 1.7, 0.1), Vector3(x, y + 0.9, face * (d / 2.0 + 0.04)), GLASS)
					k.add_box(Vector3(1.35, 1.95, 0.08), Vector3(x, y + 0.9, face * (d / 2.0 + 0.01)), WHITE)
	# Toit mansardé en ardoise, lucarnes, souches de cheminée.
	for s in [-1.0, 1.0]:
		k.add_box(Vector3(w + 1.0, 0.3, d / 2.0 / cos(0.62) + 0.8), Vector3(0, 11.2 + tan(0.62) * d / 4.0, s * d / 4.0), SLATE, Vector3(-s * 0.62, 0, 0))
	k.add_box(Vector3(w + 0.6, 0.3, 0.4), Vector3(0, 11.2 + tan(0.62) * d / 2.0 + 0.2, 0), IRON)
	for i in 5:
		var x := -w / 2.0 + 2.6 + float(i) * (w - 5.2) / 4.0
		if absf(x) < pw / 2.0:
			continue
		k.add_box(Vector3(1.2, 1.4, 1.0), Vector3(x, 12.2, d / 4.0 + 0.4), CREAM)
		k.add_box(Vector3(0.8, 0.8, 0.1), Vector3(x, 12.2, d / 4.0 + 0.92), GLASS)
		k.add_box(Vector3(1.5, 0.12, 1.3), Vector3(x, 13.0, d / 4.0 + 0.4), SLATE)
	for x in [-w / 2.0 + 2.0, w / 2.0 - 2.0]:
		k.add_box(Vector3(0.9, 2.4, 0.9), Vector3(x, 13.2, -1.0), BRICK)
	# Mâts à drapeaux (tricolore) et lampadaires de part et d'autre du perron.
	for x in [-pw / 2.0 - 1.2, pw / 2.0 + 1.2]:
		_flag(k, x, 0.0, d / 2.0 + 3.0, 7.0)
	var node := k.build()
	var root := Node3D.new()
	root.add_child(node)
	_sign(root, "MAIRIE", Vector3(0, 8.6, d / 2.0 + 2.62), 0.0, 0.016)
	if label != "":
		_sign(root, label.to_upper(), Vector3(0, 5.2, d / 2.0 + 2.62), 0.0, 0.0075, Color(0.2, 0.15, 0.1))
	return {"node": root, "size": Vector3(w, 12.0, d)}


# --- École : corps de bâtiment, clocheton, grandes baies, préau, cour avec jeux ------------------------------------------------------------

static func _ecole(w_in: float, d_in: float, label: String) -> Dictionary:
	var long_x := w_in >= d_in
	var w := clampf(w_in, 8.0, 44.0)
	var d := clampf(d_in, 8.0, 34.0)
	var k := PropKit.new()
	var h := 4.6
	k.add_box(Vector3(w, h, d), Vector3(0, h / 2.0, 0), BRICK)
	k.add_box(Vector3(w + 0.2, 0.9, d + 0.2), Vector3(0, 0.45, 0), STONE_DARK)
	k.add_box(Vector3(w + 0.3, 0.3, d + 0.3), Vector3(0, h + 0.15, 0), CREAM)                        # bandeau crème
	# Toit à deux pans (faîtage le long du grand côté).
	var ang := 0.42
	if long_x:
		for s in [-1.0, 1.0]:
			k.add_box(Vector3(w + 1.0, 0.22, (d / 2.0 + 0.6) / cos(ang)), Vector3(0, h + 0.3 + tan(ang) * d / 4.0, s * d / 4.0), TILE_RED, Vector3(-s * ang, 0, 0))
	else:
		for s in [-1.0, 1.0]:
			k.add_box(Vector3((w / 2.0 + 0.6) / cos(ang), 0.22, d + 1.0), Vector3(s * w / 4.0, h + 0.3 + tan(ang) * w / 4.0, 0), TILE_RED, Vector3(0, 0, -s * ang))
	var ridge_y := h + 0.4 + tan(ang) * (d if long_x else w) / 2.0
	# Clocheton central : base carrée, cloche et petit toit.
	k.add_box(Vector3(2.4, 2.4, 2.4), Vector3(0, ridge_y + 1.0, 0), CREAM)
	k.add_box(Vector3(1.2, 1.2, 0.1), Vector3(0, ridge_y + 1.1, 1.25), IRON)
	k.add_box(Vector3(1.2, 1.2, 0.1), Vector3(0, ridge_y + 1.1, -1.25), IRON)
	k.add_cyl(0.0, 1.9, 1.6, Vector3(0, ridge_y + 3.0, 0), SLATE, Vector3.ZERO, 4)
	k.add_sphere(0.3, Vector3(0, ridge_y + 1.0, 0), COPPER, Vector3(1, 1.1, 1), 6)                   # cloche
	# Grandes baies régulières sur les deux grands côtés ; porte double côté rue.
	if long_x:
		var n := int(floor(w / 3.2))
		for i in n:
			var x := -w / 2.0 + 1.6 + float(i) * (w - 3.2) / float(maxi(n - 1, 1))
			for s in [-1.0, 1.0]:
				k.add_box(Vector3(1.9, 2.0, 0.1), Vector3(x, 2.7, s * (d / 2.0 + 0.04)), GLASS)
				k.add_box(Vector3(2.1, 2.2, 0.08), Vector3(x, 2.7, s * (d / 2.0 + 0.01)), CREAM)
		k.add_box(Vector3(2.4, 3.0, 0.2), Vector3(0, 1.5, d / 2.0 + 0.1), WOOD)
		k.add_box(Vector3(5.0, 0.2, 2.0), Vector3(0, 3.4, d / 2.0 + 1.0), TILE_RED)                   # auvent d'entrée
		for sx in [-2.2, 2.2]:
			k.add_box(Vector3(0.18, 3.3, 0.18), Vector3(sx, 1.65, d / 2.0 + 1.9), WOOD)
	else:
		var n2 := int(floor(d / 3.2))
		for i in n2:
			var z := -d / 2.0 + 1.6 + float(i) * (d - 3.2) / float(maxi(n2 - 1, 1))
			for s in [-1.0, 1.0]:
				k.add_box(Vector3(0.1, 2.0, 1.9), Vector3(s * (w / 2.0 + 0.04), 2.7, z), GLASS)
				k.add_box(Vector3(0.08, 2.2, 2.1), Vector3(s * (w / 2.0 + 0.01), 2.7, z), CREAM)
		k.add_box(Vector3(2.4, 3.0, 0.2), Vector3(0, 1.5, d / 2.0 + 0.1), WOOD)
		k.add_box(Vector3(5.0, 0.2, 2.0), Vector3(0, 3.4, d / 2.0 + 1.0), TILE_RED)
		for sx in [-2.2, 2.2]:
			k.add_box(Vector3(0.18, 3.3, 0.18), Vector3(sx, 1.65, d / 2.0 + 1.9), WOOD)
	# Cour côté rue : dalle, muret avec portail, jeux (toboggan, balançoires, bascule, marelle, bac à sable) et un arbre.
	var cz := d / 2.0 + 7.5
	var cw := minf(w + 6.0, 30.0)
	k.add_box(Vector3(cw, 0.06, 13.0), Vector3(0, 0.03, cz), Color(0.64, 0.6, 0.55))
	for s in [-1.0, 1.0]:
		k.add_box(Vector3(0.3, 1.0, 13.0), Vector3(s * cw / 2.0, 0.5, cz), STONE)
	k.add_box(Vector3(cw / 2.0 - 1.4, 1.0, 0.3), Vector3(-cw / 4.0 - 0.7, 0.5, cz + 6.5), STONE)
	k.add_box(Vector3(cw / 2.0 - 1.4, 1.0, 0.3), Vector3(cw / 4.0 + 0.7, 0.5, cz + 6.5), STONE)
	k.add_box(Vector3(0.3, 2.0, 0.3), Vector3(-1.4, 1.0, cz + 6.5), IRON)
	k.add_box(Vector3(0.3, 2.0, 0.3), Vector3(1.4, 1.0, cz + 6.5), IRON)
	var gx := -cw / 2.0 + 3.0
	k.add_box(Vector3(1.0, 0.1, 3.2), Vector3(gx, 1.0, cz - 1.0), Color(0.85, 0.3, 0.3), Vector3(0.6, 0, 0))     # toboggan
	k.add_box(Vector3(1.0, 2.2, 0.12), Vector3(gx, 1.1, cz - 2.6), IRON)
	for sx in [-0.9, 0.9]:
		k.add_box(Vector3(0.1, 2.4, 0.1), Vector3(gx + 6.0 + sx, 1.2, cz + 1.0), IRON, Vector3(0, 0, -sx * 0.1))   # balançoires
	k.add_box(Vector3(2.2, 0.1, 0.1), Vector3(gx + 6.0, 2.35, cz + 1.0), IRON)
	for sx in [-0.5, 0.5]:
		k.add_box(Vector3(0.4, 0.06, 0.4), Vector3(gx + 6.0 + sx, 0.7, cz + 1.0), Color(0.2, 0.4, 0.75))
	k.add_box(Vector3(2.6, 0.1, 0.3), Vector3(gx + 11.0, 0.55, cz + 2.0), Color(0.9, 0.7, 0.2), Vector3(0, 0, 0.12))   # bascule
	k.add_cyl(0.1, 0.18, 0.5, Vector3(gx + 11.0, 0.25, cz + 2.0), IRON, Vector3.ZERO, 6)
	for i in 6:
		k.add_box(Vector3(0.9, 0.02, 0.9), Vector3(gx + 15.0, 0.07, cz - 2.5 + float(i) * 1.0), [Color(0.95, 0.85, 0.3), Color(0.9, 0.4, 0.4), Color(0.4, 0.6, 0.9)][i % 3])   # marelle
	k.add_box(Vector3(2.4, 0.25, 2.4), Vector3(gx + 3.0, 0.13, cz + 3.5), WOOD)
	k.add_box(Vector3(2.2, 0.28, 2.2), Vector3(gx + 3.0, 0.14, cz + 3.5), Color(0.9, 0.82, 0.55))                  # bac à sable
	k.add_cyl(0.16, 0.22, 2.6, Vector3(cw / 2.0 - 3.0, 1.3, cz + 3.5), WOOD, Vector3.ZERO, 6)
	k.add_sphere(2.0, Vector3(cw / 2.0 - 3.0, 4.0, cz + 3.5), Color(0.38, 0.6, 0.3), Vector3(1, 0.85, 1), 8)       # arbre de cour
	var root := Node3D.new()
	root.add_child(k.build())
	_sign(root, label.to_upper() if label != "" else "ÉCOLE", Vector3(0, 4.9, d / 2.0 + 0.22), 0.0, 0.0085 if long_x else 0.0075, Color(0.98, 0.95, 0.85))
	return {"node": root, "size": Vector3(w, 6.0, d)}


# --- Hôpital : bloc de quatre niveaux, entrée à auvent, croix verte, héliport, ambulance, parking ----------------------------------------

static func _hopital(w_in: float, d_in: float, label: String) -> Dictionary:
	var w := clampf(w_in, 14.0, 26.0)
	var d := clampf(d_in, 18.0, 40.0)
	var k := PropKit.new()
	var floors := 4
	var fh := 3.5
	var h := float(floors) * fh
	k.add_box(Vector3(w, h, d), Vector3(0, h / 2.0, 0), WHITE)
	for i in floors:
		k.add_box(Vector3(w + 0.3, 0.45, d + 0.3), Vector3(0, float(i) * fh + 0.2, 0), Color(0.55, 0.75, 0.82))   # bandeaux bleu clair
		for face in [-1.0, 1.0]:
			var n := int(floor(d / 3.0))
			for j in n:
				var z := -d / 2.0 + 1.5 + float(j) * (d - 3.0) / float(maxi(n - 1, 1))
				k.add_box(Vector3(0.1, 1.5, 1.8), Vector3(face * (w / 2.0 + 0.04), float(i) * fh + 2.0, z), GLASS)
		var nf := int(floor(w / 3.0))
		for j in nf:
			var x := -w / 2.0 + 1.5 + float(j) * (w - 3.0) / float(maxi(nf - 1, 1))
			for face in [-1.0, 1.0]:
				if i == 0 and face > 0.0 and absf(x) < 4.0:
					continue
				k.add_box(Vector3(1.8, 1.5, 0.1), Vector3(x, float(i) * fh + 2.0, face * (d / 2.0 + 0.04)), GLASS)
	k.add_box(Vector3(w + 0.5, 0.5, d + 0.5), Vector3(0, h + 0.25, 0), Color(0.75, 0.77, 0.8))            # acrotère
	# Locaux techniques sur le toit et héliport.
	k.add_box(Vector3(5.0, 2.2, 4.0), Vector3(-w / 4.0, h + 1.6, -d / 4.0), Color(0.7, 0.72, 0.75))
	k.add_cyl(0.5, 0.5, 2.4, Vector3(-w / 4.0 + 3.0, h + 1.7, -d / 4.0 + 1.0), IRON, Vector3.ZERO, 8)
	var hx := w / 4.0
	var hz := -d / 4.0
	k.add_cyl(5.0, 5.0, 0.3, Vector3(hx, h + 0.65, hz), Color(0.3, 0.32, 0.36), Vector3.ZERO, 20)
	k.add_box(Vector3(0.5, 0.05, 3.0), Vector3(hx - 0.9, h + 0.83, hz), Color(0.97, 0.9, 0.3))
	k.add_box(Vector3(0.5, 0.05, 3.0), Vector3(hx + 0.9, h + 0.83, hz), Color(0.97, 0.9, 0.3))
	k.add_box(Vector3(1.8, 0.05, 0.5), Vector3(hx, h + 0.83, hz), Color(0.97, 0.9, 0.3))
	# Entrée : auvent sur deux colonnes, double porte vitrée, croix verte lumineuse.
	k.add_box(Vector3(8.0, 0.3, 4.5), Vector3(0, 4.2, d / 2.0 + 2.2), Color(0.55, 0.75, 0.82))
	for sx in [-3.5, 3.5]:
		k.add_cyl(0.22, 0.22, 4.1, Vector3(sx, 2.05, d / 2.0 + 4.0), WHITE, Vector3.ZERO, 8)
	k.add_box(Vector3(3.6, 3.0, 0.15), Vector3(0, 1.5, d / 2.0 + 0.1), GLASS)
	k.add_box(Vector3(6.0, 0.15, 3.0), Vector3(0, 0.07, d / 2.0 + 3.0), Color(0.7, 0.7, 0.68))
	var cx := 0.0
	var cy := h - 1.2
	k.add_box(Vector3(0.45, 2.6, 0.2), Vector3(cx, cy, d / 2.0 + 0.2), Color(0.2, 0.7, 0.35), Vector3.ZERO, true)
	k.add_box(Vector3(2.6, 0.45, 0.2), Vector3(cx, cy, d / 2.0 + 0.2), Color(0.2, 0.7, 0.35), Vector3.ZERO, true)
	# Urgences : sas d'ambulances à gauche, ambulance garée (carrosserie blanche, bandes rouges, gyrophare bleu).
	k.add_box(Vector3(6.0, 0.25, 5.0), Vector3(-w / 2.0 - 3.0, 3.2, d / 2.0 - 2.5), Color(0.8, 0.2, 0.2))
	for sx in [-w / 2.0 - 5.6, -w / 2.0 - 0.6]:
		k.add_box(Vector3(0.2, 3.2, 0.2), Vector3(sx, 1.6, d / 2.0 - 0.2), WHITE)
	var ax := -w / 2.0 - 3.0
	var az := d / 2.0 + 2.0
	k.add_box(Vector3(2.2, 1.7, 5.0), Vector3(ax, 1.3, az), WHITE)
	k.add_box(Vector3(2.25, 0.3, 5.05), Vector3(ax, 1.1, az), Color(0.8, 0.15, 0.15))
	k.add_box(Vector3(2.0, 1.0, 1.4), Vector3(ax, 1.4, az + 2.8), WHITE)
	k.add_box(Vector3(1.8, 0.5, 0.06), Vector3(ax, 1.75, az + 3.52), Color(0.3, 0.45, 0.55))
	k.add_box(Vector3(1.4, 0.18, 0.3), Vector3(ax, 2.25, az + 2.4), Color(0.2, 0.4, 1.0), Vector3.ZERO, true)
	for sx in [-0.9, 0.9]:
		for sz in [-1.5, 1.8]:
			k.add_cyl(0.38, 0.38, 0.25, Vector3(ax + sx, 0.38, az + sz), IRON, Vector3(0, 0, PI / 2.0), 10)
	# Parking : dalle et places marquées ; mât à drapeau.
	k.add_box(Vector3(w, 0.05, 14.0), Vector3(0, 0.03, d / 2.0 + 12.0), Color(0.34, 0.35, 0.38))
	for i in 8:
		k.add_box(Vector3(0.1, 0.02, 4.2), Vector3(-w / 2.0 + 1.5 + float(i) * (w - 3.0) / 7.0, 0.07, d / 2.0 + 14.0), WHITE)
	_flag(k, w / 2.0 + 2.0, 0.0, d / 2.0 + 2.0, 7.0)
	var root := Node3D.new()
	root.add_child(k.build())
	_sign(root, "HÔPITAL", Vector3(0, h - 3.1, d / 2.0 + 0.3), 0.0, 0.02, Color(0.15, 0.4, 0.3))
	_sign(root, "URGENCES", Vector3(-w / 2.0 - 3.0, 3.7, d / 2.0 + 0.1), 0.0, 0.01, Color(0.98, 0.9, 0.9))
	if label != "":
		_sign(root, label.to_upper(), Vector3(0, 4.9, d / 2.0 + 0.3), 0.0, 0.007, Color(0.2, 0.3, 0.35))
	return {"node": root, "size": Vector3(w, h + 1.0, d)}


# --- Distillerie de calva : halle de brique à toit en sheds, cheminée, alambics de cuivre, fûts, quai de chargement ------------------------

static func _usine(w_in: float, d_in: float, label: String) -> Dictionary:
	var w := clampf(w_in, 10.0, 24.0)
	var d := clampf(d_in, 16.0, 44.0)
	var k := PropKit.new()
	var h := 7.0
	k.add_box(Vector3(w, h, d), Vector3(0, h / 2.0, 0), BRICK)
	k.add_box(Vector3(w + 0.2, 0.8, d + 0.2), Vector3(0, 0.4, 0), STONE_DARK)
	k.add_box(Vector3(w + 0.3, 0.35, d + 0.3), Vector3(0, h + 0.17, 0), STONE)
	# Toit en sheds (dents de scie) : versant plein et verrière verticale.
	var teeth := int(floor(d / 5.0))
	for i in teeth:
		var z := -d / 2.0 + 2.5 + float(i) * 5.0
		k.add_box(Vector3(w + 0.4, 0.2, 5.2), Vector3(0, h + 1.5, z), SLATE, Vector3(-0.42, 0, 0))
		k.add_box(Vector3(w + 0.4, 1.8, 0.12), Vector3(0, h + 1.2, z + 2.3), GLASS)
	# Fenêtres hautes et portes de chargement.
	for s in [-1.0, 1.0]:
		var n := int(floor(d / 4.0))
		for j in n:
			var z2 := -d / 2.0 + 2.0 + float(j) * (d - 4.0) / float(maxi(n - 1, 1))
			k.add_box(Vector3(0.1, 2.2, 1.6), Vector3(s * (w / 2.0 + 0.04), 4.6, z2), GLASS)
			k.add_box(Vector3(0.13, 2.4, 1.8), Vector3(s * (w / 2.0 + 0.01), 4.6, z2), STONE)
	k.add_box(Vector3(3.6, 4.0, 0.2), Vector3(0, 2.0, d / 2.0 + 0.1), WOOD)
	k.add_box(Vector3(5.0, 0.2, 3.0), Vector3(0, 4.6, d / 2.0 + 1.5), Color(0.5, 0.52, 0.55))             # auvent du quai
	for sx in [-2.3, 2.3]:
		k.add_cyl(0.14, 0.14, 4.5, Vector3(sx, 2.25, d / 2.0 + 2.8), IRON, Vector3.ZERO, 6)
	k.add_box(Vector3(w * 0.8, 1.1, 3.0), Vector3(0, 0.55, d / 2.0 + 1.6), Color(0.62, 0.6, 0.57))       # quai
	# Cheminée de brique à anneaux, côté arrière.
	var chx := w / 2.0 + 2.6
	var chz := -d / 2.0 + 5.0
	k.add_cyl(1.0, 1.7, 32.0, Vector3(chx, 16.0, chz), BRICK, Vector3.ZERO, 12)
	for y in [10.0, 20.0, 28.0]:
		k.add_cyl(1.25, 1.25, 0.5, Vector3(chx, y, chz), STONE, Vector3.ZERO, 12)
	k.add_cyl(1.3, 1.3, 0.6, Vector3(chx, 32.2, chz), IRON, Vector3.ZERO, 12)
	k.add_box(Vector3(3.0, 0.5, 3.0), Vector3(chx, 0.25, chz), STONE_DARK)
	# Alambics de cuivre : cucurbite, chapiteau, col de cygne, serpentin.
	for i in 3:
		var ax := -w / 2.0 - 4.0
		var az := -d / 4.0 + float(i) * 6.0
		k.add_box(Vector3(3.0, 0.5, 3.0), Vector3(ax, 0.25, az), STONE_DARK)
		k.add_sphere(1.4, Vector3(ax, 2.0, az), COPPER, Vector3(1.0, 1.15, 1.0), 10)
		k.add_cyl(0.35, 0.8, 1.6, Vector3(ax, 3.9, az), COPPER, Vector3.ZERO, 8)
		k.add_box(Vector3(0.22, 0.22, 2.6), Vector3(ax, 4.9, az + 1.2), COPPER, Vector3(0.0, 0.0, 0.0))
		k.add_cyl(0.6, 0.6, 3.0, Vector3(ax, 2.2, az + 3.2 if i < 2 else az - 2.8), COPPER, Vector3.ZERO, 8)
	# Fûts de chêne empilés en pyramide (couchés), cageots de pommes, citerne.
	for st in 2:
		var bx := -w / 2.0 + 3.0 + float(st) * 5.0
		var bz := d / 2.0 + 5.0
		for row in 3:
			for c in 3 - row:
				k.add_cyl(0.5, 0.5, 1.1, Vector3(bx - 0.55 * float(2 - row) + 1.1 * float(c), 0.5 + 0.88 * float(row), bz), Color(0.5, 0.33, 0.2), Vector3(PI / 2.0, 0, 0), 10)
	for i in 6:
		k.add_box(Vector3(0.9, 0.5, 0.7), Vector3(w / 2.0 + 3.0 + float(i % 3) * 1.0, 0.25 + 0.5 * float(i / 3), d / 2.0 + 3.0), Color(0.55, 0.4, 0.22))
		k.add_sphere(0.2, Vector3(w / 2.0 + 3.0 + float(i % 3) * 1.0, 0.6 + 0.5 * float(i / 3), d / 2.0 + 3.0), Color(0.85, 0.2, 0.15), Vector3.ONE, 6)
	k.add_cyl(1.6, 1.6, 4.5, Vector3(w / 2.0 + 4.5, 2.25, -d / 4.0), Color(0.72, 0.74, 0.78), Vector3.ZERO, 12)
	k.add_cyl(0.18, 0.18, 6.0, Vector3(w / 2.0 + 0.4, 5.0, -d / 4.0), IRON, Vector3(PI / 2.0, 0, 0), 6)       # tuyauterie
	# Camion de livraison garé devant le quai.
	var tx := w / 2.0 + 2.0
	var tz2 := d / 2.0 + 9.0
	k.add_box(Vector3(2.4, 2.8, 6.0), Vector3(tx, 2.2, tz2), WHITE)
	k.add_box(Vector3(2.0, 1.6, 1.7), Vector3(tx, 1.7, tz2 + 3.9), Color(0.2, 0.42, 0.7))
	k.add_box(Vector3(2.45, 0.7, 6.05), Vector3(tx, 1.2, tz2), Color(0.55, 0.14, 0.14))
	for sx in [-1.0, 1.0]:
		for sz in [-2.0, 3.8]:
			k.add_cyl(0.5, 0.5, 0.3, Vector3(tx + sx * 1.2, 0.5, tz2 + sz), IRON, Vector3(0, 0, PI / 2.0), 10)
	var root := Node3D.new()
	root.add_child(k.build())
	_sign(root, "DISTILLERIE POMMIER & FILS", Vector3(0, 5.2, d / 2.0 + 0.3), 0.0, 0.0105, Color(0.98, 0.93, 0.78))
	_sign(root, "CALVA DU PAYS DE FROUCH", Vector3(0, 3.0, d / 2.0 + 0.3), 0.0, 0.0075, Color(0.98, 0.93, 0.78))
	return {"node": root, "size": Vector3(w, h + 2.0, d)}
