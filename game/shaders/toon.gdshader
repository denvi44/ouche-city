// Ouche City — toon shader de base (agent 03).
// Éclairage quantifié en 3 paliers + rim light, ombres dures, aucune texture PBR.
// Identique sous Vulkan (Windows), Metal (macOS) et Compatibility (captures CI de secours).
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

// Couleur d'aplat principale.
uniform vec4 couleur : source_color = vec4(0.94, 0.89, 0.76, 1.0);
// Couleur de l'ombre (multipliée) : on teinte vers le bleu plutôt que vers le noir.
uniform vec4 teinte_ombre : source_color = vec4(0.55, 0.58, 0.75, 1.0);
// Seuils des trois paliers de lumière (ombre / mi-teinte / plein jour).
uniform float seuil_mi_teinte : hint_range(-1.0, 1.0) = 0.05;
uniform float seuil_plein : hint_range(-1.0, 1.0) = 0.45;
// Intensité et largeur du liseré de contre-jour (rim light).
uniform float rim_force : hint_range(0.0, 1.0) = 0.25;
uniform float rim_largeur : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	ALBEDO = couleur.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	// Ombre portée dure : on seuille l'atténuation.
	float ombre_portee = step(0.5, ATTENUATION);
	float palier = ndl > seuil_plein ? 1.0 : (ndl > seuil_mi_teinte ? 0.6 : 0.0);
	palier *= ombre_portee;
	vec3 sombre = ALBEDO * teinte_ombre.rgb;
	vec3 c = mix(sombre, ALBEDO, palier);
	// Rim light : bord du modèle tourné vers la lumière.
	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	rim = step(1.0 - rim_largeur, rim) * clamp(ndl + 0.3, 0.0, 1.0) * rim_force;
	DIFFUSE_LIGHT += (c / max(ALBEDO, vec3(0.001)) + vec3(rim)) * LIGHT_COLOR / PI;
}
