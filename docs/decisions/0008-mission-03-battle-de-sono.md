# 0008 — Mission 03 « Battle de sono » : tranche jouable

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 05 (gameplay), 06 (compagnons), 08 (audio), 12 (réseau)

## Contexte

`missions/m03_battle_sono.json` oppose le lotissement des Pommiers au Clos Fleuri : rassembler la sono, trois manches de rythme, des sabotages, la gendarmerie, une médaille. Contrairement aux missions 1 et 2, il n'y a pas de véhicule : la mission se joue à pied, autour d'une scène.

## Décisions

- **Lieux** (`gis/fiction.py`, POI v5, prop `stage`) : sono des Pommiers (maison à 70-220 m de l'apparition), sono du Clos Fleuri (à plus de 220 m), trois objets (caisson, rallonge, groupe) chez des voisins à 80-300 m. Noms fictifs, posés sur la vraie carte.
- **Rythme** : 120 pulsations par minute (une grosse caisse toutes les 0,5 s, `Synth.track`). Un appui sur « interagir » à moins de 14 m de la sono est jugé **côté serveur** : parfait à ±0,07 s (3 points), bon à ±0,15 s (1 point), sinon raté ; un temps ne compte qu'une fois. Manches de 32, 40 et 40 temps ; la dernière double les 8 derniers temps (« lâcher de basses »).
- **Public** : le rival vise un public par manche (jeunes, tous, anciens). Jouer pour un autre public que le sien vaut ×1,2 ; le tube de l'été (« tous ») ×0,7 ; la techno augmente la nuisance de 30 %.
- **Rival** : sa progression suit le temps, vers un objectif de 55 / 62 / 68 % du maximum de la manche. Manche gagnée = points du joueur ≥ objectif.
- **Sabotages** (2 en solo, 4 en coop, manche 2 seulement) : câble débranché (son coupé 4 s), clé USB d'accordéon (points ÷2 pendant 6 s), poules (−6 points). Chacun se déjoue en 6 s en allant à son emplacement (« interagir »). Il faut quitter le pupitre : c'est le dilemme de la manche.
- **Nuisance** : monte avec la musique et chaque temps réussi (×0,75 en solo) ; à 70 %, appel aux gendarmes (barbecue −35 %, accuser le Clos Fleuri 50 % de −50 % / +15 %, merguez −25 % et +3 points ; sans réponse en 12 s : +10 %) ; à 100 %, sono saisie. Lemoine arrive après 90 s de musique (+8 %, sauf si Ginette tient les portes).
- **Médailles** : or = 3 manches et pas de gendarmes ; argent = 3 manches ; bronze = 2 manches ; moins : défaite. Matériel non rassemblé en 5 min : échec.
- **Compagnons** (solo) : chacun rapporte d'abord son objet (Kévin le caisson, Ginette la rallonge, Gégé le groupe), puis tient un poste devant la scène. Gégé électricien rebranche le câble seul ; Ginette videur ajoute 8 % du maximum à chaque manche et retient Lemoine ; Kévin saboteur retire 12 % à l'objectif du rival depuis le camp adverse. Le joueur reste DJ.
- **Audio** : trois playlists synthétisées (musette remixée, techno foraine, tube 2003), boucles de 8 s ; compte à rebours de 6 temps pour que la boucle reste alignée sur les temps. Sous-titres sonores pour chaque playlist. Les enceintes de la scène pulsent sur le temps.

## Conséquences

- Ce qui manque : cinématique d'intro et d'épilogue, répartition des rôles entre joueurs humains (DJ, saboteur, électricien, videur : en ligne, tous peuvent jouer le beat), DJ IA quand aucun humain ne tient le pupitre, foule visible, vrai public, radio débloquée en récompense, objet « sono portable ».
- En ligne, le jugement du rythme se fait à l'arrivée du message : la latence se paie en précision (fenêtre « bon » de 0,15 s ; pas de compensation côté serveur).
- Tests : `m03_flow.gd` (parcours complet et trois fins ratées), `m03_companions.gd`, `m03_online.sh`, tests unitaires des playlists et des fenêtres de timing.
