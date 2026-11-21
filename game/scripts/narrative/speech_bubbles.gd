class_name SpeechBubbles
extends Node3D
## Bulles de dialogue au-dessus des personnages (agent 03 / 07) + onomatopées liées aux répliques (`#onoma:`).
## Le locuteur est retrouvé par son nom : compagnons (identifiants négatifs), PNJ de mission (nœuds nommés du monde),
## sinon le joueur local. Sans rendu en mode headless.

const SPEAKER_NODES := {
	"Gégé": "-1", "Tonton Gégé": "-1", "Ginette": "-2", "Kévin Radio": "-3", "Kévin": "-4",
	"Mme Hubert": "MmeHubert", "Gégé du stand": "GegeStand", "Josette": "Josette", "Dylan": "Dylan", "Gendarme": "Gardien", "Marguerite": "Vache_0",
}
const PIXEL := 0.0055
const MAX_WIDTH_PX := 460
const COLORS := {"Gégé": Color(0.78, 0.55, 0.3), "Ginette": Color(0.85, 0.4, 0.55), "Kévin": Color(0.95, 0.8, 0.25), "Kévin Radio": Color(0.3, 0.65, 0.65)}

var _bubbles := {}                   # locuteur -> Node3D
var shown := 0                       ## bulles de dialogue posées (tests)


func _ready() -> void:
	name = "Bulles"


func bind(player: DialoguePlayer) -> void:
	player.line_started.connect(_on_line)


## Nœud 3D du locuteur ; le joueur local à défaut.
func speaker_node(speaker: String) -> Node3D:
	var world := get_parent()
	if world == null:
		return null
	var key: String = SPEAKER_NODES.get(speaker, "")
	var players: Node = world.get("players_root")
	# Le héros de la mission, c'est le joueur : ses répliques sortent de sa bouche.
	if key != "" and world.get("hero_id") != null and int(world.get("hero_id")) != 0 and str(int(world.get("hero_id"))) == key and players:
		var me := players.get_node_or_null("1") as Node3D
		if me:
			return me
	if key != "":
		if players:
			var p := players.get_node_or_null(key) as Node3D
			if p:
				return p
		var n := world.find_child(key, true, false) as Node3D
		if n:
			return n
	if speaker == "Gégé":
		var gs := world.find_child("GegeStand", true, false) as Node3D
		if gs:
			return gs
	if players and multiplayer.has_multiplayer_peer():
		return players.get_node_or_null(str(multiplayer.get_unique_id())) as Node3D
	return null


func _on_line(speaker: String, text: String, _id: String, seconds: float, tags: Dictionary) -> void:
	var node := speaker_node(speaker)
	var sfx0 := get_node_or_null("/root/Sfx")
	if sfx0 and DisplayServer.get_name() != "headless":
		sfx0.play("babble", 0.0, 0.8 + float(speaker.hash() % 40) / 100.0)
	if tags.has("onoma"):
		var sfx := get_node_or_null("/root/Sfx")
		if sfx:
			sfx.say_onoma(str(tags.onoma), node.global_position if node else null, "loud")
	var st := get_node_or_null("/root/Settings")
	if DisplayServer.get_name() == "headless" or (st != null and not bool(st.get("speech_bubbles"))) or node == null:
		return
	show_bubble(speaker, text, node, seconds)


func show_bubble(speaker: String, text: String, target: Node3D, seconds: float) -> Node3D:
	if _bubbles.has(speaker) and is_instance_valid(_bubbles[speaker]):
		(_bubbles[speaker] as Node3D).queue_free()
	var root := Node3D.new()
	root.name = "Bulle_" + speaker
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.pixel_size = PIXEL
	label.width = MAX_WIDTH_PX
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.12, 0.09, 0.08)
	label.outline_size = 0
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 7
	label.position.z = 0.02
	var chars_per_line := 24.0
	var lines := ceilf(float(text.length()) / chars_per_line)
	var w := clampf(float(minf(text.length(), 26)) * 0.12 + 0.5, 1.2, 2.9)
	var h := lines * 0.27 + 0.32
	var quad_dark := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w + 0.1, h + 0.1)
	quad_dark.mesh = qm
	quad_dark.material_override = _mat(Color(0.12, 0.09, 0.08))
	root.add_child(quad_dark)
	var quad := MeshInstance3D.new()
	var qm2 := QuadMesh.new()
	qm2.size = Vector2(w, h)
	quad.mesh = qm2
	quad.material_override = _mat(COLORS.get(speaker, Color(0.98, 0.96, 0.9)).lerp(Color(0.98, 0.96, 0.9), 0.65), 2)
	quad.position.z = 0.005
	root.add_child(quad)
	# Petite queue vers le locuteur.
	var tail := MeshInstance3D.new()
	var tm := PrismMesh.new()
	tm.size = Vector3(0.22, 0.24, 0.01)
	tail.mesh = tm
	tail.rotation_degrees.z = 180.0
	tail.position = Vector3(0.0, -h / 2.0 - 0.1, 0.004)
	tail.material_override = _mat(Color(0.98, 0.96, 0.9), 2)
	root.add_child(tail)
	root.add_child(label)
	target.add_child(root)
	root.position = Vector3(0, 2.55 + h / 2.0 + 0.2, 0)
	if target.has_method("speed_kmh") or str(target.name) in ["Dylan"]:
		root.position.y += 0.6
	_bubbles[speaker] = root
	shown += 1
	var tw := root.create_tween()
	root.scale = Vector3.ZERO
	tw.tween_property(root, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(seconds - 0.3, 0.2))
	tw.tween_property(root, "scale", Vector3.ZERO, 0.15)
	tw.tween_callback(root.queue_free)
	return root


func _mat(color: Color, priority := 1) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = priority
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
