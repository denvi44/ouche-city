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
| Mission 01 | 05, 07 | jouable : 4 caisses → camionnette → barrage → stand → médaille ; manquent cinématique, choix d'équipe, événements de route, compagnons IA |
| PNJ, trafic, compagnons IA | 06 | M1 (graphe routier déjà produit) |
| Missions (JSON) | 07 | m01 à m03 écrites, validées par schéma |
| Audio : effets, moteurs, ambiance, radio | 08 | synthétisés (décision 0006) : klaxon, moteurs, chocs, verre, meuglement, cloches, valse musette ; sous-titres sonores ; autres radios M2 |
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
