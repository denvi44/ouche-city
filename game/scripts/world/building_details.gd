class_name BuildingDetails
extends RefCounted
## Détails d'architecture des bâtiments (agent 04) : cheminées, lucarnes, corniches, soubassements, auvents de porte,
## stores de commerce, contreforts d'église. Tout est déterministe (graine = identifiant du bâtiment) et émis dans les
## mêmes SurfaceTool que les murs : un seul maillage par tuile, contour compris (le constructeur collecte les triangles).
##
## Les fonctions « spots » sont pures (aucun accès au constructeur) : elles sont testées sans scène.

const CORNICE_OUT := 0.2
const CORNICE_H := 0.26
const PLINTH_H := 0.55
const PLINTH_OUT := 0.05
const CHIMNEY := 0.62
const DORMER_W := 1.15
const MIN_LEN_DOOR := 2.2


# --- Calculs purs --------------------------------------------------------------------------------------------------------------------

## Hachage entier du graine d'un mur (0..255) : même quantification que le sommet COLOR lu par le shader de façade.
static func seed_byte(seed: float) -> int:
	return int(roundf(clampf(seed, 0.0, 1.0) * 255.0))


## Nombre de travées d'une façade et sa largeur, comme `facade_details.gdshaderinc` (longueur quantifiée à 1/255 de 100 m).
static func bays(seg_len: float, church := false) -> Vector2:
	var lenq := roundf(minf(seg_len / 100.0, 1.0) * 255.0) / 255.0 * 100.0
	var n := maxf(floorf(lenq / (4.2 if church else 2.8) + 0.5), 1.0)
	return Vector2(n, lenq / n)


## Travée de la porte : doit rester identique à `door_cell` du shader (arithmétique entière).
static func door_cell(seed: float, n: int) -> int:
	return (seed_byte(seed) * 37 + 11) % maxi(n, 1)


## Distance de la porte depuis le début du mur, le long du mur.
static func door_offset(seed: float, seg_len: float, church := false) -> float:
	var b := bays(seg_len, church)
	return (float(door_cell(seed, int(b.x))) + 0.5) * b.y


## Positions de cheminées sur le faîtage : [Vector2 position, ...] (zéro, une ou deux), toujours dans le contour.
static func chimney_spots(ring: PackedVector2Array, m: Dictionary, seed: float, typo: String) -> Array:
	if m.k <= 0.0 or typo in ["annexe", "eglise"]:
		return []
	var lo := INF
	var hi := -INF
	for p in ring:
		var s: float = (p - m.c).dot(m.axis)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	var length := hi - lo
	if length < 5.0 or m.half < 2.2:
		return []
	var fracs := [0.22] if seed < 0.4 else ([0.2, 0.78] if (seed > 0.8 and length > 11.0) else [0.75 if seed < 0.7 else 0.3])
	var out := []
	for f in fracs:
		var p: Vector2 = m.c + m.axis * (lo + length * f) + m.n * m.o
		if Geometry2D.is_point_in_polygon(p, ring):
			out.append(p)
	return out


## Lucarnes : [{pos: Vector2 (milieu du pan), side: ±1}, ...]. Seulement sur les toits assez hauts et profonds.
static func dormer_spots(ring: PackedVector2Array, m: Dictionary, seed: float, typo: String, levels: int) -> Array:
	if m.k <= 0.0 or typo in ["annexe", "eglise", "commerce"] or levels < 2 or m.half < 3.0:
		return []
	var lo := INF
	var hi := -INF
	for p in ring:
		var s: float = (p - m.c).dot(m.axis)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	var length := hi - lo
	var per_side := clampi(int(floor((length - 2.0) / 4.5)), 0, 3)
	if per_side == 0:
		return []
	var sides := [1.0, -1.0] if seed > 0.55 else [1.0 if seed < 0.3 else -1.0]
	var out := []
	for sd in sides:
		var count := maxi(per_side - (1 if seed > 0.8 else 0), 1)
		for i in count:
			var t := lo + length * (float(i) + 1.0) / (float(count) + 1.0)
			var p: Vector2 = m.c + m.axis * t + m.n * (m.o + sd * m.half * 0.5)
			if Geometry2D.is_point_in_polygon(p, ring):
				out.append({"pos": p, "side": sd})
	return out


## Contreforts d'une église : deux par mur long, [{pos, normal}].
static func buttress_spots(ring: PackedVector2Array, m: Dictionary) -> Array:
	var out := []
	for i in ring.size():
		var a := ring[i]
		var c := ring[(i + 1) % ring.size()]
		var d := c - a
		var l := d.length()
		if l < 9.0:
			continue
		var dir := d / l
		var nrm := Vector2(dir.y, -dir.x)
		var mid := (a + c) * 0.5
		if (mid - m.c).dot(nrm) < 0.0:
			nrm = -nrm
		var count := int(floor(l / 6.0))
		for k in count:
			out.append({"pos": a + dir * (l * (float(k) + 0.5) / float(count)), "normal": nrm})
	return out


