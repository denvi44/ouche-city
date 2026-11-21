"""Lieux fictifs d'Ouche City (agent 01, validé narration 07).

Tous les noms de bâtiments, commerces et monuments sont inventés : aucun nom réel n'est repris,
qu'il vienne de l'IGN, d'OSM ou d'ailleurs. Seuls les noms de rues réels sont conservés.
L'attribution est déterministe (hachage de l'identifiant du bâtiment) : même ville à chaque génération.
Humour « Normandie profonde » : tendre, jamais méprisant.
"""
from __future__ import annotations

import hashlib
import math

from shapely.geometry import LineString, Point, Polygon
from shapely.ops import nearest_points

# Catégorie -> enseignes inventées.
ENSEIGNES = {
    "boulangerie": ["Au Fournil de Mémère", "La Mie du Bocage", "Boulangerie du Pressoir", "Le Pain Bénit",
                    "Aux Croûtes Dorées"],
    "boucherie": ["Boucherie Lecochon", "Charcuterie Andouille & Fils", "Au Jambon Qui Chante"],
    "cafe": ["Le Bistrot du Bocage", "Café de la Mare aux Canards", "Bar-Tabac Le Pommier Penché",
             "Le Petit Trou Normand", "Café des Sports et du Tiercé"],
    "epicerie": ["Épicerie Chez Raymonde", "Supérette du Rond-Point", "L'Épicerie des Quatre Vaches"],
    "coiffure": ["Tif'Ouche", "Le Bigoudi d'Or", "Hair du Bocage"],
    "fleuriste": ["Les Pétales Pressés", "Au Bouquet de Pommiers"],
    "pharmacie": ["Pharmacie de la Pomme Verte", "Pharmacie du Donjon"],
    "garage": ["Garage Bielle et Pistons", "Mécanique Gaston Frères"],
    "presse": ["Presse L'Écho du Bocage", "Le Kiosque à Ragots"],
    "creperie": ["Crêperie Bolée & Galette", "La Galette Qui Roule"],
    "brocante": ["Brocante Tout Doit Disparaître (depuis 1987)", "Le Grenier de Tata Odette"],
    "banque": ["Caisse Mutuelle du Pays d'Ouche", "Crédit Pommier"],
    "immobilier": ["Immo Colombages", "Agence Clé des Champs"],
    "fromagerie": ["Fromagerie La Croûte Fleurie", "Au Plateau du Dimanche"],
    "quincaillerie": ["Quincaillerie Clou & Cie", "Bricol'Ouche"],
    "restaurant": ["Restaurant L'Auberge du Cidre Doux", "La Table de Fernand", "Pizzeria Mamma Normandia"],
    "vetements": ["Boutique Laine et Bottes", "Mode Bocage Chic"],
    "opticien": ["Optique Yeux de Lynx"],
}

# Qualificatifs pour décliner une enseigne déjà prise (la ville compte plus de commerces que de noms).
QUALIFICATIFS = ["& Fils", "Père et Fille", "depuis 1962", "Express", "du Marché", "du Centre", "de la Gare",
                 "Bis", "Le Retour", "du Haut", "du Bas", "des Halles", "de la Mare", "du Lavoir",
                 "Saint-Michel", "des Vergers", "de l'Église", "du Pont", "de la Place", "Chez Nous"]

# Lieux de mission rattachés à des bâtiments réels de la zone (identifiants des missions/*.json).
LIEUX_MISSION = [
    ("auto_bling_27", "shop", "Auto Bling 27", ["m02_tuning_samedi"]),
    ("comite_fetes", "mission_start", "Comité des fêtes", ["m01_calva_gege"]),
]

MONUMENTS = {
    "eglise": "Église Notre-Dame-du-Bocage",
    "public": "Salle des fêtes Fernand-Lepommier",
}


def _h(*parts) -> int:
    return int(hashlib.sha1("|".join(map(str, parts)).encode()).hexdigest()[:12], 16)


def _r(v: float) -> float:
    return round(float(v), 2)


def emplacement_enseigne(footprint, routes: list[LineString]) -> tuple[tuple[float, float], float]:
    """Point de façade le plus proche de la route la plus proche, et angle (rad) de la façade vers la route.

    L'angle suit la convention Godot : rotation autour de Y pour que +Z local regarde la rue.
    """
    poly = Polygon(footprint)
    if not routes:
        c = poly.centroid
        return (c.x, c.y), 0.0
    route = min(routes, key=lambda r: r.distance(poly))
    sur_facade, sur_route = nearest_points(poly.exterior, route)
    dx, dz = sur_route.x - sur_facade.x, sur_route.y - sur_facade.y
    n = math.hypot(dx, dz)
    if n < 1e-6:
        c = poly.centroid
        dx, dz = sur_facade.x - c.x, sur_facade.y - c.y
        n = math.hypot(dx, dz) or 1.0
    dx, dz = dx / n, dz / n
    pos = (sur_facade.x + dx * 0.35, sur_facade.y + dz * 0.35)
    return pos, math.atan2(dx, dz)


