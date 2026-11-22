class_name ThemeUtil
extends RefCounted
## Thème commun de l'interface : grandes tailles, fort contraste, échelle réglable (accessibilité).

const INK := Color(0.12, 0.09, 0.08)
const CREAM := Color(0.97, 0.93, 0.82)
const SLATE := Color(0.29, 0.35, 0.44)
const APPLE := Color(0.72, 0.18, 0.16)


static func make_theme() -> Theme:
	var t := Theme.new()
	var s := Settings.text_scale
	t.default_font_size = int(26 * s)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(CREAM, 0.95)
	panel.border_color = INK
	panel.set_border_width_all(4)
	panel.set_corner_radius_all(10)
	panel.set_content_margin_all(24)
	t.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": SLATE, "hover": APPLE, "pressed": INK, "focus": APPLE}[state]
		b.border_color = INK
		b.set_border_width_all(3)
		b.set_corner_radius_all(8)
		b.set_content_margin_all(12)
		t.set_stylebox(state, "Button", b)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", CREAM)
	t.set_color("font_focus_color", "Button", CREAM)
	t.set_color("font_color", "Label", INK)
	return t


## ---- Thème « Material Design 3 » de l'écran titre : cartes translucides arrondies, boutons pilule, ombres douces. ----
const MD_PRIMARY := Color(0.72, 0.18, 0.16)            # pomme (couleur d'accent du jeu)
const MD_ON_PRIMARY := Color(1, 1, 1)
const MD_TONAL := Color(0.99, 0.86, 0.80)              # conteneur secondaire
const MD_ON_TONAL := Color(0.25, 0.07, 0.05)
const MD_SURFACE := Color(0.99, 0.97, 0.93)            # surface (crème), rendue translucide sur la carte
const MD_ON_SURFACE := Color(0.13, 0.10, 0.09)
const MD_OUTLINE := Color(0.46, 0.40, 0.38)


