# Frouch City — consignes projet

Open-world d'action-aventure en cel-shading, façon GTA-like, dans une reproduction de Conches-en-Frouch (Eure).
Jouable seul (compagnons IA, hors ligne) ou en ligne jusqu'à 16 joueurs (missions coop de 1 à 4).
Humour « Normandie profonde » : tendre, jamais méprisant. Tout est fictif : personnages, commerces, marques.

Plan de production de référence : document « Frouch City — Plan de production » (onglets missions 01 à 03).

## Plateformes (phase 1)

- **Windows 10/11 x86_64** et **macOS 12+ universel** (Apple Silicon + Intel). Pas de Linux, consoles ni web pour l'instant.
- Configs de référence :
  - Mac : Apple Silicon M1, 8 Go de RAM → 1080p, 60 FPS, réglages « Moyen ».
  - PC : GPU classe GTX 1060 / RX 580, 8 Go → 1080p, 60 FPS, réglages « Moyen ».
- Le cross-play PC ↔ Mac est obligatoire : même build serveur, même protocole.
- Tout chemin de fichier passe par `user://` ou `res://` (jamais de chemin absolu, attention à la casse : macOS est insensible, la CI Linux ne l'est pas).
- Entrées : clavier/souris et manette (XInput sur PC, manettes MFi/PlayStation/Xbox sur Mac). Pas de raccourci réservé au système (Cmd+Q, Cmd+H…).

## Stack

| Couche | Choix |
| --- | --- |
| Moteur | Godot 4 (version figée dans `game/project.godot`, mise à jour uniquement par décision de l'orchestrateur) |
| Langage | GDScript uniquement (pas de C# : un seul outillage sur les deux OS) |
| Rendu | Forward+ (Vulkan sur Windows, Metal/MoltenVK sur macOS) |
| Réseau | API multijoueur Godot sur ENet, serveur dédié autoritaire |
| SIG | Python 3 : osmnx, GDAL, shapely |
| 3D | Blender headless (bpy) + Geometry Nodes, export glTF 2.0 |
| Lobby / comptes | FastAPI + PostgreSQL, en Docker |
| CI | GitHub Actions : runner Linux (tests, serveur), runner macOS (build + signature + notarisation), runner Windows (build) |

## Arborescence

```
CLAUDE.md
.claude/agents/        fiches des agents (une par rôle)
contracts/             schémas JSON versionnés (tile, poi, mission, save) — source de vérité entre agents
docs/                  GDD, style guide, décisions (docs/decisions/NNNN-titre.md)
gis/                   pipeline données ouvertes → tuiles (Python)
blender/               scripts bpy, kits modulaires, règles de génération
game/                  projet Godot
  scenes/ scripts/ shaders/ assets/ ui/
  scripts/net/         couche réseau (agent 12 uniquement)
missions/              données de mission JSON (m01_…, m02_…)
narrative/             dialogues (Yarn) et bibles de personnages
audio/                 sources audio et banques
server/                lobby, comptes, Dockerfile du serveur de jeu
qa/                    tests, bots, rapports de perf
LICENSES/ATTRIBUTIONS.md
```

## Rôle de la session principale : chef de projet (orchestrateur)

La session principale joue l'agent 00. Elle :

1. découpe le travail en tickets (GitHub Issues, un label par agent `agent:01-cartographe`…) ;
2. délègue chaque ticket au sous-agent concerné, avec le contrat JSON et la Definition of Done ;
3. relit chaque PR, lance la CI, merge — **personne d'autre ne merge sur `main`** ;
4. tranche les conflits entre agents et consigne la décision dans `docs/decisions/`.

## Règles communes à tous les agents

- **Périmètre** : un agent n'écrit que dans ses dossiers (voir sa fiche). Besoin d'un changement ailleurs → ticket pour l'agent propriétaire.
- **Contrats** : toute donnée échangée suit un schéma de `contracts/`. Modifier un schéma = PR dédiée, numéro de version incrémenté, validée par l'orchestrateur.
- **Branches** : `agent/<numéro>-<sujet>` ; commits courts en français ; une PR par ticket.
- **Réseau d'abord** : aucun système de gameplay n'est écrit « solo puis porté ». Tout état de jeu vit côté serveur ; le client prédit et affiche.
- **Solo = même code** : le client lance le serveur en local pour le solo. Chaque rôle de mission doit pouvoir être tenu par un compagnon IA.
- **Fiction** : aucun nom de personne, d'enseigne ou de marque réels ; aucun asset, logo, police ou élément d'interface repris de GTA ou d'un autre jeu.
- **Données ouvertes** : toute donnée OSM ou IGN ajoutée est déclarée dans `LICENSES/ATTRIBUTIONS.md` (© contributeurs OpenStreetMap, ODbL ; IGN, Licence Ouverte Etalab 2.0).
- **Accessibilité** : toute UI respecte la checklist de l'agent 11 (sous-titres, remappage, tailles, daltonisme).
- **Les deux OS** : une fonctionnalité n'est « finie » que si elle tourne sur Windows et sur macOS en CI.

## Definition of Done

- [ ] Tests passent (`qa/`), build verte sur Windows et macOS
- [ ] Testé en solo (serveur local) et à 2 joueurs en ligne
- [ ] Visible dans la scène témoin (`game/scenes/temoin_rue_sainte_foy.tscn`) quand c'est pertinent
- [ ] Conforme au style guide (`docs/style-guide.md`) et au contrat JSON concerné
- [ ] Budget perf respecté (voir `qa/budgets.md`)
- [ ] Captures d'écran jointes à la PR pour tout changement visible (Windows + macOS, générées par `qa/screenshots/`)

## Captures d'écran

Dès qu'une chose se voit, on la capture. Chaque PR qui touche la carte, les assets, les shaders, l'UI ou une mission joint ses captures ; chaque nightly publie la galerie complète (`qa/screenshots/out/<date>/`) ; chaque rapport de sprint de l'orchestrateur commence par 3 captures « avant / après ».

## Jalon en cours

M0 — Préproduction : GDD, style guide, agents configurés, POC carto de la rue Sainte-Foy générée automatiquement et importée dans Godot, première build Windows + macOS d'une scène vide signée.

## Reprise par une autre IA

Voir `docs/reprise/README.md` (état des lieux, architecture, commandes, backlog priorisé, recettes).
