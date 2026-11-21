"""Pipeline SIG sur un cache synthétique : déterminisme, anonymisation, typologies (agent 09)."""
import json
from pathlib import Path

from jsonschema import Draft202012Validator

from gis import build

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = Path(__file__).parent / "fixtures" / "osm_mini.json"


def _run(tmp_path, name):
    out = tmp_path / name
    assert build.main(["--osm", str(FIXTURE), "--ign", str(tmp_path / "absent.json"),
                       "--alti", str(tmp_path / "absent_alti.json"), "--out", str(out)]) == 0
    return out


def test_sorties_deterministes(tmp_path):
    a, b = _run(tmp_path, "a"), _run(tmp_path, "b")
    fa = sorted(p.relative_to(a) for p in a.rglob("*.json"))
    assert fa == sorted(p.relative_to(b) for p in b.rglob("*.json"))
    for rel in fa:
        assert (a / rel).read_bytes() == (b / rel).read_bytes()


def test_tuiles_conformes_et_contenu(tmp_path):
    out = _run(tmp_path, "o")
    schema = Draft202012Validator(json.loads((ROOT / "contracts/tile.schema.json").read_text()))
    batiments, routes = {}, []
    for p in (out / "tiles").glob("*.json"):
        t = json.loads(p.read_text())
        assert not list(schema.iter_errors(t))
        batiments.update({b["id"]: b for b in t["buildings"]})
        routes += t["roads"]
    assert batiments["b_201"]["typology"] == "eglise" and batiments["b_201"]["roof"] == "spire"
    assert batiments["b_202"]["typology"] == "annexe"
    assert batiments["b_200"]["typology"] == "commerce"  # contient la boulangerie
    assert batiments["b_200"]["height"] == 7.0  # 2 niveaux × 3 m + 1 m
    assert any(r["name"] == "Rue Sainte-Foy" for r in routes)


def test_noms_de_commerces_supprimes(tmp_path):
    out = _run(tmp_path, "o")
    texte = "".join(p.read_text() for p in out.rglob("*.json"))
    assert "Nom réel à supprimer" not in texte
    pois = json.loads((out / "poi.json").read_text())["pois"]
    from gis import fiction
    tous = {n for noms in fiction.ENSEIGNES.values() for n in noms}
    assert any(p["kind"] == "shop" and p["label"] in tous for p in pois)


def test_normalisation_des_noms():
    assert build.normaliser_nom("Rue Sainte-Foy") == build.normaliser_nom("Rue Sainte Foy")
    assert build.normaliser_nom("Rue de l'Hôtel de Ville") == "rue de l hotel de ville"


def test_anneaux_antihoraires_vus_du_dessus(tmp_path):
    out = _run(tmp_path, "o")
    for p in (out / "tiles").glob("*.json"):
        for b in json.loads(p.read_text())["buildings"]:
            ring = b["footprint"]
            area = sum(a[0] * c[1] - c[0] * a[1] for a, c in zip(ring, ring[1:] + ring[:1])) / 2
            assert area < 0  # négative en (x, z) car z pointe au sud


def test_lieux_fictifs_uniques_et_rattaches(tmp_path):
    """Chaque commerce de la zone reçoit une enseigne inventée, unique, posée sur sa façade."""
    from gis import fiction
    out = _run(tmp_path, "o")
    pois = json.loads((out / "poi.json").read_text())["pois"]
    lieux = [p for p in pois if p.get("building")]
    assert lieux, "aucun lieu fictif"
    labels = [p["label"] for p in lieux]
    assert len(labels) == len(set(labels))
    assert all(p["source"] == "design" and isinstance(p["facing"], float) for p in lieux)
    assert any(p["id"] == "eglise" and p["label"] == fiction.MONUMENTS["eglise"] for p in pois)


def test_fumier_accessible_a_pied(tmp_path):
    """Le tas de fumier est hors de tout bâtiment et joignable en ligne droite depuis une rue
    (les compagnons IA suivent le graphe routier, pas un maillage de navigation complet)."""
    from shapely.geometry import LineString, Point, Polygon
    from shapely.ops import nearest_points
    out = ROOT / "gis/out"
    pois = {p["id"]: p for p in json.loads((out / "poi.json").read_text())["pois"]}
    if "fumier_tas" not in pois:
        return
    pt = Point(pois["fumier_tas"]["position"])
    polys, routes = [], []
    for f in (out / "tiles").glob("*.json"):
        t = json.loads(f.read_text())
        polys += [Polygon(b["footprint"]) for b in t["buildings"]]
        routes += [LineString(r["points"]) for r in t["roads"] if r["kind"] not in ("footway", "track")]
    assert all(p.distance(pt) >= 2.9 for p in polys), "fumier trop près d'un bâtiment"
    road = min(routes, key=lambda r: r.distance(pt))
    foot = nearest_points(road, pt)[0]
    assert foot.distance(pt) <= 28.0
    ray = LineString([(foot.x, foot.y), (pt.x, pt.y)])
    assert not any(p.intersects(ray) for p in polys), "un bâtiment barre l'accès au fumier"
