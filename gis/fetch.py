"""Téléchargement des données OpenStreetMap (API Overpass), mis en cache et daté.

Usage : python -m gis.fetch   (réseau requis ; le reste du pipeline travaille sur le cache)
"""
from __future__ import annotations

import datetime as dt
import json
import sys
import urllib.parse
import urllib.request

from pyproj import Transformer

from .config import GIS_DIR, charger

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
CACHE_PATH = GIS_DIR / "cache" / "osm_conches.json"


def bbox_wgs84(emp) -> tuple[float, float, float, float]:
    """(sud, ouest, nord, est) de l'emprise carrée autour du centre."""
    to_l93 = Transformer.from_crs("EPSG:4326", "EPSG:2154", always_xy=True)
    to_wgs = Transformer.from_crs("EPSG:2154", "EPSG:4326", always_xy=True)
    cx, cy = to_l93.transform(emp.centre_lon, emp.centre_lat)
    d = emp.demi_cote_m
    ouest, sud = to_wgs.transform(cx - d, cy - d)
    est, nord = to_wgs.transform(cx + d, cy + d)
    return sud, ouest, nord, est


def requete(bbox) -> str:
    s, w, n, e = bbox
    b = f"({s:.6f},{w:.6f},{n:.6f},{e:.6f})"
    return f"""
[out:json][timeout:120];
(
  way["building"]{b};
  relation["building"]{b};
  way["highway"]{b};
  way["landuse"]{b};
  way["leisure"]{b};
  way["natural"]{b};
  way["waterway"]{b};
  node["natural"="tree"]{b};
  node["amenity"]{b};
  node["shop"]{b};
  node["historic"]{b};
  way["historic"]{b};
);
out body;
>;
out skel qt;
"""


def main() -> int:
    emp = charger()
    q = requete(bbox_wgs84(emp))
    body = urllib.parse.urlencode({"data": q}).encode()
    req = urllib.request.Request(OVERPASS_URL, data=body, headers={"User-Agent": "frouch-city-gis/1.0"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.load(resp)
    data["_frouch"] = {
        "source": "OpenStreetMap via Overpass API",
        "licence": "ODbL 1.0 — © contributeurs OpenStreetMap",
        "extrait_le": dt.date.today().isoformat(),
    }
    CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    CACHE_PATH.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"{len(data['elements'])} éléments OSM → {CACHE_PATH.relative_to(GIS_DIR.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
