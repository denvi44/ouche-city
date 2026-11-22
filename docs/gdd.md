# Frouch City — Document de game design (GDD)

Version M0. Plan de production de référence : « Frouch City — Plan de production » (onglets missions 01 à 03).

## Pitch

Un open-world d'action-aventure en cel-shading à Frouch, dans l'Eure. On y fait des embrouilles de village plutôt que des braquages : livrer en douce le calva de Tonton Gégé à la foire, tuner la voiture de Kévin pour le samedi soir, gagner la battle de sono contre le Clos Fleuri. L'humour est « Normandie profonde » : tendre, jamais méprisant.

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
| Mission 07 | 05, 04, 06, 07, 08 | jouable : après un jus de pomme « un peu vif » à la fête de la pomme, rentrer aux toilettes de chez soi sans accident : pression qui monte (course, pavés, crampes, frayeurs), serrer (marche de crabe, endurance), Mme Hubert, chien, toilettes publiques (bronze), porte fermée à clé (clé sous le pot ou Ginette) ; or ≤ 70 % de pression à l'arrivée, argent, bronze ; humour tendre, tout hors champ (onomatopées) |
| Dialogues et onomatopées | 07, 03, 08 | 87 nœuds Yarn (125 répliques) dits par-dessus l'action, bulles de paroles, sous-titre ; onomatopées en bulles (POUET POUET !, BOUM !, CRAAAC !…) pour chaque son important, désactivables ; passage des scènes au vote |
| Mission 06 | 05, 04, 06, 08 | jouable : faire six courses au Panier de Frouch à 2 km/h (plafond de vitesse imposé), lecture d'étiquettes immobile, causette de Mme Hubert, file de clients pressés dont l'impatience monte, « Après vous ! », caisse (compter la monnaie), gérant qui raccompagne au 4ᵉ incident, médailles selon l'heure de sortie (8 h 50 / 9 h / 9 h 30) ; manquent intro, rôles humains, intérieur d'autres commerces |
| Bâtiments détaillés | 04 | cheminées sur le faîtage, lucarnes à fenêtre et petit toit, corniche sous l'égout, soubassement de pierre, auvent de porte sur consoles (stores rayés pour les commerces), contreforts d'église ; la porte 3D suit la porte peinte par le shader ; sans collision |
| Personnages détaillés | 04, 05 | visage (yeux, sourcils, bouche, oreilles), cheveux (court, chignon, long), moustache, barbe, lunettes ; col, boutons, poches, ceinture à boucle, gilet, tablier, foulard ; manchettes, pouces, semelles ; couvre-chefs (béret, casquette, casque audio, foulard, paille, képi) ; un style par personnage |
| Mission 05 | 05, 04, 06, 08 | jouable : huit vaches (dont Marguerite, la plus farouche) fuient les gens dans le pré ; on les rabat vers un enclos en se plaçant derrière elles et en sifflant ; clôture et bâtiments les bloquent ; barrière à fermer ; médailles 8 / 6 / 4 vaches ; manquent intro, rôles humains, obstacles (tracteur, chiens) |
| Mission 04 | 05, 04, 06, 08 | jouable : agneau, broche et charbon (4 min) → tenir le feu dans la bonne plage 60 s (soufflet à la volée) → chiens errants → huit assiettes à quatre tables → bûcher et feu d'artifice → satisfaction du village ; manquent intro, rôles humains, foule d'invités |
| Accessoires détaillés | 04 | `PropKit` : 17 accessoires assemblés par le code (lampadaire, banc, jardinière, borne, puits, botte de paille, tonneau, chaise, table à nappe vichy, broche et agneau, brasero, bûcher, flammes, chien, agneau, charbon, fanions) ; mobilier de rue posé sur toute la carte (lampadaires le long des routes, jardinières, bornes et bancs devant les commerces) |
| Mission 03 | 05, 06, 08 | jouable : matériel (5 min) → trois manches de rythme (playlist au choix, sabotages du rival, lâcher de basses) → nuisance et gendarmes → médaille ; manquent intro, rôles humains (DJ, saboteur, électricien, videur), DJ IA, vraie foule |
| Mission 01 | 05, 07 | jouable : 4 caisses → camionnette → barrage → stand → médaille ; manquent cinématique, choix d'équipe, événements de route, compagnons IA |
| PNJ, trafic, compagnons IA | 06 | M1 (graphe routier déjà produit) |
| Missions (JSON) | 07 | m01 à m07 écrites, validées par schéma |
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

## Mission 9 — Le siège des Bretons (chapitre bonus)
Sous la pluie, des Bretons en ciré jaune débarquent loin du village et lancent du beurre salé sur les façades. Vous êtes Kévin : portez **dix camemberts**,
des étals (à prendre avec E) à la catapulte de la Saint-Camembert (à charger avec E), dans le temps imparti (240 s : le village « tient » tant que la jauge n'est pas vide).
Les flaques de beurre au sol ralentissent. Au dixième camembert, la catapulte tire (cinématique : épaisse fumée verte et jaunâtre, les Bretons fuient vers leurs terres
sous la pluie). Médaille d'après la part de village restante au moment du tir (or ≥ 50 %, argent ≥ 25 %). Musique : Breton-Norman Clash, tout du long. Tout est fictif.

## Mission 8 — Les oies font grève
Vous êtes l'oie meneuse de Mémé Odette. Un « HONK ! » rassemble la basse-cour, un autre la rassure, un troisième fait reculer le garde-barrière :
barrez la voie et arrêtez le Train des Vacances de 17 h 42 (il freine toujours) le temps que les Parisiens descendent et s'attendrissent.
