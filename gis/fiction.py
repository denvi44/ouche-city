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
            label = f"{noms[start]} (annexe {len(deja)})"
        deja.add(label)
        ajout(b, f"commerce_{b['id'][2:]}", "shop", label)

    for typo, label in MONUMENTS.items():
        candidats = [b for b in batiments if b["typology"] == typo]
        if candidats:
            b = max(candidats, key=lambda b: Polygon(b["footprint"]).area)
            ajout(b, {"eglise": "eglise", "public": "salle_des_fetes"}[typo], "landmark", label)
    return pois


def nom_commerce_generique(osm_id) -> str:
    """Nom fictif pour un commerce OSM isolé (hors bâtiment identifié)."""
    categories = sorted(ENSEIGNES)
    noms = ENSEIGNES[categories[_h("cat", osm_id) % len(categories)]]
    return noms[_h("nom", osm_id) % len(noms)]
