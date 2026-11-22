extends Node
## Réglages du joueur (accessibilité incluse), persistés dans user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name: String = "Normand"
var mouse_sensitivity: float = 0.003
var invert_y: bool = false
## Échelle des textes de l'interface (accessibilité : 1.0 à 2.0).
var text_scale: float = 1.0
var subtitles: bool = true
## Onomatopées en bulles (POUET !, BOUM !…) au-dessus des sons : équivalent visuel des bruitages (accessibilité).
var onomatopees: bool = true
## Bulles de dialogue au-dessus des personnages (les sous-titres du bas restent affichés).
var speech_bubbles: bool = true
## Volumes (0 à 1) : général, effets, musique (radio), ambiance.
var volume_master: float = 0.9
var volume_sfx: float = 1.0
var volume_music: float = 0.7
var volume_ambience: float = 0.8
## Filtre daltonisme : "aucun", "protanopie", "deuteranopie", "tritanopie" (appliqué au jalon M1).
var colorblind_mode: String = "aucun"
## Cinématiques d'introduction et de fin de mission (désactivables ; toujours passables).
var cinematics: bool = true
## En solo, les compagnons IA ne font que guider (suivre, montrer le chemin) ; vrai : ils tiennent aussi leurs rôles (tâches de mission).
var companions_help: bool = false
## Vie ambiante : passants et voitures qui circulent (décor, non solides). Désactivable pour les petites configurations.
var ambient_life: bool = true
## Multiplicateur de durée des dialogues et des plans de cinématique (1.0 = rapide, 1.6 = confortable, 2.4 = très lent).
var dialogue_pace: float = 1.6


func _ready() -> void:
	load_settings()
	preload("res://scripts/core/input_bindings.gd").apply_saved()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = cfg.get_value("joueur", "nom", player_name)
	mouse_sensitivity = cfg.get_value("controles", "sensibilite_souris", mouse_sensitivity)
	invert_y = cfg.get_value("controles", "inverser_y", invert_y)
	text_scale = clampf(cfg.get_value("accessibilite", "taille_texte", text_scale), 1.0, 2.0)
	subtitles = cfg.get_value("accessibilite", "sous_titres", subtitles)
	onomatopees = cfg.get_value("accessibilite", "onomatopees", onomatopees)
	speech_bubbles = cfg.get_value("accessibilite", "bulles", speech_bubbles)
	volume_master = clampf(cfg.get_value("audio", "general", volume_master), 0.0, 1.0)
	volume_sfx = clampf(cfg.get_value("audio", "effets", volume_sfx), 0.0, 1.0)
	volume_music = clampf(cfg.get_value("audio", "musique", volume_music), 0.0, 1.0)
	volume_ambience = clampf(cfg.get_value("audio", "ambiance", volume_ambience), 0.0, 1.0)
	colorblind_mode = cfg.get_value("accessibilite", "daltonisme", colorblind_mode)
	cinematics = cfg.get_value("jeu", "cinematiques", cinematics)
	companions_help = cfg.get_value("jeu", "compagnons_aident", companions_help)
	ambient_life = cfg.get_value("jeu", "vie_ambiante", ambient_life)
	dialogue_pace = clampf(cfg.get_value("jeu", "rythme_dialogues", dialogue_pace), 1.0, 3.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("joueur", "nom", player_name)
	cfg.set_value("controles", "sensibilite_souris", mouse_sensitivity)
	cfg.set_value("controles", "inverser_y", invert_y)
	cfg.set_value("accessibilite", "taille_texte", text_scale)
	cfg.set_value("accessibilite", "sous_titres", subtitles)
	cfg.set_value("accessibilite", "onomatopees", onomatopees)
	cfg.set_value("accessibilite", "bulles", speech_bubbles)
	cfg.set_value("audio", "general", volume_master)
	cfg.set_value("audio", "effets", volume_sfx)
	cfg.set_value("audio", "musique", volume_music)
	cfg.set_value("audio", "ambiance", volume_ambience)
	cfg.set_value("accessibilite", "daltonisme", colorblind_mode)
	cfg.set_value("jeu", "cinematiques", cinematics)
	cfg.set_value("jeu", "compagnons_aident", companions_help)
	cfg.set_value("jeu", "vie_ambiante", ambient_life)
	cfg.set_value("jeu", "rythme_dialogues", dialogue_pace)
	cfg.save(PATH)
