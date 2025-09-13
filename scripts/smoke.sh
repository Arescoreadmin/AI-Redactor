#!/usr/bin/env bash
# Smoke test for AI-Redactor stack
# - Waits for API health
# - Creates a job, approves it, waits for completion
# Env knobs:
#   API_URL         (default: http://localhost:8080)
#   HEALTH_TIMEOUT  seconds to wait for health (default: 60)
#   TIMEOUT         seconds to wait for job completion (default: 90)
#   JOB_TYPE        job type: doc|audio|video (default: doc)
#   ORG_ID          org UUID (default: 00000000-0000-0000-0000-000000000001)
#   AUTO_UP         if set to 1, bring containers up automatically
#   COMPOSE_FILE    override compose file (default: infra/docker-compose.yml)
#   ENV_FILE        override env file      (default: infra/.env)

set -Eeuo pipefail

API_URL="${API_URL:-http://localhost:8080}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
TIMEOUT="${TIMEOUT:-90}"
JOB_TYPE="${JOB_TYPE:-doc}"
ORG_ID="${ORG_ID:-00000000-0000-0000-0000-000000000001}"
AUTO_UP="${AUTO_UP:-0}"
COMPOSE_FILE="${COMPOSE_FILE:-infra/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-infra/.env}"

# --- helpers ---------------------------------------------------------------

err() { printf "\n\033[31mERROR:\033[0m %s\n" "$*" >&2; }

has_cmd() { command -v "$1" >/dev/null 2>&1; }

json_get() {
  # Reads JSON from stdin and prints a top-level field value ($1)
  # Requires Python 3 (present in your setup)
  python -c "import sys,json;print(json.load(sys.stdin).get('$1',''))" 2>/dev/null
}

compose() {
  if [[ -x ./scripts/dc.sh ]]; then
    ./scripts/dc.sh "$@"
  elif has_cmd docker && has_cmd docker compose; then
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
  else
    err "docker compose not available"
    return 1
  fi
}

log_tail() {
  local svc="$1" lines="${2:-80}"
  if [[ -x ./scripts/dc.sh ]]; then
    ./scripts/dc.sh logs -n "$lines" "$svc" || true
  elif has_cmd docker && has_cmd docker compose; then
    docker compose -f "$COMPOSE_FILE" logs -n "$lines" "$svc" || true
  fi
}

diagnostics() {
  echo "---- Diagnostics ----"
  echo "health URL: $API_URL/healthz"
  if has_cmd docker && has_cmd docker compose; then
    docker compose -f "$COMPOSE_FILE" ps || true
  elif [[ -x ./scripts/dc.sh ]]; then
    ./scripts/dc.sh ps || true
  fi
  echo "api_gateway logs (last 80):"
  log_tail api_gateway 80
  echo "orchestrator logs (last 80):"
  log_tail orchestrator 80
  echo "---------------------"
}

print_status_line() {
  # Single-line status with fallback if tput isn't usable
  local s="$1"
  if has_cmd tput && tput el >/dev/null 2>&1; then
    printf "\rstatus=%s" "$s"
    tput el
  else
    printf "\rstatus=%s\033[K" "$s"
  fi
}

# --- optional auto up ------------------------------------------------------

if [[ "$AUTO_UP" == "1" ]]; then
  echo "AUTO_UP=1 → bringing up containers…"
  compose up -d
fi

# --- wait for health -------------------------------------------------------

echo "Waiting for API health at $API_URL/healthz …"
start="$(date +%s)"
while :; do
  # Expect 200 and {"status":"ok"}
  resp="$(curl -sS -w $'\n%{http_code}' "$API_URL/healthz" || true)"
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  if [[ "$code" == "200" ]] && echo "$body" | grep -q '"status":"ok"'; then
    echo "API is healthy."
    break
  fi
  now="$(date +%s)"
  (( now - start >= HEALTH_TIMEOUT )) && {
    echo "Health check did not pass within ${HEALTH_TIMEOUT}s."
    echo "Raw health response:"
    echo "----"; echo "$body"; echo "----"
    diagnostics
    exit 1
  }
  printf .
  sleep 1
done

# --- create job ------------------------------------------------------------

echo "Creating $JOB_TYPE job…"
resp="$(curl -sS -w $'\n%{http_code}' -X POST "$API_URL/v1/jobs" \
  -H 'content-type: application/json' \
  -d "{\"type\":\"$JOB_TYPE\",\"org_id\":\"$ORG_ID\"}" || true)"
code="${resp##*$'\n'}"
body="${resp%$'\n'*}"

if [[ "$code" != "200" ]]; then
  err "Job creation failed (HTTP $code). Body:"
  echo "$body"
  diagnostics
  exit 1
fi

jid="$(printf "%s" "$body" | json_get id)"
if [[ -z "$jid" ]]; then
  err "Could not extract job id from response:"
  echo "$body"
  diagnostics
  exit 1
fi

echo "jid=$jid"

# --- approve ---------------------------------------------------------------

echo "Approving job…"
curl -sfS -X POST "$API_URL/v1/review/$jid/approve" >/dev/null

# --- poll completion -------------------------------------------------------

echo "Waiting for job completion (timeout=${TIMEOUT}s)…"
start="$(date +%s)"
state="unknown"  # avoid set -u before first poll

while :; do
  resp="$(curl -sS -w $'\n%{http_code}' "$API_URL/v1/jobs/$jid" || true)"
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"

  if [[ "$code" == "200" ]]; then
    # Try to parse; if parse fails, keep previous state
    parsed="$(printf "%s" "$body" | json_get status || true)"
    [[ -n "$parsed" ]] && state="$parsed"
  else
    state="unknown"
  fi

  print_status_line "$state"

  if [[ "$state" == "completed" ]]; then
    echo
    break
  fi

  now="$(date +%s)"
  (( now - start >= TIMEOUT )) && {
    echo
    err "Timed out after ${TIMEOUT}s waiting for completion."
    echo "Last job object:"
    echo "$body"
    diagnostics
    exit 1
  }
  sleep 1
done

# --- final readout ---------------------------------------------------------

echo "Final job object:"
curl -sfS "$API_URL/v1/jobs/$jid"
echo
echo "✅ Smoke succeeded."
