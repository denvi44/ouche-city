class_name Supermarket
extends RefCounted
## Supermarché « Le Panier de Frouch » (agent 04 / 05) : bâtiment-décor sans toit (la caméra voit l'intérieur d'en haut),
## avec collisions (murs, gondoles, comptoirs). Repère local : origine au centre, +Z = devant (côté route, porte),
## X le long de la façade. Dimensions : murs à x = ±12,5 et z = -8,5 / +8,5 ; porte automatique |x| < 2,2.
## Les positions des rayons, de la caisse et des chariots sont partagées avec la mission 06 (constantes ci-dessous).

const HALF_X := 12.5
const HALF_Z := 8.5
const DOOR_HALF := 2.2
const WALL_H := 3.2
## Rangées de gondoles : z, demi-longueur (x de -L à +L).
const ROWS := [{"z": -4.5, "half": 9.0}, {"z": -1.5, "half": 9.0}, {"z": 2.0, "half": 9.0}]
const CHECKOUTS := [Vector3(8.5, 0, 5.8), Vector3(4.5, 0, 5.8)]
const WALL_COLOR := Color(0.93, 0.9, 0.82)


## Positions des objets de la liste de courses (repère local, plan x-z) : où l'on se tient pour les prendre.
static func shopping_spots() -> Dictionary:
	return {
		"baguette": Vector3(9.5, 0, -6.6),
		"camembert": Vector3(-7.0, 0, -6.6),
		"lait": Vector3(-2.5, 0, -6.6),
		"cidre": Vector3(4.0, 0, -3.0),
		"palets": Vector3(-6.0, 0, 0.25),
		"litiere": Vector3(6.5, 0, 3.6),
	}


