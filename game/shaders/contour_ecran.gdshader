// Ouche City — contours du décor en post-process, par discontinuité de profondeur (agent 03).
// Appliqué sur un quad plein écran (MeshInstance3D enfant de la caméra).
// Profondeur seule : fonctionne en Forward+ comme en Compatibility. Budget : < 1,5 ms 1080p M1.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, skip_vertex_transform;

uniform sampler2D tex_profondeur : hint_depth_texture, filter_nearest;
uniform sampler2D tex_ecran : hint_screen_texture, filter_nearest;
uniform vec4 couleur_contour : source_color = vec4(0.12, 0.09, 0.08, 1.0);
// Épaisseur en pixels (à 1080p ; ajustée à la résolution).
uniform float epaisseur_px : hint_range(0.5, 4.0) = 1.2;
// Sensibilité : écart relatif de distance au-delà duquel on trace un trait.
uniform float seuil : hint_range(0.001, 0.5) = 0.06;
// Au-delà de cette distance (m), les traits s'estompent (lisibilité du lointain).
uniform float distance_fondu = 220.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float distance_lineaire(vec2 uv, mat4 inv_proj) {
	float d = texture(tex_profondeur, uv).r;
	vec4 ndc = vec4(uv * 2.0 - 1.0, d, 1.0);
	vec4 vue = inv_proj * ndc;
	return -vue.z / vue.w;
}

void fragment() {
	vec2 px = epaisseur_px * (VIEWPORT_SIZE.y / 1080.0) / VIEWPORT_SIZE;
	float c = distance_lineaire(SCREEN_UV, INV_PROJECTION_MATRIX);
	float g = distance_lineaire(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float d = distance_lineaire(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
	float h = distance_lineaire(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float b = distance_lineaire(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
	float ecart = max(max(abs(g - c), abs(d - c)), max(abs(h - c), abs(b - c))) / max(c, 0.01);
	float trait = step(seuil, ecart) * (1.0 - smoothstep(distance_fondu * 0.6, distance_fondu, c));
	vec3 fond = texture(tex_ecran, SCREEN_UV).rgb;
	ALBEDO = mix(fond, couleur_contour.rgb, trait);
}
