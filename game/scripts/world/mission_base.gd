class_name MissionBase
extends Node
## Base commune des missions (agent 05) : ce que le monde, le HUD et le réseau attendent de toute mission.
## Chaque mission (m01, m02…) garde un état à autorité serveur, répliqué aux clients par `_sync`.

signal changed          ## État mis à jour (client et serveur) : le HUD se rafraîchit.

var title := ""
var step := ""
var started := false
var elapsed := 0.0
var messages: Array = []
var van: Vehicle        ## véhicule principal de la mission (camionnette, voiture)
var _players_root: Node3D


# --- Dialogues : « aboiements » et scènes dites par-dessus l'action (nœuds de narrative/dialogues/*.yarn) ---

var _said_intro := false
var _last_step_said := "?"
var _bark_cd := {}
var _skip_votes := {}


func _enter_tree() -> void:
	changed.connect(_dialogue_hook)


## Identifiant court de la mission (m01…m06) : préfixe des nœuds de dialogue.
func dialogue_prefix() -> String:
	return str(get("mission_id")).substr(0, 3)


func dialogues() -> DialoguePlayer:
	var w := get_parent()
	return w.get_node_or_null("Dialogues") as DialoguePlayer if w else null


## Serveur : joue le nœud chez tout le monde (les nœuds inconnus sont ignorés).
func say(node: String, urgent := false) -> void:
	if not is_server():
		return
	var d := dialogues()
	if d == null or not d.has_node_id(node):
		return
	d.play(node, urgent)
	for id in Net.ready_peers():
		if id != multiplayer.get_unique_id():
			_say.rpc_id(id, node, urgent)


## Réplique d'ambiance sur un événement : au plus une fois par `cooldown` secondes et par nœud.
func bark(node: String, cooldown := 20.0) -> void:
	if not is_server():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_bark_cd.get(node, -1000.0)) < cooldown:
		return
	_bark_cd[node] = now
	say(node)


@rpc("authority", "call_remote", "reliable")
func _say(node: String, urgent: bool) -> void:
	var d := dialogues()
	if d:
		d.play(node, urgent)


## Vote pour passer la scène en cours (« majority_vote » du JSON) : la majorité des humains suffit.
func request_skip() -> void:
	if is_server():
		_skip_vote(multiplayer.get_unique_id())
	else:
		_request_skip.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_skip() -> void:
	if is_server():
		_skip_vote(multiplayer.get_remote_sender_id())


func _skip_vote(peer: int) -> void:
	_skip_votes[peer] = true
	var humans := 0
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai:
				humans += 1
	if _skip_votes.size() * 2 > maxi(humans, 1):
		_skip_votes.clear()
		var d := dialogues()
		if d:
			d.skip()
		for id in Net.ready_peers():
			if id != multiplayer.get_unique_id():
				_skip_dialogue.rpc_id(id)


@rpc("authority", "call_remote", "reliable")
func _skip_dialogue() -> void:
	var d := dialogues()
	if d:
		d.skip()


func _dialogue_hook() -> void:
	if not is_server() or not started:
		return
	var prefix := dialogue_prefix()
	if not _said_intro:
		_said_intro = true
		say(prefix + "_intro")
	if step != _last_step_said:
		_last_step_said = step
		say("%s_%s" % [prefix, step])
		# Variantes selon l'issue : m02_done_win, m06_failed_evicted…
		var res = get("result")
		if res != null and str(res) != "" and step in ["done", "failed"]:
			say("%s_%s_%s" % [prefix, step, str(res)])


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func actor(id: int) -> Node3D:
	return _players_root.get_node_or_null(str(id)) as Node3D if _players_root else null


## Compagnons IA présents dans le monde (joueurs d'identifiant négatif).
func companions() -> Array:
	var out := []
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and (p as Player).is_ai:
				out.append(p)
	return out


static func format_time(seconds: float) -> String:
	var s := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [s / 60, s % 60]


## Pose les lieux et accessoires d'après les POI du cartographe (appelé par le monde).
func setup(_pois: Array, _ground: Callable, _vehicle: Vehicle, _players: Node3D) -> void:
	pass


## Que se passerait-il si ce joueur appuyait sur « interagir » ? ({} = rien)
func resolve(_peer: int, _pos: Vector3) -> Dictionary:
	return {}


func interact(_peer: int, _allowed: Array = []) -> void:
	pass


func request_interact() -> void:
	pass


func request_choice(_option: String) -> void:
	pass


func request_horn() -> void:
	pass


func request_boost() -> void:
	pass


func objective() -> String:
	return ""


## Lignes du panneau de mission (HUD).
func hud_lines() -> PackedStringArray:
	return PackedStringArray([title, objective()])


## Texte final (médaille, échec) affiché au centre de l'écran.
func result_text() -> String:
	return ""


## Rôles tenus par les compagnons IA en solo : identifiant négatif -> rôle.
func companion_roles() -> Dictionary:
	return {}


## Ce que fait un compagnon, déduit de l'état public (valable sur tous les pairs).
func companion_status(_c: Player) -> String:
	return "attend"


func on_player_left(_peer: int) -> void:
	pass


func send_full_state(_peer: int) -> void:
	pass


## Où regardent les compagnons à leur poste (Vector3.ZERO : nulle part en particulier).
func look_target() -> Vector3:
	return Vector3.ZERO


## Point d'attente d'un compagnon (HUD, IA) ; Vector3.ZERO si inconnu.
func spot(_name: String) -> Vector3:
	return Vector3.ZERO
