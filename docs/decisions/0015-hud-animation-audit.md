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
