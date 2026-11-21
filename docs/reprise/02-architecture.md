# 02 — Architecture

## Dossiers (rappel de `CLAUDE.md`, avec les ajouts)
```
contracts/        schémas JSON versionnés : tile (v2), poi (v14), mission, save, cinematic (v1)
gis/              pipeline Python : build.py (orchestration), nivelage.py (routes nivelées, carrière), vegetation.py (arbres, vergers),
                  fiction.py (noms et lieux fictifs, missions 1-8, édifices publics), config.py, fetch*.py (données ouvertes)
game/             projet Godot 4.4.1 (GDScript seul)
  scripts/core      settings, progress (sauvegarde solo), input_bindings (remappage)
  scripts/net       network_manager (autoload Net), net_body (prédiction/réconciliation)
  scripts/world     city_builder, mission_base + mission_m01…m08, prop_kit, landmarks, street_furniture, building_details, smoke_puff, day_night…
  scripts/player    player, character_model, goose_model, vehicle, car, camera_rig
  scripts/ai        companion_brain (rôles des compagnons), road_nav (A* sur le graphe routier)
  scripts/audio     synth (sons générés), sfx (catalogue, légendes, onomatopées), ambiance
  scripts/narrative yarn_lite, dialogue_player, speech_bubbles
  scripts/cinematic cinematic_player, cinematic_director
  ui/               main_menu, hud (+ hud_widgets), controls_menu, theme_util
  assets/           copies générées (make city) : city/ (tuiles, poi, graphe), missions/, dialogues/, cinematics/
missions/         JSON de mission (source de vérité) ; narrative/dialogues/*.yarn ; narrative/cinematics/*.json
qa/               unit/ (pytest + run_gdscript_tests.gd), integration/ (flows, compagnons, en ligne, audits), feasibility/audit.gd, screenshots/, roads_audit.py
docs/             gdd, style-guide, decisions/, reprise/ (ce dossier)
```
**Ne jamais éditer `game/assets/*` à la main** : tout vient de `make gis` / `make city` (copies de `gis/out`, `missions/`, `narrative/`). Les tests Python vérifient que les copies sont exactes.

## Autoloads (project.godot) : `Settings`, `Net`, `Sfx`, `Progress`
Piège : dans les scripts lancés avec `-s` (tests), ces identifiants **ne compilent pas** si le script est chargé avant les autoloads → utiliser `get_node("/root/Net")`.
Les nouveaux `class_name` demandent `godot --headless --path game --import` avant d'être connus.

## Patrons à connaître
1. **Mission** = classe `MissionMxx extends MissionBase` (`game/scripts/world/`). Autorité serveur ; état dans des variables ; `state()`/`_sync()` (RPC `authority`) répliquent un dictionnaire à ~5 Hz ;
   les agents « purs état » (vaches, oies, clients, chiens) sont des tableaux de dictionnaires {x, z, vx, vz, st…} que les clients **prolongent** entre deux envois. Hooks : `setup(pois, ground, vehicle, players_root)`,
   `resolve(peer,pos)` / `interact(peer, allowed)` (action « interagir » = touche E), `hud_lines/hud_gauges/hud_markers`, `objective()`, `companion_roles()/companion_status()`, `result_text()`,
   `spawn_hint()`. Les dialogues sont déclenchés par `MissionBase._dialogue_hook` : nœuds `mxx_intro`, `mxx_<étape>`, `mxx_<done|failed>_<résultat>`.
   **Repères** : `focus_markers()` n'expose qu'une balise (la première de `hud_markers()`) + celles marquées `keep`.
2. **Monde** (`world.gd`) : construit la ville (`CityBuilder.build_city`), crée la mission (`mission_key`), les joueurs (`_spawn`, avatar « oie » en m08), les compagnons (`_spawn_companions`), le HUD, le directeur de cinématiques.
3. **Réseau** : le serveur simule tout ; le client prédit son corps (`NetBody`). Solo = serveur local (`Net.host_solo`). `--server` = serveur dédié headless. Variables d'environnement `FROUCH_PORT/HOST/MAX_PLAYERS`.
4. **Rendu** : `CityBuilder` fusionne les surfaces par matériau (un `ArrayMesh` par tuile) ; `PropKit` fusionne des primitives par couleur avec contour ; `StreetFurniture._multimesh` pose des instances.
   Les détails d'architecture dont le nom commence par « ~ » sont exclus des collisions. Mobilier de rue : collisions sur la couche 2 (les humains les heurtent, pas les véhicules ni les compagnons).
5. **Données POI** : `gis/out/poi.json` → `game/assets/city/poi.json`. Un POI avec `step` + `prop` est un lieu de mission (faisceau, libellé, accessoire) ; avec `facility`+`rect` un édifice détaillé ;
   avec `prop: carriere` la carrière ; avec `prop: rail/gare/pond` les décors de la mission 8.
6. **Sauvegarde** : `Progress` (user://saves/solo.json, conforme à `contracts/save.schema.json`) ; touches : `user://touches.cfg` ; réglages : `user://settings.cfg`.

## Décisions structurantes à ne pas défaire sans raison
Pas de binaire dans le dépôt (tout procédural) ; pas de C# ; un seul graphe routier pour l'IA ; contrats versionnés ; l'orchestrateur (agent 00) seul merge sur `main` (cette session a travaillé sur une branche de fonctionnalité et n'a jamais ouvert de PR).
