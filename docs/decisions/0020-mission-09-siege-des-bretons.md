# 0020 — Mission 9 « Le siège des Bretons » (chapitre bonus)

**Contexte** : le propriétaire du projet demande une mission où l'on défend le village contre des Bretons en ciré jaune qui lancent du beurre salé : dix camemberts à charger dans une catapulte dans le temps imparti, puis une cinématique des dégâts (fumée verte et jaunâtre) où ils fuient sous la pluie.
**Décisions** :
- Identifiant `m09_siege_des_bretons`, chapitre bonus après la mission 8 (qui garde son épilogue de « fin de saison » ; la 8 débloque la 9). Héros : Kévin.
- POI v15 (`catapulte` avec le nouvel accessoire `catapult`, trois étals `stock_fromage_N`, `debarquement_bretons`) générés par `gis/fiction.lieux_mission09` en terrain dégagé ; cinématique schéma v3 : nouveau moment `launch` (joué par `CinematicDirector` quand l'étape passe à « launch »).
- Autorité serveur : camemberts portés/chargés, temps restant, étape. Les Bretons, le beurre lancé et les flaques de beurre sont **déterministes** (fonctions pures de `elapsed`, `MissionM09.shot_*`, `slick_*`, `breton_pos`) : aucun paquet par projectile. Seule conséquence de jeu : la vitesse maximale (`speed_cap`) dans une flaque.
- Effets locaux : pluie (`RainFx`), fumée (`SiegeSmoke`), brouillard ; absents en headless.
- Musique : `game/assets/musique_perso/m09` (Breton-Norman Clash). Mission 3 : plus aucune musique hors manches de rythme.
**Garde-fous** : tout est fictif ; les « Bretons » sont des caricatures tendres (cirés jaunes, beurre salé), jamais méprisantes.
