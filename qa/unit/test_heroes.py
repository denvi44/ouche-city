"""Le héros change selon la mission : chaque mission en désigne un, parmi les cinq personnages, avec de la variété."""
import json
from pathlib import Path

import jsonschema

ROOT = Path(__file__).resolve().parents[2]
MISSIONS = {p.name[:3]: json.loads(p.read_text(encoding="utf-8")) for p in sorted((ROOT / "missions").glob("m0*.json"))}
SCHEMA = json.loads((ROOT / "contracts/mission.schema.json").read_text(encoding="utf-8"))


def test_chaque_mission_a_un_heros_valide():
    assert len(MISSIONS) == 8
    for k, m in MISSIONS.items():
        assert m.get("hero") in ("gege", "ginette", "kevin", "kevin_radio", "odette"), k
        jsonschema.validate(m, SCHEMA)


def test_le_heros_varie():
    heros = [m["hero"] for m in MISSIONS.values()]
    assert len(set(heros)) >= 5, "les cinq personnages jouables apparaissent"
    for a, b in zip(heros, heros[1:]):
        assert a != b, "on ne garde pas le même héros d'une mission à la suivante"