def lieux_fictifs(tuiles: dict, taille: float) -> list[dict]:
    """POI fictifs pour les commerces et monuments des tuiles construites."""
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"]
              if r["kind"] not in ("footway", "track")]
    batiments = sorted((b for t in tuiles.values() for b in t["buildings"]), key=lambda b: b["id"])
    commerces = [b for b in batiments if b["typology"] == "commerce"]
    commerces.sort(key=lambda b: _h("ordre", b["id"]))
    pois: list[dict] = []
    deja: set[str] = set()

    def ajout(b, pid, kind, label, missions=None):
        (x, z), facing = emplacement_enseigne(b["footprint"], routes)
        poi = {"id": pid, "kind": kind, "label": label, "position": [_r(x), _r(z)],
               "tile": f"{int(x // taille)}_{int(z // taille)}", "radius": 4.0, "source": "design",
               "building": b["id"], "facing": _r(facing)}
        if missions:
            poi["missions"] = missions
        pois.append(poi)

    # Lieux de mission d'abord, sur les premiers commerces de l'ordre déterministe.
    restants = list(commerces)
    for pid, kind, label, missions in LIEUX_MISSION:
        if restants:
            ajout(restants.pop(0), pid, kind, label, missions)
            if pid == "auto_bling_27":
                pois[-1]["step"] = "parts"       # boutique de pièces de la mission 2 (prix ×1,5)
            deja.add(label)

    categories = sorted(ENSEIGNES)
    for b in restants:
        cat = categories[_h("cat", b["id"]) % len(categories)]
        noms = ENSEIGNES[cat]
        start = _h("nom", b["id"]) % len(noms)
        label = None
        # Une enseigne n'apparaît qu'une fois ; sinon on change de catégorie, puis on numérote.
        for k in range(len(categories)):
            c = categories[(categories.index(cat) + k) % len(categories)]
            libres = [n for n in ENSEIGNES[c] if n not in deja]
            if libres:
                label = libres[(start + k) % len(libres)]
                break
        if label is None:
            # Toutes les enseignes de base sont prises : on décline avec un qualificatif de quartier.
            for k in range(len(QUALIFICATIFS)):
                essai = f"{noms[start]} {QUALIFICATIFS[(_h('q', b['id']) + k) % len(QUALIFICATIFS)]}"
                if essai not in deja:
                    label = essai
                    break
            if label is None:
                label = f"{noms[start]} {len(deja)}"
        deja.add(label)
        ajout(b, f"commerce_{b['id'][2:]}", "shop", label)

    for typo, label in MONUMENTS.items():
        candidats = [b for b in batiments if b["typology"] == typo]
        if candidats:
            b = max(candidats, key=lambda b: Polygon(b["footprint"]).area)
            ajout(b, {"eglise": "eglise", "public": "salle_des_fetes"}[typo], "landmark", label)
    return pois


TAU_16 = math.tau / 16.0

# --- Mission 01 « Le Calva de Tonton Gégé » : lieux de blockout -------------------------------------
M01 = "m01_calva_gege"
LABELS_M01 = {
    "cave_gege": "Cave de Tonton Gégé",
    "grange_pommiers": "Grange des Pommiers",
    "poulailler_ginette": "Poulailler de Mémère Ginette",
    "fumier_tas": "Tas de fumier du père Lepommier",
    "van_gege": "Camionnette de Gégé",
    "barrage_bosc_tenney": "Barrage de l'avenue du Bosc-Tenney",
    "stand_comite": "Stand du Comité des fêtes",
}


def _poi(pid, kind, label, x, z, facing, taille, step, prop=None, building=None, radius=4.0):
    p = {"id": pid, "kind": kind, "label": label, "position": [_r(x), _r(z)],
         "tile": f"{int(x // taille)}_{int(z // taille)}", "radius": radius, "source": "design",
         "missions": [M01], "step": step, "facing": _r(facing)}
    if prop:
        p["prop"] = prop
    if building:
        p["building"] = building
    return p


def _point_sur_route(tuiles, nom_normalise, normaliser, fraction=0.5):
    """Point au milieu de la plus longue route portant ce nom, et direction (rad) de la route."""
    best = []
    for t in tuiles.values():
        for r in t["roads"]:
            if normaliser(r.get("name")) == nom_normalise and len(r["points"]) > len(best):
                best = r["points"]
    if len(best) < 2:
        return None
    line = LineString(best)
    pt = line.interpolate(fraction, normalized=True)
    a = line.interpolate(max(fraction - 0.05, 0), normalized=True)
    b = line.interpolate(min(fraction + 0.05, 1), normalized=True)
    return (pt.x, pt.y), math.atan2(b.x - a.x, b.y - a.y)


