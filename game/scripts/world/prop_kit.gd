class_name PropKit
extends RefCounted
## Atelier d'accessoires détaillés (agent 04) : mobilier de rue, ferme, fête, animaux.
##
## Chaque accessoire est assemblé à partir de primitives (boîtes, cylindres, sphères, cônes) fusionnées en un seul
## maillage à une surface par couleur, avec le contour « inverted hull » du reste du décor (HullOutline). Aucun
## fichier binaire : tout vient du code, donc identique sous Windows et macOS et sans Git LFS.
## Repère : +Y en haut, +Z = devant, origine au sol. Dimensions en mètres.

const SHADER := preload("res://shaders/toon.gdshader")

static var _materials := {}

var _parts := {}                    # clé "couleur|lueur" -> Array de [Mesh, Transform3D]


# --- Matériaux ----------------------------------------------------------------------------------------------------------

static func material_for(color: Color, glow := false) -> Material:
	var key := "%s|%s" % [color.to_html(false), glow]
	if _materials.has(key):
		return _materials[key]
	var m: Material
	if glow:
		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_color = color
		m = sm
	else:
		var tm := ShaderMaterial.new()
		tm.shader = SHADER
		tm.set_shader_parameter("couleur", color)
		m = tm
	_materials[key] = m
	return m


# --- Primitives -----------------------------------------------------------------------------------------------------------

func _add(mesh: Mesh, pos: Vector3, rot: Vector3, color: Color, glow: bool, scale := Vector3.ONE) -> PropKit:
	var key := "%s|%s" % [color.to_html(false), glow]
	if not _parts.has(key):
		_parts[key] = []
	var basis := Basis.from_euler(rot) * Basis.from_scale(scale)
	_parts[key].append([mesh, Transform3D(basis, pos)])
	return self


func add_box(size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO, glow := false) -> PropKit:
	var m := BoxMesh.new()
	m.size = size
	return _add(m, pos, rot, color, glow)


func add_cyl(r_top: float, r_bottom: float, height: float, pos: Vector3, color: Color, rot := Vector3.ZERO, segments := 8, glow := false) -> PropKit:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return _add(m, pos, rot, color, glow)


func add_sphere(radius: float, pos: Vector3, color: Color, scale := Vector3.ONE, segments := 8, glow := false) -> PropKit:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 3)
	return _add(m, pos, Vector3.ZERO, color, glow, scale)


## Assemble un autre accessoire dans celui-ci, placé par `xf`.
func append(other: PropKit, xf: Transform3D) -> PropKit:
	for key in other._parts:
		if not _parts.has(key):
			_parts[key] = []
		for p in other._parts[key]:
			_parts[key].append([p[0], xf * (p[1] as Transform3D)])
	return self


func part_count() -> int:
	var n := 0
	for key in _parts:
		n += _parts[key].size()
	return n


# --- Maillages ------------------------------------------------------------------------------------------------------------

## Maillage fusionné : une surface par couleur (matériau toon, ou lueur sans éclairage).
func mesh() -> ArrayMesh:
	var out := ArrayMesh.new()
	var keys := _parts.keys()
	keys.sort()
	for key in keys:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p in _parts[key]:
			st.append_from(p[0], 0, p[1])
		var halves: PackedStringArray = str(key).split("|")
		st.set_material(material_for(Color.html(halves[0]), halves[1] == "true"))
		st.commit(out)
	return out


## Contour (coque gonflée à normales lissées) des parties éclairées.
func outline_mesh() -> ArrayMesh:
	var tris := []
	for key in _parts:
		if str(key).ends_with("|true"):
			continue
		for p in _parts[key]:
			tris.append_array(HullOutline.tris_of(p[0], p[1]))
	return HullOutline.build(tris)


func triangle_count() -> int:
	var n := 0
	for key in _parts:
		for p in _parts[key]:
			n += (p[0] as Mesh).get_faces().size() / 3
	return n


func bounds() -> AABB:
	var box := AABB()
	var first := true
	for key in _parts:
		for p in _parts[key]:
			var b: AABB = (p[1] as Transform3D) * (p[0] as Mesh).get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


## Nœud prêt à poser : corps et contour.
func build(outline := true) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "Corps"
	body.mesh = mesh()
	root.add_child(body)
	if outline:
		var hull := MeshInstance3D.new()
		hull.name = "Contour"
		hull.mesh = outline_mesh()
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(hull)
	return root


# --- Palette (style guide : aplats chauds, bois, pierre, tissus vichy) -----------------------------------------------------------

const WOOD := Color(0.55, 0.38, 0.24)
const WOOD_DARK := Color(0.36, 0.25, 0.17)
const IRON := Color(0.17, 0.18, 0.2)
const STONE := Color(0.62, 0.6, 0.55)
const CREAM := Color(0.96, 0.93, 0.84)
const RED := Color(0.82, 0.2, 0.2)
const GLASS := Color(1.0, 0.86, 0.5)
const STRAW := Color(0.86, 0.72, 0.32)
const GREEN := Color(0.32, 0.55, 0.3)


# --- Mobilier de rue -----------------------------------------------------------------------------------------------------------------

## Lampadaire de village : socle, fût, collier, crosse recourbée, lanterne à toit et verre lumineux.
static func lamp() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(0.2, 0.26, 0.5, Vector3(0, 0.25, 0), IRON, Vector3.ZERO, 8)
	k.add_cyl(0.1, 0.14, 3.6, Vector3(0, 2.3, 0), IRON, Vector3.ZERO, 8)
	k.add_cyl(0.17, 0.17, 0.12, Vector3(0, 0.85, 0), IRON, Vector3.ZERO, 8)
	k.add_cyl(0.15, 0.15, 0.1, Vector3(0, 3.7, 0), IRON, Vector3.ZERO, 8)
	k.add_box(Vector3(0.1, 0.1, 0.85), Vector3(0, 4.05, 0.38), IRON, Vector3(0.35, 0, 0))
	k.add_box(Vector3(0.08, 0.08, 0.35), Vector3(0, 4.3, 0.1), IRON, Vector3(-0.7, 0, 0))
	k.add_box(Vector3(0.36, 0.06, 0.36), Vector3(0, 4.18, 0.82), IRON)
	k.add_box(Vector3(0.3, 0.38, 0.3), Vector3(0, 3.96, 0.82), GLASS, Vector3.ZERO, true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			k.add_box(Vector3(0.04, 0.4, 0.04), Vector3(sx * 0.16, 3.96, 0.82 + sz * 0.16), IRON)
	k.add_cyl(0.0, 0.3, 0.26, Vector3(0, 4.34, 0.82), IRON, Vector3.ZERO, 4)
	k.add_sphere(0.05, Vector3(0, 4.5, 0.82), IRON)
	return k


## Banc public : assise à trois lattes, dossier à deux lattes, accoudoirs et pieds de fonte.
static func bench() -> PropKit:
	var k := PropKit.new()
	for i in 3:
		k.add_box(Vector3(1.7, 0.05, 0.14), Vector3(0, 0.46, -0.16 + i * 0.16), WOOD)
	for i in 2:
		k.add_box(Vector3(1.7, 0.16, 0.04), Vector3(0, 0.78 + i * 0.2, -0.3), WOOD, Vector3(-0.15, 0, 0))
	for sx in [-0.75, 0.75]:
		k.add_box(Vector3(0.06, 0.46, 0.5), Vector3(sx, 0.23, 0), IRON)
		k.add_box(Vector3(0.06, 0.06, 0.5), Vector3(sx, 0.62, 0), IRON)
		k.add_box(Vector3(0.06, 0.5, 0.06), Vector3(sx, 0.7, -0.3), IRON, Vector3(-0.15, 0, 0))
	return k


## Jardinière en bois cerclée de fer, terre et fleurs de trois couleurs.
static func planter() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(0.9, 0.5, 0.42), Vector3(0, 0.25, 0), WOOD_DARK)
	k.add_box(Vector3(0.96, 0.06, 0.48), Vector3(0, 0.52, 0), WOOD)
	k.add_box(Vector3(0.8, 0.06, 0.32), Vector3(0, 0.55, 0), Color(0.25, 0.17, 0.11))
	for sx in [-0.3, 0.3]:
		k.add_box(Vector3(0.05, 0.52, 0.45), Vector3(sx, 0.26, 0), IRON)
	var cols := [Color(0.9, 0.3, 0.35), Color(0.97, 0.8, 0.25), Color(0.7, 0.45, 0.85)]
	for i in 7:
		var x := -0.34 + i * 0.113
		k.add_cyl(0.015, 0.015, 0.22, Vector3(x, 0.68, (i % 3 - 1) * 0.08), GREEN, Vector3.ZERO, 4)
		k.add_sphere(0.075, Vector3(x, 0.82 + (i % 2) * 0.04, (i % 3 - 1) * 0.08), cols[i % 3], Vector3(1, 0.8, 1), 6)
	return k


