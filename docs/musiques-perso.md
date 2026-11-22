# Musiques personnalisées

Le jeu lit vos fichiers **mp3, ogg ou wav** sans reconstruction : on les dépose dans un dossier, un sous-dossier par usage.

## Où les mettre

Dans le menu principal ou le menu pause : **« Mes musiques (ouvrir le dossier) »** crée le dossier (avec un mode d'emploi) et l'ouvre.
Chemin réel : `~/Library/Application Support/Godot/app_userdata/<nom du jeu>/musique/` sur Mac, `%APPDATA%\Godot\app_userdata\<nom du jeu>\musique\` sous Windows.

| Sous-dossier | Usage |
| --- | --- |
| `radio/` | radio du véhicule : **R** marche/arrêt, **T** (RB sur manette) titre suivant ; les titres s'enchaînent |
| `titre/` | écran titre |
| `m01/` … `m08/` | musique d'ambiance de la mission (se tait pendant la radio et la battle de sono) |
| `m03_musette_remix/`, `m03_techno_foraine/`, `m03_tube_ete_2003/` | remplace la boucle synthétique de chaque playlist de la battle de sono (le 1er fichier tourne en boucle ; le rythme des flèches reste calé sur 120 BPM) |

Les titres passent dans l'ordre alphabétique (préfixez `01_`, `02_`…). Un fichier illisible est ignoré. Pas de fichier = musique d'origine du jeu.
Réglage : « Musiques personnalisées » dans le menu pause (désactive tout d'un coup).

## Fichiers livrés avec le jeu

On peut aussi placer des fichiers dans `game/assets/musique_perso/<sous-dossier>/` (même structure) : ils sont importés par Godot et inclus dans les builds. Ne les versionnez **que** si vous avez les droits de diffusion (voir `LICENSES/ATTRIBUTIONS.md`) ; sinon gardez-les dans le dossier utilisateur.

## Technique

`game/scripts/audio/music_library.gd` (recherche, titres, chargement) ; `Sfx.play_mission_music`, `Sfx.set_radio`, `Sfx.radio_next` (`sfx.gd`). Tests : `qa/unit/run_gdscript_tests.gd` (mp3 réel dans `qa/unit/data/test.mp3`).

## Musiques livrées avec le jeu (état actuel)

| Dossier | Morceau |
| --- | --- |
| `titre/` | Pulse de Normandie |
| `m01/` (Le Calva de Tonton Gégé) | Fête de la Moisson |
| `m02/` (Tuning du samedi soir, la fusée de Dylan) | Zinzin du Tuning |
| `m03/` (Battle de sono) | Breton-Norman Clash (extended), puis Zinzin du Tuning (smooth hardtech remix) |
| `m05/` (Les vaches sont de sortie) | Bal des Vaches Mécaniques |
| `m08/` (Les oies font grève, le train des Parisiens) | Saloon Shuffle (remix) |

Sans musique livrée : m04, m06, m07 (la mission garde ses sons) ; la radio du véhicule garde la valse synthétique.
Les playlists de rythme de la mission 3 (`m03_*`) restent synthétiques : les flèches sont calées sur 120 BPM, un morceau au tempo différent les désynchroniserait.
Le dossier utilisateur (`user://musique/`) passe avant les fichiers livrés dans une même catégorie : y déposer un fichier ajoute des titres à la liste.
