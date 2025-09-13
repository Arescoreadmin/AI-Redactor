import os, json, asyncio, uuid, logging, jwt
from fastapi import FastAPI, HTTPException
from fastapi import Body
from fastapi.responses import JSONResponse
import asyncpg
from nats.aio.client import Client as NATS

LOG = logging.getLogger("api_gateway")
logging.basicConfig(level=logging.INFO)

POSTGRES_DSN = os.getenv("POSTGRES_DSN","postgresql://postgres:postgres@postgres:5432/redactor")
NATS_URL = os.getenv("NATS_URL","nats://nats:4222")
JWT_ISSUER = os.getenv("JWT_ISSUER","ai-redactor")
JWT_AUDIENCE = os.getenv("JWT_AUDIENCE","ai-redactor")
JWT_SIGNING_KEY = os.getenv("JWT_SIGNING_KEY","dev_signing_key_change_me")

app = FastAPI(title="AI Redaction Suite API (MVP)")
nc = NATS()
db_pool = None

@app.on_event("startup")
async def startup():
    global db_pool
    db_pool = await asyncpg.create_pool(dsn=POSTGRES_DSN, min_size=1, max_size=5)
    async with db_pool.acquire() as conn:
        await conn.execute(open("/app/app/sql_init.sql","r").read())
    if not nc.is_connected:
        await nc.connect(servers=[NATS_URL])

# embed SQL at runtime to avoid a separate init container
w_sql = """
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS orgs(id UUID PRIMARY KEY, name TEXT, created_at TIMESTAMPTZ DEFAULT now());
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_type') THEN
    CREATE TYPE job_type AS ENUM ('doc','audio','video');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_status') THEN
    CREATE TYPE job_status AS ENUM ('queued','running','waiting_review','approved','packaging','completed','failed','blocked_over_cap');
  END IF;
END $$;
CREATE TABLE IF NOT EXISTS jobs(
  id UUID PRIMARY KEY,
  org_id UUID NOT NULL,
  type job_type NOT NULL,
  status job_status NOT NULL DEFAULT 'queued',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
"""
open("/app/app/sql_init.sql","w").write(w_sql)

@app.get("/healthz")
async def healthz():
    return {"status":"ok"}

@app.post("/v1/jobs")
async def create_job(payload: dict = Body(...)):
    t = payload.get("type")
    if t not in ("doc","audio","video"):
        raise HTTPException(400, "type must be doc|audio|video")
    org_id = payload.get("org_id") or "00000000-0000-0000-0000-000000000001"
    job_id = str(uuid.uuid4())
    async with db_pool.acquire() as conn:
        await conn.execute("INSERT INTO jobs(id, org_id, type, status) VALUES($1,$2,$3,$4)", job_id, org_id, t, "queued")
    evt = {
        "msg_id": str(uuid.uuid4()),
        "event": "jobs.created",
        "org_id": org_id,
        "job_id": job_id,
        "type": t,
    }
    await nc.publish("jobs.created", json.dumps(evt).encode())
    return {"id": job_id, "status":"queued", "links":{"self": f"/v1/jobs/{job_id}"}}

@app.get("/v1/jobs/{job_id}")
async def get_job(job_id: str):
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT id, type, status, created_at, updated_at FROM jobs WHERE id=$1", job_id)
        if not row:
            raise HTTPException(404, "not found")
    return dict(row)

@app.post("/v1/review/{job_id}/approve")
async def approve_job(job_id: str):
    async with db_pool.acquire() as conn:
        await conn.execute("UPDATE jobs SET status='packaging', updated_at=now() WHERE id=$1", job_id)
    await nc.publish("review.approved", json.dumps({"job_id":job_id}).encode())
    return {"job_id": job_id, "status": "packaging"}
