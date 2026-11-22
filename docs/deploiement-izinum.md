# Déploiement sur git.izinum.fr + Unraid

Objectif : construire les versions Windows et macOS sans dépendre des minutes GitHub, et héberger le serveur de jeu. Rien ici n'a pu être testé depuis l'environnement de développement (le serveur est inaccessible d'ici) : à valider au premier essai.

## 1. Pousser le code
```
git remote add izinum https://git.izinum.fr/<utilisateur>/<depot>.git
git push izinum claude/blissful-meitner-cywnil:main          # ou une autre branche
git lfs push --all izinum                                     # les images (png, jpg, ogg, wav) sont dans Git LFS
```
Le serveur doit avoir **Git LFS** et **Actions** activés (réglages du dépôt → Actions).

## 2. Runner de build sur Unraid
`server/docker-compose.unraid.yml` (service `runner`) : y renseigner le jeton d'enregistrement (Gitea : Administration du site → Actions → Runners). Le runner doit tourner sur Linux x86_64 avec accès Docker.
Dépôt **privé** conseillé : un runner exécute le code des commits, donc ne pas l'ouvrir à des pull requests inconnues.

## 3. Ce que fait le workflow (`.gitea/workflows/build.yml`)
À chaque push : tests Python, tests GDScript, missions 1 à 9 de bout en bout, **export Windows**, **export macOS universel non signé**, puis artefacts `frouch-city-windows` et `frouch-city-macos` (page de l'exécution). Lancement manuel avec « Régression complète » = `make test-godot` (≈ 40 min).
Les presets d'export n'ont pas de signature Apple : on exporte depuis Linux sans problème. Sur Mac :
```
cd ~/Downloads && ditto -x -k FrouchCity-mac.zip . && xattr -cr "Frouch City.app" && codesign --force --deep --sign - "Frouch City.app" && open "Frouch City.app"
```
La signature et la notarisation Apple (secrets Apple) restent dans `.github/workflows/ci.yml` et exigent un runner macOS.

## 4. Serveur de jeu
Service `jeu` du même fichier compose : port UDP **24680**, jusqu'à 16 joueurs (même protocole et même build que les clients PC et Mac).

## Limites connues
- `actions/upload-artifact@v3` (la v4 n'existe pas sur Gitea/Forgejo).
- Le workflow GitHub (`.github/workflows/ci.yml`) est ignoré par Gitea quand `.gitea/workflows` existe.
- Les captures d'écran de la CI GitHub (rendu logiciel) ne sont pas reprises ici.
