// Frouch City — contour « inverted hull » du décor (agent 03).
// Le maillage de contour est une copie du bâti dont chaque sommet porte, dans COLOR, une normale
// LISSÉE (moyenne des faces voisines) : en gonflant le long de cette normale, les coins ne
// s'ouvrent pas. Les faces avant sont masquées (cull_front) : seule reste une bordure sombre.
// L'épaisseur croît avec la distance pour rester d'environ 2 px à toute distance (1080p).
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled;

uniform vec4 couleur_contour : source_color = vec4(0.13, 0.09, 0.08, 1.0);
// Épaisseur minimale (m) et croissance par mètre de distance.
uniform float epaisseur_min = 0.035;
uniform float epaisseur_par_metre = 0.0028;
uniform float epaisseur_max = 0.7;

void vertex() {
	vec3 n = COLOR.rgb * 2.0 - 1.0;
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float e = clamp(epaisseur_min + dist * epaisseur_par_metre, epaisseur_min, epaisseur_max);
	VERTEX += normalize(n) * e;
}

void fragment() {
	ALBEDO = couleur_contour.rgb;
}
