# 0016 — Routes nivelées, pentes des véhicules, repères un par un, mission 8

Statut : accepté (orchestrateur)

## Routes nivelées (agent 01, `gis/nivelage.py`)
Constat (`qa/roads_audit.py`) : sur le relief brut de l'IGN (une altitude tous les 25 m), 42 % des échantillons d'axe de route avaient
plus de 4 % de dévers, 27 % plus de 8 %, jusqu'à 52 % (rue des Fontaines). Les véhicules glissent, se couchent ou décollent.
Correctif : grille de relief de 5 m (51 × 51 par tuile, bords partagés), puis nivellement de chaque route carrossable par priorité :
profil en long lu sur la grille, lissé (±10 m) et borné (9 à 12 % selon la classe), carrefours épinglés sur la route déjà nivelée,
tous les nœuds à moins de (demi-chaussée + trottoir + 3 m) de l'axe à la hauteur du profil (dévers nul), talus de 7 m, chaussées déjà
nivelées verrouillées. Résultat : dévers médian 2,8 % → 0,1 %, 42 % → 3,4 % au-dessus de 4 %, 27 % → 1,5 % au-dessus de 8 % ; les
restes sont des rues de vallée aux carrefours imposés. Le site de la piste de drag (mission 2) a changé en conséquence (recherche du
terrain le plus plat). Tests : `qa/unit/test_routes.py` (dévers, pentes, continuité entre tuiles, graphe connexe, lieux accessibles).

## Véhicules sur les pentes
Banc d'essai `qa/integration/vehicle_slope_audit.gd` (rampes de 8° et 14°, crête, descente) : pas de décollage, vitesse tenue. Inclinaison
visuelle de la caisse bornée à ±11°.

## Repères un par un
`MissionBase.focus_markers()` : une seule balise (objectif en cours) plus celles marquées `keep` (danger immédiat) ; minicarte, flèches
et faisceaux lumineux du monde suivent. Audit `qa/integration/focus_audit.gd` et `hud_audit.gd`.

## Mission 8 « Les oies font grève »
Le joueur est une oie (`goose_model.gd`, avatar « oie » du `Player`, plus lente et plus basse). Un « HONK ! » (E, recharge de 2 s par
joueur) rassemble les oies à moins de 20 m : elles suivent le meneur en file, s'installent sur la voie dès que le meneur y est, le train
(15 m/s, départ calé pour arriver à 120 s) freine **toujours** avant la première oie et attend ; il repart si moins de 5 oies tiennent la
voie 7 s. Tenue de 30 s ; le klaxon du train effraie les oies non rassurées par un cri récent ; le garde-barrière sort 8 s après l'arrêt et
chasse une oie toutes les 2,5 s, un cri à moins de 8 m le fait reculer 9 s. Médailles d'après la moyenne d'oies sur la voie (or ≥ 10, argent ≥ 8,
bronze ≥ 5). Données : POI `passage_niveau` (prop `rail`, champ `length`) et `etang_oies` (prop `pond`), contrat POI v11 ; joueurs et
compagnons (Kévin rassemble, Ginette guette, Gégé rassure) apparaissent près de la mare (`spawn_hint`). Audit de faisabilité : seul, médaille d'argent
en 145 s ; avec les compagnons, bronze.

## Gare du Pays de Frouch
Les données ouvertes de la zone (IGN BD TOPO : bâtiments, routes, végétation, eau) n'ont ni voie ferrée ni gare : la voie et la gare sont
fictives. `gis/fiction.py` oriente la voie de la gare vers le passage à niveau (le train vient du côté de la gare), puis cherche le quai de 80 m
et le bâtiment (emprise de 2 à 26 m de l'axe) libres de tout obstacle entre 160 et 60 m avant le passage à niveau, au plus près de 70 m, avec un
chemin d'accès libre (≤ 110 m) jusqu'à la route la plus proche. Résultat : gare à 70 m avant le passage à niveau, côté opposé à la mare, chemin de
66 m. POI `gare_pays_frouch` (prop `gare`, champs `side` et `path`, contrat POI v12). Le train s'arrête le long du quai quand les oies le bloquent ;
six voyageurs parisiens (valises) descendent sur le quai pendant la tenue. Quai surélevé (0,8 m) avec rampes, auvent, bâtiment avec horloge et
enseigne, bancs et lampadaires de quai, chemin de gravier. Tests : `test_gare_du_pays_d_frouch`, cinématiques, accessoires.
