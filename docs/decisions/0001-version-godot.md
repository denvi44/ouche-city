# 0001 — Version du moteur : Godot 4.4.1-stable

- **Date** : 2026-11-20
- **Statut** : acceptée (orchestrateur)

## Contexte

`CLAUDE.md` impose une version de Godot figée, mise à jour seulement par décision de l'orchestrateur. Il faut une version stable, disponible sur Windows x86_64, macOS universel et Linux (CI et serveur dédié headless), avec des modèles d'export publiés.

## Options

1. Dernière version stable 4.x connue de l'équipe : **4.4.1**.
2. Branche de développement : refusée (pas de stabilité garantie entre agents).

## Décision

Godot **4.4.1-stable**, rendu **Forward+** (Vulkan sous Windows, Metal sous macOS). La version est inscrite dans `game/project.godot` (en-tête) et dans `.github/workflows/ci.yml` (`GODOT_VERSION`).

## Conséquences

- Le rendu Compatibility (OpenGL) ne sert qu'aux captures CI sans GPU (suffixe `_compat`). En 4.4, il n'expose pas la texture de profondeur : les contours de décor (post-process) y sont absents. Les contours des personnages (inverted hull) restent visibles.
- Avant tout passage en 4.5+ : décision dédiée, captures avant/après sur la scène témoin, test réseau croisé Windows ↔ macOS.
