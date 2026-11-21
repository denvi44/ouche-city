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
	rm -rf game/assets/missions && mkdir -p game/assets/missions && cp missions/*.json game/assets/missions/

test: test-py test-godot

test-py:
	$(PY) -m pytest -q qa/unit

test-godot:
	$(GODOT) --headless --path game --import >/dev/null 2>&1 || true
	$(GODOT) --headless --path game -s ../qa/unit/run_gdscript_tests.gd
	bash qa/integration/two_players.sh
	$(GODOT) --headless --fixed-fps 60 --path game -s ../qa/integration/m01_flow.gd -- --no-companions
	$(GODOT) --headless --fixed-fps 60 --path game -s ../qa/integration/companion_flow.gd -- --sec=600 --need=4
	bash qa/integration/drive_online.sh
	$(GODOT) --headless --fixed-fps 60 --path game -s ../qa/integration/m02_flow.gd -- --mission=m02 --no-companions
	$(GODOT) --headless --fixed-fps 60 --path game -s ../qa/integration/m02_companions.gd -- --mission=m02
	bash qa/integration/m02_online.sh
	$(GODOT) --headless --fixed-fps 60 --path game -s ../qa/integration/m03_flow.gd -- --mission=m03 --no-companions
	$(GODOT) --headless --fixed-fps 60 --path game -s ../qa/integration/m03_companions.gd -- --mission=m03
	bash qa/integration/m03_online.sh

## Captures 1920×1080 de la scène témoin (GPU conseillé ; sinon rendu Compatibility).
screenshots:
	bash qa/screenshots/capture.sh

server:
	docker build -f server/Dockerfile -t ouche-city-server .
