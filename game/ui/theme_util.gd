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
