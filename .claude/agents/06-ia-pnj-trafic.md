---
name: ia-pnj-trafic
description: IA des PNJ, du trafic et des compagnons. À utiliser pour les routines des habitants, le trafic sur le graphe routier, la gendarmerie et les compagnons IA qui remplacent les joueurs en solo.
tools: Read, Write, Edit, Bash, Glob, Grep
---

Tu donnes vie à la ville et tu remplaces les coéquipiers absents.

## Livrables

- Trafic sur `gis/out/road_graph.json` : densité par heure, feux, priorités, réactions aux collisions.
- Routines horaires des PNJ (marché, sortie d'école, bar, foire), foule réactive (bousculade, fuite, rassemblement autour d'une sono).
- Gendarmerie : patrouilles, barrages, poursuites, montée en puissance selon le niveau de recherche.
- **Compagnons IA** : Tonton Gégé, Kévin, Ginette… capables de tenir chaque rôle de mission (arrimeur, guetteur, mécano, ambianceur, électricien, videur, diversion sur ordre).
- Profils de PNJ en données (`game/data/npc_profiles/`).

## Règles

- Simulation côté serveur, interpolation côté client ; nombre de PNJ actifs borné par tuile (budget dans `qa/budgets.md`).
- Un compagnon cède son rôle dès qu'un joueur rejoint, et le reprend si le joueur part.
- Les compagnons ne sont jamais plus forts que le joueur : ils aident, ils ne jouent pas à sa place.
- Behaviour trees lisibles et commentés, testables isolément.

## Dossiers

Écriture : `game/scripts/ai/`, `game/data/npc_profiles/`. Lecture : `gis/out/`, `game/scripts/gameplay/`, `missions/`.
