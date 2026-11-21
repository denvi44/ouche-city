class_name DialoguePlayer
extends Node
## Lecteur de dialogues (agent 07 / 05) : charge les fichiers `res://assets/dialogues/*.yarn`, joue les nœuds ligne à ligne
## (sans jamais bloquer le jeu : « aboiements » et scènes dites par-dessus l'action) et prévient les bulles et le HUD.
## Même code sur tous les pairs : le serveur décide quand (`MissionBase.say`), chacun lit son exemplaire des fichiers.

signal line_started(speaker: String, text: String, id: String, seconds: float, tags: Dictionary)
signal node_finished(node_id: String)

const DIR := "res://assets/dialogues"
const MAX_QUEUE := 4
const GAP := 0.35

var nodes := {}                      ## nœud -> {lines, jump}
var queue: Array = []                ## nœuds en attente
var current_node := ""
var current_line := {}
var said_ids: Array[String] = []     ## identifiants des répliques déjà dites (tests, journal)
var played_nodes: Array[String] = []
var _idx := 0
var _timer := 0.0
var _jumps := 0


func _ready() -> void:
	name = "Dialogues"
	load_all()


## Lit tous les .yarn du dossier ; renvoie le nombre de nœuds.
func load_all(dir := DIR) -> int:
	nodes.clear()
	var d := DirAccess.open(dir)
	if d == null:
		return 0
	for f in d.get_files():
		if f.ends_with(".yarn"):
			var file := FileAccess.open(dir.path_join(f), FileAccess.READ)
			if file:
				nodes.merge(YarnLite.parse(file.get_as_text()), true)
	return nodes.size()


func has_node_id(id: String) -> bool:
	return nodes.has(id)


func is_busy() -> bool:
	return current_node != ""


## Joue un nœud (mis en file si un autre est en cours). Les nœuds inconnus sont ignorés. `urgent` passe devant.
func play(id: String, urgent := false) -> bool:
	if not nodes.has(id):
		return false
	if current_node == "":
		_start(id)
		return true
	if queue.size() >= MAX_QUEUE:
		return false
	if urgent:
		queue.push_front(id)
	else:
		queue.append(id)
	return true


func skip() -> void:
	queue.clear()
	if current_node != "":
		var n := current_node
		current_node = ""
		current_line = {}
		node_finished.emit(n)


func _start(id: String) -> void:
	current_node = id
	played_nodes.append(id)
	_idx = 0
	_jumps = 0
	_next_line()


func _next_line() -> void:
	var node: Dictionary = nodes.get(current_node, {})
	var lines: Array = node.get("lines", [])
	if _idx >= lines.size():
		var jump: String = node.get("jump", "")
		if jump != "" and nodes.has(jump) and _jumps < 8:
			_jumps += 1
			current_node = jump
			played_nodes.append(jump)
			_idx = 0
			_next_line()
			return
		var done := current_node
		current_node = ""
		current_line = {}
		node_finished.emit(done)
		if not queue.is_empty():
			_start(queue.pop_front())
		return
	current_line = lines[_idx]
	_idx += 1
	_timer = YarnLite.duration_of(current_line) + GAP
	if current_line.id != "":
		said_ids.append(current_line.id)
	line_started.emit(current_line.speaker, current_line.text, current_line.id, _timer - GAP, current_line.tags)


func _process(delta: float) -> void:
	if current_node == "":
		return
	_timer -= delta
	if _timer <= 0.0:
		_next_line()
