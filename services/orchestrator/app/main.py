import os, json, asyncio, uuid
from loguru import logger
import asyncpg
from nats.aio.client import Client as NATS

POSTGRES_DSN = os.getenv("POSTGRES_DSN","postgresql://postgres:postgres@postgres:5432/redactor")
NATS_URL = os.getenv("NATS_URL","nats://nats:4222")

async def run():
    pool = await asyncpg.create_pool(dsn=POSTGRES_DSN)
    nc = NATS()
    await nc.connect(servers=[NATS_URL])
    logger.info("orchestrator online")

    async def on_jobs_created(msg):
        evt = json.loads(msg.data.decode())
        job_id = evt["job_id"]
        t = evt["type"]
        logger.info(f"routing job {job_id} type={t}")
        async with pool.acquire() as conn:
            await conn.execute("UPDATE jobs SET status='running', updated_at=now() WHERE id=$1", job_id)
        subj = f"jobs.{t}.start"
        await nc.publish(subj, json.dumps(evt).encode())

    async def on_detections_proposed(msg):
        evt = json.loads(msg.data.decode())
        job_id = evt["job_id"]
        async with pool.acquire() as conn:
            await conn.execute("UPDATE jobs SET status='waiting_review', updated_at=now() WHERE id=$1", job_id)
        logger.info(f"job {job_id} waiting_review")

    async def on_packaged(msg):
        evt = json.loads(msg.data.decode())
        job_id = evt["job_id"]
        async with pool.acquire() as conn:
            await conn.execute("UPDATE jobs SET status='completed', updated_at=now() WHERE id=$1", job_id)
        logger.info(f"job {job_id} completed")

    await nc.subscribe("jobs.created", cb=on_jobs_created)
    await nc.subscribe("detections.proposed", cb=on_detections_proposed)
    await nc.subscribe("packager.completed", cb=on_packaged)

    while True:
        await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(run())
