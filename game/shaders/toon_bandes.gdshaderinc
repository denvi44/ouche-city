// Frouch City — éclairage cel-shading commun (agent 03).
// Trois paliers nets (plein jour / mi-teinte / ombre), bords anti-crénelés, ombres portées dures.
// Le palier d'ombre ne reçoit que la lumière ambiante (teintée par le cycle jour/nuit) :
// l'ombre prend donc la couleur du ciel, jamais du noir.

// Largeur de transition entre deux paliers (en N·L) : petite = bord franc.
const float LARGEUR_BORD = 0.012;

// Renvoie le facteur de lumière directe (0 = ombre, ~0,7 = mi-teinte, 1 = plein jour).
float toon_palier(float ndl, float attenuation, float seuil_mi, float seuil_plein, float mi_force) {
	// Ombre portée dure : on seuille l'atténuation de la shadow map.
	float ombre = smoothstep(0.45, 0.55, attenuation);
	float mi = smoothstep(seuil_mi - LARGEUR_BORD, seuil_mi + LARGEUR_BORD, ndl);
	float plein = smoothstep(seuil_plein - LARGEUR_BORD, seuil_plein + LARGEUR_BORD, ndl);
	return ombre * mix(mi * mi_force, 1.0, plein);
}
