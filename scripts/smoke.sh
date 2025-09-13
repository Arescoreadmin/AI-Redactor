#!/usr/bin/env bash
set -euo pipefail

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
  | python -c "import sys,json; print(json.load(sys.stdin)['id'])"
)

echo "jid=$jid"

# approve + fetch
curl -sfS -X POST "http://localhost:8080/v1/review/$jid/approve" >/dev/null
curl -sfS "http://localhost:8080/v1/jobs/$jid"
