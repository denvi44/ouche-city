class_name DroneShots
extends RefCounted
## Plans de drone de l'écran titre : une liste de plans (orbite, survol, grue) calculés autour des lieux du village.
## Tout est pur et testé (qa/unit) : `shots(lieux)` décrit les plans, `pose(plan, u, sol)` donne la caméra à l'instant u ∈ [0, 1].
## Repère du jeu : x est, z sud, y haut. `sol` est une fonction (x, z) -> altitude du terrain.

const MIN_CLEARANCE := 14.0     # le drone reste au moins à 14 m au-dessus du sol sous lui (clochers et cheminées compris)
const DEFAULT_DURATION := 11.0


## `lieux` : identifiant de POI -> Vector2 (x, z). Les plans dont le lieu manque sont ignorés ;
## `centre` sert de repli pour un plan d'ensemble toujours présent.
static func shots(lieux: Dictionary, centre: Vector2) -> Array:
	var out: Array = []
	var church: Vector2 = lieux.get("eglise", centre)
	out.append({"nom": "Le clocher", "kind": "orbit", "centre": church, "rayon": 90.0, "h0": 55.0, "h1": 62.0, "a0": -0.6, "a1": 0.55, "regard": 18.0, "fov": 55.0, "duree": 12.0})
	if lieux.has("spawn_rue_sainte_foy"):
		var s: Vector2 = lieux.spawn_rue_sainte_foy
		out.append({"nom": "La rue Sainte-Foy", "kind": "fly", "de": s + Vector2(-12, 110), "vers": s + Vector2(8, -150), "h0": 34.0, "h1": 30.0, "regard": 4.0, "fov": 62.0, "duree": 13.0})
	if lieux.has("mairie"):
		out.append({"nom": "La mairie", "kind": "crane", "centre": lieux.mairie, "rayon": 62.0, "h0": 16.0, "h1": 70.0, "a0": 2.4, "a1": 3.2, "regard": 10.0, "fov": 58.0, "duree": 11.0})
	if lieux.has("usine_calva"):
		out.append({"nom": "La distillerie", "kind": "orbit", "centre": lieux.usine_calva, "rayon": 70.0, "h0": 42.0, "h1": 36.0, "a0": 0.8, "a1": -0.4, "regard": 12.0, "fov": 55.0, "duree": 11.0})
	if lieux.has("gare_pays_frouch") and lieux.has("etang_oies"):
		out.append({"nom": "La gare et la mare aux oies", "kind": "fly", "de": lieux.etang_oies + Vector2(-40, 30), "vers": lieux.gare_pays_frouch + Vector2(60, -20), "h0": 26.0, "h1": 30.0, "regard": 2.0, "fov": 64.0, "duree": 12.0})
	if lieux.has("carriere_pierres"):
		out.append({"nom": "La carrière", "kind": "orbit", "centre": lieux.carriere_pierres, "rayon": 125.0, "h0": 70.0, "h1": 56.0, "a0": 3.9, "a1": 2.8, "regard": -8.0, "fov": 58.0, "duree": 12.0})
	out.append({"nom": "Le village", "kind": "orbit", "centre": church, "rayon": 300.0, "h0": 170.0, "h1": 140.0, "a0": 1.2, "a1": 2.4, "regard": 0.0, "fov": 50.0, "duree": 14.0})
	return out


static func smooth(u: float) -> float:
	var x := clampf(u, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Caméra du plan à l'instant `u` : {"pos": Vector3, "cible": Vector3, "fov": float}.
static func pose(shot: Dictionary, u: float, sol: Callable) -> Dictionary:
	var x := clampf(u, 0.0, 1.0)
	var pos := Vector3.ZERO
	var cible := Vector3.ZERO
	match str(shot.kind):
		"fly":
			var p: Vector2 = (shot.de as Vector2).lerp(shot.vers, x)
			var ahead: Vector2 = (shot.de as Vector2).lerp(shot.vers, minf(1.0, x + 0.22))
			var h: float = lerpf(float(shot.h0), float(shot.h1), x)
			pos = Vector3(p.x, float(sol.call(p.x, p.y)) + h, p.y)
			cible = Vector3(ahead.x, float(sol.call(ahead.x, ahead.y)) + float(shot.regard), ahead.y)
		_:
			# orbite et grue : cercle autour du centre, altitude et angle en fondu enchaîné doux
			var e := smooth(x) if shot.kind == "crane" else x
			var a: float = lerpf(float(shot.a0), float(shot.a1), e)
			var c: Vector2 = shot.centre
			var p := c + Vector2(sin(a), cos(a)) * float(shot.rayon)
			var h: float = lerpf(float(shot.h0), float(shot.h1), e)
			pos = Vector3(p.x, float(sol.call(c.x, c.y)) + h, p.y)
			cible = Vector3(c.x, float(sol.call(c.x, c.y)) + float(shot.regard), c.y)
	# Léger balancement du drone, puis garde-fou : jamais sous le sol + marge.
	pos.y += sin(x * TAU * 1.5) * 0.4
	var floor_y: float = float(sol.call(pos.x, pos.z)) + MIN_CLEARANCE
	pos.y = maxf(pos.y, floor_y)
	return {"pos": pos, "cible": cible, "fov": float(shot.fov)}
