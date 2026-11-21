// Frouch City — fenêtres, volets, portes, vitrines : façades peintes (agent 03).
// Aucune texture image : tout est dessiné en aplats par le shader, dans l'esprit « peint à la main ».
//
// Entrées (par mur, fournies par CityBuilder) :
//   m = UV du mur : x = abscisse le long du mur (m), y = hauteur depuis le sol (m)
//   d = COLOR des sommets : r = graine du bâtiment, g = longueur du mur / 100,
//       b = porte (0 aucune, 0,5 porte, 1 porte + vitrine), a = hauteur d'égout / 40
//   style : 0 maison, 1 commerce (vitrine + store), 2 église
// Sortie : rgb = couleur peinte, a = 1 là où quelque chose est peint, 0 sinon (mur nu).

float fd_h(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

// Les couleurs sont écrites en sRGB (lisibles) puis converties.
vec3 fd_srgb(vec3 c) {
	return pow(c, vec3(2.2));
}

vec3 fd_volet(float seed) {
	float k = floor(fd_h(seed * 91.7) * 5.0);
	if (k < 1.0) return fd_srgb(vec3(0.27, 0.42, 0.56));   // bleu-gris
	if (k < 2.0) return fd_srgb(vec3(0.30, 0.50, 0.33));   // vert
	if (k < 3.0) return fd_srgb(vec3(0.66, 0.22, 0.20));   // rouge
	if (k < 4.0) return fd_srgb(vec3(0.93, 0.90, 0.82));   // blanc cassé
	return fd_srgb(vec3(0.42, 0.30, 0.22));                // brun
}

vec3 fd_porte(float seed) {
	float k = floor(fd_h(seed * 53.3 + 7.0) * 5.0);
	if (k < 1.0) return fd_srgb(vec3(0.62, 0.20, 0.18));   // rouge
	if (k < 2.0) return fd_srgb(vec3(0.22, 0.38, 0.55));   // bleu
	if (k < 3.0) return fd_srgb(vec3(0.24, 0.45, 0.30));   // vert
	if (k < 4.0) return fd_srgb(vec3(0.38, 0.26, 0.18));   // bois
	return fd_srgb(vec3(0.84, 0.66, 0.24));                // moutarde
}

const float FD_CREME_R = 0.95;

vec4 fd_vitre(float cx, float vy, float y0, float y1, float half_w) {
	// Cadre crème, croisillons, reflet en biais : un seul aplat par zone.
	vec3 creme = fd_srgb(vec3(0.95, 0.92, 0.84));
	float fr = 0.07;
	if (abs(cx) > half_w - fr || vy < y0 + fr || vy > y1 - fr) return vec4(creme, 1.0);
	float cy = 0.5 * (y0 + y1);
	if (abs(cx) < 0.025 || abs(vy - cy) < 0.025) return vec4(creme, 1.0);
	vec3 verre = fd_srgb(vec3(0.30, 0.40, 0.52));
	vec3 reflet = fd_srgb(vec3(0.55, 0.68, 0.80));
	float diag = cx + (vy - cy) * 0.55;
	if (diag > 0.12 && diag < 0.24) return vec4(reflet, 1.0);
	return vec4(verre, 1.0);
}

vec4 facade_paint(vec2 m, vec4 d, int style) {
	// Les valeurs viennent d'octets (0..255) : on les quantifie pour que le hachage ne bascule
	// jamais sur une erreur d'arrondi d'interpolation (sinon : grain de pixels aux seuils).
	vec4 q = floor(d * 255.0 + 0.5) / 255.0;
	float seed = q.r;
	float len = q.g * 100.0;
	float door = q.b;
	float eave = q.a * 40.0;
	if (eave < 2.4 || len < 2.2) return vec4(0.0);
	bool church = style == 2;
	float floor_h = church ? 6.0 : 3.0;
	float n = max(floor(len / (church ? 4.2 : 2.8) + 0.5), 1.0);
	float pitch = len / n;
	float cell = clamp(floor(m.x / pitch), 0.0, n - 1.0);
	float cx = m.x - (cell + 0.5) * pitch;
	float fl = floor(m.y / floor_h);
	float vy = m.y - fl * floor_h;
	float floors = max(floor((eave - 0.4) / floor_h), 1.0);
	if (fl >= floors) return vec4(0.0);
	// Travée de la porte : arithmétique entière, identique à BuildingDetails.door_cell (l'auvent 3D suit la porte peinte).
	int seed_i = int(seed * 255.0 + 0.5);
	float door_cell = float((seed_i * 37 + 11) % max(int(n), 1));
	bool ground = fl < 0.5;
	bool is_door = door > 0.25 && ground && abs(cell - door_cell) < 0.5;
	vec3 creme = fd_srgb(vec3(0.95, 0.92, 0.84));
	vec3 pierre = fd_srgb(vec3(0.78, 0.74, 0.66));

	// --- Portes ---
	if (is_door) {
		float dw = church ? 0.85 : 0.52;
		float dh = church ? 3.1 : 2.2;
		if (vy < 0.14 && abs(cx) < dw + 0.32) return vec4(pierre, 1.0);                 // marche
		if (abs(cx) < dw + 0.13 && vy < dh + 0.14) {
			bool arch = church && vy > dh - dw && (cx * cx + (vy - (dh - dw)) * (vy - (dh - dw)) > dw * dw);
			if (arch) return vec4(0.0);
			if (abs(cx) > dw || vy > dh) return vec4(creme, 1.0);                       // encadrement
			vec3 pc = church ? fd_srgb(vec3(0.30, 0.20, 0.14)) : fd_porte(seed);
			if (!church && vy > 1.45 && vy < dh - 0.15 && abs(cx) < dw - 0.2) {
				return fd_vitre(cx, vy, 1.45, dh - 0.15, dw - 0.13);                    // petit vitrage
			}
			if (length(vec2(cx - dw * 0.7, vy - 1.0)) < 0.05) return vec4(creme, 1.0);   // poignée
			if (abs(cx) < 0.02 || (!church && abs(vy - 0.55) < 0.015) || (church && fract(vy * 1.3) < 0.07)) return vec4(pc * 0.6, 1.0);
			return vec4(pc, 1.0);
		}
	}

	// --- Commerce : vitrine et store au rez-de-chaussée ---
	if (style == 1 && ground) {
		float half_v = pitch * 0.5 - 0.3;
		if (vy > 2.38 && vy < 2.85 && abs(cx) < pitch * 0.5) {                          // store à rayures
			float stripe = step(0.5, fract((m.x + seed * 3.0) * 2.2));
			vec3 rouge = fd_srgb(vec3(0.76, 0.22, 0.18));
			return vec4(mix(creme, rouge, stripe), 1.0);
		}
		if (vy > 0.3 && vy < 2.25 && abs(cx) < half_v) {
			float w = half_v;
			vec4 g = fd_vitre(cx, vy, 0.3, 2.25, w);
			// vitrine : pas de croisillon horizontal, un meneau central seulement
			return g;
		}
		return vec4(0.0);
	}

	// --- Fenêtres, volets, appuis ---
	float ww = church ? 0.42 : 0.5;
	float wy0 = church ? 1.6 : 0.9;
	float wy1 = church ? 4.9 : 2.3;
	bool arch_top = church && vy > wy1 - ww;
	float arch_d = length(vec2(cx, vy - (wy1 - ww)));
	bool in_w = abs(cx) < ww && vy > wy0 && vy < wy1 && !(arch_top && arch_d > ww);
	if (in_w) {
		if (church) {
			vec3 vitrail = fd_srgb(vec3(0.28, 0.36, 0.62));
			if (abs(cx) < 0.03 || abs(vy - 3.2) < 0.03) return vec4(pierre * 0.8, 1.0);
			if (fract(vy * 0.9) < 0.5 && abs(cx) > 0.2) return vec4(fd_srgb(vec3(0.62, 0.26, 0.24)), 1.0);
			return vec4(vitrail, 1.0);
		}
		return fd_vitre(cx, vy, wy0, wy1, ww);
	}
	if (!church) {
		if (vy > wy0 - 0.12 && vy < wy0 && abs(cx) < ww + 0.12) return vec4(creme, 1.0);   // appui
		bool shutters = fd_h(seed * 7.0 + cell * 3.1 + fl * 5.7) > 0.3;
		if (shutters && abs(cx) >= ww && abs(cx) < ww + 0.4 && vy > wy0 - 0.04 && vy < wy1 + 0.04) {
			vec3 vc = fd_volet(seed);
			if (fract(vy * 7.0) < 0.14) vc *= 0.72;                                    // lames
			return vec4(vc, 1.0);
		}
	}
	return vec4(0.0);
}
