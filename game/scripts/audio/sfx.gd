extends Node
## Gestionnaire audio de Frouch City (agent 08) — autoload « Sfx ».
##
## - Sons courts : `play(nom)` (2D) ou `play_at(nom, position)` (3D, atténué avec la distance).
## - Boucles tenues par leur propriétaire (moteur, tracteur) : `make_loop`.
## - Bus de mixage : Effets, Musique, Ambiance, réglés par `Settings`.
## - Accessibilité : tout son important émet `caption` (sous-titre sonore) ; le HUD l'affiche.
## - Tests : `played` garde la trace des sons demandés, même sans carte son (serveur, CI).
## Les sons viennent de `Synth` ; un fichier `res://assets/audio/<nom>.ogg|.wav` le remplace s'il existe.

signal caption(text: String, seconds: float)
## Onomatopée à afficher en bulle : `pos` = null (au-dessus du joueur local) ou Vector3 (monde) ; `tone` : loud, soft, good, bad.
signal onomatopee(text: String, pos: Variant, tone: String)

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
	"bark": {"gen": "bark", "caption": "[Aboiement]", "db": -3.0, "bus": "Effets"},
	"sizzle": {"gen": "sizzle", "caption": "", "db": -9.0, "bus": "Effets"},
	"firework": {"gen": "firework", "caption": "[Feu d'artifice]", "db": -4.0, "bus": "Effets"},
	"whistle": {"gen": "whistle", "caption": "[Sifflet du berger]", "db": -3.0, "bus": "Effets"},
	"beep": {"gen": "beep", "caption": "[Bip de caisse]", "db": -6.0, "bus": "Effets"},
	"coin": {"gen": "coin", "caption": "", "db": -5.0, "bus": "Effets"},
	"sigh": {"gen": "sigh", "caption": "[Soupir agacé d'un client]", "db": -4.0, "bus": "Effets"},
	"babble": {"gen": "babble", "caption": "", "db": -12.0, "bus": "Effets"},
	"gurgle": {"gen": "gurgle", "caption": "[Gargouillis inquiétant]", "db": -3.0, "bus": "Effets"},
	"toot": {"gen": "toot", "caption": "[Un petit bruit… discret]", "db": -3.0, "bus": "Effets"},
	"toot_big": {"gen": "toot_big", "caption": "[Un bruit sans équivoque]", "db": -1.0, "bus": "Effets"},
	"honk": {"gen": "honk", "caption": "[HONK d'oie]", "db": -2.0, "bus": "Effets"},
	"train_horn": {"gen": "train_horn", "caption": "[Klaxon du train]", "db": -3.0, "bus": "Effets"},
	"bird": {"gen": "bird", "caption": "", "db": -10.0, "bus": "Ambiance"},
}
## Onomatopée de chaque son (texte, ton) : le bruitage a toujours un équivalent écrit, façon bande dessinée.
const ONOMA := {
	"klaxon": ["POUET POUET !", "loud"], "thud": ["BOUM !", "loud"], "glass": ["CRAAAC !", "bad"], "crate": ["TOC !", "soft"],
	"moo": ["MEUUUH !", "soft"], "chime": ["DING !", "good"], "fail": ["OUPS…", "bad"], "fanfare": ["TADAAAA !", "good"],
	"radio_blip": ["KSSSH…", "soft"], "bell": ["DING DONG !", "good"], "bark": ["OUAF OUAF !", "loud"], "sizzle": ["TSSSSS", "soft"],
	"firework": ["BOUM ! PSCHIIIT", "loud"], "whistle": ["FIIIIIT !", "loud"], "beep": ["BIP !", "soft"], "coin": ["CLING !", "good"],
	"sigh": ["PFFFF…", "bad"], "gurgle": ["GRRRBLOUP !", "bad"], "toot": ["PFRRT !", "bad"], "toot_big": ["PRRRRRRRT !!", "loud"], "honk": ["HONK !", "loud"], "train_horn": ["POUUUT POUUUT !", "loud"],
}
const ONOMA_COOLDOWN := 0.35
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
var onoma_log: Array[String] = []     ## dernières onomatopées émises (tests)
var _onoma_t := {}

var _cache := {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer
var _music_stream: AudioStreamWAV
var _music_thread: Thread
var _music_pending := false
var _radio_player: AudioStreamPlayer
var _radio_track := ""                 ## fichier en cours sur la radio personnalisée
var _mission_player: AudioStreamPlayer
var mission_category := ""            ## catégorie de musique d'ambiance en cours (tests)
var _mission_track := ""


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


func _log(name: String, pos: Variant = null) -> void:
	_onoma(name, pos)
	counts[name] = counts.get(name, 0) + 1
	played.append(name)
	if played.size() > 80:
		played.pop_front()
	var cap: String = CATALOG.get(name, {}).get("caption", "")
	if cap != "" and Settings.subtitles:
		caption.emit(cap, 2.6)


## Émet l'onomatopée d'un son (au plus une fois par 0,35 s et par son), si l'option est active.
func _onoma(name: String, pos: Variant) -> void:
	if not ONOMA.has(name) or not Settings.onomatopees:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_onoma_t.get(name, -10.0)) < ONOMA_COOLDOWN:
		return
	_onoma_t[name] = now
	say_onoma(ONOMA[name][0], pos, ONOMA[name][1])


## Onomatopée libre (étiquette `#onoma:` d'une réplique, événements) : journal + signal pour les bulles.
func say_onoma(text: String, pos: Variant = null, tone := "loud") -> void:
	if not Settings.onomatopees:
		return
	onoma_log.append(text)
	if onoma_log.size() > 60:
		onoma_log.pop_front()
	onomatopee.emit(text, pos, tone)


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
	_log(name, pos)
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

