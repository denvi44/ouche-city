class_name NetBody
extends CharacterBody3D
## Corps répliqué à autorité serveur, avec prédiction du pilote (agent 12).
##
## Un corps a au plus un **contrôleur** (`controller`, identifiant de pair ; 0 = personne).
## - Le serveur simule tous les corps. Pour un corps piloté à distance, il rejoue les entrées
##   numérotées du pilote ; sans pilote, il simule une entrée neutre.
## - Le pilote prédit avec le même code (`simulate`), envoie ses entrées (60 Hz, non fiables
##   ordonnées), puis se réconcilie sur l'état serveur (20 Hz) en rejouant les entrées non acquittées.
## - Les autres clients interpolent 100 ms dans le passé.
## Le contrôleur peut changer en cours de partie (monter / descendre d'un véhicule) : toute la
## file de prédiction est alors remise à zéro des deux côtés.

const STATE_EVERY_TICKS := 3          # 20 Hz
const INTERP_DELAY_MS := 100
const MAX_PENDING := 120
const MAX_QUEUE := 30

var controller := 0
## Dernier orientation répliquée (lacet en radians).
var visual: Node3D

var _seq := 0
var _ack := 0
var _pending: Array[Dictionary] = []
var _server_queue: Array[Dictionary] = []
var _last_received_seq := 0
var _snapshots: Array = []
var _tick := 0
var _last_controller := -1


# --- À surcharger ----------------------------------------------------------------

## Pas de simulation déterministe, partagé client / serveur.
func simulate(_inp: Dictionary, _delta: float) -> void:
	pass


## Entrées du pilote local pour ce pas.
func gather_input(_delta: float) -> Dictionary:
	return {}


## Entrée neutre (serveur, corps sans pilote ou sans entrée reçue).
func neutral_input() -> Dictionary:
	return {}


## Entrée simulée par le serveur pour un corps sans contrôleur (neutre, ou cerveau IA).
func server_input(_delta: float) -> Dictionary:
	return neutral_input()


func pack_input(_inp: Dictionary) -> PackedFloat32Array:
	return PackedFloat32Array()


func unpack_input(_a: PackedFloat32Array) -> Dictionary:
	return {}


func get_facing() -> float:
	return rotation.y


func set_facing(f: float) -> void:
	rotation.y = f


## Appelé quand le serveur consomme une entrée (pour mémoriser un état d'entrée).
func on_input_consumed(_inp: Dictionary) -> void:
	pass


# --- Mécanique commune -------------------------------------------------------------

func is_local_controller() -> bool:
	return multiplayer.has_multiplayer_peer() and controller != 0 and controller == multiplayer.get_unique_id()


func reset_prediction() -> void:
	_pending.clear()
	_server_queue.clear()
	_snapshots.clear()
	_last_received_seq = 0
	_ack = 0


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if controller != _last_controller:
		reset_prediction()
		_last_controller = controller
	var server := multiplayer.is_server()
	if is_local_controller():
		var inp := gather_input(delta)
		_seq += 1
		inp["seq"] = _seq
		simulate(inp, delta)
		if server:
			_ack = _seq
		else:
			_pending.append(inp)
			if _pending.size() > MAX_PENDING:
				_pending.pop_front()
			_submit_input.rpc_id(1, _seq, pack_input(inp))
	elif server:
		if controller == 0:
			simulate(server_input(delta), delta)
		elif _server_queue.is_empty():
			simulate(neutral_input(), delta)
		else:
			# Rattrapage doux si des paquets arrivent groupés.
			var n := 1 if _server_queue.size() <= 3 else 2
			for i in mini(n, _server_queue.size()):
				var inp: Dictionary = _server_queue.pop_front()
				simulate(inp, delta)
				_ack = inp.seq
				on_input_consumed(inp)
	if server:
		_tick += 1
		if _tick % STATE_EVERY_TICKS == 0 and (velocity.length_squared() > 0.0004 or _tick % 30 == 0 or controller != 0):
			for id in Net.ready_peers():
				_state.rpc_id(id, global_position, velocity, get_facing(), _ack)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _submit_input(seq: int, packed: PackedFloat32Array) -> void:
	if not multiplayer.is_server() or controller == 0 or multiplayer.get_remote_sender_id() != controller:
		return
	if seq <= _last_received_seq:
		return
	_last_received_seq = seq
	if _server_queue.size() > MAX_QUEUE:
		_server_queue.pop_front()
	var inp := unpack_input(packed)
	inp["seq"] = seq
	_server_queue.append(inp)


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(pos: Vector3, vel: Vector3, face: float, ack: int) -> void:
	if is_local_controller():
		_reconcile(pos, vel, face, ack)
	else:
		_snapshots.append([Time.get_ticks_msec(), pos, face])
		if _snapshots.size() > 20:
			_snapshots.pop_front()


func _reconcile(pos: Vector3, vel: Vector3, face: float, ack: int) -> void:
	var before := global_position
	global_position = pos
	velocity = vel
	set_facing(face)
	_pending = _pending.filter(func(i): return i.seq > ack)
	for inp in _pending:
		simulate(inp, 1.0 / Engine.physics_ticks_per_second)
	# L'écart est absorbé visuellement plutôt que téléporté.
	var err := before - global_position
	if visual and err.length() < 2.0:
		visual.position += err


func _process(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server() and not is_local_controller():
		_interpolate()
	if visual:
		visual.position = visual.position.lerp(Vector3.ZERO, clampf(12.0 * delta, 0.0, 1.0))


func _interpolate() -> void:
	if _snapshots.is_empty():
		return
	var t := Time.get_ticks_msec() - INTERP_DELAY_MS
	var last: Array = _snapshots[-1]
	if t >= last[0]:
		global_position = last[1]
		set_facing(last[2])
		return
	for i in range(_snapshots.size() - 1, 0, -1):
		var a: Array = _snapshots[i - 1]
		var b: Array = _snapshots[i]
		if t >= a[0]:
			var k := float(t - a[0]) / maxf(b[0] - a[0], 1.0)
			global_position = (a[1] as Vector3).lerp(b[1], k)
			set_facing(lerp_angle(a[2], b[2], k))
			return
