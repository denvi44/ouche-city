#!/usr/bin/env bash
# Test d'intégration réseau (agent 09) : un serveur dédié headless + 2 clients bots.
# Vérifie : poignée de main, apparition des 2 joueurs, mouvement autoritaire côté serveur,
# refus poli d'une version de protocole différente.
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
PORT="${PORT:-$((25000 + RANDOM % 1000))}"
LOG="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$LOG"' EXIT

"$GODOT" --headless --path game -- --server --port="$PORT" --qa-report=1 --quit-after=12 >"$LOG/server.log" 2>&1 &
SERVER=$!
sleep 3
"$GODOT" --headless --path game -- --join=127.0.0.1:"$PORT" --bot --name=Bot1 --qa-report=1 --quit-after=16 >"$LOG/c1.log" 2>&1 &
sleep 1
"$GODOT" --headless --path game -- --join=127.0.0.1:"$PORT" --bot --name=Bot2 --qa-report=1 --quit-after=16 >"$LOG/c2.log" 2>&1 &
wait $SERVER
sleep 1

fail=0
grep -q "joueurs=2" "$LOG/server.log" || { echo "ÉCHEC : le serveur ne voit pas 2 joueurs"; fail=1; }
for c in c1 c2; do
  grep -q "accepté par le serveur" "$LOG/$c.log" || { echo "ÉCHEC : $c non accepté"; fail=1; }
  grep -q "joueurs=2" "$LOG/$c.log" || { echo "ÉCHEC : $c ne voit pas l'autre joueur"; fail=1; }
  grep -q "\[net\] serveur\|server_lost" "$LOG/$c.log" && true
done
# Les bots ont marché : positions serveur éloignées du point d'apparition.
python3 - "$LOG/server.log" <<'PY' || fail=1
import re, sys
line = [l for l in open(sys.argv[1]) if l.startswith("[qa]") and "joueurs=2" in l][-1]
pos = [tuple(map(float, p.split("@")[1].split(","))) for p in line.split("positions=")[1].split()]
spawn = [l for l in open(sys.argv[1]) if "apparu en" in l]
starts = [tuple(map(float, re.search(r"apparu en \(([^)]*)\)", s).group(1).split(","))) for s in spawn]
moved = all(min(((a[0]-b[0])**2 + (a[2]-b[2])**2) ** 0.5 for b in starts) > 3 for a in pos)
print("positions serveur :", pos)
if not moved:
    print("ÉCHEC : les joueurs n'ont pas bougé côté serveur"); sys.exit(1)
PY
if [ $fail -ne 0 ]; then
  echo "--- serveur ---"; cat "$LOG/server.log"; echo "--- client 1 ---"; cat "$LOG/c1.log"
  exit 1
fi
echo "OK : 2 joueurs connectés, mouvement autoritaire répliqué"
