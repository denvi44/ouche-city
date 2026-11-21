class_name HudWidgets
extends RefCounted
## Éléments graphiques du HUD (agent 03 / 05) : jauge, minicarte, balises d'objectif en bord d'écran.
## Les calculs (couleurs, projections, bords) sont des fonctions statiques pures, testées sans scène.

const INK := Color(0.12, 0.09, 0.08)
const CREAM := Color(0.97, 0.93, 0.82)
const OK := Color(0.4, 0.75, 0.4)
const WARN := Color(0.95, 0.75, 0.2)
const BAD := Color(0.85, 0.25, 0.2)


## Couleur de remplissage d'une jauge : la couleur de la mission, ou vert → jaune → rouge si « danger » (haut = mauvais),
## rouge quand « low_is_bad » et que la valeur tombe sous 25 %.
static func fill_color(spec: Dictionary) -> Color:
	var v: float = spec.value
	if spec.get("danger", false):
		return OK.lerp(WARN, clampf(v / 0.6, 0.0, 1.0)).lerp(BAD, clampf((v - 0.6) / 0.4, 0.0, 1.0))
	if spec.get("low_is_bad", false) and v < 0.25:
		return BAD.lerp(WARN, v / 0.25)
	return spec.color


## Rectangle (x, largeur) d'une plage [a, b] dans une barre de largeur `w`.
static func zone_span(zone: Vector2, w: float) -> Vector2:
	var a := clampf(zone.x, 0.0, 1.0)
	var b := clampf(zone.y, 0.0, 1.0)
	return Vector2(a * w, maxf(b - a, 0.0) * w)


## Position d'un point du monde (x, z) sur la minicarte : centre = joueur, échelle en pixels par mètre, repère nord en haut.
static func to_map(world: Vector2, center_world: Vector2, px_per_m: float, map_center: Vector2) -> Vector2:
	var d := world - center_world
	return map_center + Vector2(d.x, d.y) * px_per_m


## Ramène un point de la minicarte sur le bord du disque de rayon `radius` s'il est dehors.
static func clamp_to_disc(p: Vector2, map_center: Vector2, radius: float) -> Vector2:
	var d := p - map_center
	if d.length() <= radius:
		return p
	return map_center + d.normalized() * radius


## Point du bord de l'écran (marge `margin`) dans la direction d'un objectif hors champ ; `screen` : position projetée (peut être
## négative ou derrière la caméra, auquel cas on l'inverse depuis le centre).
static func edge_point(screen: Vector2, view: Vector2, margin: float, behind := false) -> Vector2:
	var c := view * 0.5
	var d := screen - c
	if behind:
		d = -d
	if d.length() < 0.001:
		d = Vector2(0, 1)
	var k := minf((c.x - margin) / maxf(absf(d.x), 0.001), (c.y - margin) / maxf(absf(d.y), 0.001))
	return c + d * k


static func on_screen(screen: Vector2, view: Vector2, margin: float, behind: bool) -> bool:
	return not behind and screen.x > margin and screen.x < view.x - margin and screen.y > margin and screen.y < view.y - margin


# --- Jauge ----------------------------------------------------------------------------------------------------------------------------------

