# 04 — Pipeline de données

Sources (voir `docs/decisions/0003-…`, `LICENSES/ATTRIBUTIONS.md`) : IGN BD TOPO V3 (bâtiments, routes, végétation, eau) et IGN altimétrie, via `gis/fetch_ign.py` ; OSM en secours (`gis/fetch.py`).
Les caches `gis/cache/ign_bdtopo.json` et `ign_alti.json` sont **dans le dépôt** : `make gis` ne demande aucun réseau. Les zones IGN **n'ont ni voie ferrée, ni gare, ni arbres isolés** : tout cela est fictif.

## Ordre d'exécution (`gis/build.py`)
1. Lecture des sources, repère local (mètres autour du centre), découpage en tuiles de 250 m (26 tuiles autour du POC « Rue Sainte-Foy »).
2. `construire()` : relief brut → bâtiments (typologies : annexe, colombages, brique, pavillon, commerce, église) → routes (densifiées, largeurs par classe) → végétation → arbres ponctuels.
3. **Carrière** : `nivelage.site_carriere` (disque libre, 350-900 m du centre).
4. **`nivelage.niveler`** : grille de 5 m (51 × 51 par tuile, bords partagés) ; routes carrossables par priorité (profil lissé et borné 9-14 %, carrefours épinglés, chaussées verrouillées, talus de 7 m) ;
   puis creusement de la carrière. Mesures : `python3 qa/roads_audit.py`.
5. **`vegetation.planter`** : arbres de forêt (grille jitterée 6,8 m), vergers (4), arbres d'alignement ; format `[x, z, espèce]`.
6. Graphe routier (`road_graph.json`), POI OSM, puis **POI fictifs** dans cet ordre (l'ordre compte : chaque étape évite les bâtiments pris avant) :
   `lieux_fictifs` (commerces, monuments) → missions 1 à 7 → **mission 8** (voie ferrée, mare, gare) → carrière → `lieux_publics` (mairie, écoles, hôpital, usine, annote l'église).
7. `vegetation.nettoyer` retire les arbres des lieux de mission, de la voie et de la gare ; écriture des tuiles, `poi.json`, `manifest.json`.

## Conséquence importante
Les lieux de mission sont **choisis par balayage déterministe** (le plus plat, le plus proche…). Toute modification du relief ou des bâtiments peut déplacer un POI (c'est arrivé : la piste de drag de la mission 2 a changé de place
quand le relief a été nivelé). Après un changement de données : `make gis`, `make test`, relire `qa/feasibility/audit.gd` (temps de trajet des missions), recapturer.

## Contrats (`contracts/`)
- `tile.schema.json` v2 : `ground.resolution` 51 ; `trees` = `[x, z]` ou `[x, z, espèce]` ; végétation `orchard` en plus.
- `poi.schema.json` v14 : `prop` ∈ {van, barrier, stand, fumier, garage, junkyard, strip, car, stage, fete, pyre, pen, supermarket, pressoir, wc, coop, rail, pond, gare, carriere} ;
  champs v3+ : `step`, `prop` ; v10-v14 : `length` (rail), `side`/`path` (gare), `facility`/`rect` (édifices).
- `mission.schema.json`, `save.schema.json`, `cinematic.schema.json`.
Modifier un schéma : incrémenter `version`, mettre à jour la description, ajouter/adapter les tests dans `qa/unit/test_contracts.py`. Les labels de POI doivent être déclarés dans `gis/fiction.py` (test des noms fictifs).

## Ajouter un lieu fictif
Voir `09-recettes.md` (« Ajouter un POI »). Règles : jamais de nom réel (personne, enseigne, marque) ; `missions: [id]` pour un lieu de mission ; ids en `[a-z0-9_]+`.
