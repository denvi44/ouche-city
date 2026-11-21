extends Node
## Progression du joueur en solo (agent 12) — autoload « Progress ».
## Sauvegarde locale conforme à contracts/save.schema.json, écrite uniquement par le serveur local :
## argent, état et médaille de chaque mission, réputation, déblocages, véhicules.
## Le client ne décide jamais de ces valeurs. En mode headless (tests, serveur dédié) rien n'est
## écrit sur disque sauf si `--save=CHEMIN` est donné.

signal changed

const DEFAULT_PATH := "user://saves/solo.json"
const SCHEMA_VERSION := 1

var path := DEFAULT_PATH
var persist := true
var data := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--save="):
			path = a.substr(7)
			persist = true
	if DisplayServer.get_name() == "headless" and path == DEFAULT_PATH:
		persist = false
	load_save()


static func fresh() -> Dictionary:
	return {"schemaVersion": SCHEMA_VERSION, "playerId": "solo", "displayName": "Normand",
		"updatedAt": Time.get_datetime_string_from_system(true) + "Z", "protocolVersion": 1,
		"money": 0, "missions": {}, "reputation": {}, "unlocks": [], "vehicles": [], "position": [0.0, 0.0, 0.0]}


## Une sauvegarde lue est acceptée si elle a les clés obligatoires du contrat.
static func is_valid(d) -> bool:
	if not (d is Dictionary):
		return false
	for k in ["schemaVersion", "playerId", "updatedAt", "money", "missions", "reputation", "position"]:
		if not d.has(k):
			return false
	return int(d.schemaVersion) == SCHEMA_VERSION and d.missions is Dictionary and d.position is Array and d.position.size() == 3


func load_save() -> void:
	data = fresh()
	if not persist or not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if is_valid(parsed):
		data = parsed
		data.money = int(data.money)
	else:
		push_warning("[progress] sauvegarde illisible, nouvelle partie : %s" % path)


func save() -> void:
	data.updatedAt = Time.get_datetime_string_from_system(true) + "Z"
	data.displayName = Settings.player_name
	changed.emit()
	if not persist:
		return
	var dir := path.get_base_dir()
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  ") + "\n")


func reset() -> void:
	data = fresh()
	save()


func money() -> int:
	return int(data.money)


func add_money(n: int) -> void:
	data.money = maxi(int(data.money) + n, 0)


func mission_state(id: String) -> String:
	return data.missions.get(id, {}).get("state", "locked")


func medal_of(id: String) -> String:
	var m = data.missions.get(id, {}).get("medal", null)
	return m if m != null else ""


func is_done(id: String) -> bool:
	return mission_state(id) == "done"


## Disponible si déjà débloquée, ou si toutes les missions requises sont terminées.
func is_available(id: String, requires: Array = []) -> bool:
	if mission_state(id) in ["available", "in_progress", "done"] or id in data.unlocks:
		return true
	for r in requires:
		if not is_done(r):
			return false
	return true


func start(id: String) -> void:
	if mission_state(id) != "done":
		data.missions[id] = {"state": "in_progress", "medal": null, "checkpoint": null}


## Fin d'une mission réussie : médaille, récompenses, déblocages. L'argent est ajouté par l'appelant.
func complete(id: String, medal: String, reputation: Dictionary = {}, unlocks: Array = [], vehicles: Array = []) -> void:
	var prev: String = medal_of(id)
	var order := ["", "bronze", "silver", "gold"]
	var best := medal if order.find(medal) >= order.find(prev) else prev      # on garde la meilleure médaille
	data.missions[id] = {"state": "done", "medal": best if best != "" else null, "checkpoint": null}
	for k in reputation:
		data.reputation[k] = int(data.reputation.get(k, 0)) + int(reputation[k])
	for u in unlocks:
		if not (u in data.unlocks):
			data.unlocks.append(u)
		if u.begins_with("m") and not data.missions.has(u):
			data.missions[u] = {"state": "available", "medal": null, "checkpoint": null}
	for v in vehicles:
		if not (v in data.vehicles):
			data.vehicles.append(v)
	save()
