// Frouch City — contour « inverted hull » pour personnages et véhicules (agent 03).
// À utiliser en next_pass d'un matériau toon : on gonfle le maillage le long des normales
// et on n'affiche que les faces arrière, en aplat sombre.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 couleur_contour : source_color = vec4(0.12, 0.09, 0.08, 1.0);
// Épaisseur du contour en mètres (personnage : 0.025 ; véhicule : 0.04).
uniform float epaisseur : hint_range(0.0, 0.2) = 0.025;

void vertex() {
	VERTEX += NORMAL * epaisseur;
}

void fragment() {
	ALBEDO = couleur_contour.rgb;
}
