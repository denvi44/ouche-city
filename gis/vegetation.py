"""Végétation (agent 01, cartographe) : forêts peuplées d'arbres, vergers de pommiers, arbres d'alignement.

Les données ouvertes de la zone ne contiennent que des polygones de bois (37 ha, 111 polygones) et aucun arbre isolé : ce module
sème les arbres de façon déterministe (grille jitterée par hachage, aucun hasard non semé) et ajoute des vergers fictifs.
Format des arbres : [x, z, espèce] avec espèce 0 feuillu (chêne), 1 pin, 2 pommier, 3 peuplier.
"""
from __future__ import annotations

import hashlib
import math

from shapely.geometry import LineString, Point, Polygon, box
from shapely.strtree import STRtree

PAS_FORET = 6.8
PAS_VERGER = (6.5, 5.5)
MAX_ARBRES_PAR_POLYGONE = 650
MAX_ARBRES_ALIGNEMENT = 380
ESPACE_ALIGNEMENT = 26.0
KINDS_ALIGNEMENT = ("residential", "tertiary", "secondary")


def _h(*parts) -> int:
    return int(hashlib.sha1("|".join(map(str, parts)).encode()).hexdigest()[:12], 16)


def _u(*parts) -> float:
    return (_h(*parts) % 100000) / 100000.0


def _obstacles(tuiles: dict, marge_route=2.5, marge_bat=3.0):
    obst = []
    for t in tuiles.values():
        obst += [Polygon(b["footprint"]).buffer(marge_bat) for b in t["buildings"]]
        obst += [LineString(r["points"]).buffer(r["width"] / 2 + marge_route) for r in t["roads"] if r["kind"] not in ("footway", "path")]
        obst += [Polygon(v["polygon"]).buffer(1.0) for v in t["vegetation"] if v["kind"] == "water"]
    return obst