class GaugeBar:
	extends Control
	var spec := {}
	var scale_font := 1.0
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(440, 42)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_spec(s: Dictionary, text_scale: float) -> void:
		spec = s
		scale_font = text_scale
		custom_minimum_size = Vector2(440, 40 * text_scale + 6)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if spec.get("shake", false) or (spec.get("low_is_bad", false) and float(spec.get("value", 1.0)) < 0.2):
			queue_redraw()

	func _draw() -> void:
		if spec.is_empty():
			return
		var font := ThemeDB.fallback_font
		var fs := int(16 * scale_font)
		var w := size.x
		var bar_h := 16.0 * scale_font
		var y0 := size.y - bar_h - 2.0
		var jitter := Vector2(sin(_t * 70.0) * 1.5, 0) if spec.get("shake", false) else Vector2.ZERO
		# Libellé et valeur.
		draw_string(font, Vector2(2, y0 - 6) + jitter, str(spec.label), HORIZONTAL_ALIGNMENT_LEFT, w * 0.62, fs, CREAM)
		var txt := str(spec.get("text", ""))
		if txt != "":
			draw_string(font, Vector2(w * 0.38, y0 - 6) + jitter, txt, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.62, fs, CREAM)
		# Piste.
		var track := Rect2(Vector2(0, y0) + jitter, Vector2(w, bar_h))
		draw_rect(track.grow(2.0), INK)
		draw_rect(track, Color(0.25, 0.22, 0.2))
		# Plage à viser (verte) ou à éviter (rouge si « danger »).
		if spec.has("zone"):
			var zs := HudWidgets.zone_span(spec.zone, w)
			var zc := Color(0.4, 0.75, 0.4, 0.55) if not spec.get("danger", false) else Color(0.85, 0.25, 0.2, 0.45)
			draw_rect(Rect2(track.position + Vector2(zs.x, 0), Vector2(zs.y, bar_h)), zc)
			if spec.has("zone2"):
				var z2 := HudWidgets.zone_span(spec.zone2, w)
				draw_rect(Rect2(track.position + Vector2(z2.x, 0), Vector2(z2.y, bar_h)), Color(1.0, 0.95, 0.5, 0.7))
		if spec.has("danger_from"):
			var df := HudWidgets.zone_span(Vector2(float(spec.danger_from), 1.0), w)
			draw_rect(Rect2(track.position + Vector2(df.x, 0), Vector2(df.y, bar_h)), Color(0.85, 0.25, 0.2, 0.45))
		var v := float(spec.value)
		if spec.get("cursor", false):
			# Curseur qui défile (rythme, jeu de timing) : trait épais.
			var cx := v * w
			draw_rect(Rect2(track.position + Vector2(cx - 3, -3), Vector2(6, bar_h + 6)), CREAM)
			draw_rect(Rect2(track.position + Vector2(cx - 2, -2), Vector2(4, bar_h + 4)), spec.color)
		else:
			var col := HudWidgets.fill_color(spec)
			if spec.get("low_is_bad", false) and v < 0.2:
				col = col.lightened(0.25 * (0.5 + 0.5 * sin(_t * 8.0)))
			draw_rect(Rect2(track.position, Vector2(w * v, bar_h)), col)
			draw_rect(Rect2(track.position, Vector2(w * v, bar_h * 0.35)), col.lightened(0.25))
		if spec.has("marker"):
			var mx := float(spec.marker) * w
			draw_rect(Rect2(track.position + Vector2(mx - 2, -4), Vector2(4, bar_h + 8)), BAD)


# --- Minicarte -------------------------------------------------------------------------------------------------------------------------------

class Minimap:
	extends Control
	const RADIUS_M := 130.0
	static var _roads: Array = []          # [{pts: PackedVector2Array, kind: String}]
	var player_pos := Vector2.ZERO
	var player_yaw := 0.0
	var markers: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(210, 210)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	static func load_roads() -> void:
		if not _roads.is_empty():
			return
		var data = CityBuilder.read_json("res://assets/city/road_graph.json")
		if data is Dictionary:
			for e in data.get("edges", []):
				var pts := PackedVector2Array()
				for p in e.points:
					pts.append(Vector2(float(p[0]), float(p[1])))
				_roads.append({"pts": pts, "kind": str(e.get("kind", ""))})

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		var k := r / RADIUS_M
		draw_circle(c, r + 4.0, HudWidgets.INK)
		draw_circle(c, r, Color(0.2, 0.24, 0.33))          # fond ardoise : jamais de vert sous les routes
		load_roads()
		# Disque de découpe : les routes sont coupées proprement au bord, jamais abandonnées parce qu'un sommet est loin.
		var disc := PackedVector2Array()
		for i in 40:
			disc.append(c + Vector2(cos(TAU * float(i) / 40.0), sin(TAU * float(i) / 40.0)) * (r - 1.0))
		var layers := [["residential", 5.0, Color(0.93, 0.88, 0.76)], ["major", 8.0, Color(1.0, 0.97, 0.88)], ["small", 2.5, Color(0.7, 0.68, 0.62)]]
		for layer in [0, 1]:      # 0 : liseré sombre, 1 : remplissage clair
			for road in _roads:
				var pts: PackedVector2Array = road.pts
				var near := false
				for p in pts:
					if p.distance_to(player_pos) < RADIUS_M * 1.6:
						near = true
						break
				if not near:
					continue
				var poly := PackedVector2Array()
				for p in pts:
					poly.append(HudWidgets.to_map(p, player_pos, k, c))
				var kind: String = road.kind
				var spec: Array = layers[1] if kind in ["secondary", "primary", "tertiary"] else (layers[0] if kind == "residential" else layers[2])
				var wd: float = spec[1]
				var col: Color = spec[2] if layer == 1 else HudWidgets.INK
				for piece in Geometry2D.intersect_polyline_with_polygon(poly, disc):
					draw_polyline(piece, col, wd + (0.0 if layer == 1 else 2.5), true)
		# Balises : points colorés (au bord du disque quand elles sont loin).
		for m in markers:
			var wp := Vector2(m.pos.x, m.pos.z)
			var mp := HudWidgets.to_map(wp, player_pos, k, c)
			var inside := mp.distance_to(c) <= r
			var q := HudWidgets.clamp_to_disc(mp, c, r - 6.0)
			draw_circle(q, 7.0 if inside else 5.0, HudWidgets.INK)
			draw_circle(q, 5.0 if inside else 3.5, m.color)
		# Joueur : flèche orientée.
		var f := Vector2(-sin(player_yaw), -cos(player_yaw))
		var s := Vector2(-f.y, f.x)
		draw_colored_polygon(PackedVector2Array([c + f * 11.0, c - f * 7.0 + s * 7.0, c - f * 3.0, c - f * 7.0 - s * 7.0]), HudWidgets.INK)
		draw_colored_polygon(PackedVector2Array([c + f * 8.0, c - f * 5.0 + s * 5.0, c - f * 2.0, c - f * 5.0 - s * 5.0]), Color(0.3, 0.55, 0.95))
		draw_arc(c, r, 0.0, TAU, 48, HudWidgets.INK, 3.0)
		# Nord.
		draw_string(ThemeDB.fallback_font, c + Vector2(-5, -r + 15), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, HudWidgets.INK)