## Poulailler de campagne (+Z = vers la rue) : abri sur pilotis à toit de zinc, rampe à tasseaux, pondoir latéral,
## enclos grillagé avec abreuvoir, mangeoire, paille et quatre poules. Largeur 3 m, profondeur 3,4 m.
static func coop() -> PropKit:
	var k := PropKit.new()
	var zinc := Color(0.55, 0.58, 0.6)
	# Abri : caisse en planches sur quatre pieds.
	for sx in [-0.7, 0.7]:
		for sz in [-0.45, 0.45]:
			k.add_box(Vector3(0.1, 0.5, 0.1), Vector3(sx, 0.25, 0.9 + sz), WOOD_DARK)
	k.add_box(Vector3(1.7, 1.0, 1.3), Vector3(0, 1.0, 0.9), WOOD)
	for i in 6:
		k.add_box(Vector3(0.03, 1.02, 1.32), Vector3(-0.7 + i * 0.28, 1.0, 0.9), WOOD_DARK)
	# Toit à deux pans (zinc) avec débord.
	k.add_box(Vector3(1.0, 0.07, 1.55), Vector3(-0.42, 1.72, 0.9), zinc, Vector3(0, 0, 0.42))
	k.add_box(Vector3(1.0, 0.07, 1.55), Vector3(0.42, 1.72, 0.9), zinc, Vector3(0, 0, -0.42))
	k.add_box(Vector3(0.12, 0.08, 1.58), Vector3(0, 1.95, 0.9), IRON)
	# Trappe d'accès côté enclos et rampe à tasseaux.
	k.add_box(Vector3(0.36, 0.46, 0.04), Vector3(0.0, 0.88, 1.56), Color(0.1, 0.08, 0.06))
	k.add_box(Vector3(0.42, 0.04, 1.0), Vector3(0.0, 0.3, 2.0), WOOD, Vector3(0.55, 0, 0))
	for i in 5:
		k.add_box(Vector3(0.42, 0.03, 0.04), Vector3(0.0, 0.18 + i * 0.1, 1.72 + i * 0.12), WOOD_DARK, Vector3(0.55, 0, 0))
	# Pondoir sur le flanc : petite boîte à couvercle incliné.
	k.add_box(Vector3(0.5, 0.5, 0.6), Vector3(1.1, 1.0, 0.9), WOOD)
	k.add_box(Vector3(0.58, 0.05, 0.68), Vector3(1.1, 1.3, 0.9), zinc, Vector3(0, 0, -0.25))
	k.add_box(Vector3(0.02, 0.24, 0.3), Vector3(1.36, 0.95, 0.9), Color(0.1, 0.08, 0.06))
	# Enclos grillagé : poteaux, deux lisses et grillage à fines tiges.
	var x0 := -1.4
	var x1 := 1.4
	var z0 := 1.6
	var z1 := 3.3
	for px in [x0, 0.0, x1]:
		k.add_box(Vector3(0.08, 1.1, 0.08), Vector3(px, 0.55, z1), WOOD_DARK)
	for pz in [z0, 2.45]:
		k.add_box(Vector3(0.08, 1.1, 0.08), Vector3(x0, 0.55, pz), WOOD_DARK)
		k.add_box(Vector3(0.08, 1.1, 0.08), Vector3(x1, 0.55, pz), WOOD_DARK)
	var mesh_col := Color(0.7, 0.72, 0.7)
	for y in [0.35, 1.05]:
		k.add_box(Vector3(x1 - x0, 0.04, 0.04), Vector3(0, y, z1), WOOD)
		k.add_box(Vector3(0.04, 0.04, z1 - z0), Vector3(x0, y, (z0 + z1) / 2.0), WOOD)
		k.add_box(Vector3(0.04, 0.04, z1 - z0), Vector3(x1, y, (z0 + z1) / 2.0), WOOD)
	for i in 12:
		var gx := x0 + 0.2 + i * 0.2
		k.add_box(Vector3(0.012, 0.95, 0.012), Vector3(gx, 0.58, z1), mesh_col)
	for i in 8:
		var gz := z0 + 0.1 + i * 0.2
		k.add_box(Vector3(0.012, 0.95, 0.012), Vector3(x0, 0.58, gz), mesh_col)
		k.add_box(Vector3(0.012, 0.95, 0.012), Vector3(x1, 0.58, gz), mesh_col)
	# Sol : paille, mangeoire (auge + pieds) et abreuvoir (seau).
	k.add_box(Vector3(2.7, 0.03, 1.6), Vector3(0, 0.02, 2.45), STRAW)
	k.add_box(Vector3(0.7, 0.12, 0.2), Vector3(-0.7, 0.1, 2.9), WOOD)
	k.add_cyl(0.16, 0.12, 0.22, Vector3(0.8, 0.11, 2.9), zinc, Vector3.ZERO, 8)
	# Poules : corps, queue relevée, tête, crête rouge, bec orange, pattes.
	var hens := [[Vector3(-0.5, 0, 2.2), 0.4, Color(0.96, 0.94, 0.88)], [Vector3(0.45, 0, 2.5), -0.8, Color(0.7, 0.4, 0.2)],
		[Vector3(-0.1, 0, 3.0), 2.4, Color(0.55, 0.33, 0.18)], [Vector3(0.9, 0, 2.1), 1.6, Color(0.96, 0.94, 0.88)]]
	for h in hens:
		var base: Vector3 = h[0]
		var yaw: float = h[1]
		var c: Color = h[2]
		var b := Basis(Vector3.UP, yaw)
		k.add_sphere(0.2, base + b * Vector3(0, 0.32, 0), c, Vector3(1.0, 0.85, 1.25), 8)
		k.add_box(Vector3(0.05, 0.2, 0.18), base + b * Vector3(0, 0.46, 0.24), c, Vector3(0.5, yaw, 0))
		k.add_sphere(0.085, base + b * Vector3(0, 0.5, -0.2), c, Vector3.ONE, 6)
		k.add_box(Vector3(0.03, 0.06, 0.1), base + b * Vector3(0, 0.6, -0.2), RED)
		k.add_box(Vector3(0.04, 0.03, 0.07), base + b * Vector3(0, 0.49, -0.29), Color(0.95, 0.65, 0.15))
		for sx in [-0.05, 0.05]:
			k.add_box(Vector3(0.02, 0.16, 0.02), base + b * Vector3(sx, 0.08, 0.0), Color(0.9, 0.65, 0.2))
	return k


## Borne en pierre à tête arrondie et bague.
static func bollard() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(0.14, 0.17, 0.75, Vector3(0, 0.375, 0), STONE, Vector3.ZERO, 8)
	k.add_sphere(0.14, Vector3(0, 0.78, 0), STONE, Vector3(1, 0.7, 1))
	k.add_cyl(0.18, 0.18, 0.06, Vector3(0, 0.55, 0), Color(0.5, 0.48, 0.44), Vector3.ZERO, 8)
	return k


## Barrière de pré : `n` travées de 2 m (poteaux fendus et deux lisses).
static func fence(n := 3) -> PropKit:
	var k := PropKit.new()
	for i in n + 1:
		k.add_box(Vector3(0.12, 1.15, 0.12), Vector3(i * 2.0, 0.575, 0), WOOD_DARK)
		k.add_box(Vector3(0.16, 0.05, 0.16), Vector3(i * 2.0, 1.17, 0), WOOD)
	for i in n:
		for h in [0.45, 0.9]:
			k.add_box(Vector3(1.9, 0.1, 0.05), Vector3(i * 2.0 + 1.0, h, 0), WOOD)
	return k


## Puits de village : margelle de pierre, deux montants, toit à deux pans, manivelle et seau.
static func well() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(0.8, 0.85, 0.9, Vector3(0, 0.45, 0), STONE, Vector3.ZERO, 12)
	k.add_cyl(0.62, 0.62, 0.05, Vector3(0, 0.9, 0), Color(0.08, 0.12, 0.2), Vector3.ZERO, 12)
	for sx in [-0.7, 0.7]:
		k.add_box(Vector3(0.12, 1.8, 0.12), Vector3(sx, 1.8, 0), WOOD_DARK)
	k.add_cyl(0.07, 0.07, 1.5, Vector3(0, 2.2, 0), WOOD, Vector3(0, 0, PI / 2), 6)
	k.add_box(Vector3(1.9, 0.07, 1.2), Vector3(0, 2.95, 0.5), Color(0.62, 0.28, 0.2), Vector3(-0.5, 0, 0))
	k.add_box(Vector3(1.9, 0.07, 1.2), Vector3(0, 2.95, -0.5), Color(0.62, 0.28, 0.2), Vector3(0.5, 0, 0))
	k.add_box(Vector3(0.05, 0.4, 0.05), Vector3(0.75, 2.2, 0.2), IRON, Vector3(0, 0, 0.4))
	k.add_cyl(0.13, 0.1, 0.22, Vector3(0.35, 1.4, 0), WOOD, Vector3.ZERO, 8)
	return k


# --- Ferme et fête -----------------------------------------------------------------------------------------------------------------------

