import os, json, asyncio, hashlib, asyncpg
from fastapi import FastAPI, Body

POSTGRES_DSN = os.getenv("POSTGRES_DSN","postgresql://postgres:postgres@postgres:5432/redactor")

app = FastAPI(title="Audit Log (MVP)")
db_pool = None

def canonical_json(d: dict) -> bytes:
    return json.dumps(d, separators=(",", ":"), sort_keys=True, ensure_ascii=False).encode("utf-8")

@app.on_event("startup")
async def startup():
    global db_pool
    db_pool = await asyncpg.create_pool(dsn=POSTGRES_DSN)

@app.get("/healthz")
async def healthz(): return {"status":"ok"}

@app.post("/audit")
async def append_audit(payload: dict = Body(...)):
    # very minimal hash chain: prev_hash of last event
    async with db_pool.acquire() as conn:
        row = await conn.fetchrow("SELECT this_hash FROM audit_events ORDER BY id DESC LIMIT 1")
        prev_hash = row["this_hash"] if row else "0"*64
        payload_digest = hashlib.sha256(canonical_json(payload)).hexdigest()
        this_hash = hashlib.sha256((prev_hash + payload_digest).encode()).hexdigest()
        await conn.execute(
            "INSERT INTO audit_events(org_id, actor, action, object_ref, payload_digest, prev_hash, this_hash) VALUES($1,$2,$3,$4,$5,$6,$7)",
            payload.get("org_id"), payload.get("actor","api"), payload.get("action","EVENT"), payload.get("object_ref","-"),
            payload_digest, prev_hash, this_hash
        )
    return {"ok": True, "this_hash": this_hash}