def lieux_mission01(tuiles: dict, taille: float, normaliser, spawn) -> list[dict]:
    """Lieux jouables de la mission 01, posés sur la vraie carte (sans retouche manuelle).

    - cave : colombages le plus proche de l'apparition, hors commerce ;
    - grange / poulailler : plus grande / plus petite annexe de la zone, loin du centre ;
    - fumier : 7 m derrière la grange, côté opposé à la rue ;
    - camionnette : sur la rue Sainte-Foy, près de l'apparition ;
    - barrage : milieu de l'avenue du Bosc-Tenney ; stand : place Carnot (foire).
    """
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"]
              if r["kind"] not in ("footway", "track")]
    batiments = sorted((b for t in tuiles.values() for b in t["buildings"]), key=lambda b: b["id"])
    out: list[dict] = []
    sx, sz = spawn

    def dist(b):
        c = Polygon(b["footprint"]).centroid
        return math.hypot(c.x - sx, c.y - sz)

    col = sorted((b for b in batiments if b["typology"] == "colombages" and 25 < dist(b) < 120), key=dist)
    if col:
        (x, z), f = emplacement_enseigne(col[0]["footprint"], routes)
        out.append(_poi("cave_gege", "mission_target", LABELS_M01["cave_gege"], x, z, f, taille, "crates", building=col[0]["id"]))
    annexes = [b for b in batiments if b["typology"] == "annexe" and dist(b) > 60]
    annexes.sort(key=lambda b: Polygon(b["footprint"]).area)
    if annexes:
        petit, grand = annexes[0], annexes[-1]
        (x, z), f = emplacement_enseigne(grand["footprint"], routes)
        out.append(_poi("grange_pommiers", "mission_target", LABELS_M01["grange_pommiers"], x, z, f, taille, "crates", building=grand["id"]))
        # Le tas de fumier va à côté de la grange, hors de tout bâtiment (marge de 3 m) et
        # ACCESSIBLE à pied : la ligne droite depuis la rue la plus proche ne doit croiser aucun bâtiment
        # (les compagnons IA suivent les rues ; on préfère le côté de la grange, pas sa façade).
        polys = [Polygon(b["footprint"]) for b in batiments]
        c = Polygon(grand["footprint"]).centroid
        best, best_score = None, None
        for d in range(5, 46, 3):
            for k in range(16):
                a = TAU_16 * k
                x, z = c.x + math.sin(a) * d, c.y + math.cos(a) * d
                pt = Point(x, z)
                if any(p_.distance(pt) < 3.0 for p_ in polys):
                    continue
                if routes:
                    road = min(routes, key=lambda r: r.distance(pt))
                    foot = nearest_points(road, pt)[0]
                    if foot.distance(pt) > 28.0:
                        continue
                    ray = LineString([(foot.x, foot.y), (x, z)])
                    if any(p_.intersects(ray) for p_ in polys):
                        continue
                    score = d + 0.4 * foot.distance(pt)
                else:
                    score = d
                # Pas devant la façade (là où s'ouvre l'enseigne) : on veut un coin discret.
                if math.sin(a) * math.sin(f) + math.cos(a) * math.cos(f) > 0.6:
                    score += 12.0
                if best_score is None or score < best_score:
                    best, best_score = (x, z), score
        fx, fz = best if best else (c.x, c.y)
        out.append(_poi("fumier_tas", "mission_target", LABELS_M01["fumier_tas"], fx, fz, f + math.pi, taille, "crates", prop="fumier"))
        (x, z), f = emplacement_enseigne(petit["footprint"], routes)
        out.append(_poi("poulailler_ginette", "mission_target", LABELS_M01["poulailler_ginette"], x, z, f, taille, "crates", prop="coop", building=petit["id"]))
    rue = _point_sur_route(tuiles, normaliser("Rue Sainte-Foy"), normaliser, 0.35)
    if rue:
        (x, z), f = rue
        out.append(_poi("van_gege", "spawn", LABELS_M01["van_gege"], x + math.cos(f) * 2.6, z - math.sin(f) * 2.6, f, taille, "vehicle", prop="van"))
    bosc = _point_sur_route(tuiles, normaliser("Avenue du Bosc Tenney"), normaliser, 0.5)
    if bosc:
        (x, z), f = bosc
        out.append(_poi("barrage_bosc_tenney", "mission_target", LABELS_M01["barrage_bosc_tenney"], x, z, f, taille, "checkpoint", prop="barrier", radius=8.0))
    carnot = _point_sur_route(tuiles, normaliser("Place Carnot"), normaliser, 0.5)
    if carnot:
        (x, z), f = carnot
        out.append(_poi("stand_comite", "mission_target", LABELS_M01["stand_comite"], x, z, f, taille, "fair", prop="stand", radius=5.0))
    return out


# --- Mission 02 « Tuning du samedi soir » : lieux de blockout ------------------------------------
M02 = "m02_tuning_samedi"
LABELS_M02 = {
    "garage_kevin": "Garage de Kévin (mécanique à la dure)",
    "voiture_kevin": "La Fusée de Kévin",
    "casse_dugenou": "Casse Auto Dugenou",
    "annonce_vendeur": "Chez le père Bernard (annonce : jantes à saisir)",
    "cour_dylan": "Cour de Dylan",
    "parc_rdv": "Parking du rendez-vous du samedi soir",
    "drag_depart": "Ligne de départ du drag",
    "drag_arrivee": "Ligne d'arrivée du drag",
}
DRAG_LENGTH = 400.0       # m, imposé par missions/m02 (drag_race.distanceM)
STRIP_SEARCH_LENGTH = 440.0
STRIP_WIDTH = 16.0


