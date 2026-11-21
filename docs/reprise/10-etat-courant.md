# 10 — État courant et passation (à lire en premier si tu reprends au milieu)

Photographie du travail au **21 novembre 2026**. Branche `claude/blissful-meitner-cywnil` ; aucune PR ouverte ; la dernière CI verte complète est le run 55 (écran titre) ;
les runs 56 à 59 sont rouges pour des raisons connues et corrigées (voir « Historique des pannes »). Cherche le run le plus récent avec `mcp__github__actions_list` (workflow CI).

## Où j'en suis exactement
1. **Fait et poussé** : tout ce qui suit dans « Ce qui est fait ce soir-là ».
2. **Fait, à valider par `make test` complet** : bâtiments enterrés sur les pentes. Le seuil d'un bâtiment est maintenant à la hauteur du terrain devant sa **porte** (côté rue),
   avec un soubassement en pierre jusqu'au terrain en aval (`CityBuilder.build_building`) ; les décors de mission (`LIFT_PROPS` : cuisine du méchoui, scène, bûcher, pressoir, WC, stand)
   sont soulevés à la plus haute altitude de leur emprise avec un socle de terre (`_seat_on_slope`). Le supermarché a une rampe d'accès (`Supermarket._add_ramp`).
   Piège : `_tool(nom)` crée la surface au premier appel ; une surface vide décale les noms de matériaux (créer l'outil paresseusement, au moment d'émettre).
3. **À vérifier dès que tu peux** : résultat de la dernière CI ; l'artefact macOS (`frouch-city-macos`, `FrouchCity-mac.zip`/`.tar.gz`, **non signé** : `ditto -x -k`, puis
   `xattr -cr`, puis `codesign --force --deep --sign -`).

## Ce qui est fait (chronologie utile)
- Rues nivelées (grille 5 m, dévers supprimé, pentes bornées), véhicules à inclinaison bornée, une balise d'objectif à la fois (décisions 0015, 0016).
- Mission 8 « Les oies font grève » (joueur = oie, train, garde-barrière), gare, voie ferrée, mare (POI v12).
- Renommage Ouche → Frouch (Frouch City, Conches-en-Frouch, variables `FROUCH_*`, exports, Docker).
- Édifices publics détaillés (`landmarks.gd`), forêts/vergers/arbres d'alignement, carrière creusée (décision 0017).
- Écran titre **Material Design 3** + fond **drone** (7 plans, `drone_shots.gd`, `title_backdrop.gd`, décision 0018).
- **Enseignes plaquées aux murs** : `gis/fiction.py::emplacement_enseigne` donne le cap exact de la normale du mur, pose l'enseigne à 7 cm, évite les ruelles
  trop étroites (`LIBRE_MIN` 2,5 m, `definir_batiments`). Tests : `test_decor.py::test_enseignes_plaquees_aux_murs` et `test_lieux_de_mission_atteignables`.
- **Édifices publics hors de la rue** : `ajuster_edifice` + `MARGES_EDIFICE` (débordement du modèle mesuré) ; audit `qa/integration/landmarks_audit.gd`.
  Si tu changes un modèle de `landmarks.gd`, relance l'audit et ajuste `MARGES_EDIFICE`.
