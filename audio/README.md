# Audio d'Ouche City

Tous les sons sont synthétisés par le code (voir `docs/decisions/0006-audio-synthetise.md`).

| Son | Fonction `Synth` | Déclencheur | Sous-titre |
| --- | --- | --- | --- |
| Klaxon (sol4 + si4, deux coups) | `klaxon` | touche H, partagé avec tous les joueurs | [Klaxon] |
| Moteur de la camionnette | `engine_loop` | boucle tant qu'il y a un conducteur, hauteur = vitesse | — |
| Tracteur « teuf-teuf » | `tractor_loop` | boucle tant que le tracteur roule | — |
| Choc de nid-de-poule | `thud` | `jolt_serial` de la mission | [Choc dans un nid-de-poule] |
| Bouteille cassée | `glass` | compteur de bouteilles cassées | [Verre brisé] |
| Caisse | `crate` | prise d'une caisse | — |
| Carillon | `chime` | chargement validé, livraison sans médaille | — |
| Meuglement | `moo` | vaches actives (toutes les 6 à 11 s) ou klaxon | [Meuglement] |
| Échec | `fail` | mission échouée | [Échec] |
| Fanfare | `fanfare` | médaille obtenue | [Fanfare de victoire] |
| Pas | `step` | à chaque pas du joueur local | — |
| Bip de radio | `radio_blip` | message de Kévin Radio | [Radio : Kévin Radio parle] |
| Cloches | `bell` | à chaque heure de jeu (8 h à 20 h), près de l'église | [Cloches de l'église] |
| Vent | `wind_loop` | boucle d'ambiance | — |
| Oiseaux | `bird` | le jour, toutes les 6 à 14 s | — |
| Valse du Pommier | `music_pommier` | radio de la camionnette (touche R) | [Radio Pommiers : valse musette] |

## Écouter / retravailler

```sh
godot --headless --path game -s ../audio/export_wav.gd -- --out=/tmp/ouche-audio
```

Remplacer un son : déposer `game/assets/audio/<nom>.ogg` (ou `.wav`) ; `Sfx.stream_for` le prend à la place de la synthèse.

## « Valse du Pommier »

Composition originale, la mineur, valse musette à 132 pulsations par minute, 8 mesures bouclées : basse sur le premier temps, accords plaqués sur les deux autres (Am, Dm, E, Am, Am, Dm, E, Am), mélodie à l'anche double désaccordée de 0,6 %.
