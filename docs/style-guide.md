# Style guide — Frouch City

Une page, tenue par l'agent 03. Référence : la rue Sainte-Foy (`game/scenes/temoin_rue_sainte_foy.tscn`).

## Intention

Une Normandie de carte postale peinte à la main : aplats francs, contours sombres, ciel en bandes. Jamais de texture photo, jamais de PBR réaliste. Lisible de loin, tendre de près.

## Palette (sRGB)

| Rôle | Teinte | Valeur |
| --- | --- | --- |
| Colombages (poutres) | brun foncé | `#45301F` |
| Torchis | crème | `#EDD9AD` |
| Ardoise | bleu-gris | `#5C6B80` |
| Tuile | brun-rouge | `#9E543D` |
| Brique | rouge | `#B5543D` |
| Vert bocage | vert | `#739E52` |
| Route | gris bleuté | `#61616B` |
| Trottoir | pierre claire | `#B3ADA3` |
| Contour | presque noir chaud | `#1F1714` |
| Accent UI (pomme) | rouge pomme | `#B82E29` |

Les matériaux de base sont dans `game/assets/materials/` (un `.tres` par rôle).

## Lumière

- **3 paliers nets** (`toon.gdshader` + `toon_bandes.gdshaderinc`) : ombre = lumière ambiante seule (teintée par le ciel, jamais noire), mi-teinte, plein jour. Seuils par défaut : 0,02 et 0,5 sur N·L, bords anti-crénelés. Cibles de lisibilité à midi : ombre ≈ 50 %, mi-teinte ≈ 78 %, plein jour 100 % de l'aplat.
- **Ombres portées dures** : atténuation seuillée, `shadow_blur = 0`.
- **Rim light** discret (force 0,25) pour détacher personnages et véhicules.
- **Cycle jour/nuit** (`day_night.gd`) : rampes peintes ; aube rose, midi bleu franc, 20 h 30 orangé, nuit bleu nuit (jamais noir pur). Soleil : est à 6 h, sud à midi, ouest à 18 h.

## Contours

- Personnages et véhicules : **inverted hull** (`contour_coque.gdshader`), 2,5 cm pour un personnage, 4 cm pour un véhicule.
- Décor : **inverted hull aussi** (`contour_decor.gdshader`) : un maillage de contour par tuile dont les sommets portent une normale lissée (pas de fissure aux angles). Épaisseur ≈ 2 px à toute distance (0,035 m + 0,28 % de la distance). Pas de post-process par profondeur : la texture de profondeur n'est pas fiable entre moteurs de rendu (voir décision 0005), et la géométrie garantit un rendu identique Windows / macOS.

## Proportions et lisibilité

- Personnages : tête légèrement grosse (1/5 de la hauteur), silhouette lisible à 30 m ; un accessoire signature par personnage (béret pour le joueur par défaut).
- Bâtiments : hauteurs réelles (IGN), toits normands raides (~50°), soubassement de pierre de 60 cm sur les colombages.
- Façades à colombages : poteaux tous les 1,25 m, une croix de Saint-André sur quatre panneaux.
- UI : police par défaut du moteur (aucune police reprise d'un autre jeu), corps 26 px minimum à 1080p, contraste ≥ 4,5:1, encadrés crème bordés de contour. Échelle du texte réglable de 1 à 2.

## Interdits

Logos, polices, icônes ou cadres d'interface repris de GTA ou d'un autre jeu ; textures photographiques ; noir pur ; flou de profondeur.