## Botte de paille ronde couchée, deux liens.
static func hay_bale() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(0.7, 0.7, 1.2, Vector3(0, 0.7, 0), STRAW, Vector3(0, 0, PI / 2), 12)
	for x in [-0.28, 0.28]:
		k.add_cyl(0.72, 0.72, 0.05, Vector3(x, 0.7, 0), Color(0.55, 0.4, 0.2), Vector3(0, 0, PI / 2), 12)
	k.add_cyl(0.3, 0.3, 0.02, Vector3(0.6, 0.7, 0), Color(0.72, 0.58, 0.25), Vector3(0, 0, PI / 2), 8)
	return k


## Tonneau de chêne, trois cerclages et un bouchon.
static func barrel() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(0.42, 0.42, 0.9, Vector3(0, 0.45, 0), WOOD, Vector3.ZERO, 10)
	k.add_cyl(0.46, 0.46, 0.7, Vector3(0, 0.45, 0), WOOD, Vector3.ZERO, 10)
	for y in [0.15, 0.45, 0.75]:
		k.add_cyl(0.475 if y == 0.45 else 0.44, 0.475 if y == 0.45 else 0.44, 0.05, Vector3(0, y, 0), IRON, Vector3.ZERO, 10)
	k.add_cyl(0.06, 0.06, 0.08, Vector3(0.4, 0.45, 0.1), WOOD_DARK, Vector3(0, 0, PI / 2), 6)
	return k


## Chaise de fête : assise, dossier à barreaux, quatre pieds.
static func chair() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(0.44, 0.05, 0.44), Vector3(0, 0.46, 0), WOOD)
	for sx in [-0.19, 0.19]:
		for sz in [-0.19, 0.19]:
			k.add_box(Vector3(0.05, 0.46, 0.05), Vector3(sx, 0.23, sz), WOOD_DARK)
		k.add_box(Vector3(0.05, 0.5, 0.05), Vector3(sx, 0.72, -0.19), WOOD_DARK)
	for y in [0.82, 0.95]:
		k.add_box(Vector3(0.44, 0.06, 0.04), Vector3(0, y, -0.19), WOOD)
	return k


## Table à tréteaux, nappe vichy rouge et crème, assiettes, verres, pichet et une miche de pain. `plates` = assiettes garnies.
static func table(plates := 0) -> PropKit:
	var k := PropKit.new()
	for sx in [-0.9, 0.9]:
		k.add_box(Vector3(0.08, 0.76, 0.7), Vector3(sx, 0.38, 0), WOOD_DARK, Vector3(0, 0, sx * 0.12))
		k.add_box(Vector3(0.06, 0.06, 0.62), Vector3(sx * 0.95, 0.12, 0), WOOD_DARK)
	k.add_box(Vector3(2.3, 0.06, 0.82), Vector3(0, 0.77, 0), WOOD)
	for i in 8:
		var c := RED if i % 2 == 0 else CREAM
		k.add_box(Vector3(2.34, 0.02, 0.1), Vector3(0, 0.815, -0.36 + i * 0.1), c)
	for i in 4:
		k.add_box(Vector3(0.14, 0.2, 0.84), Vector3(-1.0 + i * 0.66, 0.74, 0), RED if i % 2 == 0 else CREAM, Vector3.ZERO)
	for sx in [-0.6, 0.6]:
		for sz in [-0.22, 0.22]:
			k.add_cyl(0.13, 0.11, 0.025, Vector3(sx, 0.835, sz), Color(0.97, 0.97, 0.95), Vector3.ZERO, 10)
			k.add_cyl(0.04, 0.035, 0.1, Vector3(sx + 0.17, 0.88, sz), Color(0.8, 0.9, 0.95), Vector3.ZERO, 6)
	for i in mini(plates, 4):
		var sx := -0.6 if i % 2 == 0 else 0.6
		var sz := -0.22 if i < 2 else 0.22
		k.add_sphere(0.085, Vector3(sx, 0.88, sz), Color(0.66, 0.38, 0.18), Vector3(1.2, 0.6, 0.9))
		k.add_sphere(0.03, Vector3(sx + 0.06, 0.9, sz), GREEN, Vector3.ONE, 5)
	k.add_cyl(0.07, 0.09, 0.22, Vector3(0.0, 0.93, 0.0), Color(0.78, 0.52, 0.3), Vector3.ZERO, 8)
	k.add_sphere(0.14, Vector3(-0.2, 0.9, 0.05), Color(0.86, 0.66, 0.38), Vector3(1.4, 0.7, 0.8))
	return k


## Table complète : table + quatre chaises (deux de chaque côté).
static func table_set(plates := 0) -> PropKit:
	var k := table(plates)
	for sx in [-0.55, 0.55]:
		k.append(chair(), Transform3D(Basis.from_euler(Vector3(0, PI, 0)), Vector3(sx, 0, -0.78)))
		k.append(chair(), Transform3D(Basis.IDENTITY, Vector3(sx, 0, 0.78)))
	return k


## Broche à méchoui : deux chevalets, tige, agneau doré (corps, tête, oreilles, pattes ficelées) et manivelle.
static func spit(doneness := 1.0, burn := 0.0) -> PropKit:
	var k := PropKit.new()
	# La viande passe du rose cru au doré, puis au brun noirci si elle brûle.
	var gold := Color(0.93, 0.62, 0.55).lerp(Color(0.78, 0.46, 0.18), clampf(doneness, 0.0, 1.0)).lerp(Color(0.2, 0.12, 0.08), clampf(burn, 0.0, 1.0))
	var dark := gold.darkened(0.35)
	for sx in [-1.25, 1.25]:
		k.add_box(Vector3(0.07, 1.2, 0.07), Vector3(sx, 0.6, 0.4), IRON, Vector3(0.3, 0, 0))
		k.add_box(Vector3(0.07, 1.2, 0.07), Vector3(sx, 0.6, -0.4), IRON, Vector3(-0.3, 0, 0))
		k.add_box(Vector3(0.09, 0.09, 0.3), Vector3(sx, 1.15, 0), IRON)
	k.add_cyl(0.03, 0.03, 2.9, Vector3(0, 1.15, 0), IRON, Vector3(0, 0, PI / 2), 6)
	k.add_sphere(0.34, Vector3(0, 1.15, 0), gold, Vector3(2.0, 0.95, 1.0), 10)
	k.add_sphere(0.2, Vector3(0.78, 1.2, 0), dark, Vector3(1.1, 0.9, 0.9), 8)
	k.add_sphere(0.14, Vector3(1.0, 1.15, 0), gold, Vector3(1.3, 0.9, 0.8), 8)
	for sz in [-0.12, 0.12]:
		k.add_box(Vector3(0.03, 0.14, 0.05), Vector3(0.85, 1.38, sz), dark, Vector3(0, 0, 0.5))
	for sx in [-0.5, 0.5]:
		for sz in [-0.26, 0.26]:
			k.add_cyl(0.05, 0.035, 0.34, Vector3(sx, 1.0, sz), dark, Vector3(0, 0, 0.35 * sign(sz) * 0.0 + 0.2), 6)
	k.add_cyl(0.015, 0.015, 0.7, Vector3(0, 1.15, 0), Color(0.9, 0.85, 0.7), Vector3(PI / 2, 0, 0), 4)
	# Manivelle.
	k.add_box(Vector3(0.05, 0.4, 0.05), Vector3(-1.5, 1.15, 0), IRON, Vector3(0, 0, 0))
	k.add_box(Vector3(0.05, 0.05, 0.3), Vector3(-1.5, 1.35, 0.15), IRON)
	k.add_cyl(0.03, 0.03, 0.16, Vector3(-1.5, 1.35, 0.32), WOOD, Vector3(PI / 2, 0, 0), 6)
	return k


## Brasero : bac de tôle sur quatre pieds, braises incandescentes, grille.
static func brazier() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(2.8, 0.3, 0.9), Vector3(0, 0.45, 0), IRON)
	k.add_box(Vector3(2.9, 0.06, 1.0), Vector3(0, 0.62, 0), Color(0.28, 0.28, 0.3))
	for sx in [-1.3, 1.3]:
		for sz in [-0.38, 0.38]:
			k.add_box(Vector3(0.08, 0.3, 0.08), Vector3(sx, 0.15, sz), IRON)
	for i in 9:
		k.add_box(Vector3(0.28, 0.07, 0.6), Vector3(-1.2 + i * 0.3, 0.56, 0), Color(1.0, 0.42, 0.12), Vector3.ZERO, true)
	return k


## Tas de bois de la Saint-Jean : bûches empilées en cône, fagots et paille. Les flammes sont à part (`flames`).
static func pyre() -> PropKit:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 24
	for layer in 5:
		var r := 1.9 - layer * 0.34
		var n := 8 - layer
		for i in n:
			var a := TAU * i / n + layer * 0.5
			k.add_cyl(0.11, 0.11, 2.6 - layer * 0.35, Vector3(cos(a) * r * 0.55, 0.15 + layer * 0.3, sin(a) * r * 0.55), WOOD if i % 2 == 0 else WOOD_DARK,
				Vector3(PI / 2 + sin(a) * 0.1, a + PI / 2, 0.0), 6)
	k.add_cyl(0.0, 0.9, 1.5, Vector3(0, 1.8, 0), STRAW, Vector3.ZERO, 8)
	for i in 6:
		var a := TAU * i / 6.0
		k.add_cyl(0.18, 0.18, 0.7, Vector3(cos(a) * 2.2, 0.2, sin(a) * 2.2), STRAW, Vector3(0, 0, PI / 2), 6)
	return k


