# 0007 — Mission 02 « Tuning du samedi soir » : tranche jouable

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 05 (gameplay), 06 (compagnons), 12 (réseau)

## Contexte

`missions/m02_tuning_samedi.json` décrit un samedi soir en sept étapes. La mission suppose de l'argent hérité de la mission 1, quatre sources de pièces aux mécaniques différentes, un jury, et une course de 400 m contre un rival. Il fallait une tranche jouable de bout en bout, testable sans écran, qui respecte « réseau d'abord » et « chaque rôle tenable par un compagnon ».

## Décisions

- **Progression sauvegardée** (`Progress`, contrat `save.schema.json` v1) : argent, état et médaille des missions, réputation, déblocages, véhicules. Écrite par le serveur local seulement ; rien n'est écrit en headless sauf `--save=`. Le budget de la mission 2 = 400 € + gains précédents ; ce qui reste à la fin est conservé.
- **Base commune** `MissionBase` : le monde, le HUD et le réseau ne connaissent que cette interface. La mission est choisie par **le serveur** et annoncée aux clients dans la poignée de main (`--mission=m02`, ou le menu).
- **Sources de pièces** (ids du JSON) : `casse` (furtif, gratuit : jantes), `annonce` (marchandage : pot ; 40 / 60 / 80 % du prix, chance 25 / 55 / 90 %), `auto_bling_27` (toutes pièces à ×1,5), `cour_dylan` (néons volés : gratuit, « recherché » 1, `dylan_recognizes_parts`).
- **Casse** : il faut rester immobile 6 s dans la zone ; le gardien (cône de vision de 65°, 11 m, lancer de rayon contre les murs) interrompt la fouille.
- **Montage** : un mini-jeu de timing par pièce (curseur sinusoïdal, zone verte 0,38–0,62). Raté : −1 au jury (`penaltyPerFail`). Si personne n'appuie en 7 s, Kévin (compagnon mécano) le fait avec 70 % de réussite ; sans Kévin, c'est raté.
- **Essai routier** : 3 contrôles + le rendez-vous sur l'itinéraire réel (graphe routier, routes carrossables) ; un radar à 60 km/h (amende 30 €).
- **Jury** (`MissionM02.jury_scores`, fonction pure) : look = 2 + jantes 3 + néons 3 + aileron 2 ; son = 2 + pot 4 + caisson 4 ; présence = 3 + Gégé sur place 4 + pas de flash 1 + dans les temps 2 ; note = moyenne arrondie − 1 par raté − 1 si Dylan reconnaît ses pièces (0 à 10).
- **Drag** : piste de 400 m **posée par le cartographe** (couloir libre de 440 m, le plus plat, balayage déterministe : 0,4 m de dénivelé). Départ à l'arrêt, compte à rebours de 3 s, voitures retenues. Un turbo unique : lancé avant 55 % de la vitesse maximale, il casse le moteur (plafond 43 km/h). Dylan roule en ligne droite, réglé pour battre une voiture d'origine mais pas une voiture bien préparée avec un turbo bien placé (calibrage : 17,7 s d'origine, 16,6 s avec pot + jantes + aileron, 16,0 s avec turbo ; Dylan ≈ 16,5 s).
- **Médailles** : or = victoire et jury ≥ 8 ; argent = victoire ; bronze = voiture présentée. Échec seulement si 21 h passent avant la ligne de départ.
- **Compagnons** : Ginette (chineuse) va marchander l'annonce (chance +30 %), Kévin (mécano) attend au garage et monte à la place du joueur, Gégé (ambianceur) s'installe au rendez-vous (présence du jury).

## Conséquences

- Ce qui manque : cinématique d'intro, répartition des rôles entre joueurs humains (pilote / chineur / mécano / ambianceur), mini-jeux de montage variés, événements de l'essai (seul le radar est là), conduite de Dylan sur autre chose qu'une ligne droite, grande piste à plusieurs voitures.
- Le test `qa/integration/m02_flow.gd` a trouvé un vrai bug (pénalité du jury au mauvais signe) ; `m02_companions.gd` et `m02_online.sh` couvrent compagnons et réseau.
