class_name CinematicDirector
extends Node
## Metteur en scène (agent 08) : joue l'introduction de la mission au démarrage et la scène de fin (réussite ou échec) quand
## l'étape passe à « done » / « failed » ; après une réussite, la scène de liaison vers la mission suivante (bridge) ou l'épilogue. Chaque joueur voit ses propres scènes, une seule fois par partie. Inactif en headless
## (tests, serveur dédié) et si le joueur a désactivé les cinématiques.

var world: Node3D
var _played := {}
var _last_step := ""
var _busy := false
var _queue: Array = []


func _ready() -> void:
	world = get_parent() as Node3D
	if DisplayServer.get_name() == "headless" or not Settings.cinematics or world == null:
		return
	var mission = world.get("mission")
	if mission == null:
		return
	_last_step = str(mission.step)
	mission.changed.connect(_on_changed)
	_intro.call_deferred()


func _anchors() -> Dictionary:
	var poi: Variant = CityBuilder.read_json("res://assets/city/poi.json")
	return CinematicPlayer.anchors_from_pois((poi as Dictionary).get("pois", []) if poi is Dictionary else [], world.builder.height_at)


func _intro() -> void:
	# On attend que le joueur local soit là, puis un instant pour que la ville soit affichée.
	for i in 900:
		if Net.has_local_player() and world.players_root.get_node_or_null(str(multiplayer.get_unique_id())) != null:
			break
		await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout
	var mission = world.get("mission")
	if mission != null and float(mission.get("elapsed") if mission.get("elapsed") != null else 0.0) > 45.0:
		return        # partie en cours rejointe plus tard : pas d'introduction
	play(str(world.mission_key) + "_intro")


func _on_changed() -> void:
	var mission = world.get("mission")
	var s := str(mission.step)
	if s == _last_step:
		return
	_last_step = s
	if s == "done" or s == "failed":
		await get_tree().create_timer(0.9).timeout
		play("%s_%s" % [world.mission_key, s])
		if s == "done":
			# L'histoire continue : « à suivre » vers la mission suivante (missions 1 à 7) ou épilogue (mission 8).
			play("%s_bridge" % world.mission_key)
			play("%s_epilogue" % world.mission_key)


func play(id: String) -> void:
	if _played.has(id):
		return
	_played[id] = true
	_queue.append(id)
	if _busy:
		return
	_busy = true
	while not _queue.is_empty():
		var cid: String = _queue.pop_front()
		var d := CinematicPlayer.load_def(cid)
		if d.is_empty():
			continue
		var p := CinematicPlayer.new()
		world.add_child(p)
		p.start(d, _anchors())
		await p.finished
	_busy = false
