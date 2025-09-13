#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DC="docker compose --env-file $ROOT/infra/.env -f $ROOT/infra/docker-compose.yml"

API_URL="${API_URL:-http://localhost:8080}"
HEALTH_URL="${HEALTH_URL:-$API_URL/healthz}"
TIMEOUT="${TIMEOUT:-120}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
AUTO_UP="${AUTO_UP:-}"
JOB_TYPE="${JOB_TYPE:-doc}"   # CI passes this; default to doc locally

die(){ echo "ERROR: $*" >&2; exit 1; }

if [[ -n "$AUTO_UP" ]]; then
  echo "AUTO_UP=1 → bringing up containers…"
  $DC up -d
fi

# Wait for API health
echo "Waiting for API health at $HEALTH_URL …"
start=$(date +%s)
while :; do
  if curl -sfS "$HEALTH_URL" | grep -q '"status":"ok"'; then
    echo "API is healthy."
    break
  fi
  if (( $(date +%s) - start >= HEALTH_TIMEOUT )); then
    echo "Health check did not pass within ${HEALTH_TIMEOUT}s."
    echo "Raw health response:"; echo "----"
    curl -s "$HEALTH_URL" || true
    echo; echo "----"
    echo; echo "---- Diagnostics ----"
    echo "health URL: $HEALTH_URL"
    $DC ps || true
    echo "api_gateway logs (last 80):"; $DC logs --tail=80 api_gateway || true
    echo "orchestrator logs (last 80):"; $DC logs --tail=80 orchestrator || true
    echo "---------------------"
    exit 1
  fi
  printf '.'
  sleep 1
done

# Create job
echo "Creating $JOB_TYPE job…"
jid=$(
  curl -sfS -X POST "$API_URL/v1/jobs" \
    -H 'content-type: application/json' \
    -d "{\"type\":\"$JOB_TYPE\",\"org_id\":\"00000000-0000-0000-0000-000000000001\"}" \
  | python -c "import sys,json; print(json.load(sys.stdin)['id'])"
)
echo "jid=$jid"

# Approve
echo "Approving job…"
curl -sfS -X POST "$API_URL/v1/review/$jid/approve" >/dev/null

# Poll until completed
echo "Waiting for job completion (timeout=${TIMEOUT}s)…"
state="unknown"
start=$(date +%s)
while :; do
  state=$(
    curl -sfS "$API_URL/v1/jobs/$jid" \
    | python -c "import sys,json; print(json.load(sys.stdin)['status'])" 2>/dev/null || echo unknown
  )
  if command -v tput >/dev/null && tput el >/dev/null 2>&1; then
    printf "\rstatus=%s" "$state"; tput el
  else
    printf "\rstatus=%s\033[K" "$state"
  fi
  if [[ "$state" == "completed" ]]; then
    echo
    break
  fi
  if (( $(date +%s) - start >= TIMEOUT )); then
    echo
    echo "Timed out after ${TIMEOUT}s waiting for completion."
    exit 1
  fi
  sleep 1
done

# Final fetch
echo "Final job object:"
curl -sfS "$API_URL/v1/jobs/$jid"
echo
echo "✅ Smoke succeeded."