def _poi2(pid, kind, label, x, z, facing, taille, step, prop=None, building=None, radius=5.0):
    p = {"id": pid, "kind": kind, "label": label, "position": [_r(x), _r(z)],
         "tile": f"{int(x // taille)}_{int(z // taille)}", "radius": radius, "source": "design",
         "missions": [M02], "step": step, "facing": _r(facing)}
    if prop:
        p["prop"] = prop
    if building:
        p["building"] = building
    return p


def _hauteur(tuiles: dict, x: float, z: float, taille: float):
    """Altitude relative du terrain (grille des tuiles), None hors tuiles."""
    t = tuiles.get((int(x // taille), int(z // taille)))
    if not t:
        return None
    g = t["ground"]
    res, hs = g["resolution"], g["heights"]
    step = taille / (res - 1)
    gx = min(max((x - t["origin"][0]) / step, 0.0), res - 1.001)
    gz = min(max((z - t["origin"][1]) / step, 0.0), res - 1.001)
    i, j = int(gx), int(gz)
    fx, fz = gx - i, gz - j
    top = hs[j * res + i] * (1 - fx) + hs[j * res + i + 1] * fx
    bot = hs[(j + 1) * res + i] * (1 - fx) + hs[(j + 1) * res + i + 1] * fx
    return top * (1 - fz) + bot * fz


def trouver_piste(tuiles_xy: dict, taille: float, longueur=STRIP_SEARCH_LENGTH, largeur=STRIP_WIDTH):
    """Couloir rectangulaire libre (sans bâtiment, route ni eau) et le plus plat possible.

    `tuiles_xy` : {(x, y): tuile}. Renvoie (dénivelé m, cap degrés, centre x, centre z) ou None.
    Déterministe : balayage d'une grille de 20 m, caps tous les 10°.
    """
    from shapely.strtree import STRtree
    obstacles = []
    for t in tuiles_xy.values():
        obstacles += [Polygon(b["footprint"]).buffer(3.0) for b in t["buildings"]]
        obstacles += [LineString(r["points"]).buffer(r["width"] / 2 + 2.0) for r in t["roads"] if r["kind"] not in ("footway", "track")]
        obstacles += [Polygon(v["polygon"]) for v in t["vegetation"] if v["kind"] == "water"]
    arbre = STRtree(obstacles)
    xs = [k[0] for k in tuiles_xy]
    ys = [k[1] for k in tuiles_xy]
    x0, x1 = min(xs) * taille, (max(xs) + 1) * taille
    z0, z1 = min(ys) * taille, (max(ys) + 1) * taille
    meilleur = None
    for cap in range(0, 180, 10):
        a = math.radians(cap)
        d = (math.sin(a), math.cos(a))
        p = (-d[1], d[0])
        for cx in range(int(x0) + 60, int(x1) - 60, 20):
            for cz in range(int(z0) + 60, int(z1) - 60, 20):
                coins = [(cx + d[0] * s * longueur / 2 + p[0] * w * largeur / 2, cz + d[1] * s * longueur / 2 + p[1] * w * largeur / 2)
                         for s, w in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
                if any((int(qx // taille), int(qz // taille)) not in tuiles_xy for qx, qz in coins):
                    continue
                poly = Polygon(coins)
                if any(obstacles[i].intersects(poly) for i in arbre.query(poly)):
                    continue
                hs = [_hauteur(tuiles_xy, cx + d[0] * k, cz + d[1] * k, taille) for k in range(-int(longueur / 2), int(longueur / 2) + 1, 20)]
                if None in hs:
                    continue
                pente = max(hs) - min(hs)
                if meilleur is None or pente < meilleur[0] - 1e-9:
                    meilleur = (pente, cap, cx, cz)
    return meilleur


def _dir_route(routes, pt: Point):
    """Point de la route la plus proche et sa direction (rad, convention (sin, cos))."""
    route = min(routes, key=lambda r: r.distance(pt))
    d = route.project(pt)
    a = route.interpolate(max(d - 2.0, 0.0))
    b = route.interpolate(min(d + 2.0, route.length))
    near = route.interpolate(d)
    return (near.x, near.y), math.atan2(b.x - a.x, b.y - a.y)


def lieux_mission02(tuiles: dict, taille: float, normaliser, spawn, utilises: set) -> list[dict]:
    """Lieux jouables de la mission 02, posés sur la vraie carte (sans retouche manuelle).

    - garage : annexe de taille moyenne proche de l'apparition ; la voiture est garée sur la rue ;
    - casse : grande annexe éloignée ; annonce et cour de Dylan : deux maisons éloignées l'une de l'autre ;
    - piste de drag : couloir libre de 440 m (400 m utiles) cherché sur toute la zone, le plus plat ;
    - parking du rendez-vous : à côté de la ligne de départ, de sorte que le jury précède la course.
    """
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")]
    batiments = [b for t in tuiles.values() for b in t["buildings"] if b["id"] not in utilises]
    batiments.sort(key=lambda b: b["id"])
    sx, sz = spawn
    out: list[dict] = []

    def centre(b):
        c = Polygon(b["footprint"]).centroid
        return c.x, c.y

    def dist(b, ref=(sx, sz)):
        c = centre(b)
        return math.hypot(c[0] - ref[0], c[1] - ref[1])

    def aire(b):
        return Polygon(b["footprint"]).area

    # Garage et voiture.
    garages = sorted((b for b in batiments if b["typology"] == "annexe" and 40 <= aire(b) <= 160 and 40 < dist(b) < 260), key=dist)
    garage = garages[0] if garages else None
    if garage:
        (x, z), f = emplacement_enseigne(garage["footprint"], routes)
        out.append(_poi2("garage_kevin", "hideout", LABELS_M02["garage_kevin"], x, z, f, taille, "assembly", prop="garage", building=garage["id"]))
        (rx, rz), rf = _dir_route(routes, Point(x, z))
        # La voiture est garée sur la chaussée, nez dans le sens de la rue, décalée de 2 m du centre.
        out.append(_poi2("voiture_kevin", "spawn", LABELS_M02["voiture_kevin"], rx + math.cos(rf) * 2.2, rz - math.sin(rf) * 2.2, rf, taille, "test_drive", prop="car"))
        utilises = utilises | {garage["id"]}
    garage_pos = centre(garage) if garage else (sx, sz)
    # Casse : grande annexe, loin du garage.
    grandes = sorted((b for b in batiments if b["typology"] == "annexe" and aire(b) >= 110 and b["id"] not in utilises), key=lambda b: -aire(b))[:6]
    casse = max(grandes, key=lambda b: dist(b, garage_pos)) if grandes else None
    if casse:
        (x, z), f = emplacement_enseigne(casse["footprint"], routes)
        out.append(_poi2("casse_dugenou", "mission_target", LABELS_M02["casse_dugenou"], x, z, f, taille, "parts", prop="junkyard", building=casse["id"], radius=7.0))
        utilises = utilises | {casse["id"]}
    # Annonce puis cour de Dylan : deux maisons, à 120 m au moins l'une de l'autre.
    maisons = sorted((b for b in batiments if b["typology"] in ("pavillon", "brique", "colombages") and b["id"] not in utilises and 110 < dist(b) < 380 and 25 < aire(b) < 160),
                     key=lambda b: (_hash_str(b["id"]), b["id"]))
    annonce = maisons[0] if maisons else None
    if annonce:
        (x, z), f = emplacement_enseigne(annonce["footprint"], routes)
        out.append(_poi2("annonce_vendeur", "mission_target", LABELS_M02["annonce_vendeur"], x, z, f, taille, "parts", building=annonce["id"]))
        dylan = next((b for b in maisons[1:] if math.hypot(centre(b)[0] - centre(annonce)[0], centre(b)[1] - centre(annonce)[1]) > 120), None)
        if dylan:
            (x, z), f = emplacement_enseigne(dylan["footprint"], routes)
            out.append(_poi2("cour_dylan", "mission_target", LABELS_M02["cour_dylan"], x, z, f, taille, "parts", building=dylan["id"]))
    # Piste de drag, parking du rendez-vous.
    piste = trouver_piste({k: v for k, v in _tuiles_par_xy(tuiles).items()}, taille)
    if piste:
        pente, cap, cx, cz = piste
        a = math.radians(cap)
        d = (math.sin(a), math.cos(a))
        demi = DRAG_LENGTH / 2
        ax, az = cx - d[0] * demi, cz - d[1] * demi
        bx, bz = cx + d[0] * demi, cz + d[1] * demi
        out.append(_poi2("drag_depart", "mission_target", LABELS_M02["drag_depart"], ax, az, a, taille, "drag", prop="strip", radius=8.0))
        out.append(_poi2("drag_arrivee", "mission_target", LABELS_M02["drag_arrivee"], bx, bz, a, taille, "drag", radius=8.0))
        px, pz = ax - d[0] * 22 - d[1] * 20, az - d[1] * 22 + d[0] * 20
        out.append(_poi2("parc_rdv", "mission_target", LABELS_M02["parc_rdv"], px, pz, a, taille, "meet", radius=9.0))
    return out


def _hash_str(s: str) -> int:
    return _h("m02", s)


def _tuiles_par_xy(tuiles: dict) -> dict:
    """Les tuiles construites, indexées par (x, y) entiers."""
    return {(t["tile"]["x"], t["tile"]["y"]): t for t in tuiles.values()}


def nom_commerce_generique(osm_id) -> str:
    """Nom fictif pour un commerce OSM isolé (hors bâtiment identifié)."""
    categories = sorted(ENSEIGNES)
    noms = ENSEIGNES[categories[_h("cat", osm_id) % len(categories)]]
    return noms[_h("nom", osm_id) % len(noms)]


# --- Mission 03 « Battle de sono » : lieux de blockout ----------------------------------------------
M03 = "m03_battle_sono"
LABELS_M03 = {
    "camp_pommiers": "Sono du lotissement des Pommiers",
    "camp_clos_fleuri": "Sono du Clos Fleuri (rivaux)",
    "item_caisson": "Le caisson de la Fusée (chez Kévin)",
    "item_rallonge": "La rallonge de Ginette",
    "item_groupe": "Le groupe électrogène de Tonton Gégé",
}


def _poi3(pid, label, x, z, facing, taille, step, prop=None, building=None, radius=5.0):
    p = _poi2(pid, "mission_target", label, x, z, facing, taille, step, prop=prop, building=building, radius=radius)
    p["missions"] = [M03]
    return p


def lieux_mission03(tuiles: dict, taille: float, normaliser, spawn, utilises: set) -> list[dict]:
    """Lieux de la mission 03, posés sur la vraie carte.

    - sono des Pommiers : maison de taille moyenne à 70-220 m de l'apparition ;
    - sono du Clos Fleuri : maison à 220 m au moins de la précédente (le camp rival est loin) ;
    - trois objets à rassembler (caisson, rallonge, groupe) : maisons voisines (80-300 m du camp), deux à deux écartées de 40 m.
    """
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")]
    batiments = [b for t in tuiles.values() for b in t["buildings"] if b["id"] not in utilises and b["typology"] in ("pavillon", "brique", "colombages") and 25 < Polygon(b["footprint"]).area < 180]
    batiments.sort(key=lambda b: (_h("m03", b["id"]), b["id"]))

    def centre(b):
        c = Polygon(b["footprint"]).centroid
        return c.x, c.y

    def dist(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    out: list[dict] = []
    camp = next((b for b in batiments if 70 < dist(centre(b), spawn) < 220), None)
    if camp is None:
        return out
    cc = centre(camp)
    (x, z), f = emplacement_enseigne(camp["footprint"], routes)
    out.append(_poi3("camp_pommiers", LABELS_M03["camp_pommiers"], x, z, f, taille, "stage", prop="stage", building=camp["id"], radius=10.0))
    pris = [cc]
    rival = next((b for b in batiments if b is not camp and dist(centre(b), cc) > 220), None)
    if rival:
        (x, z), f = emplacement_enseigne(rival["footprint"], routes)
        out.append(_poi3("camp_clos_fleuri", LABELS_M03["camp_clos_fleuri"], x, z, f, taille, "rival", prop="stage", building=rival["id"], radius=10.0))
        pris.append(centre(rival))
    for pid in ("item_caisson", "item_rallonge", "item_groupe"):
        b = next((b for b in batiments if b["id"] != camp["id"] and 80 < dist(centre(b), cc) < 300 and all(dist(centre(b), q) > 40 for q in pris)), None)
        if b is None:
            continue
        (x, z), f = emplacement_enseigne(b["footprint"], routes)
        out.append(_poi3(pid, LABELS_M03[pid], x, z, f, taille, "setup", building=b["id"], radius=3.0))
        pris.append(centre(b))
    return out


# --- Mission 04 « Le méchoui de la Saint-Jean » : lieux de blockout --------------------------------------
M04 = "m04_mechoui_saint_jean"
LABELS_M04 = {
    "place_fete": "Cuisine du méchoui (Comité des fêtes)",
    "bucher": "Bûcher de la Saint-Jean",
    "item_agneau": "L'agneau de la ferme du Pré-Fleuri",
    "item_broche": "La broche de Tonton Gégé",
    "item_charbon": "Le charbon de la quincaillerie Lebrun-Dupré",
}


def _poi4(pid, label, x, z, facing, taille, step, prop=None, building=None, radius=5.0):
    p = _poi2(pid, "mission_target", label, x, z, facing, taille, step, prop=prop, building=building, radius=radius)
    p["missions"] = [M04]
    return p


def lieux_mission04(tuiles: dict, taille: float, normaliser, spawn, utilises: set) -> list[dict]:
    """Lieux de la mission 04 : cuisine du méchoui (maison à 60-200 m), bûcher (à 150 m au moins de la cuisine),
    trois objets chez des voisins à 70-280 m de la cuisine, deux à deux écartés de 40 m."""
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")]
    batiments = [b for t in tuiles.values() for b in t["buildings"] if b["id"] not in utilises and b["typology"] in ("pavillon", "brique", "colombages") and 25 < Polygon(b["footprint"]).area < 180]
    batiments.sort(key=lambda b: (_h("m04", b["id"]), b["id"]))

    def centre(b):
        c = Polygon(b["footprint"]).centroid
        return c.x, c.y

    def dist(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    out: list[dict] = []
    cuisine = next((b for b in batiments if 60 < dist(centre(b), spawn) < 200), None)
    if cuisine is None:
        return out
    cc = centre(cuisine)
    (x, z), f = emplacement_enseigne(cuisine["footprint"], routes)
    out.append(_poi4("place_fete", LABELS_M04["place_fete"], x, z, f, taille, "fire", prop="fete", building=cuisine["id"], radius=8.0))
    pris = [cc]
    bucher = next((b for b in batiments if b is not cuisine and 150 < dist(centre(b), cc) < 330), None)
    if bucher:
        (x, z), f = emplacement_enseigne(bucher["footprint"], routes)
        out.append(_poi4("bucher", LABELS_M04["bucher"], x, z, f, taille, "bonfire", prop="pyre", building=bucher["id"], radius=6.0))
        pris.append(centre(bucher))
    for pid in ("item_agneau", "item_broche", "item_charbon"):
        b = next((b for b in batiments if b["id"] != cuisine["id"] and 70 < dist(centre(b), cc) < 280 and all(dist(centre(b), q) > 40 for q in pris)), None)
        if b is None:
            continue
        (x, z), f = emplacement_enseigne(b["footprint"], routes)
        out.append(_poi4(pid, LABELS_M04[pid], x, z, f, taille, "gather", building=b["id"], radius=3.0))
        pris.append(centre(b))
    return out


# --- Mission 05 « Les vaches sont de sortie » : lieux de blockout ---------------------------------------
M05 = "m05_vaches_en_goguette"
LABELS_M05 = {
    "enclos_odette": "Enclos de la ferme de Mémé Odette",
    "pre_vaches": "Le pré où les vaches ont filé",
}
PEN_FRONT = 0.0           # m : le centre de l'enclos est le point du POI
PEN_RADIUS = 6.0          # demi-côté de l'enclos (m)


def _poi5(pid, label, x, z, facing, taille, step, prop=None, building=None, radius=5.0):
    p = _poi2(pid, "mission_target", label, x, z, facing, taille, step, prop=prop, building=building, radius=radius)
    p["missions"] = [M05]
    return p


def lieux_mission05(tuiles: dict, taille: float, normaliser, spawn, utilises: set) -> list[dict]:
    """Enclos et pré des vaches, tous deux en terrain dégagé. L'enclos (12 × 12 m, ouvert vers le pré) est cherché à 60-200 m
    de l'apparition ; le pré (rayon 25 m, sans bâtiment) est à 80-140 m de l'enclos, relié à lui par un couloir de 10 m sans
    bâtiment : les vaches peuvent être rabattues en ligne droite. Balayage déterministe d'une grille de 15 m."""
    from shapely.strtree import STRtree
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")]
    obstacles = [Polygon(b["footprint"]) for t in tuiles.values() for b in t["buildings"]]
    arbre = STRtree(obstacles)
    en_zone = {(t["tile"]["x"], t["tile"]["y"]) for t in tuiles.values()}

    def libre(poly):
        return not any(obstacles[i].intersects(poly) for i in arbre.query(poly))

    sx, sz = spawn
    sites = []
    for x in range(int(sx) - 200, int(sx) + 200, 15):
        for z in range(int(sz) - 200, int(sz) + 200, 15):
            d = math.hypot(x - sx, z - sz)
            if 60 < d < 200 and (int(x // taille), int(z // taille)) in en_zone:
                sites.append((_h("m05", f"{x}_{z}"), x, z))
    sites.sort()
    for _, x, z in sites:
        if not libre(Point(x, z).buffer(PEN_RADIUS * 1.5 + 2.0)):
            continue
        if any(r.distance(Point(x, z)) < PEN_RADIUS * 1.5 for r in routes):
            continue
        for rayon in (100.0, 115.0, 130.0, 90.0, 140.0):
            for k in range(24):
                a = TAU_FICTION * k / 24.0
                px, pz = x + math.cos(a) * rayon, z + math.sin(a) * rayon
                if (int(px // taille), int(pz // taille)) not in en_zone:
                    continue
                if not libre(Point(px, pz).buffer(25.0)) or not libre(LineString([(x, z), (px, pz)]).buffer(5.0)):
                    continue
                f = math.atan2(px - x, pz - z)           # la porte de l'enclos regarde le pré
                return [
                    _poi5("enclos_odette", LABELS_M05["enclos_odette"], x, z, f, taille, "pen", prop="pen", radius=PEN_RADIUS),
                    _poi5("pre_vaches", LABELS_M05["pre_vaches"], px, pz, 0.0, taille, "herd", radius=25.0),
                ]
    return []


TAU_FICTION = 2 * math.pi


# --- Mission 06 « Les courses de 8 h » : le supermarché -------------------------------------------------
M06 = "m06_courses_de_8h"
LABELS_M06 = {"supermarche": "Supermarché Le Panier d'Ouche"}
SUPER_W = 26.0            # m le long de la façade
SUPER_D = 18.0            # m de profondeur


def lieux_mission06(tuiles: dict, taille: float, normaliser, spawn, utilises: set) -> list[dict]:
    """Supermarché indépendant : emprise de 26 × 18 m (marge de 4 m) sans bâtiment, route ni eau, la plus plate possible, à 60-220 m
    de l'apparition, tournée (porte à l'avant) vers la route la plus proche. Balayage déterministe d'une grille de 10 m."""
    from shapely.strtree import STRtree
    from shapely.geometry import Polygon as P
    obstacles = [Polygon(b["footprint"]) for t in tuiles.values() for b in t["buildings"]]
    obstacles += [Polygon(v["polygon"]) for t in tuiles.values() for v in t["vegetation"] if v["kind"] == "water"]
    arbre = STRtree(obstacles)
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")]
    en_zone = {(t["tile"]["x"], t["tile"]["y"]) for t in tuiles.values()}
    par_xy = {(t["tile"]["x"], t["tile"]["y"]): t for t in tuiles.values()}
    sx, sz = spawn
    meilleur = None
    for x in range(int(sx) - 220, int(sx) + 220, 10):
        for z in range(int(sz) - 220, int(sz) + 220, 10):
            d = math.hypot(x - sx, z - sz)
            if not (60 < d < 220) or (int(x // taille), int(z // taille)) not in en_zone:
                continue
            pt = Point(x, z)
            proche = min(routes, key=lambda r: r.distance(pt))
            dr = proche.distance(pt)
            if not (16.0 < dr < 55.0):
                continue
            np_ = proche.interpolate(proche.project(pt))
            f = math.atan2(np_.x - x, np_.y - z)
            fx, fz = math.sin(f), math.cos(f)
            px, pz = fz, -fx
            coins = [(x + px * sgx * (SUPER_W / 2 + 4) + fx * sgz * (SUPER_D / 2 + 4), z + pz * sgx * (SUPER_W / 2 + 4) + fz * sgz * (SUPER_D / 2 + 4))
                     for sgx, sgz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            if any((int(qx // taille), int(qz // taille)) not in en_zone for qx, qz in coins):
                continue
            poly = P(coins)
            if any(obstacles[i].intersects(poly) for i in arbre.query(poly)):
                continue
            if any(r.intersects(poly) for r in routes):
                continue
            hs = []
            for ix in (-1, -0.5, 0, 0.5, 1):
                for iz in (-1, -0.5, 0, 0.5, 1):
                    qx = x + px * ix * SUPER_W / 2 + fx * iz * SUPER_D / 2
                    qz = z + pz * ix * SUPER_W / 2 + fz * iz * SUPER_D / 2
                    h = _hauteur(par_xy, qx, qz, taille)
                    if h is None:
                        hs = None
                        break
                    hs.append(h)
                if hs is None:
                    break
            if not hs:
                continue
            pente = max(hs) - min(hs)
            if meilleur is None or pente < meilleur[0] - 1e-9:
                meilleur = (pente, x, z, f)
    if meilleur is None:
        return []
    _, x, z, f = meilleur
    p = _poi2("supermarche", "shop", LABELS_M06["supermarche"], x, z, f, taille, "shop", prop="supermarket", radius=SUPER_W / 2)
    p["missions"] = [M06]
    return [p]


# --- Mission 07 « Le jus de pomme de Tonton Gégé » : fête de la pomme, WC publics, chez soi ------------------
M07 = "m07_jus_de_pomme"
LABELS_M07 = {
    "fete_pomme": "Stand de jus de pomme de Tonton Gégé (fête de la pomme)",
    "wc_publics": "Toilettes publiques (souvent occupées)",
    "chez_soi": "Chez vous : la maison aux toilettes si lointaines",
}


def _poi7(pid, label, x, z, facing, taille, step, prop=None, building=None, radius=5.0, kind="mission_target"):
    p = _poi2(pid, kind, label, x, z, facing, taille, step, prop=prop, building=building, radius=radius)
    p["missions"] = [M07]
    return p


def lieux_mission07(tuiles: dict, taille: float, normaliser, spawn, utilises: set) -> list[dict]:
    """Stand de la fête (emplacement libre sur le trottoir d'une maison à 40-160 m de l'apparition), maison du joueur à 150-230 m
    à vol d'oiseau du stand, toilettes publiques sur le bord de la route la plus proche du milieu du trajet."""
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")]
    batiments = [b for t in tuiles.values() for b in t["buildings"] if b["id"] not in utilises and b["typology"] in ("pavillon", "brique", "colombages") and 25 < Polygon(b["footprint"]).area < 180]
    batiments.sort(key=lambda b: (_h("m07", b["id"]), b["id"]))

    def centre(b):
        c = Polygon(b["footprint"]).centroid
        return c.x, c.y

    def dist(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    fete_b = next((b for b in batiments if 40 < dist(centre(b), spawn) < 160), None)
    if fete_b is None:
        return []
    fc = centre(fete_b)
    home_b = next((b for b in batiments if b is not fete_b and 150 < dist(centre(b), fc) < 230), None)
    if home_b is None:
        return []
    (fx, fz), ff = emplacement_enseigne(fete_b["footprint"], routes)
    (hx, hz), hf = emplacement_enseigne(home_b["footprint"], routes)
    mid = Point((fx + hx) / 2.0, (fz + hz) / 2.0)
    proche = min(routes, key=lambda r: r.distance(mid))
    q = proche.interpolate(proche.project(mid))
    (_, _), rf = _dir_route(routes, q)
    # À 3,5 m du bord de la chaussée, côté milieu du trajet ; la cabine regarde la route.
    nx, nz = math.cos(rf), -math.sin(rf)
    sgn = 1.0 if (mid.x - q.x) * nx + (mid.y - q.y) * nz >= 0 else -1.0
    wx, wz = q.x + nx * sgn * 3.5, q.y + nz * sgn * 3.5
    wf = math.atan2(-nx * sgn, -nz * sgn)
    return [
        _poi7("fete_pomme", LABELS_M07["fete_pomme"], fx, fz, ff, taille, "start", prop="pressoir", building=fete_b["id"], radius=6.0),
        _poi7("chez_soi", LABELS_M07["chez_soi"], hx, hz, hf, taille, "home", building=home_b["id"], radius=3.0, kind="hideout"),
        _poi7("wc_publics", LABELS_M07["wc_publics"], wx, wz, wf, taille, "wc", prop="wc", radius=3.0),
    ]
