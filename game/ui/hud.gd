extends CanvasLayer
## Interface en jeu : état de la partie, heure, mention OSM obligatoire, menu pause.

var _info: Label
var _pause: PanelContainer
var _open_btn: Button
var _mission_label: Label
var _card: PanelContainer
var _title: Label
var _objective: Label
var _gauge_box: VBoxContainer
var _gauges := {}                   # id -> HudWidgets.GaugeBar
var _status: Label
var _minimap: HudWidgets.Minimap
var _markers: HudWidgets.MarkerLayer
var _prompt: PanelContainer
var _key: Label
var _prompt_text: Label
var _speed_box: PanelContainer
var _speed: Label
var _hint: Label
var _result: Label
var _captions: Label
var _dialogue: Label
var _dialogue_until := 0.0
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
	_build_dialogue(root)
	_build_pause(root)
	Sfx.caption.connect(_on_caption)
	var dlg := get_parent().get_node_or_null("Dialogues") as DialoguePlayer
	if dlg:
		dlg.line_started.connect(_on_dialogue_line)


func _outlined(l: Label, size: int) -> void:
	l.add_theme_font_size_override("font_size", int(size * Settings.text_scale))
	l.add_theme_color_override("font_color", ThemeUtil.CREAM)
	l.add_theme_color_override("font_outline_color", ThemeUtil.INK)
	l.add_theme_constant_override("outline_size", 8)


