# Ouche City

GTA-like en cel-shading, made in Normandie : une reproduction de Conches-en-Ouche (Eure), jouable seul ou à plusieurs en ligne, avec des missions « Normandie profonde ».

- **Plateformes (phase 1)** : Windows 10/11 et macOS 12+ (Apple Silicon + Intel), cross-play.
- **Moteur** : Godot 4, GDScript.
- **Production** : pilotée par une équipe d'agents IA (Claude Code), voir `CLAUDE.md` et `.claude/agents/`.

## Démarrer

1. Ouvrir le dépôt dans Claude Code : la session principale joue le chef de projet (`CLAUDE.md`).
2. Premier ticket : l'agent `cartographe` génère la rue Sainte-Foy depuis OpenStreetMap et l'IGN.
3. Chaque étape visible produit des captures d'écran (`qa/screenshots/`).

## Missions écrites

| Fichier | Mission |
| --- | --- |
| `missions/m01_calva_gege.json` | Le Calva de Tonton Gégé |
| `missions/m02_tuning_samedi.json` | Tuning du samedi soir |
| `missions/m03_battle_sono.json` | Battle de sono |

Scénarios, dialogues et règles détaillées : document « Ouche City — Plan de production ».

## Licences des données

Voir `LICENSES/ATTRIBUTIONS.md`. Personnages, commerces et marques du jeu sont fictifs.
