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
| `m03_rythme/` | musique des manches de rythme de la battle de sono, **la même pour toute la mission 3** (elle doit être à 128 BPM, grosse caisse sur le premier temps) |
| `m03_musette_remix/`, `m03_techno_foraine/`, `m03_tube_ete_2003/` | une musique par playlist, utilisée seulement si `m03_rythme/` est vide |

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
| `m02/` (Tuning du samedi soir, la fusée de Dylan) | Zinzin du Tuning, puis son remix « smooth hardtech » |
| `m09/` (Le siège des Bretons) | Breton-Norman Clash (extended), tout du long |
| `m03_rythme/` (manches de rythme) | Under A Thousand Suns |
| `m05/` (Les vaches sont de sortie) | Bal des Vaches Mécaniques |
| `m08/` (Les oies font grève, le train des Parisiens) | Saloon Shuffle (remix) |

Mission 3 : aucune autre musique que celle des manches de rythme. Sans musique livrée : m04, m06, m07 (la mission garde ses sons) ; la radio du véhicule garde la valse synthétique.
Rythme de la mission 3 : les flèches sont calées sur **128 BPM** (le jeu et les boucles synthétiques). Un morceau d'un autre tempo les désynchroniserait. « Under A Thousand Suns » (`m03_rythme/`) est à 128 BPM, sa grosse caisse tombe à 0,054 s (`Sfx.RHYTHM_TRACK_OFFSET`) ; la musique démarre avec le décompte de 6 temps.
Le dossier utilisateur (`user://musique/`) passe avant les fichiers livrés dans une même catégorie : y déposer un fichier ajoute des titres à la liste.
