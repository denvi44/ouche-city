# 05 — Les missions (étapes, fichiers, réglages, limites)

Gabarit commun : `missions/mXX_*.json` (titre, `requires`, rôles, compagnons, étapes, médailles, récompenses, paramètres) ; `game/scripts/world/mission_mXX.gd` ; `narrative/dialogues/mXX_*.yarn` ;
`narrative/cinematics/mXX_{intro,done,failed}.json` ; tests `qa/integration/mXX_{flow,companions}.gd` + `mXX_online.sh` ; décision `docs/decisions/00NN-*.md`. Chaîne de déblocage : m01 → m02 → … → m08 (`rewards.unlocks`).
Les temps ci-dessous sont les **limites** et les résultats des bots de `qa/feasibility/audit.gd`.

| # | Mission | Étapes (état `step`) | Compagnons | Limite / résultat bot | À savoir |
| --- | --- | --- | --- | --- | --- |
| 1 | Le Calva de Tonton Gégé | `crates` (cave → poulailler → grange → fumier, une balise à la fois), `road` (conduite avec nids-de-poule, tracteur, vaches), `checkpoint` (barrage : bluff/diversion), `fair` (stand) | Gégé arrimeur, Ginette négociatrice, Kévin Radio guetteur, Kévin diversion | 1110 s / 746 s | Cargaison fragile (bouteilles), police gendarmes ; la camionnette ne doit pas être bloquée par du mobilier (couche 2) |
| 2 | Tuning du samedi soir | `parts` (casse → annonce → magasin, ou garage si assez de pièces), `assembly`, `test_drive`, `meet` (jury), `drag` | Ginette chineuse, Kévin mécano, Gégé ambianceur | 720 s / 437 s | Voiture `Car` ; piste de drag cherchée sur le terrain le plus plat |
| 3 | Battle de sono | `setup` (3 objets), `round` ×3 (rythme, sabotages, gendarmes), fin | Kévin électricien, Ginette videur, Gégé saboteur | 297 s de mise en place / rythme 100 % | Mini-jeu de rythme ; nuisance sonore ; 3 manches |
| 4 | Méchoui de la Saint-Jean | `gather` (agneau, broche, charbon), `fire`, `serve` (4 tables), `bonfire` | Gégé cuisinier, Ginette gardienne, Kévin serveur | 570 s / 335 s | Chiens qui volent les gigots, cuisson à surveiller |
| 5 | Les vaches sont de sortie | `herd` (8 vaches, sifflet), `gate` | Kévin rabatteur, Ginette guetteuse, Gégé barrière | 480 s / ≈ 402 s | Agents « purs état » répliqués ; Kévin garde sa vache et vise les retardataires si un humain est actif |
| 6 | Les courses de 8 h | `shop` (liste, 2 km/h), `pay` (file + mini-jeu de pièces), `exit` | Ginette bavarde, Gégé caddie | 540 s / or en 236 s | Vitesse plafonnée (`Player.speed_cap`), clients qui s'impatientent, éviction |
| 7 | Le jus de pomme | `run` (pression qui monte), `door`, fin (accident, toilettes publiques, chez soi) | Ginette portier, Kévin diversion, Kévin Radio file | 150 s | Serrer (E), endurance, Mme Hubert, chien, clé sous le pot ; **nuages de fumée** et sons (`smoke_puff.gd`) |
| 8 | Les oies font grève | `gather` (HONK ! rassemble les oies de la mare), `block` (tenir la voie 30 s) | Kévin rabatteuse, Ginette sentinelle, Gégé ferme-file | 480 s / argent en 145 s | Joueur = oie (`goose_model.gd`) ; le train freine toujours ; garde-barrière ; gare et voyageurs ; spawn près de la mare (`spawn_hint`) |

## Réglages (où tourner les boutons)
JSON de mission (durées, seuils de médailles, nombre d'agents) en priorité, puis les constantes en tête de `mission_mXX.gd`. Après un réglage : relancer le flow et `qa/feasibility/audit.gd --only=mXX --companions`.
Exemples : m05 `timeLimitSec` 480 ; m06 mini-jeu `MINI_SPEED` 0,8 et zone 0,36-0,64 ; m07 `GOLD_PRESSURE` 0,75, serrer 0,3 ×/2,5 m/s ; m08 `holdSec` 30, `minBlockers` 5, `delaySec` du garde-barrière 8.

## Limites connues par mission
m01 : le bot de conduite ne sait pas faire demi-tour (pas de test de conduite sur les rues de vallée). m02-m03 : pas de vraie IA de pilotage adverse (Dylan suit un script). m04 : pas de météo.
m06 : intérieur du supermarché seulement. m07 : humour scatologique volontairement hors champ (onomatopées, fumée). m08 : voyageurs immobiles, pas de passage à niveau routier ni de barrières animées.
Toutes : pas de voix, pas d'animations de scène ; cinématiques = caméra + légendes.
