extends RefCounted
## Choix des touches (agent 11, accessibilité : remappage) : clavier (touche physique, donc ZQSD sur AZERTY) et manette
## (boutons). Sauvegardé dans user://touches.cfg et réappliqué au démarrage. Les sticks (déplacement, caméra) restent fixes.
## Aucun raccourci système n'est utilisable : les combinaisons avec Cmd / Ctrl / Alt sont refusées.

const DEFAULT_PATH := "user://touches.cfg"
static var path := DEFAULT_PATH

## Actions remappables : [identifiant, libellé, bouton de manette remappable ?].
const ACTIONS := [
	["move_forward", "Avancer", false], ["move_back", "Reculer", false], ["move_left", "Aller à gauche", false],
	["move_right", "Aller à droite", false], ["jump", "Sauter", true], ["sprint", "Courir", true],
	["interact", "Interagir / ramasser", true], ["horn", "Klaxon", true], ["radio_toggle", "Radio : marche / arrêt", true], ["map_toggle", "Grande carte", true],
	["beat_left", "Rythme : flèche gauche", false], ["beat_down", "Rythme : flèche bas", false], ["beat_up", "Rythme : flèche haut", false], ["beat_right", "Rythme : flèche droite", false],
	["dialogue_skip", "Passer le dialogue", true], ["pause", "Pause / menu", true],
	["choose_1", "Choix 1", true], ["choose_2", "Choix 2", true], ["choose_3", "Choix 3", true],
]
const PAD_NAMES := {0: "A / Croix", 1: "B / Rond", 2: "X / Carré", 3: "Y / Triangle", 4: "Retour / Select", 6: "Start / Menu",
	7: "Clic stick gauche", 8: "Clic stick droit", 9: "LB / L1", 10: "RB / R1", 11: "Croix haut", 12: "Croix bas", 13: "Croix gauche", 14: "Croix droite"}


static func ids() -> Array:
	var out := []
	for a in ACTIONS:
		out.append(a[0])
	return out


static func pad_remappable(action: String) -> bool:
	for a in ACTIONS:
		if a[0] == action:
			return a[2]
	return false


## Touche physique (code Godot) de la première touche clavier de l'action ; 0 si aucune.
static func key_of(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			return int((e as InputEventKey).physical_keycode)
	return 0


## Bouton de manette de l'action ; -1 si aucun (ou commande analogique).
static func pad_of(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			return int((e as InputEventJoypadButton).button_index)
	return -1


## Texte de la touche selon la disposition du clavier (AZERTY : Z, pas W).
static func key_text(phys: int) -> String:
	if phys == 0:
		return "—"
	var kc: int = DisplayServer.keyboard_get_keycode_from_physical(phys) if DisplayServer.get_name() != "headless" else 0
	return OS.get_keycode_string(kc if kc != 0 else phys)


static func pad_text(action: String) -> String:
	var b := pad_of(action)
	if b >= 0:
		return PAD_NAMES.get(b, "Bouton %d" % b)
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion:
			var axis: int = (e as InputEventJoypadMotion).axis
			return "Stick gauche" if axis < 2 else "Stick droit"
	return "—"


## Une touche est refusée si elle porte un modificateur système (Cmd, Ctrl, Alt) ou n'est pas une vraie touche.
static func key_allowed(ev: InputEventKey) -> bool:
	if ev.meta_pressed or ev.ctrl_pressed or ev.alt_pressed:
		return false
	return int(ev.physical_keycode) != 0


static func _replace_key(action: String, phys: int) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			InputMap.action_erase_event(action, e)
	if phys != 0:
		var ev := InputEventKey.new()
		ev.physical_keycode = phys as Key
		InputMap.action_add_event(action, ev)


static func _replace_pad(action: String, button: int) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			InputMap.action_erase_event(action, e)
	if button >= 0:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button as JoyButton
		InputMap.action_add_event(action, ev)


## Affecte une touche à une action. Si une autre action l'utilisait, les deux échangent leurs touches.
## Renvoie l'action échangée (« » si aucune).
static func set_key(action: String, phys: int) -> String:
	var old := key_of(action)
	var swapped := ""
	for other in ids():
		if other != action and key_of(other) == phys:
			_replace_key(other, old)
			swapped = other
	_replace_key(action, phys)
	save()
	return swapped


static func set_pad(action: String, button: int) -> String:
	var old := pad_of(action)
	var swapped := ""
	for other in ids():
		if other != action and pad_remappable(other) and pad_of(other) == button:
			_replace_pad(other, old)
			swapped = other
	_replace_pad(action, button)
	save()
	return swapped


static func save() -> void:
	var cfg := ConfigFile.new()
	for a in ACTIONS:
		cfg.set_value("clavier", a[0], key_of(a[0]))
		if a[2]:
			cfg.set_value("manette", a[0], pad_of(a[0]))
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	cfg.save(path)


## Réapplique les touches enregistrées (appelé au démarrage par Settings).
static func apply_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for a in ACTIONS:
		var id: String = a[0]
		if not InputMap.has_action(id):
			continue
		if cfg.has_section_key("clavier", id):
			_replace_key(id, int(cfg.get_value("clavier", id, 0)))
		if a[2] and cfg.has_section_key("manette", id):
			_replace_pad(id, int(cfg.get_value("manette", id, -1)))


## Touches d'origine (celles du projet) ; efface la sauvegarde.
static func reset_all() -> void:
	InputMap.load_from_project_settings()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
