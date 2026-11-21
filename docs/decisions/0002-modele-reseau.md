# 0002 — Modèle réseau : serveur autoritaire, solo en serveur local

- **Date** : 2026-11-20
- **Statut** : acceptée (orchestrateur), propriétaire : agent 12

## Contexte

Règles « Réseau d'abord » et « Solo = même code » : tout état de jeu vit côté serveur, le solo lance un serveur local, jusqu'à 16 joueurs en cross-play Windows ↔ macOS.

## Décision

- **Transport** : API multijoueur de Godot sur ENet. Port par défaut 24680, surchargé par `FROUCH_PORT` / `--port=`. Hôte d'écoute : `FROUCH_HOST`. Capacité : `FROUCH_MAX_PLAYERS` (≤ 16).
- **Modes**, un seul code (`game/scripts/net/network_manager.gd`, autoload `Net`) :
  - *solo* : serveur ENet local, **fermé** (toute connexion est refusée poliment) tant que le joueur ne choisit pas « Ouvrir la partie aux amis » ; la pause ne fige le monde qu'en solo sans invité ;
  - *hôte* : serveur local ouvert ;
  - *dédié* : `godot --headless -- --server` (aucun joueur local), image Docker `server/Dockerfile` ;
  - *client* : `--join=IP[:PORT]`.
- **Poignée de main** : `PROTOCOL_VERSION` envoyé par le client ; le serveur refuse avec un message lisible si la version diffère, si la partie solo est fermée ou pleine.
- **Joueur à pied** : le client envoie ses entrées numérotées (60 Hz, non fiables ordonnées). Le serveur les simule avec le même code (`Player.simulate`) et renvoie l'état à 20 Hz avec le dernier numéro acquitté. Le client propriétaire prédit puis se réconcilie (rejeu des entrées non acquittées, écart absorbé visuellement). Les autres joueurs sont interpolés 100 ms dans le passé.
- **Monde** : le serveur crée et détruit les joueurs par RPC fiables, uniquement vers les pairs « prêts » (scène chargée). L'heure du jour est décidée par le serveur (1 Hz).
- **Anti-triche minimal** : l'expéditeur d'une entrée doit être le propriétaire du joueur ; le vecteur de déplacement est borné ; la file d'entrées est plafonnée.

## Mise à jour : corps répliqués à contrôleur variable (`NetBody`)

Le joueur et la camionnette partagent `game/scripts/net/net_body.gd` : prédiction du pilote, réconciliation par rejeu des entrées non acquittées, interpolation des autres, autorité du serveur. Le **contrôleur** d'un corps peut changer (monter / descendre) : la file de prédiction est alors remise à zéro des deux côtés, l'expéditeur d'une entrée doit être le contrôleur courant. Les entrées sont empaquetées en `PackedFloat32Array` (3 à 5 flottants). L'état de la mission (étape, cargaison, caisses, chrono, conducteur) est un dictionnaire envoyé en fiable à 4 Hz au plus, et à chaque changement ; le client prolonge le chronomètre entre deux envois.

## Conséquences

- Les zones d'intérêt par tuile (250 m), la latence simulée (150 ms, 2 % de pertes), les votes d'équipe et la reconnexion en mission restent à faire (tickets M1, agent 12).
- Test de référence : `qa/integration/two_players.sh` (serveur dédié + 2 bots).
