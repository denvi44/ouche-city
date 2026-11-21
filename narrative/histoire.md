# L'histoire de Frouch City — saison 1 : « Le Label »

Un seul fil rouge pour les huit missions : **l'inspectrice Hautefeuille**, du *Label Village Enchanté*, visite Conches-en-Frouch **vendredi à 17 h 42**, en descendant du Train des Vacances. Le village a **six jours** pour lui prouver qu'il est vivant. Chaque mission est une « épreuve » involontaire du Label, et chaque réussite fait gagner la réputation d'un quartier (`rewards.reputation`).

| Jour | Mission | Épreuve (réputation) | Ce qui se passe | Ce qui relance la suite (scène « à suivre ») |
| --- | --- | --- | --- | --- |
| Sam. 17 h | 1 · Le Calva de Tonton Gégé | Tradition (Comité des fêtes) | Livrer le calva à la foire sans en casser une bouteille. | Flash de Radio Pommiers : l'inspectrice vient vendredi. La Fusée de Kévin est en pièces, Dylan ricane. |
| Sam. 19 h | 2 · Tuning du samedi soir | Jeunesse | Retaper la Fusée et battre Dylan au drag de 400 m. | Dylan promet que le Clos Fleuri coupera le son demain. |
| Dim. 14 h | 3 · Battle de sono | Musique (Pommiers) | Gagner la battle de sono contre le Clos Fleuri (le caisson de la Fusée sert). | L'inspectrice aime la table : le Comité propose un méchoui. |
| Lun. 18 h | 4 · Le méchoui de la Saint-Jean | Table (Comité des fêtes) | Agneau, feu, chiens errants, huit assiettes. | L'odeur du méchoui attire les vaches de Mémé Odette. |
| Mar. 4 h | 5 · Les vaches sont de sortie | Campagne | Rabattre huit vaches (dont Marguerite) dans l'enclos. | Mémé Odette offre un camembert qui marche tout seul ; il faut des courses pour le banquet. |
| Mar. 8 h | 6 · Les courses de 8 h | Troisième âge | Faire les courses à 2 km/h au Panier de Frouch. | Pour fêter ça, la cuvée spéciale de Gégé. |
| Mer. 16 h | 7 · Le jus de pomme de Tonton Gégé | Convivialité (Comité des fêtes) | Rentrer aux toilettes à temps (humour hors champ). | Radio Pommiers : le train arrive, les oies ont un projet. |
| Ven. 17 h | 8 · Les oies font grève | Accueil (campagne) | Devenir l'oie meneuse et bloquer le train des Parisiens. | **Épilogue** : l'inspectrice décerne le Label « à l'unanimité des oies ». |

## Les personnages
- **Le héros change selon la mission** (champ `hero` de `missions/*.json`, contrat v2 ; `Heroes`, `game/scripts/core/heroes.gd`). Le joueur prend le nom et la tenue du personnage, et son compagnon IA disparaît (c'est lui) :
  m01 Tonton Gégé · m02 Kévin · m03 Kévin Radio · m04 Ginette · m05 Mémé Odette · m06 Tonton Gégé · m07 Kévin · m08 Mémé Odette (sous la forme d'une oie).
  En ligne, le premier joueur (hôte) incarne le héros ; les autres gardent leur nom et un personnage ordinaire (rôles de mission). Absent en headless (tests, serveur dédié). Test : `qa/integration/hero_audit.gd`.
- Avant : « Vous » était la nouvelle recrue (le nom choisi sur l'écran titre) ; ce nom ne sert plus qu'aux joueurs en ligne autres que l'hôte.
- **Tonton Gégé** (calva, arrimeur, cuisinier, ferme-file), **Ginette** (négociatrice, chineuse, videuse, guetteuse), **Kévin** (mécano, diversion, rabatteur), **Kévin Radio** (speaker de Radio Pommiers, guetteur) : les quatre « héros » du village. En solo ils tiennent les rôles que les joueurs ne prennent pas (compagnons IA) ; en ligne, les joueurs humains prennent ces rôles à tour de rôle (1 à 4 par mission, `roles` des JSON de mission).
- **Seconds rôles** : Dylan (rival), Mémé Odette (fermière, les oies), Mme Hubert, Josette (Panier de Frouch), l'adjudant Lemoine (gendarmerie), Marguerite (la vache), **l'inspectrice Hautefeuille** (fil rouge, apparaît dans l'épilogue).

## Comment les scènes s'enchaînent (`contracts/cinematic.schema.json` v2)
1. `mNN_intro` : carton de titre (jour et lieu) puis plans de présentation, au démarrage.
2. `mNN_done` / `mNN_failed` : conclusion immédiate de la mission.
3. **`mNN_bridge`** (missions 1 à 7, après une réussite) : trois plans de liaison et un carton « À suivre… · Chapitre N+1 · titre », qui pose la suite. Peut ancrer ses plans sur les lieux de la mission suivante.
4. **`m08_epilogue`** (après la réussite de la mission 8) : fin de la saison, quatre plans, carton « Frouch City ».
Chaque joueur voit chaque scène une fois par partie ; X (ou Retour) la passe ; elles sont désactivables (option « Cinématiques »).

## Règles pour prolonger l'histoire
- Garder le fil : toute nouvelle mission est une épreuve du Label (ou une conséquence de l'une d'elles) et commence par une scène `bridge` de la précédente.
- Une mission ratée ne fait pas avancer l'histoire : la scène « à suivre » ne se joue qu'après une réussite.
- Humour tendre, jamais méprisant ; aucun nom réel ; « Hautefeuille », « Frouch », « Pommiers », « Clos Fleuri » sont fictifs.
