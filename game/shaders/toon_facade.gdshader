// Frouch City — mur à façade peinte (agent 03) : aplat de couleur + fenêtres, volets, portes.
// Éclairage cel-shading identique à toon.gdshader. UV et COLOR fournis par CityBuilder.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_bandes.gdshaderinc"
#include "res://shaders/facade_details.gdshaderinc"

uniform vec4 couleur : source_color = vec4(0.93, 0.88, 0.76, 1.0);
// 0 maison, 1 commerce (vitrine, store), 2 église
uniform int style = 0;
uniform float seuil_mi_teinte : hint_range(-1.0, 1.0) = 0.02;
uniform float seuil_plein : hint_range(-1.0, 1.0) = 0.5;
uniform float gain : hint_range(0.0, 2.0) = 0.6;
uniform float mi_teinte_force : hint_range(0.0, 1.0) = 0.56;
// Mettre à 0 pour retirer les détails (comparaison avant / après, option d'accessibilité « façades simples »).
uniform float details : hint_range(0.0, 1.0) = 1.0;

// Données de façade identiques sur tout le mur : interpolation « flat » (pas de dégradé).
varying flat vec4 donnees_mur;

void vertex() {
	donnees_mur = COLOR;
}

void fragment() {
	vec4 p = facade_paint(UV, donnees_mur, style);
	ALBEDO = mix(couleur.rgb, p.rgb, p.a * details);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR * gain * toon_palier(ndl, ATTENUATION, seuil_mi_teinte, seuil_plein, mi_teinte_force);
}
