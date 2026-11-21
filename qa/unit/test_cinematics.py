"""Cinématiques (narration) : conformes au contrat, ancrées sur de vrais lieux de la mission, durées raisonnables,
copiées dans le projet Godot (make city) et sans marque réelle."""
import json
import re
from pathlib import Path

import jsonschema
import pytest

ROOT = Path(__file__).resolve().parents[2]
FILES = sorted((ROOT / "narrative/cinematics").glob("*.json"))
SCHEMA = json.loads((ROOT / "contracts/cinematic.schema.json").read_text(encoding="utf-8"))
POIS = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
MISSIONS = {f"m0{i}" for i in range(1, 9)}


def load(p):
    return json.loads(p.read_text(encoding="utf-8"))


def test_il_y_a_des_cinematiques_pour_chaque_mission():
    names = {p.stem for p in FILES}
    for m in MISSIONS:
        assert f"{m}_intro" in names, f"{m} : pas d'introduction"
        assert f"{m}_done" in names, f"{m} : pas de scène de réussite"


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_cinematique_valide(path):
    d = load(path)
    jsonschema.validate(d, SCHEMA)
    assert d["id"] == path.stem and d["id"] == f"{d['mission']}_{d['when']}"
    assert d["mission"] in MISSIONS
    if d["when"] == "intro":
        assert d.get("title") and d.get("subtitle"), "l'introduction a un carton de titre"
    total = sum(s["dur"] for s in d["shots"])
    assert total <= (24 if d["when"] == "intro" else 12), f"trop longue : {total:.1f} s"
    assert any("caption" in s for s in d["shots"]), "au moins une légende (accessibilité : rien ne passe que par l'image)"


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_lieux_existent_et_appartiennent_a_la_mission(path):
    d = load(path)
    for s in d["shots"]:
        refs = [s["cam"], s["look"]] + [s[k] for k in ("cam_to", "look_to") if k in s]
        for r in refs:
            assert r["at"] in POIS, f"POI inconnu : {r['at']}"
            assert any(m.startswith(d["mission"]) for m in POIS[r["at"]].get("missions", [])), f"{r['at']} n'est pas un lieu de {d['mission']}"
        if "cam_to" in s:
            assert s["cam_to"]["at"] == s["cam"]["at"], "le travelling reste autour d'un même lieu"
        # La caméra ne se pose jamais dans le sol et ne regarde pas son propre point.
        assert s["cam"]["off"][1] >= 1.0


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.stem)
def test_fiction_et_langue(path):
    d = load(path)
    texte = " ".join([d.get("title", ""), d.get("subtitle", "")] + [s.get("caption", {}).get("text", "") for s in d["shots"]])
    assert not re.search(r"subaru|renault|peugeot|citro[eë]n|leclerc|carrefour|google|gta", texte, re.I)
    for s in d["shots"]:
        c = s.get("caption")
        if c:
            assert c["text"].strip() and c["who"].strip()
            assert c["text"][0].isupper() or c["text"][0] in "«…"


def test_copie_dans_godot():
    """game/assets/cinematics doit être une copie exacte de narrative/cinematics (make city)."""
    for src in FILES:
        dst = ROOT / "game/assets/cinematics" / src.name
        assert dst.exists() and dst.read_bytes() == src.read_bytes(), f"{src.name} : lancer make city"


def test_export_inclut_les_cinematiques():
    cfg = (ROOT / "game/export_presets.cfg").read_text(encoding="utf-8")
    assert cfg.count("assets/cinematics/*.json") >= 2, "les cinématiques doivent être exportées (Windows et macOS)"
