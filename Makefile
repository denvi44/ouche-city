# Ouche City — commandes de production (agent 10).
GODOT ?= godot
PY ?= python3

.PHONY: gis gis-fetch city test test-py test-godot screenshots server

## Télécharge les données ouvertes (réseau requis) : IGN puis OSM si joignable.
gis-fetch:
	$(PY) -m gis.fetch_ign
	-$(PY) -m gis.fetch

## Génère les tuiles depuis le cache, puis les importe dans le projet Godot.
gis:
	$(PY) -m gis.build
	$(MAKE) city

## Copie les sorties du cartographe dans le projet Godot (res://assets/city), sans retouche.
city:
	rm -rf game/assets/city && mkdir -p game/assets/city
	cp -r gis/out/tiles gis/out/poi.json gis/out/road_graph.json gis/out/manifest.json game/assets/city/

test: test-py test-godot

test-py:
	$(PY) -m pytest -q qa/unit

test-godot:
	$(GODOT) --headless --path game --import >/dev/null 2>&1 || true
	$(GODOT) --headless --path game -s ../qa/unit/run_gdscript_tests.gd
	bash qa/integration/two_players.sh

## Captures 1920×1080 de la scène témoin (GPU conseillé ; sinon rendu Compatibility).
screenshots:
	bash qa/screenshots/capture.sh

server:
	docker build -f server/Dockerfile -t ouche-city-server .