static func _md_box(bg: Color, radius: int, margin_v := 10, margin_h := 24, border := Color(0, 0, 0, 0), border_w := 0, shadow := 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.set_corner_radius_all(radius)
	b.content_margin_top = margin_v
	b.content_margin_bottom = margin_v
	b.content_margin_left = margin_h
	b.content_margin_right = margin_h
	if border_w > 0:
		b.border_color = border
		b.set_border_width_all(border_w)
	if shadow > 0:
		b.shadow_size = shadow
		b.shadow_color = Color(0, 0, 0, 0.28)
		b.shadow_offset = Vector2(0, 3)
	return b


const BAR_FONT := "res://assets/fonts/BebasNeue-Regular.ttf"      # Bebas Neue, SIL OFL 1.1 (voir LICENSES/ATTRIBUTIONS.md)
const BAR_BLACK := Color(0.05, 0.045, 0.055, 0.78)             # barre de menu : noir translucide, on devine le village derrière
const BAR_LIGHT := Color(0.97, 0.94, 0.85, 0.96)               # barre sélectionnée : crème


## Une barre de menu : rectangle plein (angles vifs), noir translucide ; crème quand elle est survolée ou sélectionnée.
static func _bar_box(bg: Color, margin_v := 8, margin_h := 18, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var b := _md_box(bg, 0, margin_v, margin_h, border, border_w, 0)
	b.skew = Vector2(-0.06, 0.0)            # léger penché, comme des étiquettes collées à la main
	return b


static func _md_button(t: Theme, variation: String, bg: Color, fg: Color, _shadow: int) -> void:
	t.set_type_variation(variation, "Button")
	t.set_stylebox("normal", variation, _bar_box(bg))
	# Survol et focus (clavier, manette) : la barre devient crème, texte encre — jamais la seule couleur qui change : la forme aussi (bordure épaisse).
	t.set_stylebox("hover", variation, _bar_box(BAR_LIGHT))
	t.set_stylebox("focus", variation, _bar_box(BAR_LIGHT, 8, 18, APPLE, 3))
	t.set_stylebox("pressed", variation, _bar_box(APPLE))
	t.set_stylebox("disabled", variation, _bar_box(Color(0.05, 0.045, 0.055, 0.35)))
	t.set_color("font_color", variation, fg)
	t.set_color("font_hover_color", variation, INK)
	t.set_color("font_focus_color", variation, INK)
	t.set_color("font_pressed_color", variation, Color(1, 1, 1))
	t.set_color("font_disabled_color", variation, Color(1, 1, 1, 0.4))


static func make_material_theme() -> Theme:
	var t := Theme.new()
	var s := Settings.text_scale
	if ResourceLoader.exists(BAR_FONT):
		t.default_font = load(BAR_FONT)
	t.default_font_size = int(32 * s)          # Bebas Neue est petite à corps égal : on grossit
	# Textes posés directement sur le village : crème cerclé d'encre (lisible sur ciel clair comme sur briques).
	t.set_color("font_color", "Label", Color(1, 0.98, 0.92))
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 8)
	# Panneaux : « Card » est transparent (le menu principal flotte sur le village), « MenuPanel » un voile sombre (pause, touches).
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _md_box(Color(0, 0, 0, 0), 0, 8, 8))
	t.set_type_variation("MenuPanel", "PanelContainer")
	t.set_stylebox("panel", "MenuPanel", _md_box(Color(0.04, 0.035, 0.045, 0.62), 0, 22, 26))
	# Puce d'information (légende de plan, crédits) : petite étiquette sombre translucide.
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", _md_box(Color(0.08, 0.07, 0.08, 0.62), 0, 6, 16))
	t.set_type_variation("ChipLabel", "Label")
	t.set_color("font_color", "ChipLabel", Color(1, 1, 1, 0.95))
	t.set_constant("outline_size", "ChipLabel", 0)
	# Étiquette rouge pomme (slogan) : texte blanc sur fond pomme.
	t.set_type_variation("Tag", "PanelContainer")
	t.set_stylebox("panel", "Tag", _bar_box(APPLE, 4, 16))
	# Boutons : toutes les variantes sont des barres ; « Filled » (action principale) reste crème, les autres noires.
	_md_button(t, "FilledButton", BAR_LIGHT, INK, 0)
	t.set_color("font_hover_color", "FilledButton", INK)
	t.set_stylebox("hover", "FilledButton", _bar_box(Color(1, 1, 1, 1)))
	_md_button(t, "TonalButton", BAR_BLACK, Color(1, 0.98, 0.92), 0)
	_md_button(t, "TextButton", Color(0.05, 0.045, 0.055, 0.5), Color(1, 0.98, 0.92), 0)
	# Bouton par défaut = barre noire.
	_md_button(t, "Button", BAR_BLACK, Color(1, 0.98, 0.92), 0)
	for typ in ["CheckButton", "CheckBox"]:
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			t.set_stylebox(st, typ, t.get_stylebox(st, "Button"))
		for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_disabled_color", "font_hover_pressed_color"]:
			t.set_color(c, typ, Color(1, 0.98, 0.92) if c in ["font_color", "font_pressed_color"] else (INK if c != "font_disabled_color" else Color(1, 1, 1, 0.4)))
	# Champ de texte : barre sombre, bord crème.
	t.set_stylebox("normal", "LineEdit", _bar_box(Color(0.05, 0.045, 0.055, 0.7), 8, 16, Color(1, 0.98, 0.92, 0.8), 2))
	t.set_stylebox("focus", "LineEdit", _bar_box(Color(0.05, 0.045, 0.055, 0.85), 8, 16, APPLE, 3))
	t.set_color("font_color", "LineEdit", Color(1, 0.98, 0.92))
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.5))
	t.set_color("caret_color", "LineEdit", Color(1, 0.98, 0.92))
	return t


## Texte des barres aligné à gauche (comme sur les menus à étiquettes) : à appeler une fois l'arbre construit.
static func align_bars(node: Node) -> void:
	for c in node.get_children():
		if c is Button and not (c is CheckButton) and not (c is CheckBox):
			(c as Button).alignment = HORIZONTAL_ALIGNMENT_LEFT
		align_bars(c)
