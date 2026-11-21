# Frouch City — plan de reprise (pour une autre IA ou un autre développeur)

Ce dossier est le **point d'entrée** pour continuer le projet sans l'historique de la session qui l'a construit. Lis dans l'ordre :

| Fichier | Contenu |
| --- | --- |
| `01-etat-des-lieux.md` | Ce qui existe, ce qui est vérifié, ce qui ne l'est pas, chiffres clés |
| `02-architecture.md` | Dossiers, autoloads, patrons de code (mission, réseau, rendu), où mettre quoi |
| `03-commandes-et-tests.md` | Toutes les commandes, la pyramide de tests, pièges d'exécution (à lire avant de lancer quoi que ce soit) |
| `04-pipeline-donnees.md` | Données ouvertes → tuiles : nivelage, fiction, végétation, contrats et versions |
| `05-missions.md` | Les 8 missions : étapes, fichiers, constantes de réglage, tests, limites |
| `06-art-audio-narration.md` | PropKit, Landmarks, modèles de personnages, sons synthétisés, dialogues, cinématiques |
| `07-reseau-ia-qa-ci.md` | Réseau autoritaire, compagnons IA, audits, CI, exports Windows/macOS |
| `08-backlog.md` | **Ce qu'il reste à faire**, priorisé, avec critères d'acceptation |
| `09-recettes.md` | Pas-à-pas : ajouter une mission, un édifice, un son, un dialogue, une cinématique, un POI |

Règles du projet (rappel, détail dans `CLAUDE.md`) : tout est **fictif** (aucun nom de personne, d'enseigne ou de marque réels ; seuls les noms de rues sont réels) ;
aucun asset repris d'un autre jeu ; **serveur autoritaire** (le solo lance un serveur local, même code) ; deux OS obligatoires (Windows 10/11, macOS 12+) ;
GDScript uniquement ; chemins `res://` / `user://` ; humour « Normandie profonde » tendre, jamais méprisant.

Branche de travail de la session : `claude/blissful-meitner-cywnil` (aucune PR ouverte ; la CI tourne à chaque push). Le dépôt GitHub s'appelle encore
`denvi44/ouche-city` (le jeu s'appelle Frouch City ; le renommage du dépôt est à faire par son propriétaire).

**Avant toute modification :** `make test-py` (rapide), puis le test GDScript concerné (voir `03`). **Après :** `make test` complet (≈ 40 min) ou la CI.
Quand quelque chose échoue, lis d'abord la section « pièges » de `03-commandes-et-tests.md` : la plupart des échecs rencontrés avaient des causes récurrentes.
