"""Audit des routes (agent 13, QA) : pentes en long, dévers, continuité du relief entre tuiles, connexité du graphe routier et
accessibilité des lieux de mission. Utilisé par qa/unit/test_routes.py ; `python3 qa/roads_audit.py [--out rapport.md]` écrit un rapport.

Mesures sur le relief des tuiles (gis/out/tiles), bilinéaire comme dans Godot (city_builder.height_at)."""
from __future__ import annotations

import argparse
import glob
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
CARROSSABLES = {"primary", "secondary", "tertiary", "residential", "service", "track"}
PENTE_LONGUE_MAX = {"primary": 0.09, "secondary": 0.09, "tertiary": 0.10, "residential": 0.12, "service": 0.14, "track": 0.18}


class Relief:
    def __init__(self, out: Path | None = None):
        out = out or ROOT / "gis/out"
        self.tuiles = {}
        for f in glob.glob(str(out / "tiles/*.json")):
            d = json.load(open(f, encoding="utf-8"))
            self.tuiles[(d["tile"]["x"], d["tile"]["y"])] = d
        self.size = next(iter(self.tuiles.values()))["size"]

    def h(self, x: float, z: float):
        T = self.size
        t = self.tuiles.get((int(math.floor(x / T)), int(math.floor(z / T))))
        if t is None:
            return None
        g = t["ground"]
        res = g["resolution"]
        step = T / (res - 1)
        ox, oz = t["origin"]
        gx = min(max((x - ox) / step, 0.0), res - 1.001)
        gz = min(max((z - oz) / step, 0.0), res - 1.001)
        i, j = int(gx), int(gz)
        fx, fz = gx - i, gz - j
        hs = g["heights"]
        top = hs[j * res + i] * (1 - fx) + hs[j * res + i + 1] * fx
        bot = hs[(j + 1) * res + i] * (1 - fx) + hs[(j + 1) * res + i + 1] * fx
        return top * (1 - fz) + bot * fz


def mesurer_routes(relief: Relief, pas: float = 2.0):
    """Une ligne par échantillon d'axe de route carrossable : (kind, nom, id, x, z, pente_longue, dévers)."""
    lignes = []
    for t in relief.tuiles.values():
        for r in t["roads"]:
            if r["kind"] not in CARROSSABLES:
                continue
            pts = np.array(r["points"], dtype=float)
            w = float(r["width"])
            prev = None
            for a, b in zip(pts[:-1], pts[1:]):
                seg = float(np.linalg.norm(b - a))
                if seg < 0.5:
                    continue
                n = max(int(seg // pas), 1)
                u = (b - a) / seg
                nrm = np.array([-u[1], u[0]])
                for k in range(n + 1):
                    p = a + u * (seg * k / n)
                    h0, hl, hr = relief.h(*p), relief.h(*(p + nrm * w / 2)), relief.h(*(p - nrm * w / 2))
                    if None in (h0, hl, hr):
                        prev = None
                        continue
                    if prev is not None:
                        d = float(np.linalg.norm(p - prev[1]))
                        if d > 0.05:
                            lignes.append((r["kind"], r.get("name"), r["id"], float(p[0]), float(p[1]), abs(h0 - prev[0]) / d, abs(hl - hr) / w))
                    prev = (h0, p)
    return lignes


def discontinuites_de_bord(relief: Relief):
    """Écart de hauteur entre deux tuiles voisines sur leur bord commun (doit être nul : pas de marche à la jonction)."""
    pire = 0.0
    for (tx, ty), t in relief.tuiles.items():
        for dx, dy in ((1, 0), (0, 1)):
            v = relief.tuiles.get((tx + dx, ty + dy))
            if not v:
                continue
            g1, g2 = t["ground"], v["ground"]
            res = g1["resolution"]
            for k in range(res):
                if dx == 1:
                    a, b = g1["heights"][k * res + res - 1], g2["heights"][k * res]
                else:
                    a, b = g1["heights"][(res - 1) * res + k], g2["heights"][k]
                pire = max(pire, abs(a - b))
    return pire


def graphe(out: Path | None = None):
    out = out or ROOT / "gis/out"
    g = json.load(open(out / "road_graph.json", encoding="utf-8"))
    return g


def composantes(g):
    """Composantes connexes du graphe routier (non orienté) : liste de ensembles d'identifiants de nœuds."""
    adj = defaultdict(set)
    for e in g["edges"]:
        adj[e["from"]].add(e["to"])
        adj[e["to"]].add(e["from"])
    vus, comps = set(), []
    for n in (x["id"] for x in g["nodes"]):
        if n in vus:
            continue
        pile, comp = [n], set()
        while pile:
            c = pile.pop()
            if c in comp:
                continue
            comp.add(c)
            pile.extend(adj[c] - comp)
        vus |= comp
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    return comps


def noeud_le_plus_proche(g, x, z):
    best, bd = None, 1e18
    for n in g["nodes"]:
        d = math.hypot(n["position"][0] - x, n["position"][1] - z)
        if d < bd:
            best, bd = n["id"], d
    return best, bd


def stats(lignes):
    gl = np.array([r[5] for r in lignes])
    dv = np.array([r[6] for r in lignes])
    return {"echantillons": len(lignes),
            "pente_p50": float(np.percentile(gl, 50)), "pente_p99": float(np.percentile(gl, 99)), "pente_max": float(gl.max()),
            "devers_p50": float(np.percentile(dv, 50)), "devers_p99": float(np.percentile(dv, 99)), "devers_max": float(dv.max()),
            "part_devers_sup_4": float((dv > 0.04).mean()), "part_devers_sup_8": float((dv > 0.08).mean()),
            "part_pente_sup_12": float((gl > 0.12).mean())}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path)
    a = ap.parse_args()
    rel = Relief()
    lignes = mesurer_routes(rel)
    s = stats(lignes)
    g = graphe()
    comps = composantes(g)
    txt = ["# Audit des routes\n",
           f"- {s['echantillons']} échantillons d'axe (tous les 2 m) sur les routes carrossables.",
           f"- Pente en long : médiane {s['pente_p50']:.1%}, 99ᵉ centile {s['pente_p99']:.1%}, maximum {s['pente_max']:.1%} ; {s['part_pente_sup_12']:.1%} des échantillons au-dessus de 12 %.",
           f"- Dévers (inclinaison latérale de la chaussée) : médiane {s['devers_p50']:.1%}, 99ᵉ centile {s['devers_p99']:.1%}, maximum {s['devers_max']:.1%} ; {s['part_devers_sup_4']:.1%} au-dessus de 4 %, {s['part_devers_sup_8']:.1%} au-dessus de 8 %.",
           f"- Continuité entre tuiles : écart maximal de hauteur sur un bord commun {discontinuites_de_bord(rel):.3f} m.",
           f"- Graphe routier : {len(g['nodes'])} nœuds, {len(g['edges'])} tronçons, {len(comps)} composante(s) connexe(s) (tailles : {', '.join(str(len(c)) for c in comps[:6])}).\n"]
    pires = sorted(lignes, key=lambda r: -r[6])[:5]
    txt.append("Pires dévers : " + " ; ".join(f"{r[1] or r[0]} {r[6]:.1%} en ({r[3]:.0f}, {r[4]:.0f})" for r in pires) + "\n")
    txt.append("Seuils (tests) : pente en long ≤ 12 % (99ᵉ centile ≤ 10 %), dévers ≤ 4 % au 99ᵉ centile et ≤ 8 % partout.\n")
    out = "\n".join(txt)
    print(out)
    if a.out:
        a.out.write_text(out, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
