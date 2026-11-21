extends SceneTree
## Choix des touches : remappage clavier et manette, échange en cas de conflit, refus des raccourcis système, sauvegarde et
## relecture, retour aux touches d'origine, et construction de l'écran « Touches et souris ».
## Usage : godot --headless --path game -s ../qa/integration/controls_audit.gd
var fails := 0
const B := preload("res://scripts/core/input_bindings.gd")


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, label: String) -> bool:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("ÉCHEC ", label)
	return cond


func key_event(code: int, meta := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.meta_pressed = meta
	e.pressed = true
	return e


func _run() -> void:
	B.path = "/tmp/ouche_touches_test.cfg"
	B.reset_all()
	var jump0 := B.key_of("jump")
	var inter0 := B.key_of("interact")
	check(jump0 == KEY_SPACE and inter0 == KEY_E, "touches d'origine : espace et E")
	for id in B.ids():
		check(InputMap.has_action(id), "action « %s » existe" % id)
	# Remappage simple
	check(B.set_key("jump", KEY_K) == "", "sauter → K, sans conflit")
	check(B.key_of("jump") == KEY_K and InputMap.action_has_event("jump", key_event(KEY_K)), "K déclenche bien « jump »")
	check(not InputMap.action_has_event("jump", key_event(KEY_SPACE)), "l'espace ne fait plus sauter")
	# Conflit : échange
	check(B.set_key("interact", KEY_K) == "jump", "interagir → K : échange avec « jump »")
	check(B.key_of("interact") == KEY_K and B.key_of("jump") == inter0, "…sauter reprend E")
	# Les déplacements gardent le stick de la manette
	B.set_key("move_forward", KEY_UP)
	check(B.pad_text("move_forward") == "Stick gauche" and B.key_of("move_forward") == KEY_UP, "avancer : flèche haut, stick gauche conservé")
	# Manette : boutons, échange
	var pad_jump := B.pad_of("jump")
	var pad_inter := B.pad_of("interact")
	check(B.set_pad("jump", pad_inter) == "interact" and B.pad_of("interact") == pad_jump, "manette : échange des boutons")
	check(not B.pad_remappable("move_left") and B.pad_remappable("jump"), "les sticks ne se remappent pas")
	# Raccourcis système refusés
	check(not B.key_allowed(key_event(KEY_Q, true)), "Cmd+Q refusé")
	check(B.key_allowed(key_event(KEY_Q)), "Q seule acceptée")
	# Sauvegarde / relecture
	var saved_jump := B.key_of("jump")
	var saved_inter := B.key_of("interact")
	InputMap.load_from_project_settings()
	check(B.key_of("jump") == KEY_SPACE, "(simulation d'un redémarrage : touches d'usine)")
	B.apply_saved()
	check(B.key_of("jump") == saved_jump and B.key_of("interact") == saved_inter and B.key_of("move_forward") == KEY_UP, "relecture : touches personnalisées réappliquées")
	# Aucune touche attribuée deux fois
	var seen := {}
	var dup := false
	for id in B.ids():
		var k := B.key_of(id)
		if k != 0 and seen.has(k):
			dup = true
		seen[k] = id
	check(not dup, "aucune touche attribuée à deux actions")
	# Écran
	var menu = load("res://ui/controls_menu.gd").new()
	root.add_child(menu)
	await process_frame
	var buttons := 0
	var stack: Array = [menu]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			buttons += 1
		stack.append_array(n.get_children())
	check(buttons >= 2 * B.ACTIONS.size() + 2, "l'écran construit ses boutons (%d)" % buttons)
	menu.queue_free()
	# Retour aux touches d'origine
	B.reset_all()
	check(B.key_of("jump") == KEY_SPACE and B.key_of("interact") == KEY_E and not FileAccess.file_exists(B.path), "touches d'origine rétablies, sauvegarde effacée")
	print("--- controls_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
