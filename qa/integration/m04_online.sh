#!/usr/bin/env bash
# Test d'intégration réseau (agent 09) : la mission 04 en ligne.
# Un serveur dédié lance la mission 4 ; deux clients se connectent SANS préciser la mission : ils doivent
# charger la même (annoncée par le serveur), voir les mêmes lieux, Dylan et le gardien, sans erreur de script.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-$((27000 + RANDOM % 1000))}"
LOG="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$LOG"' EXIT

"$GODOT" --headless --path game -- --server --mission=m04 --port="$PORT" --qa-report=1 --quit-after=35 >"$LOG/server.log" 2>&1 &
SERVER=$!
# Attend que le serveur écoute (le chargement du monde varie selon la machine), au plus 30 s.
for _ in $(seq 1 60); do grep -q "serveur DEDICATED" "$LOG/server.log" && break; sleep 0.5; done
sleep 3
"$GODOT" --headless --path game -- --join=127.0.0.1:"$PORT" --name=Cuistot --qa-report=1 --quit-after=32 >"$LOG/c1.log" 2>&1 &
sleep 1
"$GODOT" --headless --path game -- --join=127.0.0.1:"$PORT" --name=Serveur --qa-report=1 --quit-after=31 >"$LOG/c2.log" 2>&1 &
wait $SERVER
sleep 1

fail=0
if grep -h "SCRIPT ERROR" "$LOG"/*.log >/dev/null 2>&1; then
  echo "ÉCHEC : erreur de script dans les journaux"; grep -h "SCRIPT ERROR" -A2 "$LOG"/*.log | head; fail=1
fi
grep -q "joueurs=2" "$LOG/server.log" || { echo "ÉCHEC : le serveur ne voit pas 2 joueurs"; fail=1; }
for c in c1 c2; do
  grep -q "mission m04" "$LOG/$c.log" || { echo "ÉCHEC : $c n'a pas reçu la mission 4 du serveur"; fail=1; }
  grep -q "etape=gather" "$LOG/$c.log" || { echo "ÉCHEC : $c n'est pas à l'étape « gather »"; fail=1; }
  grep -q "joueurs=2" "$LOG/$c.log" || { echo "ÉCHEC : $c ne voit pas l'autre joueur"; fail=1; }
done
if [ $fail -ne 0 ]; then
  echo "--- serveur ---"; tail -12 "$LOG/server.log"; echo "--- client 1 ---"; tail -12 "$LOG/c1.log"
  exit 1
fi
echo "OK : mission 4 en ligne : le serveur impose la mission, les clients la chargent sans erreur"
