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


## Point d'attente d'un compagnon (HUD, IA) ; Vector3.ZERO si inconnu.
func spot(_name: String) -> Vector3:
	return Vector3.ZERO