## Allume ou éteint la radio de la camionnette (« Valse du Pommier », ou vos mp3 du dossier « radio »).
func set_radio(on: bool) -> void:
	radio_on = on
	var tag := "radio_on" if on else "radio_off"
	counts[tag] = counts.get(tag, 0) + 1
	played.append(tag)
	var custom := _custom_radio_list()
	if on and Settings.subtitles and custom.is_empty():
		caption.emit("[Radio Pommiers : valse musette]", 3.0)
	_apply_mission_pause()
	if on and not custom.is_empty():
		counts["radio_perso"] = counts.get("radio_perso", 0) + 1
		_radio_track = _radio_track if _radio_track in custom else custom[0]
		_play_radio_track()
		return
	if not enabled:
		return
	if _radio_player:
		_radio_player.stop()
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
## Décalage (s) du 1er temps de « Under A Thousand Suns » : on démarre la lecture un peu plus loin pour que les temps tombent sur la grille du jeu.
const RHYTHM_TRACK_OFFSET := 0.054
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
	_apply_mission_pause()
	# Musique des manches : « m03_rythme » (la même pour toutes les playlists) ou, à défaut, celle de la playlist choisie.
	var perso: Array = MusicLibrary.tracks("m03_rythme") if Settings.custom_music else []
	var shared := not perso.is_empty()
	if not shared and Settings.custom_music:
		perso = MusicLibrary.tracks("m03_" + id)
	if not perso.is_empty():
		counts["track_perso"] = counts.get("track_perso", 0) + 1
		var st := MusicLibrary.load_stream(perso[0], true)
		if st != null:
			_track_player.stream = st
			_track_player.play(RHYTHM_TRACK_OFFSET if shared else 0.0)
			return
	if not _track_cache.has(id):
		_track_cache[id] = Synth.to_stream(Synth.track(id), true)
	_track_player.stream = _track_cache[id]
	_track_player.play()


func stop_track() -> void:
	current_track = ""
	_apply_mission_pause()
	if _track_player:
		_track_player.stop()


func toggle_radio() -> void:
	set_radio(not radio_on)


# --- Musiques personnalisées (dossier « musique » du joueur) ------------------------------------------------------------------

func _custom_radio_list() -> Array:
	return MusicLibrary.tracks("radio") if Settings.custom_music else []


## Titre suivant de la radio personnalisée (sans effet si la radio est éteinte ou n'a pas de fichiers).
func radio_next() -> void:
	var list := _custom_radio_list()
	if not radio_on or list.is_empty():
		return
	_radio_track = MusicLibrary.next_after(list, _radio_track)
	counts["radio_suivant"] = counts.get("radio_suivant", 0) + 1
	_play_radio_track()


func _play_radio_track() -> void:
	if Settings.subtitles and _radio_track != "":
		caption.emit("[Radio : %s]" % MusicLibrary.title_of(_radio_track), 3.0)
	if not enabled:
		return
	var st := MusicLibrary.load_stream(_radio_track)
	if st == null:
		# Fichier illisible : on l'écarte et on passe au suivant, sinon on retombe sur la valse d'origine.
		counts["radio_illisible"] = counts.get("radio_illisible", 0) + 1
		return
	if _radio_player == null:
		_radio_player = AudioStreamPlayer.new()
		_radio_player.bus = "Musique"
		_radio_player.volume_db = -4.0
		_radio_player.finished.connect(func(): if radio_on: radio_next())
		add_child(_radio_player)
	_music_player.stop()
	_radio_player.stream = st
	_radio_player.play()


## Musique d'ambiance d'une mission (ou « titre ») : les fichiers du dossier de la catégorie, en boucle sur la liste.
func play_mission_music(category: String) -> void:
	stop_mission_music()
	var list: Array = MusicLibrary.tracks(category) if Settings.custom_music else []
	if list.is_empty():
		return
	mission_category = category
	_mission_track = list[0]
	counts["musique_" + category] = counts.get("musique_" + category, 0) + 1
	played.append("musique_" + category)
	_play_mission_track()


func _play_mission_track() -> void:
	if Settings.subtitles and _mission_track != "":
		caption.emit("[Musique : %s]" % MusicLibrary.title_of(_mission_track), 3.0)
	if not enabled or _mission_track == "":
		return
	var st := MusicLibrary.load_stream(_mission_track)
	if st == null:
		counts["musique_illisible"] = counts.get("musique_illisible", 0) + 1
		return
	if _mission_player == null:
		_mission_player = AudioStreamPlayer.new()
		_mission_player.bus = "Musique"
		_mission_player.volume_db = -9.0
		_mission_player.finished.connect(func():
			var list: Array = MusicLibrary.tracks(mission_category)
			if mission_category != "" and not list.is_empty():
				_mission_track = MusicLibrary.next_after(list, _mission_track)
				_play_mission_track())
		add_child(_mission_player)
	_mission_player.stream = st
	_mission_player.stream_paused = false
	_mission_player.play()
	_apply_mission_pause()


func stop_mission_music() -> void:
	mission_category = ""
	_mission_track = ""
	if _mission_player:
		_mission_player.stop()


## La musique d'ambiance se tait pendant la radio du véhicule ou la battle de sono.
func _apply_mission_pause() -> void:
	if _mission_player:
		_mission_player.stream_paused = radio_on or current_track != ""
