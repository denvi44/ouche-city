# 0009 — Mission 04 « Le méchoui de la Saint-Jean » et atelier d'accessoires détaillés

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 04 (accessoires), 05 (gameplay), 06 (compagnons), 08 (audio)

## Contexte

La mission 04 n'existait pas encore (la mission 3 la débloquait seulement). En parallèle, les décors se limitaient à des boîtes et aux arbres ; le blockout des missions manquait de détail. Blender n'est pas disponible dans l'environnement de build (pas de `bpy`) et Git LFS est bloqué : les accessoires sont donc **procéduraux, en GDScript**, sans fichier binaire.

## Décisions — mission

- **Scénario** (`missions/m04_mechoui_saint_jean.json`, schéma mission v1 respecté) : la veille de la Saint-Jean, le Comité des fêtes veut un agneau à la broche pour huit convives. Rôles : cuisinier (Gégé), serveur (Ginette), gardien (Kévin), allumeur (le joueur).
- **Lieux** (POI v6, props `fete` et `pyre`) : cuisine du méchoui, bûcher, trois objets (agneau, broche, charbon), noms fictifs, posés sur la vraie carte.
- **Feu** : la chaleur retombe de 0,07/s ; chaque appui sur « interagir » ajoute 0,1 (intervalle 0,25 s). La viande cuit à pleine vitesse dans la bande 0,45-0,72 (et au-dessus), au tiers de la vitesse entre 0,30 et 0,45, pas du tout en dessous. Au-delà de 0,85, elle brûle (0,04/s) ; à 100 % brûlé, l'agneau est carbonisé : échec. 60 s de cuisson.
- **Chiens** : 3 en solo, 5 en coop, qui arrivent de 26 m à 3,2 m/s. Un chien à portée (3,5 m) a priorité sur le soufflet : « chasser ». S'il atteint le foyer il vole un gigot (−1/3 du bonus « chiens »). Kévin les chasse seul à 6 m (délai 0,3 s) quand il tient son poste.
- **Service** : huit assiettes, quatre tables de deux, 150 s. Une assiette à la fois par personne.
- **Bûcher** : l'allumer termine la mission (feu d'artifice : trois salves sonores et sous-titrées, lumière et flammes à l'écran).
- **Bilan** : satisfaction = 100 × (0,4 × cuisson + 0,4 × convives servis + 0,2 × (1 − gigots volés/3)). Or ≥ 85, argent ≥ 65, bronze ≥ 40 ; en dessous, fête médiocre sans médaille. Échecs : agneau carbonisé, matériel non rassemblé en 4 minutes.
- **Compagnons** : chacun rapporte son objet (Kévin la broche, Ginette l'agneau, Gégé le charbon). Gégé tient le soufflet (il attise dès que la chaleur approche du bas de la bande), Kévin chasse les chiens, Ginette porte les assiettes aux tables les moins servies.

## Décisions — accessoires (`PropKit`, `StreetFurniture`)

- Un accessoire = des primitives (boîtes, cylindres, sphères) fusionnées en un maillage à une surface par couleur, avec le matériau toon du jeu et le contour « inverted hull » (`HullOutline`). Les parties lumineuses (verre de lanterne, braises, flammes) sont sans éclairage.
- 17 accessoires, de 3 à 50 parties chacun : lampadaire, banc, jardinière fleurie, borne, barrière, puits, botte, tonneau, chaise, table à nappe vichy (avec assiettes garnies), jeu de table, broche avec agneau (rose cru → doré → brûlé), brasero, bûcher, flammes, fanions, chien, agneau, caisse de charbon.
- **Mobilier de rue** posé automatiquement sur toute la carte : un lampadaire tous les 46 m le long des routes carrossables (alternance de côté, jamais dans un bâtiment, cap vers la chaussée), et devant chaque commerce deux jardinières, deux bornes et un banc sur trois. Rendu en MultiMesh (corps + contour), placement déterministe.
- Budget : accessoire < 4 000 triangles (testé).

## Correctif de navigation

`m04_companions.gd` a révélé un vrai défaut : le graphe routier contient des passages sous porche (rue de l'Hôtel de Ville) qui traversent un bâtiment que les collisions rendent infranchissable ; Kévin s'y bloquait indéfiniment. `RoadNav.block_buildings` désactive désormais les points du graphe situés dans un contour de bâtiment (piétons seulement) et le cerveau des compagnons rejoint le sommet le plus proche après trois blocages de suite.

## Conséquences

- Manquent : cinématiques, rôles distincts entre joueurs humains, foule d'invités visible, accessoires animés (l'agneau ne tourne pas), arbres détaillés, mobilier à l'intérieur des bâtiments, textures peintes sur les accessoires.
- Les accessoires sont de style « blockout détaillé » : ils remplaceront un jour des modèles Blender, l'API (`PropKit.xxx().build()`) ne changera pas.
- Tests : `m04_flow.gd` (parcours complet + 3 fins), `m04_companions.gd`, `m04_online.sh`, tests unitaires des accessoires, de la navigation et des sons (aboiement, braises, feu d'artifice).
