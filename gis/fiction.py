"""Lieux fictifs de Frouch City (agent 01, validé narration 07).

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
    "coiffure": ["Tif'Frouch", "Le Bigoudi d'Or", "Hair du Bocage"],
    "fleuriste": ["Les Pétales Pressés", "Au Bouquet de Pommiers"],
    "pharmacie": ["Pharmacie de la Pomme Verte", "Pharmacie du Donjon"],
    "garage": ["Garage Bielle et Pistons", "Mécanique Gaston Frères"],
    "presse": ["Presse L'Écho du Bocage", "Le Kiosque à Ragots"],
    "creperie": ["Crêperie Bolée & Galette", "La Galette Qui Roule"],
    "brocante": ["Brocante Tout Doit Disparaître (depuis 1987)", "Le Grenier de Tata Odette"],
    "banque": ["Caisse Mutuelle du Pays de Frouch", "Crédit Pommier"],
    "immobilier": ["Immo Colombages", "Agence Clé des Champs"],
    "fromagerie": ["Fromagerie La Croûte Fleurie", "Au Plateau du Dimanche"],
    "quincaillerie": ["Quincaillerie Clou & Cie", "Bricol'Frouch"],
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


# Bâtiments voisins : une enseigne ou un objet de mission ne doit pas tomber dans une ruelle trop étroite pour un joueur
# (corps de 0,8 m) entre deux bâtiments. Renseigné par `definir_batiments` (appelé au début de `lieux_fictifs`).
_ARBRE = None
_BATS: list = []
LIBRE_MIN = 2.5


def definir_batiments(tuiles: dict) -> None:
    global _ARBRE, _BATS
    from shapely.strtree import STRtree
    _BATS = [Polygon(b["footprint"]) for t in tuiles.values() for b in t["buildings"]]
    _ARBRE = STRtree(_BATS) if _BATS else None


def _libre(x: float, z: float, propre: Polygon) -> float:
    """Distance (≤ LIBRE_MIN) du point au bâtiment voisin le plus proche (le bâtiment `propre` est ignoré)."""
    if _ARBRE is None:
        return LIBRE_MIN
    pt = Point(x, z)
    mini = LIBRE_MIN
    for i in _ARBRE.query(pt.buffer(LIBRE_MIN)):
        b = _BATS[int(i)]
        if b.equals(propre):
            continue
        mini = min(mini, b.distance(pt))
    return mini


def _normale_sortante(a, c, aire: float) -> tuple[float, float]:
    """Normale unitaire de l'arête a→c, tournée vers l'extérieur du bâtiment (`aire` : aire signée de l'anneau)."""
    ex, ez = c[0] - a[0], c[1] - a[1]
    n = math.hypot(ex, ez) or 1.0
    nx, nz = ez / n, -ex / n
    return (-nx, -nz) if aire < 0 else (nx, nz)


def emplacement_enseigne(footprint, routes: list[LineString], largeur: float = 2.5) -> tuple[tuple[float, float], float]:
    """Point de façade tourné vers la route la plus proche, et angle (rad) de la façade.

    L'enseigne est **plaquée au mur** : son cap est exactement la normale sortante d'une arête du bâtiment
    (jamais une diagonale vers la route quand le point le plus proche est un coin) et elle est posée contre
    le mur, centrée sur l'arête si elle est plus courte que `largeur`, sans dépasser du coin sinon.
    Convention Godot : rotation autour de Y pour que +Z local regarde la rue.
    """
    poly = Polygon(footprint)
    pts = [tuple(p) for p in footprint]
    aire = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2.0
    if not routes:
        c = poly.centroid
        return (c.x, c.y), 0.0
    route = min(routes, key=lambda r: r.distance(poly))
    _, sur_route = nearest_points(poly.exterior, route)
    meilleur = None
    for i in range(len(pts)):
        a, c = pts[i], pts[(i + 1) % len(pts)]
        ex, ez = c[0] - a[0], c[1] - a[1]
        long = math.hypot(ex, ez)
        if long < 0.8:
            continue
        t = max(0.0, min(1.0, ((sur_route.x - a[0]) * ex + (sur_route.y - a[1]) * ez) / (long * long)))
        n = _normale_sortante(a, c, aire)
        marge = min(largeur / 2.0, long / 2.0)
        lo, hi = marge / long, 1.0 - marge / long
        # Positions candidates le long du mur : la plus proche de la route d'abord, puis le centre et les quarts.
        for u in (max(lo, min(hi, t)), 0.5, 0.25, 0.75, 0.125, 0.875):
            u = max(lo, min(hi, u))
            px, pz = a[0] + ex * u, a[1] + ez * u
            qx, qz = px + n[0] * 0.07, pz + n[1] * 0.07
            libre = _libre(qx, qz, poly)
            d = math.hypot(sur_route.x - px, sur_route.y - pz)
            vers = ((sur_route.x - px) / d, (sur_route.y - pz) / d) if d > 1e-6 else n
            regard = n[0] * vers[0] + n[1] * vers[1]            # 1 : la façade regarde la route
            score = d + (4.0 if long < 2.0 else 0.0) + (3.0 if regard < 0.2 else 0.0) + (0.0 if libre >= LIBRE_MIN else 8.0 + (LIBRE_MIN - libre) * 4.0)
            if meilleur is None or score < meilleur[0]:
                meilleur = (score, a, c, n, long, u)
            if libre >= LIBRE_MIN:
                break
    if meilleur is None:
        c = poly.centroid
        return (c.x, c.y), 0.0
    _, a, c, n, long, u = meilleur
    px, pz = a[0] + (c[0] - a[0]) * u, a[1] + (c[1] - a[1]) * u
    return (px + n[0] * 0.07, pz + n[1] * 0.07), math.atan2(n[0], n[1])


def lieux_fictifs(tuiles: dict, taille: float) -> list[dict]:
    """POI fictifs pour les commerces et monuments des tuiles construites."""
    definir_batiments(tuiles)
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"]
              if r["kind"] not in ("footway", "track")]
    batiments = sorted((b for t in tuiles.values() for b in t["buildings"]), key=lambda b: b["id"])
    commerces = [b for b in batiments if b["typology"] == "commerce"]
    commerces.sort(key=lambda b: _h("ordre", b["id"]))
    pois: list[dict] = []
    deja: set[str] = set()

    def ajout(b, pid, kind, label, missions=None):
        (x, z), facing = emplacement_enseigne(b["footprint"], routes, min(5.5, max(1.4, len(label) * 0.16 + 0.4)))
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
LABELS_M06 = {"supermarche": "Supermarché Le Panier de Frouch"}
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


