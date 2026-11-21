extends CanvasLayer
## Interface en jeu : état de la partie, heure, mention OSM obligatoire, menu pause.

var _info: Label
var _pause: PanelContainer
var _open_btn: Button
var _mission_label: Label
var _hint: Label
var _speed: Label
var _result: Label
var _captions: Label
var _caption_lines: Array = []      # [texte, instant d'expiration (s)]


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
	_build_mission(root)
	_build_captions(root)
	_build_pause(root)
	Sfx.caption.connect(_on_caption)


func _outlined(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", int(size * Settings.text_scale))
	l.add_theme_color_override("font_color", ThemeUtil.CREAM)
	l.add_theme_color_override("font_outline_color", ThemeUtil.INK)
	l.add_theme_constant_override("outline_size", 8)


func _build_mission(root: Control) -> void:
	_mission_label = Label.new()
	_mission_label.position = Vector2(24, 64)
	_mission_label.custom_minimum_size = Vector2(620, 0)
	_mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outlined(_mission_label, 22)
	root.add_child(_mission_label)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.position.y -= 90
	_outlined(_hint, 30)
	root.add_child(_hint)
	_speed = Label.new()
	_speed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed.position -= Vector2(24, 60)
	_outlined(_speed, 40)
	root.add_child(_speed)
	_result = Label.new()
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_result.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_result.position.y += 140
	_outlined(_result, 54)
	root.add_child(_result)


## Sous-titres sonores : toute information importante transmise par le son a un équivalent écrit.
func _build_captions(root: Control) -> void:
	_captions = Label.new()
	_captions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_captions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_captions.position += Vector2(24, -24)
	_outlined(_captions, 24)
	root.add_child(_captions)


func _on_caption(text: String, seconds: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_caption_lines.append([text, now + seconds])
	if _caption_lines.size() > 4:
		_caption_lines.pop_front()


## Texte des sous-titres encore valables à l'instant `now` (fonction pure, testée).
static func caption_text(lines: Array, now: float) -> String:
	var out: PackedStringArray = []
	for l in lines:
		if l[1] > now:
			out.append(l[0])
	return "\n".join(out)


static func format_time(seconds: float) -> String:
	return MissionBase.format_time(seconds)


static func companions_of(m: MissionBase) -> Array:
	return m.companions()


## Texte du panneau de mission (fonction pure, testée).
static func mission_text(m: MissionBase) -> String:
	return "\n".join(m.hud_lines())


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
	# Réglages audio : volumes par bus et sous-titres sonores.
	for spec in [["Volume général", "volume_master"], ["Effets", "volume_sfx"], ["Musique (radio)", "volume_music"], ["Ambiance", "volume_ambience"]]:
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = spec[0]
		lab.custom_minimum_size = Vector2(230, 0)
		row.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = Settings.get(spec[1])
		sl.custom_minimum_size = Vector2(190, 28)
		sl.value_changed.connect(func(v: float):
			Settings.set(spec[1], v)
			Sfx.apply_volumes()
			Settings.save_settings())
		row.add_child(sl)
		box.add_child(row)
	var sub := CheckButton.new()
	sub.text = "Sous-titres sonores"
	sub.button_pressed = Settings.subtitles
	sub.toggled.connect(func(on: bool):
		Settings.subtitles = on
		Settings.save_settings())
	box.add_child(sub)
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
	var world := get_parent()
	var mission := world.get("mission") as MissionBase if world else null
	if mission:
		_mission_label.text = mission_text(mission)
		var me := world.players_root.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		_hint.text = ""
		_speed.text = ""
		if me:
			var r := mission.resolve(me.peer_id, me.global_position)
			if r.has("label"):
				_hint.text = ("[E]  " if r.kind != "none" else "") + r.label
			if me.is_driving() and me.vehicle:
				_speed.text = "%d km/h   ·   [R] Radio Pommiers %s" % [int(me.vehicle.speed_kmh()), "♪" if Sfx.radio_on else "(éteinte)"]
		_result.text = mission.result_text()
	_captions.text = caption_text(_caption_lines, Time.get_ticks_msec() / 1000.0) if Settings.subtitles else ""
	_info.text = "Rue Sainte-Foy · %02d h %02d · %s · %d joueur(s)" % [int(h), int(fmod(h, 1.0) * 60), mode_txt, maxi(Net.players.size(), 1)]
