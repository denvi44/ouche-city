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
