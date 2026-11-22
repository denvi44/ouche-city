"""Construction des tuiles de Frouch City depuis le cache OSM.

Usage :
    python -m gis.build            # tuiles du POC (rue Sainte-Foy) + graphe routier + POI
    python -m gis.build --toutes   # toutes les tuiles de l'emprise 3 × 3 km

Entrée : gis/cache/osm_conches.json (python -m gis.fetch).
Sorties (conformes à contracts/) : gis/out/tiles/<x>_<y>.json, gis/out/road_graph.json, gis/out/poi.json.

Repère local : x vers l'est, z vers le sud (convention Godot, y = haut), en mètres,
origine au coin nord-ouest de l'emprise. Les sorties sont déterministes (tri par identifiant OSM).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from dataclasses import dataclass
from pathlib import Path

from pyproj import Transformer
from shapely.geometry import LineString, MultiLineString, MultiPolygon, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import nearest_points

from . import fiction, nivelage, vegetation
from .config import GIS_DIR, Emprise, charger

CACHE_OSM = GIS_DIR / "cache" / "osm_conches.json"
CACHE_IGN = GIS_DIR / "cache" / "ign_bdtopo.json"
CACHE_ALTI = GIS_DIR / "cache" / "ign_alti.json"
ATTR_IGN = "Source : IGN — BD TOPO, RGE ALTI (Licence Ouverte Etalab 2.0)"
OUT_DIR = GIS_DIR / "out"
ATTR_OSM = "© contributeurs OpenStreetMap (ODbL 1.0)"

# --- Tables de correspondance OSM → contrat ---------------------------------

ROAD_KIND = {
    "motorway": "primary", "trunk": "primary", "primary": "primary", "primary_link": "primary",
    "secondary": "secondary", "secondary_link": "secondary",
    "tertiary": "tertiary", "tertiary_link": "tertiary",
    "residential": "residential", "unclassified": "residential", "living_street": "residential",
    "service": "service",
    "pedestrian": "pedestrian",
    "footway": "footway", "path": "footway", "cycleway": "footway", "steps": "footway",
    "track": "track",
}
ROAD_WIDTH = {"primary": 7.0, "secondary": 6.5, "tertiary": 6.0, "residential": 5.0,
              "service": 3.5, "pedestrian": 5.0, "footway": 2.0, "track": 3.0}
ROAD_SPEED = {"primary": 50, "secondary": 50, "tertiary": 50, "residential": 30,
              "service": 20, "pedestrian": 10, "footway": 5, "track": 20}
SIDEWALK = {"primary": 1.8, "secondary": 1.6, "tertiary": 1.5, "residential": 1.2}

VEGETATION = {
    ("landuse", "grass"): "grass", ("landuse", "meadow"): "grass", ("landuse", "village_green"): "grass",
    ("leisure", "park"): "park", ("leisure", "garden"): "garden", ("leisure", "pitch"): "grass",
    ("landuse", "forest"): "forest", ("natural", "wood"): "forest", ("natural", "scrub"): "forest",
    ("landuse", "farmland"): "farmland", ("landuse", "orchard"): "farmland",
    ("natural", "water"): "water", ("landuse", "basin"): "water", ("landuse", "reservoir"): "water",
}

CHURCH = {"church", "chapel", "cathedral"}
ANNEXE = {"garage", "garages", "shed", "roof", "carport", "hut", "greenhouse", "barn"}
PUBLIC = {"public", "civic", "townhall", "school", "government", "college", "hospital", "train_station", "fire_station", "castle"}
HOUSE = {"house", "detached", "semidetached_house", "bungalow", "residential"}
COMMERCE_AMENITY = {"restaurant", "cafe", "bar", "pub", "fast_food", "bank", "pharmacy"}
PUBLIC_AMENITY = {"townhall", "school", "library", "post_office", "police", "fire_station"}
ROOF = {"flat": "flat", "gabled": "gabled", "hipped": "hipped", "pyramidal": "hipped", "spire": "spire"}

# Libellés génériques (aucun nom de commerce réel n'est conservé).
LIBELLE_COMMERCE = {
    "bakery": "Boulangerie", "butcher": "Boucherie", "supermarket": "Supérette", "convenience": "Épicerie",
    "hairdresser": "Salon de coiffure", "florist": "Fleuriste", "clothes": "Boutique de vêtements",
    "restaurant": "Restaurant", "cafe": "Café", "bar": "Bar", "pub": "Bar", "fast_food": "Snack",
    "bank": "Banque", "pharmacy": "Pharmacie", "car_repair": "Garage", "newsagent": "Maison de la presse",
    "tobacco": "Bureau de tabac",
}


def _hash01(*parts) -> float:
    """Pseudo-aléatoire déterministe dans [0, 1[."""
    h = hashlib.sha1("|".join(map(str, parts)).encode()).hexdigest()
    return int(h[:8], 16) / 0x100000000


def nom_fictif(nom: str | None) -> str | None:
    """Noms de rues : la ville s'appelle simplement « Frouch » (« Guillaume de Conches » -> « Guillaume de Frouch »)."""
    return nom.replace("Conches-en-Frouch", "Frouch").replace("Conches", "Frouch") if nom else nom


def normaliser_nom(nom: str | None) -> str:
    """« Rue Sainte-Foy » == « Rue Sainte Foy » == « rue sainte foy » (noms BAN sans tirets ni accents)."""
    import unicodedata
    if not nom:
        return ""
    n = unicodedata.normalize("NFKD", nom).encode("ascii", "ignore").decode()
    return " ".join(n.lower().replace("-", " ").replace("'", " ").split())


def _r(v: float) -> float:
    return round(float(v), 2)


@dataclass
class Repere:
    """Projection WGS84 → repère local de l'emprise (x est, z sud)."""

    emp: Emprise

    def __post_init__(self):
        self._t = Transformer.from_crs("EPSG:4326", "EPSG:2154", always_xy=True)
        cx, cy = self._t.transform(self.emp.centre_lon, self.emp.centre_lat)
        self.x0 = cx - self.emp.demi_cote_m
        self.y0 = cy + self.emp.demi_cote_m
        self.centre = (self.emp.demi_cote_m, self.emp.demi_cote_m)

    def local(self, lat: float, lon: float) -> tuple[float, float]:
        e, n = self._t.transform(lon, lat)
        return e - self.x0, self.y0 - n

    def wgs(self, x: float, z: float) -> tuple[float, float]:
        """Repère local → (lon, lat)."""
        if not hasattr(self, "_inv"):
            self._inv = Transformer.from_crs("EPSG:2154", "EPSG:4326", always_xy=True)
        return self._inv.transform(x + self.x0, self.y0 - z)

    @property
    def nb_tuiles(self) -> int:
        return int(math.ceil(2 * self.emp.demi_cote_m / self.emp.taille_tuile_m))


# --- Lecture des sources -------------------------------------------------------

def _lire(path: Path, rep: Repere):
    data = json.loads(path.read_text(encoding="utf-8"))
    nodes, ways, points = {}, [], []
    for el in data["elements"]:
        if el["type"] == "node":
            nodes[el["id"]] = rep.local(el["lat"], el["lon"])
            if el.get("tags"):
                points.append(el)
    for el in data["elements"]:
        if el["type"] == "way" and el.get("tags"):
            coords = [nodes[n] for n in el["nodes"] if n in nodes]
            if len(coords) >= 2:
                ways.append({"id": el["id"], "tags": el["tags"], "nodes": el["nodes"], "coords": coords})
    ways.sort(key=lambda w: abs(w["id"]))
    points.sort(key=lambda p: p["id"])
    return nodes, ways, points, data.get("_frouch", {})


@dataclass
class Sources:
    nodes: dict
    ways: list
    points: list
    meta: list
    attribution: list


def charger_sources(rep: Repere, cache_ign: Path | None, cache_osm: Path | None) -> Sources:
    """Géométries : IGN BD TOPO si présent (hauteurs mesurées), sinon OSM. POI et arbres : OSM."""
    meta, attribution = [], []
    nodes, ways, points = {}, [], []
    osm = _lire(cache_osm, rep) if cache_osm and cache_osm.exists() else None
    if cache_ign and cache_ign.exists():
        nodes, ways, _, m = _lire(cache_ign, rep)
        meta.append(m)
        attribution.append(ATTR_IGN)
    elif osm:
        nodes, ways = osm[0], osm[1]
    if osm:
        points = osm[2]
        meta.append(osm[3])
        attribution.insert(0, ATTR_OSM)
        nodes = {**osm[0], **nodes}
    if not ways:
        raise FileNotFoundError("aucune source : lancer python -m gis.fetch_ign ou python -m gis.fetch")
    return Sources(nodes, ways, points, meta, attribution)


class Relief:
    """Grille d'altitudes absolues (m) sur le repère local, interpolée bilinéairement."""

    def __init__(self, path: Path | None):
        self.grid = None
        if path and path.exists():
            d = json.loads(path.read_text(encoding="utf-8"))
            self.step, self.n, self.z = float(d["step"]), int(d["n"]), d["z"]
            self.grid = True

    def altitude(self, x: float, z: float) -> float:
        if not self.grid:
            return 0.0
        gx = min(max(x / self.step, 0.0), self.n - 1.001)
        gz = min(max(z / self.step, 0.0), self.n - 1.001)
        i, j = int(gx), int(gz)
        fx, fz = gx - i, gz - j
        def at(a, b):
            return self.z[b * self.n + a]
        top = at(i, j) * (1 - fx) + at(i + 1, j) * fx
        bot = at(i, j + 1) * (1 - fx) + at(i + 1, j + 1) * fx
        return top * (1 - fz) + bot * fz


def _polygone(coords) -> Polygon | None:
    if len(coords) < 4 or coords[0] != coords[-1]:
        return None
    p = Polygon(coords)
    if not p.is_valid:
        p = p.buffer(0)
    if p.is_empty or p.area < 1.0:
        return None
    if isinstance(p, MultiPolygon):
        p = max(p.geoms, key=lambda g: g.area)
    return p


def _ring(poly: Polygon) -> list[list[float]]:
    """Anneau extérieur antihoraire vu du dessus (aire signée négative en (x, z) car z pointe au sud)."""
    poly = orient(poly.simplify(0.25, preserve_topology=True), sign=-1.0)
    pts = [[_r(x), _r(z)] for x, z in poly.exterior.coords[:-1]]
    dedup = [p for i, p in enumerate(pts) if p != pts[i - 1]]
    return dedup


# --- Bâtiments ---------------------------------------------------------------

def typologie(tags: dict, poly: Polygon, rep: Repere, commerces: list[Point]) -> str:
    b = tags.get("building", "yes")
    if b in CHURCH or tags.get("amenity") == "place_of_worship":
        return "eglise"
    if b in ANNEXE or poly.area < 25:
        return "annexe"
    if b in PUBLIC or tags.get("amenity") in PUBLIC_AMENITY:
        return "public"
    if b in {"retail", "commercial", "shop"} or tags.get("shop") or any(poly.contains(c) for c in commerces):
        return "commerce"
    c = poly.centroid
    dist = math.dist((c.x, c.y), rep.centre)
    if dist > rep.emp.rayon_centre_m:
        return "pavillon" if b in HOUSE or b == "yes" else "brique"
    return "colombages" if _hash01("typo", round(c.x), round(c.y)) < 0.6 else "brique"


def hauteur(tags: dict, typo: str, seed: float) -> tuple[float, int]:
    if "height" in tags:
        try:
            h = float(str(tags["height"]).replace("m", "").strip())
            return max(2.5, min(h, 80.0)), max(1, round(h / 3))
        except ValueError:
            pass
    if "building:levels" in tags:
        try:
            lv = max(1, int(float(tags["building:levels"])))
            return lv * 3.0 + 1.0, lv
        except ValueError:
            pass
    defaut = {"colombages": (2, 3), "brique": (2, 3), "commerce": (2, 3), "pavillon": (1, 2),
              "public": (2, 3), "annexe": (1, 1), "eglise": (6, 6)}[typo]
    lv = defaut[0] + int(seed * (defaut[1] - defaut[0] + 1))
    lv = min(lv, defaut[1])
    h = {"annexe": 3.2, "eglise": 18.0}.get(typo, lv * 3.0 + 1.0)
    return h, lv


def toit(tags: dict, typo: str, poly: Polygon) -> str:
    if tags.get("roof:shape") in ROOF:
        return ROOF[tags["roof:shape"]]
    if typo == "eglise":
        return "spire"
    if typo == "annexe" or poly.area > 600:
        return "flat"
    return "gabled"


# --- Construction ------------------------------------------------------------

CARRIERE = None  # site de la carrière (cx, cz, cap de la rampe), fixé par construire()
GROUND_RES = nivelage.RES  # 51 × 51 points par tuile : un point tous les 5 m (routes nivelées, voir nivelage.py)


def construire(src: Sources, rep: Repere, relief: Relief, emp: Emprise, toutes: bool):
    nodes, ways, points = src.nodes, src.ways, src.points
    commerces = [Point(rep.local(p["lat"], p["lon"])) for p in points
                 if "shop" in p["tags"] or p["tags"].get("amenity") in COMMERCE_AMENITY]

    T = emp.taille_tuile_m
    n = rep.nb_tuiles

    # Zone du POC : autour du centre de gravité de la rue choisie.
    cible = normaliser_nom(emp.poc_rue)
    rue = [w for w in ways if w["tags"].get("highway") and normaliser_nom(w["tags"].get("name")) == cible]
    if rue:
        # Point de la chaussée le plus proche du centre de gravité (une rue courbe a son centroïde dans un îlot).
        lignes = MultiLineString([w["coords"] for w in rue])
        poc_centre = nearest_points(lignes, lignes.centroid)[0]
    else:
        poc_centre = Point(rep.centre)
    zone = poc_centre.buffer(emp.poc_rayon_m) if not toutes else box(0, 0, n * T, n * T)
    ref = round(relief.altitude(poc_centre.x, poc_centre.y), 1)

    def hauteur_sol(x, z):
        return relief.altitude(x, z) - ref

    tuiles: dict[tuple[int, int], dict] = {}

    def tuiles_de(geom):
        minx, miny, maxx, maxy = geom.bounds
        for tx in range(max(0, int(minx // T)), min(n - 1, int(maxx // T)) + 1):
            for ty in range(max(0, int(miny // T)), min(n - 1, int(maxy // T)) + 1):
                if box(tx * T, ty * T, (tx + 1) * T, (ty + 1) * T).intersects(zone):
                    yield tx, ty

    for tx, ty in tuiles_de(zone):
        heights = [_r(hauteur_sol(tx * T + i * T / (GROUND_RES - 1), ty * T + j * T / (GROUND_RES - 1)))
                   for j in range(GROUND_RES) for i in range(GROUND_RES)]
        tuiles[(tx, ty)] = {"schemaVersion": 1, "tile": {"x": tx, "y": ty}, "origin": [tx * T, ty * T],
                            "size": T, "scale": 1,
                            "ground": {"resolution": GROUND_RES, "baseAltitude": ref, "heights": heights},
                            "buildings": [], "roads": [], "vegetation": [], "trees": [],
                            "attribution": src.attribution}
    garder = set(tuiles)

    for w in ways:
        tags = w["tags"]
        if "building" in tags and tags.get("building") != "no":
            poly = _polygone(w["coords"])
            if poly is None or not poly.intersects(zone):
                continue
            c = poly.representative_point()
            key = (int(c.x // T), int(c.y // T))
            if key not in garder:
                continue
            typo = typologie(tags, poly, rep, commerces)
            h, lv = hauteur(tags, typo, _hash01("h", w["id"]))
            ring = _ring(poly)
            if len(ring) < 3:
                continue
            ground_z = min(hauteur_sol(x, z) for x, z in ring)
            tuiles[key]["buildings"].append({
                "id": f"b_{abs(w['id'])}", "footprint": ring, "height": _r(h), "levels": lv,
                "roof": toit(tags, typo, poly), "typology": typo, "groundZ": _r(ground_z),
            })
        elif tags.get("highway") in ROAD_KIND:
            line = LineString(w["coords"])
            if not line.intersects(zone):
                continue
            kind = ROAD_KIND[tags["highway"]]
            try:
                width = float(str(tags.get("width", "")).replace("m", "").strip())
            except ValueError:
                width = ROAD_WIDTH[kind]
            if width <= 0:
                width = ROAD_WIDTH[kind]
            surface = "pavers" if tags.get("surface") in {"paving_stones", "sett", "cobblestone"} else (
                "gravel" if tags.get("surface") in {"gravel", "fine_gravel", "compacted", "unpaved"} or kind == "track"
                else "asphalt")
            for tx, ty in tuiles_de(line):
                if (tx, ty) not in garder:
                    continue
                part = line.intersection(box(tx * T, ty * T, (tx + 1) * T, (ty + 1) * T))
                for i, g in enumerate(getattr(part, "geoms", [part])):
                    if g.is_empty or g.geom_type != "LineString" or g.length < 0.5:
                        continue
                    g = g.segmentize(4.0)  # densifié pour épouser le relief
                    tuiles[(tx, ty)]["roads"].append({
                        "id": f"r_{abs(w['id'])}_{i}", "name": nom_fictif(tags.get("name")), "kind": kind,
                        "points": [[_r(x), _r(z)] for x, z in g.coords], "width": _r(width),
                        "sidewalk": SIDEWALK.get(kind, 0.0), "oneway": tags.get("oneway") == "yes",
                        "surface": surface,
                    })
        else:
            kind = next((v for (k, val), v in VEGETATION.items() if tags.get(k) == val), None)
            if kind is None:
                continue
            poly = _polygone(w["coords"])
            if poly is None or not poly.intersects(zone):
                continue
            for tx, ty in tuiles_de(poly):
                if (tx, ty) not in garder:
                    continue
                part = poly.intersection(box(tx * T, ty * T, (tx + 1) * T, (ty + 1) * T))
                for g in getattr(part, "geoms", [part]):
                    if g.geom_type == "Polygon" and g.area >= 4:
                        ring = _ring(g)
                        if len(ring) >= 3:
                            tuiles[(tx, ty)]["vegetation"].append({"kind": kind, "polygon": ring})

    for p in points:
        if p["tags"].get("natural") == "tree":
            x, z = rep.local(p["lat"], p["lon"])
            key = (int(x // T), int(z // T))
            if key in garder and zone.contains(Point(x, z)):
                tuiles[key]["trees"].append([_r(x), _r(z)])

    # Carrière : site libre (ni bâtiment, ni route, ni eau) ; le relief est creusé en même temps que les routes sont nivelées.
    obstacles = [Polygon(b["footprint"]).buffer(10.0) for t in tuiles.values() for b in t["buildings"]]
    obstacles += [LineString(r["points"]).buffer(r["width"] / 2 + 10.0) for t in tuiles.values() for r in t["roads"] if r["kind"] not in ("footway", "path")]
    obstacles += [Polygon(v["polygon"]).buffer(10.0) for t in tuiles.values() for v in t["vegetation"] if v["kind"] == "water"]
    global CARRIERE
    CARRIERE = nivelage.site_carriere(tuiles, T, (poc_centre.x, poc_centre.y), obstacles)
    nivelage.niveler(tuiles, T, hauteur_sol, CARRIERE)
    stats = vegetation.planter(tuiles, T, CARRIERE, nivelage.CARRIERE_R)
    print("végétation :", stats, "| carrière :", CARRIERE)
    return tuiles, poc_centre, ref


def graphe_routier(ways, nodes, attribution) -> dict:
    """Graphe routier de toute l'emprise : nœuds aux carrefours et extrémités."""
    routes = [w for w in ways if w["tags"].get("highway") in ROAD_KIND]
    compte: dict[int, int] = {}
    for w in routes:
        for i, nid in enumerate(w["nodes"]):
            compte[nid] = compte.get(nid, 0) + (2 if i in (0, len(w["nodes"]) - 1) else 1)
    graph_nodes, edges = {}, []
    for w in routes:
        tags = w["tags"]
        kind = ROAD_KIND[tags["highway"]]
        try:
            speed = int(str(tags.get("maxspeed", "")).split()[0])
        except (ValueError, IndexError):
            speed = ROAD_SPEED[kind]
        ids = [nid for nid in w["nodes"] if nid in nodes]
        start, poly = ids[0], [nodes[ids[0]]]
        for nid in ids[1:]:
            poly.append(nodes[nid])
            if compte.get(nid, 0) >= 2 or nid == ids[-1]:
                for g in (start, nid):
                    graph_nodes[g] = [_r(nodes[g][0]), _r(nodes[g][1])]
                length = sum(math.dist(poly[i], poly[i + 1]) for i in range(len(poly) - 1))
                edges.append({"id": f"e_{w['id']}_{len(edges)}", "from": f"n_{start}", "to": f"n_{nid}",
                              "kind": kind, "name": nom_fictif(tags.get("name")), "oneway": tags.get("oneway") == "yes",
                              "lengthM": _r(length), "speedKmh": speed, "width": ROAD_WIDTH[kind],
                              "points": [[_r(x), _r(z)] for x, z in poly]})
                start, poly = nid, [nodes[nid]]
    return {"schemaVersion": 1,
            "nodes": [{"id": f"n_{k}", "position": v} for k, v in sorted(graph_nodes.items())],
            "edges": edges, "attribution": attribution}


def points_interet(rep: Repere, ways, points, poc_centre, emp, origine: str = "osm") -> dict:
    T = emp.taille_tuile_m
    pois = []

    def ajout(pid, kind, label, x, z, **extra):
        pois.append({"id": pid, "kind": kind, "label": label, "position": [_r(x), _r(z)],
                     "tile": f"{int(x // T)}_{int(z // T)}", **extra})

    ajout("spawn_rue_sainte_foy", "spawn", emp.poc_rue, poc_centre.x, poc_centre.y, radius=5.0, source=origine)
    vus = set()
    for w in ways:
        t = w["tags"]
        if t.get("amenity") == "place_of_worship" or t.get("building") in CHURCH:
            poly = _polygone(w["coords"])
            if poly is not None and "eglise" not in vus:
                c = poly.centroid
                ajout("eglise_lointaine", "landmark", fiction.MONUMENTS["eglise"], c.x, c.y, radius=15.0, source=origine)
                vus.add("eglise")
        if t.get("historic") in {"castle", "tower"} and "donjon" not in vus:
            poly = _polygone(w["coords"]) if w["coords"][0] == w["coords"][-1] else None
            c = poly.centroid if poly is not None else LineString(w["coords"]).centroid
            ajout("donjon", "landmark", "Donjon", c.x, c.y, radius=12.0, source=origine)
            vus.add("donjon")
    for p in points:
        t = p["tags"]
        cat = t.get("shop") or t.get("amenity")
        if cat in LIBELLE_COMMERCE:
            x, z = rep.local(p["lat"], p["lon"])
            ajout(f"commerce_osm_{p['id']}", "shop", fiction.nom_commerce_generique(p["id"]), x, z, source="design")
    return {"schemaVersion": 4, "pois": pois}


def ecrire(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--toutes", action="store_true", help="toutes les tuiles de l'emprise")
    ap.add_argument("--ign", type=Path, default=CACHE_IGN)
    ap.add_argument("--osm", type=Path, default=CACHE_OSM)
    ap.add_argument("--alti", type=Path, default=CACHE_ALTI)
    ap.add_argument("--out", type=Path, default=OUT_DIR)
    args = ap.parse_args(argv)
    emp = charger()
    rep = Repere(emp)
    try:
        src = charger_sources(rep, args.ign, args.osm)
    except FileNotFoundError as exc:
        print(exc, file=sys.stderr)
        return 1
    relief = Relief(args.alti)
    tuiles, poc_centre, ref = construire(src, rep, relief, emp, args.toutes)
    ecrire(args.out / "road_graph.json", graphe_routier(src.ways, src.nodes, src.attribution))
    poi = points_interet(rep, src.ways, src.points, poc_centre, emp, "ign" if args.ign.exists() else "osm")
    fictifs = fiction.lieux_fictifs(tuiles, emp.taille_tuile_m)
    fictifs += fiction.lieux_mission01(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y))
    deja_pris = {p["building"] for p in fictifs if p.get("building")}
    fictifs += fiction.lieux_mission02(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    deja_pris |= {p["building"] for p in fictifs if p.get("building")}
    fictifs += fiction.lieux_mission03(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    deja_pris |= {p["building"] for p in fictifs if p.get("building")}
    fictifs += fiction.lieux_mission04(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    deja_pris |= {p["building"] for p in fictifs if p.get("building")}
    fictifs += fiction.lieux_mission05(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    fictifs += fiction.lieux_mission06(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    deja_pris |= {p["building"] for p in fictifs if p.get("building")}
    fictifs += fiction.lieux_mission07(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    fictifs += fiction.lieux_mission08(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    deja_pris |= {p["building"] for p in fictifs if p.get("building")}
    fictifs += fiction.lieux_mission09(tuiles, emp.taille_tuile_m, normaliser_nom, (poc_centre.x, poc_centre.y), deja_pris)
    if CARRIERE:
        fictifs.append(fiction.poi_carriere(CARRIERE, emp.taille_tuile_m))
    fictifs += fiction.lieux_publics(tuiles, emp.taille_tuile_m, (poc_centre.x, poc_centre.y), poi["pois"] + fictifs)
    ids_fictifs = {p["id"] for p in fictifs}
    # Les monuments trouvés dans la zone remplacent leurs homologues lointains.
    poi["pois"] = [p for p in poi["pois"] if not (p["id"] == "eglise_lointaine" and "eglise" in ids_fictifs)] + fictifs
    deplaces = fiction.degager_decors(poi["pois"], tuiles, emp.taille_tuile_m)
    print("décors de mission déplacés hors des murs et de la chaussée :", deplaces)
    retires = vegetation.nettoyer(tuiles, poi["pois"])
    print("arbres retirés des lieux de mission :", retires)
    tiles_dir = args.out / "tiles"
    for old in tiles_dir.glob("*.json"):
        old.unlink()
    for (tx, ty), t in sorted(tuiles.items()):
        t["buildings"].sort(key=lambda b: b["id"])
        ecrire(tiles_dir / f"{tx}_{ty}.json", t)

    ecrire(args.out / "poi.json", poi)
    ecrire(args.out / "manifest.json", {
        "sources": src.meta, "attribution": src.attribution, "tiles": [f"{x}_{y}" for x, y in sorted(tuiles)],
        "tileSize": emp.taille_tuile_m, "pocCentre": [_r(poc_centre.x), _r(poc_centre.y)],
        "altitudeReference": ref,
    })
    nb_b = sum(len(t["buildings"]) for t in tuiles.values())
    nb_r = sum(len(t["roads"]) for t in tuiles.values())
    print(f"{len(tuiles)} tuiles, {nb_b} bâtiments, {nb_r} tronçons de route → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
