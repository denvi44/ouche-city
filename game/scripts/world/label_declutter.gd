class_name LabelDeclutter
extends Node
## Anti-superposition des noms flottants (lieux de mission, noms de joueurs, PNJ) : toutes les 0,15 s, on projette chaque étiquette
## du groupe « etiquettes » à l'écran ; si elle chevauche une étiquette déjà retenue (plus proche, ou prioritaire), on la masque.
## Les étiquettes sont retenues dans l'ordre : priorité (méta « prio », plus petit = d'abord), puis distance à la caméra.

const GROUP := "etiquettes"
const PERIOD := 0.15
const PAD := 6.0                  # marge (pixels) autour de chaque étiquette

var _t := 0.0
var _hidden := {}                 # instance_id -> Label3D masqué par nous


## Fonction pure (testée) : `rects` triés par ordre de priorité ; renvoie pour chacun s'il est retenu (aucun chevauchement avec un retenu).
static func select(rects: Array, pad := PAD) -> Array:
	var kept: Array[Rect2] = []
	var out: Array = []
	for r: Rect2 in rects:
		var g := r.grow(pad * 0.5)
		var ok := true
		for k in kept:
			if g.intersects(k.grow(pad * 0.5)):
				ok = false
				break
		out.append(ok)
		if ok:
			kept.append(r)
	return out


## Étiquettes et bulles posées dans le monde : de près elles deviendraient géantes ; on les rétrécit pour que leur taille
## à l'écran ne dépasse jamais celle qu'elles ont à REF_DIST mètres.
const REF_DIST := 9.0
const MIN_SCALE := 0.3


static func near_scale(dist: float) -> float:
	return clampf(dist / REF_DIST, MIN_SCALE, 1.0)


func _cap_sizes() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for g in [GROUP, "bulles"]:
		for n in get_tree().get_nodes_in_group(g):
			var l := n as Node3D
			if l == null or (l is Label3D and (l as Label3D).fixed_size):
				continue
			var k := near_scale(cam.global_position.distance_to(l.global_position))
			l.scale = Vector3(k, k, k)


func _process(delta: float) -> void:
	_cap_sizes()
	_t += delta
	if _t < PERIOD:
		return
	_t = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Réaffiche d'abord ce que nous avions masqué.
	for id in _hidden.keys():
		var l: Label3D = _hidden[id]
		if is_instance_valid(l):
			l.visible = true
	_hidden.clear()
	var items: Array = []   # [prio, distance, label, rect]
	for n in get_tree().get_nodes_in_group(GROUP):
		var l := n as Label3D
		if l == null or not l.is_visible_in_tree():
			continue
		var p := l.global_position
		if cam.is_position_behind(p):
			continue
		var rect: Rect2
		if l.fixed_size:
			# Taille constante à l'écran : estimation d'après le texte (≈ 12,5 px par caractère pour font_size 48, pixel_size 0,0007).
			var c := cam.unproject_position(p)
			var k := l.pixel_size / 0.0007
			var w := float(l.text.length()) * float(l.font_size) * 0.26 * k
			var h := float(l.font_size) * 0.9 * k
			rect = Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
		else:
			# Taille dans le monde : on projette les coins de la boîte englobante.
			var bb := l.get_aabb()
			var lo := Vector2(INF, INF)
			var hi := Vector2(-INF, -INF)
			for i in 8:
				var q := cam.unproject_position(l.global_transform * bb.get_endpoint(i))
				lo = lo.min(q)
				hi = hi.max(q)
			rect = Rect2(lo, hi - lo)
		items.append([int(l.get_meta("prio", 5)), cam.global_position.distance_to(p), l, rect])
	items.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var keep := select(items.map(func(i): return i[3]))
	for i in items.size():
		if not keep[i]:
			var l: Label3D = items[i][2]
			l.visible = false
			_hidden[l.get_instance_id()] = l