# --- Émission -----------------------------------------------------------------------------------------------------------------------------

## Boîte posée dans le repère (axe `ax` horizontal, normale `nz` horizontale) : demi-tailles hx (le long de ax), hz (le long de nz).
static func box(b: CityBuilder, mat: String, center: Vector2, ax: Vector2, nz: Vector2, hx: float, hz: float, y0: float, y1: float) -> void:
	var st := b._dtool(mat)
	var p := func(sx: float, sz: float) -> Vector2: return center + ax * (sx * hx) + nz * (sz * hz)
	var c00: Vector2 = p.call(-1, -1)
	var c10: Vector2 = p.call(1, -1)
	var c11: Vector2 = p.call(1, 1)
	var c01: Vector2 = p.call(-1, 1)
	var h := y1 - y0
	var faces := [[c00, c10, -nz], [c10, c11, ax], [c11, c01, nz], [c01, c00, -ax]]
	for f in faces:
		var a: Vector2 = f[0]
		var c: Vector2 = f[1]
		var n2: Vector2 = f[2]
		b._quad(st, Vector3(a.x, y0, a.y), Vector3(c.x, y0, c.y), Vector3(c.x, y1, c.y), Vector3(a.x, y1, a.y), Vector3(n2.x, 0, n2.y),
			Vector2(0, 0), Vector2(1, 0), Vector2(1, h), Vector2(0, h))
	var up := Vector3.UP
	b._quad(st, Vector3(c00.x, y1, c00.y), Vector3(c10.x, y1, c10.y), Vector3(c11.x, y1, c11.y), Vector3(c01.x, y1, c01.y), up,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


static func emit_chimneys(b: CityBuilder, ring: PackedVector2Array, m: Dictionary, ground: float, seed: float, typo: String) -> int:
	var spots := chimney_spots(ring, m, seed, typo)
	for p in spots:
		var ridge := ground + CityBuilder.roof_height(m, p)
		var ax: Vector2 = m.axis
		var nz: Vector2 = m.n
		box(b, "brique", p, ax, nz, CHIMNEY * 0.5, CHIMNEY * 0.4, ridge - 0.5, ridge + 1.5)
		box(b, "pierre_public", p, ax, nz, CHIMNEY * 0.62, CHIMNEY * 0.5, ridge + 1.5, ridge + 1.64)
		box(b, "zinc", p, ax, nz, 0.12, 0.12, ridge + 1.64, ridge + 1.95)
		box(b, "zinc", p + ax * 0.2, ax, nz, 0.1, 0.1, ridge + 1.64, ridge + 1.85)
	return spots.size()


## Lucarne : corps vertical, fenêtre à encadrement de bois, petit toit à deux pans (faîtage dans le sens de la pente).
static func emit_dormers(b: CityBuilder, ring: PackedVector2Array, m: Dictionary, ground: float, seed: float, typo: String, levels: int, roof_mat: String) -> int:
	var spots := dormer_spots(ring, m, seed, typo, levels)
	for s in spots:
		var side: float = s.side
		var nz: Vector2 = m.n * side                       # vers l'extérieur du pan
		var ax: Vector2 = m.axis
		var center: Vector2 = s.pos
		var hw := DORMER_W * 0.5
		var depth := 0.55
		var front := center + nz * depth
		var back := center - nz * depth
		var y_front := ground + CityBuilder.roof_height(m, front)
		var y_back := ground + CityBuilder.roof_height(m, back)
		var top := y_front + 1.15
		var wall := b._dtool("crepi_pavillon" if typo != "colombages" else "colombages")
		var st_roof := b._dtool(roof_mat)
		var nvec := Vector3(nz.x, 0, nz.y)
		var f0 := front - ax * hw
		var f1 := front + ax * hw
		var b0 := back - ax * hw
		var b1 := back + ax * hw
		# Façade (avec la fenêtre peinte en relief : cadre de bois puis vitre).
		var cur := b._cur_color
		b._cur_color = Color(0, 0, 0, 0)
		b._quad(wall, Vector3(f0.x, y_front - 0.05, f0.y), Vector3(f1.x, y_front - 0.05, f1.y), Vector3(f1.x, top, f1.y), Vector3(f0.x, top, f0.y), nvec,
			Vector2(0, 0), Vector2(DORMER_W, 0), Vector2(DORMER_W, 1.2), Vector2(0, 1.2))
		b._cur_color = cur
		var wx := hw * 0.62
		var wy0 := y_front + 0.2
		var wy1 := y_front + 0.95
		var fr := nz * 0.02
		var w0 := front - ax * (wx + 0.07) + fr
		var w1 := front + ax * (wx + 0.07) + fr
		var cadre := b._dtool("bois_fonce")
		b._quad(cadre, Vector3(w0.x, wy0 - 0.07, w0.y), Vector3(w1.x, wy0 - 0.07, w1.y), Vector3(w1.x, wy1 + 0.07, w1.y), Vector3(w0.x, wy1 + 0.07, w0.y), nvec,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		var g0 := front - ax * wx + nz * 0.035
		var g1 := front + ax * wx + nz * 0.035
		var vitre := b._dtool("vitre")
		b._quad(vitre, Vector3(g0.x, wy0, g0.y), Vector3(g1.x, wy0, g1.y), Vector3(g1.x, wy1, g1.y), Vector3(g0.x, wy1, g0.y), nvec,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		var mullion := front + nz * 0.045
		b._quad(cadre, Vector3(mullion.x - ax.x * 0.025, wy0, mullion.y - ax.y * 0.025), Vector3(mullion.x + ax.x * 0.025, wy0, mullion.y + ax.y * 0.025),
			Vector3(mullion.x + ax.x * 0.025, wy1, mullion.y + ax.y * 0.025), Vector3(mullion.x - ax.x * 0.025, wy1, mullion.y - ax.y * 0.025), nvec,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		# Joues (côtés), qui rejoignent le pan de toit.
		b._cur_color = Color(0, 0, 0, 0)
		var jn0 := Vector3(-ax.x, 0, -ax.y)
		var jn1 := Vector3(ax.x, 0, ax.y)
		b._quad(wall, Vector3(f0.x, y_front - 0.05, f0.y), Vector3(b0.x, y_back - 0.05, b0.y), Vector3(b0.x, top, b0.y), Vector3(f0.x, top, f0.y), jn0,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1.2), Vector2(0, 1.2))
		b._quad(wall, Vector3(f1.x, y_front - 0.05, f1.y), Vector3(b1.x, y_back - 0.05, b1.y), Vector3(b1.x, top, b1.y), Vector3(f1.x, top, f1.y), jn1,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1.2), Vector2(0, 1.2))
		b._cur_color = cur
		# Fronton triangulaire + toit à deux pans.
		var apex_f := Vector3(front.x, top + 0.55, front.y)
		var apex_b := Vector3(back.x, top + 0.55 + (y_back - y_front) * 0.0, back.y)
		var ov := nz * 0.12
		var e0f := f0 + ov - ax * 0.1
		var e1f := f1 + ov + ax * 0.1
		var e0b := b0 - ax * 0.1
		var e1b := b1 + ax * 0.1
		var tl := Vector3(e0f.x, top, e0f.y)
		var tr := Vector3(e1f.x, top, e1f.y)
		var bl := Vector3(e0b.x, top, e0b.y)
		var br := Vector3(e1b.x, top, e1b.y)
		var n_l := (apex_b - apex_f).cross(tl - apex_f).normalized()
		if n_l.y < 0.0:
			n_l = -n_l
		var n_r := (apex_b - apex_f).cross(tr - apex_f).normalized()
		if n_r.y < 0.0:
			n_r = -n_r
		b._quad(st_roof, tl, apex_f + Vector3(ov.x, 0, ov.y), apex_b, bl, n_l, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		b._quad(st_roof, tr, apex_f + Vector3(ov.x, 0, ov.y), apex_b, br, n_r, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		b._cur_color = Color(0, 0, 0, 0)
		b._tri(wall, Vector3(f0.x, top, f0.y), Vector3(f1.x, top, f1.y), apex_f, nvec, f0, f1, front)
		b._cur_color = cur
	return spots.size()


## Corniche sous l'égout et soubassement de pierre autour du bâtiment.
static func emit_bands(b: CityBuilder, a: Vector2, c: Vector2, n2: Vector2, ground: float, ha: float, hc: float, typo: String, is_door_edge: bool) -> void:
	if typo == "annexe":
		return
	var out := n2 * CORNICE_OUT
	var mat := "tronc" if typo == "colombages" else "pierre_public"
	var st := b._dtool(mat)
	var nv := Vector3(n2.x, 0, n2.y)
	var cur := b._cur_color
	b._cur_color = Color.WHITE
	# Corniche : face avant et sous-face.
	var a1 := a + out
	var c1 := c + out
	b._quad(st, Vector3(a1.x, ground + ha - CORNICE_H, a1.y), Vector3(c1.x, ground + hc - CORNICE_H, c1.y), Vector3(c1.x, ground + hc, c1.y), Vector3(a1.x, ground + ha, a1.y), nv,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	b._quad(st, Vector3(a.x, ground + ha - CORNICE_H, a.y), Vector3(c.x, ground + hc - CORNICE_H, c.y), Vector3(c1.x, ground + hc - CORNICE_H, c1.y), Vector3(a1.x, ground + ha - CORNICE_H, a1.y), Vector3.DOWN,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	# Soubassement : pierre, un peu en saillie, sauf devant la porte.
	if not is_door_edge and typo != "eglise":
		var pa := a + n2 * PLINTH_OUT
		var pc := c + n2 * PLINTH_OUT
		var sp := b._dtool("pierre_public")
		b._quad(sp, Vector3(pa.x, ground, pa.y), Vector3(pc.x, ground, pc.y), Vector3(pc.x, ground + PLINTH_H, pc.y), Vector3(pa.x, ground + PLINTH_H, pa.y), nv,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		b._quad(sp, Vector3(pa.x, ground + PLINTH_H, pa.y), Vector3(pc.x, ground + PLINTH_H, pc.y), Vector3(c.x, ground + PLINTH_H, c.y), Vector3(a.x, ground + PLINTH_H, a.y), Vector3.UP,
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	b._cur_color = cur


## Auvent de porte (maisons) ou store rayé (commerces), centré sur la travée de la porte peinte par le shader.
static func emit_door_feature(b: CityBuilder, a: Vector2, c: Vector2, n2: Vector2, ground: float, seed: float, typo: String, church: bool) -> void:
	var d := c - a
	var seg := d.length()
	if seg < MIN_LEN_DOOR:
		return
	var dir := d / seg
	var off := door_offset(seed, seg, church)
	var center := a + dir * minf(off, seg - 0.4)
	var cur := b._cur_color
	b._cur_color = Color.WHITE
	if typo == "commerce":
		var width := bays(seg).y * 0.92
		var steps := 8
		for i in steps:
			var t0 := -width * 0.5 + width * float(i) / float(steps)
			var t1 := -width * 0.5 + width * float(i + 1) / float(steps)
			var mat := "toile_rouge" if i % 2 == 0 else "toile_creme"
			var st := b._dtool(mat)
			var p0 := center + dir * t0
			var p1 := center + dir * t1
			var q0 := p0 + n2 * 1.35
			var q1 := p1 + n2 * 1.35
			var top := Vector3(n2.x, 0.55, n2.y).normalized()
			b._quad(st, Vector3(p0.x, ground + 2.9, p0.y), Vector3(p1.x, ground + 2.9, p1.y), Vector3(q1.x, ground + 2.45, q1.y), Vector3(q0.x, ground + 2.45, q0.y), top,
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
			# Volant festonné.
			var vv := b._dtool(mat)
			b._quad(vv, Vector3(q0.x, ground + 2.45, q0.y), Vector3(q1.x, ground + 2.45, q1.y), Vector3(q1.x, ground + 2.27, q1.y), Vector3(q0.x, ground + 2.27, q0.y), Vector3(n2.x, 0, n2.y),
				Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	elif typo != "annexe":
		var wide := 0.95 if not church else 1.5
		var proj := 0.85 if not church else 1.4
		var st := b._dtool("tuile" if typo != "eglise" else "ardoise")
		var p0 := center - dir * wide
		var p1 := center + dir * wide
		var q0 := p0 + n2 * proj
		var q1 := p1 + n2 * proj
		var y0 := ground + (2.55 if not church else 3.6)
		var top := Vector3(n2.x, 0.8, n2.y).normalized()
		b._quad(st, Vector3(p0.x, y0 + 0.4, p0.y), Vector3(p1.x, y0 + 0.4, p1.y), Vector3(q1.x, y0, q1.y), Vector3(q0.x, y0, q0.y), top, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
		# Deux consoles de bois.
		for sgn in [-1.0, 1.0]:
			var base: Vector2 = center + dir * (wide * 0.8 * sgn)
			box(b, "tronc", base + n2 * 0.25, dir, n2, 0.04, 0.25, y0 - 0.25, y0 - 0.15)
	b._cur_color = cur


static func emit_buttresses(b: CityBuilder, ring: PackedVector2Array, m: Dictionary, ground: float, wall_h: float) -> int:
	var spots := buttress_spots(ring, m)
	for s in spots:
		var nz: Vector2 = s.normal
		var ax := Vector2(-nz.y, nz.x)
		var p: Vector2 = s.pos + nz * 0.45
		box(b, "pierre_eglise", p, ax, nz, 0.35, 0.45, ground, ground + wall_h * 0.85)
		box(b, "pierre_eglise", p + nz * 0.18, ax, nz, 0.3, 0.3, ground + wall_h * 0.85, ground + wall_h * 0.97)
	return spots.size()
