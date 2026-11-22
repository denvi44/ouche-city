extends Control
## Menu principal : solo (serveur local), héberger, rejoindre. Lit aussi la ligne de commande :
##   -- --server            serveur dédié (headless)
##   -- --solo | --host     lance directement la partie
##   -- --join=IP[:PORT]    rejoint une partie

const WORLD := "res://scenes/temoin_rue_sainte_foy.tscn"

var _status: Label
var _name: LineEdit
var _address: LineEdit


func _ready() -> void:
	theme = ThemeUtil.make_material_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Net.joined.connect(_go_world)
	Net.refused.connect(func(r): _set_status(r))
	Net.connection_failed.connect(func(): _set_status("Connexion impossible. Le serveur est peut-être parti traire."))
	if _handle_cmdline():
		return
	_build()
	Sfx.play_mission_music("titre")


func _handle_cmdline() -> bool:
	if Net.arg("server") != null:
		if Net.start_dedicated() == OK:
			_go_world.call_deferred()
		else:
			get_tree().quit(1)
		return true
	if Net.arg("solo") != null:
		Net.host_solo()
		_go_world.call_deferred()
		return true
	if Net.arg("host") != null:
		Net.host_game()
		_go_world.call_deferred()
		return true
	var j = Net.arg("join")
	if j != null:
		_build()
		_join(str(j), false)   # une adresse passée en ligne de commande ne doit pas écraser les réglages
		return true
	return false


## Missions du solo : [clé, texte si disponible, texte si verrouillée]. La première est toujours disponible ;
## chaque suivante s'ouvre quand la précédente (CHAIN) est terminée.
const SOLO_MISSIONS := [
	["m01", "Jouer en solo (mission 1 : le Calva de Tonton Gégé)", ""],
	["m02", "Solo : Tuning du samedi soir (mission 2)", "Mission 2 : terminez d'abord le Calva de Tonton Gégé"],
	["m03", "Solo : Battle de sono (mission 3)", "Mission 3 : terminez d'abord Tuning du samedi soir"],
	["m04", "Solo : Le méchoui de la Saint-Jean (mission 4)", "Mission 4 : terminez d'abord la Battle de sono"],
	["m05", "Solo : Les vaches sont de sortie (mission 5)", "Mission 5 : terminez d'abord le méchoui de la Saint-Jean"],
	["m06", "Solo : Les courses de 8 h (mission 6)", "Mission 6 : terminez d'abord les vaches"],
	["m07", "Solo : Le jus de pomme de Tonton Gégé (mission 7)", "Mission 7 : terminez d'abord les courses de 8 h"],
	["m08", "Solo : Les oies font grève (mission 8)", "Mission 8 : terminez d'abord le jus de pomme"],
]
var _backdrop: TitleBackdrop


