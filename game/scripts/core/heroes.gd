class_name Heroes
extends RefCounted
## Héros jouable de chaque mission : le joueur n'est pas toujours le même personnage (champ `hero` de missions/*.json, contrat v2).
## Le héros prend la tenue et le nom du personnage ; son compagnon IA disparaît (c'est lui). Absent en headless (serveur dédié, tests)
## sauf `Heroes.force`, pour ne pas changer les compagnons dont dépendent les tests.

const IDS := {"gege": -1, "ginette": -2, "kevin_radio": -3, "kevin": -4, "odette": -5}
const NAMES := {-1: "Tonton Gégé", -2: "Ginette", -3: "Kévin Radio", -4: "Kévin", -5: "Mémé Odette"}
const MISSIONS_DIR := "res://assets/missions/"

static var force := false


static func enabled() -> bool:
	return force or DisplayServer.get_name() != "headless"


## Identifiant (négatif) du héros de la mission `key` (« m01 »…), 0 s'il n'y en a pas ou si les héros sont désactivés.
static func hero_of(key: String) -> int:
	if not enabled():
		return 0
	return raw_hero_of(key)


static func raw_hero_of(key: String) -> int:
	var dir := DirAccess.open(MISSIONS_DIR)
	if dir == null:
		return 0
	for f in dir.get_files():
		if f.begins_with(key + "_") and f.ends_with(".json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string(MISSIONS_DIR + f))
			if d is Dictionary:
				return int(IDS.get(str(d.get("hero", "")), 0))
	return 0


static func name_of(id: int) -> String:
	return str(NAMES.get(id, ""))
