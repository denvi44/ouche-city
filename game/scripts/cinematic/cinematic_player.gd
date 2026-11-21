class_name CinematicPlayer
extends CanvasLayer
## Lecteur de cinématiques (agent 08, narration) : bandes noires, travelling de caméra entre des lieux de la carte (points
## d'intérêt de poi.json), légendes sous-titrées, carton de titre, fondu. Purement visuel et local à chaque joueur ; en solo le
## jeu est mis en pause pendant la scène (le chrono de mission ne tourne pas), en ligne le monde continue.
## Données : narrative/cinematics/*.json (contrat contracts/cinematic.schema.json). Passage : touche « passer le dialogue ».

signal finished(id: String)

## Vrai pendant qu'une cinématique est jouée : le joueur local ne bouge plus.
static var active := false

const DIR := "res://assets/cinematics/"
const BAR := 0.12                 # hauteur des bandes (part de l'écran)
const FADE := 0.7

var def := {}
var anchors := {}                 # id -> {"pos": Vector3, "facing": float}
var _cam: Camera3D
var _prev_cam: Camera3D
var _hidden: Array = []
var _markers: Array = []        # faisceaux et libellés de lieux de mission : masqués pendant la scène (les décors restent)
var _bars: Array = []
var _fade: ColorRect
var _who: Label
var _text: Label
var _title: Label
var _sub: Label
var _hint: Label
var _shot := -1
var _shot_t := 0.0
var _t := 0.0
var _total := 0.0
var _done := false
var _we_paused := false


# --- Données et géométrie (fonctions pures, testées) ----------------------------------------------------------------------------

static func load_def(id: String) -> Dictionary:
	var path := DIR + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## Points d'ancrage : tous les POI (position au sol + cap). Le repère local d'un lieu : +Z vers la rue, +X à droite, +Y en haut.
static func anchors_from_pois(pois: Array, height_at: Callable) -> Dictionary:
	var out := {}
	for p in pois:
		var x := float(p.position[0])
		var z := float(p.position[1])
		out[str(p.id)] = {"pos": Vector3(x, float(height_at.call(x, z)), z), "facing": float(p.get("facing", 0.0))}
	return out


static func resolve(ref: Dictionary, anchors: Dictionary) -> Variant:
	var a = anchors.get(str(ref.get("at", "")), null)
	if a == null:
		return null
	var off: Array = ref.get("off", [0, 0, 0])
	return (a.pos as Vector3) + Basis(Vector3.UP, float(a.facing)) * Vector3(float(off[0]), float(off[1]), float(off[2]))


