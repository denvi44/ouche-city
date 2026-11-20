extends CanvasLayer
## Interface en jeu : état de la partie, heure, mention OSM obligatoire, menu pause.

var _info: Label
var _pause: PanelContainer
var _open_btn: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = ThemeUtil.make_theme()
	add_child(root)
	_info = Label.new()
	_info.position = Vector2(24, 18)
	_info.add_theme_color_override("font_color", ThemeUtil.CREAM)
	_info.add_theme_color_override("font_outline_color", ThemeUtil.INK)
	_info.add_theme_constant_override("outline_size", 8)
	root.add_child(_info)
	var osm := Label.new()
	osm.text = map_credit(CityBuilder.load_manifest())
	osm.add_theme_font_size_override("font_size", int(18 * Settings.text_scale))
	osm.add_theme_color_override("font_color", ThemeUtil.CREAM)
	osm.add_theme_color_override("font_outline_color", ThemeUtil.INK)
	osm.add_theme_constant_override("outline_size", 6)
	osm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	osm.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	osm.grow_vertical = Control.GROW_DIRECTION_BEGIN
	osm.position -= Vector2(16, 10)
	root.add_child(osm)
	_build_pause(root)


## Mention obligatoire des sources de la carte, d'après le manifeste du cartographe.
static func map_credit(manifest: Dictionary) -> String:
	var parts: PackedStringArray = []
	for a in manifest.get("attribution", []):
		if "OpenStreetMap" in a:
			parts.append("© contributeurs OpenStreetMap")
		elif "IGN" in a:
			parts.append("Source : IGN")
	return "Carte : " + (" · ".join(parts) if not parts.is_empty() else "© contributeurs OpenStreetMap")


func _build_pause(root: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_pause = PanelContainer.new()
	_pause.visible = false
	center.add_child(_pause)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(460, 0)
	_pause.add_child(box)
	var title := Label.new()
	title.text = "Pause"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Reprendre"
	resume.pressed.connect(_toggle_pause)
	box.add_child(resume)
	_open_btn = Button.new()
	_open_btn.text = "Ouvrir la partie aux amis"
	_open_btn.pressed.connect(func():
		Net.open_to_friends()
		_open_btn.text = "Ouverte sur le port %d" % Net.port
		_open_btn.disabled = true)
	box.add_child(_open_btn)
	var quit := Button.new()
	quit.text = "Retour au menu"
	quit.pressed.connect(func():
		Net.leave()
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main.tscn"))
	box.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	_pause.visible = not _pause.visible
	_open_btn.visible = Net.mode == Net.Mode.SOLO
	# Le monde ne se fige qu'en solo sans invité ; en ligne, le menu s'ouvre par-dessus.
	get_tree().paused = _pause.visible and Net.can_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _pause.visible else Input.MOUSE_MODE_CAPTURED
	if _pause.visible:
		_pause.get_child(0).get_child(1).grab_focus()


func _process(_delta: float) -> void:
	var dn := get_parent().get_node_or_null("CycleJourNuit") as DayNight
	var h: float = dn.hour if dn else 12.0
	var mode_txt: String = {Net.Mode.SOLO: "Solo", Net.Mode.HOST: "Hôte", Net.Mode.CLIENT: "En ligne", Net.Mode.DEDICATED: "Serveur"}.get(Net.mode, "—")
	_info.text = "Rue Sainte-Foy · %02d h %02d · %s · %d joueur(s)" % [int(h), int(fmod(h, 1.0) * 60), mode_txt, maxi(Net.players.size(), 1)]