## Flammes (lueur sans éclairage) : trois langues emboîtées, à animer par échelle.
static func flames() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(0.0, 0.8, 2.3, Vector3(0, 2.3, 0), Color(1.0, 0.45, 0.1), Vector3.ZERO, 8, true)
	k.add_cyl(0.0, 0.5, 1.8, Vector3(0.1, 2.25, 0.05), Color(1.0, 0.7, 0.15), Vector3.ZERO, 8, true)
	k.add_cyl(0.0, 0.25, 1.2, Vector3(-0.05, 2.1, 0.0), Color(1.0, 0.92, 0.5), Vector3.ZERO, 8, true)
	return k


## Guirlande de fanions entre deux points (repère local : de (0,0,0) à `span` sur X, flèche de 0,5 m).
static func bunting(span := 6.0) -> PropKit:
	var k := PropKit.new()
	var cols := [RED, Color(0.96, 0.8, 0.25), Color(0.3, 0.6, 0.85), CREAM]
	var n := int(span / 0.5)
	k.add_cyl(0.012, 0.012, span, Vector3(span / 2.0, 0, 0), Color(0.2, 0.15, 0.1), Vector3(0, 0, PI / 2), 4)
	for i in n:
		var x := (i + 0.5) * span / n
		var sag := -0.5 * (1.0 - pow(2.0 * x / span - 1.0, 2.0))
		k.add_box(Vector3(0.26, 0.26, 0.015), Vector3(x, sag - 0.14, 0), cols[i % 4], Vector3(0, 0, PI / 4))
	return k


# --- Animaux --------------------------------------------------------------------------------------------------------------------------

## Chien errant : corps, poitrail, tête, museau, truffe, oreilles tombantes, quatre pattes, queue en panache.
static func dog() -> PropKit:
	var k := PropKit.new()
	var fur := Color(0.72, 0.5, 0.28)
	var dark := Color(0.4, 0.26, 0.14)
	k.add_sphere(0.24, Vector3(0, 0.5, 0), fur, Vector3(1.0, 0.85, 1.9))
	k.add_sphere(0.2, Vector3(0, 0.55, 0.3), CREAM, Vector3(0.9, 0.9, 0.8))
	k.add_sphere(0.17, Vector3(0, 0.72, 0.52), fur, Vector3(1.0, 1.0, 1.0))
	k.add_box(Vector3(0.11, 0.1, 0.2), Vector3(0, 0.66, 0.68), CREAM)
	k.add_sphere(0.035, Vector3(0, 0.7, 0.79), Color(0.08, 0.07, 0.07), Vector3.ONE, 5)
	for sx in [-1.0, 1.0]:
		k.add_box(Vector3(0.05, 0.16, 0.1), Vector3(sx * 0.14, 0.74, 0.46), dark, Vector3(0, 0, sx * 0.4))
		for sz in [-0.3, 0.32]:
			k.add_cyl(0.045, 0.035, 0.36, Vector3(sx * 0.12, 0.2, sz), dark if sz > 0 else fur, Vector3.ZERO, 6)
	k.add_cyl(0.03, 0.07, 0.4, Vector3(0, 0.66, -0.52), fur, Vector3(-0.9, 0, 0), 6)
	return k


## Agneau à la laine bouclée (grappe de sphères), tête sombre et pattes fines.
static func lamb() -> PropKit:
	var k := PropKit.new()
	var wool := Color(0.95, 0.93, 0.86)
	var face := Color(0.25, 0.2, 0.18)
	for i in 9:
		var a := TAU * i / 9.0
		k.add_sphere(0.17, Vector3(cos(a) * 0.17, 0.52 + (i % 2) * 0.08, sin(a) * 0.28), wool, Vector3(1, 0.95, 1), 6)
	k.add_sphere(0.28, Vector3(0, 0.56, 0), wool, Vector3(1.0, 0.9, 1.5), 8)
	k.add_sphere(0.14, Vector3(0, 0.68, 0.42), face, Vector3(0.9, 1.0, 1.1), 8)
	for sx in [-1.0, 1.0]:
		k.add_box(Vector3(0.12, 0.05, 0.08), Vector3(sx * 0.15, 0.74, 0.38), face, Vector3(0, 0, sx * 0.3))
		for sz in [-0.22, 0.22]:
			k.add_cyl(0.03, 0.025, 0.3, Vector3(sx * 0.12, 0.15, sz), face, Vector3.ZERO, 5)
	return k


## Caisse de charbon de bois : planches, charbon noir et un sac.
static func charcoal() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(0.8, 0.5, 0.55), Vector3(0, 0.25, 0), WOOD)
	k.add_box(Vector3(0.7, 0.06, 0.45), Vector3(0, 0.52, 0), Color(0.1, 0.1, 0.11))
	for i in 5:
		k.add_box(Vector3(0.14, 0.1, 0.12), Vector3(-0.28 + i * 0.14, 0.58 + (i % 2) * 0.05, (i % 3 - 1) * 0.1), Color(0.14, 0.14, 0.15), Vector3(0.2 * i, 0.3 * i, 0.1))
	k.add_sphere(0.3, Vector3(0.7, 0.28, 0.1), Color(0.72, 0.6, 0.4), Vector3(1.0, 0.9, 0.7), 8)
	return k


# --- Ferme (mission 05) ------------------------------------------------------------------------------------------------------------

## Vache normande : corps blanc taché de brun, pis, tête à mufle rose, cornes, oreilles, queue à houppe, quatre pattes, étiquettes
## d'oreille. `variant` 1 : Marguerite, plus sombre, avec sa cloche dorée au cou.
static func cow(variant := 0) -> PropKit:
	var k := PropKit.new()
	var white := Color(0.95, 0.93, 0.88)
	var brown := Color(0.52, 0.31, 0.17) if variant == 0 else Color(0.32, 0.2, 0.12)
	var pink := Color(0.93, 0.66, 0.66)
	k.add_sphere(0.55, Vector3(0, 1.05, 0), white if variant == 0 else Color(0.82, 0.78, 0.72), Vector3(0.95, 0.9, 1.75), 10)
	k.add_sphere(0.3, Vector3(0.28, 1.2, 0.35), brown, Vector3(0.7, 0.9, 1.1), 7)
	k.add_sphere(0.32, Vector3(-0.3, 1.1, -0.35), brown, Vector3(0.7, 0.8, 1.2), 7)
	k.add_sphere(0.22, Vector3(0.1, 1.45, -0.2), brown, Vector3(1.0, 0.5, 1.0), 6)
	k.add_sphere(0.2, Vector3(0, 0.62, -0.62), pink, Vector3(1.0, 0.8, 1.0), 7)
	for sx in [-0.09, 0.09]:
		k.add_cyl(0.025, 0.02, 0.12, Vector3(sx, 0.48, -0.62), pink, Vector3.ZERO, 5)
	k.add_box(Vector3(0.36, 0.38, 0.5), Vector3(0, 1.28, 0.95), white if variant == 0 else Color(0.82, 0.78, 0.72))
	k.add_box(Vector3(0.28, 0.2, 0.2), Vector3(0, 1.12, 1.25), pink)
	k.add_box(Vector3(0.18, 0.1, 0.06), Vector3(0, 1.1, 1.36), Color(0.75, 0.45, 0.45))
	for sx in [-1.0, 1.0]:
		k.add_box(Vector3(0.22, 0.07, 0.14), Vector3(sx * 0.27, 1.38, 0.85), brown, Vector3(0, 0, sx * 0.3))
		k.add_cyl(0.025, 0.04, 0.16, Vector3(sx * 0.2, 1.55, 0.92), CREAM, Vector3(0, 0, sx * 0.6), 5)
		for sz in [-0.55, 0.62]:
			k.add_cyl(0.07, 0.055, 0.7, Vector3(sx * 0.27, 0.35, sz), white, Vector3.ZERO, 6)
			k.add_cyl(0.065, 0.065, 0.1, Vector3(sx * 0.27, 0.05, sz), Color(0.2, 0.17, 0.15), Vector3.ZERO, 6)
	k.add_cyl(0.025, 0.04, 0.8, Vector3(0, 0.95, -0.95), white, Vector3(0.25, 0, 0), 5)
	k.add_sphere(0.07, Vector3(0, 0.52, -1.0), brown, Vector3(1, 1.4, 1), 5)
	k.add_box(Vector3(0.05, 0.06, 0.02), Vector3(0.26, 1.34, 0.9), Color(0.95, 0.8, 0.2))
	if variant == 1:
		k.add_cyl(0.1, 0.12, 0.14, Vector3(0, 0.98, 0.75), Color(0.95, 0.75, 0.2), Vector3.ZERO, 8)
		k.add_box(Vector3(0.5, 0.05, 0.05), Vector3(0, 1.12, 0.72), Color(0.4, 0.25, 0.15))
	return k


