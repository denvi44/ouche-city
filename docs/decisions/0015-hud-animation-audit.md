# 0015 — HUD, animations réalistes, audit de cohérence et de faisabilité

Statut : accepté (orchestrateur)

## HUD
- `game/ui/hud.gd` + `hud_widgets.gd` : carte de mission (titre, objectifs, jauges), mini-carte, marqueurs
  hors écran, invite d'interaction, cadran de vitesse. Les missions déclarent `hud_gauges()` / `hud_markers()`
  dans `MissionBase` ; le HUD ne connaît aucune mission en particulier.
- Couleurs doublées d'une forme/texte (daltonisme) ; tailles pilotées par `Settings`.
- `qa/integration/hud_audit.gd` vérifie les 7 missions.

## Mouvements des personnages
- Cycle de marche/course piloté par la vitesse réelle (amplitude des membres, balancement du buste,
  inclinaison, rebond), transitions amorties ; pas d'animation de glissement.

## Audit de faisabilité (`qa/feasibility/audit.gd`)
Bots + calculs : chaque mission est jouable dans sa limite de temps. Réglages issus de l'audit :
- m05 : limite 480 s (8/8 en ≈ 402 s) ; Kévin vise la vache la plus éloignée.
- m06 : mini-jeu de pièces ralenti (0,8), zone 0,36–0,64 ; or ≈ 236 s (8 h 42).
- m07 : pression retunée ; or à 75 % ; courir/marcher ≈ argent, malin ≈ or.
- m01 : estimation corrigée (746 s sur 1110 s) ; m02 437 s/720 s ; m03 100 % victoire (σ 70 ms).

## Fiction
Contrôle des marques réelles : « Subaru » (m02) remplacé par « Sapristi GT ».

## Mouvements et collisions (audit `qa/integration/movement_audit.gd`)
Saut 0,80 m / 0,58 s (4,5 m en courant). Ajout d'une montée de marche automatique (≤ 35 cm), déterministe
(client = serveur). Murs, marches de 60 cm, obstacles de 2 m et rampes à 25° vérifiés.

## Écran titre et sauvegarde
« Continuer » (prochaine mission non terminée), résumé de sauvegarde, « Nouvelle partie » avec confirmation
(`qa/integration/menu_save_audit.gd`). Balises de mission : 80 m de haut, étiquette à taille constante.

## Fumée (mission 7)
`smoke_puff.gd` : nuage « dessin animé » (CPUParticles3D, purement visuel, déclenché côté client par les
événements répliqués). Crampe : fuite (petite si l'on serre) + bruitage `toot` ; accident : grand nuage + `toot_big`.

## Choix des touches
`input_bindings.gd` (clavier par touche physique, manette par bouton ; sticks fixes), sauvegardé dans `user://touches.cfg`,
réappliqué au démarrage. Conflit = échange des deux actions ; Cmd/Ctrl/Alt refusés (pas de raccourci système).
Écran `controls_menu.gd` accessible depuis le menu principal et la pause, aussi sensibilité souris et axe Y
(`qa/integration/controls_audit.gd`).

## Cinématiques
`narrative/cinematics/*.json` (contrat `contracts/cinematic.schema.json`) : 21 scènes (introduction + réussite pour les
7 missions, échec quand il existe), plans de caméra ancrés sur les POI (repère local du lieu), légendes, carton de titre.
Lecteur `game/scripts/cinematic/cinematic_player.gd` (bandes noires, fondus, travelling, passage avec la touche « passer le
dialogue », jeu en pause en solo) et metteur en scène `cinematic_director.gd` (intro au démarrage, fin quand l'étape passe à
done/failed). Désactivable dans la pause. Audit `qa/integration/cinematic_audit.gd` : caméra jamais dans un mur ni derrière un
bâtiment (un monde par mission), lecture complète, rétablissement de la caméra et du jeu.
