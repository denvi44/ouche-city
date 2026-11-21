extends SceneTree
## Écran titre et sauvegarde : le menu se construit, « Continuer » vise la bonne mission, la sauvegarde fait l'aller-retour
## disque (écriture, relecture), une sauvegarde corrompue est refusée sans planter, « Nouvelle partie » efface tout.
## Usage : godot --headless --path game -s ../qa/integration/menu_save_audit.gd -- --save=/tmp/frouch_menu_test.json
var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func check(cond: bool, label: String) -> bool:
	if cond:
		print("  ok  ", label)
	else:
		fails += 1
		printerr("ÉCHEC ", label)
	return cond


func _run() -> void:
	var prog = root.get_node("Progress")
	var Menu = load("res://ui/main_menu.gd")
	prog.reset()
	check(Menu.next_mission_key() == "m01", "sans sauvegarde : on commence à la mission 1")
	prog.complete("m01_calva_gege", "silver", {}, ["m02_tuning_samedi"])
	prog.add_money(150)
	prog.save()
	check(Menu.next_mission_key() == "m02", "après la mission 1 : « Continuer » mène à la mission 2")
	for id in ["m02_tuning_samedi", "m03_battle_sono", "m04_mechoui_saint_jean", "m05_vaches_en_goguette", "m06_courses_de_8h"]:
		prog.complete(id, "gold")
	check(Menu.next_mission_key() == "m07", "après la mission 6 : mission 7")
	prog.complete("m07_jus_de_pomme", "bronze")
	check(Menu.next_mission_key() == "m08", "après la mission 7 : mission 8")
	prog.complete("m08_oies_en_greve", "silver")
	check(Menu.next_mission_key() == "m08", "tout terminé : on peut rejouer la dernière")
	# Aller-retour disque
	var money: int = prog.money()
	prog.load_save()
	check(prog.money() == money and prog.is_done("m03_battle_sono") and prog.medal_of("m01_calva_gege") == "silver", "relecture : argent, missions et médailles conservés")
	# Meilleure médaille conservée
	prog.complete("m01_calva_gege", "bronze")
	check(prog.medal_of("m01_calva_gege") == "silver", "une médaille moins bonne n'écrase pas la meilleure")
	# Menu : instanciation sans erreur
	var menu = Menu.new()
	root.add_child(menu)
	await process_frame
	var buttons := 0
	var stack: Array = [menu]
	var texts: Array = []
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button:
			buttons += 1
			texts.append((n as Button).text)
		stack.append_array(n.get_children())
	check(buttons >= 10, "le menu construit ses boutons (%d)" % buttons)
	check(texts.any(func(t): return t.begins_with("Continuer")), "bouton « Continuer »")
	check(texts.any(func(t): return t.begins_with("Nouvelle partie (efface")), "bouton « Nouvelle partie » avec confirmation")
	check(Menu.SOLO_MISSIONS.size() == Menu.CHAIN.size(), "menu : une entrée de mission par maillon de la chaîne")
	var mth: Theme = load("res://ui/theme_util.gd").make_material_theme()
	check(mth.has_stylebox("panel", "Card") and mth.has_stylebox("normal", "FilledButton") and mth.has_stylebox("focus", "TonalButton") and mth.has_stylebox("panel", "Chip"), "thème Material : carte, puce, boutons plein et tonal avec focus")
	check(texts.any(func(t): return str(t).begins_with("Jouer en solo (mission 1")), "menu : la mission 1 est toujours proposée")
	# Sauvegarde corrompue
	if prog.persist:
		var f := FileAccess.open(prog.path, FileAccess.WRITE)
		f.store_string("{pas du json")
		f.close()
		prog.load_save()
		check(prog.money() == 0 and not prog.is_done("m01_calva_gege"), "sauvegarde corrompue : nouvelle partie, pas de plantage")
	prog.reset()
	check(prog.money() == 0 and Menu.next_mission_key() == "m01", "nouvelle partie : tout est effacé")
	print("--- menu_save_audit : ", "OK" if fails == 0 else "%d échec(s)" % fails)
	quit(1 if fails > 0 else 0)
