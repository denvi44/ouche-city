#!/usr/bin/env bash
# Test d'intégration réseau (agent 09) : la mission 06 en ligne.
# Un serveur dédié lance la mission 6 ; deux clients se connectent SANS préciser la mission : ils doivent
# charger la même (annoncée par le serveur), voir les mêmes lieux, Dylan et le gardien, sans erreur de script.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-$((27000 + RANDOM % 1000))}"
LOG="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$LOG"' EXIT

"$GODOT" --headless --path game -- --server --mission=m06 --port="$PORT" --qa-report=1 --quit-after=10 >"$LOG/server.log" 2>&1 &
SERVER=$!
sleep 3
"$GODOT" --headless --path game -- --join=127.0.0.1:"$PORT" --name=Acheteuse --qa-report=1 --quit-after=7 >"$LOG/c1.log" 2>&1 &
sleep 1
"$GODOT" --headless --path game -- --join=127.0.0.1:"$PORT" --name=Acheteur --qa-report=1 --quit-after=6 >"$LOG/c2.log" 2>&1 &
wait $SERVER
sleep 1

fail=0
if grep -h "SCRIPT ERROR" "$LOG"/*.log >/dev/null 2>&1; then
  echo "ÉCHEC : erreur de script dans les journaux"; grep -h "SCRIPT ERROR" -A2 "$LOG"/*.log | head; fail=1
fi
grep -q "joueurs=2" "$LOG/server.log" || { echo "ÉCHEC : le serveur ne voit pas 2 joueurs"; fail=1; }
for c in c1 c2; do
  grep -q "mission m06" "$LOG/$c.log" || { echo "ÉCHEC : $c n'a pas reçu la mission 6 du serveur"; fail=1; }
  grep -q "etape=shop" "$LOG/$c.log" || { echo "ÉCHEC : $c n'est pas à l'étape « shop »"; fail=1; }
  grep -q "joueurs=2" "$LOG/$c.log" || { echo "ÉCHEC : $c ne voit pas l'autre joueur"; fail=1; }
done
if [ $fail -ne 0 ]; then
  echo "--- serveur ---"; tail -12 "$LOG/server.log"; echo "--- client 1 ---"; tail -12 "$LOG/c1.log"
  exit 1
fi
echo "OK : mission 6 en ligne : le serveur impose la mission, les clients la chargent sans erreur"
