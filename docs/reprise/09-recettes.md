# 09 — Recettes

**Ajouter une mission** : JSON `missions/mNN_*.json` (schéma) → `mission_mNN.gd` (hérite `MissionBase`, tout l'état côté serveur) → ajouter l'id à `MISSION_IDS` (`world.gd`) → lieux dans `gis/fiction.py` (labels + `lieux_missionNN`, appeler dans `build.py`) → `make gis` → dialogue Yarn → cinématiques intro/done/failed → rôles `CompanionBrain` → tests flow/companions/online → audit feasibility → décision `docs/decisions/`.
**Ajouter un POI** : label dans `fiction.py`, fonction de placement déterministe, champ `prop` autorisé dans `poi.schema.json` (bump de version si nouveau), construction dans `city_builder.gd`, test dans `qa/unit/test_contracts.py`.
**Ajouter un édifice** : fonction dans `landmarks.gd`, `facility` dans `LABELS_PUBLICS`, test de nombre de pièces (`run_gdscript_tests.gd`), capture `capture_edifices.gd`.
**Ajouter un son** : `Synth` → `Sfx` → test.
**Ajouter un dialogue** : `.yarn` dans `narrative/dialogues/`, nœud référencé par l'étape.
**Ajouter une cinématique** : JSON `narrative/cinematics/`, ancré sur un POI, `cinematic_audit`.
**Avant de commit** : `make test`. Ne jamais lancer `make city`/`--import` pendant une régression en cours.
