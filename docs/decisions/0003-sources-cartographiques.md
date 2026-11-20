# 0003 — Sources cartographiques : IGN BD TOPO d'abord, OSM en complément

- **Date** : 2026-11-20
- **Statut** : acceptée (orchestrateur), propriétaire : agent 01

## Contexte

Le premier ticket M0 demande la rue Sainte-Foy générée automatiquement et importée dans Godot sans retouche. Depuis l'environnement d'exécution (cloud et CI), l'API Overpass d'OpenStreetMap est injoignable : le tunnel s'établit, mais la négociation TLS est coupée côté serveur. La Géoplateforme IGN (`data.geopf.fr`) répond.

## Options

1. Attendre Overpass : bloque le jalon.
2. Extrait OSM Geofabrik (Haute-Normandie, ~200 Mo) : lourd pour la CI.
3. **IGN BD TOPO V3 (WFS) + RGE ALTI**, convertis vers le même modèle intermédiaire qu'OSM.

## Décision

Option 3, avec la règle de fusion suivante dans `gis/build.py` :

- géométries (bâti, routes, végétation, eau) : IGN si `gis/cache/ign_bdtopo.json` existe, sinon OSM ;
- hauteurs de bâtiments : IGN (mesurées), sinon `building:levels` d'OSM, sinon valeur par typologie ;
- noms de rues : champ BAN de l'IGN (« Rue Sainte Foy »), rapprochés du nom configuré par normalisation (accents, tirets, casse) ;
- relief : RGE ALTI, grille de 50 m sur l'emprise, rééchantillonnée à 25 m par tuile ; altitude de référence = la chaussée de la rue Sainte-Foy (0 m dans le jeu) ;
- POI, arbres, commerces (anonymisés) : OSM, dès que `python -m gis.fetch` aboutit.

## Conséquences

- `LICENSES/ATTRIBUTIONS.md` déclare IGN BD TOPO et RGE ALTI (Licence Ouverte Etalab 2.0, extraits datés du 2026-11-20). La mention en jeu est calculée depuis le manifeste : aujourd'hui « Source : IGN » ; « © contributeurs OpenStreetMap » s'ajoute dès qu'OSM est réellement utilisé.
- Les points de vue `parvis_eglise`, `haut_du_donjon` et `avenue_bosc_tenney` sont hors des 6 tuiles du POC ; les captures les ignorent jusqu'à l'extension de l'emprise (M1).
- Ticket ouvert pour l'agent 01 : rétablir l'extraction OSM (miroir Overpass ou extrait Geofabrik découpé) et fusionner les POI.
