# 03 — Commandes et tests

Godot 4.4.1 doit être dans le PATH (`godot`). Python 3 avec `pytest jsonschema shapely pyproj numpy`.

## Commandes (Makefile)
| Commande | Effet |
| --- | --- |
| `make gis` | Régénère `gis/out` depuis les caches (`gis/cache/*.json`, sans réseau) puis copie dans `game/assets` (`make city`). **Déterministe.** |
| `make city` | Copie `gis/out`, `missions/`, `narrative/dialogues`, `narrative/cinematics` vers `game/assets/` (obligatoire après toute modification de ces sources) |
| `make test-py` | pytest `qa/unit` (≈ 30 s) |
| `make test-godot` | Tout le reste (≈ 40 min) : tests unitaires GDScript, réseau, flows de m01 à m08 (solo, compagnons, en ligne), audits HUD / mouvements / véhicule / repères / touches / menu / cinématiques, faisabilité |
| `make test` | les deux |
| `make screenshots` | captures 1920×1080 de la scène témoin (GPU conseillé) |
| `make server` | image Docker du serveur dédié |

Lancer un test seul : `godot --headless --fixed-fps 60 --path game -s ../qa/integration/m08_flow.gd -- --mission=m08 --no-companions`.
Captures avec rendu logiciel : `xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan --path game -s ../qa/screenshots/capture_m08.gd -- --out=/tmp/x`.
Le jeu : `godot --path game` (menu) ou `-- --solo --mission=m05` ; serveur dédié : `-- --server --mission=m08 --port=24680`.

## Pyramide de tests
1. **Python** (`qa/unit/*.py`) : contrats (schémas, POI de chaque mission), données (tuiles, routes nivelées, décor, cinématiques), dialogues, pipeline SIG.
2. **GDScript unitaire** (`qa/unit/run_gdscript_tests.gd`) : fonctions pures, kits, synthèse sonore, modèles.
3. **Intégration headless** (`qa/integration/*.gd|sh`) : le monde réel est instancié ; les « flows » pilotent la mission en manipulant l'état (téléportation du joueur, appels à `mission.interact`), `*_companions.gd` laisse
   les compagnons gagner seuls, `*_online.sh` lance un serveur et deux clients.
4. **Audits** : `hud_audit` (jauges/balises valides, un objectif à la fois), `movement_audit` (saut, collisions, mobilier), `vehicle_slope_audit`, `cinematic_audit` (caméra hors des murs), `focus_audit`,
   `controls_audit`, `menu_save_audit`, `feasibility/audit.gd` (bots : chaque mission est finissable dans sa limite ; `--companions`, `--only=m08`, `--report=` à finir).

## Pièges d'exécution (causes de la plupart des échecs rencontrés)
- **Ne pas modifier `game/` ni lancer `make city`/`--import` pendant qu'une régression tourne** : les fichiers lus par les tests changent en cours de route. Utiliser un `git worktree` pour développer en parallèle.
- **Ports** : les tests en ligne utilisent des ports aléatoires ; un autre processus Godot solo prend 24680-24681. Éviter de lancer deux régressions en même temps.
- **`--fixed-fps 60`** rend les tests déterministes (temps simulé) ; sans lui les durées dépendent du CPU.
- **Lambdas GDScript** : capturent les variables locales **par valeur** (utiliser un tableau/dictionnaire pour remonter un état).
- **Typage** : `var x := tableau[i]` échoue (Variant) → `var x: Type = …`. `ease()` et `input()` sont des fonctions natives : ne pas les redéfinir.
- **Chemins** : `res://`/`user://` uniquement ; la CI Linux est sensible à la casse, pas macOS.
- **Distance de visibilité** d'un MultiMesh : mesurée à l'**origine du nœud** (placer le nœud au centre du groupe).
- **Données** : après `make gis`, relancer pytest (les copies dans `game/assets` doivent être exactes) ; si un POI change de place, les missions qui en dépendent bougent (voir `04`).
- **Compagnons** : les rayons de vue (`_clear`) ne voient que la couche 1 ; leurs corps ignorent le mobilier de rue ; les mâts de lampadaires ne sont pas solides (ils coinçaient l'IA).
