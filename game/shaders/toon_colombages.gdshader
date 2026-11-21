// Ouche City — façade normande à colombages (agent 03).
// Motif peint procédural : poutres brun foncé sur torchis crème. UV des murs en mètres
// (u = longueur le long du mur, v = hauteur depuis le sol), fournis par tile_loader.gd.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_bandes.gdshaderinc"
#include "res://shaders/facade_details.gdshaderinc"

uniform vec4 torchis : source_color = vec4(0.93, 0.85, 0.68, 1.0);
uniform vec4 poutre : source_color = vec4(0.27, 0.18, 0.12, 1.0);
// Espacement des poteaux verticaux (m) et hauteur d'étage (m).
uniform float pas_poteaux = 1.25;
uniform float hauteur_etage = 3.0;
// Épaisseur des poutres (m).
uniform float epaisseur = 0.14;
uniform float details : hint_range(0.0, 1.0) = 1.0;
uniform float seuil_mi_teinte : hint_range(-1.0, 1.0) = 0.02;
uniform float seuil_plein : hint_range(-1.0, 1.0) = 0.5;

float bande(float x, float largeur) {
	float d = abs(fract(x) - 0.5) * 2.0;
	return step(1.0 - largeur, d);
}

varying flat vec4 donnees_mur;

void vertex() {
	donnees_mur = COLOR;
}

void fragment() {
	vec2 m = UV;
	// Normale quasi verticale = toit ou sol : pas de motif.
	float est_mur = step(abs(NORMAL.y), 0.5);
	float etage = m.y / hauteur_etage;
	float sabliere = bande(etage, epaisseur * 2.0 / hauteur_etage);
	float poteau = bande(m.x / pas_poteaux + 0.5, epaisseur * 2.0 / pas_poteaux);
	// Croix de Saint-André un panneau sur trois : diagonales dans la cellule.
	vec2 cell = vec2(m.x / pas_poteaux, etage);
	vec2 f = fract(cell);
	float idx = mod(floor(cell.x) + floor(cell.y) * 3.0, 4.0);
	float diag = idx < 0.5 ? max(step(abs(f.x - f.y), epaisseur / pas_poteaux), step(abs(f.x - (1.0 - f.y)), epaisseur / pas_poteaux)) : 0.0;
	// Soubassement en pierre peinte (60 cm).
	float soubassement = step(m.y, 0.6);
	float bois = clamp(sabliere + poteau + diag, 0.0, 1.0) * est_mur * (1.0 - soubassement);
	vec3 pierre = vec3(0.72, 0.68, 0.6);
	vec3 base = mix(torchis.rgb, pierre, soubassement * est_mur);
	vec3 mur = mix(base, poutre.rgb, bois);
	vec4 p = facade_paint(UV, donnees_mur, 0);
	ALBEDO = mix(mur, p.rgb, p.a * details);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR * 0.6 * toon_palier(ndl, ATTENUATION, seuil_mi_teinte, seuil_plein, 0.56);
}
