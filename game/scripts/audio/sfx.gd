extends Node
## Gestionnaire audio d'Ouche City (agent 08) — autoload « Sfx ».
##
## - Sons courts : `play(nom)` (2D) ou `play_at(nom, position)` (3D, atténué avec la distance).
## - Boucles tenues par leur propriétaire (moteur, tracteur) : `make_loop`.
## - Bus de mixage : Effets, Musique, Ambiance, réglés par `Settings`.
## - Accessibilité : tout son important émet `caption` (sous-titre sonore) ; le HUD l'affiche.
## - Tests : `played` garde la trace des sons demandés, même sans carte son (serveur, CI).
## Les sons viennent de `Synth` ; un fichier `res://assets/audio/<nom>.ogg|.wav` le remplace s'il existe.

signal caption(text: String, seconds: float)

## nom -> {gen: fonction de Synth, caption: sous-titre (vide = aucun), db: niveau, bus}
const CATALOG := {
	"klaxon": {"gen": "klaxon", "caption": "[Klaxon]", "db": -2.0, "bus": "Effets"},
	"thud": {"gen": "thud", "caption": "[Choc dans un nid-de-poule]", "db": 0.0, "bus": "Effets"},
	"glass": {"gen": "glass", "caption": "[Verre brisé]", "db": -1.0, "bus": "Effets"},
	"crate": {"gen": "crate", "caption": "", "db": -3.0, "bus": "Effets"},
	"moo": {"gen": "moo", "caption": "[Meuglement]", "db": -2.0, "bus": "Effets"},
	"chime": {"gen": "chime", "caption": "", "db": -5.0, "bus": "Effets"},
	"fail": {"gen": "fail", "caption": "[Échec]", "db": -4.0, "bus": "Effets"},
	"fanfare": {"gen": "fanfare", "caption": "[Fanfare de victoire]", "db": -4.0, "bus": "Effets"},
	"step": {"gen": "step", "caption": "", "db": -12.0, "bus": "Effets"},
	"radio_blip": {"gen": "radio_blip", "caption": "[Radio : Kévin Radio parle]", "db": -6.0, "bus": "Effets"},
	"bell": {"gen": "bell", "caption": "[Cloches de l'église]", "db": -6.0, "bus": "Ambiance"},
	"bird": {"gen": "bird", "caption": "", "db": -10.0, "bus": "Ambiance"},
}
const LOOPS := {
	"engine": {"gen": "engine_loop", "bus": "Effets"},
	"tractor": {"gen": "tractor_loop", "bus": "Effets"},
	"wind": {"gen": "wind_loop", "bus": "Ambiance"},
}
const BUSES := ["Effets", "Musique", "Ambiance"]
const POOL_2D := 6
const POOL_3D := 12

var enabled := true             ## faux en mode headless : on journalise sans jouer
var played: Array[String] = []  ## derniers sons demandés (tests, sous-titres)
var counts := {}                ## nombre de fois où chaque son a été demandé (tests)
var radio_on := false

var _cache := {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _music_thread: Thread
var _music_pending := false


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 140.0
		add_child(p)
		_pool_3d.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Musique"
	add_child(_music_player)
	apply_volumes()


## Applique les volumes des réglages aux bus (à rappeler après modification).
func apply_volumes() -> void:
	if not enabled:
		return
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Settings.volume_master, 0.0001)))
	var vols := {"Effets": Settings.volume_sfx, "Musique": Settings.volume_music, "Ambiance": Settings.volume_ambience}
	for b in vols:
		var idx := AudioServer.get_bus_index(b)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vols[b], 0.0001)))
			AudioServer.set_bus_mute(idx, vols[b] <= 0.001)


