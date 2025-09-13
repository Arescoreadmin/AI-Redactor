#!/usr/bin/env bash
# smoke.sh — create a job, approve it, and wait until it finishes.
# Works in Git Bash / macOS / Linux. jq optional.

set -Eeuo pipefail
IFS=$'\n\t'

# -------------------------
# Config (override via env)
# -------------------------
BASE_URL="${BASE_URL:-http://localhost:8080}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/healthz}"
ORG_ID="${ORG_ID:-00000000-0000-0000-0000-000000000001}"
JOB_TYPE="${JOB_TYPE:-doc}"

HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"   # seconds to wait for health
HEALTH_SLEEP="${HEALTH_SLEEP:-1}"
TIMEOUT="${TIMEOUT:-60}"                 # seconds to wait for job completion
SLEEP="${SLEEP:-1}"

# Auto-start stack if requested
if [[ "${AUTO_UP:-0}" == "1" && -x ./scripts/dc.sh ]]; then
  echo "AUTO_UP=1 → bringing up containers…"
  ./scripts/dc.sh up -d
fi


# DEBUG=1 ./scripts/smoke.sh to see commands
[[ "${DEBUG:-0}" == "1" ]] && set -x

# -------------------------
# Utils
# -------------------------
have() { command -v "$1" >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 1; }
_safe_echo() { printf '%s' "$1"; }

json_get() {
  # json_get "<json-string>" key
  local _json="$1" _key="$2"
  if have jq; then
    printf '%s' "$(_safe_echo "$_json" | jq -r --arg k "$_key" '.[$k] // empty')" 2>/dev/null || true
    return
  fi

  local PYEXE=""
  if have python3; then PYEXE=python3
  elif have python; then PYEXE=python
  fi

  if [[ -n "$PYEXE" ]]; then
    KEY="$_key" _safe_echo "$_json" | "$PYEXE" - <<'PY'
import sys, json, os
key = os.environ.get("KEY")
try:
    d = json.load(sys.stdin)
    print(d.get(key, ""))
except Exception:
    # fall through for shell fallback
    pass
PY
    return
  fi

  # very last resort (flat keys only)
  printf '%s' "$_json" | sed -n "s/.*\"$_key\":\"\([^\"]*\)\".*/\1/p"
}

diag() {
  echo
  echo "---- Diagnostics ----"
  echo "health URL: ${BASE_URL}${HEALTH_ENDPOINT}"
  if [[ -x ./scripts/dc.sh ]]; then
    ./scripts/dc.sh ps || true
    echo "api_gateway logs (last 80):"
    ./scripts/dc.sh logs -n 80 api_gateway || true
    echo "orchestrator logs (last 80):"
    ./scripts/dc.sh logs -n 80 orchestrator || true
  elif have docker; then
    docker compose ps || true
    docker compose logs --tail 80 api_gateway orchestrator || true
  fi
  echo "---------------------"
}

trap 'echo "Smoke failed at line $LINENO"; diag' ERR

curl_json() {
  # curl_json METHOD PATH [BODY]
  local _method="$1" _path="$2" _body="${3:-}"
  local _url="${BASE_URL}${_path}"
  if [[ -n "$_body" ]]; then
    curl -sS -f -X "$_method" "$_url" \
      -H 'content-type: application/json' \
      --data "$_body"
  else
    curl -sS -f -X "$_method" "$_url"
  fi
}

# -------------------------
# 1) Wait for API health
# -------------------------
echo "Waiting for API health at ${BASE_URL}${HEALTH_ENDPOINT} …"
start=$(date +%s)
while true; do
  out="$(curl -s "${BASE_URL}${HEALTH_ENDPOINT}" || true)"
  if [[ "$out" == *'"status":"ok"'* ]]; then
    echo "API is healthy."
    break
  fi
  now=$(date +%s)
  (( now - start >= HEALTH_TIMEOUT )) && {
    echo "Health check did not pass within ${HEALTH_TIMEOUT}s."
    echo "Raw health response:"; echo "----"; printf '%s\n' "$out"; echo "----"
    diag
    exit 1
  }
  printf '.'
  sleep "$HEALTH_SLEEP"
done

# -------------------------
# 2) Create job
# -------------------------
echo "Creating ${JOB_TYPE} job…"
create_body=$(curl_json POST "/v1/jobs" \
  "{\"type\":\"${JOB_TYPE}\",\"org_id\":\"${ORG_ID}\"}" || true)

[[ "$create_body" == \{* ]] || {
  echo "Unexpected response when creating job:"
  echo "----"; printf '%s\n' "$create_body"; echo "----"
  diag
  exit 1
}

jid="$(json_get "$create_body" id)"
[[ -n "$jid" && "$jid" =~ ^[0-9a-fA-F-]{32,36}$ ]] || die "Could not extract job id from response: $create_body"
echo "jid=$jid"

# -------------------------
# 3) Approve job
# -------------------------
echo "Approving job…"
curl_json POST "/v1/review/${jid}/approve" >/dev/null

# -------------------------
# 4) Poll until completed
# -------------------------
echo "Waiting for job completion (timeout=${TIMEOUT}s)…"
start=$(date +%s)
while true; do
  job_body="$(curl_json GET "/v1/jobs/${jid}")"
  status="$(json_get "$job_body" status)"
  printf 'status=%s\r' "$status"

  if [[ "$status" == "completed" ]]; then
    echo
    echo "Final job object:"
    printf '%s\n' "$job_body"
    echo "✅ Smoke succeeded."
    exit 0
  fi

  now=$(date +%s)
  (( now - start >= TIMEOUT )) && {
    echo
    echo "Timed out waiting for job to complete."
    echo "Last job object:"
    printf '%s\n' "$job_body"
    diag
    exit 1
  }

  sleep "$SLEEP"
done
