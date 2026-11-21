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
	theme = ThemeUtil.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Net.joined.connect(_go_world)
	Net.refused.connect(func(r): _set_status(r))
	Net.connection_failed.connect(func(): _set_status("Connexion impossible. Le serveur est peut-être parti traire."))
	if _handle_cmdline():
		return
	_build()


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


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.62, 0.78, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(560, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Ouche City"
	title.add_theme_font_size_override("font_size", int(64 * Settings.text_scale))
	title.add_theme_color_override("font_color", ThemeUtil.APPLE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Conches-en-Ouche, ses colombages, ses embrouilles."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_name = LineEdit.new()
	_name.text = Settings.player_name
	_name.placeholder_text = "Votre nom"
	_name.max_length = 24
	box.add_child(_name)
	_button(box, "Jouer en solo (mission 1 : le Calva de Tonton Gégé)", func():
		Net.mission_id = "m01"
		_solo())
	# Mission 2 : disponible une fois la mission 1 terminée (ou débloquée par la sauvegarde).
	var m2_ok: bool = Progress.is_available("m02_tuning_samedi", ["m01_calva_gege"])
	var m2 := Button.new()
	m2.text = "Solo : Tuning du samedi soir (mission 2)" if m2_ok else "Mission 2 : terminez d'abord le Calva de Tonton Gégé"
	m2.disabled = not m2_ok
	m2.pressed.connect(func():
		Net.mission_id = "m02"
		_solo())
	box.add_child(m2)
	var m3_ok: bool = Progress.is_available("m03_battle_sono", ["m02_tuning_samedi"])
	var m3 := Button.new()
	m3.text = "Solo : Battle de sono (mission 3)" if m3_ok else "Mission 3 : terminez d'abord Tuning du samedi soir"
	m3.disabled = not m3_ok
	m3.pressed.connect(func():
		Net.mission_id = "m03"
		_solo())
	box.add_child(m3)
	var m4_ok: bool = Progress.is_available("m04_mechoui_saint_jean", ["m03_battle_sono"])
	var m4 := Button.new()
	m4.text = "Solo : Le méchoui de la Saint-Jean (mission 4)" if m4_ok else "Mission 4 : terminez d'abord la Battle de sono"
	m4.disabled = not m4_ok
	m4.pressed.connect(func():
		Net.mission_id = "m04"
		_solo())
	box.add_child(m4)
	var m5_ok: bool = Progress.is_available("m05_vaches_en_goguette", ["m04_mechoui_saint_jean"])
	var m5 := Button.new()
	m5.text = "Solo : Les vaches sont de sortie (mission 5)" if m5_ok else "Mission 5 : terminez d'abord le méchoui de la Saint-Jean"
	m5.disabled = not m5_ok
	m5.pressed.connect(func():
		Net.mission_id = "m05"
		_solo())
	box.add_child(m5)
	var m6_ok: bool = Progress.is_available("m06_courses_de_8h", ["m05_vaches_en_goguette"])
	var m6 := Button.new()
	m6.text = "Solo : Les courses de 8 h (mission 6)" if m6_ok else "Mission 6 : terminez d'abord les vaches"
	m6.disabled = not m6_ok
	m6.pressed.connect(func():
		Net.mission_id = "m06"
		_solo())
	box.add_child(m6)
	var m7_ok: bool = Progress.is_available("m07_jus_de_pomme", ["m06_courses_de_8h"])
	var m7 := Button.new()
	m7.text = "Solo : Le jus de pomme de Tonton Gégé (mission 7)" if m7_ok else "Mission 7 : terminez d'abord les courses de 8 h"
	m7.disabled = not m7_ok
	m7.pressed.connect(func():
		Net.mission_id = "m07"
		_solo())
	box.add_child(m7)
	_button(box, "Héberger une partie", _host)
	_address = LineEdit.new()
	_address.placeholder_text = "Adresse de l'hôte (ex. 192.168.1.20)"
	_address.text = "127.0.0.1"
	box.add_child(_address)
	_button(box, "Rejoindre", func(): _join(_address.text))
	_button(box, "Quitter", func(): get_tree().quit())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	box.add_child(_status)
	var credit := Label.new()
	credit.text = preload("res://ui/hud.gd").map_credit(CityBuilder.load_manifest()) + " — personnages et commerces fictifs."
	credit.add_theme_font_size_override("font_size", int(18 * Settings.text_scale))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(credit)
	box.get_child(4).grab_focus()


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
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
