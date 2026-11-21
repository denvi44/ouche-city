// Frouch City — toon shader de base (agent 03).
// Vrai cel-shading : 3 paliers nets, ombres portées dures, liseré de contre-jour (rim),
// reflet « peint » optionnel pour les surfaces vernies (véhicules). Aucune texture PBR.
// Identique sous Vulkan (Windows) et Metal (macOS).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_bandes.gdshaderinc"

// Couleur d'aplat principale.
uniform vec4 couleur : source_color = vec4(0.94, 0.89, 0.76, 1.0);
// Seuils des paliers sur N·L : au-dessus de « plein » = plein jour, au-dessus de « mi » = mi-teinte.
uniform float seuil_mi_teinte : hint_range(-1.0, 1.0) = 0.02;
uniform float seuil_plein : hint_range(-1.0, 1.0) = 0.5;
// Luminosité de la mi-teinte (1 = identique au plein jour).
uniform float mi_teinte_force : hint_range(0.0, 1.0) = 0.56;
// Gain global de la lumière directe (compense l'énergie du soleil).
uniform float gain : hint_range(0.0, 2.0) = 0.6;
// Rim light : liseré clair sur les bords tournés vers la lumière.
uniform float rim_force : hint_range(0.0, 1.0) = 0.22;
uniform float rim_largeur : hint_range(0.0, 1.0) = 0.3;
// Reflet peint (0 = aucun) : taille de la tache dure, 0.04 pour un véhicule.
uniform float reflet_force : hint_range(0.0, 1.0) = 0.0;
uniform float reflet_taille : hint_range(0.0, 0.2) = 0.05;

void fragment() {
	ALBEDO = couleur.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float p = toon_palier(ndl, ATTENUATION, seuil_mi_teinte, seuil_plein, mi_teinte_force);
	vec3 direct = LIGHT_COLOR * gain * p * toon_hachure(FRAGCOORD, p);
	// Rim : bord de l'objet (N·V faible) du côté éclairé.
	float bord = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(1.0 - rim_largeur - 0.01, 1.0 - rim_largeur + 0.01, bord) * smoothstep(-0.1, 0.3, ndl) * rim_force;
	// Reflet : tache dure autour de la direction du demi-vecteur.
	vec3 h = normalize(LIGHT + VIEW);
	float spec = smoothstep(1.0 - reflet_taille - 0.005, 1.0 - reflet_taille + 0.005, dot(NORMAL, h)) * reflet_force * step(0.5, ATTENUATION);
	DIFFUSE_LIGHT += direct + LIGHT_COLOR * rim + LIGHT_COLOR * spec / max(ALBEDO.r + ALBEDO.g + ALBEDO.b, 0.3) * 1.5;
}
