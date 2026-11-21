# 06 — Art, audio, narration, cinématiques

## Art (procédural, aucun asset importé)
- Style : cel-shading (`game/shaders/toon.gdshader`) + contour par coque inversée (`PropKit`). Palette : `docs/style-guide.md`.
- `PropKit` (`game/scripts/world/prop_kit.gd`) : primitives fusionnées en un seul mesh par prop (budget : peu de draw calls). Ajouter un prop = une fonction statique `xxx(...) -> Node3D`.
- `Landmarks` (`landmarks.gd`) : édifices publics détaillés (église, mairie, école, hôpital, usine de calva). Appelé par `CityBuilder.build_landmarks` d'après `poi.facility` + `poi.rect`.
- `BuildingDetails` : volets, cheminées, enseignes ; `CharacterModel` / `GooseModel` : personnages et oie.
- Mobilier urbain / arbres : `StreetFurniture._multimesh` ; la visibilité par distance se mesure à l'origine du nœud → placer le MultiMesh au centroïde du groupe.
- Limites : props qui chevauchent parfois un voisin, arbres sans collision, surcouche rocheuse de la carrière un peu crénelée.

## Audio
Synthétisé dans le code : `synth.gd` (formes d'ondes) et `sfx.gd` (catalogue, onomatopées `ONOMA` affichées en légende). Ajouter un son : fonction dans `Synth`, entrée dans `Sfx`, test d'existence dans `run_gdscript_tests.gd`.
**Jamais écouté par un humain** : à valider sur machine réelle (volume, fatigue, mixage). Pas de musique ni radio finalisées.

## Narration
- Dialogues Yarn-lite : `narrative/dialogues/mXX_*.yarn` (nœuds, `<<if>>`, choix). Bible de personnages : `narrative/`.
- Ton : Normandie profonde, tendre, jamais méprisant ; aucun nom réel.
- Cinématiques : `narrative/cinematics/*.json` (contrat `cinematic.schema.json` v1) ; plans ancrés sur le repère local du POI (+Z devant, +X droite) ; `CinematicPlayer` joue, `CinematicDirector` déclenche, `_fix_shots` décale les caméras bloquées par un mur. Audit : `qa/integration/cinematic_audit.gd`.
