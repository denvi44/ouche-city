class_name OnomaLayer
extends Node3D
## Bulles d'onomatopées façon bande dessinée (agent 03 / 08) : « POUET POUET ! », « BOUM ! », « CRAAAC ! »…
## Écoute `Sfx.onomatopee` : chaque son important a ainsi un équivalent visuel (accessibilité), au-dessus du joueur local
## ou à la position du son. Étoile « explosion » coloriée selon le ton, texte à contour, petit rebond puis disparition.
## Désactivable (`Settings.onomatopees`). Sans rendu en mode headless : seul le journal de `Sfx` compte.

const MAX_BUBBLES := 6
const LIFE := 1.25
const TONES := {
	"loud": Color(0.9, 0.22, 0.2), "soft": Color(0.3, 0.55, 0.9), "good": Color(0.3, 0.75, 0.4), "bad": Color(0.6, 0.35, 0.75),
}

var _bubbles: Array = []
var _star_cache := {}
var shown := 0                       ## nombre de bulles affichées (tests)


func _ready() -> void:
	name = "Onomatopees"
	var sfx := get_node_or_null("/root/Sfx")
	if sfx:
		sfx.onomatopee.connect(_on_onomatopee)


## Étoile à `spikes` pointes (rayon `r` / `r * 0.62`), éventail de triangles dans le plan XY.
static func star_mesh(spikes := 11, r := 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := spikes * 2
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		var r0 := r if i % 2 == 0 else r * 0.62
		var r1 := r if (i + 1) % 2 == 0 else r * 0.62
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(cos(a1) * r1, sin(a1) * r1 * 0.72, 0))
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(Vector3(cos(a0) * r0, sin(a0) * r0 * 0.72, 0))
	return st.commit()


func _material(color: Color, priority := 10) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = priority
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _anchor(pos: Variant) -> Vector3:
	if pos is Vector3:
		return (pos as Vector3) + Vector3(0, 1.6, 0)
	var world := get_parent()
	var players: Node = world.get("players_root") if world else null
	if players and multiplayer.has_multiplayer_peer():
		var me := players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
		if me:
			return me.global_position + Vector3(0, 2.9, 0)
	return Vector3(0, 3.0, 0)


## Réglage d'accessibilité lu sans identifiant d'autoload (compatible avec les scripts de test `-s`).
func _enabled() -> bool:
	var st := get_node_or_null("/root/Settings")
	return st == null or bool(st.get("onomatopees"))


func _on_onomatopee(text: String, pos: Variant, tone: String) -> void:
	if DisplayServer.get_name() == "headless" or not _enabled():
		return
	spawn(text, _anchor(pos), tone)


## Pose une bulle à une position monde (public pour les tests et les captures).
func spawn(text: String, at: Vector3, tone := "loud") -> Node3D:
	while _bubbles.size() >= MAX_BUBBLES:
		var old = _bubbles.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var root := Node3D.new()
	root.name = "Onoma"
	add_child(root)
	root.global_position = at + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))
	var color: Color = TONES.get(tone, TONES.loud)
	var w := clampf(0.9 + float(text.length()) * 0.2, 1.6, 4.6)
	var outline := MeshInstance3D.new()
	outline.mesh = star_mesh()
	outline.scale = Vector3(w * 0.62, w * 0.5, 1.0)
	outline.material_override = _material(Color(0.12, 0.08, 0.08), 10)
	root.add_child(outline)
	var star := MeshInstance3D.new()
	star.mesh = star_mesh()
	star.scale = Vector3(w * 0.56, w * 0.45, 1.0)
	star.position.z = 0.01
	star.material_override = _material(color, 11)
	root.add_child(star)
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.0042
	label.outline_size = 10
	label.outline_modulate = Color(0.12, 0.08, 0.08)
	label.modulate = Color(1.0, 0.97, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 13
	label.position.z = 0.02
	root.add_child(label)
	root.rotation_degrees.z = randf_range(-8.0, 8.0)
	root.scale = Vector3.ZERO
	var tw := root.create_tween()
	tw.tween_property(root, "scale", Vector3.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "scale", Vector3.ONE, 0.1)
	tw.parallel().tween_property(root, "position:y", root.position.y + 0.6, LIFE)
	tw.tween_property(root, "scale", Vector3.ZERO, 0.25).set_delay(maxf(LIFE - 0.47, 0.0))
	tw.tween_callback(root.queue_free)
	_bubbles.append(root)
	shown += 1
	return root