static func smooth(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## État de la caméra pendant le plan `shot` à l'avancement u (0..1) ; null si un lieu est inconnu.
static func shot_state(shot: Dictionary, u: float, anchors: Dictionary) -> Variant:
	var a = resolve(shot.cam, anchors)
	var look = resolve(shot.look, anchors)
	if a == null or look == null:
		return null
	var b = resolve(shot.cam_to, anchors) if shot.has("cam_to") else a
	if b == null:
		return null
	var l2 = resolve(shot.look_to, anchors) if shot.has("look_to") else look
	if l2 == null:
		return null
	var e := smooth(u)
	return {"cam": (a as Vector3).lerp(b, e), "look": (look as Vector3).lerp(l2, e), "fov": float(shot.get("fov", 55.0))}


static func total_duration(d: Dictionary) -> float:
	var t := 0.0
	for s in d.get("shots", []):
		t += float(s.dur)
	return t


# --- Lecture ---------------------------------------------------------------------------------------------------------------------------------

func start(definition: Dictionary, anchor_map: Dictionary) -> void:
	def = definition
	anchors = anchor_map
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_total = total_duration(def)
	active = true
	var host := get_parent()
	_prev_cam = get_viewport().get_camera_3d()
	_cam = Camera3D.new()
	_cam.name = "CameraCinematique"
	host.add_child(_cam)
	_cam.make_current()
	for c in host.get_children():
		if c is CanvasLayer and c != self and (c as CanvasLayer).visible:
			(c as CanvasLayer).visible = false
			_hidden.append(c)
	var places := host.get_node_or_null("Ville/LieuxDeMission")
	if places:
		for lieu in places.get_children():
			for c in lieu.get_children():
				if c is Label3D or (c is MeshInstance3D and (c as MeshInstance3D).mesh is CylinderMesh):
					(c as Node3D).visible = false
					_markers.append(c)
	if get_node("/root/Net").can_pause() and not get_tree().paused:
		get_tree().paused = true
		_we_paused = true
	_build_ui()
	_next_shot()


func _build_ui() -> void:
	for top in [true, false]:
		var r := ColorRect.new()
		r.color = Color.BLACK
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.anchor_top = 0.0 if top else 1.0 - BAR
		r.anchor_bottom = BAR if top else 1.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(r)
		_bars.append(r)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.anchor_top = 0.70
	box.anchor_bottom = 1.0 - BAR - 0.02
	box.offset_left = 120
	box.offset_right = -120
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_who = _label(box, 26, Color(1.0, 0.82, 0.3))
	_text = _label(box, 30, Color(0.98, 0.96, 0.9))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var tbox := VBoxContainer.new()
	tbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(tbox)
	_title = _label(tbox, 68, Color(1.0, 0.9, 0.55))
	_sub = _label(tbox, 30, Color(0.97, 0.95, 0.9))
	_title.text = str(def.get("title", ""))
	_sub.text = str(def.get("subtitle", ""))
	_title.modulate.a = 0.0
	_sub.modulate.a = 0.0
	_hint = Label.new()
	var Bindings = preload("res://scripts/core/input_bindings.gd")
	_hint.text = "[%s] Passer" % Bindings.key_text(Bindings.key_of("dialogue_skip"))
	_hint.add_theme_font_size_override("font_size", int(20 * get_node("/root/Settings").text_scale))
	_hint.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 0.8))
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hint.offset_left = -240
	_hint.offset_top = -64
	_hint.offset_right = -40
	_hint.offset_bottom = -24
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_hint)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", int(size * get_node("/root/Settings").text_scale))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.04, 0.03))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _next_shot() -> void:
	_shot += 1
	_shot_t = 0.0
	var shots: Array = def.get("shots", [])
	if _shot >= shots.size():
		_end()
		return
	var s: Dictionary = shots[_shot]
	var cap: Dictionary = s.get("caption", {})
	_who.text = str(cap.get("who", ""))
	_text.text = str(cap.get("text", ""))
	if s.has("onoma") and get_node("/root/Settings").onomatopees:
		get_node("/root/Sfx").say_onoma(str(s.onoma), null, "loud")
	_apply(0.0)


func _apply(u: float) -> void:
	var shots: Array = def.get("shots", [])
	if _shot >= shots.size():
		return
	var st = shot_state(shots[_shot], u, anchors)
	if st == null:
		return
	if (st.cam as Vector3).distance_to(st.look) < 0.01:
		return
	_cam.fov = st.fov
	_cam.look_at_from_position(st.cam, st.look, Vector3.UP)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_shot_t += delta
	var shots: Array = def.get("shots", [])
	if _shot < shots.size():
		var dur := float(shots[_shot].dur)
		_apply(_shot_t / dur)
		if _shot_t >= dur:
			_next_shot()
	# Fondus d'ouverture et de fermeture, bandes, carton de titre (premier plan).
	_fade.color.a = clampf(1.0 - _t / FADE, 0.0, 1.0) if _t < FADE else clampf((_t - (_total - FADE)) / FADE, 0.0, 1.0)
	if _shot == 0:
		var a := clampf((_shot_t - 0.5) / 0.8, 0.0, 1.0) * clampf((3.6 - _shot_t) / 0.8, 0.0, 1.0)
		_title.modulate.a = a
		_sub.modulate.a = a
	else:
		_title.modulate.a = 0.0
		_sub.modulate.a = 0.0
	_text.modulate.a = clampf(_shot_t / 0.4, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("dialogue_skip") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_end()


func skip() -> void:
	_end()


func _end() -> void:
	if _done:
		return
	_done = true
	active = false
	if _we_paused:
		get_tree().paused = false
	for m in _markers:
		if is_instance_valid(m):
			(m as Node3D).visible = true
	for c in _hidden:
		if is_instance_valid(c):
			(c as CanvasLayer).visible = true
	if is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	if is_instance_valid(_cam):
		_cam.queue_free()
	finished.emit(str(def.get("id", "")))
	queue_free()
