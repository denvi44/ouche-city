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
    autorises |= {l for _, _, l, _ in fiction.LIEUX_MISSION} | set(fiction.MONUMENTS.values()) | set(fiction.LABELS_M01.values()) | set(fiction.LABELS_M02.values()) | set(fiction.LABELS_M03.values()) | set(fiction.LABELS_M04.values()) | set(fiction.LABELS_M05.values()) | set(fiction.LABELS_M06.values()) | set(fiction.LABELS_M07.values()) | set(fiction.LABELS_M08.values()) | set(fiction.LABELS_PUBLICS.values()) | {"Donjon"}
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


def test_poulailler_a_son_accessoire():
    """Le poulailler de la mission 1 porte l'accessoire « coop » (abri, enclos, poules), sinon c'est une maison comme une autre."""
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    assert pois["poulailler_ginette"]["prop"] == "coop"
    copie = json.loads((ROOT / "game/assets/city/poi.json").read_text(encoding="utf-8"))["pois"]
    assert {p["id"]: p for p in copie}["poulailler_ginette"]["prop"] == "coop", "lancer make city"


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


def test_supermarche_mission06():
    """Le supermarché existe, est posé en terrain libre (emprise de 26 × 18 m), presque plat, porte vers une route."""
    import math
    from shapely.geometry import LineString, Point, Polygon
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    sm = pois["supermarche"]
    assert sm["prop"] == "supermarket" and sm["missions"] == ["m06_courses_de_8h"] and sm["label"].startswith("Supermarché")
    x, z = sm["position"]
    f = sm["facing"]
    fx, fz = math.sin(f), math.cos(f)
    px, pz = fz, -fx
    coins = [(x + px * a * 13 + fx * b * 9, z + pz * a * 13 + fz * b * 9) for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    emprise = Polygon(coins)
    batiments, routes = [], []
    for fch in (ROOT / "gis/out/tiles").glob("*.json"):
        t = json.loads(fch.read_text())
        batiments += [Polygon(b["footprint"]) for b in t["buildings"]]
        routes += [LineString(r["points"]) for r in t["roads"] if r["kind"] not in ("footway", "track")]
    assert not any(b.intersects(emprise) for b in batiments), "un bâtiment dans l'emprise"
    assert not any(r.intersects(emprise) for r in routes), "une route traverse l'emprise"
    devant = LineString([(x, z), (x + fx * 60, z + fz * 60)])
    assert any(r.distance(devant) < 1.0 for r in routes), "la porte ne regarde pas une route"


def _yarn_files():
    return sorted((ROOT / "narrative/dialogues").glob("*.yarn"))


def test_dialogues_valides():
    """Chaque réplique : « Locuteur: texte #line:identifiant », identifiants uniques et stables, nœuds préfixés par la mission."""
    import re
    locuteurs = {"Gégé", "Ginette", "Kévin", "Kévin Radio", "Dylan", "Gendarme", "Père Bernard", "Marguerite", "Josette", "Mme Hubert",
                 "Lemoine", "Lebrun", "Client pressé", "Client", "Vous", "Mémé Odette", "Garde-barrière", "Parisien", "Parisienne"}
    ids, titres = set(), set()
    n_lignes = 0
    for f in _yarn_files():
        prefix = f.name[:3]
        titre = None
        corps = False
        for brut in f.read_text(encoding="utf-8").splitlines():
            l = brut.strip()
            if not l or l.startswith("//"):
                continue
            if not corps:
                if l.startswith("title:"):
                    titre = l[6:].strip()
                    assert titre.startswith(prefix + "_"), f"{f.name} : nœud {titre} sans le préfixe {prefix}"
                    assert titre not in titres, f"nœud en double : {titre}"
                    titres.add(titre)
                elif l == "---":
                    corps = True
                continue
            if l == "===":
                corps = False
                continue
            if l.startswith("<<"):
                continue
            m = re.match(r"^([^:]+): (.+?)( #line:([a-z0-9_]+))( #\w+:.+)*$", l)
            assert m, f"{f.name} / {titre} : réplique mal formée : {l[:60]}"
            assert m.group(1) in locuteurs, f"locuteur inconnu : {m.group(1)}"
            assert len(m.group(2)) <= 150, f"réplique trop longue ({len(m.group(2))}) : {l[:50]}"
            ident = m.group(4)
            assert ident.startswith(titre) and ident not in ids, f"identifiant {ident} incorrect ou en double"
            ids.add(ident)
            n_lignes += 1
    assert len(titres) >= 60 and n_lignes >= 100, (len(titres), n_lignes)


def test_dialogues_importes_dans_godot():
    for f in _yarn_files():
        dst = ROOT / "game/assets/dialogues" / f.name
        assert dst.exists() and dst.read_bytes() == f.read_bytes(), f"{f.name} : lancer make city"


def test_noeuds_appeles_par_les_missions_existent():
    """Tout `say("…")` / `bark("…")` des missions désigne un nœud de dialogue ; chaque mission a une intro et un nœud par étape principale."""
    import re
    titres = set()
    for f in _yarn_files():
        titres |= set(re.findall(r"^title: (\S+)", f.read_text(encoding="utf-8"), re.M))
    for f in (ROOT / "game/scripts/world").glob("mission_m0*.gd"):
        for nom in re.findall(r'(?:say|bark)\("([a-z0-9_]+)"', f.read_text(encoding="utf-8")):
            assert nom in titres, f"{f.name} appelle le nœud inexistant {nom}"
    for m in sorted((ROOT / "missions").glob("m0*.json")):
        assert m.name[:3] + "_intro" in titres, f"{m.name} : pas d'intro"


def test_lieux_de_mission07():
    """Stand, toilettes publiques et maison existent ; le trajet fait 150-230 m à vol d'oiseau et les toilettes sont entre les deux."""
    import math
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    for pid in ("fete_pomme", "wc_publics", "chez_soi"):
        assert pid in pois and pois[pid]["missions"] == ["m07_jus_de_pomme"], pid
    assert pois["fete_pomme"]["prop"] == "pressoir" and pois["wc_publics"]["prop"] == "wc"
    a, b, w = pois["fete_pomme"]["position"], pois["chez_soi"]["position"], pois["wc_publics"]["position"]
    assert 140 < math.dist(a, b) < 240
    assert math.dist(a, w) + math.dist(w, b) < math.dist(a, b) * 1.5, "les toilettes sont loin du trajet"
    assert pois["fete_pomme"]["building"] != pois["chez_soi"]["building"]


def test_donnees_exportees_avec_le_jeu():
    """Les fichiers de données lus par le jeu (ville, missions, dialogues) sont dans le filtre d'inclusion de chaque export :
    sans cela, les builds Windows et macOS démarreraient sans dialogues ni missions."""
    presets = (ROOT / "game/export_presets.cfg").read_text(encoding="utf-8")
    filtres = [l for l in presets.splitlines() if l.startswith("include_filter=")]
    assert len(filtres) >= 2
    for f in filtres:
        for motif in ("assets/city/*.json", "assets/city/tiles/*.json", "assets/missions/*.json", "assets/dialogues/*.yarn"):
            assert motif in f, f"{motif} absent de {f}"


def test_lieux_de_mission08():
    """Voie ferrée rectiligne libre (ni bâtiment, ni route, ni eau) et mare des oies à 60-130 m de son centre, du bon côté des obstacles."""
    import math
    from shapely.geometry import LineString, Point, Polygon
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    for pid in ("passage_niveau", "etang_oies"):
        assert pid in pois and pois[pid]["missions"] == ["m08_oies_en_greve"], pid
    rail, mare = pois["passage_niveau"], pois["etang_oies"]
    assert rail["prop"] == "rail" and mare["prop"] == "pond" and rail["step"] == "block" and mare["step"] == "gather"
    assert 280 <= rail["length"] <= 480
    a = (rail["position"][0], rail["position"][1])
    d = (math.sin(rail["facing"]), math.cos(rail["facing"]))
    voie = LineString([(a[0] - d[0] * rail["length"] / 2, a[1] - d[1] * rail["length"] / 2), (a[0] + d[0] * rail["length"] / 2, a[1] + d[1] * rail["length"] / 2)])
    assert 60 < math.dist(a, mare["position"]) < 130
    obstacles = []
    for f in (ROOT / "gis/out/tiles").glob("*.json"):
        t = json.loads(f.read_text(encoding="utf-8"))
        obstacles += [Polygon(b["footprint"]) for b in t["buildings"]]
        obstacles += [LineString(r["points"]).buffer(r["width"] / 2) for r in t["roads"] if r["kind"] not in ("footway", "track")]
    assert not any(o.intersects(voie.buffer(5.0)) for o in obstacles), "la voie traverse un bâtiment ou une route"
    assert not any(o.intersects(Point(mare["position"]).buffer(12.0)) for o in obstacles), "la mare est sur un bâtiment ou une route"
    m = json.loads((ROOT / "missions/m08_oies_en_greve.json").read_text(encoding="utf-8"))
    assert m["requires"] == ["m07_jus_de_pomme"] and m["flock"]["geese"] == 12 and set(m["companions"]) == {"rabatteuse", "sentinelle", "ferme_file"}
    m7 = json.loads((ROOT / "missions/m07_jus_de_pomme.json").read_text(encoding="utf-8"))
    assert "m08_oies_en_greve" in m7["rewards"]["unlocks"], "la mission 7 débloque la mission 8"


def test_gare_du_pays_d_frouch():
    """Gare sur la voie : quai de 80 m et bâtiment libres de tout obstacle, quai avant le passage à niveau (le train s'y arrête quand
    les oies le bloquent), chemin d'accès libre jusqu'à la route."""
    import math
    from shapely.geometry import LineString, Point, Polygon
    pois = {p["id"]: p for p in json.loads((ROOT / "gis/out/poi.json").read_text(encoding="utf-8"))["pois"]}
    g, rail = pois["gare_pays_frouch"], pois["passage_niveau"]
    assert g["prop"] == "gare" and g["missions"] == ["m08_oies_en_greve"] and g["label"] == "Gare du Pays de Frouch"
    assert abs(g["facing"] - rail["facing"]) < 1e-6 and g["side"] in (-1, 1)
    d = (math.sin(rail["facing"]), math.cos(rail["facing"]))
    rx = (d[1], -d[0])
    q = (g["position"][0] - rail["position"][0], g["position"][1] - rail["position"][1])
    u, v = q[0] * d[0] + q[1] * d[1], q[0] * rx[0] + q[1] * rx[1]
    assert abs(v) < 0.5, "la gare est sur l'axe de la voie"
    assert -rail["length"] / 2 + 40 < u <= -60.0, f"le quai doit finir avant le passage à niveau (u = {u:.0f})"
    side = g["side"]
    lot = Polygon([(g["position"][0] + d[0] * s * 40 + rx[0] * side * w, g["position"][1] + d[1] * s * 40 + rx[1] * side * w)
                   for s, w in ((-1, 2), (1, 2), (1, 26), (-1, 26))])
    batis, routes = [], []
    for f in (ROOT / "gis/out/tiles").glob("*.json"):
        t = json.loads(f.read_text(encoding="utf-8"))
        batis += [Polygon(b["footprint"]) for b in t["buildings"]]
        routes += [LineString(r["points"]).buffer(r["width"] / 2) for r in t["roads"] if r["kind"] not in ("footway", "track")]
    assert not any(o.intersects(lot) for o in batis + routes), "le quai ou le bâtiment est sur un bâtiment ou une route"
    chemin = LineString(g["path"])
    assert 20 < chemin.length < 110 and not any(b.intersects(chemin.buffer(1.0)) for b in batis), "chemin d'accès"
    assert any(r.distance(Point(g["path"][-1])) < 3.0 for r in routes), "le chemin rejoint une route"
