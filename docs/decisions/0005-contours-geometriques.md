# 0005 — Contours : inverted hull partout, pas de post-process de profondeur

- **Date** : 2026-11-20
- **Statut** : acceptée (orchestrateur), propriétaire : agent 03

## Contexte

Le premier jet utilisait un post-process lisant la texture de profondeur pour tracer les contours du décor. Vérifié en Forward+ (Vulkan logiciel), il ne dessinait rien : la profondeur lue était nulle. Ce rendu n'existe pas du tout dans le mode Compatibility de Godot 4.4. Un contour qui dépend du moteur de rendu viole la règle « rendu identique sur Windows et macOS ».

## Décision

- Contours du décor par **inverted hull** : `CityBuilder` duplique les triangles du bâti dans un maillage `Contours` par tuile (sans ombre), chaque sommet portant en `COLOR` la normale lissée de sa position. `contour_decor.gdshader` le gonfle le long de cette normale, faces avant masquées.
- L'épaisseur croît avec la distance pour garder ≈ 2 px à l'écran.
- Le post-process `contour_ecran.gdshader` est supprimé.

## Conséquences

- Contours identiques en Forward+ et Compatibility, sans texture de profondeur.
- Coût : un second jeu de triangles pour le bâti (≈ ×2 sur les bâtiments, voir `qa/budgets.md`).
- Les arêtes intérieures (toit contre mur) sont lisibles par la différence de palier de lumière ; un trait d'arête supplémentaire reste possible plus tard (géométrie), sans dépendre du rendu.
