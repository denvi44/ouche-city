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
    autorises |= {l for _, _, l, _ in fiction.LIEUX_MISSION} | set(fiction.MONUMENTS.values()) | set(fiction.LABELS_M01.values()) | {"Donjon"}
    pois = json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]
    for p in pois:
        if p["kind"] in ("spawn", "viewpoint"):
            continue
        assert any(p["label"] == n or p["label"].startswith(n + " ") for n in autorises), f"nom non fictif ou non répertorié : {p['label']}"


def test_lieux_de_mission01_couvrent_les_etapes():
    """Chaque étape spatiale de m01 a un lieu posé sur la carte, et chaque lieu sert une étape existante."""
    m = json.loads((ROOT / "missions/m01_calva_gege.json").read_text(encoding="utf-8"))
    etapes = {s["id"] for s in m["steps"]}
    pois = [p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"] if p.get("step")]
    assert pois and all(p["step"] in etapes and "m01_calva_gege" in p["missions"] for p in pois)
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
