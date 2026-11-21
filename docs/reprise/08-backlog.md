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
