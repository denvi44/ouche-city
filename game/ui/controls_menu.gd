extends Control
## Écran « Touches et souris » (accessibilité : remappage) : une ligne par action, clavier et manette. Clic sur un bouton,
## puis appui sur la nouvelle touche (Échap annule). Une touche déjà prise est échangée avec l'autre action.
## S'utilise depuis l'écran titre et depuis la pause (fonctionne jeu en pause).

signal closed

const Bindings := preload("res://scripts/core/input_bindings.gd")

var _rows := {}               # action -> {"key": Button, "pad": Button}
var _listen := {}             # {} ou {action, kind}
var _info: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.04, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(640, 0)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Touches et souris"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", int(32 * Settings.text_scale))
	box.add_child(title)
	_info = Label.new()
	_info.text = "Clique sur une touche, puis appuie sur la nouvelle (Échap : annuler)."
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	var head := HBoxContainer.new()
	for t in [["Action", 230], ["Clavier", 170], ["Manette", 190]]:
		var l := Label.new()
		l.text = t[0]
		l.custom_minimum_size = Vector2(t[1], 0)
		head.add_child(l)
	rows.add_child(head)
	for a in Bindings.ACTIONS:
		var row := HBoxContainer.new()
		var lab := Label.new()
		lab.text = a[1]
		lab.custom_minimum_size = Vector2(230, 0)
		row.add_child(lab)
		var kb := Button.new()
		kb.custom_minimum_size = Vector2(170, 0)
		kb.pressed.connect(_start.bind(a[0], "key"))
		row.add_child(kb)
		var pb := Button.new()
		pb.custom_minimum_size = Vector2(190, 0)
		pb.disabled = not a[2]
		pb.pressed.connect(_start.bind(a[0], "pad"))
		row.add_child(pb)
		rows.add_child(row)
		_rows[a[0]] = {"key": kb, "pad": pb}
	# Souris : sensibilité et axe vertical.
	var srow := HBoxContainer.new()
	var slab := Label.new()
	slab.text = "Sensibilité de la souris"
	slab.custom_minimum_size = Vector2(230, 0)
	srow.add_child(slab)
	var sl := HSlider.new()
	sl.min_value = 0.001
	sl.max_value = 0.008
	sl.step = 0.0005
	sl.value = Settings.mouse_sensitivity
	sl.custom_minimum_size = Vector2(240, 28)
	sl.value_changed.connect(func(v: float):
		Settings.mouse_sensitivity = v
		Settings.save_settings())
	srow.add_child(sl)
	rows.add_child(srow)
	var inv := CheckButton.new()
	inv.text = "Inverser l'axe vertical de la caméra"
	inv.button_pressed = Settings.invert_y
	inv.toggled.connect(func(on: bool):
		Settings.invert_y = on
		Settings.save_settings())
	rows.add_child(inv)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	var reset := Button.new()
	reset.text = "Touches d'origine"
	reset.pressed.connect(func():
		Bindings.reset_all()
		_info.text = "Touches d'origine rétablies."
		refresh())
	foot.add_child(reset)
	var close := Button.new()
	close.text = "Fermer"
	close.pressed.connect(_close)
	foot.add_child(close)
	box.add_child(foot)
	refresh()
	close.grab_focus()


func refresh() -> void:
	for id in _rows:
		(_rows[id].key as Button).text = Bindings.key_text(Bindings.key_of(id))
		if Bindings.pad_remappable(id):
			(_rows[id].pad as Button).text = Bindings.pad_text(id)
		else:
			(_rows[id].pad as Button).text = Bindings.pad_text(id)


func _start(action: String, kind: String) -> void:
	_listen = {"action": action, "kind": kind}
	var b: Button = _rows[action][kind]
	b.text = "Appuie…"
	_info.text = "En attente d'une %s pour « %s » (Échap : annuler)." % ["touche" if kind == "key" else "touche de manette", _label(action)]


func _label(action: String) -> String:
	for a in Bindings.ACTIONS:
		if a[0] == action:
			return a[1]
	return action


func _close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if _listen.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close()
		return
	var action: String = _listen.action
	if _listen.kind == "key" and event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_ESCAPE:
			_info.text = "Annulé."
		elif not Bindings.key_allowed(ke):
			_info.text = "Les combinaisons avec Cmd, Ctrl ou Alt sont réservées au système : choisis une touche seule."
		else:
			var swapped := Bindings.set_key(action, int(ke.physical_keycode))
			_info.text = "« %s » : %s%s." % [_label(action), Bindings.key_text(Bindings.key_of(action)),
				" (échangée avec « %s »)" % _label(swapped) if swapped != "" else ""]
		_listen = {}
		refresh()
	elif _listen.kind == "pad" and event is InputEventJoypadButton and event.pressed:
		get_viewport().set_input_as_handled()
		var swapped2 := Bindings.set_pad(action, int((event as InputEventJoypadButton).button_index))
		_info.text = "« %s » : %s%s." % [_label(action), Bindings.pad_text(action),
			" (échangé avec « %s »)" % _label(swapped2) if swapped2 != "" else ""]
		_listen = {}
		refresh()
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_listen = {}
		_info.text = "Annulé."
		refresh()
