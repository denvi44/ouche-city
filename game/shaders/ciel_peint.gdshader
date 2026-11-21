// Frouch City — ciel peint (agent 03) : dégradé en aplats, couleurs pilotées par le cycle jour/nuit.
shader_type sky;

uniform vec4 zenith : source_color = vec4(0.36, 0.6, 0.85, 1.0);
uniform vec4 horizon : source_color = vec4(0.78, 0.88, 0.93, 1.0);
uniform vec4 sol : source_color = vec4(0.45, 0.55, 0.4, 1.0);
uniform vec4 couleur_soleil : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// Nombre de bandes du dégradé (effet peint).
uniform float bandes = 6.0;

void sky() {
	float y = EYEDIR.y;
	float t = clamp(y, 0.0, 1.0);
	t = floor(pow(t, 0.6) * bandes) / bandes;
	vec3 c = mix(horizon.rgb, zenith.rgb, t);
	c = y < 0.0 ? mix(horizon.rgb, sol.rgb, clamp(-y * 6.0, 0.0, 1.0)) : c;
	float soleil = step(0.9992, dot(EYEDIR, LIGHT0_DIRECTION)) * float(LIGHT0_ENABLED);
	COLOR = mix(c, couleur_soleil.rgb, soleil);
}