## Enclos de ferme : clôture sur trois côtés (côté +Z ouvert, porte de 4,4 m), auge et botte de foin au fond.
static func pen(half := 6.0) -> PropKit:
	var k := PropKit.new()
	var n := int(half * 2.0 / 2.0)
	for i in n + 1:
		var t := -half + i * 2.0
		k.add_box(Vector3(0.14, 1.2, 0.14), Vector3(t, 0.6, -half), WOOD_DARK)
		k.add_box(Vector3(0.14, 1.2, 0.14), Vector3(-half, 0.6, t), WOOD_DARK)
		k.add_box(Vector3(0.14, 1.2, 0.14), Vector3(half, 0.6, t), WOOD_DARK)
	for h in [0.45, 0.95]:
		k.add_box(Vector3(half * 2.0, 0.1, 0.06), Vector3(0, h, -half), WOOD)
		k.add_box(Vector3(0.06, 0.1, half * 2.0), Vector3(-half, h, 0), WOOD)
		k.add_box(Vector3(0.06, 0.1, half * 2.0), Vector3(half, h, 0), WOOD)
		for sx in [-1.0, 1.0]:
			k.add_box(Vector3(half - 2.2, 0.1, 0.06), Vector3(sx * (2.2 + (half - 2.2) / 2.0), h, half), WOOD)
	for sx in [-2.2, 2.2]:
		k.add_box(Vector3(0.2, 1.6, 0.2), Vector3(sx, 0.8, half), WOOD_DARK)
		k.add_box(Vector3(0.26, 0.06, 0.26), Vector3(sx, 1.62, half), WOOD)
	k.add_box(Vector3(2.2, 0.4, 0.55), Vector3(0, 0.2, -half + 1.0), WOOD)
	k.add_box(Vector3(2.0, 0.06, 0.4), Vector3(0, 0.38, -half + 1.0), Color(0.3, 0.5, 0.75))
	k.append(hay_bale(), Transform3D(Basis(Vector3.UP, 0.5), Vector3(-half + 1.4, 0, -half + 1.6)))
	return k


## Vantail de porte d'enclos (2,2 m, charnière à l'origine, s'étend vers +X).
static func gate_leaf() -> PropKit:
	var k := PropKit.new()
	for h in [0.3, 0.7, 1.1]:
		k.add_box(Vector3(2.1, 0.1, 0.06), Vector3(1.1, h, 0), WOOD)
	k.add_box(Vector3(0.1, 1.2, 0.08), Vector3(0.05, 0.6, 0), WOOD_DARK)
	k.add_box(Vector3(0.1, 1.2, 0.08), Vector3(2.15, 0.6, 0), WOOD_DARK)
	k.add_box(Vector3(2.2, 0.08, 0.05), Vector3(1.1, 0.7, 0.0), WOOD_DARK, Vector3(0, 0, 0.5))
	return k


# --- Supermarché (mission 06) -------------------------------------------------------------------------------------------------------------

const PRODUCT_COLORS := [Color(0.9, 0.3, 0.25), Color(0.95, 0.8, 0.25), Color(0.3, 0.6, 0.85), Color(0.35, 0.7, 0.4), Color(0.95, 0.95, 0.9), Color(0.8, 0.5, 0.2), Color(0.7, 0.4, 0.75)]


## Gondole double face : montants, quatre niveaux, produits de couleurs variées (déterministe selon `seed`), tête de gondole.
## `length` le long de X, profondeur 1 m (Z), hauteur 1,8 m.
static func shelf(length := 6.0, seed := 1) -> PropKit:
	var k := PropKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	k.add_box(Vector3(length, 0.12, 1.0), Vector3(0, 0.06, 0), Color(0.78, 0.78, 0.8))
	var posts := int(length / 2.0) + 1
	for i in posts:
		var x := -length / 2.0 + i * (length / float(posts - 1))
		k.add_box(Vector3(0.06, 1.8, 0.06), Vector3(x, 0.9, -0.45), Color(0.45, 0.47, 0.52))
		k.add_box(Vector3(0.06, 1.8, 0.06), Vector3(x, 0.9, 0.45), Color(0.45, 0.47, 0.52))
	k.add_box(Vector3(0.05, 1.7, 0.9), Vector3(0, 0.9, 0), Color(0.85, 0.85, 0.88))
	for lv in 4:
		var y := 0.3 + lv * 0.42
		k.add_box(Vector3(length, 0.04, 0.95), Vector3(0, y, 0), Color(0.82, 0.82, 0.85))
		var x := -length / 2.0 + 0.3
		while x < length / 2.0 - 0.3:
			var w := rng.randf_range(0.18, 0.4)
			var h := rng.randf_range(0.18, 0.34)
			var col: Color = PRODUCT_COLORS[rng.randi() % PRODUCT_COLORS.size()]
			for side in [-1.0, 1.0]:
				k.add_box(Vector3(w, h, 0.28), Vector3(x + w / 2.0, y + 0.02 + h / 2.0, side * 0.27), col)
				k.add_box(Vector3(w * 0.8, h * 0.25, 0.01), Vector3(x + w / 2.0, y + 0.02 + h * 0.55, side * 0.415), CREAM)
			x += w + 0.04
	k.add_box(Vector3(length + 0.1, 0.18, 1.05), Vector3(0, 1.88, 0), Color(0.25, 0.5, 0.35))
	return k


## Meuble réfrigéré de fond de magasin : caisson blanc, portes vitrées, laitages et fromages, bandeau bleu.
static func fridge(length := 8.0) -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(length, 2.1, 0.9), Vector3(0, 1.05, 0), Color(0.93, 0.94, 0.95))
	var n := int(length / 1.0)
	for i in n:
		var x := -length / 2.0 + 0.5 + i
		k.add_box(Vector3(0.9, 1.7, 0.03), Vector3(x, 1.0, 0.46), Color(0.7, 0.85, 0.95))
		for lv in 3:
			for j in 3:
				k.add_box(Vector3(0.22, 0.2, 0.2), Vector3(x - 0.27 + j * 0.27, 0.35 + lv * 0.5, 0.3), PRODUCT_COLORS[(i + lv * 2 + j) % PRODUCT_COLORS.size()])
	k.add_box(Vector3(length, 0.3, 0.95), Vector3(0, 2.25, 0), Color(0.25, 0.45, 0.8))
	return k


## Comptoir de boulangerie : vitrine, corbeille de baguettes, pains ronds, balance.
static func bakery(length := 4.0) -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(length, 1.0, 0.9), Vector3(0, 0.5, 0), WOOD)
	k.add_box(Vector3(length, 0.06, 1.0), Vector3(0, 1.03, 0), Color(0.9, 0.88, 0.82))
	k.add_box(Vector3(length - 0.2, 0.55, 0.04), Vector3(0, 1.35, 0.4), Color(0.75, 0.88, 0.95))
	for i in 7:
		k.add_cyl(0.045, 0.045, 0.8, Vector3(-length / 2.0 + 0.4 + i * 0.12, 1.2, -0.12), Color(0.82, 0.55, 0.22), Vector3(0.3, 0, 0.9 + i * 0.05), 6)
	for i in 4:
		k.add_sphere(0.14, Vector3(0.3 + i * 0.32, 1.17, 0.05), Color(0.78, 0.5, 0.2), Vector3(1, 0.7, 1), 7)
	k.add_box(Vector3(0.5, 0.05, 0.4), Vector3(-length / 2.0 + 0.4, 1.09, 0.2), Color(0.5, 0.52, 0.56))
	k.add_box(Vector3(length, 0.28, 0.95), Vector3(0, 1.95, -0.05), Color(0.82, 0.55, 0.25))
	return k


## Caisse : meuble, tapis roulant sombre, caisse enregistreuse à écran, scanner, séparateur, sac.
static func checkout() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(2.6, 0.9, 0.7), Vector3(0, 0.45, 0), Color(0.88, 0.88, 0.9))
	k.add_box(Vector3(1.6, 0.05, 0.55), Vector3(-0.4, 0.92, 0), Color(0.15, 0.15, 0.17))
	k.add_box(Vector3(0.5, 0.42, 0.4), Vector3(0.85, 1.1, 0.05), Color(0.35, 0.37, 0.42))
	k.add_box(Vector3(0.36, 0.26, 0.03), Vector3(0.85, 1.42, 0.0), Color(0.3, 0.8, 0.5), Vector3(-0.25, 0, 0), true)
	k.add_box(Vector3(0.3, 0.04, 0.22), Vector3(0.1, 0.96, 0.18), Color(0.7, 0.9, 1.0), Vector3.ZERO, true)
	k.add_box(Vector3(0.03, 0.16, 0.5), Vector3(0.35, 1.02, 0), Color(0.9, 0.5, 0.2))
	k.add_box(Vector3(2.8, 0.1, 0.8), Vector3(0, 0.9, 0), Color(0.6, 0.62, 0.66))
	k.add_cyl(0.02, 0.02, 1.6, Vector3(1.25, 1.7, 0.3), Color(0.35, 0.37, 0.42), Vector3.ZERO, 5)
	k.add_box(Vector3(0.8, 0.22, 0.06), Vector3(1.25, 2.55, 0.3), Color(0.25, 0.5, 0.35))
	return k


