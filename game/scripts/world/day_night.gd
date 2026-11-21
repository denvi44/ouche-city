class_name DayNight
extends Node
## Cycle jour/nuit (agent 03). L'heure est décidée par le serveur et diffusée aux clients.
## Rampes de couleur : aplats peints, jamais réalistes.

## Heure de jeu (0–24).
@export_range(0.0, 24.0) var hour: float = 12.0
## Minutes de jeu par seconde réelle (1 h de jeu = 2 min réelles).
@export var minutes_per_second: float = 0.5
@export var running: bool = true

@export var sun: DirectionalLight3D
@export var environment: Environment

## Clés de la rampe : heure -> [zénith, horizon, soleil, énergie soleil, ambiance]
const RAMP := [
	[0.0, Color(0.05, 0.07, 0.18), Color(0.12, 0.14, 0.28), Color(0.45, 0.5, 0.8), 0.0, Color(0.18, 0.2, 0.35)],
	[5.5, Color(0.12, 0.13, 0.3), Color(0.55, 0.42, 0.5), Color(1.0, 0.6, 0.45), 0.1, Color(0.3, 0.28, 0.4)],
	[7.5, Color(0.4, 0.58, 0.82), Color(0.98, 0.78, 0.6), Color(1.0, 0.82, 0.62), 0.6, Color(0.55, 0.55, 0.6)],
	[12.0, Color(0.36, 0.6, 0.85), Color(0.78, 0.88, 0.93), Color(1.0, 0.97, 0.88), 0.85, Color(0.62, 0.66, 0.72)],
	[18.0, Color(0.36, 0.55, 0.8), Color(0.95, 0.8, 0.62), Color(1.0, 0.85, 0.65), 0.7, Color(0.58, 0.56, 0.6)],
	[20.5, Color(0.25, 0.25, 0.5), Color(0.98, 0.55, 0.4), Color(1.0, 0.55, 0.35), 0.35, Color(0.42, 0.36, 0.45)],
	[21.5, Color(0.1, 0.11, 0.28), Color(0.4, 0.3, 0.45), Color(0.7, 0.6, 0.85), 0.05, Color(0.24, 0.24, 0.38)],
	[24.0, Color(0.05, 0.07, 0.18), Color(0.12, 0.14, 0.28), Color(0.45, 0.5, 0.8), 0.0, Color(0.18, 0.2, 0.35)],
]


func _process(delta: float) -> void:
	if running and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		hour = fposmod(hour + delta * minutes_per_second / 60.0, 24.0)
	apply()


## Échantillonne la rampe à l'heure donnée (fonction pure, testée).
static func sample(h: float) -> Dictionary:
	h = fposmod(h, 24.0)
	for i in RAMP.size() - 1:
		var a: Array = RAMP[i]
		var b: Array = RAMP[i + 1]
		if h >= a[0] and h <= b[0]:
			var t: float = (h - a[0]) / maxf(b[0] - a[0], 0.0001)
			return {
				"zenith": (a[1] as Color).lerp(b[1], t), "horizon": (a[2] as Color).lerp(b[2], t),
				"sun_color": (a[3] as Color).lerp(b[3], t), "sun_energy": lerpf(a[4], b[4], t),
				"ambient": (a[5] as Color).lerp(b[5], t),
			}
	return {}


## Direction du soleil : se lève à l'est (6 h), culmine au sud à midi, se couche à l'ouest (18 h).
## La nuit, la « lumière » devient une lune douce venant du sud-ouest.
static func sun_rotation(h: float) -> Vector3:
	var day := clampf((h - 6.0) / 12.0, 0.0, 1.0)
	var is_day := h >= 6.0 and h <= 18.0
	var elevation := sin(day * PI) * deg_to_rad(55.0) if is_day else deg_to_rad(35.0)
	var azimuth := lerpf(deg_to_rad(90.0), deg_to_rad(-90.0), day) if is_day else deg_to_rad(-140.0)
	# DirectionalLight3D éclaire vers -Z local.
	return Vector3(-maxf(elevation, deg_to_rad(8.0)), azimuth + PI, 0.0)


func apply() -> void:
	var s := sample(hour)
	if s.is_empty():
		return
	if sun:
		sun.rotation = sun_rotation(hour)
		sun.light_color = s.sun_color
		sun.light_energy = maxf(s.sun_energy, 0.2)
	if environment:
		environment.ambient_light_color = s.ambient
		var sky_mat := environment.sky.sky_material as ShaderMaterial if environment.sky else null
		if sky_mat:
			sky_mat.set_shader_parameter("zenith", s.zenith)
			sky_mat.set_shader_parameter("horizon", s.horizon)
			sky_mat.set_shader_parameter("couleur_soleil", s.sun_color)
