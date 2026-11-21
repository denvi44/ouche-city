# 07 — Réseau, IA, QA, CI

## Réseau
Serveur autoritaire (ENet). `MissionBase.state()` synchronisé à 5 Hz (`_sync`) ; agents « purs état » extrapolés côté client. Solo = serveur local. Code réseau : `game/scripts/net/` uniquement. Tests : `qa/integration/*_online.sh` (2 clients + serveur).
Non fait : lobby/comptes (FastAPI + PostgreSQL, `server/`), > 2 joueurs testés, anti-triche.

## IA
`CompanionBrain` : un rôle par mission et par compagnon (rabatteuse, sentinelle, ferme-file…). Déplacement : `RoadNav` (A* sur graphe routier) + rayon d'obstacle (masque 1). Règle : chaque rôle doit pouvoir être tenu par un compagnon (`mXX_companions`).
Non fait : piétons ambiants, trafic, gendarmerie libre.

## QA
Pyramide dans `03-commandes-et-tests.md`. Audits : hud, movement, vehicle_slope, cinematic, focus, controls, menu_save, feasibility (`qa/feasibility/audit.gd`), `qa/roads_audit.py`. Captures : `qa/screenshots/*` (xvfb + lavapipe, donc **pas** de mesure de perf GPU).
Budgets : `qa/budgets.md`.

## CI (`.github/workflows/ci.yml`)
Linux : pytest + tests GDScript + flows ; Windows et macOS : build ; macOS signé ad hoc (non notarisé) ; Docker. Artefact macOS : `frouch-city-macos` (FrouchCity-mac.zip / .tar.gz). Décompression : `ditto -x -k`, puis `xattr -cr`, puis `codesign --force --deep --sign -`.
Non fait : notarisation Apple (compte développeur requis), mesure de perf sur GPU réel.