## Chariot de courses : panier en fil, poignée, quatre roulettes, siège enfant.
static func caddie() -> PropKit:
	var k := PropKit.new()
	var metal := Color(0.62, 0.64, 0.68)
	k.add_box(Vector3(0.55, 0.04, 0.95), Vector3(0, 0.38, 0.05), metal)
	for sx in [-1.0, 1.0]:
		k.add_box(Vector3(0.03, 0.45, 0.95), Vector3(sx * 0.27, 0.62, 0.05), metal)
		k.add_box(Vector3(0.03, 0.45, 0.03), Vector3(sx * 0.27, 0.62, 0.52), metal, Vector3(0, 0, 0))
	k.add_box(Vector3(0.55, 0.45, 0.03), Vector3(0, 0.62, 0.52), metal)
	k.add_box(Vector3(0.55, 0.03, 0.03), Vector3(0, 0.95, -0.42), Color(0.9, 0.3, 0.25))
	k.add_box(Vector3(0.03, 0.55, 0.03), Vector3(-0.27, 0.68, -0.42), metal)
	k.add_box(Vector3(0.03, 0.55, 0.03), Vector3(0.27, 0.68, -0.42), metal)
	for sx in [-1.0, 1.0]:
		for sz in [-0.4, 0.45]:
			k.add_cyl(0.05, 0.05, 0.04, Vector3(sx * 0.22, 0.05, sz), IRON, Vector3(0, 0, PI / 2), 6)
	return k


## Panneau d'entrée à deux montants (le texte est un Label3D posé par le constructeur).
static func super_sign() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(9.0, 1.4, 0.3), Vector3(0, 0, 0), Color(0.88, 0.2, 0.2))
	k.add_box(Vector3(9.2, 0.12, 0.35), Vector3(0, 0.74, 0), CREAM)
	k.add_box(Vector3(9.2, 0.12, 0.35), Vector3(0, -0.74, 0), CREAM)
	return k


# --- Fête de la pomme (mission 07) ---------------------------------------------------------------------------------------------------------

const APPLE_RED := Color(0.85, 0.2, 0.18)
const APPLE_GREEN := Color(0.62, 0.78, 0.25)


## Cageot de pommes : caisse à claire-voie et deux couches de pommes rouges et vertes avec leur queue.
static func apple_crate() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(0.6, 0.04, 0.4), Vector3(0, 0.02, 0), WOOD)
	for sx in [-0.3, 0.3]:
		k.add_box(Vector3(0.04, 0.3, 0.4), Vector3(sx, 0.17, 0), WOOD_DARK)
	for sz in [-0.2, 0.2]:
		k.add_box(Vector3(0.6, 0.3, 0.04), Vector3(0, 0.17, sz), WOOD_DARK)
	for i in 6:
		var x := -0.2 + (i % 3) * 0.2
		var z := -0.09 + (i / 3) * 0.18
		var col := APPLE_RED if i % 2 == 0 else APPLE_GREEN
		k.add_sphere(0.09, Vector3(x, 0.32, z), col, Vector3(1, 0.9, 1), 7)
		k.add_cyl(0.008, 0.008, 0.05, Vector3(x, 0.42, z), WOOD_DARK, Vector3.ZERO, 4)
	return k


## Stand de la fête de la pomme : pressoir à vis, tonneaux, cageots, comptoir à gobelets, cruche de jus « maison », toile rayée.
static func cider_press() -> PropKit:
	var k := PropKit.new()
	# Pressoir : cuve de bois cerclée, vis centrale, volant.
	k.add_cyl(0.7, 0.75, 0.9, Vector3(-2.4, 0.45, 0), WOOD, Vector3.ZERO, 12)
	for y in [0.15, 0.45, 0.75]:
		k.add_cyl(0.78, 0.78, 0.05, Vector3(-2.4, y, 0), IRON, Vector3.ZERO, 12)
	k.add_cyl(0.06, 0.06, 1.4, Vector3(-2.4, 1.6, 0), IRON, Vector3.ZERO, 6)
	k.add_box(Vector3(1.4, 0.07, 0.07), Vector3(-2.4, 2.25, 0), WOOD_DARK)
	k.add_sphere(0.09, Vector3(-1.7, 2.25, 0), IRON, Vector3.ONE, 6)
	k.add_sphere(0.09, Vector3(-3.1, 2.25, 0), IRON, Vector3.ONE, 6)
	k.add_box(Vector3(0.9, 0.05, 0.5), Vector3(-2.4, 1.0, 0), WOOD_DARK)
	# Comptoir et gobelets.
	k.add_box(Vector3(3.2, 1.0, 0.9), Vector3(0.6, 0.5, 0.0), WOOD)
	k.add_box(Vector3(3.4, 0.07, 1.05), Vector3(0.6, 1.03, 0.0), Color(0.92, 0.9, 0.82))
	for i in 5:
		k.add_cyl(0.045, 0.035, 0.11, Vector3(-0.6 + i * 0.2, 1.12, 0.3), Color(0.95, 0.95, 0.92), Vector3.ZERO, 8)
	# Cruche de jus de pomme (un peu trop vif : bouchon qui a sauté).
	k.add_cyl(0.13, 0.16, 0.38, Vector3(1.6, 1.25, 0.1), Color(0.8, 0.58, 0.25), Vector3.ZERO, 10)
	k.add_cyl(0.06, 0.1, 0.12, Vector3(1.6, 1.5, 0.1), Color(0.8, 0.58, 0.25), Vector3.ZERO, 8)
	k.add_sphere(0.05, Vector3(1.74, 1.62, 0.1), Color(0.9, 0.85, 0.6), Vector3.ONE, 5)
	# Toile rayée et mâts.
	for sx in [-0.9, 2.1]:
		k.add_box(Vector3(0.1, 2.6, 0.1), Vector3(sx, 1.3, -0.5), WOOD_DARK)
	for i in 8:
		k.add_box(Vector3(0.45, 0.06, 1.7), Vector3(-0.7 + i * 0.45 - 0.0, 2.68 - 0.0, -0.1), RED if i % 2 == 0 else CREAM, Vector3(0.25, 0, 0))
	# Tonneaux et cageots autour.
	for spec in [[Vector3(3.0, 0, 0.6), 0.0], [Vector3(3.2, 0, -0.2), 0.7]]:
		k.append(barrel(), Transform3D(Basis(Vector3.UP, spec[1]), spec[0]))
	for i in 3:
		k.append(apple_crate(), Transform3D(Basis(Vector3.UP, 0.15 * i), Vector3(-0.8 + (i % 2) * 0.7, 0.0 + (i / 2) * 0.32, 1.4)))
	k.append(apple_crate(), Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.6, 0, 1.5)))
	return k


## Cabine de toilettes publiques : caisson vert, toit plat, porte à verrou, voyant « OCCUPÉ » rouge, pictogramme.
static func wc_cabin() -> PropKit:
	var k := PropKit.new()
	var green := Color(0.28, 0.5, 0.36)
	k.add_box(Vector3(1.4, 2.4, 1.4), Vector3(0, 1.2, 0), green)
	k.add_box(Vector3(1.6, 0.12, 1.6), Vector3(0, 2.46, 0), green.darkened(0.2))
	k.add_box(Vector3(0.85, 2.0, 0.06), Vector3(0, 1.05, 0.72), green.lightened(0.25))
	k.add_box(Vector3(0.08, 0.14, 0.04), Vector3(0.3, 1.05, 0.77), Color(0.9, 0.9, 0.85))
	k.add_box(Vector3(0.3, 0.14, 0.04), Vector3(0, 1.95, 0.77), Color(0.9, 0.2, 0.2), Vector3.ZERO, true)
	k.add_box(Vector3(0.5, 0.5, 0.03), Vector3(0, 1.55, 0.75), Color(0.95, 0.95, 0.9))
	k.add_cyl(0.07, 0.07, 0.14, Vector3(0, 1.72, 0.78), Color(0.2, 0.3, 0.6), Vector3(PI / 2, 0, 0), 8)
	k.add_box(Vector3(0.18, 0.28, 0.03), Vector3(0, 1.45, 0.78), Color(0.2, 0.3, 0.6))
	return k


