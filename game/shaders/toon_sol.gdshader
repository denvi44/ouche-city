// Frouch City — sols peints (chaussée, trottoir, herbe, pavés, gravier) : cel-shading + motifs procéduraux en aplats posterisés,
// dans l'esprit « dessin animé urbain » (bandes de teintes nettes, traits sombres francs, marquages peints). Aucune texture image.
// Les motifs sont calculés dans le repère du MONDE (continus d'une tuile à l'autre, identiques sur tous les pairs et sous Vulkan comme Metal).
// Chaussée : le ruban fournit UV (x = largeur en m depuis le bord gauche, y = abscisse le long de la route en m) et COLOR.r = largeur / 16.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_bandes.gdshaderinc"

uniform vec4 couleur : source_color = vec4(0.38, 0.38, 0.42, 1.0);
// 0 asphalte, 1 trottoir (dalles), 2 herbe, 3 pavés, 4 gravier
uniform int motif = 0;
uniform float seuil_mi_teinte : hint_range(-1.0, 1.0) = 0.02;
uniform float seuil_plein : hint_range(-1.0, 1.0) = 0.5;
uniform float gain : hint_range(0.0, 2.0) = 0.6;
uniform float mi_teinte_force : hint_range(0.0, 1.0) = 0.56;
// 0 : aplat uni (comparaison, option d'accessibilité « sols simples »)
uniform float details : hint_range(0.0, 1.0) = 1.0;

varying vec3 wp;
varying flat float largeur;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	largeur = COLOR.r * 16.0;
}

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// Distance au bord de la cellule de Voronoï la plus proche (fissures).
float fissure(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

float poster(float v, float n) {
	return floor(v * n) / n;
}

vec3 asphalte(vec3 base, vec2 uv) {
	vec2 q = wp.xz;
	float g = vnoise(q * 0.8) * 0.6 + vnoise(q * 3.3) * 0.4;
	vec3 c = base * (0.9 + 0.2 * poster(g, 4.0));                       // plages de teinte (usure, goudron frais)
	// Pièces de réfection : rectangles plus sombres, bord net.
	vec2 pc = floor(q / 9.0);
	float hp = h21(pc + 3.7);
	if (hp > 0.8) {
		vec2 o = vec2(h21(pc + 1.1), h21(pc + 2.2)) * 5.0;
		vec2 s = vec2(1.6 + 3.0 * h21(pc + 5.5), 1.0 + 2.0 * h21(pc + 6.6));
		vec2 l = abs(mod(q, 9.0) - o - s * 0.5);
		if (l.x < s.x * 0.5 && l.y < s.y * 0.5) {
			c *= 0.86;
			if (l.x > s.x * 0.5 - 0.05 || l.y > s.y * 0.5 - 0.05) c *= 0.8;
		}
	}
	// Fissures fines et rares.
	float f = fissure(q * 0.55);
	if (f < 0.02 && h21(floor(q * 0.55)) > 0.8) c *= 0.7;
	// Marquages : ligne centrale pointillée et lignes de rive, sur les routes assez larges.
	if (largeur > 4.4) {
		float lat = uv.x / largeur;
		float dash = step(0.45, fract(uv.y / 7.0));
		float eps = 0.012 + 0.03 / largeur;
		if (abs(lat - 0.5) < eps && dash < 0.5) c = mix(c, vec3(0.95, 0.88, 0.62), 0.92);
		if (largeur > 5.6 && (lat < 0.035 || lat > 0.965)) c = mix(c, vec3(0.9, 0.88, 0.8), 0.7);
	}
	return c;
}

vec3 trottoir(vec3 base, vec2 uv) {
	vec2 q = wp.xz;
	vec2 cell = floor(q / vec2(1.0, 0.6));
	float t = h21(cell);
	vec3 c = base * (0.95 + 0.07 * poster(t, 3.0));                      // dalles de teintes légèrement différentes
	vec2 f = fract(q / vec2(1.0, 0.6));
	float joint = min(min(f.x, 1.0 - f.x) * 1.0, min(f.y, 1.0 - f.y) * 0.6);
	if (joint < 0.025) c *= 0.8;
	// Bordure de trottoir : liseré clair au bord de la chaussée.
	return c;
}

vec3 herbe(vec3 base) {
	vec2 q = wp.xz;
	float g = vnoise(q * 0.35) * 0.55 + vnoise(q * 1.7) * 0.45;
	vec3 c = base * (0.86 + 0.28 * poster(g, 3.0));                      // plages claires et sombres, bords francs
	// Brins peints : petits traits sombres et clairs sur un maillage de 0,45 m.
	vec2 cell = floor(q / 0.45);
	vec2 f = fract(q / 0.45) - 0.5;
	float h = h21(cell);
	if (h > 0.86 && abs(f.x + (h - 0.9) * 2.0) < 0.05 && abs(f.y) < 0.2) c *= 0.7;
	if (h < 0.1 && abs(f.x) < 0.05 && abs(f.y + 0.05) < 0.17) c = c * 1.18 + 0.03;
	return c;
}

vec3 paves(vec3 base) {
	vec2 q = wp.xz / 0.32;
	float row = floor(q.y);
	q.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	vec3 c = base * (0.88 + 0.2 * poster(h21(cell), 3.0));
	if (min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) < 0.07) c *= 0.62;
	return c;
}

vec3 gravier(vec3 base) {
	vec2 q = wp.xz;
	vec3 c = base * (0.9 + 0.16 * poster(vnoise(q * 1.5), 3.0));
	if (h21(floor(q * 7.0)) > 0.9) c *= 0.74;
	if (h21(floor(q * 7.0) + 9.0) > 0.93) c = c * 1.15;
	return c;
}

void fragment() {
	vec3 c = couleur.rgb;
	vec3 d = c;
	if (motif == 0) d = asphalte(c, UV);
	else if (motif == 1) d = trottoir(c, UV);
	else if (motif == 2) d = herbe(c);
	else if (motif == 3) d = paves(c);
	else d = gravier(c);
	ALBEDO = mix(c, d, details);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	DIFFUSE_LIGHT += LIGHT_COLOR * gain * toon_palier(ndl, ATTENUATION, seuil_mi_teinte, seuil_plein, mi_teinte_force);
}
