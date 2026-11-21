"""Téléchargement IGN (Géoplateforme) : BD TOPO (bâti, routes, végétation, eau) et RGE ALTI (relief).

Les entités BD TOPO sont converties vers le même modèle intermédiaire que le cache OSM
(nœuds + chemins + étiquettes de style OSM) pour que gis.build traite les deux sources à l'identique.
Licence Ouverte Etalab 2.0 — « Source : IGN ».

Usage : python -m gis.fetch_ign
"""
from __future__ import annotations

import datetime as dt
import json
import sys
import time
import urllib.parse
import urllib.request

from .config import GIS_DIR, charger
from .fetch import bbox_wgs84

WFS = "https://data.geopf.fr/wfs/ows"
ALTI = "https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevation.json"
CACHE_PATH = GIS_DIR / "cache" / "ign_bdtopo.json"
ALTI_PATH = GIS_DIR / "cache" / "ign_alti.json"
PAS_ALTI = 50.0  # m
PAGE = 5000

COUCHES = {
    "batiment": "BDTOPO_V3:batiment",
    "route": "BDTOPO_V3:troncon_de_route",
    "vegetation": "BDTOPO_V3:zone_de_vegetation",
    "eau": "BDTOPO_V3:surface_hydrographique",
}


def _get_json(url: str, params: dict, essais: int = 4):
    full = url + "?" + urllib.parse.urlencode(params, safe=":,|")
    for i in range(essais):
        try:
            req = urllib.request.Request(full, headers={"User-Agent": "frouch-city-gis/1.0"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.load(resp)
        except Exception as exc:  # réseau capricieux : on réessaie avec attente croissante
            if i == essais - 1:
                raise
            print(f"  nouvel essai ({exc})", file=sys.stderr)
            time.sleep(2 ** i)


def wfs(typename: str, bbox) -> list[dict]:
    s, w, n, e = bbox
    feats, start = [], 0
    while True:
        data = _get_json(WFS, {
            "SERVICE": "WFS", "VERSION": "2.0.0", "REQUEST": "GetFeature", "TYPENAMES": typename,
            "BBOX": f"{s},{w},{n},{e},urn:ogc:def:crs:EPSG::4326", "OUTPUTFORMAT": "application/json",
            "COUNT": PAGE, "STARTINDEX": start, "SORTBY": "cleabs",
        })
        page = data.get("features", [])
        feats.extend(page)
        if len(page) < PAGE:
            return feats
        start += PAGE


# --- Conversion BD TOPO → étiquettes de style OSM -------------------------------

def tags_batiment(p: dict) -> dict:
    nature, usage = p.get("nature") or "", p.get("usage_1") or ""
    if nature in {"Eglise", "Chapelle"} or usage == "Religieux":
        b = "church"
    elif nature in {"Château", "Tour, donjon", "Fort, blockhaus, casemate"}:
        b = "castle"
    elif p.get("construction_legere") or usage == "Annexe" or nature == "Serre":
        b = "shed"
    elif usage == "Commercial et services":
        b = "commercial"
    elif usage in {"Résidentiel"}:
        b = "residential"
    elif usage in {"Sportif", "Agricole", "Industriel"} or nature.startswith("Industriel"):
        b = "industrial"
    else:
        b = "yes"
    tags = {"building": b, "source": "IGN BD TOPO"}
    if p.get("hauteur"):
        tags["height"] = str(p["hauteur"])
    if p.get("nombre_d_etages"):
        tags["building:levels"] = str(p["nombre_d_etages"])
    if p.get("altitude_minimale_sol") is not None:
        tags["ele"] = str(p["altitude_minimale_sol"])
    if b == "castle":
        tags["historic"] = "castle"
    return tags


def tags_route(p: dict) -> dict | None:
    if p.get("position_par_rapport_au_sol") not in (None, "0", 0):
        return None  # ponts et souterrains : jalon ultérieur
    nature, imp = p.get("nature") or "", str(p.get("importance") or "5")
    if nature == "Sentier":
        hw = "footway"
    elif nature == "Escalier":
        hw = "steps"
    elif nature in {"Chemin", "Route empierrée"}:
        hw = "track"
    elif nature == "Bac ou liaison maritime":
        return None
    else:
        hw = {"1": "primary", "2": "primary", "3": "secondary", "4": "tertiary"}.get(imp, "residential")
    tags = {"highway": hw, "source": "IGN BD TOPO"}
    nom = p.get("nom_voie_ban_gauche") or p.get("nom_voie_ban_droite") or p.get("nom_collaboratif_gauche")
    if nom:
        tags["name"] = nom
    if p.get("largeur_de_chaussee"):
        tags["width"] = str(p["largeur_de_chaussee"])
    if p.get("sens_de_circulation") in {"Sens direct", "Sens inverse"}:
        tags["oneway"] = "yes"
    if p.get("vitesse_moyenne_vl"):
        tags["maxspeed"] = str(p["vitesse_moyenne_vl"])
    return tags


def tags_vegetation(p: dict) -> dict:
    nature = (p.get("nature") or "").lower()
    if "verger" in nature or "vigne" in nature:
        return {"landuse": "orchard"}
    if "lande" in nature or "haie" in nature:
        return {"natural": "scrub"}
    return {"natural": "wood"}


class Convertisseur:
    """Accumule nœuds et chemins au format intermédiaire (identifiants négatifs : source IGN)."""

    def __init__(self):
        self.elements: list[dict] = []
        self._next = -1
        self._nodes: dict[tuple[float, float], int] = {}

    def node(self, lon: float, lat: float) -> int:
        key = (round(lon, 7), round(lat, 7))
        if key not in self._nodes:
            self._nodes[key] = self._next
            self.elements.append({"type": "node", "id": self._next, "lat": key[1], "lon": key[0]})
            self._next -= 1
        return self._nodes[key]

    def way(self, coords, tags: dict, fermer: bool) -> None:
        ids = [self.node(c[0], c[1]) for c in coords]
        if fermer and ids[0] != ids[-1]:
            ids.append(ids[0])
        self.elements.append({"type": "way", "id": self._next, "nodes": ids, "tags": tags})
        self._next -= 1

    def feature(self, f: dict, tags: dict | None) -> None:
        if tags is None:
            return
        g = f["geometry"]
        if g is None:
            return
        if g["type"] == "Polygon":
            self.way(g["coordinates"][0], tags, True)
        elif g["type"] == "MultiPolygon":
            for poly in g["coordinates"]:
                self.way(poly[0], tags, True)
        elif g["type"] == "LineString":
            coords = g["coordinates"]
            if f["properties"].get("sens_de_circulation") == "Sens inverse":
                coords = coords[::-1]
            self.way(coords, tags, False)
        elif g["type"] == "MultiLineString":
            for line in g["coordinates"]:
                self.way(line, tags, False)


def altitudes(points: list[tuple[float, float]]) -> list[float]:
    """Altitudes RGE ALTI (m) pour une liste de (lon, lat), par paquets."""
    out: list[float] = []
    for i in range(0, len(points), 150):
        chunk = points[i:i + 150]
        data = _get_json(ALTI, {
            "lon": "|".join(f"{p[0]:.7f}" for p in chunk), "lat": "|".join(f"{p[1]:.7f}" for p in chunk),
            "resource": "ign_rge_alti_wld", "zonly": "true",
        })
        out.extend(float(z) if z is not None and z > -1000 else 0.0 for z in data["elevations"])
    return out


def main() -> int:
    emp = charger()
    bbox = bbox_wgs84(emp)
    conv = Convertisseur()
    stats = {}
    for cle, couche in COUCHES.items():
        feats = wfs(couche, bbox)
        feats.sort(key=lambda f: f["properties"].get("cleabs", f.get("id", "")))
        stats[cle] = len(feats)
        print(f"{couche} : {len(feats)} entités")
        for f in feats:
            p = f["properties"]
            if cle == "batiment":
                conv.feature(f, tags_batiment(p))
            elif cle == "route":
                conv.feature(f, tags_route(p))
            elif cle == "vegetation":
                conv.feature(f, tags_vegetation(p))
            else:
                conv.feature(f, {"natural": "water"})
    data = {
        "elements": conv.elements,
        "_frouch": {
            "source": "IGN BD TOPO V3 via Géoplateforme (WFS)",
            "licence": "Licence Ouverte Etalab 2.0 — Source : IGN",
            "extrait_le": dt.date.today().isoformat(),
            "entites": stats,
        },
    }
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"→ {CACHE_PATH.relative_to(GIS_DIR.parent)}")

    # Relief : grille régulière sur toute l'emprise, dans le repère local.
    from .build import Repere
    rep = Repere(emp)
    n = int(2 * emp.demi_cote_m / PAS_ALTI) + 1
    pts = [rep.wgs(i * PAS_ALTI, j * PAS_ALTI) for j in range(n) for i in range(n)]
    z = altitudes(pts)
    ALTI_PATH.write_text(json.dumps({
        "step": PAS_ALTI, "n": n, "z": [round(v, 2) for v in z],
        "source": "IGN RGE ALTI via Géoplateforme", "licence": "Licence Ouverte Etalab 2.0 — Source : IGN",
        "extrait_le": dt.date.today().isoformat(),
    }, separators=(",", ":")), encoding="utf-8")
    print(f"relief {n}×{n} (min {min(z):.1f} m, max {max(z):.1f} m) → {ALTI_PATH.relative_to(GIS_DIR.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