## Pot de fleurs (la clé de secours est dessous) : terre cuite, terre, géraniums rouges.
static func flowerpot() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(0.22, 0.15, 0.3, Vector3(0, 0.15, 0), Color(0.78, 0.4, 0.25), Vector3.ZERO, 10)
	k.add_cyl(0.24, 0.24, 0.05, Vector3(0, 0.31, 0), Color(0.72, 0.36, 0.22), Vector3.ZERO, 10)
	k.add_cyl(0.19, 0.19, 0.03, Vector3(0, 0.33, 0), Color(0.25, 0.17, 0.11), Vector3.ZERO, 10)
	for i in 5:
		var a := TAU * i / 5.0
		k.add_cyl(0.012, 0.012, 0.22, Vector3(cos(a) * 0.07, 0.45, sin(a) * 0.07), GREEN, Vector3.ZERO, 4)
		k.add_sphere(0.07, Vector3(cos(a) * 0.09, 0.6 + (i % 2) * 0.03, sin(a) * 0.09), Color(0.9, 0.2, 0.25), Vector3(1, 0.8, 1), 6)
	return k

# --- Mission 08 : l'oie, la voie ferrée et le train ---------------------------------------------------------------------------------------

## Oie (+Z = devant) : corps ovale, cou, tête, bec orange, queue, ailes repliées et pattes. `variant` 0 : blanche, 1 : grise, 2 : meneuse (collier rouge).
static func goose(variant := 0) -> PropKit:
	var k := PropKit.new()
	var body := Color(0.97, 0.96, 0.92) if variant != 1 else Color(0.66, 0.64, 0.6)
	var wing := Color(0.9, 0.89, 0.84) if variant != 1 else Color(0.5, 0.48, 0.45)
	var orange := Color(0.96, 0.58, 0.12)
	k.add_sphere(0.24, Vector3(0, 0.5, 0), body, Vector3(0.85, 0.82, 1.45), 9)
	k.add_sphere(0.17, Vector3(0, 0.55, -0.3), body, Vector3(0.9, 0.9, 1.1), 8)                       # croupion
	k.add_box(Vector3(0.12, 0.05, 0.22), Vector3(0, 0.66, -0.52), body, Vector3(-0.35, 0, 0))          # queue
	k.add_cyl(0.07, 0.1, 0.55, Vector3(0, 0.85, 0.28), body, Vector3(0.3, 0, 0), 7)                    # cou
	k.add_sphere(0.1, Vector3(0, 1.13, 0.4), body, Vector3(0.9, 0.95, 1.1), 8)                          # tête
	k.add_box(Vector3(0.09, 0.05, 0.16), Vector3(0, 1.1, 0.53), orange)                                # bec
	k.add_box(Vector3(0.07, 0.03, 0.08), Vector3(0, 1.14, 0.5), orange)
	for sx in [-1.0, 1.0]:
		k.add_sphere(0.022, Vector3(sx * 0.07, 1.16, 0.45), Color(0.05, 0.04, 0.04), Vector3.ONE, 4)   # yeux
		k.add_sphere(0.2, Vector3(sx * 0.19, 0.52, -0.02), wing, Vector3(0.28, 0.6, 1.35), 7)          # ailes repliées
		k.add_cyl(0.022, 0.03, 0.3, Vector3(sx * 0.09, 0.2, 0.0), orange, Vector3.ZERO, 5)             # pattes
		k.add_box(Vector3(0.1, 0.02, 0.15), Vector3(sx * 0.09, 0.02, 0.05), orange)                    # pieds palmés
	if variant == 2:
		k.add_cyl(0.085, 0.09, 0.07, Vector3(0, 0.78, 0.33), Color(0.85, 0.2, 0.2), Vector3(0.3, 0, 0), 8)   # collier rouge
	return k


## Un mètre de voie : traverse en bois, deux rails d'acier et un peu de ballast (placé tous les mètres par `RailLine`).
static func rail_tie() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(3.0, 0.16, 0.34), Vector3(0, 0.08, 0), Color(0.42, 0.3, 0.2))
	for sx in [-0.72, 0.72]:
		k.add_box(Vector3(0.1, 0.16, 1.08), Vector3(sx, 0.24, 0), Color(0.55, 0.57, 0.6))
		k.add_box(Vector3(0.2, 0.04, 1.08), Vector3(sx, 0.17, 0), Color(0.35, 0.36, 0.38))
	k.add_box(Vector3(3.6, 0.1, 1.08), Vector3(0, 0.03, 0), Color(0.6, 0.57, 0.52))                    # ballast
	return k


## Train des vacances (+Z = devant) : locomotive et trois voitures bleu et crème, vitres, pare-chocs et phare.
static func train() -> PropKit:
	var k := PropKit.new()
	var blue := Color(0.2, 0.42, 0.7)
	var cream := Color(0.95, 0.92, 0.82)
	var dark := Color(0.2, 0.22, 0.26)
	var glass := Color(0.55, 0.78, 0.9)
	# Locomotive (avant, z > 0) : 0 → +9 m ; voitures derrière.
	k.add_box(Vector3(2.9, 1.2, 9.0), Vector3(0, 1.0, 4.5), blue)
	k.add_box(Vector3(2.9, 1.5, 3.2), Vector3(0, 2.35, 2.2), blue)                                     # cabine
	k.add_box(Vector3(2.6, 0.5, 0.06), Vector3(0, 2.75, 3.82), glass)                                  # pare-brise
	k.add_box(Vector3(3.0, 0.14, 9.2), Vector3(0, 1.62, 4.5), cream)                                   # bandeau
	k.add_box(Vector3(2.2, 0.3, 0.3), Vector3(0, 0.55, 9.1), dark)                                      # pare-chocs
	k.add_box(Vector3(0.5, 0.3, 0.1), Vector3(-0.8, 1.7, 9.02), Color(1.0, 0.95, 0.6), Vector3.ZERO, true)  # phares
	k.add_box(Vector3(0.5, 0.3, 0.1), Vector3(0.8, 1.7, 9.02), Color(1.0, 0.95, 0.6), Vector3.ZERO, true)
	k.add_cyl(0.16, 0.2, 0.5, Vector3(0, 1.85, 6.5), dark, Vector3.ZERO, 8)                            # cheminée d'échappement
	for i in 3:
		var z0 := -1.0 - i * 15.0
		k.add_box(Vector3(2.9, 2.5, 14.2), Vector3(0, 1.9, z0 - 6.0), cream)
		k.add_box(Vector3(2.95, 0.7, 14.2), Vector3(0, 0.7, z0 - 6.0), blue)
		k.add_box(Vector3(3.0, 0.1, 14.2), Vector3(0, 1.4, z0 - 6.0), blue)
		for j in 6:
			for sx in [-1.0, 1.0]:
				k.add_box(Vector3(0.06, 0.8, 1.6), Vector3(sx * 1.46, 2.2, z0 - 11.8 + j * 2.3), glass)
		k.add_box(Vector3(2.9, 0.12, 14.4), Vector3(0, 3.2, z0 - 6.0), Color(0.7, 0.72, 0.75))         # toit
	for bz in [8.0, 5.5, 1.0, -4.0, -9.0, -14.0, -19.0, -24.0, -29.0, -34.0, -39.0, -44.0]:
		for sx in [-1.0, 1.0]:
			k.add_cyl(0.46, 0.46, 0.22, Vector3(sx * 1.3, 0.46, bz), dark, Vector3(0, 0, PI / 2.0), 10)
	return k


## Maisonnette du garde-barrière (+Z = vers la voie) : murs crème, toit rouge, porte et petite fenêtre.
static func gate_hut() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(3.2, 2.4, 3.0), Vector3(0, 1.2, 0), Color(0.94, 0.88, 0.74))
	k.add_box(Vector3(3.6, 0.12, 3.4), Vector3(0, 2.46, 0), Color(0.75, 0.25, 0.2), Vector3(0.0, 0.0, 0.0))
	k.add_box(Vector3(3.5, 0.1, 1.9), Vector3(0, 2.78, -0.8), Color(0.75, 0.25, 0.2), Vector3(0.45, 0, 0))
	k.add_box(Vector3(3.5, 0.1, 1.9), Vector3(0, 2.78, 0.8), Color(0.75, 0.25, 0.2), Vector3(-0.45, 0, 0))
	k.add_box(Vector3(0.9, 1.8, 0.06), Vector3(-0.6, 0.9, 1.52), Color(0.4, 0.26, 0.17))
	k.add_box(Vector3(0.8, 0.7, 0.06), Vector3(0.8, 1.4, 1.52), Color(0.55, 0.78, 0.9))
	k.add_box(Vector3(0.26, 0.6, 0.26), Vector3(1.0, 3.2, -0.6), Color(0.6, 0.35, 0.3))                # cheminée
	return k


## Croix de Saint-André et feu de passage à niveau (barrières relevées) : deux mâts, une croix rouge et blanche.
static func crossing_signs() -> PropKit:
	var k := PropKit.new()
	for sx in [-4.2, 4.2]:
		k.add_cyl(0.06, 0.07, 3.2, Vector3(sx, 1.6, 0), Color(0.9, 0.9, 0.9), Vector3.ZERO, 6)
		k.add_box(Vector3(1.3, 0.14, 0.06), Vector3(sx, 3.05, 0.04), Color(0.85, 0.18, 0.15), Vector3(0, 0, 0.7))
		k.add_box(Vector3(1.3, 0.14, 0.06), Vector3(sx, 3.05, 0.04), Color(0.85, 0.18, 0.15), Vector3(0, 0, -0.7))
		k.add_sphere(0.11, Vector3(sx, 2.55, 0.1), Color(1.0, 0.3, 0.25), Vector3.ONE, 6, true)
		k.add_sphere(0.11, Vector3(sx, 2.3, 0.1), Color(1.0, 0.3, 0.25), Vector3.ONE, 6, true)
	return k