static func _solid(root: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = pos
	body.add_child(shape)
	root.add_child(body)


static func _wall(k: PropKit, size: Vector3, pos: Vector3) -> void:
	k.add_box(size, pos, WALL_COLOR)


## Construit le magasin complet. `with_collision` faux pour les mesures.
static func build(with_collision := true, lift := 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Supermarche"
	var inner := _build_inner(with_collision)
	inner.position.y = lift
	root.add_child(inner)
	return root


## Hauteur dont il faut relever le sol du magasin : le point le plus haut du terrain sous l'emprise (+ 4 cm), pour qu'aucune
## partie du sol ne soit enterrée. `origin` : centre (monde, y ignoré) ; `facing` : cap de la façade.
static func lift_for(height_at: Callable, origin: Vector3, facing: float) -> float:
	var fx := sin(facing)
	var fz := cos(facing)
	var hmax := -INF
	var hc: float = height_at.call(origin.x, origin.z)
	for ix in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		for iz in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			var x: float = origin.x + fz * ix * HALF_X + fx * iz * HALF_Z
			var z: float = origin.z - fx * ix * HALF_X + fz * iz * HALF_Z
			hmax = maxf(hmax, height_at.call(x, z))
	return maxf(hmax - hc, 0.0) + 0.04


static func _build_inner(with_collision: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Interieur"
	var shell := PropKit.new()
	# Dalle et fondation (descend sous le terrain en pente).
	shell.add_box(Vector3(HALF_X * 2 + 1.0, 0.1, HALF_Z * 2 + 1.0), Vector3(0, 0.0, 0), Color(0.78, 0.78, 0.8))
	shell.add_box(Vector3(HALF_X * 2 + 0.6, 4.0, HALF_Z * 2 + 0.6), Vector3(0, -2.0, 0), Color(0.6, 0.6, 0.62))
	# Carrelage en damier (dalles de 2 m, deux tons).
	for ix in int(HALF_X):
		for iz in int(HALF_Z):
			if (ix + iz) % 2 == 0:
				shell.add_box(Vector3(2.0, 0.02, 2.0), Vector3(-HALF_X + 1.0 + ix * 2.0 + 0.0, 0.06, -HALF_Z + 1.0 + iz * 2.0), Color(0.86, 0.87, 0.9))
	# Murs (le côté route a la porte).
	_wall(shell, Vector3(HALF_X * 2, WALL_H, 0.3), Vector3(0, WALL_H / 2, -HALF_Z))
	_wall(shell, Vector3(0.3, WALL_H, HALF_Z * 2), Vector3(-HALF_X, WALL_H / 2, 0))
	_wall(shell, Vector3(0.3, WALL_H, HALF_Z * 2), Vector3(HALF_X, WALL_H / 2, 0))
	var side_w := HALF_X - DOOR_HALF
	_wall(shell, Vector3(side_w, WALL_H, 0.3), Vector3(-(DOOR_HALF + side_w / 2), WALL_H / 2, HALF_Z))
	_wall(shell, Vector3(side_w, WALL_H, 0.3), Vector3(DOOR_HALF + side_w / 2, WALL_H / 2, HALF_Z))
	shell.add_box(Vector3(DOOR_HALF * 2, 0.7, 0.3), Vector3(0, WALL_H - 0.35, HALF_Z), WALL_COLOR)
	# Vitrines de façade (bandeaux de verre) et portes coulissantes ouvertes.
	for sx in [-1.0, 1.0]:
		shell.add_box(Vector3(side_w - 1.0, 1.5, 0.32), Vector3(sx * (DOOR_HALF + side_w / 2), 1.8, HALF_Z + 0.02), Color(0.6, 0.78, 0.9))
		shell.add_box(Vector3(0.06, WALL_H, 0.34), Vector3(sx * DOOR_HALF, WALL_H / 2, HALF_Z), Color(0.35, 0.37, 0.42))
	# Bandeau rouge sur le haut des murs, plinthe.
	shell.add_box(Vector3(HALF_X * 2 + 0.4, 0.35, 0.4), Vector3(0, WALL_H + 0.1, -HALF_Z), Color(0.88, 0.2, 0.2))
	shell.add_box(Vector3(0.4, 0.35, HALF_Z * 2 + 0.4), Vector3(-HALF_X, WALL_H + 0.1, 0), Color(0.88, 0.2, 0.2))
	shell.add_box(Vector3(0.4, 0.35, HALF_Z * 2 + 0.4), Vector3(HALF_X, WALL_H + 0.1, 0), Color(0.88, 0.2, 0.2))
	shell.add_box(Vector3(HALF_X * 2 + 0.4, 0.35, 0.4), Vector3(0, WALL_H + 0.1, HALF_Z), Color(0.88, 0.2, 0.2))
	# Auvent d'entrée en saillie.
	shell.add_box(Vector3(7.0, 0.2, 2.4), Vector3(0, WALL_H + 0.1, HALF_Z + 1.2), Color(0.88, 0.2, 0.2))
	for sx in [-3.2, 3.2]:
		shell.add_box(Vector3(0.18, WALL_H, 0.18), Vector3(sx, WALL_H / 2, HALF_Z + 2.2), Color(0.35, 0.37, 0.42))
	root.add_child(shell.build())
	if with_collision:
		_solid(root, Vector3(HALF_X * 2, WALL_H, 0.3), Vector3(0, WALL_H / 2, -HALF_Z))
		_solid(root, Vector3(0.3, WALL_H, HALF_Z * 2), Vector3(-HALF_X, WALL_H / 2, 0))
		_solid(root, Vector3(0.3, WALL_H, HALF_Z * 2), Vector3(HALF_X, WALL_H / 2, 0))
		_solid(root, Vector3(side_w, WALL_H, 0.3), Vector3(-(DOOR_HALF + side_w / 2), WALL_H / 2, HALF_Z))
		_solid(root, Vector3(side_w, WALL_H, 0.3), Vector3(DOOR_HALF + side_w / 2, WALL_H / 2, HALF_Z))
		_solid(root, Vector3(40.0, 1.0, 40.0), Vector3(0, -0.5, 0))        # sol (le terrain peut être plus bas)
	# Rayons : gondoles (collision à hauteur de poitrine), frigos, boulangerie, caisses, chariots.
	var seed := 11
	for row in ROWS:
		# Gondole de 18 m = trois modules de 6 m (budget de triangles par accessoire).
		for mod in 3:
			var n := PropKit.shelf(6.0, seed).build()
			n.position = Vector3(-6.0 + mod * 6.0, 0.1, float(row.z))
			root.add_child(n)
			seed += 7
		if with_collision:
			_solid(root, Vector3(float(row.half) * 2.0, 1.9, 1.0), Vector3(0, 0.95, float(row.z)))
	var fr := PropKit.fridge(10.0).build()
	fr.position = Vector3(-5.0, 0.1, -HALF_Z + 0.6)
	root.add_child(fr)
	if with_collision:
		_solid(root, Vector3(10.0, 2.1, 0.9), Vector3(-5.0, 1.05, -HALF_Z + 0.6))
	var bk := PropKit.bakery(5.0).build()
	bk.position = Vector3(9.5, 0.1, -HALF_Z + 0.7)
	root.add_child(bk)
	if with_collision:
		_solid(root, Vector3(5.0, 1.0, 0.9), Vector3(9.5, 0.5, -HALF_Z + 0.7))
	for c in CHECKOUTS:
		var ck := PropKit.checkout().build()
		ck.position = c + Vector3(0, 0.1, 0)
		root.add_child(ck)
		if with_collision:
			_solid(root, Vector3(2.8, 1.0, 0.8), c + Vector3(0, 0.5, 0))
	for i in 5:
		var cd := PropKit.caddie().build()
		cd.position = Vector3(-10.5 + i * 0.0, 0.1, 5.0 + i * 0.35)
		cd.rotation.y = 0.0
		root.add_child(cd)
	# Enseigne au-dessus de l'entrée.
	var sign_k := PropKit.super_sign().build()
	sign_k.position = Vector3(0, WALL_H + 1.2, HALF_Z + 0.3)
	root.add_child(sign_k)
	var label := Label3D.new()
	label.text = "LE PANIER DE FROUCH"
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = Color(0.98, 0.95, 0.85)
	label.outline_size = 10
	label.outline_modulate = Color(0.55, 0.08, 0.08)
	label.position = Vector3(0, WALL_H + 1.2, HALF_Z + 0.5)
	root.add_child(label)
	return root
