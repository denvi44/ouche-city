"""Contrats JSON : schémas valides, données du dépôt conformes (agent 09)."""
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "contracts"


def schema(name):
    s = json.loads((CONTRACTS / f"{name}.schema.json").read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(s)
    return Draft202012Validator(s)


@pytest.mark.parametrize("name", ["tile", "poi", "mission", "save", "road_graph"])
def test_schema_valide_et_versionne(name):
    s = json.loads((CONTRACTS / f"{name}.schema.json").read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(s)
    assert isinstance(s.get("version"), int) and s["version"] >= 1


@pytest.mark.parametrize("path", sorted((ROOT / "missions").glob("m*.json")), ids=lambda p: p.name)
def test_missions_conformes(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    errors = sorted(schema("mission").iter_errors(data), key=str)
    assert not errors, "\n".join(e.message for e in errors)
    assert data["id"] == path.stem
    # Solo = même code : chaque rôle tenu par un compagnon IA, sauf celui du joueur.
    roles = set(data["roles"])
    assert len(roles - set(data.get("companions", {}))) <= 1, "un rôle n'a pas de compagnon IA"


def test_chaine_de_deblocage():
    ids = {json.loads(p.read_text())["id"] for p in (ROOT / "missions").glob("m*.json")}
    for p in (ROOT / "missions").glob("m*.json"):
        for req in json.loads(p.read_text()).get("requires", []):
            assert req in ids


def _tiles(dirname):
    return sorted((ROOT / dirname / "tiles").glob("*.json"))


@pytest.mark.parametrize("path", _tiles("gis/out"), ids=lambda p: p.name)
def test_tuiles_conformes(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    errors = list(schema("tile").iter_errors(data))
    assert not errors, errors[0].message
    g = data["ground"]
    assert len(g["heights"]) == g["resolution"] ** 2


def test_poi_et_graphe_conformes():
    for name, file in [("poi", "poi.json"), ("road_graph", "road_graph.json")]:
        data = json.loads((ROOT / "gis/out" / file).read_text(encoding="utf-8"))
        errors = list(schema(name).iter_errors(data))
        assert not errors, f"{file}: {errors[0].message}"


def test_ville_importee_dans_godot_sans_retouche():
    """game/assets/city doit être une copie exacte de gis/out (make city)."""
    for src in [*(ROOT / "gis/out").glob("*.json"), *_tiles("gis/out")]:
        rel = src.relative_to(ROOT / "gis/out")
        dst = ROOT / "game/assets/city" / rel
        assert dst.exists(), f"{rel} absent de game/assets/city : lancer make city"
        assert dst.read_bytes() == src.read_bytes(), f"{rel} différent : lancer make city"


def test_attributions_declarees():
    txt = (ROOT / "LICENSES/ATTRIBUTIONS.md").read_text(encoding="utf-8")
    manifest = json.loads((ROOT / "gis/out/manifest.json").read_text(encoding="utf-8"))
    for m in manifest["sources"]:
        assert m["extrait_le"] in txt, f"source {m['source']} non datée dans ATTRIBUTIONS.md"


def test_noms_de_lieux_fictifs():
    """Tous les lieux nommés (hors rues et point d'apparition) viennent de gis/fiction.py."""
    import sys
    sys.path.insert(0, str(ROOT))
    from gis import fiction
    autorises = {n for noms in fiction.ENSEIGNES.values() for n in noms}
    autorises |= {l for _, _, l, _ in fiction.LIEUX_MISSION} | set(fiction.MONUMENTS.values()) | set(fiction.LABELS_M01.values()) | set(fiction.LABELS_M02.values()) | set(fiction.LABELS_M03.values()) | set(fiction.LABELS_M04.values()) | set(fiction.LABELS_M05.values()) | {"Donjon"}
    pois = json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]
    for p in pois:
        if p["kind"] in ("spawn", "viewpoint"):
            continue
        assert any(p["label"] == n or p["label"].startswith(n + " ") for n in autorises), f"nom non fictif ou non répertorié : {p['label']}"


def test_lieux_de_mission01_couvrent_les_etapes():
    """Chaque étape spatiale de m01 a un lieu posé sur la carte, et chaque lieu sert une étape existante."""
    m = json.loads((ROOT / "missions/m01_calva_gege.json").read_text(encoding="utf-8"))
    etapes = {s["id"] for s in m["steps"]}
    pois = [p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]
            if p.get("step") and "m01_calva_gege" in p.get("missions", [])]
    assert pois and all(p["step"] in etapes for p in pois)
    servies = {p["step"] for p in pois}
    assert {"crates", "vehicle", "checkpoint", "fair"} <= servies
    # Les 4 sources de caisses du JSON (cave, grange, poulailler, fumier) ont chacune un lieu.
    ids = {p["id"] for p in pois if p["step"] == "crates"}
    assert len(ids) == len(next(s for s in m["steps"] if s["id"] == "crates")["spawns"])


def test_missions_importees_dans_godot():
    """game/assets/missions doit être une copie exacte de missions/ (make city)."""
    for src in (ROOT / "missions").glob("m*.json"):
        dst = ROOT / "game/assets/missions" / src.name
        assert dst.exists() and dst.read_bytes() == src.read_bytes(), f"{src.name} : lancer make city"


def test_lieux_de_mission02():
    """Chaque étape spatiale de m02 a un lieu ; la piste de drag fait 400 m, libre et presque plate."""
    import math
    from shapely.geometry import LineString, Point, Polygon
    m = json.loads((ROOT / "missions/m02_tuning_samedi.json").read_text(encoding="utf-8"))
    etapes = {s["id"] for s in m["steps"]}
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    m02 = [p for p in pois.values() if "m02_tuning_samedi" in p.get("missions", []) and p.get("step")]
    assert all(p["step"] in etapes for p in m02)
    for source in ("casse", "annonce", "auto_bling_27", "cour_dylan"):       # les 4 sources du JSON
        assert any(s["id"] == source for s in m["sources"])
    for pid in ("garage_kevin", "voiture_kevin", "casse_dugenou", "annonce_vendeur", "auto_bling_27", "cour_dylan", "parc_rdv", "drag_depart", "drag_arrivee"):
        assert pid in pois, f"lieu manquant : {pid}"
    a, b = pois["drag_depart"]["position"], pois["drag_arrivee"]["position"]
    assert abs(math.dist(a, b) - m["steps"][[s["id"] for s in m["steps"]].index("drag")]["distanceM"]) < 0.5
    couloir = LineString([a, b]).buffer(8.0, cap_style="flat")
    batiments, routes = [], []
    for f in (ROOT / "gis/out/tiles").glob("*.json"):
        t = json.loads(f.read_text())
        batiments += [Polygon(x["footprint"]) for x in t["buildings"]]
        routes += [LineString(r["points"]) for r in t["roads"] if r["kind"] not in ("footway", "track")]
    assert not any(p.intersects(couloir) for p in batiments), "un bâtiment barre la piste"
    assert not any(r.intersects(couloir) for r in routes), "une route traverse la piste"
    # Les lieux de la mission 02 sont tous distincts les uns des autres (pas d'empilement).
    pts = [Point(p["position"]) for p in m02 if p["id"] not in ("drag_arrivee",)]
    for i, p in enumerate(pts):
        for q in pts[i + 1:]:
            assert p.distance(q) > 2.0


def test_lieux_de_mission03():
    """La sono des Pommiers, celle du Clos Fleuri et les trois objets existent ; les camps sont loin l'un de l'autre."""
    import math
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    for pid in ("camp_pommiers", "camp_clos_fleuri", "item_caisson", "item_rallonge", "item_groupe"):
        assert pid in pois, f"lieu manquant : {pid}"
        assert pois[pid]["missions"] == ["m03_battle_sono"]
    assert pois["camp_pommiers"]["prop"] == "stage" and pois["camp_clos_fleuri"]["prop"] == "stage"
    assert math.dist(pois["camp_pommiers"]["position"], pois["camp_clos_fleuri"]["position"]) > 200
    ids = [pois[i]["position"] for i in ("camp_pommiers", "camp_clos_fleuri", "item_caisson", "item_rallonge", "item_groupe")]
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            assert math.dist(a, b) > 20


def test_lieux_de_mission04():
    """La cuisine du méchoui, le bûcher et les trois objets existent, distincts de ceux des autres missions."""
    import math
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    ids = ("place_fete", "bucher", "item_agneau", "item_broche", "item_charbon")
    for pid in ids:
        assert pid in pois, f"lieu manquant : {pid}"
        assert pois[pid]["missions"] == ["m04_mechoui_saint_jean"]
    assert pois["place_fete"]["prop"] == "fete" and pois["bucher"]["prop"] == "pyre"
    assert math.dist(pois["place_fete"]["position"], pois["bucher"]["position"]) > 100
    autres = [p for p in pois.values() if p.get("missions") and p["missions"] != ["m04_mechoui_saint_jean"] and p.get("building")]
    bat4 = {pois[i]["building"] for i in ids}
    assert not (bat4 & {p["building"] for p in autres}), "un bâtiment sert à deux missions"


def test_lieux_de_mission05():
    """L'enclos et le pré existent ; le pré est dégagé et relié à l'enclos par un couloir sans bâtiment."""
    import math
    from shapely.geometry import LineString, Point, Polygon
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    assert "enclos_odette" in pois and "pre_vaches" in pois
    enclos, pre = pois["enclos_odette"], pois["pre_vaches"]
    assert enclos["prop"] == "pen" and enclos["missions"] == ["m05_vaches_en_goguette"]
    centre = tuple(enclos["position"])
    assert 60 < math.dist(centre, pre["position"]) < 160
    batiments = []
    for fch in (ROOT / "gis/out/tiles").glob("*.json"):
        batiments += [Polygon(b["footprint"]) for b in json.loads(fch.read_text())["buildings"]]
    couloir = LineString([centre, pre["position"]]).buffer(5.0)
    assert not any(b.intersects(couloir) for b in batiments), "un bâtiment barre le couloir"
    assert not any(b.intersects(Point(pre["position"]).buffer(25.0)) for b in batiments), "le pré n'est pas dégagé"
