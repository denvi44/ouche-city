class_name Cow
extends ScriptedBody
## Vache normande de la mission 01 (événement « cows »), tachetée de brun.
## Elle traverse la route en broutant du regard, s'arrête au milieu, et ne repart que
## quand elle en a envie — ou quand on klaxonne (voir `startle`).

const WALK := 0.9
const RUN := 2.6

## Traversée : axe perpendiculaire à la route, position cible au repos (m), distance de sortie (m).
var origin := Vector2.ZERO          # point de la route où se fait la traversée
var across := Vector2.RIGHT         # direction de traversée (unitaire, perpendiculaire à la route)
var rest_offset := 0.0              # où la vache s'arrête au milieu de la route (m le long de `across`)
var exit_offset := 7.0
var state := "waiting"              # waiting | to_road | grazing | leaving | gone
var graze_left := 0.0
var _off := -7.0                    # position le long de `across`
var _legs: Array[Node3D] = []
var _phase := 0.0


func _ready() -> void:
	radius = 0.9
	shape_node = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, 1.3, 1.9)
	shape_node.shape = box
	shape_node.position.y = 0.8
	add_child(shape_node)
	super._ready()


func script_input(delta: float) -> Dictionary:
	var here := Vector2(global_position.x, global_position.z)
	_off = (here - origin).dot(across)
	var heading := atan2(-across.x, -across.y)           # le nez vers la traversée
	match state:
		"to_road":
			if _off >= rest_offset:
				state = "grazing"
				graze_left = 14.0
			return {"speed": WALK, "yaw": heading}
		"grazing":
			graze_left -= delta
			if graze_left <= 0.0:
				state = "leaving"
			return {"speed": 0.0, "yaw": heading}
		"leaving":
			if _off >= exit_offset:
				state = "gone"
			return {"speed": RUN if graze_left < -1000.0 else WALK * 1.2, "yaw": heading}
	return {"speed": 0.0, "yaw": heading}


## Le klaxon les secoue : elles filent de l'autre côté.
func startle() -> void:
	if state == "grazing" or state == "to_road":
		state = "leaving"
		graze_left = -9999.0


func _process(delta: float) -> void:
	super._process(delta)
	_phase += speed_now * delta * 4.0
	var swing := sin(_phase) * 0.5 * clampf(speed_now / 1.0, 0.0, 1.0)
	for i in _legs.size():
		_legs[i].rotation.x = swing if (i == 0 or i == 3) else -swing


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visuel"
	add_child(visual)
	var tris := []
	var blanc := Color(0.95, 0.93, 0.88)
	var brun := Color(0.48, 0.3, 0.2)
	# Avant de la vache = -Z.
	_part(visual, tris, Vector3(0.85, 0.8, 1.7), Vector3(0, 1.05, 0), blanc)                 # corps
	_part(visual, tris, Vector3(0.9, 0.5, 0.7), Vector3(0, 1.15, 0.2), brun)                  # tache (flanc)
	_part(visual, tris, Vector3(0.5, 0.5, 0.6), Vector3(0, 1.3, -1.05), blanc)                # tête
	_part(visual, tris, Vector3(0.36, 0.26, 0.3), Vector3(0, 1.15, -1.4), Color(0.9, 0.7, 0.68))  # museau
	_part(visual, tris, Vector3(0.52, 0.2, 0.3), Vector3(0, 1.5, -1.0), brun)                 # tache sur l'œil
	_part(visual, tris, Vector3(0.08, 0.18, 0.08), Vector3(-0.22, 1.62, -1.0), Color(0.9, 0.85, 0.7))  # corne
	_part(visual, tris, Vector3(0.08, 0.18, 0.08), Vector3(0.22, 1.62, -1.0), Color(0.9, 0.85, 0.7))
	_part(visual, tris, Vector3(0.1, 0.5, 0.1), Vector3(0, 1.05, 0.95), brun, 0.0, Vector3(0.3, 0, 0))  # queue
	_finish_hull(visual, tris)
	for lx in [-0.28, 0.28]:
		for lz in [-0.6, 0.6]:
			var leg := Node3D.new()
			leg.position = Vector3(lx, 0.7, lz)
			visual.add_child(leg)
			var ltris := []
			_part(leg, ltris, Vector3(0.18, 0.7, 0.18), Vector3(0, -0.35, 0), blanc)
			_legs.append(leg)
