class_name Ambiance
extends Node
## Ambiance sonore de la ville (agent 08) : vent permanent, chants d'oiseaux le jour,
## cloches de l'église à chaque heure de jeu (spatialisées : on ne les entend que près de l'église).

const BIRD_HOURS := Vector2(6.0, 21.0)

var day_night: DayNight
var church_pos := Vector3.ZERO
var has_church := false
var _wind: AudioStreamPlayer
var _bird_t := 5.0
var _last_hour := -1
var _strikes_left := 0
var _strike_t := 0.0


func _ready() -> void:
	if Sfx.enabled:
		_wind = AudioStreamPlayer.new()
		_wind.stream = Sfx.stream_for("wind")
		_wind.bus = "Ambiance"
		_wind.volume_db = -14.0
		add_child(_wind)
		_wind.play()


## Nombre de coups à l'heure donnée (cadran de 12 h, plafonné pour ne pas sonner trop longtemps).
static func strikes_for(hour: int) -> int:
	var h := hour % 12
	return mini(12 if h == 0 else h, 4)


func _process(delta: float) -> void:
	if day_night == null:
		return
	var h := int(floor(day_night.hour))
	if _last_hour < 0:
		_last_hour = h
	elif h != _last_hour:
		_last_hour = h
		if h >= 8 and h <= 20 and has_church:
			_strikes_left = strikes_for(h)
			_strike_t = 0.0
	if _strikes_left > 0:
		_strike_t -= delta
		if _strike_t <= 0.0:
			_strikes_left -= 1
			_strike_t = 1.8
			Sfx.play_at("bell", church_pos + Vector3(0, 25.0, 0))
	# Oiseaux : le jour seulement, à intervalles irréguliers.
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = randf_range(6.0, 14.0)
		if day_night.hour >= BIRD_HOURS.x and day_night.hour <= BIRD_HOURS.y:
			Sfx.play("bird", randf_range(-3.0, 2.0), randf_range(0.85, 1.25))
