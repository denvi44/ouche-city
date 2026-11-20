# Budgets de performance

Configs de référence (`CLAUDE.md`) : **Mac M1 8 Go** et **PC GTX 1060 / RX 580 8 Go**, 1080p, réglages « Moyen », **60 FPS** (16,6 ms par image).

| Poste | Budget | Mesure M0 |
| --- | --- | --- |
| Image complète | ≤ 16,6 ms (p95), ≤ 20 ms (p99) | à mesurer sur les runners avec GPU |
| Post-process contours | ≤ 1,5 ms à 1080p (M1) | à mesurer |
| Ombres (soleil) | ≤ 2,5 ms, distance 160 m | à mesurer |
| Triangles visibles | ≤ 1,5 M | scène témoin : ≈ 150 k, contours inclus (26 tuiles, 1 359 bâtiments : le bâti est dessiné deux fois, corps + coque de contour) |
| Appels de rendu | ≤ 2 000 | scène témoin : 236 surfaces (1 par matériau et par tuile) + joueurs |
| PNJ actifs (IA complète) | ≤ 60 dans 150 m | M1 |
| Véhicules simulés | ≤ 40 | M1 |
| Mémoire vive (client) | ≤ 3 Go | à mesurer |
| Mémoire vidéo | ≤ 2 Go | à mesurer |
| Chargement scène témoin | ≤ 5 s sur SSD | génération de la ville : 0,7 s (CPU, CI Linux) |
| Bande passante par joueur (descendante) | ≤ 64 kbit/s à 16 joueurs | état joueur : 20 Hz × ~40 octets × 15 pairs ≈ 96 kbit/s ; à réduire par zones d'intérêt (M1) |
| Bande passante par joueur (montante) | ≤ 16 kbit/s | entrées : 60 Hz × ~28 octets (5 flottants + en-tête) ≈ 13 kbit/s ; en voiture 3 flottants, moins |
| Serveur dédié, 16 joueurs | ≤ 1 cœur à 50 %, ≤ 1 Go | à mesurer (test de charge, agent 12) |

Tolérance des comparaisons de captures Windows / macOS : écart moyen ≤ 2 % par canal, aucun bloc 32 × 32 au-delà de 10 % (à confirmer avec l'agent 03).
