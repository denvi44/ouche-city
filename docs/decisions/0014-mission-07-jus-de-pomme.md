# 0014 — Mission 07 « Le jus de pomme de Tonton Gégé » : une course contre son propre ventre

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 05 (gameplay), 04 (décor), 06 (compagnons), 07 (dialogues), 08 (audio)

## Contexte

Demande : un personnage a bu du jus de pomme « un peu trop fermenté » à la fête de la pomme et doit rentrer aux toilettes de chez lui, sans accident en route. Le sujet est scatologique : traitement **tendre et hors champ** (jamais montré, seulement suggéré par des onomatopées et des sous-entendus), cohérent avec « Normandie profonde : tendre, jamais méprisant ». Le joueur est la victime ; le coupable est Tonton Gégé, qui reste à son stand.

## Décisions

- **Pression** (par joueur humain, 0 → 100 %) : départ 20 %, +0,6 %/s à l'arrêt, +0,2 %/s au pas, +0,8 %/s en courant, +1,2 %/s sur les pavés au-dessus de 2,5 m/s ; crampes toutes les 9 à 13 s (+4 %), frayeur du chien (+8 %). **Serrer** (E, bascule) divise la montée par 2,5 mais plafonne la vitesse à 2 m/s (marche de crabe) et épuise une endurance (20 s) : à zéro, les muscles lâchent (+5 %, impossible de serrer pendant 3 s). À 100 % : accident, mission ratée. Temps limite 150 s.
- **Le trajet** : du stand à la porte, 150-230 m à vol d'oiseau (≈ 210 m), calculé sur le graphe routier des piétons ; les événements sont posés à des fractions du trajet. Pavés (30 %), Mme Hubert (50 %, 6 s de causette ; on peut couper court), chien du portail (78 %). **Toilettes publiques** près du milieu : on peut y faire la queue (15 s, 7 s si Kévin Radio garde la file), soulagement de 55 % et fin de mission (**bronze**) : le choix tactique contre la maison (plus loin, mais or ou argent).
- **Porte fermée à clé** : la clé est sous le pot de fleurs (5 s de recherche, immobile) ou Ginette l'a et ouvre à la volée. Arrivée : **or** si la pression ≤ 70 %, **argent** sinon.
- **Multijoueur** : chaque humain a sa pression ; la mission se termine quand tous sont arrivés (la pire pression décide de la médaille ; un seul accident = échec).
- **Lieux** (POI v9, props `pressoir` et `wc`) : stand de la fête (pressoir à vis, comptoir, gobelets, cruche au bouchon sauté, tonneaux, cageots de pommes, fanions), toilettes publiques (cabine verte, voyant « OCCUPÉ »), maison du joueur, choisis automatiquement (test). Accessoires : cageot de pommes, pressoir, cabine, pot de fleurs.
- **Compagnons** : Ginette attend à la porte avec la clé, Kévin occupe Mme Hubert (plus de causette forcée), Kévin Radio garde la file des toilettes ; Gégé reste au stand (PNJ). Chacun a un poste, tous testés.
- **Audio et texte** : gargouillis synthétisé avec l'onomatopée « GRRRBLOUP ! » ; « GLOUPS ! », « PRRRRT ! », « AAAAH ! » dans les dialogues (15 nœuds). Aucune image explicite : l'accident est un texte et un bruit.

## Conséquences

- Manquent : jauge visuelle sur le personnage (tremblements, jambes serrées), foule de la fête, intérieur de la maison (la victoire est un message), variantes de trajet (raccourci par le jardin de l'église), jus de Gégé en objet à ramasser.
- Tests : `m07_flow.gd` (rythmes de montée mesurés, serrer, endurance, crampe, causette, chien, queue, clé, or/argent, accident, temps), `m07_companions.gd`, `m07_online.sh`, lieux (Python), accessoires.
