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

# create job (capture raw response)
resp="$(curl -sS -X POST http://localhost:8080/v1/jobs \
  -H 'content-type: application/json' \
  -d '{"type":"doc","org_id":"00000000-0000-0000-0000-000000000001"}')"

# fail fast if the response doesn't look like JSON
if ! printf '%s' "$resp" | grep -q '^{'; then
  echo "Unexpected response creating job:"
  echo "----"
  printf '%s\n' "$resp"
  echo "----"
  exit 1
fi

# parse id without jq (portable), fall back to printing resp on failure
jid="$(printf '%s' "$resp" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
if ! printf '%s' "$jid" | grep -Eq '^[0-9a-fA-F-]{32,36}$'; then
  echo "Could not extract job id from response:"
  echo "----"
  printf '%s\n' "$resp"
  echo "----"
  exit 1
fi
echo "jid=$jid"

# approve
curl -sfS -X POST "http://localhost:8080/v1/review/$jid/approve" >/dev/null

# poll until completed (or timeout)
start=$(date +%s)
while :; do
  body="$(curl -sfS "http://localhost:8080/v1/jobs/$jid")"
  status="$(printf '%s' "$body" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
  echo "status=$status"
  [ "$status" = "completed" ] && { echo "$body"; break; }

  now=$(date +%s)
  (( now - start > TIMEOUT )) && { echo "timeout waiting for completion"; exit 1; }
  sleep "$SLEEP"
done
