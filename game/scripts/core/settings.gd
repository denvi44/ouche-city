extends Node
## Réglages du joueur (accessibilité incluse), persistés dans user://settings.cfg.

const PATH := "user://settings.cfg"

var player_name: String = "Normand"
var mouse_sensitivity: float = 0.003
var invert_y: bool = false
## Échelle des textes de l'interface (accessibilité : 1.0 à 2.0).
var text_scale: float = 1.0
var subtitles: bool = true
## Filtre daltonisme : "aucun", "protanopie", "deuteranopie", "tritanopie" (appliqué au jalon M1).
var colorblind_mode: String = "aucun"


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	player_name = cfg.get_value("joueur", "nom", player_name)
	mouse_sensitivity = cfg.get_value("controles", "sensibilite_souris", mouse_sensitivity)
	invert_y = cfg.get_value("controles", "inverser_y", invert_y)
	text_scale = clampf(cfg.get_value("accessibilite", "taille_texte", text_scale), 1.0, 2.0)
	subtitles = cfg.get_value("accessibilite", "sous_titres", subtitles)
	colorblind_mode = cfg.get_value("accessibilite", "daltonisme", colorblind_mode)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("joueur", "nom", player_name)
	cfg.set_value("controles", "sensibilite_souris", mouse_sensitivity)
	cfg.set_value("controles", "inverser_y", invert_y)
	cfg.set_value("accessibilite", "taille_texte", text_scale)
	cfg.set_value("accessibilite", "sous_titres", subtitles)
	cfg.set_value("accessibilite", "daltonisme", colorblind_mode)
	cfg.save(PATH)
