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
// Matière du mur nu : 0 enduit, 1 brique, 2 pierre de taille.
uniform int motif_mur = 0;

float mur_h(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float mur_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mur_h(i), mur_h(i + vec2(1, 0)), f.x), mix(mur_h(i + vec2(0, 1)), mur_h(i + vec2(1, 1)), f.x), f.y);
}

// Graffiti « bombe » : tache arrondie cernée de noir, zébrures de seconde couleur, coulures. Dans les 7 m de mur on en pose un sur environ un sur cinq.
vec3 mur_graffiti(vec3 c, vec2 m, float seed) {
	float cellx = floor(m.x / 7.0);
	float h = mur_h(vec2(cellx, seed * 13.0));
	if (h < 0.8 || m.y > 2.6) return c;
	float cx = (cellx + 0.5) * 7.0 + (mur_h(vec2(cellx, seed)) - 0.5) * 2.4;
	vec2 p = (m - vec2(cx, 1.25)) / vec2(0.95, 0.62);
	float sd = length(p * vec2(1.0, 1.15));
	vec3 pal[5] = vec3[5](vec3(0.95, 0.28, 0.6), vec3(0.15, 0.82, 0.9), vec3(0.98, 0.84, 0.18), vec3(0.58, 0.88, 0.22), vec3(0.98, 0.5, 0.15));
	int k = int(floor(mur_h(vec2(cellx, seed * 5.0)) * 5.0)) % 5;
	vec3 col1 = pow(pal[k], vec3(2.2));
	vec3 col2 = pow(pal[(k + 2) % 5], vec3(2.2));
	vec3 ink = pow(vec3(0.09, 0.07, 0.12), vec3(2.2));
	if (sd < 1.0) {
		if (sd > 0.84) return ink;
		if (abs(sin(p.x * 8.0 + p.y * 4.0)) < 0.22 && sd < 0.68) return col2;
		if (length(p - vec2(-0.38, 0.28)) < 0.12) return vec3(1.0);        // éclat
		return col1;
	}
	// Coulures sous la tache.
	if (p.y < -0.7 && p.y > -1.7 && sd < 1.25 && fract(p.x * 3.3 + h * 5.0) < 0.1) return col1;
	return c;
}

vec3 mur_nu(vec3 base, vec2 m, float seed) {
	vec3 c = base;
	if (motif_mur == 1) {
		float r = floor(m.y / 0.075);
		float off = mod(r, 2.0) * 0.11;
		vec2 b = vec2(floor((m.x + off) / 0.22), r);
		c *= 0.9 + 0.2 * floor(mur_h(b + seed * 7.0) * 3.0) / 3.0;
		if (fract(m.y / 0.075) < 0.13 || fract((m.x + off) / 0.22) < 0.05) c = mix(c, vec3(0.8, 0.7, 0.58), 0.55);   // joints clairs
	} else if (motif_mur == 2) {
		float r = floor(m.y / 0.4);
		float off = mod(r, 2.0) * 0.45;
		vec2 b = vec2(floor((m.x + off) / 0.9), r);
		c *= 0.93 + 0.1 * floor(mur_h(b + seed * 3.0) * 3.0) / 3.0;
		if (fract(m.y / 0.4) < 0.05 || fract((m.x + off) / 0.9) < 0.03) c *= 0.72;
	} else {
		float n = mur_noise(m * vec2(0.9, 0.9) + seed * 11.0) * 0.6 + mur_noise(m * 3.1 + seed) * 0.4;
		c *= 0.94 + 0.1 * floor(n * 3.0) / 3.0;                                 // enduit : plages de teinte
	}
	// Salissure en pied de mur : trois bandes nettes, de plus en plus sombres vers le sol.
	float pied = 1.0 - smoothstep(0.0, 1.0, m.y);
	c *= 1.0 - 0.2 * floor(pied * 3.0 + 0.5) / 3.0;
	return c;
}

// Données de façade identiques sur tout le mur : interpolation « flat » (pas de dégradé).
varying flat vec4 donnees_mur;

void vertex() {
	donnees_mur = COLOR;
}

void fragment() {
	vec4 p = facade_paint(UV, donnees_mur, style);
	vec3 mur = couleur.rgb;
	if (style != 2) {
		mur = mur_nu(couleur.rgb, UV, donnees_mur.r);
		mur = mur_graffiti(mur, UV, donnees_mur.r);
	}
	mur = mix(couleur.rgb, mur, details);
	ALBEDO = mix(mur, p.rgb, p.a * details);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR * gain * toon_palier(ndl, ATTENUATION, seuil_mi_teinte, seuil_plein, mi_teinte_force);
}
