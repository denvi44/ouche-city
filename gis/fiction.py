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
        out.append(_poi("poulailler_ginette", "mission_target", LABELS_M01["poulailler_ginette"], x, z, f, taille, "crates", building=petit["id"]))
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
