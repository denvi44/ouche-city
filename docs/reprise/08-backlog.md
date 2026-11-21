# 08 — Backlog priorisé (avec critères d'acceptation)

1. **Perf réelle Mac M1 8 Go / PC GTX 1060** — mesurer FPS 1080p « Moyen » sur la rue Sainte-Foy, la carrière et la forêt. *OK si* ≥ 60 FPS moyen, rapport dans `qa/`.
2. **Écoute des sons** — passer le catalogue `Sfx` au casque. *OK si* aucun son agressif/clippé ; ajustements de gain consignés.
3. **Manette et AZERTY** — tester XInput/MFi et remappage. *OK si* `controls_audit` + essai manuel sur les deux OS.
4. **Ligne en ligne > 2 joueurs** — 4 puis 16 clients. *OK si* mission coop jouable à 4, serveur stable.
5. **Notarisation Apple** — secrets CI, `notarytool`. *OK si* ouverture sans `xattr`.
6. **Lobby / comptes** — FastAPI + PostgreSQL en Docker. *OK si* inscription, salon, tests d'API.
7. **PNJ ambiants, trafic, gendarmerie** — routines sur `RoadNav`. *OK si* budget perf respecté.
8. **Filtre daltonisme** — réglage existant mais non appliqué au rendu.
9. **Rapport markdown de l'audit de faisabilité** (`--report=`).
10. **Routes raides restantes** (vallée, ~3 % > 4 % de dévers) — voir décision 0016.
11. **Finitions forêt/carrière** — collisions des arbres, surcouche rocheuse, budget perf.
12. **Renommer le dépôt GitHub** `ouche-city` → `frouch-city`, puis mettre à jour les liens.
13. **Choix du héros jouable** — aujourd'hui un seul avatar (« Vous »). Spécifier avec le propriétaire : héros (Gégé, Ginette, Kévin, Kévin Radio ou nouvelle recrue), apparence (`CharacterModel`), voix de légende, et remplacement du compagnon IA correspondant par « Vous » ; réseau d'abord. *OK si* 1 à 4 joueurs choisissent chacun un héros distinct, le compagnon IA du même nom disparaît, et les rôles de mission suivent.
14. **Props de décor enterrés sur pente** (cuisine du méchoui, scène, bûcher…) — soulever à la plus haute altitude de l'emprise + socle. *OK si* un audit mesure ≤ 5 cm d'enfouissement sur tous les props de `_add_prop`.
15. **Bâtiments voisins chevauchant un édifice public** (mairie : un grand bâtiment mord sur son flanc gauche) — décaler ou retirer le voisin dans `gis/fiction.py`.
16. **Capture des enseignes** — vérification actuellement numérique seulement ; ajouter `qa/screenshots/capture_enseignes.gd`.