## Écran titre « Material » : une carte translucide à gauche, le village filmé par un drone derrière.
func _build() -> void:
	theme = ThemeUtil.make_material_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.62, 0.78, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if TitleBackdrop.available():
		_backdrop = TitleBackdrop.new()
		add_child(_backdrop)
		_backdrop.start.call_deferred()
	var blason := _make_blason()
	if blason:
		add_child(blason)          # entre les images aériennes et le menu
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"Card"
	panel.custom_minimum_size = Vector2(int(600 * Settings.text_scale), 0)
	row.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	# Titre : grosses capitales condensées, crème cerclé d'encre avec ombre pomme ; slogan sur une étiquette rouge.
	var title := Label.new()
	title.text = "FROUCH CITY"
	title.add_theme_font_size_override("font_size", int(120 * Settings.text_scale))
	title.add_theme_color_override("font_color", Color(1, 0.98, 0.92))
	title.add_theme_color_override("font_outline_color", ThemeUtil.INK)
	title.add_theme_constant_override("outline_size", 18)
	title.add_theme_color_override("font_shadow_color", ThemeUtil.APPLE)
	title.add_theme_constant_override("shadow_offset_x", 6)
	title.add_theme_constant_override("shadow_offset_y", 7)
	box.add_child(title)
	var tag := PanelContainer.new()
	tag.theme_type_variation = &"Tag"
	tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var sub := Label.new()
	sub.text = "Conches-en-Frouch, ses colombages, ses embrouilles"
	sub.add_theme_constant_override("outline_size", 0)
	sub.add_theme_color_override("font_color", Color(1, 1, 1))
	tag.add_child(sub)
	box.add_child(tag)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	box.add_child(gap)
	_name = LineEdit.new()
	_name.text = Settings.player_name
	_name.placeholder_text = "Votre nom"
	_name.max_length = 24
	box.add_child(_name)
	_build_save_block(box)
	# Missions : repliées par défaut (la partie « Continuer » suffit à la plupart des joueurs).
	var missions := VBoxContainer.new()
	missions.add_theme_constant_override("separation", 8)
	missions.visible = false
	var toggle := Button.new()
	toggle.text = "Choisir une mission  ▾"
	toggle.pressed.connect(func():
		missions.visible = not missions.visible
		toggle.text = "Choisir une mission  " + ("▴" if missions.visible else "▾"))
	box.add_child(toggle)
	box.add_child(missions)
	for i in SOLO_MISSIONS.size():
		var m: Array = SOLO_MISSIONS[i]
		var ok: bool = i == 0 or Progress.is_available(CHAIN[i], [CHAIN[i - 1]])
		var btn := Button.new()
		btn.text = m[1] if ok else m[2]
		btn.disabled = not ok
		var key: String = m[0]
		btn.pressed.connect(func():
			Net.mission_id = key
			_solo())
		missions.add_child(btn)
	_button(box, "Touches et souris", func():
		var cm = preload("res://ui/controls_menu.gd").new()
		add_child(cm))
	_button(box, "Mes musiques (ouvrir le dossier)", func():
		OS.shell_open(MusicLibrary.ensure_dirs()))
	_button(box, "Héberger une partie", _host)
	_address = LineEdit.new()
	_address.placeholder_text = "Adresse de l'hôte (ex. 192.168.1.20)"
	_address.text = "127.0.0.1"
	box.add_child(_address)
	_button(box, "Rejoindre", func(): _join(_address.text))
	_button(box, "Quitter", func(): get_tree().quit(), &"TextButton")
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	# Colonne de droite : on laisse voir le drone ; légende du plan et crédits en puces, en bas.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	if _backdrop:
		var chip := PanelContainer.new()
		chip.theme_type_variation = &"Chip"
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END
		var cl := Label.new()
		cl.theme_type_variation = &"ChipLabel"
		cl.add_theme_font_size_override("font_size", int(20 * Settings.text_scale))
		chip.add_child(cl)
		_backdrop.bind_caption(cl)
		right.add_child(chip)
	var credit_chip := PanelContainer.new()
	credit_chip.theme_type_variation = &"Chip"
	credit_chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	var credit := Label.new()
	credit.theme_type_variation = &"ChipLabel"
	credit.text = preload("res://ui/hud.gd").map_credit(CityBuilder.load_manifest()) + " — personnages et commerces fictifs."
	credit.add_theme_font_size_override("font_size", int(16 * Settings.text_scale))
	credit_chip.add_child(credit)
	right.add_child(credit_chip)
	ThemeUtil.align_bars(box)
	for c in box.get_children():
		if c is Button and not (c as Button).disabled:
			(c as Button).grab_focus()
			break


const CHAIN := ["m01_calva_gege", "m02_tuning_samedi", "m03_battle_sono", "m04_mechoui_saint_jean", "m05_vaches_en_goguette", "m06_courses_de_8h", "m07_jus_de_pomme", "m08_oies_en_greve"]
const MEDAL_TXT := {"": "–", "bronze": "bronze", "silver": "argent", "gold": "or"}


## Prochaine mission à jouer : la première de la chaîne non terminée (m01 si rien n'est fait).
static func next_mission_key() -> String:
	var prog = Engine.get_main_loop().root.get_node("Progress")
	for i in CHAIN.size():
		if not prog.is_done(CHAIN[i]):
			return "m%02d" % (i + 1)
	return "m%02d" % CHAIN.size()


