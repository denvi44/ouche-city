# Ouche City — Document de game design (GDD)

Version M0. Plan de production de référence : « Ouche City — Plan de production » (onglets missions 01 à 03).

## Pitch

Un open-world d'action-aventure en cel-shading à Conches-en-Ouche, dans l'Eure. On y fait des embrouilles de village plutôt que des braquages : livrer en douce le calva de Tonton Gégé à la foire, tuner la voiture de Kévin pour le samedi soir, gagner la battle de sono contre le Clos Fleuri. L'humour est « Normandie profonde » : tendre, jamais méprisant.

## Piliers

1. **Une vraie ville** : rues, relief et hauteurs de bâtiments issus des données ouvertes (IGN, OSM), au 1:1 dans le centre médiéval.
2. **Ensemble ou seul, même jeu** : 1 à 4 joueurs en mission, jusqu'à 16 en ville ; en solo, des compagnons IA tiennent les rôles libres.
3. **Le chaos doux** : poursuites de tracteurs, cargaisons fragiles, voisins qui appellent la gendarmerie. Pas de violence gratuite.

## Boucle de jeu

Balade libre → rencontre d'un personnage → mission à rôles (conducteur, guetteur, négociateur…) → médaille (or, argent, bronze) → argent, réputation par quartier, déblocages (véhicules, garage, activités).

## Systèmes (propriétaires)

| Système | Agent | État M0 |
| --- | --- | --- |
| Ville générée (tuiles 250 m, relief, bâti) | 01, 02 | rue Sainte-Foy (26 tuiles, rayon 560 m) importée sans retouche |
| Rendu toon, contours, jour/nuit | 03 | shaders et matériaux de base |
| Joueur à pied, caméra | 05 | marche, sprint, saut, portage de caisse, caméra 3ᵉ personne |
| Conduite arcade | 05 | camionnette de Gégé : accélération, freinage, frein à main, chocs, caméra qui se range |
| Réseau autoritaire, solo local | 12 | poignée de main versionnée, prédiction et réconciliation |
| Cargaison fragile, niveau de recherche | 05 | cargaison (bouteilles cassées selon la violence du choc) faite ; recherche M1 |
| Mission 02 | 05, 06, 07 | jouable : pièces (casse furtive, marchandage, boutique, vol) → montage → essai routier + radar → jury → drag de 400 m contre Dylan ; manquent intro, rôles humains, variété des mini-jeux |
| Mission 05 | 05, 04, 06, 08 | jouable : huit vaches (dont Marguerite, la plus farouche) fuient les gens dans le pré ; on les rabat vers un enclos en se plaçant derrière elles et en sifflant ; clôture et bâtiments les bloquent ; barrière à fermer ; médailles 8 / 6 / 4 vaches ; manquent intro, rôles humains, obstacles (tracteur, chiens) |
| Mission 04 | 05, 04, 06, 08 | jouable : agneau, broche et charbon (4 min) → tenir le feu dans la bonne plage 60 s (soufflet à la volée) → chiens errants → huit assiettes à quatre tables → bûcher et feu d'artifice → satisfaction du village ; manquent intro, rôles humains, foule d'invités |
| Accessoires détaillés | 04 | `PropKit` : 17 accessoires assemblés par le code (lampadaire, banc, jardinière, borne, puits, botte de paille, tonneau, chaise, table à nappe vichy, broche et agneau, brasero, bûcher, flammes, chien, agneau, charbon, fanions) ; mobilier de rue posé sur toute la carte (lampadaires le long des routes, jardinières, bornes et bancs devant les commerces) |
| Mission 03 | 05, 06, 08 | jouable : matériel (5 min) → trois manches de rythme (playlist au choix, sabotages du rival, lâcher de basses) → nuisance et gendarmes → médaille ; manquent intro, rôles humains (DJ, saboteur, électricien, videur), DJ IA, vraie foule |
| Mission 01 | 05, 07 | jouable : 4 caisses → camionnette → barrage → stand → médaille ; manquent cinématique, choix d'équipe, événements de route, compagnons IA |
| PNJ, trafic, compagnons IA | 06 | M1 (graphe routier déjà produit) |
| Missions (JSON) | 07 | m01 à m05 écrites, validées par schéma |
| Audio : effets, moteurs, ambiance, radio | 08 | synthétisés (décision 0006) : klaxon, moteurs, chocs, verre, meuglement, cloches, valse musette ; sous-titres sonores ; playlists de la battle de sono ; autres radios M2 |
| Accessibilité, licences | 11 | sous-titres et échelle du texte prévus dans les réglages |

## Contrôles

| Action | Clavier/souris | Manette |
| --- | --- | --- |
| Se déplacer | W A S D en position physique (Z Q S D sur AZERTY) | stick gauche |
| Caméra | souris | stick droit |
| Sauter | Espace | A / Croix |
| Sprinter | Maj gauche | Start (provisoire, M1 : gâchette) |
| Interagir (prendre / charger une caisse, monter, descendre) | E | X / Carré |
| Conduire | W A S D / stick gauche ; Espace = frein à main | stick gauche ; A = frein à main |
| Klaxon | H | Y / Triangle |
| Radio Pommiers (en voiture) | R | croix directionnelle bas |
| Choix d'équipe au barrage | 1 / 2 / 3 | croix directionnelle haut / gauche / droite |
| Pause (volumes, sous-titres) | Échap | Select |

Aucun raccourci réservé au système (Cmd+Q, Cmd+H…). Remappage complet : M1 (agent 11).

## Personnages (fictifs)

Tonton Gégé (calva, rôle d'arrimeur), Kévin (mécano, diversion), Kévin Radio (guetteur), Ginette (négociatrice, videuse, chineuse), Dylan (rival du drag du samedi), l'adjudant Lemoine (gendarmerie). Bibles détaillées : `narrative/` (agent 07).

## Jalons

- **M0** : préproduction, POC carto de la rue Sainte-Foy, première build signée Windows + macOS.
- **M1** : centre médiéval complet, conduite, PNJ, mission 01 jouable de bout en bout en solo et à 4.
- **M2–M5** : missions 02–03, radios, extension 3 × 3 km, optimisation, bêta.
