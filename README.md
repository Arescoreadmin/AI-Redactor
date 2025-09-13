cat >> README.md <<'MD'
## Quickstart (Dev)

```bash
# clone
git clone git@github.com:Arescoreadmin/AI-Redactor.git
cd AI-Redactor

# env
cp infra/.env.example infra/.env   # fill creds if needed

# up
./scripts/dc.sh up -d
until curl -s http://localhost:8080/healthz | grep -q '"status":"ok"'; do printf .; sleep 1; done; echo

# smoke test
JOB_ID=$(curl -s -X POST http://localhost:8080/v1/jobs -H 'content-type: application/json' -d '{"type":"doc","org_id":"00000000-0000-0000-0000-000000000001"}' | python -c "import sys,json; print(json.load(sys.stdin)['id'])")
curl -s -X POST http://localhost:8080/v1/review/$JOB_ID/approve > /dev/null
curl -s http://localhost:8080/v1/jobs/$JOB_ID

# down
./scripts/dc.sh down            # keep data
# ./scripts/dc.sh down -v       # wipe data
