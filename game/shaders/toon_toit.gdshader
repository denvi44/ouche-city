// Frouch City — toits peints (tuiles, ardoises) : rangs de tuiles, teinte propre à chaque tuile, joints sombres et taches de mousse.
// Calculé dans le repère du monde (les rangs suivent les courbes de niveau du toit, donc parallèles à l'égout). Aucune texture image.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

#include "res://shaders/toon_bandes.gdshaderinc"

uniform vec4 couleur : source_color = vec4(0.62, 0.33, 0.24, 1.0);
// 0 tuile, 1 ardoise
uniform int motif = 0;
uniform float seuil_mi_teinte : hint_range(-1.0, 1.0) = 0.02;
uniform float seuil_plein : hint_range(-1.0, 1.0) = 0.5;
uniform float gain : hint_range(0.0, 2.0) = 0.6;
uniform float mi_teinte_force : hint_range(0.0, 1.0) = 0.56;
uniform float details : hint_range(0.0, 1.0) = 1.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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

void fragment() {
	vec3 c = couleur.rgb;
	float pas = motif == 0 ? 0.2 : 0.17;                  // hauteur d'un rang (m, mesurée en altitude)
	float rang = floor(wp.y / pas);
	float along = wp.x * 0.8 + wp.z * 0.6;                 // abscisse approximative le long de l'égout
	float larg = motif == 0 ? 0.22 : 0.3;
	float col = floor((along + mod(rang, 2.0) * larg * 0.5) / larg);
	float t = h21(vec2(col, rang));
	vec3 d = c * (0.88 + 0.22 * floor(t * 4.0) / 4.0);     // chaque tuile a sa teinte
	float fr = fract(wp.y / pas);
	if (fr < 0.14) d *= 0.7;                               // ombre portée du rang du dessus
	float fc = fract((along + mod(rang, 2.0) * larg * 0.5) / larg);
	if (fc < 0.05) d *= 0.75;                              // joint vertical
	// Mousse : plages verdâtres sur quelques toits.
	float mousse = vnoise(wp.xz * 0.5 + 7.0);
	if (mousse > 0.78) d = mix(d, vec3(0.3, 0.4, 0.22), 0.45);
	ALBEDO = mix(c, d, details);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float p = toon_palier(ndl, ATTENUATION, seuil_mi_teinte, seuil_plein, mi_teinte_force);
	DIFFUSE_LIGHT += LIGHT_COLOR * gain * p * toon_hachure(FRAGCOORD, p);
}