def planter(tuiles: dict, taille: float, carriere=None, rayon_carriere=0.0) -> dict:
    """Ajoute les arbres (`trees`) et les vergers (`vegetation`, kind « orchard ») aux tuiles. Renvoie des comptages."""
    obst = _obstacles(tuiles)
    arbre = STRtree(obst)
    exclus = Point(carriere[0], carriere[1]).buffer(rayon_carriere + 8.0) if carriere else None
    obst_ali = _obstacles(tuiles, marge_route=1.0, marge_bat=3.5)       # arbres d'alignement : bord de chaussée autorisé
    arbre_ali = STRtree(obst_ali)

    def libre_ali(x, z):
        p = Point(x, z)
        if exclus is not None and exclus.contains(p):
            return False
        pg = p.buffer(1.2)
        return not any(obst_ali[i].intersects(pg) for i in arbre_ali.query(pg))

    def libre(x, z, marge=0.0):
        p = Point(x, z)
        if exclus is not None and exclus.contains(p):
            return False
        pg = p.buffer(marge) if marge else p
        return not any(obst[i].intersects(pg) for i in arbre.query(pg))

    def tuile_de(x, z):
        return tuiles.get((int(x // taille), int(z // taille)))

    n_foret = n_verger = n_align = 0
    # 1. Forêts : grille de 6,8 m jitterée, espèces par hachage (chêne 68 %, pin 24 %, peuplier 8 %).
    for t in sorted(tuiles.values(), key=lambda t: (t["tile"]["x"], t["tile"]["y"])):
        for vi, v in enumerate(t["vegetation"]):
            if v["kind"] != "forest":
                continue
            poly = Polygon(v["polygon"])
            if not poly.is_valid or poly.area < 120:
                continue
            minx, minz, maxx, maxz = poly.bounds
            compte = 0
            gx = int(minx // PAS_FORET)
            while gx * PAS_FORET <= maxx and compte < MAX_ARBRES_PAR_POLYGONE:
                gz = int(minz // PAS_FORET)
                while gz * PAS_FORET <= maxz and compte < MAX_ARBRES_PAR_POLYGONE:
                    x = (gx + 0.15 + 0.7 * _u("fx", gx, gz)) * PAS_FORET
                    z = (gz + 0.15 + 0.7 * _u("fz", gx, gz)) * PAS_FORET
                    if poly.contains(Point(x, z)) and libre(x, z) and _u("fd", gx, gz) < 0.88:
                        r = _u("fs", gx, gz)
                        esp = 0 if r < 0.68 else (1 if r < 0.92 else 3)
                        tt = tuile_de(x, z)
                        if tt is not None:
                            tt["trees"].append([round(x, 1), round(z, 1), esp])
                            compte += 1
                            n_foret += 1
                    gz += 1
                gx += 1
    # 2. Vergers fictifs : rectangles de 70 × 46 m libres, à 150-700 m du centre de la zone, dans une seule tuile.
    xs = [k[0] for k in tuiles]
    ys = [k[1] for k in tuiles]
    cx0 = (min(xs) + max(xs) + 1) * taille / 2.0
    cz0 = (min(ys) + max(ys) + 1) * taille / 2.0
    forets = [Polygon(v["polygon"]) for t in tuiles.values() for v in t["vegetation"] if v["kind"] == "forest"]
    sites = []
    for x in range(int(min(xs) * taille) + 40, int((max(xs) + 1) * taille) - 110, 20):
        for z in range(int(min(ys) * taille) + 40, int((max(ys) + 1) * taille) - 86, 20):
            if int(x // taille) != int((x + 70) // taille) or int(z // taille) != int((z + 46) // taille):
                continue
            if tuile_de(x, z) is None:
                continue
            d = math.hypot(x + 35 - cx0, z + 23 - cz0)
            if not 150.0 <= d <= 700.0:
                continue
            sites.append((_h("verger", x, z), x, z))
    sites.sort()
    vergers = []
    for _, x, z in sites:
        if len(vergers) >= 4:
            break
        rect = box(x, z, x + 70, z + 46)
        if any(math.hypot(x - vx, z - vz) < 170 for vx, vz in vergers):
            continue
        marge = rect.buffer(6.0)
        if any(obst[i].intersects(marge) for i in arbre.query(marge)) or any(f.intersects(marge) for f in forets):
            continue
        if exclus is not None and exclus.intersects(marge):
            continue
        tt = tuile_de(x, z)
        tt["vegetation"].append({"kind": "orchard", "polygon": [[x, z], [x + 70, z], [x + 70, z + 46], [x, z + 46]]})
        px = x + 5.0
        while px <= x + 66.0:
            pz = z + 5.0
            while pz <= z + 42.0:
                tt["trees"].append([round(px + (_u("vx", px, pz) - 0.5) * 0.6, 1), round(pz + (_u("vz", px, pz) - 0.5) * 0.6, 1), 2])
                n_verger += 1
                pz += PAS_VERGER[1]
            px += PAS_VERGER[0]
        vergers.append((x, z))
    # 3. Arbres d'alignement le long des routes secondaires, tertiaires et résidentielles (tilleuls), sans gêner les façades.
    deja: list[tuple[float, float]] = []
    for t in sorted(tuiles.values(), key=lambda t: (t["tile"]["x"], t["tile"]["y"])):
        for r in t["roads"]:
            if r["kind"] not in KINDS_ALIGNEMENT or n_align >= MAX_ARBRES_ALIGNEMENT:
                continue
            ligne = LineString(r["points"])
            if ligne.length < 40:
                continue
            d = 14.0 + 12.0 * _u("ali", r["id"])
            cote = 1.0 if _u("cote", r["id"]) < 0.5 else -1.0
            while d < ligne.length - 12.0 and n_align < MAX_ARBRES_ALIGNEMENT:
                a, b = ligne.interpolate(max(d - 1.0, 0.0)), ligne.interpolate(min(d + 1.0, ligne.length))
                dx, dz = b.x - a.x, b.y - a.y
                nrm = math.hypot(dx, dz) or 1.0
                off = r["width"] / 2.0 + 2.2
                x, z = a.x + (-dz / nrm) * off * cote, a.y + (dx / nrm) * off * cote
                if (int(x // taille), int(z // taille)) == (t["tile"]["x"], t["tile"]["y"]) and libre_ali(x, z) and all(math.hypot(x - px, z - pz) > 9.0 for px, pz in deja[-60:]):
                    t["trees"].append([round(x, 1), round(z, 1), 0])
                    deja.append((x, z))
                    n_align += 1
                d += ESPACE_ALIGNEMENT
                cote = -cote
    return {"foret": n_foret, "verger": n_verger, "alignement": n_align, "vergers": len(vergers)}


def nettoyer(tuiles: dict, pois: list[dict]) -> int:
    """Retire les arbres qui tomberaient sur un lieu de mission, un édifice ou la voie ferrée (appelé une fois les POI connus)."""
    zones = []
    for p in pois:
        x, z = p["position"]
        if p.get("prop") == "rail" and "length" in p:
            d = (math.sin(p["facing"]), math.cos(p["facing"]))
            L = p["length"] / 2.0
            zones.append(LineString([(x - d[0] * L, z - d[1] * L), (x + d[0] * L, z + d[1] * L)]).buffer(9.0))
        elif p.get("prop") == "gare":
            d = (math.sin(p["facing"]), math.cos(p["facing"]))
            r = (d[1], -d[0])
            s = p.get("side", 1)
            zones.append(Polygon([(x + d[0] * a * 44 + r[0] * s * b, z + d[1] * a * 44 + r[1] * s * b) for a, b in ((-1, -4), (1, -4), (1, 36), (-1, 36))]))
            if p.get("path"):
                zones.append(LineString(p["path"]).buffer(3.5))
        elif p.get("prop") == "pond":
            zones.append(Point(x, z).buffer(p.get("radius", 14.0) + 5.0))
        elif "rect" in p:
            w, d2 = p["rect"]
            zones.append(Point(x, z).buffer(max(w, d2) / 2.0 + 6.0))
        elif p.get("step") or p.get("prop"):
            zones.append(Point(x, z).buffer(p.get("radius", 4.0) + 3.0))
    if not zones:
        return 0
    arbre = STRtree(zones)
    retires = 0
    for t in tuiles.values():
        gardes = []
        for tr in t["trees"]:
            pt = Point(tr[0], tr[1])
            if any(zones[i].intersects(pt) for i in arbre.query(pt)):
                retires += 1
            else:
                gardes.append(tr)
        t["trees"] = gardes
    return retires
