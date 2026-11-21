# Frouch City

GTA-like en cel-shading, made in Normandie : une reproduction de Conches-en-Frouch (Eure), jouable seul ou à plusieurs en ligne, avec des missions « Normandie profonde ».

- **Plateformes (phase 1)** : Windows 10/11 et macOS 12+ (Apple Silicon + Intel), cross-play.
- **Moteur** : Godot 4.4.1, GDScript.
- **Production** : pilotée par une équipe d'agents IA (Claude Code), voir `CLAUDE.md` et `.claude/agents/`.

## Jouer (M0)

Ouvrir `game/` dans Godot 4.4.1, puis lancer (F5). Menu : *Jouer en solo* (mission 1), *Tuning du samedi soir* (mission 2, une fois la mission 1 terminée), *Battle de sono* (mission 3, une fois la mission 2 terminée), *Le méchoui de la Saint-Jean* (mission 4, une fois la mission 3 terminée), *Les vaches sont de sortie* (mission 5, une fois la mission 4 terminée), *Les courses de 8 h* (mission 6, une fois la mission 5 terminée), *Le jus de pomme de Tonton Gégé* (mission 7, une fois la mission 6 terminée), *Les oies font grève* (mission 8 : vous êtes l'oie meneuse et bloquez le Train des Vacances, une fois la mission 7 terminée), *Touches et souris*, *Héberger*, *Rejoindre*.

En ligne de commande :

```sh
godot --path game -- --solo                 # partie solo directe (mission 1)
godot --path game -- --solo --mission=m02   # mission 2 directement
godot --path game -- --solo --mission=m03   # mission 3 directement
godot --path game -- --solo --mission=m04   # mission 4 directement
godot --path game -- --solo --mission=m05   # mission 5 directement
godot --path game -- --solo --mission=m06   # mission 6 directement
godot --path game -- --solo --mission=m07   # mission 7 directement
godot --path game -- --solo --mission=m08   # mission 8 directement
godot --path game -- --host                 # héberger (port 24680/UDP)
godot --path game -- --join=192.168.1.20    # rejoindre
godot --headless --path game -- --server    # serveur dédié (ou : make server)
```

Contrôles : ZQSD/WASD (position physique), souris, Espace (sauter ; frein à main en voiture), Maj (sprinter ; turbo en voiture), E (interagir), H (klaxon), R (radio), 1 à 5 (choix), Échap (pause : volumes, sous-titres, ouvrir aux amis).

## Produire la ville

```sh
make gis-fetch   # télécharge IGN BD TOPO + RGE ALTI (et OSM si joignable) dans gis/cache/
make gis         # tuiles gis/out/ → copie sans retouche dans game/assets/city/
```

Le pipeline est déterministe ; la zone (rue Sainte-Foy, rayon 560 m) se règle dans `gis/config/emprise.toml`.

## Tests et captures

```sh
make test          # contrats JSON, pipeline SIG, GDScript, réseau (serveur dédié + 2 bots)
make screenshots   # captures 1920×1080 de la scène témoin (qa/screenshots/out/<date>/)
```

## Missions écrites

| Fichier | Mission |
| --- | --- |
| `missions/m01_calva_gege.json` | Le Calva de Tonton Gégé (jouable) |
| `missions/m02_tuning_samedi.json` | Tuning du samedi soir (jouable) |
| `missions/m03_battle_sono.json` | Battle de sono (jouable) |
| `missions/m04_mechoui_saint_jean.json` | Le méchoui de la Saint-Jean (jouable) |
| `missions/m05_vaches_en_goguette.json` | Les vaches sont de sortie (jouable) |
| `missions/m06_courses_de_8h.json` | Les courses de 8 h (jouable) |
| `missions/m07_jus_de_pomme.json` | Le jus de pomme de Tonton Gégé (jouable) |
| `narrative/dialogues/*.yarn` | Dialogues des six missions (voir `narrative/README.md`) |

Scénarios, dialogues et règles détaillées : document « Frouch City — Plan de production ».

## Documentation

`docs/gdd.md`, `docs/style-guide.md`, décisions dans `docs/decisions/`, budgets dans `qa/budgets.md`, contrats dans `contracts/`.

## Licences des données

Voir `LICENSES/ATTRIBUTIONS.md` : IGN BD TOPO et RGE ALTI (Licence Ouverte Etalab 2.0, « Source : IGN »), OpenStreetMap (ODbL, « © contributeurs OpenStreetMap »). Personnages, commerces et marques du jeu sont fictifs.
