# 0018 — Écran titre « Material » avec drone

Statut : accepté (orchestrateur).

## Décision
- L'écran titre (`game/ui/main_menu.gd`) suit les principes de **Material Design 3** : carte translucide arrondie à gauche (`Card`), boutons pilule (plein pour « Continuer », tonal pour le reste, texte pour « Quitter » et « Nouvelle partie (efface…) »), champs de texte contourés, puces d'information (`Chip`). Le thème est `ThemeUtil.make_material_theme()` ; le HUD garde son thème d'origine.
- Derrière la carte, `TitleBackdrop` (`game/ui/title_backdrop.gd`) fait voler un **drone** au-dessus du village dans un `SubViewport` indépendant (`own_world_3d`), à 17 h 20 (lumière dorée), avec fondus au noir entre les plans et une puce de légende (« Le clocher », « La gare et la mare aux oies »…).
- Les plans (`game/scripts/cinematic/drone_shots.gd`, fonctions pures testées) : clocher (orbite), rue Sainte-Foy (survol), mairie (grue), distillerie (orbite), gare et mare (survol), carrière (orbite), village (vue d'ensemble). Le drone reste à au moins 14 m du sol ; le cadrage est décalé de 20 % vers la droite pour ne pas passer derrière la carte.
- Les missions sont repliées sous « Choisir une mission » ; les textes et les règles de déblocage ne changent pas (`SOLO_MISSIONS`).
- Pas de fond 3D en headless (serveur dédié, tests) : le menu garde un aplat bleu ciel.

## Conséquences
- Le fond construit la ville une seconde fois (quelques secondes, et de la mémoire) tant que le menu est affiché ; elle est libérée au changement de scène.
- Contrôles manette/clavier inchangés ; le focus est un contour épais (accessibilité). Échelle du texte respectée (`Settings.text_scale`).
- Captures : `qa/screenshots/capture_titre.gd` (un cadre par plan ; Vulkan requis, pas de Compatibility sans GPU).
- Limites : pas de musique de titre ; le fond n'est pas désactivable dans les réglages (à ajouter si la perf des petites configs l'exige).
