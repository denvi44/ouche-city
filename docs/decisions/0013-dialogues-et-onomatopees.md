# 0013 — Dialogues et onomatopées

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 07 (narration), 05 (gameplay), 03 (rendu), 08 (audio), 11 (accessibilité)

## Contexte

Question : « y a-t-il des onomatopées pour les dialogues ? » Réponse : non, et il n'y avait pas non plus de dialogues. Le dossier `narrative/` était vide (CLAUDE.md prévoit des dialogues Yarn) ; les répliques n'existaient que comme lignes du journal de mission.

## Décisions

- **Dialogues** : sous-ensemble de Yarn lu par `YarnLite` (pas de plugin : aucune dépendance, même code sous Windows et macOS). 72 nœuds, 109 répliques pour les six missions : introduction, une réplique par étape, issues (victoire, défaite, éviction…), « aboiements » sur les événements (nid-de-poule, vache, sabotage, chien, incident de la file, pièce ratée…).
- **Non bloquant** : pas de choix ni de variables, pas de pause du monde (en ligne le monde ne peut pas s'arrêter pour une scène). Les intros sont des scènes dites par-dessus le début de la mission ; `skip: majority_vote` des JSON est respecté (touche X, vote des humains).
- **Réseau** : le serveur décide (`MissionBase.say` / `bark`) et envoie le **nom du nœud** ; chaque pair lit son exemplaire des fichiers (même build). Un joueur qui arrive en cours de route ne rejoue pas l'introduction.
- **Bulles de paroles** (`SpeechBubbles`) : panneau crème à contour sombre au-dessus du locuteur, teinté selon le personnage, avec queue ; rebond à l'apparition ; une bulle par locuteur ; la réplique reste aussi en sous-titre en bas (le texte reste lisible sans bulle). Petit marmonnement synthétisé, de hauteur variable selon le locuteur.
- **Onomatopées** (`OnomaLayer`, `Sfx.ONOMA`) : chaque son important a son texte et son ton ; l'étiquette `#onoma:` d'une réplique ajoute une onomatopée au-dessus du locuteur (HMPF, BLABLABLA, TADAAAA !…). Étoile « explosion » coloriée, texte à contour, rebond puis disparition en 1,25 s ; au plus six à l'écran et une même onomatopée toutes les 0,35 s. Elles accompagnent les sous-titres sonores : équivalent visuel des bruitages (accessibilité, checklist de l'agent 11). Deux options dans le menu pause : onomatopées, bulles.
- **Sans rendu en headless** : le journal (`Sfx.onoma_log`, `DialoguePlayer.said_ids`) reste tenu, ce qui permet de tester les dialogues et les onomatopées dans la CI.

## Conséquences

- Manquent : doublage (seulement un marmonnement), choix de réponses et variables (Yarn complet), dialogues de la foule et des passants, localisation (les identifiants stables sont prêts), cinématiques avec caméra, nœuds d'ambiance dans la ville libre.
- Les nœuds de dialogue des missions 3 à 6 sont plus courts que ceux des missions 1 et 2 ; à étoffer.
- Tests : format des fichiers, identifiants uniques, copie dans Godot, nœuds appelés existants (Python) ; lecture, saut, file, passage, onomatopées et réglages (GDScript) ; intros dans `m01_flow` et `m06_flow` ; dialogues répliqués dans `m06_online.sh`.
