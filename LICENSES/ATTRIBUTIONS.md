# Attributions

Tenu à jour par l'agent `accessibilite-conformite` (11) et l'agent `cartographe` (01). Chaque source ajoutée est datée.

## Données cartographiques

| Source | Usage | Licence | Mention | Date d'extraction |
| --- | --- | --- | --- | --- |
| OpenStreetMap | POI, arbres, typologies (complément) | ODbL 1.0 (base dérivée publiée sous ODbL) | © contributeurs OpenStreetMap | pas encore extrait (API Overpass injoignable depuis l'environnement CI, voir docs/decisions/0003) |
| IGN RGE ALTI (service d'altimétrie Géoplateforme, ressource `ign_rge_alti_wld`) | Relief, grille 50 m | Licence Ouverte Etalab 2.0 | Source : IGN | 2026-11-20 |
| IGN BD TOPO V3 (WFS Géoplateforme : bâtiment, tronçon de route, zone de végétation, surface hydrographique) | Emprises et hauteurs de bâtiments, routes et noms de voies (BAN), végétation, eau | Licence Ouverte Etalab 2.0 | Source : IGN | 2026-11-20 |

Fichiers bruts : `gis/cache/ign_bdtopo.json`, `gis/cache/ign_alti.json` (datés dans leur champ `extrait_le`).

La mention « © contributeurs OpenStreetMap » apparaît aussi dans les crédits du jeu et sur la carte en jeu.

## Musique, sons, polices

| Élément | Origine | Licence |
| --- | --- | --- |
| Effets sonores (klaxon, moteurs, chocs, verre, meuglement, cloches, vent, oiseaux…) | Synthèse par le code, `game/scripts/audio/synth.gd` | Œuvre originale du projet, aucune ressource tierce |
| « Valse du Pommier » (Radio Pommiers) | Composition originale du projet, générée par `Synth.music_pommier` | Œuvre originale du projet |
| Polices | Police par défaut du moteur Godot (Open Sans, licence OFL) | SIL Open Font License 1.1 |

## Musiques personnalisées

Les mp3 déposés par le joueur dans `user://musique/` ne sont jamais distribués avec le jeu ni envoyés en ligne. Tout fichier placé dans `game/assets/musique_perso/` doit être accompagné de sa licence ici.

## Police des menus

Bebas Neue — © 2019 The Bebas Neue Project Authors (https://github.com/dharmatype/Bebas-Neue), licence SIL Open Font 1.1 (texte : `LICENSES/OFL-BebasNeue.txt`). Fichier : `game/assets/fonts/BebasNeue-Regular.ttf`.

Blason de l'écran titre (`game/assets/ui/blason.png`) : illustration fournie par le propriétaire du projet (blason de Normandie détourné), détourée à partir de l'illustration fournie ; usage autorisé par lui dans le jeu.
