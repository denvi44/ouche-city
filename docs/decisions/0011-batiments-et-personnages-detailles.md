# 0011 — Bâtiments et personnages détaillés

- **Date** : 2026-11-21
- **Statut** : acceptée (orchestrateur), propriétaires : agents 04 (assets), 03 (rendu), 05 (personnages)

## Contexte

Le bâti était des volumes extrudés (murs peints par shader, toit à deux pans) et les personnages des capsules avec un béret. Pas de Blender ici et Git LFS est bloqué : le détail est généré par le code, comme les accessoires de la décision 0009.

## Décisions — bâtiments (`BuildingDetails`)

- **Cheminées** sur le faîtage (une ou deux selon la graine et la longueur) : fût de brique, chapeau de pierre, deux boisseaux de zinc.
- **Lucarnes** sur les grands toits à étage : jouées de crépi, fenêtre à cadre de bois, vitre et meneau, fronton triangulaire et petit toit à deux pans. Jamais sur un commerce, une annexe ou un toit trop peu profond.
- **Corniche** sous l'égout (bois pour les colombages, pierre sinon) et **soubassement** de pierre de 55 cm.
- **Porte** : auvent à consoles (maisons, plus grand pour l'église) ou **store rayé rouge et crème** (commerces), centré sur la porte peinte. Pour que les deux coïncident, le shader de façade choisit désormais la travée de porte par arithmétique **entière** à partir de l'octet de graine (`(graine × 37 + 11) mod nombre de travées`), reproduite à l'identique dans `BuildingDetails.door_cell`. L'ancienne formule (sinus flottant) ne pouvait pas être reproduite côté CPU de façon fiable.
- **Église** : contreforts le long des murs longs.
- Les détails sont émis dans des surfaces à part (préfixe « ~ ») : **exclus des collisions**. Mesuré : avec les détails dans les collisions, Gégé restait bloqué 148 s (`companion_flow`) ; sans, le test passe. Leur contour (coque) est conservé.
- Coût mesuré : 50 k → 281 k triangles pour le bâti et ses contours, 1,2 → 1,9 s de génération. Dans le budget (≤ 1,5 M).

## Décisions — personnages (`CharacterModel`)

- Visage : yeux (blanc et pupille), sourcils, bouche, oreilles ; cheveux (court, chignon, long, chauve), moustache, barbe, lunettes.
- Vêtements : col, boutons, poches, ceinture à boucle, gilet (coque autour du torse, ouverte devant), tablier à bavette, foulard ; manchettes, pouces, semelles.
- Couvre-chefs : béret (défaut), casquette (visière devant ou derrière), casque audio, foulard noué, chapeau de paille, képi.
- Un `style` par personnage (dictionnaire facultatif de `CharacterModel.make`) : Gégé (cheveux gris, moustache, gilet brun), Ginette (chignon, lunettes, tablier), Kévin Radio (casque audio, lunettes), Kévin (casquette à l'envers, barbiche), le gendarme (képi, moustache), le fermier (chapeau de paille, barbe, gilet). Les joueurs humains reçoivent un style stable selon leur identifiant (`Player.default_style`).
- Matériaux partagés par couleur ; pas de contour sur les petits détails (il les noierait).
- L'animation (marche, course, saut, portage) est inchangée : la hiérarchie `Bassin / Tronc / Tete` est conservée.

## Conséquences

- Manquent : mains à doigts, vêtements animés, modèles différents selon le sexe ou la corpulence, textures peintes sur les vêtements, fenêtres en relief sur toutes les façades, volets 3D, toitures détaillées (tuiles), fumée de cheminée.
- Le soubassement et la corniche épousent le contour des murs mais pas les angles rentrants.
- Tests : `run_gdscript_tests.gd` (spots, cohérence porte/travée, comptes de triangles, collisions sans détails, personnages et styles), captures `capture_batiments.gd` et `capture_galerie_personnages.gd`.
