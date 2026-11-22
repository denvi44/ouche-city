# 01 — État des lieux

## Ce qui est fait (vérifié par tests automatiques sauf mention)
- **Ville** : 26 tuiles de 250 m autour de Frouch (relief IGN, 1 359 bâtiments, 327 tronçons de route), rendue en cel-shading (toon + contours « inverted hull »),
  jour/nuit, ambiance sonore. Relief sur grille de 5 m avec **routes nivelées** (dévers ≈ 0).
- **9 missions jouables** en solo (compagnons IA) et en ligne (serveur dédié autoritaire) : m01 Calva, m02 Tuning, m03 Battle de sono, m04 Méchoui, m05 Vaches,
  m06 Courses de 8 h, m07 Jus de pomme, m08 Oies en grève, m09 Siège des Bretons (bonus). Chacune a : JSON de mission, dialogues Yarn, 2-3 cinématiques, HUD, test de bout en bout, test avec
  compagnons, test en ligne, scénario de faisabilité.
- **Personnages** articulés procéduraux (humain détaillé, oie), animations pilotées par la vitesse ; **véhicules** arcade (camionnette, voiture) ; train (m08).
- **Décor détaillé** : commerces fictifs, église, mairie, 2 écoles, hôpital, distillerie, gare, voie ferrée, carrière, forêts, vergers, mobilier de rue.
- **Interface** : écran titre (Continuer / résumé de sauvegarde / Nouvelle partie), HUD (jauges, minicarte, une seule balise à la fois), pause, remappage clavier/manette,
  sous-titres, onomatopées en bulles, cinématiques désactivables.
- **Pipeline** Python reproductible (`make gis`), contrats JSON versionnés, CI GitHub Actions (Linux tests + captures, Windows, macOS ad hoc, image Docker du serveur).

## Ce qui n'est PAS vérifié (important)
- **Aucune exécution sur un vrai GPU Windows/Mac** par l'IA : les captures viennent de Vulkan logiciel (lavapipe sous xvfb). Les performances réelles (60 fps 1080p « Moyen »
  sur M1 8 Go / GTX 1060) ne sont **pas mesurées**. L'utilisateur a lancé le build macOS (non signé) une fois : le jeu démarrait et l'écran de mission 1 s'affichait.
- **Sons** : synthétisés par code, jamais écoutés par l'IA.
- **Manette** et clavier AZERTY réels : jamais testés par l'IA (seulement la logique).
- **Jeu en ligne à plus de 2 joueurs** : testé en CI avec 2 clients ; 16 joueurs jamais essayés.
- **Signature/notarisation Apple** : absente (pas de secrets) ; la CI signe « ad hoc » seulement.

## Chiffres de référence (au dernier état)
- Tests : ≈ 163 tests Python (`qa/unit`), ≈ 249 tests GDScript (`qa/unit/run_gdscript_tests.gd`), 8 × (flow + compagnons + en ligne), audits HUD / mouvements / véhicule / cinématiques /
  repères / touches / menu / faisabilité.
- Faisabilité (bots) : m01 746 s sur 1110 ; m02 437/720 ; m03 222/297 + rythme ; m04 335/570 (or) ; m05 8/8 en ≈ 402 s sur 480 ; m06 or en 236 s ; m07 médailles équilibrées ; m08 argent en 145 s.
- Arbres : ≈ 7 300 (MultiMesh par espèce et tuile, masqués au-delà de 420 m). Triangles : non mesurés (voir backlog « performance »).

## Historique des décisions
`docs/decisions/0001…0017` (une par sujet : version Godot, modèle réseau, sources cartographiques, lieux fictifs, contours, audio synthétisé, chaque mission, bâtiments et personnages,
dialogues, HUD/animation/audit, routes et mission 8, édifices/végétation/carrière). Les lire avant de changer un choix structurant.
