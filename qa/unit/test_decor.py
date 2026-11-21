"""Décor de Frouch City : édifices publics détaillés, forêts, vergers, arbres d'alignement, carrière (relief creusé et rampe)."""
import glob
import json
import math
import sys
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from qa import roads_audit as ra  # noqa: E402

POIS = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
TUILES = [json.loads(Path(f).read_text(encoding="utf-8")) for f in sorted(glob.glob(str(ROOT / "gis/out/tiles/*.json")))]
BATIMENTS = {b["id"]: b for t in TUILES for b in t["buildings"]}


def test_edifices_publics_presents():
    attendus = {"eglise": "eglise", "mairie": "mairie", "ecole_pommiers": "ecole", "college_bocage": "ecole", "hopital_frouch": "hopital", "usine_calva": "usine"}
    for pid, fac in attendus.items():
        p = POIS[pid]
        assert p["facility"] == fac and len(p["rect"]) == 2 and p["rect"][0] > 6 and p["rect"][1] > 6, pid
        assert p["building"] in BATIMENTS or pid == "eglise"


def test_edifices_sur_des_batiments_distincts_et_libres():
    """Chaque édifice remplace un bâtiment différent, sans enseigne ni lieu de mission ; deux édifices ne se chevauchent pas."""
    fac = [p for p in POIS.values() if p.get("facility")]
    ids = [p["building"] for p in fac]
    assert len(set(ids)) == len(ids)
    autres = {p["building"] for p in POIS.values() if p.get("building") and not p.get("facility")}
    assert not (set(ids) & autres), "un édifice remplace un bâtiment qui porte déjà une enseigne ou un lieu de mission"
    for i, a in enumerate(fac):
        for b in fac[i + 1:]:
            assert math.dist(a["position"], b["position"]) > 60, f"{a['id']} et {b['id']} trop proches"


def test_edifices_proches_de_leur_emprise():
    for p in POIS.values():
        if p.get("facility") and p["building"] in BATIMENTS:
            poly = Polygon(BATIMENTS[p["building"]]["footprint"])
            assert poly.centroid.distance(Point(p["position"])) < 6.0, p["id"]


def test_arbres_forets_vergers_alignements():
    nb = {0: 0, 1: 0, 2: 0, 3: 0}
    for t in TUILES:
        for tr in t["trees"]:
            assert len(tr) in (2, 3)
            nb[tr[2] if len(tr) > 2 else 0] += 1
    assert nb[0] > 3000 and nb[1] > 800 and nb[2] >= 200 and nb[3] > 100, nb
    assert sum(1 for t in TUILES for v in t["vegetation"] if v["kind"] == "orchard") >= 3


def test_arbres_pas_sur_les_batiments_ni_les_routes():
    obst = [Polygon(b["footprint"]) for b in BATIMENTS.values()]
    routes = [LineString(r["points"]).buffer(r["width"] / 2.0) for t in TUILES for r in t["roads"] if r["kind"] not in ("footway", "path", "track")]
    from shapely.strtree import STRtree
    arbre = STRtree(obst + routes)
    for t in TUILES[:8]:
        for tr in t["trees"][:400]:
            pt = Point(tr[0], tr[1])
            assert not any((obst + routes)[i].intersects(pt) for i in arbre.query(pt)), f"arbre sur un bâtiment ou une route : {tr}"


def test_arbres_pas_sur_la_voie_ferree_ni_la_gare():
    rail = POIS["passage_niveau"]
    d = (math.sin(rail["facing"]), math.cos(rail["facing"]))
    L = rail["length"] / 2.0
    voie = LineString([(rail["position"][0] - d[0] * L, rail["position"][1] - d[1] * L), (rail["position"][0] + d[0] * L, rail["position"][1] + d[1] * L)]).buffer(8.0)
    mare = Point(POIS["etang_oies"]["position"]).buffer(14.0)
    for t in TUILES:
        for tr in t["trees"]:
            pt = Point(tr[0], tr[1])
            assert not voie.contains(pt) and not mare.contains(pt), "arbre sur la voie ferrée ou la mare"


def test_carriere_creusee():
    q = POIS["carriere_pierres"]
    assert q["prop"] == "carriere" and q["radius"] > 50
    rel = ra.Relief()
    cx, cz = q["position"]
    d = (math.sin(q["facing"]), math.cos(q["facing"]))
    fond = rel.h(cx, cz)
    bord = rel.h(cx + d[0] * (q["radius"] + 14), cz + d[1] * (q["radius"] + 14))
    assert bord - fond > 10.0, f"carrière trop peu profonde ({bord - fond:.1f} m)"
    # Rampe : monte de façon continue du fond au bord, pente ≤ 30 %.
    prec = None
    for k in range(0, int(q["radius"]) + 10, 4):
        h = rel.h(cx + d[0] * k, cz + d[1] * k)
        if prec is not None:
            assert (h - prec) / 4.0 <= 0.30 and h - prec >= -0.8, f"rampe discontinue à {k} m"
        prec = h


def test_carriere_libre():
    q = POIS["carriere_pierres"]
    disque = Point(q["position"]).buffer(q["radius"] + 8)
    for b in BATIMENTS.values():
        assert not Polygon(b["footprint"]).intersects(disque), "bâtiment dans la carrière"
    for t in TUILES:
        for r in t["roads"]:
            if r["kind"] not in ("footway", "path"):
                assert not LineString(r["points"]).intersects(disque), "route dans la carrière"


def _aire(pts):
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2


def test_enseignes_plaquees_aux_murs():
    """Chaque enseigne est collée à un mur (≤ 15 cm), son cap est la normale sortante de ce mur (≤ 0,5°, jamais une diagonale
    vers la rue) et elle ne dépasse pas du bout de l'arête."""
    mauvais = []
    nb = 0
    for p in POIS.values():
        if "building" not in p or "facing" not in p or p.get("facility"):
            continue
        nb += 1
        pts = [tuple(q) for q in BATIMENTS[p["building"]]["footprint"]]
        aire = _aire(pts)
        fd = (math.sin(p["facing"]), math.cos(p["facing"]))
        ok = False
        for i in range(len(pts)):
            a, c = pts[i], pts[(i + 1) % len(pts)]
            ex, ez = c[0] - a[0], c[1] - a[1]
            long = math.hypot(ex, ez)
            if long < 0.8:
                continue
            t = ((p["position"][0] - a[0]) * ex + (p["position"][1] - a[1]) * ez) / (long * long)
            if not -0.01 <= t <= 1.01:
                continue
            nx, nz = (ez / long, -ex / long) if aire >= 0 else (-ez / long, ex / long)
            dist = abs((p["position"][0] - a[0]) * nx + (p["position"][1] - a[1]) * nz)
            ecart = math.degrees(math.acos(max(-1.0, min(1.0, fd[0] * nx + fd[1] * nz))))
            if dist <= 0.15 and ecart <= 0.5:
                ok = True
                break
        if not ok:
            mauvais.append(p["id"])
    assert nb > 100
    assert not mauvais, f"enseignes non plaquées à un mur : {mauvais[:10]} ({len(mauvais)}/{nb})"
