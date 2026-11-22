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