# --- Balises à l'écran ----------------------------------------------------------------------------------------------------------------------------

class MarkerLayer:
	extends Control
	var markers: Array = []
	var text_scale := 1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var view := size
		var font := ThemeDB.fallback_font
		var fs := int(15 * text_scale)
		var taken: Array = []                 # rectangles des libellés déjà posés : on décale les suivants pour ne pas les superposer
		for m in markers:
			var pos: Vector3 = m.pos + Vector3(0, 2.5, 0)
			var behind := cam.is_position_behind(pos)
			var sp := cam.unproject_position(pos)
			var dist := cam.global_position.distance_to(m.pos)
			var label := "%s  %d m" % [m.label, int(dist)]
			if HudWidgets.on_screen(sp, view, 24.0, behind):
				if dist < 6.0:
					continue
				_diamond(sp, m.color, 9.0)
				var at := _free_slot(taken, sp + Vector2(-90, -16))
				draw_string(font, at, label, HORIZONTAL_ALIGNMENT_CENTER, 180, fs, HudWidgets.CREAM)
			else:
				var e := HudWidgets.edge_point(sp, view, 34.0, behind)
				var dir := (e - view * 0.5).normalized()
				_arrow(e, dir, m.color)
				var off := Vector2(-90, -26) if e.y > 60.0 else Vector2(-90, 34)
				draw_string(font, _free_slot(taken, e + off), label, HORIZONTAL_ALIGNMENT_CENTER, 180, fs, HudWidgets.CREAM)

	## Place un libellé de 180 × 20 px au plus près de `p` sans recouvrir un libellé déjà posé (décalage vertical de 20 px).
	static func free_slot(taken: Array, p: Vector2) -> Vector2:
		var q := p
		for _i in 8:
			var r := Rect2(q + Vector2(0, -16), Vector2(180, 20))
			var hit := false
			for t in taken:
				if (t as Rect2).intersects(r):
					hit = true
					break
			if not hit:
				taken.append(r)
				return q
			q.y += 20.0
		return q

	func _free_slot(taken: Array, p: Vector2) -> Vector2:
		return free_slot(taken, p)

	func _diamond(p: Vector2, col: Color, r: float) -> void:
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r - 3), p + Vector2(r + 3, 0), p + Vector2(0, r + 3), p + Vector2(-r - 3, 0)]), HudWidgets.INK)
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col)

	func _arrow(p: Vector2, dir: Vector2, col: Color) -> void:
		var s := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 18.0, p - dir * 10.0 + s * 13.0, p - dir * 4.0, p - dir * 10.0 - s * 13.0]), HudWidgets.INK)
		draw_colored_polygon(PackedVector2Array([p + dir * 13.0, p - dir * 7.0 + s * 9.0, p - dir * 3.0, p - dir * 7.0 - s * 9.0]), col)
