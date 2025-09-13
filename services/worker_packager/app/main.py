import os, json, asyncio, uuid, time
from loguru import logger
from nats.aio.client import Client as NATS

NATS_URL = os.getenv("NATS_URL","nats://nats:4222")

async def run():
    nc = NATS()
    await nc.connect(servers=[NATS_URL])
    logger.info("worker_packager online")

    async def on_approved(msg):
        evt = json.loads(msg.data.decode())
        job_id = evt["job_id"]
        # simulate packaging
        await asyncio.sleep(0.2)
        await nc.publish("packager.completed", json.dumps({"job_id": job_id}).encode())
        logger.info(f"packaged job {job_id}")

    await nc.subscribe("review.approved", cb=on_approved)
    while True:
        await asyncio.sleep(1)

if __name__ == "__main__":
    asyncio.run(run())
