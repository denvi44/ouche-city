extends Node
## Couche réseau d'Ouche City (agent 12) — autoload « Net ».
##
## Un seul code pour tous les modes :
## - solo : le client héberge un serveur ENet local (même build), fermé aux autres
##   jusqu'à « Ouvrir aux amis » ;
## - hôte : serveur local ouvert ;
## - client : connexion à un hôte ou à un serveur dédié ;
## - dédié : `godot --headless -- --server` (aucun joueur local).
## Le serveur est autoritaire : progression, argent, score et positions sont décidés par lui.

signal joined                       ## Le client est accepté par le serveur.
signal refused(reason: String)      ## Le serveur a refusé la connexion.
signal connection_failed
signal server_lost
signal roster_changed               ## Liste des joueurs modifiée (côté serveur et clients).

## Version du protocole : client et serveur refusent poliment une version différente.
const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 24680
const MAX_PLAYERS := 16

enum Mode { NONE, SOLO, HOST, CLIENT, DEDICATED }

var mode: Mode = Mode.NONE
var port: int = DEFAULT_PORT
## Solo : partie fermée tant que le joueur ne l'ouvre pas.
var open_to_others := false
## Pilotage automatique du joueur local (bots de playtest QA).
var bot := false
## peer_id -> { "name": String, "os": String, "ready": bool }
var players: Dictionary = {}

var _args: Dictionary = {}


func _ready() -> void:
	_args = parse_args(OS.get_cmdline_user_args())
	port = int(OS.get_environment("OUCHE_PORT")) if OS.get_environment("OUCHE_PORT") != "" else DEFAULT_PORT
	if _args.has("port"):
		port = int(_args["port"])
	bot = _args.has("bot")
	if _args.has("name"):
		Settings.player_name = str(_args["name"])
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): connection_failed.emit())
	multiplayer.server_disconnected.connect(_on_server_disconnected)


## Analyse des arguments utilisateur (après `--`) : `--cle=valeur` ou `--drapeau`.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out


func arg(key: String, default = null):
	return _args.get(key, default)


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func has_local_player() -> bool:
	return mode in [Mode.SOLO, Mode.HOST, Mode.CLIENT]


## Pause autorisée seulement en solo sans invité.
func can_pause() -> bool:
	return mode == Mode.SOLO and players.size() <= 1


# --- Démarrage -----------------------------------------------------------------

func host_solo() -> Error:
	open_to_others = false
	return _start_server(Mode.SOLO, MAX_PLAYERS - 1, true)


func host_game() -> Error:
	open_to_others = true
	return _start_server(Mode.HOST, MAX_PLAYERS - 1, true)


func start_dedicated() -> Error:
	open_to_others = true
	var max_players := int(OS.get_environment("OUCHE_MAX_PLAYERS")) if OS.get_environment("OUCHE_MAX_PLAYERS") != "" else MAX_PLAYERS
	return _start_server(Mode.DEDICATED, clampi(max_players, 1, MAX_PLAYERS), false)


func open_to_friends() -> void:
	if mode == Mode.SOLO:
		open_to_others = true
		mode = Mode.HOST
		print("[net] partie ouverte aux amis sur le port %d" % port)


func join(address: String, join_port: int = -1) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var p := join_port if join_port > 0 else port
	var err := peer.create_client(address, p)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	print("[net] connexion à %s:%d" % [address, p])
	return OK


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	mode = Mode.NONE


func _start_server(new_mode: Mode, max_clients: int, local_player: bool) -> Error:
	var host := OS.get_environment("OUCHE_HOST")
	var err := ERR_CANT_CREATE
	var peer: ENetMultiplayerPeer
	# En solo, si le port est pris (deux instances), on essaie les suivants.
	for attempt in range(10 if new_mode == Mode.SOLO else 1):
		peer = ENetMultiplayerPeer.new()
		if host != "":
			peer.set_bind_ip(host)
		err = peer.create_server(port + attempt, max_clients)
		if err == OK:
			port += attempt
			break
	if err != OK:
		push_error("[net] impossible d'ouvrir le serveur sur le port %d (%s)" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	mode = new_mode
	players.clear()
	if local_player:
		players[1] = {"name": Settings.player_name, "os": OS.get_name(), "ready": false}
	print("[net] serveur %s, port %d, protocole v%d" % [Mode.keys()[new_mode], port, PROTOCOL_VERSION])
	roster_changed.emit()
	return OK


# --- Poignée de main -------------------------------------------------------------

func _on_connected_to_server() -> void:
	_hello.rpc_id(1, PROTOCOL_VERSION, Settings.player_name, OS.get_name())


@rpc("any_peer", "call_remote", "reliable")
func _hello(version: int, player_name: String, os_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := check_admission(version, players.size(), open_to_others)
	if reason != "":
		_refuse.rpc_id(id, reason)
		# Laisse le temps au message d'arriver avant de couper.
		get_tree().create_timer(0.5).timeout.connect(func(): _kick(id))
		return
	players[id] = {"name": player_name.left(24).strip_edges(), "os": os_name, "ready": false}
	print("[net] joueur %d accepté (%s, %s)" % [id, players[id].name, os_name])
	_welcome.rpc_id(id, {"protocol": PROTOCOL_VERSION, "mode": Mode.keys()[mode]})
	roster_changed.emit()


## Décision d'admission, pure (testée par qa/unit).
static func check_admission(version: int, current_players: int, is_open: bool) -> String:
	if version != PROTOCOL_VERSION:
		return "Version différente (serveur v%d, vous v%d). Mettez le jeu à jour, ça vaut le coup." % [PROTOCOL_VERSION, version]
	if not is_open:
		return "Cette partie solo n'est pas ouverte aux amis."
	if current_players >= MAX_PLAYERS:
		return "La partie est pleine (16 joueurs). Même la foire de la Saint-Michel n'en demande pas tant."
	return ""


func _kick(id: int) -> void:
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer and id in multiplayer.get_peers():
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)


@rpc("authority", "call_remote", "reliable")
func _refuse(reason: String) -> void:
	print("[net] refusé : ", reason)
	refused.emit(reason)
	leave()


@rpc("authority", "call_remote", "reliable")
func _welcome(_info: Dictionary) -> void:
	print("[net] accepté par le serveur")
	joined.emit()


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		print("[net] pair %d connecté, en attente de poignée de main" % id)


func _on_peer_disconnected(id: int) -> void:
	if players.erase(id):
		print("[net] joueur %d parti" % id)
		roster_changed.emit()


func _on_server_disconnected() -> void:
	players.clear()
	mode = Mode.NONE
	server_lost.emit()


## Pairs prêts (monde chargé) : seuls destinataires des RPC du monde.
func ready_peers() -> Array[int]:
	var out: Array[int] = []
	for id in players:
		if players[id].ready and id != multiplayer.get_unique_id():
			out.append(id)
	return out