- **Histoire collective** (`narrative/histoire.md`) : fil rouge « le Label » (l'inspectrice Hautefeuille arrive vendredi 17 h 42) ; scènes `mNN_bridge`
  (missions 1 à 7) et `m08_epilogue` jouées par `CinematicDirector` après `done` ; contrat `cinematic.schema.json` v2 ; chapitre suivant affiché sous « Continuer ».
- **Mission 3 clarifiée** : encadré « Comment jouer », guidage vers la sono, choix de musique expliqués, `PICK_FIRST` 20 s, dialogue m03_round_02/03.
- **Anti-superposition des noms flottants** : `label_declutter.gd` (groupe `etiquettes`, priorités par méta `prio`).
- **Chute sous la carte** : `Player.void_y` est fixé par `World` d'après le relief (les vallées descendent à −48 m). Avant, un seuil fixe à −30 m renvoyait en l'air
  les personnages dans le pré des vaches. `CompanionBrain._clear_at` ne prend plus une pente douce pour un mur.
- **Compagnons guides en solo** (demande du propriétaire) : par défaut (`Settings.companions_help` faux) `CompanionBrain.think` appelle `_guide` : les compagnons suivent le joueur,
  le premier passe devant vers la balise d'objectif (`focus_markers()[0]`) et l'attend, une réplique `mNN_guide` toutes les 45 s si le joueur est loin ; **aucune action de mission**.
  Le mode « coéquipiers » (tâches faites par l'IA) reste disponible : case dans le menu pause, et les tests `*_companions.gd`/l'audit « avec compagnons » le forcent à vrai.
  Test : `qa/integration/guide_mode.gd`. Le HUD affiche `companion_line(c)` (« te montre le chemin… » ou la tâche).
- **Décors et mobilier hors des murs et de la chaussée** : `gis/fiction.py::degager_decors` déplace (≤ 32 m, plus petit déplacement) tout décor de mission dont l'emprise
  (`EMPRISE_DECOR`, mesurée par `props_audit.gd`, lignes `EXT`) mord sur un bâtiment ou une route ; `StreetFurniture.blocked` supprime les bancs, jardinières et bornes
  qui seraient dans un mur ou sur la chaussée ; une enseigne n'est plus posée pour un décor déplacé hors du mur (`build_signs`). Audit : `qa/integration/props_audit.gd`.
  Si tu ajoutes ou modifies un décor de `_add_prop`, mets à jour `EMPRISE_DECOR`.
- **Textures détaillées (esprit « dessin animé urbain », sans graffitis)** : `toon_sol.gdshader` (asphalte marqué/fissuré, dalles, herbe peinte, pavés, gravier), `toon_toit.gdshader` (rangs de tuiles/ardoises, teinte par tuile, mousse),
  briques/pierre/enduit dans `toon_facade.gdshader`, grain du bois et torchis moucheté dans `toon_colombages.gdshader`, hachures d'encre dans les mi-teintes (`toon_hachure` de `toon_bandes.gdshaderinc`). Paramètre `details` = 0 pour revenir aux aplats.
- Plan de reprise (ce dossier), décisions 0015 à 0018.

## Chiffres de contrôle
pytest 190 ; tests GDScript 256 ; audit de faisabilité : m01 746 s/1110, m02 437/720, m03 222/297, m04 331/570, m05 ≈ 368/480 (solo) 384 (compagnons), m06 234/540, m07 39–61/150, m08 145/480 ;
32 cinématiques (`cinematic_audit`) ; `make test` complet ≈ 40 min (aucune sortie tant qu'il n'est pas fini : lance-le en arrière-plan et surveille `EXIT n` à la fin du journal).

## Ce qui n'existe PAS (honnêteté)
- **Héros par mission** : fait (voir `narrative/histoire.md`). Reste à faire : en ligne, attribuer un héros distinct à chaque joueur humain (seul l'hôte incarne le héros), et mettre les répliques « Vous » au nom du héros.
- Aucune mesure de performance sur GPU réel (Mac M1, GTX 1060) ; sons jamais écoutés ; pas de notarisation Apple ; lobby/comptes (FastAPI + PostgreSQL) non faits ; piétons ambiants/trafic/police libres non faits ; filtre daltonien non appliqué au rendu.

## Pièges rencontrés (lis avant de toucher)
1. **Ne jamais éditer `game/`, lancer `make city` ou `--import` pendant que `make test` tourne** (il lit le projet en direct) ; pour comparer deux états, utilise `git worktree add --detach /tmp/wt_xxx <commit>`.
2. **Régénérer les données** = `python3 -m gis.build` (écrit `gis/out/`) puis `make city` (copie dans `game/assets/`), puis **tout retester** : le moindre déplacement d'un POI ou d'un arbre peut faire échouer un bot.
   Les bots (audit de faisabilité, compagnons) sont **chaotiques** : un changement minuscule peut faire passer 8/8 vaches à 6/8. Cherche la vraie cause (ex. la chute sous la carte, `_clear_at`) plutôt que d'élargir une tolérance.
3. Les scripts lancés avec `-s` ne compilent pas les identifiants d'autoload (`Settings`, `Net`, `Sfx`, `Progress`) : passe par `get_node("/root/X")` ou `load(...)` ; une nouvelle `class_name` demande `godot --headless --path game --import`.
4. Types GDScript : `var x := tableau[i]` exige un type explicite ; `ease`/`input` sont des noms natifs ; une lambda capture par valeur (utilise un tableau comme boîte).
5. Les tests en ligne (`*_online.sh`) attendent que le serveur écoute ; sur la CI le chargement est plus lent (forêts, carrière) : ne remets pas de `sleep 3` fixes.
6. Un lieu de mission collé à un mur ne doit jamais se trouver dans une ruelle < 0,8 m (le charbon de la mission 4 était inaccessible) : `test_lieux_de_mission_atteignables`.
7. Les captures demandent Vulkan : `xvfb-run -a -s "-screen 0 1920x1080x24" godot --rendering-driver vulkan --path game -s ../qa/screenshots/<script>.gd -- --out=/tmp/x` (voir `03`).
   Scripts : `capture_titre` (écran titre), `capture_edifices`, `capture_cinematiques` (`--only=m04_bridge`), `capture_etiquettes`, `capture_m08`, `capture_touches`, `capture_poulailler`.

## Historique des pannes de CI (pour ne pas les rechercher deux fois)
- Run 50 : test réseau à délais fixes trop courts → attente de « serveur DEDICATED » (commits e556dcc, c50ced9).
- Audit de faisabilité m05 : vache coincée contre le côté de l'enclos → `MissionM05.push_goal` (viser le devant de la porte).
- Runs 56–59 : étapes intermédiaires (données SIG changées avant `make city`, bot de la mission 4 bloqué par le charbon dans une ruelle, Kévin bloqué par la chute sous la carte).

## Test instable connu
`qa/integration/drive_online.sh` échoue de temps en temps **sur la CI seulement** (la camionnette reste à l'arrêt alors que le conducteur est bien monté ; local : toujours vert).
Cause non élucidée ; le script refait une tentative. À investiguer : entrées du pilote distant côté serveur sur machine lente.

## Prochaines étapes conseillées (dans l'ordre)
1. Terminer le correctif des props enterrés, relancer `make test`, pousser, vérifier la CI.
2. Fiche de spécification « choix du héros » (avec le propriétaire), puis implémentation réseau d'abord.
3. Mesures de performance sur machines réelles ; écoute des sons ; notarisation Apple.
4. Reste du backlog : `08-backlog.md`.
