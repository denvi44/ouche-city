# 0012 — Mission 06 « Les courses de 8 h » : la lenteur comme mécanique

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 05 (gameplay), 04 (décor), 06 (compagnons), 08 (audio)

## Contexte

Demande : faire les courses à 8 h au supermarché, mais à 2 à l'heure, « comme les petits vieux qui embêtent tout le monde ». Aucune mission de ce type n'existait. Ton du projet : tendre, jamais méprisant : le joueur incarne l'acheteur lent et son point de vue (lire les étiquettes, compter la monnaie, bavarder) est le sujet du gag ; les autres clients sont pressés, pas méchants.

## Décisions

- **Mécanique centrale** : `Player.speed_cap` (m/s) plafonne la vitesse, **sprint compris** ; la mission le règle à 2 km/h (0,556 m/s) pour tous les acheteurs, humains et compagnons, **sur tous les pairs** (la prédiction client applique le même plafond). Il tombe à zéro pendant la lecture d'une étiquette (3 s), la causette, le « pas de côté » et le paiement. Test : sprint enfoncé pendant 2 s → 0,56 m/s au maximum.
- **Lieu** (POI v8, prop `supermarket`) : « Supermarché Le Panier de Frouch » (nom fictif), emprise de 26 × 18 m en terrain libre, la plus plate possible, à 60-220 m de l'apparition, **porte tournée vers la route la plus proche** (test). Le magasin est un décor sans toit (la caméra voit l'intérieur d'en haut), avec collisions (murs, gondoles, comptoirs) ; son sol est relevé au point le plus haut du terrain (`Supermarket.lift_for`) pour ne pas être enterré.
- **Intérieur** : trois rangées de gondoles (modules de 6 m, produits de couleurs variées), meuble réfrigéré, comptoir de boulangerie, deux caisses, chariots, enseigne. Accessoires de `PropKit` (shelf, fridge, bakery, checkout, caddie, super_sign).
- **Déroulé** : liste de six articles (baguette, camembert, lait, cidre, palets, litière) à lire et prendre ; payer en comptant la monnaie (4 pièces, curseur lent, une pièce ratée = +8 s) ; sortir par la porte automatique.
- **Horloge** : 8 h 00 au départ, 1 minute de jeu = 6 s. Or avant 8 h 50 avec au plus un incident, argent avant 9 h, bronze avant 9 h 30 ; au-delà, le magasin ferme pour la pause. Les incidents et les pièces ratées ajoutent des secondes au chrono.
- **Clients pressés** (état pur, répliqué à 5 Hz) : un toutes les 14 s sur deux parcours dans les allées (1,5 m/s). Un client **bloqué** (joueur, autre client ou compagnon en mouvement à moins de 1,7 m devant lui) perd patience (12 s pour 100 %). À 100 % : **incident** (« Dites donc, vous allez bouger ?! », +6 s). Au quatrième, le gérant raccompagne dehors (échec). **« Après vous ! »** (E) : pas de côté de 1,2 s, la file passe pendant 3,5 s, impatience −50 %, un point de politesse.
- **Mme Hubert** : retient le joueur 8 s une seule fois (il peut couper court : −1,5 s par appui). Si Ginette est déjà en train de papoter avec elle, elle ne retient personne.
- **Compagnons** : Gégé va chercher les palets et le cidre à 2 à l'heure par les allées (parcours fixes, reprise au point le plus proche) ; Ginette papote avec Mme Hubert ; Kévin attend au volant. Un compagnon **immobile** ne bloque pas les clients (défaut trouvé par `m06_companions.gd` : Ginette, plantée dans l'allée, faisait évincer le joueur en 90 s).
- **Audio** : bip de scanner, tintement de pièce, soupir agacé (tous sous-titrés sauf la pièce).

## Conséquences

- Manquent : cinématiques, vrais PNJ du magasin (caissière et Mme Hubert sont immobiles), produits individuels cueillis dans les rayons (la prise est abstraite), caddie physique, autres commerces avec intérieur, rôles distincts entre joueurs humains en ligne (tous les joueurs sont des acheteurs lents).
- Tests : `m06_flow.gd` (plafond, lecture, causette, blocage, « Après vous », incident, caisse, sortie, éviction, pause), `m06_companions.gd`, `m06_online.sh`, plan du magasin (articles et parcours hors des gondoles), accessoires du magasin.
