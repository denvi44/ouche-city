# 0004 — Noms de lieux : tout est inventé, sauf les rues

- **Date** : 2026-11-20
- **Statut** : acceptée (orchestrateur, sur demande du commanditaire), propriétaires : agents 01 et 07

## Contexte

OpenStreetMap reste injoignable (voir 0003), donc aucun POI réel n'est disponible. Le commanditaire demande d'inventer les lieux et rappelle que les noms de bâtiments doivent être fictifs. `CLAUDE.md` impose déjà : aucun nom de personne, d'enseigne ou de marque réels.

## Décision

- `gis/fiction.py` attribue à chaque bâtiment `commerce` de la zone une enseigne **inventée**, unique, choisie de façon déterministe (hachage de l'identifiant). Les 18 catégories sont listées dans `ENSEIGNES`.
- Les lieux de mission sont rattachés aux premiers commerces de cet ordre : « Auto Bling 27 » (m02) et « Comité des fêtes » (m01).
- Les monuments reçoivent des noms fictifs : l'église devient « Église Notre-Dame-du-Bocage », la salle des fêtes « Salle des fêtes Fernand-Lepommier ».
- Même quand OSM reviendra, ses noms de commerces et de monuments ne seront **jamais** repris : ses POI ne servent qu'à savoir *où* il y a un commerce.
- **Noms de rues** : ils restent réels, conformément à la fiche de l'agent 01.
- Contrat `poi.schema.json` **v2** : ajout des champs `building` (bâtiment porteur) et `facing` (orientation de l'enseigne). Godot pose les enseignes sur la façade côté rue (`CityBuilder.build_signs`).
- Garde-fou : `qa/unit/test_contracts.py::test_noms_de_lieux_fictifs` refuse tout libellé absent du répertoire fictif.

## Conséquences

- L'agent 07 peut enrichir `ENSEIGNES` et `MONUMENTS` (ton tendre, jamais méprisant). Toute nouvelle enseigne passe par ce fichier.
- L'agent 11 vérifie qu'aucune enseigne inventée ne coïncide avec une marque déposée connue.
