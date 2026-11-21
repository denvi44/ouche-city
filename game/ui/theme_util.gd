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


static func _md_button(t: Theme, variation: String, bg: Color, fg: Color, shadow: int) -> void:
	t.set_type_variation(variation, "Button")
	var hover := bg.lerp(fg, 0.08)
	var press := bg.lerp(fg, 0.16)
	t.set_stylebox("normal", variation, _md_box(bg, 28, 12, 28, Color(0, 0, 0, 0), 0, shadow))
	t.set_stylebox("hover", variation, _md_box(hover, 28, 12, 28, Color(0, 0, 0, 0), 0, shadow + 2 if shadow > 0 else 0))
	t.set_stylebox("pressed", variation, _md_box(press, 28, 12, 28))
	# Focus clavier / manette : contour épais bien visible (accessibilité), jamais la seule indication d'état.
	var focus := _md_box(hover, 28, 12, 28, MD_ON_SURFACE, 3, shadow)
	t.set_stylebox("focus", variation, focus)
	t.set_stylebox("disabled", variation, _md_box(Color(MD_ON_SURFACE, 0.10), 28, 12, 28))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		t.set_color(c, variation, fg)
	t.set_color("font_disabled_color", variation, Color(MD_ON_SURFACE, 0.45))


static func make_material_theme() -> Theme:
	var t := Theme.new()
	var s := Settings.text_scale
	t.default_font_size = int(24 * s)
	t.set_color("font_color", "Label", MD_ON_SURFACE)
	# Carte : grande surface arrondie translucide (on devine le drone derrière), ombre portée.
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", _md_box(Color(MD_SURFACE, 0.86), 32, 28, 32, Color(1, 1, 1, 0.55), 1, 18))
	# Puce d'information (légende de plan, crédits) : petite pastille sombre translucide.
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", _md_box(Color(0.08, 0.07, 0.08, 0.62), 16, 6, 16))
	t.set_type_variation("ChipLabel", "Label")
	t.set_color("font_color", "ChipLabel", Color(1, 1, 1, 0.95))
	_md_button(t, "FilledButton", MD_PRIMARY, MD_ON_PRIMARY, 6)
	_md_button(t, "TonalButton", MD_TONAL, MD_ON_TONAL, 0)
	_md_button(t, "TextButton", Color(0, 0, 0, 0), MD_PRIMARY, 0)
	# Bouton par défaut = tonal.
	t.set_stylebox("normal", "Button", _md_box(MD_TONAL, 28, 12, 28))
	t.set_stylebox("hover", "Button", _md_box(MD_TONAL.lerp(MD_ON_TONAL, 0.08), 28, 12, 28))
	t.set_stylebox("pressed", "Button", _md_box(MD_TONAL.lerp(MD_ON_TONAL, 0.16), 28, 12, 28))
	t.set_stylebox("focus", "Button", _md_box(MD_TONAL.lerp(MD_ON_TONAL, 0.08), 28, 12, 28, MD_ON_SURFACE, 3))
	t.set_stylebox("disabled", "Button", _md_box(Color(MD_ON_SURFACE, 0.10), 28, 12, 28))
	for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		t.set_color(c, "Button", MD_ON_TONAL)
	t.set_color("font_disabled_color", "Button", Color(MD_ON_SURFACE, 0.45))
	# Champ de texte « outlined ».
	var field := _md_box(Color(1, 1, 1, 0.55), 14, 10, 16, MD_OUTLINE, 2)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", _md_box(Color(1, 1, 1, 0.8), 14, 10, 16, MD_PRIMARY, 3))
	t.set_color("font_color", "LineEdit", MD_ON_SURFACE)
	t.set_color("font_placeholder_color", "LineEdit", Color(MD_ON_SURFACE, 0.55))
	t.set_color("caret_color", "LineEdit", MD_PRIMARY)
	return t
