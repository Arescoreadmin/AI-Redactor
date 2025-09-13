# scripts/smoke.sh
#!/usr/bin/env bash
set -euo pipefail

TIMEOUT="${TIMEOUT:-60}"   # seconds
SLEEP="${SLEEP:-1}"

# wait for API
until curl -s http://localhost:8080/healthz | grep -q '"status":"ok"'; do
  printf .
  sleep 1
done
echo

# create job
jid=$(
  curl -sfS -X POST http://localhost:8080/v1/jobs \
    -H 'content-type: application/json' \
    -d '{"type":"doc","org_id":"00000000-0000-0000-0000-000000000001"}' \
  | python - <<'PY'
import sys,json; print(json.load(sys.stdin)['id'])
PY
)
echo "jid=$jid"

# approve
curl -sfS -X POST "http://localhost:8080/v1/review/$jid/approve" >/dev/null

# poll until completed (or timeout)
start=$(date +%s)
while :; do
  body=$(curl -sfS "http://localhost:8080/v1/jobs/$jid")
  status=$(printf '%s' "$body" | python - <<'PY'
import sys,json; print(json.load(sys.stdin)['status'])
PY
)
  echo "status=$status"
  [ "$status" = "completed" ] && { echo "$body"; break; }
  now=$(date +%s); (( now-start > TIMEOUT )) && { echo "timeout waiting for completion"; exit 1; }
  sleep "$SLEEP"
done