## Mare des oies : disque d'eau, roseaux et cabane à oies.
static func goose_pond() -> PropKit:
	var k := PropKit.new()
	k.add_cyl(7.5, 7.5, 0.1, Vector3(0, 0.03, 0), Color(0.36, 0.6, 0.78), Vector3.ZERO, 18)
	k.add_cyl(8.2, 8.2, 0.06, Vector3(0, 0.0, 0), Color(0.5, 0.42, 0.28), Vector3.ZERO, 18)
	for i in 14:
		var a := float(i) * 0.9
		var r := 7.0 + 0.8 * sin(float(i) * 2.3)
		k.add_cyl(0.025, 0.03, 1.1 + 0.4 * sin(float(i)), Vector3(cos(a) * r, 0.6, sin(a) * r), Color(0.45, 0.6, 0.3), Vector3.ZERO, 4)
		k.add_sphere(0.05, Vector3(cos(a) * r, 1.2 + 0.4 * sin(float(i)), sin(a) * r), Color(0.5, 0.35, 0.2), Vector3(1, 2.2, 1), 5)
	k.add_box(Vector3(1.6, 1.0, 1.2), Vector3(9.5, 0.5, 2.0), Color(0.55, 0.38, 0.24))                   # cabane
	k.add_box(Vector3(1.9, 0.1, 1.5), Vector3(9.5, 1.15, 2.0), Color(0.36, 0.25, 0.17), Vector3(0, 0, 0.12))
	return k

# --- Gare du Pays de Frouch (mission 08) ---------------------------------------------------------------------------------------------------
## Repère : +Z le long de la voie, +X vers le bâtiment (le quai est entre la voie, x ≈ 0, et le bâtiment). Le monde tourne le tout de 180° si
## la gare est de l'autre côté. Quai : x de 2,2 à 6,4 m, 80 m de long, 0,8 m de haut ; bâtiment : x de 10 à 19 m, 24 m de long.

const QUAI_LEN := 80.0
const QUAI_H := 0.8


## Quai : dalle, ligne de sécurité jaune, bordure et deux rampes d'extrémité.
static func station_platform() -> PropKit:
	var k := PropKit.new()
	var concrete := Color(0.72, 0.71, 0.68)
	k.add_box(Vector3(4.2, QUAI_H, QUAI_LEN), Vector3(4.3, QUAI_H / 2.0, 0), concrete)
	k.add_box(Vector3(0.3, 0.03, QUAI_LEN), Vector3(2.45, QUAI_H + 0.02, 0), Color(0.97, 0.8, 0.15))        # ligne de sécurité
	k.add_box(Vector3(0.22, 0.12, QUAI_LEN), Vector3(2.2, QUAI_H - 0.04, 0), Color(0.55, 0.55, 0.52))        # bordure
	for sz in [-1.0, 1.0]:
		k.add_box(Vector3(4.2, 0.12, 4.2), Vector3(4.3, QUAI_H / 2.0, sz * (QUAI_LEN / 2.0 + 2.0)), concrete, Vector3(-sz * 0.2, 0, 0))   # rampes
	return k


## Auvent du quai : huit poteaux et un toit à pente douce en zinc, avec lambrequin crème.
static func station_canopy() -> PropKit:
	var k := PropKit.new()
	var zinc := Color(0.5, 0.56, 0.58)
	var cream := Color(0.95, 0.9, 0.78)
	for i in 8:
		var z := -22.0 + float(i) * 6.3
		k.add_box(Vector3(0.18, 3.0, 0.18), Vector3(5.7, QUAI_H + 1.5, z), Color(0.2, 0.34, 0.3))
	k.add_box(Vector3(5.6, 0.14, 46.0), Vector3(5.2, QUAI_H + 3.15, 0), zinc, Vector3(0, 0, -0.06))
	k.add_box(Vector3(0.1, 0.45, 46.0), Vector3(2.5, QUAI_H + 2.95, 0), cream)
	return k


## Bâtiment des voyageurs : socle de brique, murs crème à colombages, toit d'ardoise à quatre pans, cheminées, fenêtres et portes,
## horloge côté quai.
static func station_building() -> PropKit:
	var k := PropKit.new()
	var brick := Color(0.7, 0.34, 0.26)
	var cream := Color(0.95, 0.91, 0.78)
	var timber := Color(0.36, 0.25, 0.17)
	var slate := Color(0.3, 0.33, 0.4)
	var glass := Color(0.45, 0.62, 0.78)
	var x0 := 14.5
	k.add_box(Vector3(9.0, 1.1, 24.0), Vector3(x0, 0.55, 0), brick)
	k.add_box(Vector3(9.0, 3.2, 24.0), Vector3(x0, 2.7, 0), cream)
	for i in 9:
		var z := -11.0 + float(i) * 2.75
		k.add_box(Vector3(9.05, 3.2, 0.14), Vector3(x0, 2.7, z), timber)                                      # colombages
	k.add_box(Vector3(9.05, 0.16, 24.05), Vector3(x0, 4.35, 0), timber)
	# Toit : quatre pans (deux grands, deux croupes) et faîtage.
	k.add_box(Vector3(5.6, 0.2, 25.5), Vector3(x0 - 2.3, 5.2, 0), slate, Vector3(0, 0, 0.48))
	k.add_box(Vector3(5.6, 0.2, 25.5), Vector3(x0 + 2.3, 5.2, 0), slate, Vector3(0, 0, -0.48))
	k.add_box(Vector3(0.3, 0.2, 22.0), Vector3(x0, 6.3, 0), Color(0.22, 0.24, 0.3))
	for cz in [-8.0, 7.0]:
		k.add_box(Vector3(0.9, 2.0, 0.9), Vector3(x0 + 1.5, 6.4, cz), brick)
	# Fenêtres et portes sur les deux faces.
	for face in [-1.0, 1.0]:
		var fx: float = x0 + face * 4.52
		for z in [-9.0, -6.0, 6.0, 9.0]:
			k.add_box(Vector3(0.1, 1.5, 1.2), Vector3(fx, 2.6, z), glass)
			k.add_box(Vector3(0.13, 1.7, 1.4), Vector3(fx - face * 0.02, 2.6, z), Color(0.96, 0.96, 0.94))
		for z in [-2.4, 0.0, 2.4]:
			k.add_box(Vector3(0.12, 2.2, 1.3), Vector3(fx, 1.65 if face < 0 else 1.5, z), Color(0.42, 0.28, 0.18))
			k.add_box(Vector3(0.14, 1.0, 0.8), Vector3(fx - face * 0.02, 2.0, z), glass)
	# Horloge au-dessus de la porte centrale, côté quai (face x = x0 - 4,5).
	k.add_cyl(0.62, 0.62, 0.1, Vector3(x0 - 4.6, 4.0, 0), Color(0.97, 0.96, 0.92), Vector3(0, 0, PI / 2.0), 20)
	k.add_box(Vector3(0.12, 0.45, 0.06), Vector3(x0 - 4.68, 4.12, 0), Color(0.1, 0.1, 0.1))
	k.add_box(Vector3(0.12, 0.06, 0.34), Vector3(x0 - 4.68, 4.0, 0.12), Color(0.1, 0.1, 0.1))
	# Parvis côté ville : dalle, deux bancs et un portique à vélos.
	k.add_box(Vector3(10.0, 0.05, 30.0), Vector3(x0 + 9.5, 0.025, 0), Color(0.6, 0.58, 0.55))
	return k


## Dalle de chemin : posée tous les 3 m le long de la ligne d'accès (gravier clair).
static func path_tile() -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(2.6, 0.08, 3.3), Vector3(0, 0.04, 0), Color(0.78, 0.72, 0.6))
	return k


## Valise à roulettes (voyageur) : coque, poignée, roues.
static func suitcase(color := Color(0.8, 0.25, 0.25)) -> PropKit:
	var k := PropKit.new()
	k.add_box(Vector3(0.42, 0.62, 0.22), Vector3(0, 0.4, 0), color)
	k.add_box(Vector3(0.05, 0.38, 0.05), Vector3(0.12, 0.9, 0), Color(0.2, 0.2, 0.22))
	k.add_box(Vector3(0.3, 0.05, 0.05), Vector3(0.0, 1.1, 0), Color(0.2, 0.2, 0.22))
	for sx in [-0.16, 0.16]:
		k.add_cyl(0.04, 0.04, 0.04, Vector3(sx, 0.05, 0.08), Color(0.15, 0.15, 0.15), Vector3(0, 0, PI / 2.0), 6)
	return k
