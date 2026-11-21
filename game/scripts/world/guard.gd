class_name Guard
extends ScriptedBody
## Gardien de la casse automobile (mission 02, étape « stealth_search ») : il fait les cent pas
## entre deux points, s'arrête un instant à chaque bout, et voit dans un cône devant lui.

const WALK := 1.1
const PAUSE := 3.0
const SIGHT_RANGE := 11.0
const SIGHT_HALF_ANGLE := deg_to_rad(65.0)

var a := Vector2.ZERO               # bouts de la ronde (x, z)
var b := Vector2.ZERO
var _to_b := true
var _wait := 0.0
var alert_left := 0.0               # s pendant lesquelles il court vers l'intrus (alerte)


func _ready() -> void:
	radius = 0.4
	shape_node = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape_node.shape = capsule
	shape_node.position.y = 0.9
	add_child(shape_node)
	super._ready()


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visuel"
	add_child(visual)
	var m := CharacterModel.make(Color(0.3, 0.38, 0.55), Color(0.2, 0.24, 0.38), Color(0.2, 0.26, 0.45), {"headgear": "kepi", "hair": Color(0.2, 0.15, 0.1), "moustache": Color(0.22, 0.16, 0.1), "belt": Color(0.95, 0.95, 0.95), "scarf": Color(0.9, 0.9, 0.92), "shoes": Color(0.08, 0.08, 0.1)})
	visual.add_child(m)
	var label := Label3D.new()
	label.text = "Gardien"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.5
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 10
	add_child(label)


func script_input(delta: float) -> Dictionary:
	alert_left = maxf(alert_left - delta, 0.0)
	if _wait > 0.0:
		_wait -= delta
		return {"speed": 0.0, "yaw": yaw}
	var here := Vector2(global_position.x, global_position.z)
	var target := b if _to_b else a
	if here.distance_to(target) < 0.9:
		_to_b = not _to_b
		_wait = PAUSE
		return {"speed": 0.0, "yaw": yaw}
	var d := target - here
	return {"speed": WALK, "yaw": atan2(-d.x, -d.y)}


## Voit-il ce point ? Distance, cône de vision et ligne dégagée (lancer de rayon contre les murs).
func can_see(pos: Vector3) -> bool:
	var to := pos - global_position
	to.y = 0.0
	if to.length() > SIGHT_RANGE or to.length() < 0.01:
		return to.length() < 0.01
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	if forward.angle_to(to.normalized()) > SIGHT_HALF_ANGLE:
		return false
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.6, 0), pos + Vector3(0, 1.2, 0))
	q.exclude = [get_rid()]
	for _i in 3:
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			return true
		if hit.collider is StaticBody3D:
			return false
		q.exclude.append(hit.collider.get_rid())
	return true