# --- Mission 08 « Les oies font grève » : la voie ferrée et la mare des oies ---------------------------------
M08 = "m08_oies_en_greve"
LABELS_M08 = {
    "passage_niveau": "Passage à niveau du Pays de Frouch",
    "etang_oies": "La mare des oies de Mémé Odette",
    "gare_pays_frouch": "Gare du Pays de Frouch",
}
GARE_QUAI = 80.0            # longueur du quai (m)
GARE_LOT = (2.0, 26.0)      # emprise latérale (m depuis l'axe de la voie) : quai, bâtiment et parvis
RAIL_LENGTHS = (480.0, 400.0, 340.0, 280.0)
RAIL_WIDTH = 14.0
POND_RADIUS = 14.0


def _poi8(pid, label, x, z, facing, taille, step, prop=None, radius=5.0, length=None, kind="mission_target"):
    p = _poi2(pid, kind, label, x, z, facing, taille, step, prop=prop, radius=radius)
    p["missions"] = [M08]
    if length is not None:
        p["length"] = length
    return p


def _gare(tuiles: dict, taille: float, cx: float, cz: float, d: tuple, longueur: float, obstacles_tous: list):
    """Gare sur la voie : quai de 80 m et bâtiment du même côté, libres de tout obstacle, au plus près de u = -60 m du passage à
    niveau (côté d'où vient le train : il s'arrête devant le quai quand les oies le bloquent), reliée par un chemin à la route la plus
    proche. Renvoie (u, côté, chemin) ou None."""
    from shapely.strtree import STRtree
    p = (-d[1], d[0])
    arbre = STRtree(obstacles_tous)
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] in ("primary", "secondary", "tertiary", "residential")]
    batis = [Polygon(b["footprint"]).buffer(2.0) for t in tuiles.values() for b in t["buildings"]]
    batis += [Polygon(v["polygon"]) for t in tuiles.values() for v in t["vegetation"] if v["kind"] == "water"]
    arbre_b = STRtree(batis)
    meilleur = None
    u = -longueur / 2 + 80.0
    while u <= min(longueur / 2 - 80.0, -60.0):      # le quai s'arrête avant le passage à niveau
        for cote in (-1, 1):
            x, z = cx + d[0] * u, cz + d[1] * u
            lot = Polygon([(x + d[0] * s * (GARE_QUAI / 2) + p[0] * cote * w, z + d[1] * s * (GARE_QUAI / 2) + p[1] * cote * w)
                           for s, w in ((-1, GARE_LOT[0]), (1, GARE_LOT[0]), (1, GARE_LOT[1]), (-1, GARE_LOT[1]))])
            if any(obstacles_tous[i].intersects(lot) for i in arbre.query(lot)):
                continue
            parvis = Point(x + p[0] * cote * GARE_LOT[1], z + p[1] * cote * GARE_LOT[1])
            route = min(routes, key=lambda r: r.distance(parvis))
            q = route.interpolate(route.project(parvis))
            chemin = LineString([(parvis.x, parvis.y), (q.x, q.y)])
            if chemin.length > 110.0 or any(batis[i].intersects(chemin.buffer(1.2)) for i in arbre_b.query(chemin.buffer(1.2))):
                continue
            hauteurs = [_hauteur(tuiles, x + d[0] * k, z + d[1] * k, taille) for k in (-40, -20, 0, 20, 40)]
            if None in hauteurs:
                continue
            score = abs(u + 70.0) * 0.6 + chemin.length * 0.5 + (max(hauteurs) - min(hauteurs)) * 25.0
            if meilleur is None or score < meilleur[0] - 1e-9:
                meilleur = (score, u, cote, [[round(parvis.x, 2), round(parvis.y, 2)], [round(q.x, 2), round(q.y, 2)]])
        u += 10.0
    return None if meilleur is None else meilleur[1:]


