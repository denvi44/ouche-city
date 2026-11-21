"""Routes et relief : routes nivelées (peu de dévers, pentes bornées), relief continu entre tuiles, graphe routier connecté,
lieux des missions en véhicule accessibles. Mesures dans qa/roads_audit.py (bilinéaire comme dans Godot)."""
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from qa import roads_audit as ra  # noqa: E402

REL = ra.Relief()
LIGNES = ra.mesurer_routes(REL)
STATS = ra.stats(LIGNES)
GRAPHE = ra.graphe()
COMPS = ra.composantes(GRAPHE)
POIS = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}


def test_grille_de_5_m():
    for t in REL.tuiles.values():
        g = t["ground"]
        assert g["resolution"] == 51 and len(g["heights"]) == 51 * 51


def test_relief_continu_entre_tuiles():
    assert ra.discontinuites_de_bord(REL) < 0.01, "marche de terrain à la jonction de deux tuiles"


def test_routes_sans_devers():
    """Avant nivellement : 42 % des échantillons à plus de 4 % de dévers, 27 % à plus de 8 %, jusqu'à 52 %."""
    assert STATS["devers_p50"] < 0.01
    assert STATS["part_devers_sup_4"] < 0.05, f"{STATS['part_devers_sup_4']:.1%} au-dessus de 4 % de dévers"
    assert STATS["part_devers_sup_8"] < 0.025, f"{STATS['part_devers_sup_8']:.1%} au-dessus de 8 % de dévers"
    assert STATS["devers_p99"] < 0.12


def test_pentes_en_long_bornees():
    assert STATS["pente_p50"] < 0.04
    assert STATS["part_pente_sup_12"] < 0.045, "trop de tronçons au-dessus de 12 % (rues de vallée mises à part)"


def test_routes_principales_douces():
    """Les grandes routes (primary/secondary) restent roulables : pente en long ≤ 20 % presque partout."""
    grandes = [r for r in LIGNES if r[0] in ("primary", "secondary")]
    assert grandes
    sup = sum(1 for r in grandes if r[5] > 0.20) / len(grandes)
    assert sup < 0.03, f"{sup:.1%} des échantillons de grandes routes à plus de 20 %"


def test_graphe_principal_connecte():
    assert len(COMPS[0]) >= 0.9 * len(GRAPHE["nodes"]), "le réseau routier est en morceaux"


@pytest.mark.parametrize("pid", ["van_gege", "barrage_bosc_tenney", "stand_comite", "garage_kevin", "casse_dugenou", "drag_depart",
                                 "drag_arrivee", "parc_rdv"])
def test_lieux_en_vehicule_accessibles(pid):
    p = POIS[pid]
    nid, d = ra.noeud_le_plus_proche(GRAPHE, p["position"][0], p["position"][1])
    assert nid in COMPS[0], f"{pid} : le nœud de route le plus proche n'est pas dans le réseau principal"
    assert d < 120.0, f"{pid} : route la plus proche à {d:.0f} m"