## Résumé de la sauvegarde, « Continuer » et « Nouvelle partie » (avec confirmation).
func _build_save_block(box: VBoxContainer) -> void:
	var done := 0
	var medals: PackedStringArray = []
	for id in CHAIN:
		if Progress.is_done(id):
			done += 1
			medals.append(MEDAL_TXT.get(Progress.medal_of(id), "–"))
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if done == 0 and Progress.money() == 0:
		info.text = "Aucune sauvegarde : une nouvelle partie commence."
	else:
		info.text = "Sauvegarde : %d / %d missions, %d €, médailles : %s." % [done, CHAIN.size(), Progress.money(), ", ".join(medals) if medals.size() > 0 else "aucune"]
	box.add_child(info)
	var key := next_mission_key()
	var chap := Label.new()
	chap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chap.add_theme_color_override("font_color", Color(1, 0.98, 0.92))
	var hero_name := Heroes.name_of(Heroes.raw_hero_of(key))
	chap.text = "Chapitre %d · %s%s" % [int(key.substr(1)), SOLO_MISSIONS[int(key.substr(1)) - 1][1].replace("Jouer en solo (mission 1 : ", "").replace("Solo : ", "").trim_suffix(")"), ("\nVous jouez : " + hero_name) if hero_name != "" else ""]
	box.add_child(chap)
	var cont := Button.new()
	cont.text = "Continuer (mission %d)" % int(key.substr(1)) if done > 0 else "Nouvelle partie (mission 1)"
	cont.theme_type_variation = &"FilledButton"
	cont.pressed.connect(func():
		Net.mission_id = key
		_solo())
	box.add_child(cont)
	if done > 0 or Progress.money() > 0:
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Effacer la sauvegarde et repartir de zéro ?"
		dlg.ok_button_text = "Effacer"
		dlg.cancel_button_text = "Garder"
		dlg.confirmed.connect(func():
			Progress.reset()
			get_tree().reload_current_scene())
		add_child(dlg)
		var wipe := Button.new()
		wipe.text = "Nouvelle partie (efface la sauvegarde)"
		wipe.theme_type_variation = &"TextButton"
		wipe.pressed.connect(func(): dlg.popup_centered())
		box.add_child(wipe)


const BLASON_USER := "user://blason.png"             # remplace le blason livré (essai sans reconstruire)
const BLASON_RES := "res://assets/ui/blason.png"
const BLASON_ALPHA := 0.4


## Blason détourné : image posée en transparence entre le village (drone) et le menu ; absente = rien n'est ajouté.
static func blason_texture() -> Texture2D:
	if FileAccess.file_exists(BLASON_USER):
		var img := Image.load_from_file(BLASON_USER)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(BLASON_RES):
		var t = load(BLASON_RES)
		if t is Texture2D:
			return t
	return null


func _make_blason() -> Control:
	var tex := blason_texture()
	if tex == null:
		return null
	var r := TextureRect.new()
	r.name = "Blason"
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centré dans la zone libre à droite du menu, haut de 70 % de l'écran.
	r.anchor_left = 0.36
	r.anchor_right = 1.0
	r.anchor_top = 0.12
	r.anchor_bottom = 0.88
	r.modulate = Color(1, 1, 1, 0.0)
	create_tween().tween_property(r, "modulate:a", BLASON_ALPHA, 1.6)
	return r


func _button(parent: Node, text: String, cb: Callable, variation := &"") -> void:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.pressed.connect(cb)
	parent.add_child(b)


func _save_name() -> void:
	if _name and _name.text.strip_edges() != "":
		Settings.player_name = _name.text.strip_edges()
		Settings.save_settings()


func _solo() -> void:
	_save_name()
	if Net.host_solo() == OK:
		_go_world()
	else:
		_set_status("Impossible de démarrer le serveur local.")


func _host() -> void:
	_save_name()
	if Net.host_game() == OK:
		_go_world()
	else:
		_set_status("Port %d occupé : impossible d'héberger." % Net.port)


func _join(address: String, persist := true) -> void:
	if persist:
		_save_name()
	var host := address.strip_edges()
	var p := -1
	if ":" in host:
		p = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	if Net.join(host, p) != OK:
		_set_status("Adresse invalide.")
	else:
		_set_status("Connexion en cours…")


func _set_status(text: String) -> void:
	if _status:
		_status.text = text
	print("[menu] ", text)


func _go_world() -> void:
	get_tree().change_scene_to_file(WORLD)
