# 0006 — Audio : sons synthétisés par le code

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaire : agent 08

## Contexte

La fiche de l'agent 08 prévoit des fichiers Ogg (musique) et WAV (effets) dans `game/assets/audio/`, suivis par Git LFS (`.gitattributes`). Depuis l'environnement de développement, le serveur LFS de GitHub est bloqué : aucun fichier audio ne peut y être poussé. Par ailleurs, la règle de licence impose une musique 100 % originale, consignée.

## Décision

- Tous les sons sont **générés par le code** (`game/scripts/audio/synth.gd`) : 15 effets et une musique, à 22 050 Hz mono, construits à partir de tables d'ondes. Aucun fichier binaire, aucune licence tierce.
- `Sfx` (autoload) cherche d'abord `res://assets/audio/<nom>.ogg|.wav` : **un enregistrement peut remplacer n'importe quel son** sans toucher au code.
- Les paramètres de génération sont le code lui-même (une fonction par son, valeurs commentées). `audio/export_wav.gd` exporte tout en WAV pour l'écoute ou la retouche.
- Bus de mixage créés au démarrage : Effets, Musique, Ambiance, réglés dans le menu pause (et `user://settings.cfg`).
- **Accessibilité** : tout son important émet un sous-titre (`Sfx.caption`) : klaxon, choc, verre brisé, meuglement, cloches, fanfare, radio. Option « Sous-titres sonores ».
- Les moteurs (camionnette, tracteur) sont des boucles spatialisées dont la hauteur suit la vitesse ; chez les autres joueurs, la vitesse est mesurée sur le déplacement visible.
- Mode serveur / tests (headless) : aucun son joué, mais chaque demande est journalisée (`Sfx.counts`), ce qui permet de tester que le bon son suit chaque événement.

## Conséquences

- La musique (« Valse du Pommier », 8 mesures, la mineur, 132 pulsations/minute, deux anches désaccordées pour l'effet musette) est une composition originale de ce dépôt ; elle est générée en 0,3 s dans un thread à la première écoute.
- Qualité : les sons sont crédibles mais « chiptune » ; remplacer par des enregistrements reste un chantier pour M2.
- Non fait : stations de radio 2 et 3, playlists de la mission 03, basses qui font vibrer les vitres, ambiances par zone (forêt, campagne), mixage dynamique sur macOS (à vérifier sur machine réelle).
