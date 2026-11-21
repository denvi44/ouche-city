# 0010 — Mission 05 « Les vaches sont de sortie » : rabattage d'un troupeau

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 05 (gameplay), 04 (accessoires), 06 (compagnons), 08 (audio)

## Contexte

Aucune mission 05 n'était écrite : celle-ci est nouvelle (`missions/m05_vaches_en_goguette.json`, débloquée par la mission 4). Elle introduit une mécanique qui manquait : **diriger des agents autonomes** plutôt que manipuler des objets ou jouer un rythme.

## Décisions

- **Scénario** : à quatre heures du matin la barrière de Mémé Odette est restée ouverte ; huit vaches normandes (Marguerite, Noiraude, Pâquerette, Biscotte, Cunégonde, Ficelle, Rosalie, Tulipe — noms fictifs) sont dans le pré. Rôles : berger (le joueur), rabatteur (Kévin), guetteur (Ginette), barrière (Gégé).
- **Lieux** (POI v7, prop `pen`) : l'enclos (12 × 12 m, ouvert vers le pré, auge et foin au fond) et le pré (disque dégagé de 25 m) sont cherchés **en terrain libre**, à 80-140 m l'un de l'autre, reliés par un couloir de 10 m sans bâtiment (test `test_lieux_de_mission05`). L'ancrage de l'enclos sur un bâtiment avait été essayé : le village est trop dense, aucun emplacement n'était libre.
- **Troupeau en état pur** (comme les chiens de la mission 4), pas en corps physiques répliqués : positions et vitesses simulées par le serveur, envoyées à 5 Hz, prolongées par les clients entre deux envois. Peu coûteux et sans conflit de collisions.
- **Comportement** : chaque vache fuit toute personne à moins de 10 m (joueurs et compagnons, force décroissante avec la distance), plus vite sous pression (1,1 → 4,2 m/s) ; sans pression elle broute (0,35 m/s) en restant près du troupeau. Marguerite fuit 1,4 fois plus vite et 1,3 fois plus loin. Un **sifflet** (3 s de délai) ajoute une source de peur de 16 m pendant 1,4 s.
- **Obstacles** : les vaches glissent contre les bâtiments (contours de la carte) et la clôture ; la porte (4,4 m) est ouverte tant que la barrière n'est pas fermée.
- **Fin** : huit vaches dedans → il faut fermer la barrière (le joueur, ou Gégé après 2 s à son poste). Temps limite de 300 s : à l'échéance, le bilan est fait avec ce qui est rentré. Or = 8, argent = 6, bronze = 4 vaches ; moins : défaite sans médaille.
- **Compagnons** : Kévin se place derrière la vache libre la plus proche de l'enclos (côté opposé) et siffle ; seul, il rentre les huit en environ 6 minutes (le joueur doit donc l'aider pour tenir 5 minutes). Gégé et Ginette se tiennent **sur le côté** de la porte (13 m) : placés devant, ils effrayaient les vaches qui entraient (défaut trouvé par `m05_companions.gd`). Ginette décrit la vache libre la plus proche (distance et cap).
- **Accessoires** : vache normande (blanche tachetée de brun, pis, cornes, étiquettes ; Marguerite plus sombre, avec sa cloche), enclos, vantail de porte (qui s'anime : ouvert / fermé).
- **Audio** : sifflet de berger synthétisé (sous-titré), meuglement et carillon à chaque vache rentrée.

## Conséquences

- Manquent : cinématiques, obstacles de route (tracteur, chiens), vaches qui se bousculent entre elles, traite, rôles distincts entre joueurs humains.
- Le test d'intégration `m05_flow.gd` rentre les huit vaches en se plaçant derrière elles (≈ 4 minutes de jeu simulées) ; `m05_companions.gd` laisse Kévin faire seul ; `m05_online.sh` vérifie la mission imposée par le serveur.
