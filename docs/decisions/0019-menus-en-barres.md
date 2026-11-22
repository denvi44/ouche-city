# 0019 — Menus en barres translucides (typo condensée)

**Décision** : tous les menus (titre, pause, touches) passent en barres rectangulaires : noir translucide au repos, crème au survol/focus, rouge pomme à l'appui ou activé ; titres en capitales condensées (Bebas Neue, OFL). Les panneaux du menu principal sont transparents : on garde la vue du village (drone) derrière.
**Pourquoi** : lisibilité sur n'importe quelle vue, identité plus affirmée que le style Material précédent (ADR 0018, dont le fond drone est conservé).
**Garde-fous** : on reprend uniquement la forme et la typographie d'une référence fournie, aucun logo, texte, marque ou asset d'un autre jeu. Accessibilité inchangée : la taille du texte réglable (`Settings.text_scale`), focus clavier/manette en bordure épaisse en plus de la couleur.

**Blason d'écran titre** : si `game/assets/ui/blason.png` existe (ou `user://blason.png`, qui le remplace pour essayer sans reconstruire), il est posé en transparence (40 %) entre le fond aérien et le menu, à droite. PNG à fond transparent recommandé, au moins 1000 px de haut. Absent : rien n'est affiché.