def lieux_mission08(tuiles: dict, taille: float, normaliser, spawn, utilises: set) -> list[dict]:
    """Voie ferrée : couloir rectiligne de 280 à 480 m (14 m de large) sans bâtiment, route ni eau, le plus plat possible ; le
    passage à niveau est en son milieu et son cap est celui de la voie. Mare des oies : disque de 14 m de rayon libre, à 60-120 m du
    passage à niveau, d'un côté ou de l'autre de la voie (balayage déterministe). Les joueurs de la mission apparaissent près de la mare."""
    from shapely.strtree import STRtree
    par_xy = {(t["tile"]["x"], t["tile"]["y"]): t for t in tuiles.values()}
    res = None
    longueur = 0.0
    for longueur in RAIL_LENGTHS:
        res = trouver_piste(par_xy, taille, longueur=longueur, largeur=RAIL_WIDTH)
        if res:
            break
    if not res:
        return []
    _, cap, cx, cz = res
    a = math.radians(cap)
    d = (math.sin(a), math.cos(a))
    p = (-d[1], d[0])
    obstacles = []
    for t in tuiles.values():
        obstacles += [Polygon(b["footprint"]).buffer(3.0) for b in t["buildings"]]
        obstacles += [LineString(r["points"]).buffer(r["width"] / 2 + 2.0) for r in t["roads"] if r["kind"] not in ("footway", "track")]
        obstacles += [Polygon(v["polygon"]) for v in t["vegetation"] if v["kind"] == "water"]
    arbre = STRtree(obstacles)
    voie = LineString([(cx - d[0] * longueur / 2, cz - d[1] * longueur / 2), (cx + d[0] * longueur / 2, cz + d[1] * longueur / 2)])
    pond = None
    for dist in (80.0, 70.0, 90.0, 100.0, 60.0, 110.0, 120.0):
        for s in (1, -1):
            for dec in (0.0, 40.0, -40.0, 80.0, -80.0):
                px = cx + p[0] * dist * s + d[0] * dec
                pz = cz + p[1] * dist * s + d[1] * dec
                if (int(px // taille), int(pz // taille)) not in par_xy:
                    continue
                disque = Point(px, pz).buffer(POND_RADIUS + 3.0)
                if any(obstacles[i].intersects(disque) for i in arbre.query(disque)):
                    continue
                if voie.distance(Point(px, pz)) < POND_RADIUS + 8.0:
                    continue
                pond = (px, pz)
                break
            if pond:
                break
        if pond:
            break
    if not pond:
        return []
    # La voie est orientée de la gare vers le passage à niveau : le train vient du côté de la gare (cap inversé si besoin).
    dr = (-d[0], -d[1])
    f = math.atan2(dr[0], dr[1])
    out = [
        _poi8("passage_niveau", LABELS_M08["passage_niveau"], cx, cz, f, taille, "block", prop="rail", radius=14.0, length=longueur),
        _poi8("etang_oies", LABELS_M08["etang_oies"], pond[0], pond[1], math.atan2(cx - pond[0], cz - pond[1]), taille, "gather", prop="pond", radius=POND_RADIUS),
    ]
    gare = _gare(tuiles, taille, cx, cz, dr, longueur, obstacles)
    if gare:
        u, cote, chemin = gare
        g = _poi8("gare_pays_frouch", LABELS_M08["gare_pays_frouch"], cx + dr[0] * u, cz + dr[1] * u, f, taille, "station", prop="gare", radius=40.0, kind="landmark")
        g["side"] = -cote           # +1 : côté +X local (droite en suivant le cap de la voie)
        g["path"] = chemin
        out.append(g)
    return out


# --- Édifices publics et industriels : mairie, écoles, hôpital, usine de calva (modèles détaillés côté Godot) -------------------
LABELS_PUBLICS = {
    "mairie": "Mairie de Frouch City",
    "ecole_pommiers": "École primaire des Pommiers",
    "college_bocage": "Collège du Bocage",
    "hopital_frouch": "Hôpital de Frouch",
    "usine_calva": "Distillerie Pommier & Fils (usine de calva)",
    "carriere_pierres": "Carrière de pierres du Bocage",
}
FACILITIES = ("eglise", "mairie", "ecole", "hopital", "usine")


def _rect_orienté(footprint, facing: float):
    """Rectangle englobant orienté du bâtiment : (cx, cz, largeur le long de la façade, profondeur, cap aligné sur un axe du rectangle,
    rectangularité = aire / aire du rectangle). Le cap est ramené à l'axe du rectangle le plus proche de `facing`."""
    poly = Polygon(footprint)
    mr = poly.minimum_rotated_rectangle
    pts = list(mr.exterior.coords)[:4]
    e1 = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
    e2 = (pts[2][0] - pts[1][0], pts[2][1] - pts[1][1])
    l1, l2 = math.hypot(*e1), math.hypot(*e2)
    n = (math.sin(facing), math.cos(facing))
    best = None
    for axe, lg, lat, lat_l in ((e1, l1, e2, l2), (e2, l2, e1, l1)):
        for s in (1, -1):
            u = (axe[0] / lg * s, axe[1] / lg * s)
            sc = u[0] * n[0] + u[1] * n[1]
            if best is None or sc > best[0]:
                best = (sc, u, lg, lat_l)
    _, u, prof, larg = best
    c = mr.centroid
    return c.x, c.y, larg, prof, math.atan2(u[0], u[1]), poly.area / max(mr.area, 1e-6)


# Débordement du modèle hors de son rectangle (mesuré par qa/integration/landmarks_audit.gd) : (latéral, avant, arrière) en mètres.
# « Avant » est le côté du cap, c'est-à-dire la rue : perron, cour de récréation, parking…
MARGES_EDIFICE = {"mairie": (0.6, 4.7, 0.5), "ecole": (3.3, 14.2, 0.6), "hopital": (6.2, 12.0, 0.5), "usine": (6.2, 15.0, 0.5)}
# Dimensions minimales du modèle (il agrandit sinon son rectangle d'office).
MINI_EDIFICE = {"mairie": (14.0, 9.0), "ecole": (8.0, 8.0), "hopital": (14.0, 18.0), "usine": (10.0, 16.0)}


def _boite(cx: float, cz: float, cap: float, w: float, d: float, lat: float, avant: float, arriere: float, dx: float = 0.0, dz: float = 0.0) -> Polygon:
    """Rectangle orienté (repère local : +Z = cap, +X = droite) centré en (cx, cz) + décalage local (dx, dz), élargi des marges."""
    ux, uz = math.sin(cap), math.cos(cap)
    vx, vz = math.cos(cap), -math.sin(cap)
    ox, oz = cx + vx * dx + ux * dz, cz + vz * dx + uz * dz
    pts = []
    for lx, lz in ((-w / 2 - lat, -d / 2 - arriere), (w / 2 + lat, -d / 2 - arriere), (w / 2 + lat, d / 2 + avant), (-w / 2 - lat, d / 2 + avant)):
        pts.append((ox + vx * lx + ux * lz, oz + vz * lx + uz * lz))
    return Polygon(pts)


def ajuster_edifice(footprint, cx: float, cz: float, w: float, d: float, cap: float, facility: str, couloirs):
    """Plus grand rectangle (≤ rectangle englobant) dont le corps tient dans l'empreinte du bâtiment et dont tout le modèle
    (perron, cour…) reste hors des chaussées (`couloirs` : zones de route élargies). Renvoie (cx, cz, w, d) ou None."""
    lat, avant, arriere = MARGES_EDIFICE[facility]
    mw, md = MINI_EDIFICE[facility]
    poly = Polygon(footprint)
    meilleur = None
    for sw in (1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6, 0.55, 0.5):
        for sd in (1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6, 0.55, 0.5):
            nw, nd = w * sw, d * sd
            if nw < mw or nd < md:
                continue
            for fx in (-1.0, -0.5, 0.0, 0.5, 1.0):
                for fz in (-1.0, -0.5, 0.0, 0.5, 1.0):
                    dx, dz = fx * (w - nw) / 2.0, fz * (d - nd) / 2.0
                    corps = _boite(cx, cz, cap, nw, nd, 0, 0, 0, dx, dz)
                    if corps.difference(poly).area > 0.03 * corps.area:
                        continue
                    if couloirs is not None and _boite(cx, cz, cap, nw, nd, lat, avant, arriere, dx, dz).intersection(couloirs).area > 0.3:
                        continue
                    if meilleur is None or nw * nd > meilleur[0]:
                        c = corps.centroid
                        meilleur = (nw * nd, c.x, c.y, nw, nd)
    if meilleur is None:
        return None
    return meilleur[1], meilleur[2], meilleur[3], meilleur[4]


def lieux_publics(tuiles: dict, taille: float, spawn, pois: list[dict]) -> list[dict]:
    """Choisit, parmi les bâtiments sans enseigne ni lieu de mission, ceux qui deviennent la mairie (proche de l'église), deux écoles,
    l'hôpital (le plus grand rectangle) et l'usine de calva (grande halle de brique), et annote l'église. Déterministe ; les POI existants
    ne bougent pas (on ne prend que des bâtiments libres)."""
    routes = [LineString(r["points"]) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")]
    from shapely.ops import unary_union
    couloirs = unary_union([LineString(r["points"]).buffer(float(r.get("width", 5.0)) / 2.0 + 0.5) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "track")])
    pris = {p["building"] for p in pois if p.get("building")}
    batiments = [b for t in tuiles.values() for b in t["buildings"] if b["id"] not in pris]
    eglise = next((p for p in pois if p["id"] == "eglise"), None)

    def infos(b):
        (x, z), f = emplacement_enseigne(b["footprint"], routes)
        cx, cz, w, d, cap, rect = _rect_orienté(b["footprint"], f)
        return {"b": b, "c": (cx, cz), "w": w, "d": d, "cap": cap, "rect": rect, "aire": Polygon(b["footprint"]).area}

    cand = [i for i in (infos(b) for b in batiments if b["typology"] != "eglise") if i["rect"] >= 0.72 and routes]
    cand.sort(key=lambda i: i["b"]["id"])
    out: list[dict] = []
    utilises: list[tuple[float, float]] = []

    def dist(a, b):
        return math.hypot(a[0] - b[0], a[1] - b[1])

    def cale(i, facility):
        """Copie de `i` dont le rectangle est ajusté pour que le modèle ne morde ni sur la rue ni hors de l'empreinte ; None si impossible."""
        r = ajuster_edifice(i["b"]["footprint"], i["c"][0], i["c"][1], i["w"], i["d"], i["cap"], facility, couloirs)
        if r is None:
            return None
        return {**i, "c": (r[0], r[1]), "w": r[2], "d": r[3]}

    def prendre(i, pid, label, facility):
        utilises.append(i["c"])
        p = {"id": pid, "kind": "landmark", "label": label, "position": [_r(i["c"][0]), _r(i["c"][1])],
             "tile": f"{int(i['c'][0] // taille)}_{int(i['c'][1] // taille)}", "radius": 12.0, "source": "design",
             "building": i["b"]["id"], "facing": _r(i["cap"]), "facility": facility, "rect": [_r(i["w"]), _r(i["d"])]}
        out.append(p)
        return p

    centre_eglise = None
    if eglise is not None:
        b_eg = next((b for t in tuiles.values() for b in t["buildings"] if b["id"] == eglise.get("building")), None)
        if b_eg is not None:
            ie = infos(b_eg)
            centre_eglise = ie["c"]
            eglise["facility"] = "eglise"
            eglise["rect"] = [_r(ie["w"]), _r(ie["d"])]
            eglise["position"] = [_r(ie["c"][0]), _r(ie["c"][1])]
            eglise["facing"] = _r(ie["cap"])
            utilises.append(ie["c"])
    ref = centre_eglise or tuple(spawn)
    # Mairie : 250-800 m², à 40-250 m de l'église, la plus proche.
    mairies = sorted((i for i in cand if 250 <= i["aire"] <= 800 and 40 <= dist(i["c"], ref) <= 250 and 12 <= i["w"] and 9 <= i["d"]),
                     key=lambda i: (dist(i["c"], ref), i["b"]["id"]))
    for i in mairies:
        j = cale(i, "mairie")
        if j is not None:
            prendre(j, "mairie", LABELS_PUBLICS["mairie"], "mairie")
            break
    # Écoles : 300-900 m², à 120-700 m du centre, éloignées de 150 m entre elles et des autres édifices ; la seconde plus grande.
    ecoles = sorted((i for i in cand if 300 <= i["aire"] <= 900 and 120 <= dist(i["c"], tuple(spawn)) <= 700), key=lambda i: (_h("ecole", i["b"]["id"]), i["b"]["id"]))
    choisies = []
    for i in ecoles:
        j = cale(i, "ecole") if all(dist(i["c"], u) >= 150 for u in utilises) and all(dist(i["c"], c["c"]) >= 150 for c in choisies) else None
        if j is not None:
            choisies.append(j)
        if len(choisies) == 2:
            break
    choisies.sort(key=lambda i: i["aire"])
    for i, (pid, fac) in zip(choisies, (("ecole_pommiers", "ecole"), ("college_bocage", "ecole"))):
        prendre(i, pid, LABELS_PUBLICS[pid], fac)
    # Hôpital : le plus grand rectangle libre (≥ 700 m²), loin des autres édifices ; usine : grande halle de brique (≥ 500 m²).
    hop = sorted((i for i in cand if i["aire"] >= 700 and all(dist(i["c"], u) >= 120 for u in utilises)), key=lambda i: (-i["aire"], i["b"]["id"]))
    for i in hop:
        j = cale(i, "hopital")
        if j is not None:
            prendre(j, "hopital_frouch", LABELS_PUBLICS["hopital_frouch"], "hopital")
            break
    usines = sorted((i for i in cand if i["aire"] >= 500 and i["b"]["typology"] in ("brique", "annexe", "commerce") and all(dist(i["c"], u) >= 120 for u in utilises)),
                    key=lambda i: (-i["aire"], i["b"]["id"]))
    for i in usines:
        j = cale(i, "usine")
        if j is not None:
            prendre(j, "usine_calva", LABELS_PUBLICS["usine_calva"], "usine")
            break
    return out


def poi_carriere(site, taille: float) -> dict:
    """POI de la carrière (prop `carriere`, rayon du bord ; `facing` = cap de la rampe d'accès, vers le bourg)."""
    cx, cz, cap = site
    return {"id": "carriere_pierres", "kind": "landmark", "label": "Carrière de pierres du Bocage", "position": [_r(cx), _r(cz)],
            "tile": f"{int(cx // taille)}_{int(cz // taille)}", "radius": 62.0, "source": "design", "facing": _r(cap), "prop": "carriere"}


# ---------------------------------------------------------------------------------------------------------------------------------
# Décors de mission : aucun ne traverse un mur ni ne bloque la chaussée.
# Emprise locale (xmin, xmax, zmin, zmax) en mètres dans le repère du POI (+Z = cap, vers la rue), mesurée sur les maillages réels de
# `CityBuilder._add_prop` par qa/integration/props_audit.gd (ligne « EXT »). À mettre à jour si un décor change de taille.
EMPRISE_DECOR = {
    "fete": (-4.1, 5.4, -2.5, 0.5), "stage": (-3.5, 3.5, -1.8, 1.8), "pyre": (-2.5, 2.5, -2.3, 2.3), "pressoir": (-3.2, 4.1, -0.9, 1.8),
    "coop": (1.4, 4.2, 0.4, 3.6), "garage": (2.0, 4.0, 0.6, 1.6), "junkyard": (-4.3, 5.8, 0.2, 4.3), "stand": (-1.9, 1.9, -0.7, 0.8),
    "wc": (-0.8, 0.8, -0.8, 0.8), "fumier": (-1.5, 1.5, -1.5, 1.5),
}
MARGE_DECOR = 0.35          # m de dégagement autour de l'emprise
RAYON_DECOR = 32.0          # m : distance maximale de déplacement


def _rect_decor(x: float, z: float, cap: float, e: tuple) -> Polygon:
    c, s = math.cos(cap), math.sin(cap)
    pts = []
    for lx, lz in ((e[0] - MARGE_DECOR, e[2] - MARGE_DECOR), (e[1] + MARGE_DECOR, e[2] - MARGE_DECOR),
                   (e[1] + MARGE_DECOR, e[3] + MARGE_DECOR), (e[0] - MARGE_DECOR, e[3] + MARGE_DECOR)):
        pts.append((x + lx * c + lz * s, z - lx * s + lz * c))     # Basis(UP, cap) * (lx, 0, lz) projeté sur (x, z)
    return Polygon(pts)


def degager_decors(pois: list[dict], tuiles: dict, taille: float) -> int:
    """Déplace (par le plus petit déplacement possible, orientation d'origine d'abord) tout décor de mission dont l'emprise mord sur un
    bâtiment ou sur la chaussée. Renvoie le nombre de décors déplacés. Déterministe."""
    from shapely.strtree import STRtree
    obst: list[Polygon] = [Polygon(b["footprint"]) for t in tuiles.values() for b in t["buildings"]]
    for t in tuiles.values():
        for r in t["roads"]:
            if r["kind"] in ("footway", "track"):
                continue
            obst.append(LineString(r["points"]).buffer(float(r.get("width", 5.0)) / 2.0 + 0.2))
    arbre = STRtree(obst)

    def gene(rect: Polygon) -> float:
        return sum(obst[int(i)].intersection(rect).area for i in arbre.query(rect))

    occupes: list[Polygon] = []
    deplaces = 0
    for p in sorted((p for p in pois if p.get("prop") in EMPRISE_DECOR), key=lambda p: p["id"]):
        e = EMPRISE_DECOR[p["prop"]]
        x0, z0 = p["position"]
        f0 = float(p.get("facing", 0.0))
        rect0 = _rect_decor(x0, z0, f0, e)
        if gene(rect0) <= 0.05 and not any(rect0.intersects(o) for o in occupes):
            occupes.append(rect0)
            continue
        cands = []
        n = int(RAYON_DECOR)
        for dx in range(-n, n + 1):
            for dz in range(-n, n + 1):
                d = math.hypot(dx, dz)
                if d <= RAYON_DECOR:
                    for k, rot in enumerate((0.0, math.pi / 2, -math.pi / 2, math.pi)):
                        cands.append((d + (0.0 if k == 0 else 1.5), dx, dz, f0 + rot))
        cands.sort()
        for _, dx, dz, f in cands:
            r = _rect_decor(x0 + dx, z0 + dz, f, e)
            if gene(r) <= 0.05 and not any(r.intersects(o) for o in occupes):
                p["position"] = [_r(x0 + dx), _r(z0 + dz)]
                p["facing"] = _r(f)
                p["tile"] = f"{int((x0 + dx) // taille)}_{int((z0 + dz) // taille)}"
                occupes.append(r)
                deplaces += 1
                break
        else:
            occupes.append(rect0)
    return deplaces
