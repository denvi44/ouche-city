# 0017 — Édifices publics détaillés, forêts, vergers, carrière et distillerie

Statut : accepté (orchestrateur)

## Édifices (`game/scripts/world/landmarks.gd`, `gis/fiction.py::lieux_publics`)
Église, mairie, école primaire des Pommiers, collège du Bocage, hôpital de Frouch et distillerie de calva Pommier & Fils sont des **modèles
procéduraux** (primitives fusionnées par `PropKit`, contours « inverted hull », aucun binaire : même rendu sous Windows et macOS, pas de Git LFS)
qui **remplacent** le bâtiment OSM correspondant dans le maillage des tuiles (`CityBuilder.landmark_buildings`), avec une collision à la taille du
volume principal. Le cartographe choisit des bâtiments libres (sans enseigne ni lieu de mission, rectangularité ≥ 0,72) : mairie proche de l'église,
écoles à 120-700 m du centre, hôpital = plus grand rectangle, usine = grande halle de brique. POI v13 : `facility`, `rect` [largeur, profondeur],
`facing` aligné sur un axe du rectangle (front vers la rue). Les modèles adaptent leurs dimensions à `rect` (bornées).
Détails : église (nef, abside, contreforts, vitraux, clocher à flèche, horloge, rosace) ; mairie (fronton, horloge, mansarde, drapeaux, perron) ;
école (clocheton, baies, auvent, cour avec toboggan, balançoires, bascule, marelle) ; hôpital (4 niveaux, croix verte, héliport, urgences, ambulance,
parking) ; distillerie (halle à sheds, cheminée de 32 m, alambics de cuivre, fûts, quai, camion).
Assets « personnalisés » : tout est généré par le code (cohérent avec la règle sans binaire). Si un artiste fournit des glTF, `Landmarks.build` est le
seul point à remplacer (même signature : facility, largeur, profondeur → nœud + taille de collision).

## Forêts, vergers, arbres d'alignement (`gis/vegetation.py`)
Les données ouvertes n'ont que 111 polygones de bois (37,6 ha) et aucun arbre isolé. Semis déterministe : forêts (grille de 6,8 m jitterée par hachage,
chêne 68 %, pin 24 %, peuplier 8 %), quatre vergers fictifs de pommiers (70 × 46 m, rangs de 6,5 × 5,5 m), tilleuls d'alignement (≤ 380). Résultat :
6 777 + 280 + 255 arbres. Format tuile v2 : `trees` = [x, z, espèce] (0 feuillu, 1 pin, 2 pommier, 3 peuplier). Rendu : un MultiMesh par espèce et par
tuile (avec contour), masqué au-delà de 420 m (la distance se mesure à l'origine du nœud : on le place au centre du groupe). Les arbres sont retirés
des lieux de mission, de la voie ferrée, de la gare, de la mare, des édifices.

## Carrière de pierres du Bocage (`gis/nivelage.py::site_carriere`, `profil_carriere`)
Site libre (ni bâtiment, ni route, ni eau, marge de 10 m), à 350-900 m du centre. Le **relief est creusé** dans la grille de 5 m : trois gradins de 4,5 m,
fond plat à −13,5 m, rampe d'accès de 9 m de large (pente ≈ 26 %) tournée vers le bourg. Collision = le terrain. Décor (`CityBuilder._add_carriere`) :
sol de roche, clôture orange avec panneaux « DANGER », pelleteuse, camion-benne, concasseur à tapis, blocs, cabane de chantier, mare. POI v14 : prop `carriere`.

## Tests
`qa/unit/test_decor.py` (édifices distincts et libres, arbres hors bâtiments/routes/voie, carrière creusée et rampe, site libre) ; `run_gdscript_tests.gd`
(modèles à plusieurs dimensions, kits d'arbres et d'engins) ; `capture_edifices.gd` (captures de tous les édifices, de la carrière, de la forêt, du verger).

## Limites connues
Le sol de la carrière est un maillage de roche posé à +0,55 m (la triangulation diffère légèrement de celle du terrain : bords dentelés visibles de près).
L'hôpital et l'usine empiètent parfois sur un bâtiment voisin (parking, quai). Pas de véhicules animés, pas d'intérieurs. Les arbres n'ont pas de collision.