## Flux d'un son (fichier de remplacement s'il existe, sinon synthèse mise en cache).
func stream_for(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var info: Dictionary = CATALOG.get(name, LOOPS.get(name, {}))
	if info.is_empty():
		return null
	var stream: AudioStream = null
	for ext in ["ogg", "wav"]:
		var path := "res://assets/audio/%s.%s" % [name, ext]
		if ResourceLoader.exists(path):
			stream = load(path)
			break
	if stream == null:
		stream = Synth.to_stream(Callable(Synth, info.gen).call(), LOOPS.has(name))
	_cache[name] = stream
	return stream


func _log(name: String) -> void:
	counts[name] = counts.get(name, 0) + 1
	played.append(name)
	if played.size() > 80:
		played.pop_front()
	var cap: String = CATALOG.get(name, {}).get("caption", "")
	if cap != "" and Settings.subtitles:
		caption.emit(cap, 2.6)


## Son non spatialisé (interface, carillons).
func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	_log(name)
	if not enabled:
		return
	var s := stream_for(name)
	if s == null:
		return
	var p := _free_2d()
	p.stream = s
	p.bus = CATALOG[name].bus
	p.volume_db = CATALOG[name].db + volume_db
	p.pitch_scale = pitch
	p.play()


## Son spatialisé à une position du monde.
func play_at(name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	_log(name)
	if not enabled:
		return
	var s := stream_for(name)
	if s == null:
		return
	var p := _free_3d()
	p.stream = s
	p.bus = CATALOG[name].bus
	p.volume_db = CATALOG[name].db + volume_db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


func _free_2d() -> AudioStreamPlayer:
	for p in _pool_2d:
		if not p.playing:
			return p
	return _pool_2d[0]


func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool_3d:
		if not p.playing:
			return p
	return _pool_3d[0]


## Boucle spatialisée gérée par son propriétaire (null si l'audio est désactivé).
func make_loop(kind: String, volume_db := -8.0) -> AudioStreamPlayer3D:
	if not enabled or not LOOPS.has(kind):
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = stream_for(kind)
	p.bus = LOOPS[kind].bus
	p.volume_db = volume_db
	p.unit_size = 7.0
	p.max_distance = 110.0
	return p


# --- Radio Pommiers ---------------------------------------------------------------------------------

## Allume ou éteint la radio de la camionnette (« Valse du Pommier »).
func set_radio(on: bool) -> void:
	radio_on = on
	var tag := "radio_on" if on else "radio_off"
	counts[tag] = counts.get(tag, 0) + 1
	played.append(tag)
	if on and Settings.subtitles:
		caption.emit("[Radio Pommiers : valse musette]", 3.0)
	if not enabled:
		return
	if on:
		if _music_stream == null:
			if not _music_pending:
				_music_pending = true
				_music_thread = Thread.new()
				_music_thread.start(_generate_music)
		else:
			_music_player.play()
	else:
		_music_player.stop()


func _generate_music() -> void:
	var samples := Synth.music_pommier()
	_music_ready.call_deferred(samples)


func _music_ready(samples: PackedFloat32Array) -> void:
	_music_thread.wait_to_finish()
	_music_stream = Synth.to_stream(samples, true)
	_music_pending = false
	_music_player.stream = _music_stream
	_music_player.volume_db = -6.0
	if radio_on:
		_music_player.play()


## Playlist de la battle de sono (mission 03) : boucle de 8 s, générée une fois puis gardée.
const TRACK_CAPTIONS := {"musette_remix": "[Sono : musette remixée]", "techno_foraine": "[Sono : techno foraine]", "tube_ete_2003": "[Sono : tube de l'été 2003]"}
var current_track := ""
var _track_cache := {}
var _track_player: AudioStreamPlayer


func play_track(id: String) -> void:
	current_track = id
	var tag := "track_" + id
	counts[tag] = counts.get(tag, 0) + 1
	played.append(tag)
	if Settings.subtitles and TRACK_CAPTIONS.has(id):
		caption.emit(TRACK_CAPTIONS[id], 3.0)
	if not enabled:
		return
	if _track_player == null:
		_track_player = AudioStreamPlayer.new()
		_track_player.bus = "Musique"
		_track_player.volume_db = -4.0
		add_child(_track_player)
	if not _track_cache.has(id):
		_track_cache[id] = Synth.to_stream(Synth.track(id), true)
	_track_player.stream = _track_cache[id]
	_track_player.play()


func stop_track() -> void:
	current_track = ""
	if _track_player:
		_track_player.stop()


func toggle_radio() -> void:
	set_radio(not radio_on)
