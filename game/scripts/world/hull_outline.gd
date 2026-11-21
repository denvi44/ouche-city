class_name HullOutline
extends RefCounted
## Contour « inverted hull » à normales lissées (agent 03), partagé par le décor et les véhicules.
## À partir d'une liste de triangles (Vector3 ×3, sens horaire vu de l'extérieur), produit un
## maillage dont chaque sommet porte, dans COLOR, la normale moyenne des faces qui partagent
## sa position. `contour_decor.gdshader` le gonfle sans ouvrir les angles.

const MATERIAL := preload("res://assets/materials/contour_decor.tres")


static func _key(v: Vector3) -> Vector3i:
	return Vector3i(roundi(v.x * 50.0), roundi(v.y * 50.0), roundi(v.z * 50.0))


static func build(tris: Array) -> ArrayMesh:
	var sums := {}
	for t in tris:
		var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
		for v in t:
			var k := _key(v)
			sums[k] = sums.get(k, Vector3.ZERO) + n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in tris:
		for v in t:
			# La normale géométrique d'un triangle horaire pointe vers l'intérieur : on l'inverse.
			var sn: Vector3 = -(sums[_key(v)] as Vector3).normalized()
			st.set_color(Color(sn.x * 0.5 + 0.5, sn.y * 0.5 + 0.5, sn.z * 0.5 + 0.5))
			st.add_vertex(v)
	var mesh := ArrayMesh.new()
	if not tris.is_empty():
		st.set_material(MATERIAL)
		st.commit(mesh)
	return mesh


## Triangles d'un maillage primitif, placés par `xf`.
static func tris_of(mesh: Mesh, xf: Transform3D) -> Array:
	var out := []
	var faces := mesh.get_faces()
	for i in range(0, faces.size() - 2, 3):
		out.append([xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]])
	return out
