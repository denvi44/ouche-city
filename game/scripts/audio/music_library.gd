class_name MusicLibrary
extends RefCounted
## Musiques personnalisées : le joueur dépose ses mp3 (ou ogg, wav) dans un dossier, sans reconstruire le jeu.
## Dossier : `user://musique/<catégorie>/` (sur Mac : ~/Library/Application Support/Godot/app_userdata/<jeu>/musique/ ;
## sous Windows : %APPDATA%\Godot\app_userdata\<jeu>\musique\), ou `res://assets/musique_perso/<catégorie>/` pour des fichiers livrés avec le jeu.
## Catégories : radio (radio du véhicule), titre (écran titre), m01 … m08 (musique d'ambiance de la mission),
## m03_musette_remix / m03_techno_foraine / m03_tube_ete_2003 (les trois playlists de la battle de sono).

const EXTENSIONS := ["mp3", "ogg", "wav"]
const USER_DIR := "user://musique"
const BUNDLED_DIR := "res://assets/musique_perso"
const CATEGORIES := ["radio", "titre", "m01", "m02", "m03", "m04", "m05", "m06", "m07", "m08",
	"m03_musette_remix", "m03_techno_foraine", "m03_tube_ete_2003"]

## Dossiers racines (modifiable par les tests).
static var roots: Array = [USER_DIR, BUNDLED_DIR]


## Chemins des fichiers audio d'une catégorie, triés par nom (les dossiers utilisateur d'abord).
static func tracks(category: String) -> Array:
	var out: Array = []
	for root in roots:
		var dir := DirAccess.open("%s/%s" % [root, category])
		if dir == null:
			continue
		var names := []
		for f in dir.get_files():
			var name := f.trim_suffix(".import")        # les fichiers livrés dans res:// sont listés avec leur .import
			if name.get_extension().to_lower() in EXTENSIONS and not names.has(name):
				names.append(name)
		names.sort()
		for n in names:
			out.append("%s/%s/%s" % [root, category, n])
	return out


## Titre lisible d'un fichier : « 01_ma_chanson.mp3 » -> « ma chanson ».
static func title_of(path: String) -> String:
	var base := path.get_file().get_basename()
	var i := 0
	while i < base.length() and (base[i] >= "0" and base[i] <= "9"):
		i += 1
	if i > 0 and i < base.length() and base[i] in ["_", "-", " ", "."]:
		base = base.substr(i + 1)
	return base.replace("_", " ").strip_edges()


## Piste qui suit `current` dans la liste (retour au début en fin de liste) ; "" si la liste est vide.
static func next_after(list: Array, current: String) -> String:
	if list.is_empty():
		return ""
	var i := list.find(current)
	return str(list[(i + 1) % list.size()])


## Charge un fichier audio ; null si illisible (fichier abîmé, format inconnu) : le jeu garde alors sa musique d'origine.
static func load_stream(path: String, loop := false) -> AudioStream:
	var ext := path.get_extension().to_lower()
	if path.begins_with("res://"):
		var res = ResourceLoader.load(path.trim_suffix(".import"))
		if res is AudioStream:
			_set_loop(res, loop)
			return res
		return null
	if not FileAccess.file_exists(path):
		return null
	var stream: AudioStream = null
	match ext:
		"mp3":
			stream = AudioStreamMP3.load_from_file(path)
		"ogg":
			stream = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			var bytes := FileAccess.get_file_as_bytes(path)
			if bytes.size() > 44:
				stream = _wav_from_bytes(bytes)
	if stream != null:
		_set_loop(stream, loop)
	return stream


static func _set_loop(stream: AudioStream, loop: bool) -> void:
	if "loop" in stream:
		stream.loop = loop


## WAV 16 bits PCM simple (en-tête de 44 octets) ; tout autre WAV est ignoré.
static func _wav_from_bytes(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF" or bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null
	var channels := bytes.decode_u16(22)
	var rate := bytes.decode_u32(24)
	var bits := bytes.decode_u16(34)
	if bits != 16 or channels < 1 or channels > 2:
		return null
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = channels == 2
	w.data = bytes.slice(44)
	return w


## Crée le dossier utilisateur et un sous-dossier par catégorie (avec un mode d'emploi), et renvoie son chemin réel.
static func ensure_dirs() -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	for c in CATEGORIES:
		DirAccess.make_dir_recursive_absolute("%s/%s" % [USER_DIR, c])
	var f := FileAccess.open(USER_DIR + "/LISEZMOI.txt", FileAccess.WRITE)
	if f:
		f.store_string(readme())
	return ProjectSettings.globalize_path(USER_DIR)


static func readme() -> String:
	return "Frouch City — musiques personnalisées\n\n" \
		+ "Déposez vos fichiers mp3 (ou ogg, wav) dans les sous-dossiers :\n" \
		+ "  radio/   la radio du véhicule (touche R ; T pour passer au titre suivant)\n" \
		+ "  titre/   l'écran titre\n" \
		+ "  m01/ … m08/   la musique d'ambiance de chaque mission\n" \
		+ "  m03_musette_remix/, m03_techno_foraine/, m03_tube_ete_2003/   les trois playlists de la battle de sono\n\n" \
		+ "Les titres s'enchaînent dans l'ordre alphabétique (préfixez par 01_, 02_…). Redémarrez la mission pour les prendre en compte.\n" \
		+ "N'utilisez que de la musique dont vous avez les droits : elle reste sur votre ordinateur et n'est jamais envoyée en ligne.\n"