func _panel_style(bg: Color, border := ThemeUtil.INK, radius := 12, width := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(12)
	return sb


func _build_mission(root: Control) -> void:
	var ts: float = Settings.text_scale
	# Carte de mission (haut gauche) : titre, consigne, jauges graphiques, journal.
	_card = PanelContainer.new()
	_card.position = Vector2(20, 58)
	_card.add_theme_stylebox_override("panel", _panel_style(Color(0.2, 0.15, 0.12, 0.82), ThemeUtil.CREAM, 14, 2))
	root.add_child(_card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.custom_minimum_size = Vector2(480 * ts, 0)
	_card.add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", int(28 * ts))
	_title.add_theme_color_override("font_color", Color(0.98, 0.8, 0.3))
	box.add_child(_title)
	_objective = Label.new()
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.custom_minimum_size = Vector2(470 * ts, 0)
	_objective.add_theme_font_size_override("font_size", int(19 * ts))
	_objective.add_theme_color_override("font_color", ThemeUtil.CREAM)
	box.add_child(_objective)
	_gauge_box = VBoxContainer.new()
	_gauge_box.add_theme_constant_override("separation", 4)
	box.add_child(_gauge_box)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(470 * ts, 0)
	_status.add_theme_font_size_override("font_size", int(16 * ts))
	_status.add_theme_color_override("font_color", Color(0.9, 0.86, 0.76))
	box.add_child(_status)
	_mission_label = _status
	# Minicarte (haut droite) et balises d'objectif sur l'écran.
	_minimap = HudWidgets.Minimap.new()
	_minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_minimap.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_minimap.position += Vector2(-18, 18)
	root.add_child(_minimap)
	_markers = HudWidgets.MarkerLayer.new()
	root.add_child(_markers)
	root.move_child(_markers, 0)
	# Bulle d'action (bas centre) : touche + consigne.
	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", _panel_style(Color(0.97, 0.93, 0.82, 0.94), ThemeUtil.INK, 22, 3))
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.position.y -= 70
	_prompt.visible = false
	root.add_child(_prompt)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_prompt.add_child(hb)
	var cap := PanelContainer.new()
	cap.add_theme_stylebox_override("panel", _panel_style(ThemeUtil.INK, ThemeUtil.INK, 8, 2))
	hb.add_child(cap)
	_key = Label.new()
	_key.add_theme_font_size_override("font_size", int(26 * ts))
	_key.add_theme_color_override("font_color", ThemeUtil.CREAM)
	cap.add_child(_key)
	_prompt_text = Label.new()
	_prompt_text.add_theme_font_size_override("font_size", int(22 * ts))
	_prompt_text.add_theme_color_override("font_color", ThemeUtil.INK)
	_prompt_text.custom_minimum_size = Vector2(0, 0)
	hb.add_child(_prompt_text)
	_hint = _prompt_text
	# Compteur de vitesse (bas droite, au volant).
	_speed_box = PanelContainer.new()
	_speed_box.add_theme_stylebox_override("panel", _panel_style(Color(0.2, 0.15, 0.12, 0.85), ThemeUtil.CREAM, 18, 2))
	_speed_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed_box.position -= Vector2(20, 50)
	_speed_box.visible = false
	root.add_child(_speed_box)
	_speed = Label.new()
	_speed.add_theme_font_size_override("font_size", int(30 * ts))
	_speed.add_theme_color_override("font_color", ThemeUtil.CREAM)
	_speed_box.add_child(_speed)
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


## Réplique en cours, en bas au centre : « Locuteur : texte » (le texte reste lisible même sans bulle ni son).
func _build_dialogue(root: Control) -> void:
	_dialogue = Label.new()
	_dialogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialogue.custom_minimum_size = Vector2(900, 0)
	_dialogue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_dialogue.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_dialogue.position.y -= 150
	_outlined(_dialogue, 28)
	root.add_child(_dialogue)


func _on_dialogue_line(speaker: String, text: String, _id: String, seconds: float, _tags: Dictionary) -> void:
	_dialogue.text = "%s : %s" % [speaker, text]
	_dialogue_until = Time.get_ticks_msec() / 1000.0 + seconds + 0.3


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
	var ono := CheckButton.new()
	ono.text = "Onomatopées en bulles (POUET !, BOUM !)"
	ono.button_pressed = Settings.onomatopees
	ono.toggled.connect(func(on: bool):
		Settings.onomatopees = on
		Settings.save_settings())
	box.add_child(ono)
	var bub := CheckButton.new()
	bub.text = "Bulles de dialogue au-dessus des personnages"
	bub.button_pressed = Settings.speech_bubbles
	bub.toggled.connect(func(on: bool):
		Settings.speech_bubbles = on
		Settings.save_settings())
	box.add_child(bub)
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
	var me: Player = null
	if mission:
		me = world.players_root.get_node_or_null(str(multiplayer.get_unique_id())) as Player
		var lines := mission.hud_lines()
		var gauges := mission.hud_gauges()
		_title.text = str(lines[0]) if lines.size() > 0 else ""
		_objective.text = str(lines[1]) if lines.size() > 1 else ""
		_update_gauges(gauges)
		_status.text = "\n".join(status_lines(lines, not gauges.is_empty()))
		_status.visible = _status.text != ""
		_card.visible = true
		var markers := mission.hud_markers()
		_markers.markers = markers
		_markers.text_scale = Settings.text_scale
		_markers.queue_redraw()
		_minimap.markers = markers
		if me:
			_minimap.player_pos = Vector2(me.global_position.x, me.global_position.z)
			_minimap.player_yaw = me.facing
		_minimap.queue_redraw()
		_prompt.visible = false
		_speed_box.visible = false
		if me:
			var r := mission.resolve(me.peer_id, me.global_position)
			if r.has("label"):
				_prompt.visible = true
				_key.get_parent().visible = r.kind != "none"
				_key.text = "E"
				_prompt_text.text = str(r.label)
			if me.is_driving() and me.vehicle:
				_speed_box.visible = true
				_speed.text = "%d km/h   ·   [R] Radio %s" % [int(me.vehicle.speed_kmh()), "♪" if Sfx.radio_on else "(éteinte)"]
		_result.text = mission.result_text()
	_captions.text = caption_text(_caption_lines, Time.get_ticks_msec() / 1000.0) if Settings.subtitles else ""
	if _dialogue and Time.get_ticks_msec() / 1000.0 > _dialogue_until:
		_dialogue.text = ""
	_info.text = "Rue Sainte-Foy · %02d h %02d · %s · %d joueur(s)" % [int(h), int(fmod(h, 1.0) * 60), mode_txt, maxi(Net.players.size(), 1)]


## Lignes d'état affichées sous les jauges : le journal et les compagnons (« • … ») et les menus ; les lignes de chiffres sont
## remplacées par les jauges quand il y en a (fonction pure, testée).
static func status_lines(lines: PackedStringArray, has_gauges: bool) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(2, lines.size()):
		var l := lines[i]
		if not has_gauges or l.begins_with("•") or l.begins_with("Menu") or l.begins_with("  ["):
			out.append(l)
	return out


func _update_gauges(specs: Array) -> void:
	var ids := []
	for sp in specs:
		ids.append(sp.id)
	if ids != _gauges.keys():
		for c in _gauge_box.get_children():
			c.queue_free()
		_gauges.clear()
		for sp in specs:
			var g := HudWidgets.GaugeBar.new()
			_gauge_box.add_child(g)
			_gauges[sp.id] = g
	for sp in specs:
		(_gauges[sp.id] as HudWidgets.GaugeBar).set_spec(sp, Settings.text_scale)
